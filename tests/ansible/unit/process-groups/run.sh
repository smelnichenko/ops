#!/bin/bash
# scripts/lib/process-groups.sh on processes this test starts itself (each its own child, read so before it is
# signalled): a job that leads no group yet - a stop between its fork and its setsid - stopped by its PID at once, not
# KILLed after the grace with its traps unrun; a group read alive with no external command (the read builtin: a cat
# per process made one scan 0.6 s); a job bash reaped already never listed as this shell's (`jobs -p` lists it, its PID
# free for another process); the grace measured on the clock uptime_cs reads (/proc/uptime: no wall-clock step moves
# it), not on bash's SECONDS - in hundredths: whole seconds made a 1 s grace anything from none to a second.
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
# bounded waits on what a process of this test writes once its traps are set - never a sleep before a signal (a slow
# start took the signal before the trap: the case passed or failed on the machine's load)
ready() {  # ready <file>...: each there, 5 s at most
  local f
  for f; do for _ in $(seq 100); do [ -s "$f" ] && break; sleep 0.05; done; done
}
set +m
# a job in this shell's group (no job control): what a setsid job is until setsid has run - its group none yet
bash -c 'trap "kill \$!; exit 143" TERM; echo ready > "$0"; sleep 30 & wait' "$W/r1" & j=$!
ready "$W/r1"
t0=$SECONDS
if mine "$j"; then stop_groups 5 "$j" > "$W/stop.out"; fi
wait "$j"; rc=$?
check "a job leading no group yet: TERMed by its PID, ended at once - nothing killed after the grace" \
  "$rc $((SECONDS - t0 < 3)) $(grep -c killed "$W/stop.out")" "143 1 0"
# one leading no group yet that ignores the TERM: still counted alive by its PID - KILLed after the grace, said (read
# as gone at once, it ran on)
bash -c 'trap "" TERM; echo ready > "$0"; sleep 30' "$W/r2" & j=$!
ready "$W/r2"
if mine "$j"; then stop_groups 1 "$j" > "$W/stop.out"; fi
wait "$j"; rc=$?
check "a job leading no group yet, ignoring the TERM: counted alive, KILLed after the grace, said" \
  "$rc $(grep -c 'outlived the stop by 1 s - killed' "$W/stop.out")" "137 1"
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
# `jobs -p` naming a live process that is no child of this shell (a reaped job's PID the system gave another - here
# this test's own parent): never listed
jobs() { echo "$PPID"; echo "$k"; }
own_jobs got
unset -f jobs
check "own_jobs: a PID jobs names that is no child of this shell (another process's now) - not listed" "${got[*]}" "$k"
mine "$k" && kill "$k"
wait "$k" 2> /dev/null
# the grace on uptime_cs's clock: one that jumps 100 s at each read ends a 30 s grace at its second read - a TERM-
# ignoring job then killed at once, said; on bash's SECONDS it waited the 30 s out
set -m
bash -c 'trap "" TERM; echo ready > "$0"; sleep 30' "$W/r3" & h=$!
set +m
ready "$W/r3"
t0=$SECONDS
if mine "$h"; then
  ( fake=0; uptime_cs() { fake=$((fake + 10000)); printf -v "$1" '%s' "$fake"; }; stop_groups 30 "$h" ) > "$W/clock.out"
fi
wait "$h" 2> /dev/null; rc=$?
check "the grace measured on uptime_cs's clock: its time up, the job killed at once, said" \
  "$rc $((SECONDS - t0 < 5)) $(grep -c 'outlived the stop by 30 s - killed' "$W/clock.out")" "137 1 1"
uptime_cs up
read -r real _ < /proc/uptime
real=${real/./}
check "uptime_cs: hundredths of a second since boot" "$(( (10#$real - up) >= 0 && (10#$real - up) < 50 ))" 1
uptime_cs a; sleep 0.3; uptime_cs b
check "uptime_cs: 0.3 s read as about 30 hundredths (whole seconds read 0 or 100)" "$(( b - a >= 25 && b - a <= 60 ))" 1
# a 1 s grace is a second: a job that ends 0.6 s after its TERM is not killed (whole seconds cut it at anything from
# none to a second)
set -m
bash -c 'trap "sleep 0.6; exit 143" TERM; echo ready > "$0"; sleep 30 & wait' "$W/r4" & h=$!
set +m
ready "$W/r4"
if mine "$h"; then stop_groups 1 "$h" > "$W/grace.out"; fi
wait "$h" 2> /dev/null; rc=$?
check "a 1 s grace: a job ending 0.6 s after its TERM ends of its own (143), not killed" \
  "$rc $(grep -c killed "$W/grace.out")" "143 0"
