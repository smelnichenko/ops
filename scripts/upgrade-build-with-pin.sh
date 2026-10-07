#!/usr/bin/env bash
# upgrade-build-with-pin.sh - the full run's build (task test:upgrade:build) and, beside it (no wall time), the
# ClickHouse rollback pin of steps 59 and 61 with the real images, in docker here (tests/clickhouse-pin/run.sh): a
# failed pin stops the run when the build ends, not hours later at 59, whose proof (and 61's) wants its passing result
# for the commits and images they run. A failed build ends at once and stops the pin; a stop of this script stops
# both.
#
# Bash, not inline in the Taskfile: go-task runs a cmd in its own shell, where `$!` is no PID and `kill` does nothing,
# and errexit cannot be turned off - a failed build left the pin running, a failed pin ended the block at its `wait`
# with nothing said.
#
# Usage: scripts/upgrade-build-with-pin.sh   (test:upgrade:full)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# every line stamped with its time, as the steps' are: where the build's minutes go stays measurable
exec > >(python3 -u -c 'import sys, time
for line in sys.stdin.buffer: sys.stdout.buffer.write(time.strftime("%H:%M:%S ").encode() + line); sys.stdout.flush()') 2>&1
rm -f .upgrade/clickhouse-pin.json
# the build and the pin each in a process group of their own (job control while they start): stopped whole when this
# ends early - a failed build, an interrupt, a TERM - the pin's docker calls with it (its own trap removes its
# containers). The build in the background too, waited for: a trap waits for a foreground command to end (an hour's
# build), `wait` returns at once. Neither reads the caller's input (a background job at a terminal would stop on it).
set -m
tests/clickhouse-pin/run.sh > .upgrade/clickhouse-pin.log 2>&1 < /dev/null &
pin=$!
task test:upgrade:build < /dev/null &
build_job=$!
set +m
stop() {
  local j own
  # a group signalled only while it is still this script's job: never one it did not start
  own=" $(jobs -p | tr '\n' ' ') "
  for j in "$build_job" "$pin"; do
    [[ $own == *" $j "* ]] && kill -TERM -- "-$j" 2> /dev/null
  done
  # these two only: a bare wait waits for the time-stamping process too, which waits for this script's end
  wait "$build_job" "$pin" 2> /dev/null
}
trap stop EXIT
trap 'exit 130' INT TERM
build=0
wait "$build_job" || build=$?
[ "$build" = 0 ] || { echo "THE BUILD FAILED (exit $build) - the ClickHouse pin stopped"; exit "$build"; }
pinned=0
wait "$pin" || pinned=$?
trap - EXIT
if [ "$pinned" != 0 ]; then
  echo "THE CLICKHOUSE PIN FAILED (.upgrade/clickhouse-pin.log):"; tail -20 .upgrade/clickhouse-pin.log; exit 1
fi
echo "CLICKHOUSE PIN: $(tail -1 .upgrade/clickhouse-pin.log)"
