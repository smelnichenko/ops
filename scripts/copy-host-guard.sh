#!/usr/bin/env bash
# copy-host-guard.sh - the workstation the Vagrant VMs run on runs the radar station too: the VMs never starve it.
# The copy's VMs held 20 of the host's 30 GB, another session's build ran beside them, the host swapped 14 GB, the
# radar's SDR reader got no samples and the radar died (2026-11-13 22:17). Two guards, for every Vagrant VM here:
#   vagrant <args>  the Vagrantfile passes every vagrant command's arguments here; `up`, `reload` and `resume` start
#                   only when the host has the memory of the VMs they start (the Vagrantfile's v.memory, those not
#                   running already) available, plus a reserve for the radar station and the desktop - refused, the
#                   numbers named, otherwise. Then the watcher (below). Any other command: nothing.
#   watch           a detached watcher, one at a time: while a VM runs, the host's available memory under the trip
#                   level on two polls running powers the biggest running VM off (virsh destroy) - the run on it fails,
#                   the station keeps the host. Recorded in .copy/host-guard.log, the last in .copy/host-guard-tripped
#                   (printed by the next `vagrant up`). It ends once its VMs have stopped, or when none started within
#                   the grace (vagrant up's box import and first boot come before a VM runs).
#
# Usage: scripts/copy-host-guard.sh vagrant <vagrant's arguments> | watch | running
# Env:   COPY_HOST_RESERVE_GB (3), COPY_HOST_TRIP_MB (2048), COPY_HOST_POLL (5 s), COPY_HOST_GRACE (1800 s),
#        COPY_VAGRANTFILE (the repo's), COPY_HOST_MEMINFO (/proc/meminfo), COPY_HOST_DIR (.copy) - the last three: tests
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
vagrantfile=${COPY_VAGRANTFILE:-$ops/Vagrantfile}
meminfo=${COPY_HOST_MEMINFO:-/proc/meminfo}
dir=${COPY_HOST_DIR:-$ops/.copy}
reserve_mb=$(( ${COPY_HOST_RESERVE_GB:-3} * 1024 ))
trip_mb=${COPY_HOST_TRIP_MB:-2048}
poll=${COPY_HOST_POLL:-5}
grace=${COPY_HOST_GRACE:-1800}
# vagrant-libvirt names a machine's domain <the Vagrantfile's directory>_<machine>
prefix="$(basename "$(dirname "$vagrantfile")")_"