gone_or_zombie() {  # gone_or_zombie <pid>: "gone" once it runs no more (a zombie its parent has not reaped is gone)
  local st
  for _ in $(seq 50); do
    read -r st 2> /dev/null < "/proc/$1/stat" || { echo gone; return; }
    set -- "$1" ${st##*) }
    [ "$2" != Z ] || { echo gone; return; }
    sleep 0.05
  done
  echo running
}
# a PID alone matched only for this shell's own child: a process that is none - here a grandchild leading no group or
# session (job control off) - is no job of this shell's, whatever its PID (one bash reaped may be another process's by
# now): never read alive by it, never signalled by it
bash -c 'sleep 30 & echo $! > "$0"; wait' "$W/gc.pid" & gp=$!
ready "$W/gc.pid"
gc=$(cat "$W/gc.pid" 2> /dev/null)
gc_ok() {  # the grandchild: its parent this test's child
  local st
  read -r st 2> /dev/null < "/proc/$gc/stat" || return 1
  set -- ${st##*) }
  [ "$2" = "$gp" ]
}
check "the grandchild started (its parent this test's child)" "$(gc_ok && echo yes || echo no)" yes
if gc_ok; then
  check "group_alive: a process no child of this shell, leading no group - not read alive by its PID" \
    "$(group_alive "$gc" && echo alive || echo none)" none
  check "child_alive: a grandchild is no child" "$(child_alive "$gc" && echo child || echo none)" none
  stop_groups 1 "$gc" > "$W/foreign.out"
  check "stop_groups on it: never signalled by its PID (it lives), nothing said" \
    "$(gc_ok && echo lives || echo signalled) $(wc -l < "$W/foreign.out")" "lives 0"
fi
gc_ok && kill "$gc"
mine "$gp" && kill "$gp"
wait "$gp" 2> /dev/null
# child_alive: this shell's child, running - not one bash reaped (its PID free for another process)
sleep 30 & c=$!
check "child_alive: a running child" "$(child_alive "$c" && echo child || echo none)" child
mine "$c" && kill "$c"
wait "$c" 2> /dev/null
check "child_alive: a child reaped" "$(child_alive "$c" && echo child || echo none)" none
# a job leading a session (setsid, as the full run's step): every process group of its session stopped - a check its
# script started in a group of its own (set -m) that ignores the TERM KILLed after the grace with the rest, said; the
# job's own group stopped alone left it running (the step's checks outlived the full run's stop)
cat > "$W/session-job" <<'JOB'
#!/bin/bash
set -m
bash -c 'trap "" TERM; echo $$ > "$0"; while :; do sleep 0.1; done' "$1.deaf" &
set +m
trap 'exit 143' TERM
echo $$ > "$1"
while :; do sleep 0.1; done
JOB
setsid bash "$W/session-job" "$W/sess" < /dev/null > /dev/null 2>&1 & s=$!
ready "$W/sess" "$W/sess.deaf"
deaf=$(cat "$W/sess.deaf" 2> /dev/null)
in_session() {  # in_session <pid> <sid>: the process runs in that session
  local st
  read -r st 2> /dev/null < "/proc/$1/stat" || return 1
  set -- "$1" "$2" ${st##*) }
  [ "$6" = "$2" ] && [ "$3" != Z ]
}
check "the session's check started, in a group of its own, in the job's session" \
  "$(in_session "${deaf:-none}" "$s" && echo yes || echo no)" yes
if mine "$s"; then stop_groups 1 "$s" > "$W/session.out"; fi
wait "$s" 2> /dev/null
check "a session's job stopped: its check in another group, deaf to the TERM, KILLed after the grace, said" \
  "$(gone_or_zombie "${deaf:-none}") $(grep -c 'outlived the stop by 1 s - killed' "$W/session.out")" "gone 1"
in_session "${deaf:-none}" "$s" && kill -KILL "$deaf"
# kill_named: within a job's session every process of that name KILLed at once (go-task, which would run the step's
# next command once the running one ended) - not another process of the session, not one of that name outside it
mkdir -p "$W/named"
printf '#!/bin/bash\necho $$ > "$1"\nwhile :; do sleep 0.1; done\n' > "$W/named/task"
chmod +x "$W/named/task"
cat > "$W/named-job" <<'JOB'
#!/bin/bash
"$1/named/task" "$1/in.pid" &
bash -c 'echo $$ > "$0"; while :; do sleep 0.1; done' "$1/other.pid" &
while :; do sleep 0.1; done
JOB
setsid bash "$W/named-job" "$W" < /dev/null > /dev/null 2>&1 & s=$!
"$W/named/task" "$W/out.pid" & o=$!
ready "$W/in.pid" "$W/other.pid" "$W/out.pid"
inner=$(cat "$W/in.pid" 2> /dev/null) other=$(cat "$W/other.pid" 2> /dev/null)
check "the named processes started: two in the session, one outside" \
  "$(in_session "${inner:-none}" "$s" && in_session "${other:-none}" "$s" && mine "$o" && echo yes || echo no)" yes
mine "$s" && kill_named "$s" task
check "kill_named: the session's task KILLed at once, its other process and a task outside it left" \
  "$(gone_or_zombie "${inner:-none}") $(in_session "${other:-none}" "$s" && echo lives || echo gone) \
$(mine "$o" && echo lives || echo gone)" "gone lives lives"
mine "$o" && kill "$o"
wait "$o" 2> /dev/null
if mine "$s"; then stop_groups 1 "$s" > /dev/null; fi
wait "$s" 2> /dev/null
# a TERM the job never got (a job just forked loses one: its signals still the parent's handlers - the step's checks'
# stop then waited out their bound, 3 of 24 under load): sent again while it runs with TERM neither caught
# nor ignored - alive so, the TERM never reached it. Here a job deaf at the first TERM, at its default after: it ends of
# that TERM at once - not KILLed after the grace
set -m
# (`sleep 30; :` - its last command not exec'd in bash's place: bash stays its parent, the sleep one the job started
# after the TERM - sent again too, as a lost process's own)
bash -c 'trap "" TERM; echo ready > "$0"; sleep 0.5; trap - TERM; sleep 30; :' "$W/late.ready" & h=$!
set +m
ready "$W/late.ready"
t0=$SECONDS
if mine "$h"; then stop_groups 5 "$h" > "$W/late.out"; fi
wait "$h" 2> /dev/null; rc=$?
check "a TERM lost: sent again once the job's TERM is at its default - ended by it (143) at once, nothing killed" \
  "$rc $((SECONDS - t0 < 3)) $(grep -c killed "$W/late.out")" "143 1 0"
# never again to one that catches it, nor to what its handler starts: the handler runs once, and its cleanup's own
# command (at its default) runs to its end - a TERM sent again to every process at its default cut the cleanup short
cat > "$W/caught-job" <<'JOB'
trap 'echo stop >> "$1.n"; bash -c "sleep 1; echo cleaned >> \"\$0.n\"" "$1"; exit 143' TERM
echo ready > "$1"
while :; do sleep 0.1; done
JOB
set -m
bash "$W/caught-job" "$W/caught.ready" & h=$!
set +m
ready "$W/caught.ready"
if mine "$h"; then stop_groups 5 "$h" > /dev/null; fi
wait "$h" 2> /dev/null; rc=$?
check "a job catching the TERM: its handler run once, its cleanup's command run to its end, it ends of it (143)" \
  "$rc $(grep -c '^stop$' "$W/caught.ready.n") $(grep -c '^cleaned$' "$W/caught.ready.n")" "143 1 1"
# a stopped job (SIGSTOP: a Ctrl-Z, a debugger) acts on no TERM until continued: continued with it - its own stop runs,
# it ends of the TERM (143); not KILLed after the grace, its stop never run
set -m
bash -c 'trap "echo stopped-cleanly > \"\$0.done\"; exit 143" TERM; echo ready > "$0"; while :; do sleep 0.1; done' \
  "$W/cont.ready" & h=$!
set +m
ready "$W/cont.ready"
state=""
if mine "$h"; then
  kill -STOP -- "-$h"
  for _ in $(seq 50); do read -r st < "/proc/$h/stat"; set -- ${st##*) }; state=$1; [ "$state" = T ] && break; sleep 0.05; done
fi
check "the job stopped (state T) before the stop" "$state" T
if mine "$h"; then stop_groups 3 "$h" > "$W/cont.out"; fi
wait "$h" 2> /dev/null; rc=$?
check "a stopped job: continued with the TERM - its own stop run, ended 143, nothing killed" \
  "$rc $(cat "$W/cont.ready.done" 2> /dev/null) $(grep -c killed "$W/cont.out")" "143 stopped-cleanly 0"
# what a lost process starts after the TERM never got one: sent it once - one that catches it too (its handler runs
# once), not KILLed after the grace with its handler never run. Here the job, deaf at the TERM, starts a child that
# catches it (its TERM at its default before its exec), then turns its own to its default
set -m
bash -c 'trap "" TERM; echo ready > "$0"; sleep 0.5
  ( trap - TERM; exec bash -c "trap \"echo caught >> \\\"\$0\\\"; exit 143\" TERM; echo \$\$ > \"\$0.pid\"; while :; do sleep 0.1; done" "$0.n" ) &
  until [ -s "$0.n.pid" ]; do sleep 0.05; done; trap - TERM; wait' "$W/after.ready" & h=$!
set +m
ready "$W/after.ready"
t0=$SECONDS
if mine "$h"; then stop_groups 5 "$h" > "$W/after.out"; fi
wait "$h" 2> /dev/null; rc=$?
check "a lost process's child started after the TERM, catching it: TERMed once - its handler run once, nothing killed" \
  "$rc $((SECONDS - t0 < 3)) $(grep -c '^caught$' "$W/after.ready.n" 2> /dev/null) $(grep -c killed "$W/after.out")" \
  "143 1 1 0"
# -n <name>: every process of that name in the job KILLed at once - one that appears during the grace (go-task run by
# a command after the TERM: it swallows one and runs the step's next command) too, at the next look, not at the
# grace's end - and what it started since the TERM TERMed once (its handler run, not KILLed)
mkdir -p "$W/late"
cat > "$W/late/task" <<'TASK'
#!/bin/bash
trap '' TERM
echo $$ > "$1"
( trap - TERM; exec bash -c 'trap "echo caught >> \"$0\"; exit 143" TERM; echo $$ > "$0.pid"; while :; do sleep 0.1; done' "$1.n" ) &
wait
TASK
chmod +x "$W/late/task"
cat > "$W/late-job" <<'JOB'
#!/bin/bash
trap 'term=1' TERM
echo $$ > "$1/late.ready"
term=""
while [ -z "$term" ]; do sleep 0.1; done
"$1/late/task" "$1/late.pid"
JOB
setsid bash "$W/late-job" "$W" < /dev/null > /dev/null 2>&1 & s=$!
ready "$W/late.ready"
t0=$SECONDS
if mine "$s"; then stop_groups -n task 5 "$s" > "$W/late.out"; fi
wait "$s" 2> /dev/null
lt=$(cat "$W/late.pid" 2> /dev/null)
check "-n task: a task started during the grace KILLed at once, what it started TERMed once; nothing killed at the end" \
  "$((SECONDS - t0 < 3)) $(gone_or_zombie "${lt:-none}") $(grep -c '^caught$' "$W/late.pid.n" 2> /dev/null) \
$(grep -c killed "$W/late.out")" "1 gone 1 0"
for f in "$W/late.pid" "$W/late.pid.n.pid"; do
  x=$(cat "$f" 2> /dev/null) && in_session "$x" "$s" && kill -KILL "$x"
done
# a process the KILL does not end (uninterruptible - here every KILL lost): not said killed - its PIDs named
set -m
bash -c 'trap "" TERM; echo $$ > "$0"; while :; do sleep 0.1; done' "$W/stuck.pid" & h=$!
set +m
ready "$W/stuck.pid"
if mine "$h"; then
  ( kill() { [ "$1" = -KILL ] || builtin kill "$@"; }; stop_groups 1 "$h" ) > "$W/stuck.out"
fi
check "a process the KILL did not end: named, not said killed" \
  "$(grep -c 'killed$' "$W/stuck.out") $(grep -c "still there: .*\b$h\b" "$W/stuck.out")" "0 1"
mine "$h" && kill -KILL -- "-$h"
wait "$h" 2> /dev/null
echo "process-groups: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
