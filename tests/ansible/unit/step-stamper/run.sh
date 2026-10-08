#!/bin/bash
# scripts/upgrade-full-steps.sh (test:upgrade:full's steps) stopped by a signal, as a terminal's Ctrl-C, a TERM or a
# closed terminal (HUP) reach its process group - the script and its stamper; the step's task, a session of its own,
# gets none but through the script's stop: the step TERMed whole and its output read to the end (each line stamped,
# what it says while it stops among them), the stop said, the run ended 128+signal - no step after it, no proof for
# it. A step deaf to the TERM KILLed after STOP_GRACE, said. (In the Taskfile, go-task swallowed the first signals and,
# its command surviving one, ran the step's remaining commands and ended 0.) Each line of a step that ends of its own
# accord stamped, the script ending 0. A signal between the step's start and its record (its PID not kept yet) stops it
# all the same; a process outside the step's session holding its output (a daemon it started) holds the stop no
# longer than STAMPER_GRACE - the stamper then ended, said.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/run/tests/ansible/upgrade/steps" "$W/run/scripts/lib" "$W/bin"
for s in 01-a 02-b; do : > "$W/run/tests/ansible/upgrade/steps/$s.txt"; done
cp scripts/upgrade-full-steps.sh "$W/run/scripts/" && cp scripts/lib/process-groups.sh "$W/run/scripts/lib/"
# go-task: the step's command its child (in its group - the step's session), a TERM swallowed (go-task leaves it to
# the command); the command failing fails the task, the command ending 0 (NEXT_CMD) the task's next command runs - as
# go-task ran a step's remaining commands after one its running command survived
cat > "$W/bin/task" <<'STUB'
#!/bin/bash
echo "task $*" >> "$LOG"
case "$*" in test:upgrade:step* | test:upgrade:final-settle*) ;; *) exit 0 ;; esac
echo $$ > "$W/task.pid"
trap 'echo "task: signal received"' TERM
bash "$W/command" "$*" || exit $?
[ -z "${NEXT_CMD:-}" ] || { echo "the next command ran"; : > "$W/next.ran"; }
exit 0
STUB
# the step's command (the final settle's: "settle" lines, FINAL_ENDS of them): its PID recorded, lines written; on TERM
# it says so and writes five more over half a second (its children ending), then ends 143 - DEAF: it ignores the TERM
# (and a closed pipe); ZERO_ON_TERM: it ends 0 on it; ENDS: it ends of its own accord, 0. HOLDER: a sleep in a session
# of its own holding its output (as a daemon would), its PID recorded; LEFTOVER: a sleep left in its group, holding it;
# SESSION_CHECK: a check in a group of its own (set -m), in the step's session, that ignores the TERM. Its own end
# leaves said.ran
cat > "$W/command" <<'STUB'
case "$1" in
  test:upgrade:final-settle*) what="settle line" ends=${FINAL_ENDS:-1} said="settle done"; echo $$ > "$W/final.pid" ;;
  *) what=line ends=${ENDS:-300} said="step done"; echo $$ > "$W/step.pid" ;;
esac
[ -z "${HOLDER:-}" ] || { setsid sleep 60 & echo $! > "$W/holder.pid"; }
[ -z "${LEFTOVER:-}" ] || { sleep 60 & echo $! > "$W/leftover.pid"; }
if [ -n "${SESSION_CHECK:-}" ]; then
  set -m
  bash -c 'trap "" TERM; while :; do sleep 0.1; done' > /dev/null 2>&1 & echo $! > "$W/check.pid"
  set +m
