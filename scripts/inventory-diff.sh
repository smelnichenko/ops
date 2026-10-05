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
# Only the ones <actual> lacks are skipped: one that is there is compared like any other (2026-10-03: a job pod's image
# present in the Vagrant copy - its CronJob had run - counted as an extra line).
allowed=${3:-/dev/null}
actual=$(filter "$2")
# CRDs the expected inventory does not name: listed, then left out of the comparison
new_crds=$(LC_ALL=C comm -13 <(filter "$1" | grep '^crd-name ' || true) \
  <(printf '%s\n' "$actual" | grep '^crd-name ' || true))
[ -z "$new_crds" ] || echo "new CRDs (allowed): $(printf '%s\n' "$new_crds" | cut -d' ' -f2 | paste -sd' ')"
actual=$(LC_ALL=C comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$new_crds"))
skipped=$(LC_ALL=C comm -23 <(grep -v -E '^\s*(#|$)' "$allowed" | LC_ALL=C sort -u) <(printf '%s\n' "$actual"))
expected=$(LC_ALL=C comm -23 <(filter "$1") <(printf '%s\n' "$skipped"))
if diff -u --label expected --label actual <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"); then
  n_skipped=$(printf '%s\n' "$skipped" | grep -c . || true)
  echo "inventories match ($(printf '%s\n' "$expected" | wc -l) lines; $n_skipped allowed missing)"
else
  echo "inventories DIFFER (- expected, + actual)"; exit 1
fi
