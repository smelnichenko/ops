#!/usr/bin/env bash
# Checkpoint: rebuild STATUS.md, commit this folder on the current branch when something changed,
# and push the branch, so that no result lives only in the working clone. Never on main: a branch
# push is allowed while main is frozen, and every commit carries [CI SKIP], so no pipeline starts.
# Safe to run at any moment and from a loop.
#
#   ./checkpoint.sh ["what happened"]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
NOTE=${1:-checkpoint}
cd "$HERE" || exit 1
branch=$(git rev-parse --abbrev-ref HEAD)
case "$branch" in main | master | HEAD) echo "on '$branch' - a checkpoint needs its own branch"; exit 1 ;; esac
exec 9>"$(git rev-parse --git-dir)/eu-job-checkpoint.lock"
flock -n 9 || { echo "another checkpoint is running"; exit 0; }
python3 -I status.py >/dev/null || { echo "status.py failed - nothing committed"; exit 1; }
# The exclude list is rebuilt when its inputs are well formed; a malformed input is said and the old list kept.
python3 -I exclude_list.py >/dev/null || echo "exclude_list.py: a prohibited/ file is malformed - list not rebuilt"
python3 -I include_list.py >/dev/null || echo "include_list.py: an included/ file is malformed or clashes with the exclude list - list not rebuilt"
python3 -I investigate_list.py >/dev/null || echo "investigate_list.py: a pending/ file is malformed - list not rebuilt"
git add -- . || exit 1
if ! git diff --cached --quiet -- .; then
  git commit -q -F - -- . <<COMMIT_MSG_EU_JOBS
[CI SKIP] docs: EU-27 free job data sources - $NOTE, $(date +%H:%M)

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
COMMIT_MSG_EU_JOBS
  rc=$?
  [ $rc -eq 0 ] || { echo "commit failed rc=$rc"; exit 1; }
fi
# Push whenever the server is behind, also after an earlier push failed.
local_head=$(git rev-parse HEAD)
remote_head=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
if [ "$local_head" = "$remote_head" ]; then
  echo "$(date +%H:%M) no change; server has ${local_head:0:8}"
  exit 0
fi
case "$(git log -1 --format=%s)" in
  "[CI SKIP]"*) ;;
  *) echo "head commit carries no [CI SKIP] - not pushed"; exit 1 ;;
esac
git push -q origin "$branch"
rc=$?
[ $rc -eq 0 ] || { echo "PUSH FAILED rc=$rc - ${local_head:0:8} is in the working clone only"; exit 1; }
echo "$(date +%H:%M) saved ${local_head:0:8}; server has $(git ls-remote origin "refs/heads/$branch" | cut -c1-8)"
