#!/usr/bin/env bash
# inventory-diff.sh <expected> <actual> [allowed-missing]: diff two version inventories (scripts/version-inventory.sh),
# ignoring what is not infrastructure: the application images CD moves (git.pmon.dev/schnappy/<app>), and the
# image-build tools only the Vagrant node has (nerdctl, buildkitd: install_nerdctl_override). Exits non-zero when
# anything else differs - except a CRD more (crd-name lines): upgrades add CRDs; one missing fails like any line.
# Infrastructure built in git.pmon.dev (apt-cacher-ng) is compared: every git.pmon.dev/schnappy/ image was filtered,
# and the apt-cacher-ng step passed with it still on 1.0.
set -euo pipefail
filter() {
  local apps='^image git\.pmon\.dev/schnappy/(admin|chat|chess|game-scp|hyperfoil|masi|monitor|site) '
  local tools='^binary /usr/local/bin/(nerdctl|buildkitd) '
  { grep -v -E "$apps|$tools" "$1" || true; } \
    | LC_ALL=C sort -u
}
# optional third argument: lines of <expected> that may be missing from <actual> (comments allowed), never different.
# A line ending in ` *` allows any version of it (all but its last field the same): a left-out component production
# upgrades stays left out. A line starting `? ` is a Job's image either side may have or not (kept a day after each
# sync: production read a quiet day later lacks it, the copy just synced has it) - missing or extra, never judged. Only the ones <actual> lacks are skipped: one that is there is compared like any other
# (2026-10-03: a job pod's image present in the Vagrant copy - its CronJob had run - counted as an extra line).
allowed=${3:-/dev/null}
actual=$(filter "$2")
# the `? ` lines' matches the copy has and production does not: left out too (the other way round is the skip below)
maybe() {  # the lines of stdin a `? ` entry names (exactly, or by all but the version with ` *`)
  awk 'NR == FNR { if (sub(/^\? /, "")) { if ($NF == "*") { sub(/ \*$/, ""); any[$0] = 1 } else exact[$0] = 1 }; next }
       { p = $0; sub(/ [^ ]*$/, "", p); if (($0 in exact) || (p in any)) print }' \
    <(grep -v -E '^\s*(#|$)' "$allowed") - | LC_ALL=C sort -u
}
extra_maybe=$(LC_ALL=C comm -13 <(filter "$1") <(printf '%s\n' "$actual") | maybe)
actual=$(LC_ALL=C comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$extra_maybe"))
# CRDs the expected inventory does not name: listed, then left out of the comparison
new_crds=$(LC_ALL=C comm -13 <(filter "$1" | grep '^crd-name ' || true) \
  <(printf '%s\n' "$actual" | grep '^crd-name ' || true))
[ -z "$new_crds" ] || echo "new CRDs (allowed): $(printf '%s\n' "$new_crds" | cut -d' ' -f2 | paste -sd' ')"
actual=$(LC_ALL=C comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$new_crds"))
# the expected lines the copy lacks that the allow-list names - exactly, or by all but the version (`... *`)
missing=$(LC_ALL=C comm -23 <(filter "$1") <(printf '%s\n' "$actual"))
skipped=$(awk 'NR == FNR { sub(/^\? /, ""); if ($NF == "*") { sub(/ \*$/, ""); any[$0] = 1 } else exact[$0] = 1; next }
               { p = $0; sub(/ [^ ]*$/, "", p); if (($0 in exact) || (p in any)) print }' \
  <(grep -v -E '^\s*(#|$)' "$allowed") <(printf '%s\n' "$missing" | grep . || true) | LC_ALL=C sort -u)
expected=$(LC_ALL=C comm -23 <(filter "$1") <(printf '%s\n' "$skipped"))
if diff -u --label expected --label actual <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"); then
  n_skipped=$(printf '%s\n' "$skipped" | grep -c . || true)
  echo "inventories match ($(printf '%s\n' "$expected" | wc -l) lines; $n_skipped allowed missing)"
else
  echo "inventories DIFFER (- expected, + actual)"; exit 1
fi
