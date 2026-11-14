#!/usr/bin/env bash
# The upgrade cycle's record of an applied unit (docs/plans/120-automated-upgrade-cycle.md, part 2 step 9):
# docs/upgrades/<date>-<unit>.md - the unit, its night's steps (the log's RUN/PICK/APPLIED lines) and production's
# inventory as read after it (tests/ansible/copy/prod-inventory.txt, its diff) - committed to ops main as the
# renovate-bot and pushed, [CI SKIP] (docs and the inventory record only).
# Usage: scripts/upgrade-record.sh <unit> <night's log>
# Env:   UPGRADE_FORGEJO_TOKEN (the bot's PAT: the push), UPGRADE_RECORD_REMOTE (default git.pmon.dev/schnappy/ops.git),
#        UPGRADE_RECORD_NO_PUSH=1 (commit only - the harness's)
set -euo pipefail
export LC_ALL=C
unit=${1:-}; log=${2:-}
[[ $unit =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "REFUSED: upgrade-record.sh <unit> <log> - not '$unit'"; exit 2; }
[ -r "$log" ] || { echo "REFUSED: the night's log '$log' not readable"; exit 2; }
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
day=$(date -u +%Y-%m-%d)
rec="docs/upgrades/$day-$unit.md"
mkdir -p docs/upgrades
{
  echo "# $unit - applied $day"
  echo
  echo "The upgrade cycle's night (docs/plans/120-automated-upgrade-cycle.md): proven on the Vagrant copy, reviewed,"
  echo "applied, verified."
  echo
  echo "## The night"
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
git add -- "$rec" tests/ansible/copy/prod-inventory.txt
git -c user.name="Renovate Bot" -c user.email=renovate-bot@pmon.dev commit -q -m "upgrade cycle: $unit applied $day [CI SKIP]"
echo "RECORDED $rec"
[ -z "${UPGRADE_RECORD_NO_PUSH:-}" ] || exit 0
[ -n "${UPGRADE_FORGEJO_TOKEN:-}" ] || { echo "NOT PUSHED: no UPGRADE_FORGEJO_TOKEN"; exit 1; }
# the token through git's credential helper, never on a command line
git -c credential.helper= -c "credential.helper=!f() { test \"\$1\" = get && printf 'username=renovate-bot\\npassword=%s\\n' \"\$UPGRADE_FORGEJO_TOKEN\"; }; f" \
  push -q "https://${UPGRADE_RECORD_REMOTE:-git.pmon.dev/schnappy/ops.git}" HEAD:main
echo "PUSHED"
