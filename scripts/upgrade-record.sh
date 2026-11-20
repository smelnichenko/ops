#!/usr/bin/env bash
# The upgrade cycle's record of an applied unit: docs/upgrades/<date>-<unit>.md - the unit, its run's steps (the log's
# RUN/PICK/APPLIED lines) and production's inventory as read after it (tests/ansible/copy/prod-inventory.txt, its diff;
# the Pis' versions, pi-versions.yml) - committed to ops main as the renovate-bot and pushed. CI runs on it: ops' merge
# commit skips its own (its inventory not read yet, defaults-follow-production red by design), this one - the merge and
# the inventory together - is the tree judged. Only those paths are committed (a commit of the whole index pushed
# whatever else was staged, as the bot).
# Usage: scripts/upgrade-record.sh <unit> <the run's log>
# Env:   UPGRADE_FORGEJO_TOKEN (the bot's PAT: the push), UPGRADE_RECORD_REMOTE (default git.pmon.dev/schnappy/ops.git),
#        UPGRADE_RECORD_NO_PUSH=1 (commit only - the harness's)
set -euo pipefail
export LC_ALL=C
unit=${1:-}; log=${2:-}
[[ $unit =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "REFUSED: upgrade-record.sh <unit> <log> - not '$unit'"; exit 2; }
[ -r "$log" ] || { echo "REFUSED: the run's log '$log' not readable"; exit 2; }
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
day=$(date -u +%Y-%m-%d)
rec="docs/upgrades/$day-$unit.md"
mkdir -p docs/upgrades
{
  echo "# $unit - applied $day"
  echo
  # what the run did, as its pick says: a test environment's unit is merged and verified there - no copy, no review
  # (its record said "proven on the Vagrant copy, reviewed" all the same, test-observability 2026-11-17)
  if grep -qE ' PICK test ' "$log"; then
    echo "The upgrade cycle's run (task upgrade:run): the test environment's unit - merged, the test environment verified; no copy, no review."
  else
    echo "The upgrade cycle's run (task upgrade:run): proven on the Vagrant copy, reviewed, applied, verified."
  fi
  echo
  echo "## The run"
  echo
  echo '```'
  grep -E ' (PICK|RUN|RED|NOTICED|APPLIED|BLOCKED) ' "$log" | sed -E 's/(TOKEN|PASSWORD|token|password)=[^ ]*/\1=***/g'
  echo '```'
  echo
  echo "## Production's inventory after it"
  echo
  echo '```diff'
  git diff -- tests/ansible/copy/prod-inventory.txt | grep -E '^[-+][^-+]' || echo "(no change read)"
  echo '```'
} > "$rec"
paths=("$rec" tests/ansible/copy/prod-inventory.txt)
[ ! -e tests/ansible/copy/pi-versions.yml ] || paths+=(tests/ansible/copy/pi-versions.yml)
git add -- "${paths[@]}"
git -c user.name="Renovate Bot" -c user.email=renovate-bot@pmon.dev commit -q -m "upgrade cycle: $unit applied $day" -- "${paths[@]}"
echo "RECORDED $rec"
[ -z "${UPGRADE_RECORD_NO_PUSH:-}" ] || exit 0
[ -n "${UPGRADE_FORGEJO_TOKEN:-}" ] || { echo "NOT PUSHED: no UPGRADE_FORGEJO_TOKEN"; exit 1; }
# the token through git's credential helper, never on a command line
git -c credential.helper= -c "credential.helper=!f() { test \"\$1\" = get && printf 'username=renovate-bot\\npassword=%s\\n' \"\$UPGRADE_FORGEJO_TOKEN\"; }; f" \
  push -q "https://${UPGRADE_RECORD_REMOTE:-git.pmon.dev/schnappy/ops.git}" HEAD:main
echo "PUSHED"
