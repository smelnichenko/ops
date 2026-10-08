#!/usr/bin/env bash
# git-commit-push.sh - an environment's infra changes (create-environment.yml and destroy-environment.yml): the
# checkout made ready before the playbook reads or writes it, its changes committed and pushed after.
#
#   ready <infra checkout> [push URL]   on main, nothing uncommitted or untracked (it would be pushed with the
#                                       environment's change), then up to date with the remote's main - this checkout's
#                                       own commits (a run whose push failed) rebased onto it
#   <infra checkout> <message> [URL]    every change staged, one commit with the message (nothing changed: none); then
#                                       pushed whenever main is ahead of the remote's - a commit an earlier run could
#                                       not push among them - rebased first onto the remote's main, which moves on its
#                                       own (the apps' CD pushes image tags). A conflict: refused, nothing pushed
#
# The URL: origin without one. Only from main: a checkout on another branch would commit there, and push nothing.
set -euo pipefail
on_main() {
  local b
  b=$(git -C "$1" branch --show-current)
  [ "$b" = main ] || { echo "REFUSED: $1 is on ${b:-a detached HEAD}, not main"; exit 1; }
}
# main rebased onto the remote's (in FETCH_HEAD after); a conflict undone and refused
onto_remote() {
  git -C "$1" fetch -q "$2" main
  if ! git -C "$1" rebase -q FETCH_HEAD > /dev/null 2>&1; then
    local gd
    gd=$(git -C "$1" rev-parse --absolute-git-dir)
    if [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; then
      git -C "$1" rebase --abort
    fi
    echo "REFUSED: $1's main does not rebase onto $2's (a conflict) - nothing pushed: resolve it there"
    exit 1
  fi
}
if [ "${1:-}" = ready ]; then
  dir=$2 url=${3:-}
  url=${url:-origin}
  on_main "$dir"
  dirty=$(git -C "$dir" status --porcelain)
  if [ -n "$dirty" ]; then
    echo "REFUSED: $dir has changes not committed - they would be pushed with the environment's: ${dirty//$'\n'/; }"
    exit 1
  fi
  was=$(git -C "$dir" rev-parse --short HEAD)
  onto_remote "$dir" "$url"
  now=$(git -C "$dir" rev-parse --short HEAD)
  echo "READY: $dir at $(git -C "$dir" log -1 --format='%h %s')$([ "$was" = "$now" ] || echo " - UPDATED from $was")"
  exit 0
fi
dir=$1 msg=$2 url=${3:-}
url=${url:-origin}
on_main "$dir"
git -C "$dir" add -A
if git -C "$dir" diff --cached --quiet; then
  echo "NOTHING TO COMMIT"
else
  git -C "$dir" commit -q -m "$msg"
fi
# a push the remote's main moved past in between is rejected: rebased onto it again, at most three times
for _ in 1 2 3; do
  onto_remote "$dir" "$url"
  if [ "$(git -C "$dir" rev-list --count FETCH_HEAD..main)" = 0 ]; then
    echo "NOTHING TO PUSH"
    exit 0
  fi
  if git -C "$dir" push -q "$url" main; then
    echo "PUSHED: $(git -C "$dir" log -1 --format=%s main)"
    exit 0
  fi
done
echo "REFUSED: $dir's main not pushed to $url in three tries (the remote's moving on) - run again"
exit 1
