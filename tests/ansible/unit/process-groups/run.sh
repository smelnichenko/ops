#!/bin/bash
# scripts/lib/process-groups.sh on processes this test starts itself (each its own child, read so before it is
# signalled): a job that leads no group yet - a stop between its fork and its setsid - stopped by its PID at once, not
# KILLed after the grace with its traps unrun; a group read alive with no external command (the read builtin: a cat
# per process made one scan 0.6 s); a job bash reaped already never listed as this shell's (`jobs -p` lists it, its PID
# free for another process); the grace measured on the clock uptime_s reads (/proc/uptime: no wall-clock step moves
# it), not on bash's SECONDS.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
source scripts/lib/process-groups.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1))
}
mine() {  # mine <pid>: the process is this shell's child
  local st
  read -r st 2> /dev/null < "/proc/$1/stat" || return 1
  set -- ${st##*) }
  [ "$2" = "$$" ]
}
set +m
# a job in this shell's group (no job control): what a setsid job is until setsid has run - its group none yet
bash -c 'trap "kill \$!; exit 143" TERM; sleep 30 & wait' & j=$!
sleep 0.2
t0=$SECONDS
if mine "$j"; then stop_groups 5 "$j" > "$W/stop.out"; fi
wait "$j"; rc=$?
check "a job leading no group yet: TERMed by its PID, ended at once - nothing killed after the grace" \
  "$rc $((SECONDS - t0 < 3)) $(grep -c killed "$W/stop.out")" "143 1 0"
# a live group read alive with no external command at hand
set -m
sleep 30 & g=$!
set +m
alive=$(PATH=/nonexistent; group_alive "$g" && echo alive || echo none)
check "a live group read alive with no external command (the read builtin)" "$alive" alive
mine "$g" && kill -TERM -- "-$g"
wait "$g" 2> /dev/null
# a job bash reaped already: never listed as this shell's
sleep 0.1 & r=$!
wait "$r"
sleep 30 & k=$!
own_jobs got
check "own_jobs: the running job, not one reaped already" "${got[*]}" "$k"
mine "$k" && kill "$k"
wait "$k" 2> /dev/null
# the grace on uptime_s's clock: one that jumps 100 s at each read ends a 30 s grace at its second read - a TERM-
# ignoring job then killed at once, said; on bash's SECONDS it waited the 30 s out
set -m
bash -c 'trap "" TERM; sleep 30' & h=$!
set +m
sleep 0.2
t0=$SECONDS
if mine "$h"; then
  ( fake=0; uptime_s() { fake=$((fake + 100)); printf -v "$1" '%s' "$fake"; }; stop_groups 30 "$h" ) > "$W/clock.out"
fi
wait "$h" 2> /dev/null; rc=$?
check "the grace measured on uptime_s's clock: its time up, the job killed at once, said" \
  "$rc $((SECONDS - t0 < 5)) $(grep -c 'outlived the stop by 30 s - killed' "$W/clock.out")" "137 1 1"
uptime_s up
read -r real _ < /proc/uptime
check "uptime_s: whole seconds since boot" "$((up == ${real%.*} || up + 1 == ${real%.*}))" 1
echo "process-groups: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
