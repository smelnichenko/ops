#!/bin/bash
# scripts/copy-change-inventory.sh: the copy's inventory after a change against production's - what the change moved
# (different after, not before) printed and passed; a difference the copy had before the change too failing, named;
# no change at all said; an inventory missing refused. inventory-diff.sh's own rules (apps' images, allowed-missing)
# hold on both sides.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
printf '%s\n' 'image a/velero v1.18.4' 'image b/redis 8.1' 'argo-chart velero velero@12.2.0' 'image c/left-out v1' > "$W/prod"
printf '%s\n' 'image c/left-out v1' > "$W/allowed"
same() { grep -v 'c/left-out' "$W/prod"; }
same > "$W/before"
# the change moves Velero's image and chart
same | sed 's#v1.18.4#v1.19.0#; s#velero@12.2.0#velero@13.0.0#' > "$W/after"
out=$(bash scripts/copy-change-inventory.sh "$W/prod" "$W/before" "$W/after" "$W/allowed" 2>&1); rc=$?
check "a change's own differences: printed, passed" \
  "$rc $(grep -c '^  +image a/velero v1.19.0$' <<< "$out") $(grep -c '^  -image a/velero v1.18.4$' <<< "$out") $(grep -c 'own differences' <<< "$out")" \
  "0 1 1 1"
check "  the allowed-missing line not reported" "$(grep -c 'left-out' <<< "$out")" 0
out=$(bash scripts/copy-change-inventory.sh "$W/prod" "$W/before" "$W/before" "$W/allowed" 2>&1); rc=$?
check "no change in the inventory: said, passed" "$rc $(grep -c 'moved nothing' <<< "$out")" "0 1"
# the copy was not production before the change: redis on another version before and after
same | sed 's#redis 8.1#redis 8.0#' > "$W/stale"
same | sed 's#redis 8.1#redis 8.0#; s#v1.18.4#v1.19.0#' > "$W/stale-after"
out=$(bash scripts/copy-change-inventory.sh "$W/prod" "$W/stale" "$W/stale-after" "$W/allowed" 2>&1); rc=$?
check "a difference the copy had before the change: failed, named apart from the change's" \
  "$rc $(sed -n '/BEFORE the change/,$p' <<< "$out" | grep -c 'redis 8.0') $(sed -n '/own differences/,/BEFORE/p' <<< "$out" | grep -c 'velero v1.19.0')" \
  "1 1 1"
# the stale difference the change itself mends: the change's (it moved it), passed
out=$(bash scripts/copy-change-inventory.sh "$W/prod" "$W/stale" "$W/before" "$W/allowed" 2>&1); rc=$?
check "a stale difference the change mends: the change's own, passed" "$rc" 0
out=$(bash scripts/copy-change-inventory.sh "$W/prod" "$W/nothing" "$W/after" 2>&1); rc=$?
check "an inventory missing: refused" "$rc $(grep -c 'no inventory' <<< "$out")" "1 1"
echo "copy-change-inventory: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
