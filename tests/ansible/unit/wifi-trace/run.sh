#!/bin/bash
# deploy/ansible/playbooks/files/wifi-trace.sh against a fake tracefs: what arm writes (the instance, its buffer, each
# event on, the snapshot and traceoff triggers, the two probes), an arm that cannot finish leaving nothing behind, and
# autodump's choices - nothing to probe yet (after a boot), not armed, nothing fired, a reset still running (dumped a
# run later), a reset returned (dumped now) - each dump followed by a fresh arm. The kernel's own behaviour (a snapshot
# of the lead-up at the reset's start, the live trace stopped when it returns) was read on a 6.12.111 kernel when the
# script was written; tracefs cannot be faked for it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
S=deploy/ansible/playbooks/files/wifi-trace.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
T=$W/tracing
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
EV="g1 g2/e2"
mkdir -p "$W/bin"
# tracefs makes an instance's event files itself; here mkdir does, and rmdir removes one with its files
cat > "$W/bin/mkdir" <<STUB
#!/bin/bash
for a in "\$@"; do
  if [ "\$a" = "$T/instances/wifi" ]; then
    /bin/mkdir -p "\$a"/events/g1 "\$a"/events/g2/e2 "\$a"/events/wifi/reset_start "\$a"/events/wifi/reset_end
    for f in tracing_on buffer_size_kb trace snapshot events/enable events/g1/enable events/g2/e2/enable \
      events/wifi/enable events/wifi/reset_start/trigger events/wifi/reset_end/trigger; do : > "\$a/\$f"; done
    exit 0
  fi
done
exec /bin/mkdir "\$@"
STUB
printf '#!/bin/bash\n[ "$1" = "%s/instances/wifi" ] && exec rm -rf "$1"\nexec /bin/rmdir "$@"\n' "$T" > "$W/bin/rmdir"
printf '#!/bin/bash\necho "kernel log"\n' > "$W/bin/journalctl"
chmod +x "$W/bin/"*
fresh() {  # a fresh fake kernel: tracefs, the probed function present or not ($1: yes|no)
  rm -rf "$T" && /bin/mkdir -p "$T/instances" && : > "$T/kprobe_events" && : > "$T/kprobe_profile"
  if [ "$1" = yes ]; then echo "ffffffff t mt7921_mac_reset_work [mt7921_common]" > "$W/syms"; else : > "$W/syms"; fi
}
run() { PATH="$W/bin:$PATH" TRACEFS="$T" KALLSYMS="$W/syms" EVENTS="$EV" KB=64 bash "$S" "$@" > "$W/out" 2>&1; echo $?; }
I=$T/instances/wifi
fired() { printf '  reset_start  %s  0\n  reset_end  %s  0\n' "$1" "$2" > "$T/kprobe_profile"; echo "$3" > "$I/tracing_on"; }

fresh yes
check "arm: ends 0" "$(run arm)" 0
check "arm: the instance on, its buffer, each event on" \
  "$(cat "$I/tracing_on") $(cat "$I/buffer_size_kb") $(cat "$I/events/g1/enable") $(cat "$I/events/g2/e2/enable") $(cat "$I/events/wifi/enable")" \
  "1 64 1 1 1"
check "arm: the lead-up kept once at the reset's start, the trace stopped once when it returns" \
  "$(cat "$I/events/wifi/reset_start/trigger") $(cat "$I/events/wifi/reset_end/trigger")" "snapshot:1 traceoff:1"
check "arm: the reset function probed at its entry and its return" "$(paste -sd';' "$T/kprobe_events")" \
  "p:wifi/reset_start mt7921_mac_reset_work;r:wifi/reset_end mt7921_mac_reset_work"
check "arm again: refused, ends 1" "$(run arm)" 1

fresh yes
EV="g1 nosuch/event"
check "arm with an event the kernel lacks: ends 1" "$(run arm)" 1
check "  nothing left behind: no instance, its probes removed" \
  "$([ -d "$I" ] && echo instance) $(tail -2 "$T/kprobe_events" | paste -sd';')" " -:wifi/reset_start;-:wifi/reset_end"
EV="g1 g2/e2"

fresh no
check "arm with no driver loaded: ends 1, nothing made" "$(run arm) $([ -d "$I" ] && echo instance)$(wc -c < "$T/kprobe_events")" "1 0"
check "autodump after a boot, the driver not loaded yet: ends 0, not armed (no failed unit)" \
  "$(run autodump "$W/d") $([ -d "$I" ] && echo armed || echo unarmed)" "0 unarmed"
fresh yes
check "autodump not armed, the driver loaded: armed" "$(run autodump "$W/d") $(cat "$I/tracing_on")" "0 1"
fired 0 0 1
check "autodump, nothing fired: nothing dumped" "$(run autodump "$W/d") $(ls "$W/d" 2> /dev/null | wc -l)" "0 0"
fired 1 0 1
echo "lead-up" > "$I/snapshot"
check "autodump, a reset started and running: no dump yet, marked" \
  "$(run autodump "$W/d") $(ls "$W/d" | wc -l) $(ls -A "$W/d")" "0 0 .reset-started"
check "autodump a run later, the reset still running (hung): dumped" \
  "$(run autodump "$W/d") $(ls "$W/d" | sed 's/-[0-9T]*\.txt//' | sort | paste -sd' ')" \
  "0 wifi-kernel wifi-snapshot wifi-trace"
check "  the snapshot's lead-up in the dump, the mark gone" \
  "$(cat "$W"/d/wifi-snapshot-*.txt) $(ls -A "$W/d" | grep -c reset-started)" "lead-up 0"
check "  armed again, fresh" "$(cat "$I/tracing_on") $(cat "$I/snapshot" | wc -c)" "1 0"
rm -rf "$W/d"
fired 1 1 0
check "autodump, a reset returned (the trace stopped): dumped at once, armed again" \
  "$(run autodump "$W/d") $(ls "$W/d" | wc -l) $(cat "$I/tracing_on")" "0 3 1"
check "status: the probes' hits read" "$(run status > /dev/null; grep -o 'reset_start hits=[0-9]*' "$W/out")" "reset_start hits=1"
check "disarm: ends 0, no instance, the probes removed" \
  "$(run disarm) $([ -d "$I" ] && echo instance) $(tail -2 "$T/kprobe_events" | paste -sd';')" \
  "0  -:wifi/reset_start;-:wifi/reset_end"
check "disarm again: ends 0" "$(run disarm)" 0
check "no mode: usage, ends 2" "$(run)" 2
echo "wifi-trace: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
