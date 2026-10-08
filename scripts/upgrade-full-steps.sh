#!/usr/bin/env bash
# upgrade-full-steps.sh - test:upgrade:full's steps, in order, after its build: each step its own run of task
# test:upgrade:step, every line of it stamped with its time; stops at the first that fails. A step's proof is recorded
# once the next step's deciding settle has judged its restarts too: that settle's quiet window is 120 s, and a crash
# loop slower than that settles once - the restart history fails it a step later, so a step proven at once was proven
# with it. The last step is judged once more at production's own settle (test:upgrade:final-settle), then proven.
#
# Bash, not inline in the Taskfile: go-task swallows a Ctrl-C or a TERM (the first two), and when the step's running
# command survived one it ran the step's remaining commands and ended 0 - the run went on. Here a signal stops the
# step whole (its task in a session of its own, TERMed, KILLed after STOP_GRACE), its output read to the end, said,
# and the run ends 128+signal: no step after it, no proof for it.
#
# Usage: scripts/upgrade-full-steps.sh   (test:upgrade:full)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# own_jobs, stop_groups
source scripts/lib/process-groups.sh
mkdir -p .upgrade
work=$(mktemp -d "$PWD/.upgrade/full-steps.XXXX") || exit 1
step_job="" stamper="" signalled=""
stop() {
  local rc=$? own j steps_=() i
  trap '' INT TERM HUP
  # every job of this script's but the stamper - the step's task, a session of its own, one whose PID was not kept yet
  # (a signal between its start and its record) among them: every process of it, bounded
  own_jobs own
  for j in "${own[@]}"; do [ "$j" = "$stamper" ] || steps_+=("$j"); done
  [ "${#steps_[@]}" -eq 0 ] || stop_groups "${STOP_GRACE:-60}" "${steps_[@]}"
  # the stamper ends when what it reads does - all of it read; something outside the step still holding that (a daemon
  # it started) holds the stop STAMPER_GRACE seconds at most
  if [ -n "$stamper" ]; then
    for ((i = 0; i < ${STAMPER_GRACE:-30} * 10; i++)); do kill -0 "$stamper" 2> /dev/null || break; sleep 0.1; done
    if kill -0 "$stamper" 2> /dev/null; then
      echo "=== the step's output still held after ${STAMPER_GRACE:-30} s (a process outside it) - its stamper ended"
      kill -KILL "$stamper"
    fi
    wait "$stamper" 2> /dev/null
  fi
  [ -z "$signalled" ] || echo "=== STOPPED BY A SIGNAL $(date +%T) - the step stopped, no step after it"
  rm -rf "$work"
  exit "${signalled:-$rc}"
}
trap stop EXIT
trap 'trap "" INT TERM HUP; signalled=130; exit 130' INT
trap 'trap "" INT TERM HUP; signalled=143; exit 143' TERM
trap 'trap "" INT TERM HUP; signalled=129; exit 129' HUP

steps=$(ls tests/ansible/upgrade/steps | sed -n 's/\.txt$//p' | sort -V)
# an empty step list is a failure, not a green run (the loop just did nothing)
[ -n "$steps" ] || { echo "no upgrade steps in tests/ansible/upgrade/steps"; exit 1; }
echo "=== $(echo "$steps" | wc -l) steps"
mkfifo "$work/out" || exit 1
prev=""
for step in $steps; do
  echo "=== STEP $step $(date +%T)"
  # the commits the step mirrors, before it: the proof refuses them if a branch moved meanwhile
  refs=$(scripts/upgrade-expected-inventory.py --refs "$step") || exit 1
  infra_sha=$(git -C ../infra rev-parse "${refs% *}") || exit 1
  platform_sha=$(git -C ../platform rev-parse "${refs#* }") || exit 1
  # every line of the step stamped with its time (where a step's minutes go stays measurable), by a stamper deaf to the
  # signals - it ends when the step's output does, all of it read. The step a session of its own: no terminal signal
  # reaches it but through this script's stop. The step before it in this run, green: what it need not check again
  python3 -u -c 'import signal, sys, time
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(s, signal.SIG_IGN)
for line in sys.stdin.buffer: sys.stdout.buffer.write(time.strftime("%H:%M:%S ").encode() + line); sys.stdout.flush()' \
    < "$work/out" &
  stamper=$!
  setsid task test:upgrade:step STEP="$step" PREV_STEP="${prev%% *}" < /dev/null > "$work/out" 2>&1 &
  step_job=$!
  rc=0
  wait "$step_job" || rc=$?
  step_job=""
  wait "$stamper"
  stamper=""
  [ "$rc" = 0 ] || { echo "=== STEP $step FAILED (exit $rc) $(date +%T)"; exit "$rc"; }
  # the digests the copy runs now, right after the step: its proof (recorded a step later) keeps its images'
  mkdir -p .upgrade/step-digests
  scripts/vagrant-image-digests.sh > ".upgrade/step-digests/$step.txt" || exit 1
  if [ -n "$prev" ]; then
    # shellcheck disable=SC2086 # step, infra and platform sha: three words
    scripts/upgrade-production.py record-proof $prev || exit 1
  fi
  prev="$step $infra_sha $platform_sha"
  echo "=== STEP $step GREEN $(date +%T)"
done
task test:upgrade:final-settle STEP="${prev%% *}" || exit 1
# shellcheck disable=SC2086
scripts/upgrade-production.py record-proof $prev || exit 1
