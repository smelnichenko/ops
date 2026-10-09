#!/bin/bash
# scripts/upgrade-build-with-pin.sh in a copy of its tree, `task` and the pin stubbed: the full run's build and, beside
# it, the ClickHouse pin - both passing pass; a failed pin fails the run when the build ends, saying so; a failed build
# fails at once and stops the pin still running (its own process group), rather than waiting for it or leaving it
# behind; a TERM to the script stops the pin too. (Inline in the Taskfile it ran in go-task's own shell: `$!` no PID,
# `kill` a no-op, errexit always on - the pin orphaned, its failure unprinted.) test:upgrade:full runs it.
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/tests/clickhouse-pin" "$T/bin" "$T/.upgrade"
mkdir -p "$T/scripts/lib"; cp "$ROOT/scripts/lib/process-groups.sh" "$T/scripts/lib/"
cp "$ROOT/scripts/upgrade-build-with-pin.sh" "$T/scripts/" 2> /dev/null \
  || { echo "FAIL scripts/upgrade-build-with-pin.sh missing"; echo "build-with-pin: 1 FAILED"; exit 1; }
# go-task (task test:upgrade:build): its PID in .upgrade/task.pid, the build's command its child (in its group), a TERM
# swallowed (go-task leaves it to the command); the command failing fails the task, ending 0 (NEXT_CMD) the task's next
# command runs - as go-task ran a step's remaining commands after one its running command survived
cat > "$T/bin/task" <<'STUB'
#!/bin/bash
echo $$ > .upgrade/task.pid
trap 'echo "task: signal received"' TERM
bash "$BUILD_COMMAND" || exit $?
[ -z "${NEXT_CMD:-}" ] || echo next > .upgrade/build.next
# LEFTOVER: a process of the build left running in its session after go-task ended (a backgrounded command)
if [ -n "${LEFTOVER:-}" ]; then sleep 30 > /dev/null 2>&1 & echo $! > .upgrade/left.pid; fi
exit 0
STUB
# the build's command: BUILD (its exit), after BUILD_SECONDS; IGNORE_TERM: it ignores a TERM (its sleep too);
# SLOW_TERM: a TERM ends it a second later, said in .upgrade/build.slow; ZERO_ON_TERM: a TERM ends it 0
cat > "$T/build-command" <<'STUB'
echo $$ > .upgrade/build.pid
[ -z "${IGNORE_TERM:-}" ] || trap '' TERM
[ -z "${SLOW_TERM:-}" ] || trap 'sleep 1; echo slow > .upgrade/build.slow; exit 143' TERM
[ -z "${ZERO_ON_TERM:-}" ] || trap 'exit 0' TERM
sleep "${BUILD_SECONDS:-0}" &
wait $!
echo build; echo > .upgrade/build.finished
exit "${BUILD:-0}"
STUB
export BUILD_COMMAND=$T/build-command
# the pin: PIN (its exit) after PIN_SECONDS, its PID first, "finished" when it ran its course
cat > "$T/tests/clickhouse-pin/run.sh" <<'STUB'
#!/bin/bash
echo $$ > .upgrade/pin.pid
sleep "${PIN_SECONDS:-0}"
echo "pin result line"; echo finished > .upgrade/pin.finished
# PIN_LEFTOVER: a docker call of the pin left running after it ended
if [ -n "${PIN_LEFTOVER:-}" ]; then sleep 30 > /dev/null 2>&1 & echo $! > .upgrade/pinleft.pid; fi
exit "${PIN:-0}"
STUB
chmod +x "$T/bin/task" "$T/tests/clickhouse-pin/run.sh"
# a process's parent, process group, session and command name, from /proc (CI's image has no ps)
proc_info() {  # proc_info <pid>: "<ppid> <pgid> <sid> <comm>" - nothing for no such process
  local stat comm
  stat=$(cat "/proc/$1/stat" 2> /dev/null) && comm=$(cat "/proc/$1/comm" 2> /dev/null) || return 0
  set -- ${stat##*) }
  echo "$2 $3 $4 $comm"
}
fails=0
run() {  # run <env...>: the script's output in $out, its exit in $rc, its seconds in $took
  rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/task.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
  local t0=$SECONDS
  # bounded: a cleanup that waited on its own output's process hung the run for good
  out=$(cd "$T" && env "$@" PATH="$T/bin:$PATH" timeout -k 5 30 bash scripts/upgrade-build-with-pin.sh < /dev/null 2>&1)
  rc=$?
  took=$((SECONDS - t0))
}
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$2', want '$3'"; sed 's/^/    /' <<< "$out"; fails=$((fails + 1))
}
pin_end() { [ -e "$T/.upgrade/pin.finished" ] && echo finished || echo stopped; }
# a log as the script left it: its time-stamper (a process substitution, no job - it outlives the script by a moment)
# writes the last lines after the script's own end; read once no process of this test's holds it open, 5 s at most
settled() {  # settled <file>
  local f=$1 fd held
  for _ in $(seq 50); do
    held=""
    for fd in /proc/[0-9]*/fd/*; do [ "$fd" -ef "$f" ] && { held=1; break; }; done 2> /dev/null
    [ -n "$held" ] || break
    sleep 0.1
  done
  cat "$f"
}
gone() {  # gone <pid file>: the process it names no more there - a moment allowed for its teardown
  local pid; pid=$(cat "$1" 2> /dev/null) || { echo "no-pid"; return; }
  for _ in $(seq 20); do [ -e "/proc/$pid" ] || { echo gone; return; }; sleep 0.1; done
  echo "running"
}

run
check "build and pin pass: passed, the pin's result line shown" \
  "$rc $(grep -c '^[0-9:]\{8\} CLICKHOUSE PIN: pin result line$' <<< "$out")" "0 1"
check "every line stamped with its time (the build's minutes measurable)" \
  "$(grep -vc '^[0-2][0-9]:[0-5][0-9]:[0-5][0-9] ' <<< "$out")" 0
run PIN=1
check "the pin failed: the run fails when the build ends, saying so" \
  "$rc $(grep -c 'THE CLICKHOUSE PIN FAILED' <<< "$out")" "1 1"
run BUILD=2 PIN_SECONDS=30
check "the build failed: its exit at once, the pin still running stopped - its process gone, not left asleep" \
  "$rc $(pin_end) $((took < 10)) $(gone "$T/.upgrade/pin.pid")" "2 stopped 1 gone"
# the script stopped as an interrupted full run stops it: it is this test's own child, checked so before the signal
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
t0=$SECONDS
(cd "$T" && exec env BUILD_SECONDS=30 PIN_SECONDS=30 PATH="$T/bin:$PATH" timeout -k 5 30 \
  bash scripts/upgrade-build-with-pin.sh \
  < /dev/null > "$T/term.out" 2>&1) &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid"
[ "$(proc_info "$sp" | awk '{print $1}')" = "$$" ] && kill -TERM "$sp"
wait "$sp"
out=$(settled "$T/term.out")
check "a TERM to the script, mid-build: it ends at once, the build and the pin stopped, the pin's process gone" \
  "$(pin_end) $([ -e "$T/.upgrade/build.finished" ] && echo finished || echo stopped) $((SECONDS - t0 < 10)) \
$(gone "$T/.upgrade/pin.pid")" "stopped stopped 1 gone"
# a Ctrl-C at the terminal: INT to every process of the foreground group - the script and its time-stamper (the build
# and the pin are in sessions of their own). The stamper ignores it: what the script says while it stops reaches the
# log, and nothing it writes then dies of a closed pipe. Each job with no terminal: one that reads it (an ssh asking
# for a host key) fails instead of stopping, and the wait with it.
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/task.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
t0=$SECONDS
(cd "$T" && exec env BUILD_SECONDS=30 PIN_SECONDS=30 PATH="$T/bin:$PATH" timeout -k 5 30 \
  bash scripts/upgrade-build-with-pin.sh \
  < /dev/null > "$T/int.out" 2>&1) &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ] && [ -s "$1" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid"
own_session() {  # own_session <pid file>: "own" when the process it names leads a session of its own
  local pid info; pid=$(cat "$1" 2> /dev/null) && info=$(proc_info "$pid") || { echo "no-process"; return; }
  [ "$(awk '{print $3}' <<< "$info")" = "$pid" ] && echo own || echo shared
}
sessions="$(own_session "$T/.upgrade/task.pid") $(own_session "$T/.upgrade/pin.pid")"
# the whole group of timeout (it leads one), as the terminal's Ctrl-C reaches it - this test's own child, checked so
[ "$(proc_info "$sp" | awk '{print $1, $2}')" = "$$ $sp" ] && kill -INT -- "-$sp"
wait "$sp"
out=$(settled "$T/int.out")
check "the build and the pin each lead a session of their own (no terminal to stop on)" "$sessions" "own own"
check "a Ctrl-C to the group: it ends at once, both stopped and gone, the stop said in the log" \
  "$(pin_end) $([ -e "$T/.upgrade/build.finished" ] && echo finished || echo stopped) $((SECONDS - t0 < 10)) \
$(gone "$T/.upgrade/pin.pid") $(gone "$T/.upgrade/build.pid") $(grep -c '^[0-9:]\{8\} STOPPED BY A SIGNAL' <<< "$out")" \
  "stopped stopped 1 gone gone 1"
# a TERM or a HUP to the whole group (a closed terminal, a kill of the group): the stamper ignores them too - the stop is
# said in the log (it died of the TERM, and the stop's line of a closed pipe)
for sig in TERM HUP; do
  rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/task.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
  (cd "$T" && exec env BUILD_SECONDS=30 PIN_SECONDS=30 PATH="$T/bin:$PATH" timeout -k 5 30 \
    bash scripts/upgrade-build-with-pin.sh < /dev/null > "$T/grp.out" 2>&1) &
  sp=$!
  timeout 10 bash -c 'until [ -s "$0" ] && [ -s "$1" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid"
  [ "$(proc_info "$sp" | awk '{print $1, $2}')" = "$$ $sp" ] && kill "-$sig" -- "-$sp"
  wait "$sp"
  out=$(settled "$T/grp.out")
  check "a $sig to the group: both stopped and gone, the stop said in the log" \
    "$(gone "$T/.upgrade/pin.pid") $(gone "$T/.upgrade/build.pid") $(grep -c '^[0-9:]\{8\} STOPPED BY A SIGNAL' <<< "$out")" \
    "gone gone 1"
done
# a job ignoring the stop's TERM: killed after the stop's grace, said - it held the stop for good
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/task.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
t0=$SECONDS
(cd "$T" && exec env BUILD_SECONDS=30 PIN_SECONDS=30 IGNORE_TERM=1 STOP_GRACE=2 PATH="$T/bin:$PATH" timeout -k 5 30 \
  bash scripts/upgrade-build-with-pin.sh < /dev/null > "$T/ign.out" 2>&1) &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ] && [ -s "$1" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid"
[ "$(proc_info "$sp" | awk '{print $1}')" = "$$" ] && kill -TERM "$sp"
wait "$sp"
out=$(settled "$T/ign.out")
check "a job ignoring TERM: killed after the grace, said so; both gone, the stop said, well before the bound" \
  "$(gone "$T/.upgrade/build.pid") $(gone "$T/.upgrade/pin.pid") $(grep -c 'outlived the stop' <<< "$out") \
$(grep -c 'STOPPED BY A SIGNAL' <<< "$out") $((SECONDS - t0 < 10))" "gone gone 1 1 1"
# a second signal while the stop waits for a job that takes its time to end - a Ctrl-C pressed twice: INT to the
# whole group, the script itself included, twice: the stop goes on to its end - the job's own stop finished, both
# gone, the stop said (unguarded, the second ran the trap again inside the stop and ended it there - measured)
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/task.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished" \
  "$T/.upgrade/build.slow"
(cd "$T" && exec env BUILD_SECONDS=30 PIN_SECONDS=30 SLOW_TERM=1 PATH="$T/bin:$PATH" timeout -k 5 30 \
  bash scripts/upgrade-build-with-pin.sh < /dev/null > "$T/twice.out" 2>&1) &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ] && [ -s "$1" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid"
if [ "$(proc_info "$sp" | awk '{print $1, $2}')" = "$$ $sp" ]; then
  kill -INT -- "-$sp"; sleep 0.3; kill -INT -- "-$sp" 2> /dev/null
fi
wait "$sp"
out=$(settled "$T/twice.out")
check "a Ctrl-C pressed twice, the second during the stop: the stop goes on - the slow job's own stop done, both gone, the stop said" \
  "$([ -e "$T/.upgrade/build.slow" ] && echo slow-done || echo cut) $(gone "$T/.upgrade/build.pid") \
$(gone "$T/.upgrade/pin.pid") $(grep -c 'STOPPED BY A SIGNAL' <<< "$out")" "slow-done gone gone 1"
# a signal between a job's start and the line that keeps its PID: the job stopped all the same - every job of the
# script's, not the PIDs it kept (a copy without `pin=$!` stands for one that landed there)
sed '/^pin=\$!$/d' "$T/scripts/upgrade-build-with-pin.sh" > "$T/scripts/unkept.sh"
check "the copy has no pin=\$! (the stand-in holds)" "$(grep -c "^pin=" "$T/scripts/unkept.sh")" 0
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/pin.finished"
(cd "$T" && exec env BUILD_SECONDS=30 PIN_SECONDS=30 PATH="$T/bin:$PATH" timeout -k 5 30 \
  bash scripts/unkept.sh < /dev/null > "$T/unkept.out" 2>&1) &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid"
[ "$(proc_info "$sp" | awk '{print $1}')" = "$$" ] && kill -TERM "$sp"
wait "$sp"
out=$(settled "$T/unkept.out")
check "a job whose PID was not kept yet: stopped with the rest, its process gone" \
  "$(pin_end) $(gone "$T/.upgrade/pin.pid")" "stopped gone"
# the stop's grace a whole number of seconds, refused before any job starts: a fraction aborted the stop's arithmetic
run STOP_GRACE=1.5
check "STOP_GRACE=1.5: refused before the build and the pin, said" \
  "$rc $(grep -c 'STOP_GRACE=1.5: not a whole number of seconds' <<< "$out") \
$([ -e "$T/.upgrade/build.pid" ] || [ -e "$T/.upgrade/pin.pid" ] && echo started || echo none)" "1 1 none"
# go-task KILLed at once: its command ending 0 on the TERM, go-task ran the build's next command during the stop
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.next"
(cd "$T" && exec env NEXT_CMD=1 ZERO_ON_TERM=1 BUILD_SECONDS=30 PIN_SECONDS=30 PATH="$T/bin:$PATH" timeout -k 5 30 bash scripts/upgrade-build-with-pin.sh \
  < /dev/null > "$T/next.out" 2>&1) &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ] && [ -s "$1" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid"
[ "$(proc_info "$sp" | awk '{print $1}')" = "$$" ] && kill -TERM "$sp"
wait "$sp"
out=$(settled "$T/next.out")
check "a TERM, the build's command ending 0 on it: no next command of the build's ran; both gone" \
  "$([ -e "$T/.upgrade/build.next" ] && echo ran || echo none) $(gone "$T/.upgrade/build.pid") $(gone "$T/.upgrade/pin.pid")" \
  "none gone gone"
# the stamper gone before the stop (its output's reader): the job deaf to the TERM KILLed all the same and the stop
# goes on to its end - a write first ended it (SIGPIPE, 141)
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/task.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
(cd "$T" && exec env BUILD_SECONDS=30 PIN_SECONDS=30 IGNORE_TERM=1 STOP_GRACE=1 PATH="$T/bin:$PATH" timeout -k 5 30 \
  bash scripts/upgrade-build-with-pin.sh < /dev/null > "$T/pipe.out" 2>&1) &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ] && [ -s "$1" ]; do sleep 0.1; done' "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid"
script=""
for f in /proc/[0-9]*/stat; do  # the script: timeout's child (timeout is this test's)
  read -r st 2> /dev/null < "$f" || continue
  set -- ${st##*) }
  [ "$2" = "$sp" ] && { script=${f#/proc/}; script=${script%/stat}; }
done
stamper=""
for f in /proc/[0-9]*/stat; do  # its stamper: its python child reading the time
  read -r st 2> /dev/null < "$f" || continue
  set -- ${st##*) }
  p=${f#/proc/}; p=${p%/stat}
  [ -n "$script" ] && [ "$2" = "$script" ] && grep -q strftime "/proc/$p/cmdline" 2> /dev/null && stamper=$p
done
check "the script and its stamper found" "$([ -n "$script" ] && [ -n "$stamper" ] && echo found || echo missing)" found
[ -n "$stamper" ] && kill -KILL "$stamper"
[ -n "$script" ] && [ "$(proc_info "$sp" | awk '{print $1}')" = "$$" ] && kill -TERM "$script"
wait "$sp"; rc=$?
out=$(cat "$T/pipe.out")
check "the stamper gone: the deaf build KILLed all the same, the pin gone, the stop ended 130" \
  "$rc $(gone "$T/.upgrade/build.pid") $(gone "$T/.upgrade/pin.pid")" "130 gone gone"
# the traps set before the jobs start: a signal between a job's start and its trap left that job running
check "the traps set before the first job starts" \
  "$(awk '/^trap stop EXIT/ {t = NR} /&$/ && !j {j = NR} END {print (t && j && t < j)}' \
     "$ROOT/scripts/upgrade-build-with-pin.sh")" 1
check "test:upgrade:full runs it (not the block inline), given the run's start" \
  "$(grep -c '^      - cmd: UPGRADE_FROM={{.START}} scripts/upgrade-build-with-pin.sh$' "$ROOT/Taskfile.yml")" 1
# a process the build or the pin left running in its session once its own process ended: stopped, said, the run failed
# - wait returns when go-task (the pin) ends, and the stop knew only the jobs still its children
for mode in LEFTOVER PIN_LEFTOVER; do
  rm -f "$T/.upgrade/left.pid" "$T/.upgrade/pinleft.pid"
  run "$mode=1"
  f=$T/.upgrade/left.pid; [ $mode = LEFTOVER ] || f=$T/.upgrade/pinleft.pid
  lp=$(cat "$f" 2> /dev/null)
  check "$mode: the process left behind stopped, said, the run failed" \
    "$([ "$rc" != 0 ] && echo failed) $(grep -c 'left processes running' <<< "$out") $([ -n "$lp" ] && [ -z "$(proc_info "$lp")" ] && echo gone)" \
    "failed 1 gone"
done
echo "build-with-pin: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
