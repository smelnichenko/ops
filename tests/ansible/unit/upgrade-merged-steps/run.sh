#!/bin/bash
# Steps production merged (tagged upgrade-merged/<step> by scripts/upgrade-merge-step.sh) during the rollout: the refs
# check resolves the rest on main, a CD commit on main is put under the remaining steps by the restack, and an unmerged
# step without a change of its own is still refused. In a throwaway tree: ops (the real scripts, three step files) next
# to an infra and a platform repo.
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
g() { git -C "$W/$1" "${@:2}"; }
mkdir -p "$W/ops/scripts" "$W/ops/tests/ansible/upgrade/steps"
cp "$src/scripts/upgrade-expected-inventory.py" "$src/scripts/upgrade-restack-in-place.sh" "$W/ops/scripts/"
for s in 01-a 02-b 03-c; do printf 'branch infra\n' > "$W/ops/tests/ansible/upgrade/steps/$s.txt"; done
for r in infra platform; do
  git init -q -b main "$W/$r"; echo base > "$W/$r/f"; g "$r" add f; g "$r" commit -q -m base
done
g infra checkout -q -b upgrade/01-a; echo a >> "$W/infra/f"; g infra commit -q -am a
g infra checkout -q -b upgrade/02-b; echo b >> "$W/infra/f"; g infra commit -q -am b
g infra checkout -q -b upgrade/03-c; echo c >> "$W/infra/f"; g infra commit -q -am c
g infra checkout -q main
refs() { "$W/ops/scripts/upgrade-expected-inventory.py" --refs "$1"; }
merge() {  # what upgrade-merge-step.sh does after its checks
  local base; base=$(git -C "$W/infra" rev-parse main)
  g infra merge -q --ff-only "upgrade/$1"; g infra tag -a -m "base $base" "upgrade-merged/$1" "upgrade/$1"
}

check "before the rollout: the step's own branch" 0 "upgrade/03-c main" refs 03-c
merge 01-a; merge 02-b
check "01 and 02 merged: 03 resolves on main" 0 "upgrade/03-c main" refs 03-c
check "01 and 02 merged: 02 resolves to main" 0 "main main" refs 02-b
echo cd >> "$W/infra/g"; g infra add g; g infra commit -q -m "deploy(test): app=x"
check "a CD commit on main: 03 refused until restacked" 1 "does not contain main" refs 03-c
check "the restack skips the merged steps and puts 03 on main" 0 "02-b merged - skipped" \
  bash -c "cd '$W/infra' && '$W/ops/scripts/upgrade-restack-in-place.sh' '$W/infra'"
check "after the restack: 03 resolves" 0 "upgrade/03-c main" refs 03-c
g infra branch -q -D upgrade/01-a
check "a merged step's branch deleted after its merge: still resolved (its tag)" 0 "upgrade/03-c main" refs 03-c
g infra branch -q upgrade/01-a upgrade-merged/01-a
check "after the restack: 03 carries its own change and the CD commit" 0 "+c" \
  bash -c "git -C '$W/infra' diff main upgrade/03-c -- f | grep -x '+c' && git -C '$W/infra' merge-base --is-ancestor main upgrade/03-c"
# an unmerged step with no change of its own is in main too: still refused (the tag, not ancestry, marks merged)
g infra branch -f upgrade/03-c main
check "an unmerged empty step: refused" 1 "changes nothing" refs 03-c
# merged out of order (a later step tagged, an earlier one not) and main reset below a merged step: refused
g infra tag -d upgrade-merged/01-a > /dev/null
# 01-a unmerged but on main with a change of its own, 02-b tagged merged
g infra branch -f upgrade/01-a main; g infra checkout -q upgrade/01-a; echo a2 >> "$W/infra/f"; g infra commit -q -am a2
g infra checkout -q main
check "a step merged before the one ahead of it: the refs refuse" 1 "merged out of order" refs 03-c
check "the same: the restack refuses" 1 "merged out of order" \
  bash -c "cd '$W/infra' && '$W/ops/scripts/upgrade-restack-in-place.sh' '$W/infra'"
rm -f "$W/infra/.git/restack-old-shas"
g infra tag -a -m "base x" upgrade-merged/01-a upgrade/01-a
g infra checkout -q --detach; g infra branch -f main upgrade/01-a~1; g infra checkout -q main
check "main reset below a merged step: refused" 1 "is not in main" refs 03-c
echo "upgrade-merged-steps: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
