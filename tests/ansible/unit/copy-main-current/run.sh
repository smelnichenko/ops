#!/bin/bash
# scripts/copy-main-current.sh on a git fixture (an origin and a clone): main equal to origin/main passes; behind or
# ahead refused; a change's ref containing origin/main passes, one cut from an older main refused, a ref not there
# refused; each repo judged, the run failing on any.
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
check "main = origin/main: passes" "$(run "$W/repo")" 0
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
echo "copy-main-current: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
