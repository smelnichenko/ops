#!/usr/bin/env bash
# git-commit-push.sh - an environment's infra changes (create-environment.yml and destroy-environment.yml): the
# checkout made ready before the playbook reads or writes it, its changes committed and pushed after. The checkout is
# the operator's own (../infra), where other work happens: only the environment's paths are ever staged, and nothing
# of another's is pushed - a change outside them, or a commit ahead of the remote that is not the automation's
# (author env-automation, subject "env: "), is refused, named.
#
#   ready <infra checkout> [push URL]          on main, nothing uncommitted or untracked, no commit of another's ahead;
#                                              then up to date with the remote's main - the automation's own commits
#                                              (a run whose push failed) rebased onto it
#   <checkout> <message> <URL|""> -- <path>... the environment's paths staged (a removal too), one commit with the
#                                              message (nothing changed: none); then pushed whenever main is ahead of
#                                              the remote's - an earlier run's unpushed commit among them - rebased
#                                              first onto the remote's main, which moves on its own (the apps' CD
#                                              pushes image tags). A conflict: refused, nothing pushed
#
# The URL: origin when empty. The remote's main is read into a ref of this script's own (refs/env-automation/main),
# never FETCH_HEAD: another fetch in the checkout in between would have made another branch the base. Only from main.
set -euo pipefail
REF=refs/env-automation/main
on_main() {
  local b
  b=$(git -C "$1" branch --show-current)
  [ "$b" = main ] || { echo "REFUSED: $1 is on ${b:-a detached HEAD}, not main"; exit 1; }
}
# the remote's main into REF
fetch_main() {
  git -C "$1" fetch -q "$2" "+main:$REF"
}
# every commit ahead of the remote's main the automation's - another's (held back, another session's) is never pushed
only_ours() {
  local foreign
  foreign=$(git -C "$1" log --format='%an%x09%s' "$REF..main" | awk -F'\t' '$1 != "env-automation" || $2 !~ /^env: /')
  [ -z "$foreign" ] || { echo "REFUSED: $1's main has commits ahead of the remote that are not this automation's:" \
    "${foreign//$'\n'/; } - push or drop them first"; exit 1; }
}
# main rebased onto REF; a conflict undone and refused
onto_remote() {
  if ! git -C "$1" rebase -q "$REF" > /dev/null 2>&1; then
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
  fetch_main "$dir" "$url"
  only_ours "$dir"
  onto_remote "$dir" "$url"
  now=$(git -C "$dir" rev-parse --short HEAD)
  echo "READY: $dir at $(git -C "$dir" log -1 --format='%h %s')$([ "$was" = "$now" ] || echo " - UPDATED from $was")"
  exit 0
fi
dir=${1:-} msg=${2:-} url=${3:-}
url=${url:-origin}
[ "${4:-}" = -- ] && [ $# -ge 5 ] || { echo "REFUSED: usage: $0 <checkout> <message> <URL|\"\"> -- <path>..."; exit 1; }
shift 4
paths=("$@")
on_main "$dir"
# a change outside the environment's paths (another's work): refused before anything is staged
other=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  p=${line:3}
  p=${p##* -> }
  ours=""
  for e in "${paths[@]}"; do
    if [ "$p" = "$e" ] || [[ $p == "$e"/* ]]; then ours=1; break; fi
  done
  [ -n "$ours" ] || other+=" $p"
done <<< "$(git -C "$dir" status --porcelain --untracked-files=all)"
[ -z "$other" ] || { echo "REFUSED: changes outside the environment's paths in $dir:$other - nothing committed"; exit 1; }
# each path there, or known to git (one removed): staged; one neither - nothing of it to stage
present=()
for e in "${paths[@]}"; do
  if [ -e "$dir/$e" ] || git -C "$dir" ls-files --error-unmatch -- "$e" > /dev/null 2>&1; then present+=("$e"); fi
done
[ "${#present[@]}" -eq 0 ] || git -C "$dir" add -A -- "${present[@]}"
if git -C "$dir" diff --cached --quiet; then
  echo "NOTHING TO COMMIT"
else
  git -C "$dir" commit -q -m "$msg"
fi
# a push the remote's main moved past in between is rejected: rebased onto it again, at most three times
for _ in 1 2 3; do
  fetch_main "$dir" "$url"
  only_ours "$dir"
  onto_remote "$dir" "$url"
  if [ "$(git -C "$dir" rev-list --count "$REF..main")" = 0 ]; then
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