fi
if [ -n "${DEAF:-}" ]; then trap '' TERM PIPE
elif [ -n "${ZERO_ON_TERM:-}" ]; then trap 'echo "ended 0 on the signal"; exit 0' TERM
else trap 'echo "stopping on the signal"; for j in 1 2 3 4 5; do echo "after the signal $j"; sleep 0.1; done; exit 143' TERM
fi
i=0
while [ "$i" -lt "$ends" ]; do echo "$what $i"; i=$((i + 1)); sleep 0.1; done
echo "$said"
: > "$W/said.ran"
STUB
# python3 as the run finds it: the stamper's (SLOW_STAMPER) takes a second to start, saying so - a signal then reaches
# it before python's own start (which ignores them); every other call the real one's
REAL_PY=$(command -v python3)
export REAL_PY
cat > "$W/bin/python3" <<'STUB'
#!/bin/bash
case "$*" in *strftime*) [ -z "${SLOW_STAMPER:-}" ] || { : > "$W/stamper.starting.tmp"; mv "$W/stamper.starting.tmp" "$W/stamper.starting"; sleep 1; } ;; esac
exec "$REAL_PY" "$@"
STUB
# as go-task runs the script: its exit read by a shell that outlives the signal (a handler: the script starts with
# every signal at its default); PIPED: its output through a pipe whose reader the signal ends (a tee a Ctrl-C ended)
cat > "$W/wrapper" <<'STUB'
trap : INT TERM HUP
if [ -n "${PIPED:-}" ]; then
  bash "${SCRIPT:-scripts/upgrade-full-steps.sh}" 2>&1 | cat > "$W/out"
  echo "${PIPESTATUS[0]}" > "$W/rc"
else
  bash "${SCRIPT:-scripts/upgrade-full-steps.sh}" > "$W/out" 2>&1
  echo $? > "$W/rc"
fi
STUB
printf '#!/bin/bash\necho "sha-${@: -1}"\n' > "$W/bin/git"
# sleep as the run finds it: SLOW_SLEEP - each takes four times what it asks (a loaded host)
REAL_SLEEP=$(command -v sleep)
export REAL_SLEEP
cat > "$W/bin/sleep" <<'STUB'
#!/bin/bash
[ -z "${SLOW_SLEEP:-}" ] || exec "$REAL_SLEEP" "$(awk -v s="$1" 'BEGIN { print s * 4 }')"
exec "$REAL_SLEEP" "$@"
STUB
printf '#!/bin/bash\necho "upgrade/$2 main"\n' > "$W/run/scripts/upgrade-expected-inventory.py"
printf '#!/bin/bash\necho "proof $2" >> "$LOG"\n' > "$W/run/scripts/upgrade-production.py"
# the digests read after a step: DIGESTS_HANG - it hangs (a stalled VM), its PID recorded
printf '#!/bin/bash\n[ -z "${DIGESTS_HANG:-}" ] || { echo $$ > "$W/digests.pid"; sleep 30; }\necho digests\n' \
  > "$W/run/scripts/vagrant-image-digests.sh"
