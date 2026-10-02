#!/usr/bin/env bash
# inventory-diff.sh <expected> <actual>: diff two version inventories (scripts/version-inventory.sh), ignoring what
# is not infrastructure: application images (git.pmon.dev/schnappy/*), and the image-build tools only the Vagrant node
# has (nerdctl, buildkitd: install_nerdctl_override). Exits non-zero when anything else differs.
set -euo pipefail
filter() {
  grep -v -E '^image git\.pmon\.dev/schnappy/|^binary /usr/local/bin/(nerdctl|buildkitd) ' "$1" | LC_ALL=C sort -u
}
if diff -u --label expected --label actual <(filter "$1") <(filter "$2"); then
  echo "inventories match ($(filter "$1" | wc -l) lines)"
else
  echo "inventories DIFFER (- expected, + actual)"; exit 1
fi
