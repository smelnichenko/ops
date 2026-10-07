#!/bin/bash
# test:upgrade:full's step loop as the Taskfile holds it, in a scratch directory with three fixture steps, task, git
# and the scripts it calls stubs that log: a step's proof is recorded only once the next step's deciding settle has
# judged its restarts too (a crash loop slower than that settle's 120 s quiet window settles once, and the restart
# history fails it a step later - its proof was already written), and the last step is judged once more at
# production's own settle (300 s quiet, 4 polls) before its proof - nothing after it judged its restarts at all. A
# step that fails leaves the step before it unproven.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/run/tests/ansible/upgrade/steps" "$W/run/scripts" "$W/bin"
for s in 01-a 02-b 03-c; do : > "$W/run/tests/ansible/upgrade/steps/$s.txt"; done
python3 - "$W" <<'PY' || { echo "FAIL the loop could not be extracted"; exit 1; }
import sys, yaml
W = sys.argv[1]
cmds = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:full"]["cmds"]
text = lambda c: c.get("cmd", "") if isinstance(c, dict) else str(c)
loop = [text(c) for c in cmds if "for step in $steps" in text(c)]
assert len(loop) == 1, len(loop)
open(W + "/loop.sh", "w").write(loop[0])
PY
cat > "$W/bin/task" <<'STUB'
#!/bin/bash
echo "task $*" >> "$LOG"
[ "$*" != "test:upgrade:step STEP=$FAIL_AT" ]
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
  (cd "$W/run" && PATH="$W/bin:$PATH" LOG="$W/log" FAIL_AT=$2 bash "$W/loop.sh" > "$W/out" 2>&1); rc=$?
  [ $rc = 0 ] || rc=1
  got=$(sed 's/^task test:upgrade:step STEP=/step /; s/^task test:upgrade:final-settle STEP=/final-settle /' "$W/log" \
    | paste -sd';')
  if [ "$rc" = "$3" ] && [ "$got" = "$4" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc)"; echo "    got:  $got"; echo "    want: $4"; fails=$((fails + 1))
}
case_ "three steps green: each proof after the next step, the last after the final settle; digests after each step" \
  none 0 "step 01-a;digests;step 02-b;digests;proof 01-a;step 03-c;digests;proof 02-b;final-settle 03-c;proof 03-c"
case_ "the second step fails: the first one unproven (its restarts not judged by a passing step)" 02-b 1 \
  "step 01-a;digests;step 02-b"
case_ "the last step fails: the one before unproven, no final settle" 03-c 1 \
  "step 01-a;digests;step 02-b;digests;proof 01-a;step 03-c"
check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got $2, want $3"; fails=$((fails + 1)); fi
}
case_ "(again, for the digests' files)" none 0 \
  "step 01-a;digests;step 02-b;digests;proof 01-a;step 03-c;digests;proof 02-b;final-settle 03-c;proof 03-c"
check "each step's digests in a file of its own" "$(ls "$W/run/.upgrade/step-digests" | paste -sd' ')" \
  "01-a.txt 02-b.txt 03-c.txt"
# the final settle as the Taskfile holds it: production's quiet window and polls, a restart-history label of its own
python3 - <<'PY' || fails=$((fails + 1))
import sys, yaml
t = yaml.safe_load(open("Taskfile.yml"))["tasks"].get("test:upgrade:final-settle")
cmd = " ".join(c.get("cmd", "") if isinstance(c, dict) else str(c) for c in (t or {}).get("cmds") or [])
want = ["restart_quiet=300", "stable_polls=4", "poll_seconds=10", "restart_step=final", "argo-settled.yml"]
missing = [w for w in want if w not in cmd]
print(("PASS" if not missing else "FAIL") + " the final settle at production's values, its own history label"
      + (f": missing {missing}" if missing else ""))
sys.exit(1 if missing else 0)
PY
echo "full-run-proof-order: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
