#!/usr/bin/env bash
# git-commit-push.sh - an environment's infra changes committed and pushed (create-environment.yml and
# destroy-environment.yml, their last phase): every change in the checkout staged; nothing staged - nothing to do; else
# one commit with the message, pushed to main at the URL given (origin without one). Only from main: a checkout on
# another branch would commit there, and push nothing of it.
#
# Usage: git-commit-push.sh <infra checkout> <message> [push URL]
set -euo pipefail
dir=$1 msg=$2 url=${3:-}
branch=$(git -C "$dir" branch --show-current)
[ "$branch" = main ] || { echo "REFUSED: $dir is on ${branch:-a detached HEAD}, not main"; exit 1; }
git -C "$dir" add -A
if git -C "$dir" diff --cached --quiet; then
  echo "NOTHING TO COMMIT"
  exit 0
fi
git -C "$dir" commit -q -m "$msg"
git -C "$dir" push -q "${url:-origin}" main
echo "PUSHED: $msg"
