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
# Given what the change was to move (a sixth argument, the unit's Renovate tables: "<package> <from> <to>" a line,
# scripts/upgrade-units.py moves): every production line naming a package at its old version must name it at the new one
# on the copy after the change - "moved nothing" passed a unit whose new version never reached the copy (the
# observability review, 2026-11-25: nothing required grafana/grafana 13.3.2 running). A line the allow-list lets the
# copy lack (a Job's image) is not required; a package production names only at another version runs nowhere at the
# old one (a hook Job's image) - nothing to move. A package production names nowhere fails unless
# tests/ansible/copy/moves-names.txt names it - by the lines production calls it (a Pi's service), or as checked
# elsewhere (the runner's own image): no move passes unchecked (the wave-patches review, 2026-11-27). A digest move
# (Renovate's digest rows, a rebuilt tag) is judged on the image-digest lines; a version move's digest line wants the
# new version's line with any digest (the pin's digest moves with its version).
#
# Usage: scripts/copy-change-inventory.sh tests/ansible/copy/prod-inventory.txt .copy/vagrant-inventory-build.txt \
#          .copy/vagrant-inventory-after-change.txt .copy/vagrant-inventory.txt tests/ansible/copy/vagrant-allowed-missing.txt \
#          [the unit's moves]
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
if [ -n "${6:-}" ]; then
  [ -r "$6" ] || { echo "$6: the unit's moves not readable"; exit 1; }
  names=${COPY_MOVES_NAMES:-$here/../tests/ansible/copy/moves-names.txt}
  [ -r "$names" ] || { echo "$names: the moves' names not readable"; exit 1; }
  unmoved=$(python3 -I - "$1" "$3" "$6" "${5:-/dev/null}" "$names" <<'MOVES'
import re, sys
prod, after, moves, allowed, names = (open(p).read().splitlines() for p in sys.argv[1:6])
have = set(after)
# tests/ansible/copy/moves-names.txt: "<package> = <regex>" adds the lines it matches, "<package> - <why>" is checked
# elsewhere; a line of another shape is refused (a typo would pass a move unchecked)
mapped, elsewhere = {}, set()
for n in (x.strip() for x in names):
    if not n or n.startswith("#"):
        continue
    m = re.fullmatch(r"(\S+) = (.+)", n) or re.fullmatch(r"(\S+) - (.+)", n)
    if not m:
        print("  UNREAD tests/ansible/copy/moves-names.txt: '%s'" % n)
        continue
    if " = " in n:
        mapped[m.group(1)] = re.compile(m.group(2))
    else:
        elsewhere.add(m.group(1))
exact, anyver = set(), set()
for a in (x.strip() for x in allowed):
    if a and not a.startswith("#"):
        a = a[2:] if a.startswith("? ") else a
        (anyver.add(a[:-2]) if a.endswith(" *") else exact.add(a))
for pkg, old, new in (m.split() for m in moves if len(m.split()) == 3):
    at = re.compile(r"(?<![\d.])" + re.escape(old) + r"(?![\d.])")
    # an image's digest line left out with its image line
    as_image = lambda x: " ".join(["image"] + x.split()[1:3]) if x.startswith("image-digest ") else x
    left_out = lambda x: any(y in exact or y.rsplit(" ", 1)[0] in anyver for y in (x, as_image(x)))
    digest_move = all(re.fullmatch(r"[0-9a-f]{7}", v) for v in (old, new))
    if pkg in elsewhere:
        continue
    lines = [x for x in prod if (pkg in x or (pkg in mapped and mapped[pkg].search(x))) and at.search(x)]
    if not lines and not any(pkg in x or (pkg in mapped and mapped[pkg].search(x)) for x in prod):
        # production names it nowhere, at no version: a move nothing checks - named in moves-names.txt, or refused
        print("  NOT CHECKED %s %s -> %s: no production line names it - name it in tests/ansible/copy/moves-names.txt" % (pkg, old, new))
        continue
    # a component the copy leaves out (its production line allowed missing) is left out at the new version too; a
    # package production names only at another version runs nowhere at the old one (a hook Job's image): nothing to move
    for line in (x for x in lines if not left_out(x)):
        # moved in any of the old version's places: a chart named for its version beside the same app version moves
        # both (Cilium: cilium-1.20.5 1.20.5), a chart bump alone the first - every subset tried, none required
        spots = [m.span() for m in at.finditer(line)][:8]
        wants = set()
        for mask in range(1, 2 ** len(spots)):
            out, last = [], 0
            for i, (a, b) in enumerate(spots):
                out += [line[last:a], new if mask >> i & 1 else line[a:b]]
                last = b
            wants.add("".join(out) + line[last:])
        if line.startswith("image-digest ") and not digest_move:
            # a version move: the new version's digest line, whatever its digest
            stems = {w.rsplit(" ", 1)[0] for w in wants}
            moved = any(h.startswith("image-digest ") and h.rsplit(" ", 1)[0] in stems for h in have) or any(map(left_out, wants))
        else:
            moved = any(w in have or left_out(w) for w in wants)
        if not moved:
            print("  NOT MOVED %s %s -> %s: the copy lacks '%s'" % (pkg, old, new, at.sub(new, line)))
MOVES
)
  if [ -n "$unmoved" ]; then
    echo "what the unit moves, not on the copy after the change (or never checked):"
    printf '%s\n' "$unmoved"
    echo "INVENTORY: the change did not move what its unit moves"
    bad=1
  fi
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
