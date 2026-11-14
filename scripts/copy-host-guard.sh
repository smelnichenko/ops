#!/usr/bin/env bash
# copy-host-guard.sh - the workstation the Vagrant VMs run on runs the radar station too: the VMs never starve it.
# The copy's VMs held 20 of the host's 30 GB, another session's build ran beside them, the host swapped 14 GB, the
# radar's SDR reader got no samples and the radar died (2026-11-13 22:17). Two guards, for every Vagrant VM here:
#   vagrant <args>  the Vagrantfile passes every vagrant command's arguments here (and holds one start at a time);
#                   `up`, `reload` and `resume` start only when the host has, available, the memory of the VMs they
#                   start (the Vagrantfile's v.memory) plus the part of the running VMs' memory they have not touched
#                   yet (promised, still counted as available) plus a reserve for the radar station and the desktop -
#                   refused, the numbers named, otherwise. Then the watcher (below). Any other command: nothing.
#   watch           a detached watcher, one at a time (it holds .copy/host-guard.alive for its life): while a VM runs,
#                   the host short of memory on two polls running - available under the trip level, or every task
#                   stalled on memory (PSI "full") over its level - powers the biggest running VM off (virsh destroy),
#                   said, the station keeps the host. Recorded in .copy/host-guard.log (its start and end too), the last
#                   trip in .copy/host-guard-tripped (printed by the next `vagrant up`). It ends after a whole grace with
#                   no VM running - unless a caller relied on it meanwhile (a `watch` registers under the callers' lock,
#                   and the watcher decides to end under the same lock: a `vagrant up` right after a `destroy` is never
#                   left to a watcher about to go). Started with no environment but its own settings: production's
#                   .env (the Taskfile loads it into every task) never lives in it.
#
# Usage: scripts/copy-host-guard.sh vagrant <vagrant's arguments> | watch | running
# Env:   COPY_HOST_RESERVE_MB (2560), COPY_HOST_TRIP_MB (2048), COPY_HOST_PSI_FULL (25: % of 10 s), COPY_HOST_POLL (5 s),
#        COPY_HOST_GRACE (1800 s); tests: COPY_VAGRANTFILE, COPY_HOST_MEMINFO, COPY_HOST_PSI, COPY_HOST_UPTIME,
#        COPY_HOST_DIR, COPY_HOST_VIRSH (a stub's path: a test's watcher whose stub is gone never reaches libvirt)
set -euo pipefail
export LC_ALL=C  # the settings' checks in ASCII ranges
ops=$(cd "$(dirname "$0")/.." && pwd)
vagrantfile=${COPY_VAGRANTFILE:-$ops/Vagrantfile}
meminfo=${COPY_HOST_MEMINFO:-/proc/meminfo}
psi=${COPY_HOST_PSI:-/proc/pressure/memory}
uptime=${COPY_HOST_UPTIME:-/proc/uptime}
dir=${COPY_HOST_DIR:-$ops/.copy}
# the start's reserve: with every VM resident the host keeps ~this much, above the watcher's trip (2048): the green
# builds of 2026-11-14 ran at ~4 GB available fully resident; 3 GB of reserve refused every start once the desktop and
# the radar held ~4.5 GB (25.4-25.6 of 25.6 GB needed, 08:27-09:00)
reserve_mb=${COPY_HOST_RESERVE_MB:-2560}
trip_mb=${COPY_HOST_TRIP_MB:-2048}
psi_full=${COPY_HOST_PSI_FULL:-25}
poll=${COPY_HOST_POLL:-5}
grace=${COPY_HOST_GRACE:-1800}
# a setting that is no number fails closed: compared as one it would read as false - a guard that never trips
for v in reserve_mb trip_mb psi_full grace; do
  [[ ${!v} =~ ^[0-9]+$ ]] || { echo "REFUSED: copy-host-guard's $v is '${!v}' - a whole number"; exit 2; }
