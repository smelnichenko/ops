#!/usr/bin/env bash
# upgrade-full-steps.sh - test:upgrade:full's steps, in order, after its build: each step its own run of task
# test:upgrade:step, every line of it stamped with its time; stops at the first that fails. A step's proof is recorded
# once the next step's deciding settle has judged its restarts too: that settle's quiet window is 120 s, and a crash
# loop slower than that settles once - the restart history fails it a step later, so a step proven at once was proven
# with it. The last step is judged once more at production's own settle (test:upgrade:final-settle), then proven.
#
# Bash, not inline in the Taskfile: go-task swallows a Ctrl-C or a TERM (the first two), and when the step's running
# command survived one it ran the step's remaining commands and ended 0 - the run went on. Here a signal stops the
# step whole (its task in a session of its own, every process group of it TERMed, KILLed after STOP_GRACE; go-task
# KILLed at once), its output read to the end, said, and the run ends 128+signal: no step after it, no proof for it.
#
# Usage: scripts/upgrade-full-steps.sh   (test:upgrade:full; UPGRADE_FROM: the step it starts from - production's
#        first not done, its copy built as the steps before it left production - else the first)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# own_jobs, child_alive, group_alive, stop_groups
source scripts/lib/process-groups.sh
# the graces whole seconds, before anything starts: a fraction aborted the stop's arithmetic - nothing KILLed, the step
# left running. The stamper's 1 or more: 0 ended it at every step's end, its last lines unread
[[ ${STOP_GRACE:-0} =~ ^(0|[1-9][0-9]*)$ ]] || { echo "STOP_GRACE=$STOP_GRACE: not a whole number of seconds"; exit 1; }
[[ ${STAMPER_GRACE:-1} =~ ^[1-9][0-9]*$ ]] ||
  { echo "STAMPER_GRACE=$STAMPER_GRACE: not a whole number of seconds, 1 or more"; exit 1; }
stop_grace=${STOP_GRACE:-60} stamper_grace=${STAMPER_GRACE:-30}
mkdir -p .upgrade
work=$(mktemp -d "$PWD/.upgrade/full-steps.XXXX") || exit 1
step_job="" stamper="" signalled=""
# the stamper ends when what it reads does - all of it read; something outside the step still holding that (a daemon
# it started) holds it STAMPER_GRACE seconds at most (on the clock: counted in sleeps, a loaded host stretched it), then
# it is ended, said - 1 then (the step's log is not whole). One still waiting for its first writer (a signal between
# its start and the task's: none came) given one and its end - the FIFO opened and closed here at every look (the
# stamper may reach its own open after the first: it waited the grace out, said held), which waits for nothing and ends
# nothing a writer still holds (the task's output is closed by now: it ended, or the stop ended it)
end_stamper() {
  local held=0 now end w
  uptime_cs now
  end=$((now + stamper_grace * 100))
  while exec {w}<> "$work/out" && exec {w}>&- && child_alive "$stamper" && uptime_cs now && ((now < end)); do
    sleep 0.1
  done
  if child_alive "$stamper"; then
    kill -KILL "$stamper"
    held=1
    echo "=== the step's output still held after $stamper_grace s (a process outside it) - its stamper ended"
  fi
  wait "$stamper" 2> /dev/null
  stamper=""
  return "$held"
}
stop() {
  local rc=$? own j steps_=()
  # no signal cuts it short; a write to an output whose reader is gone (a tee the Ctrl-C ended) fails, not the stop
  trap '' INT TERM HUP PIPE
  # every job of this script's but the stamper - the step's task, a session of its own, one whose PID was not kept yet
  # (a signal between its start and its record) among them - and the session of a step whose task ended and was reaped
  # (a signal before its leftovers were stopped): every process of each, bounded. go-task KILLed at once: it ran the
  # step's next command once the running one ended, the grace still running
  own_jobs own
  # a signal between the stamper's fork and its record: the one job there is it (no task starts before that record) -
  # ended as a stamper, not stopped as a step (deaf to the TERM, it was waited out to STOP_GRACE, said outlived)
  if [ "$stamper" = starting ]; then stamper=${own[0]:-}; fi
  for j in "${own[@]}"; do [ "$j" = "$stamper" ] || steps_+=("$j"); done
  [ -z "$step_job" ] || [[ " ${steps_[*]} " == *" $step_job "* ]] || steps_+=("$step_job")
  [ "${#steps_[@]}" -eq 0 ] || stop_groups -n task "$stop_grace" "${steps_[@]}"
  [ -z "$stamper" ] || end_stamper
  [ -z "$signalled" ] || echo "=== STOPPED BY A SIGNAL $(date +%T) - the step stopped, no step after it"
  rm -rf "$work"
  exit "${signalled:-$rc}"
}
trap stop EXIT
trap 'trap "" INT TERM HUP; signalled=130; exit 130' INT
trap 'trap "" INT TERM HUP; signalled=143; exit 143' TERM
trap 'trap "" INT TERM HUP; signalled=129; exit 129' HUP

