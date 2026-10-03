#!/usr/bin/env bash
# inventory-diff.sh <expected> <actual> [allowed-missing]: diff two version inventories (scripts/version-inventory.sh), ignoring what
# is not infrastructure: application images (git.pmon.dev/schnappy/*), and the image-build tools only the Vagrant node
# has (nerdctl, buildkitd: install_nerdctl_override). Exits non-zero when anything else differs.
set -euo pipefail
filter() {
  grep -v -E '^image git\.pmon\.dev/schnappy/|^binary /usr/local/bin/(nerdctl|buildkitd) ' "$1" | LC_ALL=C sort -u
}
# optional third argument: lines of <expected> that may be missing from <actual> (comments allowed), never different.
# Only the ones <actual> lacks are skipped: one that is there is compared like any other (2026-10-03: a job pod's image
# present in the Vagrant copy - its CronJob had run - counted as an extra line).
allowed=${3:-/dev/null}
actual=$(filter "$2")
skipped=$(LC_ALL=C comm -23 <(grep -v -E '^\s*(#|$)' "$allowed" | LC_ALL=C sort -u) <(printf '%s\n' "$actual"))
expected=$(LC_ALL=C comm -23 <(filter "$1") <(printf '%s\n' "$skipped"))
if diff -u --label expected --label actual <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"); then
  echo "inventories match ($(printf '%s\n' "$expected" | wc -l) lines; $(printf '%s\n' "$skipped" | grep -c . || true) allowed missing)"
else
  echo "inventories DIFFER (- expected, + actual)"; exit 1
fi
