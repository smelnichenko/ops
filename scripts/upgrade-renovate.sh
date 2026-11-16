#!/usr/bin/env bash
# The upgrade cycle's Renovate on the workstation - task upgrade's first half (the operator's decisions of 2026-11-15:
# Renovate and the runner one task, started by hand, run locally - no CI cron).
# One run against infra, platform and ops, their policy the shared preset renovate/upgrade-cycle.json: one branch and
# pull request per unit, the same name in each repo. Renovate never merges (automerge off) - the runner proves, applies.
#
# The image pinned exactly; the bot's token (ops/.env RENOVATE_TOKEN) and a GitHub read token (RENOVATE_GITHUB_TOKEN,
# only when set - an empty one sent as a token was a 401, 2026-11-14) passed by name, never on a command line; the
# preset's one post-upgrade command allowed from renovate/allowed-commands.json (python3, gpg and xz are in the image);
# no bind mount - Renovate clones into its own container. Its log in .copy/. Never beside a runner: the runner's lock
# (.upgrade-cycle/lock) held while it runs.
#
# --apps: monitor's and masi's Renovate instead (task renovate:apps) - their dependency pull requests, each repo's own
# renovate.json; the same bot and image, by hand (their weekly Woodpecker cron and its CI-secret token gone,
# 2026-11-16: the token could push to infra, platform and ops from any pipeline).
#
# Usage: scripts/upgrade-renovate.sh [--apps] [--lookup]   --lookup: the repos and registries read, nothing changed
# Env:   RENOVATE_TOKEN (required), RENOVATE_GITHUB_TOKEN, UPGRADE_DOCKER (the harness's docker, default docker)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
image=renovate/renovate:44.198.3
repos=schnappy/infra,schnappy/platform,schnappy/ops
dry=""
for a in "$@"; do
  case "$a" in
    --lookup) dry=lookup ;;
    --apps) repos=schnappy/monitor,schnappy/masi ;;
    *) echo "REFUSED: upgrade-renovate.sh [--apps] [--lookup]" >&2; exit 2 ;;
  esac
done
[ -n "${RENOVATE_TOKEN:-}" ] || { echo "REFUSED: RENOVATE_TOKEN is empty (ops/.env) - Renovate not run" >&2; exit 1; }
# never beside a runner (its lock): Renovate rebasing a unit's branches mid-proof throws the proof away
mkdir -p "$ops/.upgrade-cycle"
exec 9>> "$ops/.upgrade-cycle/lock"
flock -n 9 || { echo "REFUSED: an upgrade run holds $ops/.upgrade-cycle/lock - Renovate not run beside it" >&2; exit 1; }
RENOVATE_ALLOWED_COMMANDS=$(cat "$ops/renovate/allowed-commands.json")
export RENOVATE_TOKEN RENOVATE_ALLOWED_COMMANDS
args=(run --rm -e RENOVATE_TOKEN -e RENOVATE_ALLOWED_COMMANDS
      -e RENOVATE_PLATFORM=forgejo -e RENOVATE_ENDPOINT=https://git.pmon.dev/api/v1/
      -e "RENOVATE_REPOSITORIES=$repos"
      -e "RENOVATE_GIT_AUTHOR=Renovate Bot <renovate-bot@pmon.dev>"
      -e RENOVATE_ONBOARDING=false -e RENOVATE_REQUIRE_CONFIG=required -e LOG_LEVEL=info)
if [ -n "$dry" ]; then args+=(-e RENOVATE_DRY_RUN=lookup); fi
if [ -n "${RENOVATE_GITHUB_TOKEN:-}" ]; then
  GITHUB_COM_TOKEN=$RENOVATE_GITHUB_TOKEN
  export GITHUB_COM_TOKEN
  args+=(-e GITHUB_COM_TOKEN)
fi
mkdir -p "$ops/.copy"
log=$ops/.copy/renovate-$(date +%Y%m%d-%H%M%S)-$$.log
echo "Renovate ${dry:-run} ($image) - its log: $log"
if ! "${UPGRADE_DOCKER:-docker}" "${args[@]}" "$image" > "$log" 2>&1; then
  echo "Renovate FAILED - the last of its log ($log):" >&2
  tail -n 20 "$log" >&2
  exit 1
fi
# a run that logged an error or a fatal ended 0 all the same: its errors said, and the task stops before the runner
if grep -qE '"level":(50|60)|^ *(ERROR|FATAL):' "$log"; then
  echo "Renovate logged errors - the runner not started ($log):" >&2
  grep -E '"level":(50|60)|^ *(ERROR|FATAL):' "$log" | tail -n 20 >&2
  exit 1
fi
# every repository read through: one skipped (no renovate.json on its main - "disabled-no-config" -, an error result)
# left the runner a unit's other halves missing - each repo finished, no result but done
want=$(tr ',' '\n' <<< "$repos" | wc -l)
done_n=$(grep -c 'INFO: Repository finished' "$log" || true)
odd=$(grep -E '"result": "' "$log" | grep -v '"result": "done"' || true)
if [ "$done_n" != "$want" ] || [ -n "$odd" ] || grep -q 'Repository is disabled' "$log"; then
  echo "Renovate did not read every repository ($done_n of $want finished) - the runner not started ($log):" >&2
  grep -E 'Repository is disabled|"result": "' "$log" | tail -n 20 >&2
  exit 1
fi
echo "Renovate done"
