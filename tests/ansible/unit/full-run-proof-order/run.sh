#!/bin/bash
# test:upgrade:full's step loop (scripts/upgrade-full-steps.sh, the Taskfile's command for it), in a scratch directory
# with three fixture steps, task, git and the scripts it calls stubs that log: a step's proof is recorded only once the next step's deciding settle has
# judged its restarts too (a crash loop slower than that settle's 120 s quiet window settles once, and the restart
# history fails it a step later - its proof was already written), and the last step is judged once more at
# production's own settle (300 s quiet, 4 polls) before its proof - nothing after it judged its restarts at all. A
# step that fails leaves the step before it unproven.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/run/tests/ansible/upgrade/steps" "$W/run/scripts/lib" "$W/bin"
for s in 01-a 02-b 03-c; do : > "$W/run/tests/ansible/upgrade/steps/$s.txt"; done
python3 - <<'PY' || { echo "FAIL test:upgrade:full does not run scripts/upgrade-full-steps.sh once"; exit 1; }
import yaml
cmds = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:full"]["cmds"]
text = lambda c: c.get("cmd", "") if isinstance(c, dict) else str(c)
assert [text(c) for c in cmds if "upgrade-full-steps.sh" in text(c)] == ["scripts/upgrade-full-steps.sh"]
assert not any("for step in" in text(c) for c in cmds)
PY
cp scripts/upgrade-full-steps.sh "$W/run/scripts/" && cp scripts/lib/process-groups.sh "$W/run/scripts/lib/"
cat > "$W/bin/task" <<'STUB'
#!/bin/bash
echo "task $*" >> "$LOG"
case "$*" in "test:upgrade:step STEP=$FAIL_AT "*) exit 1 ;; esac
STUB
cat > "$W/bin/git" <<'STUB'
#!/bin/bash
echo "sha-${@: -1}"
STUB
cat > "$W/run/scripts/upgrade-expected-inventory.py" <<'STUB'
#!/bin/bash
echo "upgrade/$2 main"
STUB
cat > "$W/run/scripts/upgrade-production.py" <<'STUB'
#!/bin/bash
echo "proof $2" >> "$LOG"
STUB
cat > "$W/run/scripts/vagrant-image-digests.sh" <<'STUB'
#!/bin/bash
echo digests >> "$LOG"
STUB
chmod +x "$W/bin/"* "$W/run/scripts/"*
fails=0
case_() {  # case_ <name> <step that fails, or none> <want rc 0|1> <want log, ; between>
  : > "$W/log"
  (cd "$W/run" && PATH="$W/bin:$PATH" LOG="$W/log" FAIL_AT=$2 bash scripts/upgrade-full-steps.sh > "$W/out" 2>&1); rc=$?
  [ $rc = 0 ] || rc=1
  got=$(sed 's/^task test:upgrade:step STEP=/step /; s/^task test:upgrade:final-settle STEP=/final-settle /' "$W/log" \
    | paste -sd';')
  if [ "$rc" = "$3" ] && [ "$got" = "$4" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc)"; echo "    got:  $got"; echo "    want: $4"; fails=$((fails + 1))
}
# each step given the one before it, green in this run (PREV_STEP: what it need not check again), the first none
case_ "three steps green: each proof after the next step, the last after the final settle; digests after each step" \
  none 0 "step 01-a PREV_STEP=;digests;step 02-b PREV_STEP=01-a;digests;proof 01-a;step 03-c PREV_STEP=02-b;digests;proof 02-b;final-settle 03-c;proof 03-c"
case_ "the second step fails: the first one unproven (its restarts not judged by a passing step)" 02-b 1 \
  "step 01-a PREV_STEP=;digests;step 02-b PREV_STEP=01-a"
case_ "the last step fails: the one before unproven, no final settle" 03-c 1 \
  "step 01-a PREV_STEP=;digests;step 02-b PREV_STEP=01-a;digests;proof 01-a;step 03-c PREV_STEP=02-b"
check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got $2, want $3"; fails=$((fails + 1)); fi
}
case_ "(again, for the digests' files)" none 0 \
  "step 01-a PREV_STEP=;digests;step 02-b PREV_STEP=01-a;digests;proof 01-a;step 03-c PREV_STEP=02-b;digests;proof 02-b;final-settle 03-c;proof 03-c"
check "each step's digests in a file of its own" "$(ls "$W/run/.upgrade/step-digests" | paste -sd' ')" \
  "01-a.txt 02-b.txt 03-c.txt"
# the final settle as the Taskfile holds it: production's own values - what scripts/upgrade-production.py settle-values
# prints, the values its settle sends argo-settled.py on ten - and a restart-history label of its own; the step settles
# one set of values (STEP_SETTLE), shorter
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY' || fails=$((fails + 1))
import contextlib, importlib.machinery, importlib.util, io, re, subprocess, sys
import yaml
l = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", l))
l.exec_module(m)
bad = []
tf = yaml.safe_load(open("Taskfile.yml"))
t = tf["tasks"].get("test:upgrade:final-settle") or {}
cmd = " ".join(c.get("cmd", "") if isinstance(c, dict) else str(c) for c in t.get("cmds") or [])
used = re.findall(r"\{\{\s*\.(\w+)\s*\}\}", cmd)
values = [v for v in used if (t.get("vars") or {}).get(v, {}) == {"sh": "scripts/upgrade-production.py settle-values"}]
if not values:
    bad.append("the final settle does not take scripts/upgrade-production.py settle-values")
if "restart_step=final" not in cmd or "argo-settled.yml" not in cmd:
    bad.append("the final settle: argo-settled.yml with a restart_step of its own")
if re.search(r"restart_quiet=|stable_polls=|poll_seconds=", cmd):
    bad.append("the final settle restates a value")
printed = subprocess.run(["scripts/upgrade-production.py", "settle-values"], capture_output=True, text=True).stdout.split()
sent = []
m.main_revisions = lambda: {u: "r" for u in m.URLS.values()}
m.remote = lambda host, command, stdin=None, timeout=None, capture=True: sent.append(command) or type(
    "R", (), {"returncode": 0, "stdout": "", "stderr": ""})()
with contextlib.redirect_stdout(io.StringIO()):
    m.settled(1, [])
flags = dict(re.findall(r"--(poll|stable-polls|restart-quiet) (\S+)", sent[0]))
want = ["-e", f"restart_quiet={flags.get('restart-quiet')}", "-e", f"stable_polls={flags.get('stable-polls')}", "-e",
        f"poll_seconds={flags.get('poll')}"]
if printed != want:
    bad.append(f"settle-values prints {printed}, production's settle sends {want}")
steps = [c.get("cmd", "") for n in ("test:upgrade:argo", "test:upgrade:step") for c in tf["tasks"][n]["cmds"]
         if isinstance(c, dict) and "argo-settled.yml" in c.get("cmd", "") and "stable_polls=1" not in c.get("cmd", "")]
if len(steps) != 2 or any("{{.STEP_SETTLE}}" not in c or re.search(r"restart_quiet=|stable_polls=", c) for c in steps):
    bad.append(f"the build's (test:upgrade:argo) and the steps' deciding settles take STEP_SETTLE alone: {steps}")
print(("PASS" if not bad else "FAIL") + " the final settle at production's own values, the step settles one set"
      + "".join("\n  " + b for b in bad))
sys.exit(1 if bad else 0)
PY
echo "full-run-proof-order: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
