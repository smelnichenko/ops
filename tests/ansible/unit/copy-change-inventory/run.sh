#!/bin/bash
# scripts/copy-change-inventory.sh: the copy's inventory after a change, judged from the build - what the change moved
# (different from production after it, not at the build) printed and passed, alone even where the build's copy was
# stale in another line it mends; a difference the build had too failing (production moved since), named apart; what
# the checks changed after the change settled failing (a leftover); a comparison with no verdict (inventory-diff.sh
# crashed) failing, never "nothing moved"; any inventory missing refused; inventory-diff.sh's own rules (apps' images,
# allowed-missing) holding on each side.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
S=scripts/copy-change-inventory.sh
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
printf '%s\n' 'image a/velero v1.18.4' 'image b/redis 8.1' 'argo-chart velero velero@12.2.0' 'image c/left-out v1' > "$W/prod"
printf '%s\n' 'image c/left-out v1' > "$W/allowed"
same() { grep -v 'c/left-out' "$W/prod"; }
same > "$W/build"
# the change moves Velero's image and chart; the checks change nothing
same | sed 's#v1.18.4#v1.19.0#; s#velero@12.2.0#velero@13.0.0#' > "$W/changed"
run() { out=$(bash "$S" "$@" 2>&1); }  # its output in $out, its exit its own
run "$W/prod" "$W/build" "$W/changed" "$W/changed" "$W/allowed"; rc=$?
check "a change's own differences: printed, passed, said" \
  "$rc $(grep -c '^  +image a/velero v1.19.0$' <<< "$out") $(grep -c '^  -image a/velero v1.18.4$' <<< "$out") $(grep -c "^INVENTORY: production's but for the change's own lines$" <<< "$out")" \
  "0 1 1 1"
check "  the allowed-missing line not reported" "$(grep -c 'left-out' <<< "$out")" 0
run "$W/prod" "$W/build" "$W/build" "$W/build" "$W/allowed"; rc=$?
check "no change in the inventory: said, passed" "$rc $(grep -c 'moved nothing' <<< "$out")" "0 1"
# production moved since the build: redis read at 8.0 then (the build matched it), 8.1 now
same | sed 's#redis 8.1#redis 8.0#' > "$W/stale"
same | sed 's#redis 8.1#redis 8.0#; s#v1.18.4#v1.19.0#' > "$W/stale-changed"
run "$W/prod" "$W/stale" "$W/stale-changed" "$W/stale-changed" "$W/allowed"; rc=$?
check "a difference the build had too: failed, named apart from the change's" \
  "$rc $(sed -n '/at its build too/,$p' <<< "$out" | grep -c 'redis 8.0') $(sed -n '/own differences/,/at its build too/p' <<< "$out" | grep -c 'velero v1.19.0') $(grep -c 'production moved since' <<< "$out")" \
  "1 1 1 1"
# the change mends the stale line and moves another: both its own, passed - the comparison's header lines no part of it
same | sed 's#v1.18.4#v1.19.0#' > "$W/mends"
run "$W/prod" "$W/stale" "$W/mends" "$W/mends" "$W/allowed"; rc=$?
check "a change that mends one stale line and moves another: its own alone, passed" \
  "$rc $(grep -c -e 'expected$' -e 'actual$' <<< "$out")" "0 0"
# a check's leftover: a Job image there after the checks, not right after the change
{ cat "$W/changed"; echo 'image d/kopia 0.16.0'; } > "$W/leftover"
run "$W/prod" "$W/build" "$W/changed" "$W/leftover" "$W/allowed"; rc=$?
check "a check's leftover (after the change settled): failed, named" \
  "$rc $(grep -c '^  +image d/kopia 0.16.0' <<< "$out") $(grep -c "a check's leftovers" <<< "$out")" "1 1 1"
# a comparison that gave no verdict: failed, never "nothing moved"
mkdir -p "$W/broken/scripts"; cp "$S" "$W/broken/scripts/"
printf '#!/bin/bash\nexit 3\n' > "$W/broken/scripts/inventory-diff.sh"; chmod +x "$W/broken/scripts/inventory-diff.sh"
out=$(bash "$W/broken/scripts/copy-change-inventory.sh" "$W/prod" "$W/build" "$W/build" "$W/build" 2>&1); rc=$?
check "inventory-diff.sh crashing (no verdict): failed, said - not 'moved nothing'" \
  "$rc $(grep -c 'gave no verdict' <<< "$out") $(grep -c 'moved nothing' <<< "$out")" "1 1 0"
for i in 1 2 3 4; do
  a=("$W/prod" "$W/build" "$W/changed" "$W/changed"); a[$((i - 1))]=$W/nothing
  run "${a[@]}"; rc=$?
  check "inventory $i of 4 missing: refused" "$rc $(grep -c 'no inventory' <<< "$out")" "1 1"
done
run "$W/prod" "$W/build" "$W/changed"; rc=$?
check "fewer than four inventories: usage (exit 2)" "$rc" 2
echo "copy-change-inventory: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
