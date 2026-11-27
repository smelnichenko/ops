#!/usr/bin/env bash
# ops CI: each build-hash pin a change moves, checked to be what its vendor signs (scripts/renovate-checksums.py
# --check); every pin when the checker or the vendors' keys change. Pull requests and pushes to main alike: ops is
# pushed to main directly. A pin no change moves is not read (the vendors' downloads stay off every other pipeline).
#
# The base: a pull request's target as the clone step fetched it (fetch_target_branch - a step's own git holds no
# credentials); a push's, the branch's last push pipeline when it is the push's ancestor. Woodpecker's previous pipeline
# on main is often a pull request's (theirs count as main's): the commit before the push is then not known, so the push is
# judged by its files (the forge's list, every commit's) - every pin when one is a pin's file, the checker or the keys,
# or when the list is not given (Woodpecker leaves it out past its limit); none of them - nothing moved.
#
# Usage: scripts/ci-build-hashes.sh [renovate-checksums.py's own arguments - the harness's --mirror, --keys]
# Env (Woodpecker's): CI_PIPELINE_EVENT; CI_COMMIT_TARGET_BRANCH (a pull request's); CI_PREV_PIPELINE_EVENT,
#      CI_PREV_COMMIT_SHA, CI_PIPELINE_FILES (a push's)
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${CI_PIPELINE_EVENT:-}" = pull_request ]; then
  target=${CI_COMMIT_TARGET_BRANCH:?a pull request names its target}
  base=$(git rev-parse -q --verify "refs/remotes/origin/$target^{commit}") \
    || { echo "FAILED: origin/$target is not in this clone (the clone step's fetch_target_branch) - the pins not checked"; exit 1; }
elif [ "${CI_PREV_PIPELINE_EVENT:-}" = push ] && [ -n "${CI_PREV_COMMIT_SHA:-}" ] \
  && git merge-base --is-ancestor "$CI_PREV_COMMIT_SHA" HEAD 2> /dev/null; then
  base=$CI_PREV_COMMIT_SHA  # every commit since the branch's last push pipeline
else
  why="the commit before this push not known (the previous pipeline: ${CI_PREV_PIPELINE_EVENT:-none} at ${CI_PREV_COMMIT_SHA:-none})"
  # exit 0: a pin's file, the checker or a key among the push's files, or its files not given; 1: none of them
  if python3 -I - <<'PINFILES'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("rc", "scripts/renovate-checksums.py")
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)
try:
    files = json.loads(os.environ.get("CI_PIPELINE_FILES") or "null")
except ValueError:
    files = None
if not isinstance(files, list):
    sys.exit(0)
watched = {p["file"] for p in rc.PINS} | {"scripts/renovate-checksums.py", "scripts/ci-build-hashes.sh"}
sys.exit(0 if any(f in watched or f.startswith("renovate/keys/") for f in files) else 1)
PINFILES
  then
    echo "$why, its files a pin's, the checker's or a key's (or not given) - every pin checked"
    exec python3 -I scripts/renovate-checksums.py --check "$@"
  fi
  echo "$why, none of its files a pin's, the checker's or a key's - nothing read"
  exit 0
fi
# the base read, or refused: a pin is never waved through for a base the clone does not hold
git cat-file -e "$base^{commit}" 2> /dev/null || { echo "FAILED: $base is not in this clone - the pins not checked"; exit 1; }
if [ -n "$(git diff --name-only "$base" HEAD -- scripts/renovate-checksums.py renovate/keys)" ]; then
  echo "the checker or the vendors' keys changed - every pin checked"
  exec python3 -I scripts/renovate-checksums.py --check "$@"
fi
exec python3 -I scripts/renovate-checksums.py --check --changed --base "$base" "$@"