machines() {  # "<machine> <MB>" for each VM the Vagrantfile defines: its define's name, the v.memory inside it
  awk '/^[[:space:]]*#/ { next }
       match($0, /config\.vm\.define "[^"]+"/) { split(substr($0, RSTART, RLENGTH), q, "\""); m = q[2] }
       m != "" && match($0, /v\.memory = [0-9]+/) { split(substr($0, RSTART, RLENGTH), w, " = "); print m, w[2]; m = "" }' \
    "$vagrantfile"
}
running() {  # the machines whose domain is active (running or paused: both hold their memory), one a line; fails
  # when libvirt cannot be asked (bash clears -e in a command substitution: said here, not read as "none runs")
  local active m _
  active=$(virsh -c qemu:///system list --name) || return 1
  while read -r m _; do
    if grep -qxF "$prefix$m" <<< "$active"; then echo "$m"; fi
  done < <(machines)
}
available_mb() { awk '$1 == "MemAvailable:" { print int($2 / 1024) }' "$meminfo"; }

case "${1:-}" in
  vagrant)
    shift
    while [[ ${1:-} == -* ]]; do shift; done  # vagrant's own options before the command (--debug, --no-tty)
    case "${1:-}" in up | reload | resume) ;; *) exit 0 ;; esac
    command=$1
    shift
    mkdir -p "$dir"
    if [ -f "$dir/host-guard-tripped" ]; then
      echo "the host guard's last trip: $(cat "$dir/host-guard-tripped")"
      rm -f "$dir/host-guard-tripped"
    fi
    all=$(machines)
    [ -n "$all" ] || { echo "REFUSED: no VM with a v.memory found in $vagrantfile - the host guard cannot size it"; exit 1; }
    # the machines named (none: all of them); a name that is none of them (a regex, an option's value): all of them
    named=()
    for a in "$@"; do [[ $a == -* ]] || named+=("$a"); done
    for a in "${named[@]}"; do
      awk -v n="$a" '$1 == n { f = 1 } END { exit !f }' <<< "$all" || { named=(); break; }
    done
    up=$(running) || { echo "REFUSED vagrant $command: libvirt's domains could not be listed (virsh) - the host guard cannot tell what runs"; exit 1; }
    need=0 starting=""
    while read -r m mb; do
      if [ "${#named[@]}" -gt 0 ] && ! printf '%s\n' "${named[@]}" | grep -qxF "$m"; then continue; fi
      if grep -qxF "$m" <<< "$up"; then continue; fi
      need=$((need + mb))
      starting+="$m ${mb} MB, "
    done <<< "$all"
    have=$(available_mb)
    if [ "$have" -lt $((need + reserve_mb)) ]; then
      echo "REFUSED vagrant $command: the host has ${have} MB available; the VMs it starts (${starting%, }) need ${need} MB" \
        "and ${reserve_mb} MB stay for the radar station and the desktop - free memory first (another session's build," \
        "a browser), or wait"
      exit 1
    fi
    echo "host memory: ${have} MB available, ${need} MB for the VMs vagrant $command starts (${starting%, }) + ${reserve_mb} MB kept"
    exec "$0" watch
    ;;
  watch)
    mkdir -p "$dir"
    exec 8> "$dir/host-guard.lock"
    flock 8
    if read -r pid < "$dir/host-guard.pid" 2> /dev/null && tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null | grep -q 'copy-host-guard.sh _loop'; then
      echo "the host guard watches already (pid $pid)"
      exit 0
    fi
    # its own session, nothing of the caller's held (the lock's fd closed in it): no run's Ctrl-C or end stops it -
    # VMs outlive runs
    setsid "$0" _loop 8>&- > /dev/null 2>> "$dir/host-guard.log" < /dev/null &
    echo $! > "$dir/host-guard.pid"
    echo "the host guard watches (pid $!): under ${trip_mb} MB available on two polls ${poll} s apart, the biggest running VM is powered off"
    ;;
  _loop)
    start=$(date +%s) seen=no gone=0 low=0
    while :; do
      if ! up=$(running); then
        echo "$(date '+%F %T') libvirt's domains could not be listed (virsh) - still watching" >> "$dir/host-guard.log"
        sleep "$poll"
        continue
      fi
      if [ -n "$up" ]; then seen=yes gone=0; else gone=$((gone + 1)); fi
      if [ -z "$up" ]; then
        if [ "$seen" = yes ] && [ "$gone" -ge 3 ]; then exit 0; fi
        if [ "$seen" = no ] && [ $(($(date +%s) - start)) -ge "$grace" ]; then exit 0; fi
      fi
      have=$(available_mb)
      if [ -n "$up" ] && [ "$have" -lt "$trip_mb" ]; then low=$((low + 1)); else low=0; fi
      if [ "$low" -ge 2 ]; then
        biggest=$(machines | grep -wFf <(echo "$up") | sort -k2,2nr | head -1 | cut -d' ' -f1)
        msg="$(date '+%F %T') the host had ${have} MB available, under ${trip_mb} MB on two polls ${poll} s apart: $prefix$biggest powered off (virsh destroy), the radar station and the desktop kept their memory"
        echo "$msg" >> "$dir/host-guard.log"
        echo "$msg" > "$dir/host-guard-tripped"
        virsh -c qemu:///system destroy "$prefix$biggest" >> "$dir/host-guard.log" 2>&1 || true
        low=0
      fi
      sleep "$poll"
    done
    ;;
  running) running ;;
  *) echo "usage: $0 vagrant <vagrant's arguments> | watch | running"; exit 2 ;;
esac