done
[[ $poll =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "REFUSED: copy-host-guard's poll is '$poll' - seconds"; exit 2; }
# vagrant-libvirt names a machine's domain <the Vagrantfile's directory>_<machine>
prefix="$(basename "$(dirname "$vagrantfile")")_"
virsh_bin=${COPY_HOST_VIRSH:-virsh}
virsh_() { timeout 30 "$virsh_bin" -c qemu:///system "$@"; }  # a hung libvirt never stalls the guard

machines() {  # "<machine> <MB>" for each VM the Vagrantfile defines: its define's name, the v.memory inside it
  awk '/^[[:space:]]*#/ { next }
       match($0, /config\.vm\.define "[^"]+"/) { split(substr($0, RSTART, RLENGTH), q, "\""); m = q[2] }
       m != "" && match($0, /v\.memory = [0-9]+/) { split(substr($0, RSTART, RLENGTH), w, " = "); print m, w[2]; m = "" }' \
    "$vagrantfile"
}
defines() { grep -cE '^[^#]*config\.vm\.define "' "$vagrantfile" || true; }
running() {  # the machines whose domain is active (running or paused: both hold their memory), one a line; fails
  # when libvirt cannot be asked (bash clears -e in a command substitution: said here, not read as "none runs")
  local active m _
  active=$(virsh_ list --name) || return 1
  while read -r m _; do
    if grep -qxF "$prefix$m" <<< "$active"; then echo "$m"; fi
  done < <(machines)
}
rss_mb() {  # the memory a running domain's guest has touched (its qemu's resident set), 0 when not known
  virsh_ dommemstat "$prefix$1" 2> /dev/null | awk '$1 == "rss" {print int($2 / 1024); f = 1} END {if (!f) print 0}'
}
available_mb() { awk '$1 == "MemAvailable:" { print int($2 / 1024) }' "$meminfo"; }
psi_full_avg10() {  # % of the last 10 s every non-idle task stalled on memory; 0 where the kernel has no PSI
  if [ -r "$psi" ]; then awk '$1 == "full" { split($2, a, "="); print int(a[2]); f = 1 } END { if (!f) print 0 }' "$psi"
  else echo 0; fi
}
now_s() { local u _; read -r u _ < "$uptime"; echo "${u%.*}"; }  # seconds since boot: steps with no clock change
log() { echo "$(date '+%F %T') $*" >> "$dir/host-guard.log"; }

