#!/bin/bash
# scripts/upgrade-merge-step.sh on throwaway repos (ops with two step files, infra with a bare origin): a merge pushes,
# fast-forwards and tags with the main it went onto; a run cut short after its push and before its tag (local main not
# moved yet, or moved) is taken up by the next run - tagged with the right base, not refused; main moved on origin by
# someone else is refused.
set -u
src=$(cd "$(dirname "$0")/../../../.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # name, want exit (0/1), output must contain, command...
  local name=$1 want=$2 grep=$3; shift 3
  out=$("$@" 2>&1); rc=$?; [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$want" ] && grep -qF -- "$grep" <<< "$out"; then echo "PASS $name"
  else echo "FAIL $name (exit $rc, want $want)"; sed 's/^/    /' <<< "$out"; fails=$((fails + 1)); fi
}
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -C "$W/infra" "$@"; }
mkdir -p "$W/ops/scripts" "$W/ops/tests/ansible/upgrade/steps"
cp "$src/scripts/upgrade-merge-step.sh" "$W/ops/scripts/"
for s in 01-a 02-b 03-c; do printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/$s.txt"; done
git init -q --bare -b main "$W/origin.git"
git clone -q "$W/origin.git" "$W/infra" 2> /dev/null
echo base > "$W/infra/f"; g add f; g commit -q -m base; g push -q origin main
for s in 01-a 02-b 03-c; do g checkout -q -b "upgrade/$s"; echo "$s" >> "$W/infra/f"; g commit -q -am "$s"; done
g checkout -q main
M="$W/ops/scripts/upgrade-merge-step.sh"
base_of() { g tag -l --format='%(contents:subject)' "upgrade-merged/$1"; }

main0=$(g rev-parse main)
check "a merge: pushed, fast-forwarded, tagged" 0 "tagged upgrade-merged/01-a" "$M" 01-a infra
check "its tag carries the main it went onto" 0 "base $main0" base_of 01-a
check "origin's main is the branch" 0 "$(g rev-parse upgrade/01-a)" git -C "$W/origin.git" rev-parse main

# cut short after the push, before the fast-forward and the tag
main1=$(g rev-parse main)
g push -q origin upgrade/02-b:main
check "pushed, not tagged, local main behind: taken up" 0 "pushed already" "$M" 02-b infra
check "tagged with local main as its base" 0 "base $main1" base_of 02-b
check "local main fast-forwarded" 0 "$(g rev-parse upgrade/02-b)" g rev-parse main

# cut short after the push and the fast-forward, before the tag
main2=$(g rev-parse main)
g push -q origin upgrade/03-c:main; g merge -q --ff-only upgrade/03-c
check "pushed and fast-forwarded, not tagged: taken up" 0 "pushed already" "$M" 03-c infra
check "tagged with main before the fast-forward (its reflog)" 0 "base $main2" base_of 03-c

# a merged step's branch deleted after its merge: the next step's predecessor check reads its tag
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/04-d.txt"
g branch -q -D upgrade/03-c
g checkout -q -b upgrade/04-d; echo d >> "$W/infra/f"; g commit -q -am d; g checkout -q main
check "the step before (03) deleted after its merge: 04 merged, 03's tag read" 0 "tagged upgrade-merged/04-d" \
  "$M" 04-d infra

# someone else moved origin's main: refused
git clone -q "$W/origin.git" "$W/other" 2> /dev/null
echo cd >> "$W/other/g"; git -C "$W/other" add g; git -C "$W/other" commit -q -m cd; git -C "$W/other" push -q origin main
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/05-e.txt"
g checkout -q -b upgrade/05-e; echo e >> "$W/infra/f"; g commit -q -am e; g checkout -q main
check "origin's main moved by someone else: refused" 1 "main is not origin/main" "$M" 05-e infra

# production's merge phase (scripts/upgrade-production.py) on the same repos: the proof's check of a step pushed by a
# run cut short before its tag compares the change with the main the push went onto - against origin's main it was an
# empty change, refused for good - and the take-up it then runs (take-up) tags only: in any other state it refuses
g pull -q --ff-only origin main
rm "$W/ops/tests/ansible/upgrade/steps/05-e.txt"  # never merged: 06's step before is 04
for s in 06-f 07-g; do printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/$s.txt"; done
g checkout -q -b upgrade/06-f; echo f >> "$W/infra/f"; g commit -q -am f; g checkout -q main
proof() {  # proof <step>: production's proof check of <step>'s infra merge, the full run having proved <own of>
  W=$W SRC=$src STEP=$1 OWN_OF=$2 python3 - <<'PYP'
import importlib.machinery, importlib.util, json, os
W, step = os.environ["W"], os.environ["STEP"]
L = importlib.machinery.SourceFileLoader("up", os.path.join(os.environ["SRC"], "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
m.OPS, m.PROVEN = os.path.join(W, "ops"), os.path.join(W, "proven")
os.makedirs(m.PROVEN, exist_ok=True)
base, tip = os.environ["OWN_OF"].split("..")
own = m.own_change(os.path.join(W, "infra"), base, tip)
json.dump({"run": "r", "ops": "x", "repos": {"infra": {"own": own}}, "floating": {"a": "b"}},
          open(m.proof_path(step), "w"))
m.floating_problems = m.app_tag_problems = m.unproven_changes = lambda *a: []
print("PROBLEMS:", m.proof_problems(step, [step], "infra") or "none")
PYP
}
check "the proof before 06's push: none" 0 "PROBLEMS: none" proof 06-f main..upgrade/06-f
check "take-up asked of a step not pushed: refused, nothing pushed" 1 "REFUSED: take-up only" "$M" 06-f infra take-up
check "origin's main untouched by it" 0 "$(g rev-parse main)" git -C "$W/origin.git" rev-parse main
main6=$(g rev-parse main)
g push -q origin upgrade/06-f:main
check "pushed by a run cut short before its tag: its change, against the main it went onto, is the proven one" 0 \
  "PROBLEMS: none" proof 06-f "$main6..upgrade/06-f"
check "then taken up (take-up): tagged, nothing else" 0 "pushed already" "$M" 06-f infra take-up
check "its base the main before the push" 0 "base $main6" base_of 06-f
g checkout -q -b upgrade/07-g; echo g >> "$W/infra/f"; g commit -q -am g; g checkout -q main
main7=$(g rev-parse main)
proven7=$(g rev-parse upgrade/07-g)
g checkout -q upgrade/07-g; echo unproven >> "$W/infra/f"; g commit -q -am unproven; g checkout -q main
g push -q origin upgrade/07-g:main
check "pushed untagged with a change the run did not prove: refused" 0 "brought a change other than" \
  proof 07-g "$main7..$proven7"
echo "upgrade-merge-step: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
exit $((fails > 0))
