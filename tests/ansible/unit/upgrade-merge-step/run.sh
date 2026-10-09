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
json.dump({"run": "r", "complete": True, "ops": "x", "repos": {"infra": {"own": own}}, "floating": {"a": "b"}},
          open(m.proof_path(step), "w"))
m.floating_problems = m.app_tag_problems = m.unproven_changes = m.main_problems = lambda *a: []
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

# production's merge passes the tip it checked: a branch that moved since (between its checks and the push - an open
# confirm, the pre-pull) is refused, nothing pushed; the tip it checked merges
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/10-j.txt"
rm -f "$W/ops/tests/ansible/upgrade/steps/08-h.txt" "$W/ops/tests/ansible/upgrade/steps/09-i.txt"
g pull -q --ff-only origin main  # 07's push (above) is origin's main
g checkout -q -b upgrade/10-j; echo j >> "$W/infra/f"; g commit -q -am j
checked=$(g rev-parse HEAD)
echo moved >> "$W/infra/f"; g commit -q -am moved; g checkout -q main
origin10=$(git -C "$W/origin.git" rev-parse main)
check "the branch moved since the tip was checked: refused" 1 "moved since" "$M" 10-j infra "$checked"
check "nothing pushed" 0 "$origin10" git -C "$W/origin.git" rev-parse main
g branch -q -f upgrade/10-j "$checked"
check "the tip it checked: merged" 0 "tagged upgrade-merged/10-j" "$M" 10-j infra "$checked"

# the branch moved while the merge runs, after its tip was checked (a restack in another shell): the commit checked is
# the one pushed and tagged - the push by the branch's name took the moved one, unproven
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/11-k.txt"
g checkout -q -b upgrade/11-k; echo k >> "$W/infra/f"; g commit -q -am k
checked11=$(g rev-parse HEAD)
echo moved >> "$W/infra/f"; g commit -q -am moved11; moved11=$(g rev-parse HEAD)
g checkout -q main; g branch -q -f upgrade/11-k "$checked11"
mkdir -p "$W/bin"
cat > "$W/bin/git" <<STUB
#!/bin/bash
# the branch moved once, at the script's first log - after its tip check, before its push
if [ "\$1" = -C ] && [ "\$3" = log ] && [ ! -e "$W/moved" ]; then
  : > "$W/moved"; $(command -v git) -C "$W/infra" update-ref refs/heads/upgrade/11-k "$moved11"
fi
exec $(command -v git) "\$@"
STUB
chmod +x "$W/bin/git"
check "the branch moved mid-run, after the tip check: the merge still runs" 0 "tagged upgrade-merged/11-k" \
  env PATH="$W/bin:$PATH" "$M" 11-k infra "$checked11"
check "the moved branch did move (the fixture worked)" 0 "$moved11" g rev-parse upgrade/11-k
check "origin's main is the commit checked, not the moved branch" 0 "$checked11" git -C "$W/origin.git" rev-parse main
check "its tag is the commit checked" 0 "$checked11" g rev-parse "upgrade-merged/11-k^{commit}"

# pushed by a run cut short before its tag, then CD pushed on top of it: still a push to take up - the proof check
# compared with origin's main, which is no longer the branch, said "restack it", and the restack made the change empty
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/12-l.txt"
g checkout -q -b upgrade/12-l; echo l >> "$W/infra/f"; g commit -q -am l; g checkout -q main
main12=$(g rev-parse main)
g push -q origin upgrade/12-l:main
git -C "$W/other" pull -q --ff-only origin main
echo cd2 >> "$W/other/g"; git -C "$W/other" commit -q -am cd2; git -C "$W/other" push -q origin main
g fetch -q origin main
check "pushed untagged, CD on top: its change, against the main it went onto, is the proven one" 0 "PROBLEMS: none" \
  proof 12-l "$main12..upgrade/12-l"
check "then taken up: tagged" 0 "pushed already" "$M" 12-l infra take-up
check "its base the main before the push" 0 "base $main12" base_of 12-l

# the tip the caller checked, compared first: a branch that moved on to a commit pushed meanwhile (in origin's main,
# untagged - the take-up's state) was tagged unchecked; take-up takes the tip too
g pull -q --ff-only origin main
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/15-o.txt"
g checkout -q -b upgrade/15-o; echo o >> "$W/infra/f"; g commit -q -am o; checked15=$(g rev-parse HEAD)
echo o2 >> "$W/infra/f"; g commit -q -am o2; g push -q origin upgrade/15-o:main; g checkout -q main
check "the branch moved on to a commit pushed since the tip was checked: refused, not taken up" 1 "moved since" \
  "$M" 15-o infra "$checked15"
