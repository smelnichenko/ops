#!/bin/bash
# wifi-trace - a kernel trace kept armed for ten's wifi adapter (MediaTek MT7921AU, driver mt7921u) and its firmware
# hang: the firmware stops answering a station-record command (STA_REC_UPDATE), the driver resets the chip
# (mt7921_mac_reset_work), its reset path warns in mt76u_stop_tx, and the access point passes no traffic until hostapd
# drops the clients (2026-10-14 14:08, 5 minutes; upstream openwrt/mt76#1141, open). Run as root.
#   arm           an ftrace instance "wifi": the driver's, mac80211's (block-ack sessions among them) and xHCI's events
#                 in a ring buffer; at the reset's start (kprobe on $FN) the buffer is copied to the snapshot once (the
#                 lead-up, kept even if the reset hangs); when the reset returns (kretprobe) the live trace stops once
#   status        armed or fired, the probes' hits, how many seconds the live buffer spans
#   dump DIR      the snapshot, the live trace and two hours of kernel log into DIR (the buffers stay)
#   autodump DIR  the timer's (setup-wifi-trace.yml): armed if it is not (after a boot, once the driver is loaded);
#                 once a reset fired and returned - or a minute after it started, a hung reset - dumped into DIR, then
#                 armed again for the next one
#   disarm        the instance and the probes removed
# FN and EVENTS override the probed function and the events; TRACEFS and KALLSYMS the kernel's files (the unit test).
set -euo pipefail
T=${TRACEFS:-/sys/kernel/tracing}
I=$T/instances/wifi
SYMS=${KALLSYMS:-/proc/kallsyms}
FN=${FN:-mt7921_mac_reset_work}
EVENTS=${EVENTS:-"mt76 mt76_usb mac80211/api_restart_hw mac80211/api_connection_loss mac80211/drv_start mac80211/drv_stop
 mac80211/drv_sta_state mac80211/drv_flush mac80211/drv_set_key mac80211/drv_reconfig_complete mac80211/drv_ampdu_action
 mac80211/api_start_tx_ba_session mac80211/api_stop_tx_ba_session mac80211/api_start_tx_ba_cb mac80211/api_stop_tx_ba_cb
 xhci-hcd/xhci_urb_enqueue xhci-hcd/xhci_urb_giveback xhci-hcd/xhci_urb_dequeue xhci-hcd/xhci_handle_transfer
 xhci-hcd/xhci_handle_cmd_stop_ep xhci-hcd/xhci_handle_cmd_reset_ep xhci-hcd/xhci_dbg_cancel_urb"}
KB=${KB:-16384}

hits() {  # hits reset_start|reset_end: the probe's hits since it was made (0 when there is none)
  awk -v p="$1" '$1 == p {print $2; found = 1} END {if (!found) print 0}' "$T/kprobe_profile" 2> /dev/null || echo 0
}

arm() {
  [ ! -d "$I" ] || { echo "already armed ($I exists) - disarm first"; return 1; }
  grep -qw "$FN" "$SYMS" || { echo "no $FN in the kernel (its module not loaded?)"; return 1; }
  mkdir "$I"
  echo 0 > "$I/tracing_on"
  echo "$KB" > "$I/buffer_size_kb"
  echo "p:wifi/reset_start $FN" >> "$T/kprobe_events"
  echo "r:wifi/reset_end $FN" >> "$T/kprobe_events"
  for e in $EVENTS; do
    [ -e "$I/events/$e/enable" ] || { echo "no event $e"; disarm > /dev/null; return 1; }
    echo 1 > "$I/events/$e/enable"
  done
  echo 'snapshot:1' > "$I/events/wifi/reset_start/trigger"
  echo 'traceoff:1' > "$I/events/wifi/reset_end/trigger"
  echo 1 > "$I/events/wifi/enable"
  echo 1 > "$I/tracing_on"
  echo "armed: $FN probed, $(wc -w <<< "$EVENTS") event groups/events, $(cat "$I/buffer_size_kb") KB a CPU"
}

status() {
  [ -d "$I" ] || { echo "not armed"; return 0; }
  echo "tracing_on=$(cat "$I/tracing_on") (0 = fired: the reset returned)"
  echo "reset_start hits=$(hits reset_start) reset_end hits=$(hits reset_end)"
  first=$(grep -m1 -vE '^#' "$I/trace" | grep -oE '[0-9]+\.[0-9]{6}:' | head -1 | tr -d :) || true
  last=$(tail -1 "$I/trace" | grep -oE '[0-9]+\.[0-9]{6}:' | head -1 | tr -d :) || true
  if [ -n "$first" ] && [ -n "$last" ]; then
    echo "live buffer spans $(awk -v a="$first" -v b="$last" 'BEGIN{printf "%.1f", b-a}') s"
  else
    echo "live buffer: no events yet"
  fi
  echo "snapshot lines: $(grep -cvE '^#' "$I/snapshot" || true)"
}

dump() {
  d=$1
  mkdir -p "$d"
  ts=$(date +%Y%m%dT%H%M%S)
  cp "$I/snapshot" "$d/wifi-snapshot-$ts.txt"
  cp "$I/trace" "$d/wifi-trace-$ts.txt"
  journalctl -k --since "-2h" --no-pager > "$d/wifi-kernel-$ts.txt" 2>&1 || true
  echo "dumped: $d/wifi-{snapshot,trace,kernel}-$ts.txt"
}

disarm() {
  if [ -d "$I" ]; then
    echo 0 > "$I/tracing_on"
    echo '!snapshot:0' > "$I/events/wifi/reset_start/trigger" 2> /dev/null || true
    echo '!traceoff:0' > "$I/events/wifi/reset_end/trigger" 2> /dev/null || true
    echo 0 > "$I/events/enable"
    rmdir "$I"
  fi
  if grep -q "wifi/reset_" "$T/kprobe_events"; then
    echo "-:wifi/reset_start" >> "$T/kprobe_events"
    echo "-:wifi/reset_end" >> "$T/kprobe_events"
  fi
  echo "disarmed"
}

autodump() {
  d=$1
  pending=$d/.reset-started
  if [ ! -d "$I" ]; then
    # after a boot the driver may load after the first run: nothing to probe yet is no failure
    grep -qw "$FN" "$SYMS" || { echo "no $FN yet - not armed"; return 0; }
    arm
    return
  fi
  [ "$(hits reset_start)" -gt 0 ] || return 0
  # the reset returned (the live trace stopped), or it started a run ago and still has not: a hung reset is dumped too
  if [ "$(cat "$I/tracing_on")" = 1 ] && [ ! -e "$pending" ]; then
    mkdir -p "$d"
    : > "$pending"
    echo "a reset started - dumped once it returns, or at the next run"
    return 0
  fi
  dump "$d"
  rm -f "$pending"
  disarm
  arm
}

case "${1:-}" in
  arm) arm ;;
  status) status ;;
  dump) dump "${2:?dump DIR}" ;;
  autodump) autodump "${2:?autodump DIR}" ;;
  disarm) disarm ;;
  *) echo "usage: $0 arm|status|dump DIR|autodump DIR|disarm"; exit 2 ;;
esac
