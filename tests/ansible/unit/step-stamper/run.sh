#!/bin/bash
# scripts/upgrade-full-steps.sh (test:upgrade:full's steps) stopped by a signal, as a terminal's Ctrl-C, a TERM or a
# closed terminal (HUP) reach its process group - the script and its stamper; the step's task, a session of its own,
# gets none but through the script's stop: the step TERMed whole and its output read to the end (each line stamped,
# what it says while it stops among them), the stop said, the run ended 128+signal - no step after it, no proof for
# it. A step deaf to the TERM KILLed after STOP_GRACE, said. (In the Taskfile, go-task swallowed the first signals and,
# its command surviving one, ran the step's remaining commands and ended 0.) Each line of a step that ends of its own
# accord stamped, the script ending 0.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/run/tests/ansible/upgrade/steps" "$W/run/scripts/lib" "$W/bin"
for s in 01-a 02-b; do : > "$W/run/tests/ansible/upgrade/steps/$s.txt"; done
cp scripts/upgrade-full-steps.sh "$W/run/scripts/" && cp scripts/lib/process-groups.sh "$W/run/scripts/lib/"
# the step: its PID recorded, lines written; on TERM it says so and writes five more over half a second (its children
# ending), then ends 143 - or, DEAF, ignores it; ENDS: it ends of its own accord, 0
cat > "$W/bin/task" <<'STUB'
#!/bin/bash
echo "task $*" >> "$LOG"
case "$*" in test:upgrade:step*) ;; *) exit 0 ;; esac
echo $$ > "$W/step.pid"
if [ -n "${DEAF:-}" ]; then trap '' TERM; else
  trap 'echo "stopping on the signal"; for j in 1 2 3 4 5; do echo "after the signal $j"; sleep 0.1; done; exit 143' TERM
fi
i=0
while [ "$i" -lt "${ENDS:-300}" ]; do echo "line $i"; i=$((i + 1)); sleep 0.1; done
echo "step done"
STUB
printf '#!/bin/bash\necho "sha-${@: -1}"\n' > "$W/bin/git"
printf '#!/bin/bash\necho "upgrade/$2 main"\n' > "$W/run/scripts/upgrade-expected-inventory.py"
printf '#!/bin/bash\necho "proof $2" >> "$LOG"\n' > "$W/run/scripts/upgrade-production.py"
printf '#!/bin/bash\necho digests\n' > "$W/run/scripts/vagrant-image-digests.sh"
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
run() {  # run <signal or none> <env...>: the script in a session of its own (a terminal's foreground group), its exit
  # read by a shell that, as go-task, outlives the signal (a handler: the script starts with every signal at its default)
  local sig=$1; shift
  rm -f "$W/rc" "$W/step.pid"; : > "$W/log"; : > "$W/out"
  (cd "$W/run" && exec env "$@" W="$W" LOG="$W/log" PATH="$W/bin:$PATH" STOP_GRACE=1 python3 -c 'import os, signal, sys
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGPIPE): signal.signal(s, signal.SIG_DFL)
os.setsid()
os.execvp("bash", ["bash", "-c", "trap : INT TERM HUP; bash scripts/upgrade-full-steps.sh > \"$W/out\" 2>&1; echo $? > \"$W/rc\""])') &
  local pg=$!
  for _ in $(seq 100); do grep -q '^[0-9:]\{8\} line 3$' "$W/out" 2> /dev/null && break; sleep 0.05; done
  if [ "$sig" != none ]; then
    proc_ok "$pg" "$BASHPID" && kill "-$sig" -- "-$pg"
  fi
  for _ in $(seq 200); do [ -s "$W/rc" ] && break; sleep 0.05; done
  # bounded: a run still going here is this test's own session - ended, never waited out
  [ -s "$W/rc" ] || { proc_ok "$pg" "$BASHPID" && kill -KILL -- "-$pg"; }
  wait "$pg" 2> /dev/null
  step=$(cat "$W/step.pid" 2> /dev/null)
  alive=$([ -n "$step" ] && [ -e "/proc/$step" ] && echo alive || echo gone)
  # a step left running by a failure here: its own process, this test's grandchild - ended
  [ "$alive" = gone ] || kill -KILL "$step" 2> /dev/null
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
run none ENDS=3
check "steps ending of their own accord: each line stamped, both green, the first proven after the second, the run 0" \
  "$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c '^[0-9:]\{8\} step done$' "$W/out") $(grep -c 'GREEN' "$W/out") \
$(grep -c '^proof 01-a$' "$W/log")" "0 2 2 1"
echo "step-stamper: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
