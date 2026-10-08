#!/bin/bash
# test:upgrade:full's per-step stamper (the python that stamps each line of a step with its time) as the Taskfile holds
# it, behind a writer standing in for go-task, both in one process group as a terminal's Ctrl-C finds them: INT, TERM
# or HUP to the group - the stamper goes on stamping until its input ends, the writer (stopping its children, as
# go-task does on INT) writes on and ends of its own accord; the stamper died first, and go-task of the closed pipe -
# its children (ansible on the copy) left running, unwaited.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
python3 - "$W/stamper.py" <<'PYEXTRACT'
import re, sys, yaml
cmds = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:full"]["cmds"]
body = next(c["cmd"] for c in cmds if isinstance(c, dict) and "task test:upgrade:step" in str(c.get("cmd", "")))
m = re.search(r"task test:upgrade:step [^\n]*?\\?\s*\| python3 -u -c '(.*?)'\n", body, re.S)
if not m:
    sys.exit("no stamper found behind task test:upgrade:step")
open(sys.argv[1], "w").write(m.group(1))
PYEXTRACT
[ -s "$W/stamper.py" ] || { echo "FAIL the stamper not found in the Taskfile"; echo "step-stamper: 1 FAILED"; exit 1; }
# the writer: on the signal it says it is stopping, writes on for a second (its children ending), then records its exit
# (a write to a dead stamper's pipe kills it first - no record)
cat > "$W/writer.sh" <<'WRITER'
#!/bin/bash
trap 'echo "stopping on the signal"; stop=1' INT TERM HUP
i=0
while [ "$i" -lt 30 ]; do echo "line $i"; i=$((i + 1)); [ -z "${stop:-}" ] || break; sleep 0.1; done
for j in 1 2 3 4 5; do echo "after the signal $j"; sleep 0.2; done
echo 0 > "$RC"
WRITER
fails=0
for sig in INT TERM HUP; do
  rm -f "$W/out" "$W/rc" "$W/stamper-rc"
  # a session of its own with every signal at its default, as go-task's foreground pipeline has them (a background job
  # of this shell would start with INT ignored, and prove nothing); its shell, as go-task, outlives the signal (a handler:
  # its children start with it at its default) to read the stamper's exit
  RC="$W/rc" python3 -c 'import os, signal, sys
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGPIPE):
    signal.signal(s, signal.SIG_DFL)
os.setsid()
os.execvp("bash", ["bash", "-c", sys.argv[1]])' "trap : INT TERM HUP; bash '$W/writer.sh' 2>&1 | python3 -u '$W/stamper.py' > '$W/out'; echo \${PIPESTATUS[1]} > '$W/stamper-rc'" &
  pg=$!
  # bounded: a pipeline that never writes fails here, never spins
  for _ in $(seq 100); do [ -s "$W/out" ] && break; sleep 0.05; done
  # its own session's group (read in /proc: CI's image has no ps) - this test's child, checked so before the signal
  st=$(cat "/proc/$pg/stat" 2> /dev/null) && set -- ${st##*) } && [ "$3" = "$pg" ] && kill "-$sig" -- "-$pg"
  for _ in $(seq 100); do [ -s "$W/rc" ] && break; sleep 0.05; done
  wait "$pg" 2> /dev/null
  for _ in $(seq 100); do [ -s "$W/stamper-rc" ] && break; sleep 0.05; done
  got="$(cat "$W/rc" 2> /dev/null || echo none) $(grep -c '^[0-9:]\{8\} after the signal' "$W/out" 2> /dev/null)"
  if [ "$got" = "0 5" ]; then echo "PASS a $sig to the group: the writer wrote on and ended of its own accord, every line stamped"
  else echo "FAIL a $sig to the group: the writer's own end, its lines after the signal: got '$got', want '0 5'"; fails=$((fails + 1)); fi
  # and the signal not swallowed: the step that survived it ended 0, the stamper ends 128+signal - the run stops
  want=$((128 + $(kill -l "$sig")))
  got=$(cat "$W/stamper-rc" 2> /dev/null || echo none)
  if [ "$got" = "$want" ]; then echo "PASS a $sig to the group: the stamper's exit says it ($want)"
  else echo "FAIL a $sig to the group: the stamper's exit: got '$got', want '$want'"; fails=$((fails + 1)); fi
done
# no signal: the stamper's exit 0
out=$(printf 'a\nb\n' | python3 -u "$W/stamper.py"); rc=$?
if [ "$rc $(grep -c '^[0-9:]\{8\} [ab]$' <<< "$out")" = "0 2" ]; then echo "PASS no signal: every line stamped, exit 0"
else echo "FAIL no signal: got '$rc', want 0"; fails=$((fails + 1)); fi
echo "step-stamper: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