chmod +x "$W/bin/"* "$W/run/scripts/"*.py "$W/run/scripts/"*.sh
fails=0
check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; sed 's/^/    /' "$W/out"; fails=$((fails + 1)); fi
}
proc_ok() {  # proc_ok <pid> <ppid>: the process is that one's child
  local want=$2 st
  st=$(cat "/proc/$1/stat" 2> /dev/null) || return 1
  set -- ${st##*) }
  [ "$2" = "$want" ]
}
run() {  # run <signal or none> <env...>: the script (SCRIPT: another copy) in a session of its own; WAIT_FOR (this
  # test's): what to wait for before the signal - re:<a line of its output> (default: the step's line 3) or file:<name>
  local sig=$1 wait_for=${WAIT_FOR:-'re:^[0-9:]\{8\} line 3$'}; shift
  rm -f "$W/rc" "$W/step.pid" "$W/final.pid" "$W/task.pid" "$W/next.ran" "$W/stamper.starting" "$W/check.pid" \
    "$W/leftover.pid" "$W/digests.pid" "$W/said.ran"
  : > "$W/log"; : > "$W/out"
  (cd "$W/run" && exec env STOP_GRACE=1 "$@" W="$W" LOG="$W/log" PATH="$W/bin:$PATH" python3 -c 'import os, signal
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGPIPE): signal.signal(s, signal.SIG_DFL)
os.setsid()
os.execvp("bash", ["bash", os.environ["W"] + "/wrapper"])') &
  local pg=$!
  for _ in $(seq 100); do
    case $wait_for in
      file:*) [ -e "$W/${wait_for#file:}" ] && break ;;
      re:*) grep -q "${wait_for#re:}" "$W/out" 2> /dev/null && break ;;
    esac
    sleep 0.05
  done
  if [ "$sig" = reader ]; then
    # the output's reader alone (PIPED: the wrapper's cat), no signal to the run: its process in this test's session
    local f st c
    for f in /proc/[0-9]*/stat; do
      read -r st 2> /dev/null < "$f" || continue
      set -- ${st##*) }
      [ "$2" = "$pg" ] && [ "$4" = "$pg" ] && read -r c 2> /dev/null < "${f%stat}comm" && [ "$c" = cat ] || continue
      c=${f#/proc/}
      kill "${c%/stat}"
    done
  elif [ "${sig#script:}" != "$sig" ]; then
    # the script alone (not its group): its process in this test's session, read from /proc
    local sp="" f c st
    for f in /proc/[0-9]*/cmdline; do
      c=$(tr '\0' ' ' 2> /dev/null < "$f") || continue
      [[ $c == "bash scripts/upgrade-full-steps.sh "* ]] || continue
      read -r st 2> /dev/null < "${f%/cmdline}/stat" || continue
      set -- ${st##*) }
      [ "$4" = "$pg" ] && { sp=${f#/proc/}; sp=${sp%/cmdline}; }
    done
    [ -n "$sp" ] && kill "-${sig#script:}" "$sp"
  elif [ "$sig" != none ]; then
    proc_ok "$pg" "$BASHPID" && kill "-$sig" -- "-$pg"
  fi
  for _ in $(seq 200); do [ -s "$W/rc" ] && break; sleep 0.05; done
  # bounded: a run still going here is this test's own session - ended, never waited out
  [ -s "$W/rc" ] || { proc_ok "$pg" "$BASHPID" && kill -KILL -- "-$pg"; }
  wait "$pg" 2> /dev/null
  local p
  step=$(cat "$W/step.pid" 2> /dev/null) final=$(cat "$W/final.pid" 2> /dev/null)
  alive=$([ -n "$step" ] && [ -e "/proc/$step" ] && echo alive || echo gone)
  falive=$([ -n "$final" ] && [ -e "/proc/$final" ] && echo alive || echo gone)
  # a step or a final settle left running by a failure here: its own process, a process this test's stub started -
  # ended (the task's session: this test's; its check, one of that session)
  for p in "$step" "$final"; do
    [ -n "$p" ] && [[ $(tr '\0' ' ' 2> /dev/null < "/proc/$p/cmdline") == "bash $W/command "* ]] && kill -KILL "$p"
  done
}
in_session() {  # in_session <pid file> <sid file>: the process runs (no zombie) in the session the other one led
  local st pid sid
  pid=$(cat "$1" 2> /dev/null) && sid=$(cat "$2" 2> /dev/null) || return 1
  read -r st 2> /dev/null < "/proc/$pid/stat" || return 1
  set -- ${st##*) }
  [ "$4" = "$sid" ] && [ "$1" != Z ]
}
for sig in INT TERM HUP; do
  run "$sig"
  want=$((128 + $(kill -l "$sig")))
  check "a $sig to the run: the step stopped whole (gone), what it said while stopping stamped, the stop said; ended $want" \
    "$(cat "$W/rc" 2> /dev/null || echo none) $alive $(grep -c '^[0-9:]\{8\} after the signal' "$W/out") \
$(grep -c '^=== STOPPED BY A SIGNAL' "$W/out")" "$want gone 5 1"
  check "a $sig to the run: no step after it, no proof, nothing said green" \
    "$(grep -c 'STEP=02-b' "$W/log") $(grep -c '^proof' "$W/log") $(grep -c 'GREEN' "$W/out")" "0 0 0"
done
run INT DEAF=1
check "a step deaf to the TERM: KILLed after the grace, said; the run ended 130" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $alive $(grep -c 'outlived the stop by 1 s - killed' "$W/out")" "130 gone 1"
# a TERM between the step's start and its record (forced in a copy: sent right after the start)
sed 's|^  setsid task "\$@" .* &$|&\n  kill -TERM $$|' "$W/run/scripts/upgrade-full-steps.sh" > "$W/run/scripts/unkept.sh"
check "the copy with a TERM before the step's record made" "$(grep -c '^  kill -TERM \$\$$' "$W/run/scripts/unkept.sh")" 1
run none SCRIPT=scripts/unkept.sh
check "a TERM before the step's PID was kept: the step stopped all the same (gone), the run ended 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $alive $(grep -c '^=== STOPPED BY A SIGNAL' "$W/out")" "143 gone 1"
# a daemon of the step's, a session of its own, holding its output: the stop held STAMPER_GRACE at most, said
run TERM HOLDER=1 STAMPER_GRACE=1
holder=$(cat "$W/holder.pid" 2> /dev/null)
check "a process outside the step holding its output: the stop not held past the stamper's grace, said; ended 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c 'output still held' "$W/out")" "143 1"
# the holder: a sleep this test's stub started - ended here
if [ -n "$holder" ] && [ "$(tr '\0' ' ' 2> /dev/null < "/proc/$holder/cmdline")" = "sleep 60 " ]; then kill "$holder"; fi
run none ENDS=3
check "steps ending of their own accord: each line stamped, both green, the first proven after the second, the run 0" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c '^[0-9:]\{8\} step done$' "$W/out") $(grep -c 'GREEN' "$W/out") \
$(grep -c '^proof 01-a$' "$W/log")" "0 2 2 1"
check "the final settle run as a step: its lines stamped" "$(grep -c '^[0-9:]\{8\} settle done$' "$W/out")" 1
check "its work directory (the fifo) removed at its end" "$(ls -d "$W/run/.upgrade"/full-steps.* 2> /dev/null | wc -l)" 0
# a signal during the final settle: stopped as a step is - whole, its stop's lines stamped, said; no proof of the last
# step (it ran in the foreground, where go-task swallowed a Ctrl-C and the script's trap waited for it)
WAIT_FOR='re:^[0-9:]\{8\} settle line 3$' run TERM ENDS=3 FINAL_ENDS=300
check "... and on a stop: its work directory removed" "$(ls -d "$W/run/.upgrade"/full-steps.* 2> /dev/null | wc -l)" 0
check "a TERM during the final settle: it stopped whole (gone), its stop's lines stamped, said; the last step unproven" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $falive $(grep -c '^[0-9:]\{8\} after the signal' "$W/out") \
$(grep -c '^=== STOPPED BY A SIGNAL' "$W/out") $(grep -c '^proof 01-a$' "$W/log") $(grep -c '^proof 02-b$' "$W/log")" \
  "143 gone 5 1 1 0"
# the graces whole seconds, refused before any step otherwise: a fraction aborted the stop's arithmetic - nothing
# KILLed, the step left running
# STAMPER_GRACE 1 at least: 0 KILLed the stamper at every step's end, every step failed
for g in STOP_GRACE=1.5 STAMPER_GRACE=0.5 STOP_GRACE=08 STAMPER_GRACE=0; do
  want="not a whole number of seconds"
  [ "${g%%=*}" = STOP_GRACE ] || want+=", 1 or more"
  run none ENDS=3 "$g"
  check "$g: refused before any step, said" \
    "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c "^${g%%=*}=${g#*=}: $want$" "$W/out") \
$(grep -c 'test:upgrade:step' "$W/log")" "1 1 0"
done
# a signal while the stamper starts (before python's own start ignores them): it survives - every line of the step,
# its stop's among them, read and stamped (dead, the step's writes ended it with a closed pipe)
WAIT_FOR=file:stamper.starting run TERM SLOW_STAMPER=1
check "a TERM while the stamper starts: the stamper survives - the step's stop lines stamped, the step gone, 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $alive $(grep -c '^[0-9:]\{8\} after the signal' "$W/out")" "143 gone 5"
# the run's output through a pipe whose reader the signal ended (a tee a Ctrl-C ended): the stop's KILL is sent before
# anything is said (a write first ended the stop - SIGPIPE, 141 - the step deaf to the TERM left running)
PIPED=1 run INT DEAF=1
check "the output's reader gone with the signal: the deaf step KILLed all the same, the run ended 130" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $alive" "130 gone"
# go-task KILLed at once: its command ending 0 on the TERM, go-task ran the step's next command during the stop
run TERM ZERO_ON_TERM=1 NEXT_CMD=1
check "a TERM, the step's command ending 0 on it: no next command of the step's ran, the run ended 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $([ -e "$W/next.ran" ] && echo ran || echo none)" "143 none"
# the step's session stopped whole: a check its command started in a group of its own, deaf to the TERM, KILLed after
# the grace, said (stopping the step's group alone left it running)
run TERM SESSION_CHECK=1
check "a TERM: the step's check in another group of its session, deaf to it, KILLed after the grace, said" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(in_session "$W/check.pid" "$W/task.pid" && echo alive || echo gone) \
$(grep -c 'outlived the stop by 1 s - killed' "$W/out")" "143 gone 1"
in_session "$W/check.pid" "$W/task.pid" && kill -KILL "$(cat "$W/check.pid")"
# a step that ended leaving a process of its session running (holding its output): stopped, said, the step failed -
# the run waited for its output for ever
run none ENDS=3 LEFTOVER=1
leftover=$(cat "$W/leftover.pid" 2> /dev/null)
check "a step ending with a process of its own left running: it stopped, said; the step failed, no step after it" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $([ -n "$leftover" ] && [ -e "/proc/$leftover" ] && echo alive || echo gone) \
$(grep -c '^=== STEP 01-a left processes running after it ended - stopped$' "$W/out") \
$(grep -c '^=== STEP 01-a FAILED' "$W/out") $(grep -c 'STEP=02-b' "$W/log")" "1 gone 1 1 0"
if [ -n "$leftover" ] && [ "$(tr '\0' ' ' 2> /dev/null < "/proc/$leftover/cmdline")" = "sleep 60 " ]; then kill "$leftover"; fi
# a step that ended, a process outside its session holding its output: the stamper ended after STAMPER_GRACE, said;
# the step failed (its log is not whole) - the run waited for ever
run none ENDS=3 HOLDER=1 STAMPER_GRACE=1
holder=$(cat "$W/holder.pid" 2> /dev/null)
check "a step ending, its output held outside it: the stamper ended after its grace, said; the step failed" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c 'output still held' "$W/out") $(grep -c '^=== STEP 01-a FAILED' "$W/out") \
$(grep -c 'STEP=02-b' "$W/log")" "1 1 1 0"
if [ -n "$holder" ] && [ "$(tr '\0' ' ' 2> /dev/null < "/proc/$holder/cmdline")" = "sleep 60 " ]; then kill "$holder"; fi
# a TERM right after a step's task ended and was reaped, before what it left running was stopped: the stop takes that
# session too (no job of the script's any more - own_jobs lists it no longer). Forced in a copy: the TERM sent then
sed 's|^  wait "\$step_job" \|\| task_rc=\$?$|&\n  kill -TERM $$|' "$W/run/scripts/upgrade-full-steps.sh" > "$W/run/scripts/reaped.sh"
check "the copy with a TERM after the task's end made" "$(grep -c '^  kill -TERM \$\$$' "$W/run/scripts/reaped.sh")" 1
run none SCRIPT=scripts/reaped.sh ENDS=3 LEFTOVER=1 STAMPER_GRACE=1
leftover=$(cat "$W/leftover.pid" 2> /dev/null)
check "a TERM after the task's end: what it left running stopped with it, the run ended 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $([ -n "$leftover" ] && [ -e "/proc/$leftover" ] && echo alive || echo gone)" \
  "143 gone"
if [ -n "$leftover" ] && [ "$(tr '\0' ' ' 2> /dev/null < "/proc/$leftover/cmdline")" = "sleep 60 " ]; then kill "$leftover"; fi
# a TERM to the script alone while the digests are read after a step (a stalled VM): the stop at once, the read
# stopped with it - in the foreground the trap waited for the read to end
WAIT_FOR=file:digests.pid run script:TERM ENDS=3 DIGESTS_HANG=1
dp=$(cat "$W/digests.pid" 2> /dev/null)
check "a TERM while the digests are read: the run stopped at once (143), the read ended with it" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $([ -n "$dp" ] && [ -e "/proc/$dp" ] && echo alive || echo gone)" "143 gone"
if [ -n "$dp" ] && [ "$(tr '\0' ' ' 2> /dev/null < "/proc/$dp/cmdline")" = "sleep 30 " ]; then kill "$dp"; fi
cs() {  # cs <variable>: hundredths of a second since boot
  local u
  read -r u _ < /proc/uptime
  u=${u/./}
  printf -v "$1" '%s' "$((10#$u))"
}
# the stamper's grace on the clock, not counted in sleeps: a loaded host (each sleep four times its length) held a 2 s
# grace 8 s
cs t0
WAIT_FOR=file:rc run none ENDS=3 HOLDER=1 STAMPER_GRACE=2 SLOW_SLEEP=1
cs t1
holder=$(cat "$W/holder.pid" 2> /dev/null)
check "a held output on a slow host: the stamper ended at its grace on the clock (well under 4 x 2 s), said; failed" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c 'output still held' "$W/out") $(( t1 - t0 < 650 ))" "1 1 1"
if [ -n "$holder" ] && [ "$(tr '\0' ' ' 2> /dev/null < "/proc/$holder/cmdline")" = "sleep 60 " ]; then kill "$holder"; fi
# a TERM after the stamper's start, before the step's task: nothing holds the output - none started (the stamper waits
# for a writer): the stop not held the stamper's grace, no process outside said to hold it. Forced in a copy
sed 's|^  setsid task "\$@" .* &$|  kill -TERM $$\n&|' "$W/run/scripts/upgrade-full-steps.sh" > "$W/run/scripts/unstarted.sh"
check "the copy with a TERM before the step's task started" "$(grep -c '^  kill -TERM \$\$$' "$W/run/scripts/unstarted.sh")" 1
cs t0
WAIT_FOR=file:rc run none SCRIPT=scripts/unstarted.sh STAMPER_GRACE=5
cs t1
check "a TERM before the step's task started: the stop at once (not the stamper's 5 s), nothing said held; ended 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c 'output still held' "$W/out") $(( t1 - t0 < 350 )) \
$(grep -c 'test:upgrade:step' "$W/log")" "143 0 1 0"
# ... the stamper slow to reach its own open (here half a second): given a writer however late it opens - not held its
# grace, nothing said held. Forced in a copy: a sleep before the stamper's exec, the TERM before the task
sed -e 's|^  ( trap .. INT TERM HUP; exec python3|  ( sleep 0.5; trap '"''"' INT TERM HUP; exec python3|' \
    -e 's|^  setsid task "\$@" .* &$|  kill -TERM $$\n&|' "$W/run/scripts/upgrade-full-steps.sh" > "$W/run/scripts/latestamper.sh"
check "the copy with a late stamper and a TERM before the task" \
  "$(grep -c '^  ( sleep 0.5; trap' "$W/run/scripts/latestamper.sh") $(grep -c '^  kill -TERM \$\$$' "$W/run/scripts/latestamper.sh")" "1 1"
cs t0
WAIT_FOR=file:rc run none SCRIPT=scripts/latestamper.sh STAMPER_GRACE=5
cs t1
check "a TERM before the task, the stamper late to open: the stop at once, nothing said held; ended 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c 'output still held' "$W/out") $(( t1 - t0 < 350 ))" "143 0 1"
# a TERM between the stamper's fork and its record: the stamper is no step job (its stop waited out STOP_GRACE for a
# process deaf to the TERM, said "outlived"), it is ended as a stamper is. Forced in a copy: the TERM before its record
sed 's|^  stamper=\$!$|  kill -TERM $$\n&|' "$W/run/scripts/upgrade-full-steps.sh" > "$W/run/scripts/unrecorded.sh"
check "the copy with a TERM before the stamper's record" "$(grep -c '^  kill -TERM \$\$$' "$W/run/scripts/unrecorded.sh")" 1
cs t0
WAIT_FOR=file:rc run none SCRIPT=scripts/unrecorded.sh STOP_GRACE=5 STAMPER_GRACE=5
cs t1
check "a TERM before the stamper's PID was kept: ended as a stamper - nothing said outlived or held, at once; 143" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c 'outlived\|output still held' "$W/out") $(( t1 - t0 < 350 ))" "143 0 1"
# the run's output reader gone, no signal to the run (a tee killed alone): the stamper reads on, its lines lost - the
# step runs to its own end (dead, the stamper's FIFO ended the step's next write: SIGPIPE in the middle of a step); the
# run then ends at its next word (141), no step after it
PIPED=1 run reader ENDS=20
check "the output's reader gone mid-step: the step ran to its own end; the run ended 141, no step after it" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $([ -e "$W/said.ran" ] && echo ended || echo cut) \
$(grep -c 'STEP=02-b' "$W/log")" "141 ended 0"
echo "step-stamper: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
