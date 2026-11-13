#!/usr/bin/env bash
# copy-change-inventory.sh <production> <the copy built> <the copy changed> <the copy now> [allowed-missing] - the
# Vagrant copy's version inventory after a change (test:copy:change, test:copy:playbook), three judgments:
#   - against production, from the build on (scripts/inventory-diff.sh's comparison, each side): a difference the built
#     copy had too is no part of the change - production moved since the build (its inventory read again), and the copy
#     no longer is it: fails, rebuild;
#   - what the change itself moved (a difference after it, not at the build) is printed for review and passes: no
#     expected inventory says what a change should move (the upgrade step files did; they are gone). A change applied
#     again, or one on top of another, is judged from the build the same way;
#   - the checks after it (the copy now, against the copy right after the change settled): exactly the same - what a
#     check left behind (a Job, a pod, an image) fails, as it does after a build.
# Each comparison must have run: inventory-diff.sh's verdict line read, or the run fails (a crash is no "no difference").
#
# Usage: scripts/copy-change-inventory.sh tests/ansible/copy/prod-inventory.txt .copy/vagrant-inventory-build.txt \
#          .copy/vagrant-inventory-after-change.txt .copy/vagrant-inventory.txt tests/ansible/copy/vagrant-allowed-missing.txt
set -euo pipefail
[ "$#" -ge 4 ] || { echo "usage: $0 <production> <built> <changed> <now> [allowed-missing]"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
for f in "$1" "$2" "$3" "$4"; do [ -s "$f" ] || { echo "$f: no inventory"; exit 1; }; done
# inventory-diff.sh's output and its verdict, which must be one it gives: matched (0) or differ (1)
compare() {  # compare <expected> <actual> [allowed] -> output in $cmp_out, verdict in $cmp_rc
  cmp_rc=0
  cmp_out=$("$here/inventory-diff.sh" "$1" "$2" "${3:-/dev/null}" 2>&1) || cmp_rc=$?
  if ! { [ "$cmp_rc" = 0 ] && grep -q '^inventories match' <<< "$cmp_out"; } \
    && ! { [ "$cmp_rc" = 1 ] && grep -q '^inventories DIFFER' <<< "$cmp_out"; }; then
    { echo "inventory-diff.sh $1 $2 gave no verdict (exit $cmp_rc):"; sed 's/^/  /' <<< "$cmp_out"; } >&2
    exit 1
  fi
}
# the differing lines of one comparison (- the expected side's, + the actual side's)
differs() {
  compare "$@"
  { grep -E '^[-+]' <<< "$cmp_out" || true; } | { grep -v -E '^(---|\+\+\+) (expected|actual)$' || true; } \
    | LC_ALL=C sort -u
}
before=$(differs "$1" "$2" "${5:-}")
after=$(differs "$1" "$3" "${5:-}")
own=$(LC_ALL=C comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | { grep . || true; })
old=$(LC_ALL=C comm -12 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | { grep . || true; })
bad=0
if [ -n "$own" ]; then
  echo "the change's own differences from production (- production, + the copy; for review, not judged):"
  sed 's/^/  /' <<< "$own"
else
  echo "the change moved nothing in the inventory"
fi
if [ -n "$old" ]; then
  echo "differences from production the copy had at its build too (- production, + the copy) - not the change's:"
  sed 's/^/  /' <<< "$old"
  echo "INVENTORY: production moved since the copy was built - rebuild it (task test:copy:build)"
  bad=1
fi
compare "$3" "$4"
if [ "$cmp_rc" != 0 ]; then
  echo "the checks after the change left the copy changed (- right after the change, + now):"
  sed 's/^/  /' <<< "$cmp_out"
  echo "INVENTORY: a check's leftovers"
  bad=1
fi
[ "$bad" = 0 ] && echo "INVENTORY: production's but for the change's own lines"
exit "$bad"
