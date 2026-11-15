#!/usr/bin/env bash
# ops CI: each build-hash pin a change moves, checked to be what its vendor signs (scripts/renovate-checksums.py
# --check); every pin when the checker or the vendors' keys change. Pull requests and pushes to main alike: ops is
# pushed to main directly. A pin no change moves is not read (the vendors' downloads stay off every other pipeline).
#
# Usage: scripts/ci-build-hashes.sh [renovate-checksums.py's own arguments - the harness's --mirror, --keys]
# Env (Woodpecker's): CI_PIPELINE_EVENT; CI_COMMIT_TARGET_BRANCH (a pull request's), CI_PREV_COMMIT_SHA (a push's)
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${CI_PIPELINE_EVENT:-}" = pull_request ]; then
  git fetch -q --depth 100 origin "${CI_COMMIT_TARGET_BRANCH:?a pull request names its target}"
  base=$(git rev-parse FETCH_HEAD)
else
  base=${CI_PREV_COMMIT_SHA:?a push names the commit before it}
fi
# the base read, or refused: a pin is never waved through for a base the clone does not hold
git cat-file -e "$base^{commit}" 2> /dev/null || { echo "FAILED: $base is not in this clone - the pins not checked"; exit 1; }
if [ -n "$(git diff --name-only "$base" HEAD -- scripts/renovate-checksums.py renovate/keys)" ]; then
  echo "the checker or the vendors' keys changed - every pin checked"
  exec python3 -I scripts/renovate-checksums.py --check "$@"
fi
exec python3 -I scripts/renovate-checksums.py --check --changed --base "$base" "$@"
