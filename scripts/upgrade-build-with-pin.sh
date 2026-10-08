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
# every line stamped with its time, as the steps' are: where the build's minutes go stays measurable. A Ctrl-C, a TERM
# or a HUP to the group reaches the stamper too: it ignores them (ignored, they stay so through its exec) and ends when
# its input does - what this script says while it stops reaches the log, and no write of it dies of a closed pipe
exec > >(trap '' INT TERM HUP; exec python3 -u -c 'import sys, time
for line in sys.stdin.buffer: sys.stdout.buffer.write(time.strftime("%H:%M:%S ").encode() + line); sys.stdout.flush()') 2>&1
rm -f .upgrade/clickhouse-pin.json
build_job="" pin="" signalled=""
# own_jobs, stop_groups
source scripts/lib/process-groups.sh
stop() {
  local j own
  # every job of this script's still its child, each a session of its own (setsid) - never a PID it did not start, nor
  # one bash reaped already: one whose PID was not kept yet (a signal between its start and `pin=$!`) is stopped with
  # the rest. The time-stamping process is no
  # job (a process substitution - `jobs -p` never lists it, measured on bash 5.2): waiting for it would wait for this
  # script's own end
  # nor here, on a stop of its own (a failed build) a signal arrives
  trap '' INT TERM HUP
  own_jobs own
  # each job's processes given STOP_GRACE seconds to end (the pin's trap removes its containers), then killed, said:
  # one that ignored the TERM held the stop for good
  [ "${#own[@]}" -eq 0 ] || stop_groups "${STOP_GRACE:-60}" "${own[@]}"
  for j in "${own[@]}"; do wait "$j" 2> /dev/null; done
  [ -z "$signalled" ] || echo "STOPPED BY A SIGNAL - the build and the ClickHouse pin stopped"
}
# the traps before the jobs: a signal between a job's start and its trap left the job running
trap stop EXIT
# a signal's first act: no other cuts the stop short (a Ctrl-C pressed twice; a timeout forwarding one to its group -
# measured: the second's exit ended the stop half done, the jobs left running, the stop unsaid). HUP (its terminal
# closed) the same stop, said
trap 'trap "" INT TERM HUP; signalled=1; exit 130' INT TERM
trap 'trap "" INT TERM HUP; signalled=1; exit 129' HUP
# the build and the pin each in a session of its own (setsid: no job control here, so neither leads a process group
# and setsid runs it in place - its PID is $!, its session's and group's): stopped whole when this ends early - a
# failed build, an interrupt, a TERM - the pin's docker calls with it (its own trap removes its containers). With no
# terminal, neither can stop on reading one (an ssh asking for a host key would, and the wait with it): it fails. The
# build in the background too, waited for: a trap waits for a foreground command to end (an hour's build), `wait`
# returns at once.
setsid tests/clickhouse-pin/run.sh > .upgrade/clickhouse-pin.log 2>&1 < /dev/null &
pin=$!
setsid task test:upgrade:build < /dev/null &
build_job=$!
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