# one task (a step, the final settle): a session of its own - no terminal signal reaches it but through this script's
# stop - every line of it stamped with its time (where a step's minutes go stays measurable) by a stamper deaf to the
# signals from its start (ignored before its exec: python's own start was a window), ending when the task's output does,
# all of it read - its own output gone (a tee killed alone), it reads on, the lines lost: dead, it ended the step's next
# write (SIGPIPE in the middle of a step). Its exit in task_rc; a process of its session outliving its end stopped,
# said, and the task failed (1), as when something outside it held its output
run_task() {  # run_task <task arguments...>
  stamper=starting
  ( trap '' INT TERM HUP; exec python3 -u -c 'import os, signal, sys, time
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(s, signal.SIG_IGN)
for line in sys.stdin.buffer:
    try: sys.stdout.buffer.write(time.strftime("%H:%M:%S ").encode() + line); sys.stdout.flush()
    except OSError: os.dup2(os.open(os.devnull, os.O_WRONLY), 1)' < "$work/out" ) &
  stamper=$!
  setsid task "$@" < /dev/null > "$work/out" 2>&1 &
  step_job=$!
  task_rc=0
  wait "$step_job" || task_rc=$?
  if group_alive "$step_job"; then
    stop_groups -n task "$stop_grace" "$step_job"
    echo "=== STEP ${step:-} left processes running after it ended - stopped"
    task_rc=1
  fi
  step_job=""
  end_stamper || task_rc=1
}

steps=$(ls tests/ansible/upgrade/steps | sed -n 's/\.txt$//p' | sort -V)
# an empty step list is a failure, not a green run (the loop just did nothing)
[ -n "$steps" ] || { echo "no upgrade steps in tests/ansible/upgrade/steps"; exit 1; }
# from the step the run starts at: the ones before it are production's done steps, its copy built as they left it
if [ -n "${UPGRADE_FROM:-}" ]; then
  grep -qx -- "$UPGRADE_FROM" <<< "$steps" || { echo "UPGRADE_FROM=$UPGRADE_FROM: no such step"; exit 1; }
  steps=$(sed -n "/^$UPGRADE_FROM\$/,\$p" <<< "$steps")
fi
echo "=== $(echo "$steps" | wc -l) steps"
mkfifo "$work/out" || exit 1
prev=""
for step in $steps; do
  echo "=== STEP $step $(date +%T)"
  # the commits the step mirrors, before it: the proof refuses them if a branch moved meanwhile
  refs=$(scripts/upgrade-expected-inventory.py --refs "$step") || exit 1
  infra_sha=$(git -C ../infra rev-parse "${refs% *}") || exit 1
  platform_sha=$(git -C ../platform rev-parse "${refs#* }") || exit 1
  # the step before it in this run, green: what it need not check again
  run_task test:upgrade:step STEP="$step" PREV_STEP="${prev%% *}"
  [ "$task_rc" = 0 ] || { echo "=== STEP $step FAILED (exit $task_rc) $(date +%T)"; exit "$task_rc"; }
  # the digests the copy runs now, right after the step: its proof (recorded a step later) keeps its images'. A job in
  # a session of its own, waited for: a signal stops it as it stops a step (in the foreground the trap waited for it)
  mkdir -p .upgrade/step-digests
  setsid scripts/vagrant-image-digests.sh > ".upgrade/step-digests/$step.txt" < /dev/null &
  wait $! || exit 1
  if [ -n "$prev" ]; then
    # shellcheck disable=SC2086 # step, infra and platform sha: three words
    scripts/upgrade-production.py record-proof $prev || exit 1
  fi
  prev="$step $infra_sha $platform_sha"
  echo "=== STEP $step GREEN $(date +%T)"
done
# the last step at production's own settle, run as a step is (in the foreground go-task swallowed a Ctrl-C, and this
# script's trap waited for it)
step=final-settle
run_task test:upgrade:final-settle STEP="${prev%% *}"
[ "$task_rc" = 0 ] || { echo "=== FINAL SETTLE FAILED (exit $task_rc) $(date +%T)"; exit 1; }
# shellcheck disable=SC2086
scripts/upgrade-production.py record-proof $prev || exit 1
