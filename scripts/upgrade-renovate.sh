#!/usr/bin/env bash
# The upgrade cycle's Renovate on the workstation - task upgrade:run's first half, task upgrade:check its --lookup (2026-11-15:
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
# --apps: the app repos' Renovate instead (task upgrade:apps:run; upgrade:apps:check its --lookup) - their dependency
# pull requests, each repo's renovate.json extending renovate/apps.json; the same bot and image, by hand (monitor's and
# masi's weekly Woodpecker cron and its CI-secret token gone, 2026-11-16: the token could push to infra, platform and
# ops from any pipeline). Since 2026-11-21 every app repo and the CI tool images (ci-tools, ansible-lint, sonar-scanner,
# hyperfoil - their PRs never merge themselves but ci-tools'): the bot has write on each (it pushes renovate/* branches).
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
    --apps) repos=schnappy/admin,schnappy/ansible-lint,schnappy/chat,schnappy/chess,schnappy/ci-tools,schnappy/hyperfoil,schnappy/masi,schnappy/monitor,schnappy/radar,schnappy/radio-scheduler,schnappy/site,schnappy/sonar-scanner,schnappy/target-scorer ;;
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
# a lookup prints what it found: Renovate's report written in the container (no bind mount) and printed after it, behind a
# marker; summarised below by scripts/upgrade-report.py (its log alone shows nothing of the updates at info level)
cmd=()
if [ -n "$dry" ]; then
  args+=(-e RENOVATE_DRY_RUN=lookup -e RENOVATE_REPORT_TYPE=file -e RENOVATE_REPORT_PATH=/tmp/renovate-report.json)
  cmd=(sh -c 'renovate; rc=$?; echo "=== renovate report ==="; cat /tmp/renovate-report.json 2> /dev/null; exit $rc')
fi
if [ -n "${RENOVATE_GITHUB_TOKEN:-}" ]; then
  GITHUB_COM_TOKEN=$RENOVATE_GITHUB_TOKEN
  export GITHUB_COM_TOKEN
  args+=(-e GITHUB_COM_TOKEN)
else
  # said, never silent: what the runner then refuses (scripts/upgrade-units.py notes - Renovate says nothing in the body)
  echo "NO GITHUB TOKEN (RENOVATE_GITHUB_TOKEN in ops/.env is empty): Renovate fetches no release notes - the runner refuses majors, one-way units and family minors until it is set (a read-only GitHub token, no scopes)"
fi
mkdir -p "$ops/.copy"
log=$ops/.copy/renovate-$(date +%Y%m%d-%H%M%S)-$$.log
echo "Renovate ${dry:-run} ($image) - its log: $log"
# its log on the console as it is written (operator 2026-11-22: "make all this logging visible on the console where task
# runs"), followed until docker is gone - so all of it before what this prints next; a lookup's report (behind its marker)
# left out, summarised below. A reader gone (a closed terminal) stops the follower, never Renovate or its log
"${UPGRADE_DOCKER:-docker}" "${args[@]}" "$image" "${cmd[@]}" > "$log" 2>&1 &
renovate_pid=$!
tail -n +1 -F -s 0.1 --pid="$renovate_pid" "$log" 2> /dev/null | sed -u '/^=== renovate report ===$/,$d' || true
if ! wait "$renovate_pid"; then
  echo "Renovate FAILED - its log above ($log)" >&2
  exit 1
fi
# the report out of the log (the checks below read Renovate's log alone)
report=$log.report.json
sed -n '/^=== renovate report ===$/,$p' "$log" | tail -n +2 > "$report"
sed -i '/^=== renovate report ===$/,$d' "$log"
[ -s "$report" ] || rm -f "$report"
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
if [ -n "$dry" ]; then
  python3 -I "$ops/scripts/upgrade-report.py" "$report" || { echo "Renovate's report missing - what it found is in its log only ($log)" >&2; exit 1; }
fi