check "take-up with the tip checked, the branch moved: refused" 1 "moved since" "$M" 15-o infra take-up "$checked15"
check "nothing tagged" 1 "" g rev-parse -q --verify refs/tags/upgrade-merged/15-o
rm -f "$W/ops/tests/ansible/upgrade/steps/15-o.txt"
# a step's tag there already (merged before): refused before any push - a forced tag moved it, its base another main
g fetch -q origin main; g merge -q --ff-only origin/main
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/13-m.txt"
g checkout -q -b upgrade/13-m; echo m >> "$W/infra/f"; g commit -q -am m; g checkout -q main
g tag -a -m "base earlier" upgrade-merged/13-m "$(g rev-parse main)"
origin13=$(git -C "$W/origin.git" rev-parse main)
check "its tag there already: refused" 1 "exists already" "$M" 13-m infra
check "nothing pushed" 0 "$origin13" git -C "$W/origin.git" rev-parse main
check "its tag unmoved" 0 "base earlier" base_of 13-m
rm -f "$W/ops/tests/ansible/upgrade/steps/13-m.txt"

# the digests a step's branch pins an image tag to, read from the branch (production's prepull pulls the reference
# production runs); a repo the step declares with neither its branch nor its merged tag refuses
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/08-h.txt"
g checkout -q -b upgrade/08-h
printf 'imageName: ghcr.io/x/pg:18.6@sha256:%s\nother: docker.io/y/z:1@sha256:%s\n' "$(printf 'a%.0s' {1..64})" \
  "$(printf 'b%.0s' {1..64})" > "$W/infra/values.yaml"
g add values.yaml; g commit -q -m h; g checkout -q main
pins() {  # pins <step> <name> <tag>: production's lookup of the digests
  W=$W SRC=$src python3 - "$@" <<'PYP'
import importlib.machinery, importlib.util, os, sys
L = importlib.machinery.SourceFileLoader("up", os.path.join(os.environ["SRC"], "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
m.OPS = os.path.join(os.environ["W"], "ops")
m.step_info = lambda step: {"branches": ["infra"]}
print("PINS:", sorted(m.image_pins(*sys.argv[1:])))
PYP
}
check "a tag the branch pins: its digest" 0 "PINS: ['sha256:$(printf 'a%.0s' {1..64})']" pins 08-h ghcr.io/x/pg 18.6
check "a short name, pinned under its docker.io name: found" 0 "PINS: ['sha256:$(printf 'b%.0s' {1..64})']" \
  pins 08-h y/z 1
check "a tag the branch does not pin: none" 0 "PINS: []" pins 08-h ghcr.io/x/pg 17
check "no branch nor tag for the step: refused" 1 "neither upgrade/09-i nor" pins 09-i ghcr.io/x/pg 18.6

# the run's proof-start records every step branch of both repos; a branch moved, made or deleted since - a restack in
# the repos the run reads (2026-10-07: 16 platform branches rewritten under a running full run) - is named
git init -q -b main "$W/platform"; git -C "$W/platform" commit -q --allow-empty -m p
git -C "$W/platform" branch upgrade/20-p
moves() {  # moves <python statements on m, run between the record and the check>
  W=$W SRC=$src ACT=$1 python3 - <<'PYP'
import importlib.machinery, importlib.util, os, subprocess
L = importlib.machinery.SourceFileLoader("up", os.path.join(os.environ["SRC"], "scripts", "upgrade-production.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
m.OPS = os.path.join(os.environ["W"], "ops")
recorded = m.branch_shas()
g = lambda repo, *a: subprocess.run(["git", "-C", os.path.join(os.environ["W"], repo), *a], check=True,
                                    capture_output=True)
exec(os.environ["ACT"])
print("MOVES:", m.branch_moves(recorded) or "none")
PYP
}
check "the branches as recorded: none moved" 0 "MOVES: none" moves "pass"
check "one moved: named" 0 "platform upgrade/20-p:" moves 'g("platform", "commit", "-q", "--allow-empty", "-m", "x");
g("platform", "branch", "-f", "upgrade/20-p")'
check "one made: named" 0 "infra upgrade/99-new: none ->" moves 'g("infra", "branch", "upgrade/99-new", "main")'
check "one deleted: named" 0 "infra upgrade/99-new:" moves 'g("infra", "branch", "-D", "upgrade/99-new")'
echo "upgrade-merge-step: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
exit $((fails > 0))
