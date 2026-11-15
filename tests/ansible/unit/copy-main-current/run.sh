#!/bin/bash
# scripts/copy-main-current.sh on a git fixture (an origin and a clone): main equal to origin/main passes; behind or
# ahead refused; a change's ref containing origin/main passes, one cut from an older main refused, a ref not there
# refused; each repo judged, the run failing on any; behind by CD's app promotions alone (their author, their files, a
# change editing CD's file too) passes - anything else in between refused.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
S=$PWD/scripts/copy-main-current.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
g() { git -c user.name=t -c user.email=t@t "$@" > /dev/null 2>&1; }
g init -q -b main "$W/origin" && g -C "$W/origin" commit -q --allow-empty -m one
g clone -q "$W/origin" "$W/repo"
g -C "$W/repo" branch old-change && g -C "$W/repo" checkout -q old-change && g -C "$W/repo" commit -q --allow-empty -m c0
g -C "$W/repo" checkout -q main
run() { out=$(bash "$S" "$@" 2>&1); echo "$?"; }
said() { bash "$S" "$@" 2>&1 | tail -1; }  # the last repo's line
check "main = origin/main: passes" "$(run "$W/repo")" 0
check "  said so" "$(said "$W/repo" | grep -c '= origin/main$')" 1
g -C "$W/origin" commit -q --allow-empty -m two
check "main behind origin/main: refused" "$(run "$W/repo")" 1
g -C "$W/repo" pull -q --ff-only
check "  pulled: passes" "$(run "$W/repo")" 0
g -C "$W/repo" commit -q --allow-empty -m local
check "main ahead of origin/main: refused" "$(run "$W/repo")" 1
g -C "$W/repo" checkout -q -b change origin/main && g -C "$W/repo" commit -q --allow-empty -m c1
check "a change cut from origin/main: passes" "$(run "$W/repo:change")" 0
check "a change cut from an older main: refused" "$(run "$W/repo:old-change")" 1
check "a ref not there: refused" "$(run "$W/repo:nosuch")" 1
check "two repos, one stale: the run fails" "$(run "$W/repo:change" "$W/repo:old-change")" 1
check "no repo given: usage (exit 2)" "$(run)" 2
check "each verdict said: a change containing origin/main" "$(said "$W/repo:change" | grep -c 'change contains origin/main')" 1
check "  one cut from an older main" "$(said "$W/repo:old-change" | grep -c 'does not contain origin/main')" 1
check "  a ref not there, or not a commit (a tree)" \
  "$(said "$W/repo:nosuch" | grep -c 'no ref nosuch') $(said "$W/repo:change^{tree}" | grep -c 'no ref')" "1 1"
check "  main ahead of origin/main" "$(said "$W/repo" | grep -c 'bring main to origin/main first')" 1
# production's main moved since the copy was built: the change passes, warned with the count
export COPY_BUILT_FILE=$W/built
echo "repo $(git -C "$W/repo" rev-parse origin/main)" > "$W/built"
check "  production's main where the build had it: no warning" "$(bash "$S" "$W/repo:change" 2>&1 | grep -c WARNING)" 0
g -C "$W/origin" commit -q --allow-empty -m three
g -C "$W/repo" fetch -q origin && g -C "$W/repo" branch -q -f change2 origin/main
out=$(bash "$S" "$W/repo:change2" 2>&1); rc=$?
check "  production's main moved 1 commit since the build: passes, warned" \
  "$rc $(grep -c "moved 1 commit(s) since the copy was built" <<< "$out")" "0 1"
unset COPY_BUILT_FILE
# CD's app promotions alone since (its author, its files): no stale base - a main, or a change (one editing CD's file
# too), passes; anything else in between, another author, another file: refused
export COPY_CD_FILE=$W/cd.json
printf '{"author": "cd@x", "paths": {"repo": ["apps.yaml"]}}' > "$W/cd.json"
cdc() {  # cdc <author> <file> <message>: a commit on origin/main
  g -C "$W/origin" -c user.email="$1" commit -q --allow-empty -m "$3" && echo "$3" > "$W/origin/$2" \
    && g -C "$W/origin" add "$2" && g -C "$W/origin" -c user.email="$1" commit -q --amend -m "$3"
}
g -C "$W/repo" fetch -q origin && g -C "$W/repo" checkout -q --detach && g -C "$W/repo" branch -q -f main origin/main \
  && g -C "$W/repo" checkout -q main  # main where origin's is (the earlier case left a local commit on it)
g -C "$W/repo" branch -q -f unit origin/main && g -C "$W/repo" checkout -q unit && echo v2 > "$W/repo/chart.yaml" \
  && g -C "$W/repo" add chart.yaml && g -C "$W/repo" commit -q -m unit && g -C "$W/repo" checkout -q main
cdc cd@x apps.yaml "promote(prod): app=1"; cdc cd@x apps.yaml "deploy(test): app=2"
g -C "$W/repo" fetch -q origin
out=$(bash "$S" "$W/repo" 2>&1); rc=$?
check "local main behind origin/main by CD's promotions alone: passes, said" "$rc $(grep -c 'by 2 CD promotion(s) alone' <<< "$out")" "0 1"
out=$(bash "$S" "$W/repo:unit" 2>&1); rc=$?
check "a change behind origin/main by CD's promotions alone, their file untouched: passes, said" \
  "$rc $(grep -c 'by 2 CD promotion(s) alone' <<< "$out")" "0 1"
g -C "$W/repo" branch -q -f unit-apps unit && g -C "$W/repo" checkout -q unit-apps && echo mine > "$W/repo/apps.yaml" \
  && g -C "$W/repo" add apps.yaml && g -C "$W/repo" commit -q -m touches && g -C "$W/repo" checkout -q main
check "  a change editing CD's file itself (another line - k6's image beside the tags): passes (the merge judges where they meet)" \
  "$(run "$W/repo:unit-apps")" 0
cdc cd@x other.yaml "promote(prod): not only tags"
g -C "$W/repo" fetch -q origin
check "  a CD commit touching another file: refused (main and change)" "$(run "$W/repo") $(run "$W/repo:unit")" "1 1"
g -C "$W/repo" merge -q --ff-only origin/main && g -C "$W/repo" rebase -q origin/main unit 2> /dev/null; g -C "$W/repo" checkout -q main
cdc someone@x apps.yaml "hand edit"
g -C "$W/repo" fetch -q origin
check "  another author's commit to CD's file: refused (main and change)" "$(run "$W/repo") $(run "$W/repo:unit")" "1 1"
printf '{"author": "cd@x", "paths": {}}' > "$W/cd.json"
g -C "$W/repo" merge -q --ff-only origin/main && g -C "$W/repo" rebase -q origin/main unit 2> /dev/null; g -C "$W/repo" checkout -q main
cdc cd@x apps.yaml "promote(prod): app=3"
g -C "$W/repo" fetch -q origin
check "  a repo with no CD files listed: behind is refused" "$(run "$W/repo")" 1
rm "$W/cd.json"
check "  the CD file unreadable: refused (fails closed)" "$(run "$W/repo")" 1
unset COPY_CD_FILE
g -C "$W/repo" remote set-url origin "$W/nowhere"
check "origin unreachable: refused (not judged on a stale origin/main)" "$([ "$(run "$W/repo:change")" != 0 ] && echo refused)" refused
echo "copy-main-current: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