case "${1:-}" in
  vagrant)
    shift
    while [[ ${1:-} == -* ]]; do shift; done  # vagrant's own options before the command (--debug, --no-tty)
    case "${1:-}" in up | reload | resume) ;; *) exit 0 ;; esac
    command=$1
    shift
    mkdir -p "$dir"
    if mv "$dir/host-guard-tripped" "$dir/host-guard-tripped.$$" 2> /dev/null; then  # claimed: printed once
      echo "the host guard's last trip: $(cat "$dir/host-guard-tripped.$$")"
      rm -f "$dir/host-guard-tripped.$$"
    fi
    all=$(machines)
    if [ -z "$all" ] || [ "$(wc -l <<< "$all")" -ne "$(defines)" ]; then
      echo "REFUSED vagrant $command: a VM of $vagrantfile without a v.memory - the host guard cannot size it"
      exit 1
    fi
    # the machines named (none: all of them); an option's value is no machine (--provider libvirt); a name that is none
    # of them (a regex): all of them
    named=() skip=no
    for a in "$@"; do
      if [ "$skip" = yes ]; then skip=no; continue; fi
      case "$a" in --provider | --provision-with) skip=yes ;; -*) ;; *) named+=("$a") ;; esac
    done
    for a in "${named[@]}"; do
      awk -v n="$a" '$1 == n { f = 1 } END { exit !f }' <<< "$all" || { named=(); break; }
    done
    up=$(running) || { echo "REFUSED vagrant $command: libvirt's domains could not be listed (virsh) - the host guard cannot tell what runs"; exit 1; }
    need=0 starting="" promised=0
    while read -r m mb; do
      if grep -qxF "$m" <<< "$up"; then
        rest=$((mb - $(rss_mb "$m")))
        [ "$rest" -le 0 ] || promised=$((promised + rest))
        continue
      fi
      if [ "${#named[@]}" -gt 0 ] && ! printf '%s\n' "${named[@]}" | grep -qxF "$m"; then continue; fi
      need=$((need + mb))
      starting+="$m ${mb} MB, "
    done <<< "$all"
    have=$(available_mb)
    if [ "$have" -lt $((need + promised + reserve_mb)) ]; then
      echo "REFUSED vagrant $command: the host has ${have} MB available; the VMs it starts (${starting%, }) need ${need} MB," \
        "the running VMs may still take ${promised} MB, and ${reserve_mb} MB stay for the radar station and the desktop" \
        "- free memory first (another session's build, a browser), or wait"
      exit 1
    fi
    echo "host memory: ${have} MB available, ${need} MB for the VMs vagrant $command starts (${starting%, }) + ${promised} MB the running ones may still take + ${reserve_mb} MB kept"
    exec "$0" watch
    ;;
  watch)
    mkdir -p "$dir"
    exec 8> "$dir/host-guard.lock"
    flock 8
    now_s > "$dir/host-guard.wanted"  # a caller relies on a watcher from now - read by one deciding to end
    if ! flock -n "$dir/host-guard.alive" true; then
      echo "the host guard watches already (pid $(cat "$dir/host-guard.pid" 2> /dev/null || echo '?'))"
      exit 0
    fi
    # its own session, nothing of the caller's held (the lock's fd closed in it), no environment but its settings: no
    # run's Ctrl-C or end stops it (VMs outlive runs), and production's secrets do not live in it for days
    env -i PATH="$PATH" HOME="$HOME" COPY_VAGRANTFILE="$vagrantfile" COPY_HOST_MEMINFO="$meminfo" COPY_HOST_PSI="$psi" \
      COPY_HOST_UPTIME="$uptime" COPY_HOST_DIR="$dir" COPY_HOST_RESERVE_MB="$reserve_mb" COPY_HOST_TRIP_MB="$trip_mb" \
      COPY_HOST_PSI_FULL="$psi_full" COPY_HOST_POLL="$poll" COPY_HOST_GRACE="$grace" COPY_HOST_VIRSH="$virsh_bin" \
      setsid "$0" _loop 8>&- > /dev/null 2>> "$dir/host-guard.log" < /dev/null &
    child=$!
    # the lock held until the watcher holds its own: no second caller starts another meanwhile
    for _ in $(seq 100); do
      flock -n "$dir/host-guard.alive" true || { echo "the host guard watches (pid $child): the biggest running VM powered off under ${trip_mb} MB available or over ${psi_full}% memory stall, two polls ${poll} s apart"; exit 0; }
      kill -0 "$child" 2> /dev/null || break
      sleep 0.05
    done
    echo "REFUSED: the host guard's watcher did not start (pid $child) - $dir/host-guard.log"
    exit 1
    ;;
  _loop)
    set +e  # a watcher never dies on a failed command: each one checked where it matters
    exec 7> "$dir/host-guard.alive"
    flock -n 7 || exit 0  # another watcher holds it
    echo $$ > "$dir/host-guard.pid"
    log "watcher $$ started: trip under ${trip_mb} MB available or over ${psi_full}% memory stall, two polls ${poll} s apart"
    trap 'log "watcher $$ ended"' EXIT
    quiet=$(now_s) low=0 virsh_down=no
    while :; do
      if ! up=$(running); then
        [ "$virsh_down" = yes ] || log "libvirt's domains could not be listed (virsh) - still watching"
        virsh_down=yes
        sleep "$poll"
        continue
      fi
      virsh_down=no
      if [ -n "$up" ]; then quiet=$(now_s); fi
      if [ -z "$up" ] && [ $(($(now_s) - quiet)) -ge "$grace" ]; then
        # a whole grace with no VM: end - decided under the callers' lock, unless one relied on the watcher since
        exec 9> "$dir/host-guard.lock"
        flock 9
        wanted=$(cat "$dir/host-guard.wanted" 2> /dev/null)
        # a caller after it went quiet (the one that started it registered before: not counted)
        if [[ $wanted =~ ^[0-9]+$ ]] && [ "$wanted" -gt "$quiet" ]; then
          quiet=$(now_s)
          exec 9>&-
        else
          exit 0  # the lock held to the end: a caller after this one sees no watcher and starts its own
        fi
      fi
      have=$(available_mb) stall=$(psi_full_avg10)
      if [ -n "$up" ] && [[ $have =~ ^[0-9]+$ ]] && { [ "$have" -lt "$trip_mb" ] || [ "${stall:-0}" -ge "$psi_full" ]; }; then
        low=$((low + 1))
      else
        low=0
      fi
      if [ "$low" -ge 2 ]; then
        biggest=$(machines | grep -wFf <(echo "$up") | sort -k2,2nr | head -1 | cut -d' ' -f1)
        why="the host had ${have} MB available and ${stall}% memory stall on two polls ${poll} s apart (trip: under ${trip_mb} MB or over ${psi_full}%)"
        # the power-off first, its record after: a log that cannot be written never stops it
        if virsh_ destroy "$prefix$biggest" > /dev/null 2>&1; then
          msg="$why: $prefix$biggest powered off (virsh destroy), the radar station and the desktop kept their memory"
        else
          msg="$why: $prefix$biggest NOT powered off - virsh destroy failed (rc $?)"
        fi
        log "$msg"
        echo "$(date '+%F %T') $msg" > "$dir/host-guard-tripped.new" && mv "$dir/host-guard-tripped.new" "$dir/host-guard-tripped"
        low=0
      fi
      sleep "$poll"
    done
    ;;
  running) running ;;
  *) echo "usage: $0 vagrant <vagrant's arguments> | watch | running"; exit 2 ;;
esac
