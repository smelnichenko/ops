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

# someone else moved origin's main: refused
git clone -q "$W/origin.git" "$W/other" 2> /dev/null
echo cd >> "$W/other/g"; git -C "$W/other" add g; git -C "$W/other" commit -q -m cd; git -C "$W/other" push -q origin main
printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/04-d.txt"
g checkout -q -b upgrade/04-d; echo d >> "$W/infra/f"; g commit -q -am d; g checkout -q main
check "origin's main moved by someone else: refused" 1 "main is not origin/main" "$M" 04-d infra
echo "upgrade-merge-step: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
exit $((fails > 0))
