#!/usr/bin/env bash
# Checkpoint: rebuild STATUS.md and commit this folder on the current branch, only when something
# changed. Local commit only - it never pushes (one push per round; main is frozen during upgrade
# runs). Safe to run at any moment and from a loop.
#
#   ./checkpoint.sh ["what happened"]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
NOTE=${1:-checkpoint}
cd "$HERE" || exit 1
exec 9>"$(git rev-parse --git-dir)/eu-job-checkpoint.lock"
flock -n 9 || { echo "another checkpoint is running"; exit 0; }
python3 -I status.py >/dev/null || { echo "status.py failed - nothing committed"; exit 1; }
git add -- . || exit 1
if git diff --cached --quiet -- .; then
  echo "$(date +%H:%M) no change"
  exit 0
fi
git commit -q -F - -- . <<COMMIT_MSG_EU_JOBS
[CI SKIP] docs: EU-27 free job data sources - $NOTE, $(date +%H:%M)

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
COMMIT_MSG_EU_JOBS
rc=$?
[ $rc -eq 0 ] || { echo "commit failed rc=$rc"; exit 1; }
echo "$(date +%H:%M) committed $(git rev-parse --short HEAD): $(git show --stat --format= HEAD | tail -1)"
