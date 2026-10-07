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
cp "$ROOT/scripts/upgrade-build-with-pin.sh" "$T/scripts/" 2> /dev/null \
  || { echo "FAIL scripts/upgrade-build-with-pin.sh missing"; echo "build-with-pin: 1 FAILED"; exit 1; }
# task test:upgrade:build: BUILD (its exit), after BUILD_SECONDS
printf '#!/bin/bash\necho $$ > .upgrade/build.pid\nsleep "${BUILD_SECONDS:-0}"; echo build; echo > .upgrade/build.finished
exit "${BUILD:-0}"\n' > "$T/bin/task"
# the pin: PIN (its exit) after PIN_SECONDS, its PID first, "finished" when it ran its course
cat > "$T/tests/clickhouse-pin/run.sh" <<'STUB'
#!/bin/bash
echo $$ > .upgrade/pin.pid
sleep "${PIN_SECONDS:-0}"
echo "pin result line"; echo finished > .upgrade/pin.finished
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
  rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
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
out=$(cat "$T/term.out")
check "a TERM to the script, mid-build: it ends at once, the build and the pin stopped, the pin's process gone" \
  "$(pin_end) $([ -e "$T/.upgrade/build.finished" ] && echo finished || echo stopped) $((SECONDS - t0 < 10)) \
$(gone "$T/.upgrade/pin.pid")" "stopped stopped 1 gone"
# a Ctrl-C at the terminal: INT to every process of the foreground group - the script and its time-stamper (the build
# and the pin are in sessions of their own). The stamper ignores it: what the script says while it stops reaches the
# log, and nothing it writes then dies of a closed pipe. Each job with no terminal: one that reads it (an ssh asking
# for a host key) fails instead of stopping, and the wait with it.
rm -f "$T/.upgrade/pin.pid" "$T/.upgrade/build.pid" "$T/.upgrade/pin.finished" "$T/.upgrade/build.finished"
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
sessions="$(own_session "$T/.upgrade/build.pid") $(own_session "$T/.upgrade/pin.pid")"
# the whole group of timeout (it leads one), as the terminal's Ctrl-C reaches it - this test's own child, checked so
[ "$(proc_info "$sp" | awk '{print $1, $2}')" = "$$ $sp" ] && kill -INT -- "-$sp"
wait "$sp"
out=$(cat "$T/int.out")
check "the build and the pin each lead a session of their own (no terminal to stop on)" "$sessions" "own own"
check "a Ctrl-C to the group: it ends at once, both stopped and gone, the stop said in the log" \
  "$(pin_end) $([ -e "$T/.upgrade/build.finished" ] && echo finished || echo stopped) $((SECONDS - t0 < 10)) \
$(gone "$T/.upgrade/pin.pid") $(gone "$T/.upgrade/build.pid") $(grep -c '^[0-9:]\{8\} STOPPED BY A SIGNAL' <<< "$out")" \
  "stopped stopped 1 gone gone 1"
# the traps set before the jobs start: a signal between a job's start and its trap left that job running
check "the traps set before the first job starts" \
  "$(awk '/^trap stop EXIT/ {t = NR} /&$/ && !j {j = NR} END {print (t && j && t < j)}' \
     "$ROOT/scripts/upgrade-build-with-pin.sh")" 1
check "test:upgrade:full runs it (not the block inline)" \
  "$(grep -c '^      - cmd: scripts/upgrade-build-with-pin.sh$' "$ROOT/Taskfile.yml")" 1
echo "build-with-pin: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
