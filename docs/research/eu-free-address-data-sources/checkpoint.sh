#!/usr/bin/env bash
# Checkpoint: copy changed working files into notes/, regenerate by-country/, commit this folder
# and push - only when something changed. Safe to run at any moment and from a loop; a second
# run while one is going exits at once.
#
#   ./checkpoint.sh ["what happened"]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
WORK="/home/sm/src/monitor/research_notes/EU free address data sources"
NOTE=${1:-checkpoint}
cd "$HERE" || exit 1

exec 9>"$(git rev-parse --git-dir)/eu-address-checkpoint.lock"
flock -n 9 || { echo "another checkpoint is running"; exit 0; }

changed=""
for f in "$WORK"/*.md; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  if ! cmp -s "$f" "notes/$b"; then
    cp -p "$f" "notes/$b" || exit 1
    changed="$changed $b"
  fi
done

python3 -I split_by_country.py || { echo "split failed - nothing committed"; exit 1; }

git add -- . || exit 1
if git diff --cached --quiet -- .; then
  echo "$(date +%H:%M) no change"
  exit 0
fi
# "-- ." commits this folder only, whatever else is staged in the shared tree.
git commit -q -F - -- . <<COMMIT_MSG_EU_ADDR
docs: EU-27 free address data sources - $NOTE, $(date +%H:%M)${changed:+ (${changed# })} [CI SKIP]

Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
COMMIT_MSG_EU_ADDR
rc=$?
[ $rc -eq 0 ] || { echo "commit failed rc=$rc"; exit 1; }
git push -q origin main
rc=$?
[ $rc -eq 0 ] || { echo "PUSH FAILED rc=$rc - commit $(git rev-parse --short HEAD) is local only"; exit 1; }
echo "$(date +%H:%M) saved $(git rev-parse --short HEAD) remote $(git ls-remote origin refs/heads/main | cut -c1-8)${changed:+ :$changed}"
