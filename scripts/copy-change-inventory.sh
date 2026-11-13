#!/usr/bin/env bash
# copy-change-inventory.sh <production> <copy before the change> <copy after it> [allowed-missing] - the copy's version
# inventory after a change (test:copy:change), against production's (scripts/inventory-diff.sh's comparison, each
# side): a difference the copy had before the change too is no part of it - the copy was not production when the
# change came (a stale copy, production moved on, a check's leftover) - and fails; what the change itself moved (a
# difference after it, not before) is printed for review and passes: no expected inventory says what a change should
# move (the upgrade step files did; they are gone).
#
# Usage: scripts/copy-change-inventory.sh tests/ansible/copy/prod-inventory.txt .copy/vagrant-inventory-before-change.txt \
#          .copy/vagrant-inventory.txt tests/ansible/copy/vagrant-allowed-missing.txt
set -euo pipefail
[ "$#" -ge 3 ] || { echo "usage: $0 <production> <before> <after> [allowed-missing]"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
for f in "$1" "$2" "$3"; do [ -s "$f" ] || { echo "$f: no inventory"; exit 1; }; done
# the differing lines of one side (- production's, + the copy's), from inventory-diff.sh's unified diff
differs() {
  { "$here/inventory-diff.sh" "$1" "$2" "${3:-/dev/null}" || true; } \
    | { grep -E '^[-+]' || true; } | { grep -v -E '^(---|\+\+\+) (expected|actual)$' || true; } | LC_ALL=C sort -u
}
before=$(differs "$1" "$2" "${4:-}")
after=$(differs "$1" "$3" "${4:-}")
own=$(LC_ALL=C comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | { grep . || true; })
old=$(LC_ALL=C comm -12 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | { grep . || true; })
if [ -n "$own" ]; then
  echo "the change's own differences from production (- production, + the copy; for review, not judged):"
  sed 's/^/  /' <<< "$own"
else
  echo "the change moved nothing in the inventory"
fi
if [ -n "$old" ]; then
  echo "differences from production the copy had BEFORE the change (- production, + the copy) - not the change's:"
  sed 's/^/  /' <<< "$old"
  echo "INVENTORY: the copy was not production when the change came - rebuild it (task test:copy:build)"
  exit 1
fi
echo "INVENTORY: production's but for the change's own lines"
