#!/usr/bin/env bash
# upgrade-merge-step.sh <step> <infra|platform> [take-up [<tip>] | <tip>] - the GitOps half of one production upgrade
# step: the step's branch (upgrade/<step>) in that repo fast-forwarded onto main and pushed. Argo CD reads main of both repos, so
# the push is the production change (platform's CI lints the same commit alongside; it gates nothing). Called by
# scripts/upgrade-production.py merge (`task deploy:upgrade:merge`) after its ledger, proof and merge-order checks.
#
# Refuses unless the step file declares that repo's branch, the repo's working tree is clean, main is origin/main,
# the repo's previous step branch is in main already and this one contains main - so the merge adds this step's
# commits only (stacked branches carry every earlier step's: merged out of order they would bring unproven ones).
# The merged step is tagged upgrade-merged/<step> (annotated: "base <main it went onto>"); a run cut short after its
# push and before its tag is taken up by the next one. `take-up`: only that - any other state is refused, nothing
# pushed (upgrade-production.py merge asks for it once its proof check found the push already live). <tip>: the
# branch's commit the caller checked - a branch moved since is refused before anything (a take-up too), nothing pushed
# or tagged. A step whose tag is there already (merged before) is refused: a forced tag moved it, its base another main.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
step=${1:?step}; repo=${2:?infra or platform}; only=${3:-} tip=${4:-}
case "$only" in
  "") ;;
  take-up) [ -z "$tip" ] || [[ $tip =~ ^[0-9a-f]{40}$ ]] || { echo "REFUSED: $tip (a commit)" >&2; exit 1; } ;;
  *) [[ $only =~ ^[0-9a-f]{40}$ ]] && [ -z "$tip" ] || { echo "REFUSED: $only (take-up, a commit, or nothing)" >&2; exit 1; }
     tip=$only only= ;;
esac
case "$repo" in infra|platform) ;; *) echo "REFUSED: repo $repo (infra or platform)" >&2; exit 1;; esac
file="$ops/tests/ansible/upgrade/steps/$step.txt"
[ -f "$file" ] || { echo "REFUSED: no step $step" >&2; exit 1; }
grep -qx "branch $repo" "$file" || { echo "REFUSED: step $step declares no $repo branch" >&2; exit 1; }
dir="$ops/../$repo"; branch="upgrade/$step"
git -C "$dir" diff --quiet && git -C "$dir" diff --cached --quiet \
  || { echo "REFUSED: $repo has uncommitted changes" >&2; exit 1; }
git -C "$dir" fetch -q origin main
git -C "$dir" rev-parse -q --verify "refs/heads/$branch" > /dev/null \
  || { echo "REFUSED: no $repo branch $branch" >&2; exit 1; }
tag="upgrade-merged/$step"
# the branch's commit, read once: the one checked (the caller's tip), logged, pushed and tagged - a branch moving under
# the run (a restack in another shell) is refused below, and never pushed by its name
head=$(git -C "$dir" rev-parse "$branch")
[ -z "$tip" ] || [ "$head" = "$tip" ] \
  || { echo "REFUSED: $repo $branch moved since it was checked (${tip:0:10}) - nothing pushed or tagged" >&2; exit 1; }
# pushed by an earlier run cut short before its tag (a push the server took, the connection gone): the branch's commit
# is in origin's main (CD may have pushed on top since) and no tag says so - tagged now with the main it went onto
# (local main if not moved yet, else where it was before the fast-forward), so the re-run is a resume, not a refusal
# of a change already live
if git -C "$dir" merge-base --is-ancestor "$head" origin/main \
   && ! git -C "$dir" rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
  if [ "$(git -C "$dir" rev-parse main)" != "$head" ]; then
    base=$(git -C "$dir" rev-parse main)
  else
    base=$(git -C "$dir" rev-parse 'main@{1}')
  fi
  [ "$base" != "$head" ] && git -C "$dir" merge-base --is-ancestor "$base" "$head" \
    || { echo "REFUSED: $repo $branch is in origin's main with no $tag, and its main before is unknown" >&2; exit 1; }
  [ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" = main ] \
    || { echo "REFUSED: $repo is on $(git -C "$dir" rev-parse --abbrev-ref HEAD) - check out main first" >&2; exit 1; }
  git -C "$dir" merge --ff-only -q "$head"
  git -C "$dir" tag -a -m "base $base" "$tag" "$head"
  echo "$repo: $branch was pushed already (a run cut short before its tag) - tagged $tag," \
    "base $(git -C "$dir" rev-parse --short "$base")"
  exit 0
fi
[ -z "$only" ] || { echo "REFUSED: take-up only, and $repo $branch is not in origin's main without $tag" >&2; exit 1; }
! git -C "$dir" rev-parse -q --verify "refs/tags/$tag" > /dev/null \
  || { echo "REFUSED: $tag exists already - step $step was merged before (task deploy:upgrade:status)" >&2; exit 1; }
[ "$(git -C "$dir" rev-parse main)" = "$(git -C "$dir" rev-parse origin/main)" ] \
  || { echo "REFUSED: $repo main is not origin/main" >&2; exit 1; }
# stacked branches all contain main: what matters is that the repo's previous step branch is merged already, so this
# one adds its own step's commits only
prev=""
for f in $(ls "$ops/tests/ansible/upgrade/steps" | sed -n 's/\.txt$//p' | sort -V); do
  [ "$f" = "$step" ] && break
  grep -qx "branch $repo" "$ops/tests/ansible/upgrade/steps/$f.txt" && prev="upgrade/$f"
done
if [ -n "$prev" ]; then
  # a merged step's branch deleted after its merge: its tag
  git -C "$dir" rev-parse -q --verify "refs/heads/$prev" > /dev/null || prev="refs/tags/upgrade-merged/${prev#upgrade/}"
  git -C "$dir" merge-base --is-ancestor "$prev" main \
    || { echo "REFUSED: $repo $prev (the step before) is not merged into main yet" >&2; exit 1; }
fi
git -C "$dir" merge-base --is-ancestor main "$head" \
  || { echo "REFUSED: $repo $branch does not contain main - rebase it" >&2; exit 1; }
echo "$repo: main $(git -C "$dir" rev-parse --short main) -> $branch $(git -C "$dir" rev-parse --short "$head"):"
git -C "$dir" log --oneline "main..$head"
current=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
[ "$current" = main ] || { echo "REFUSED: $repo is on $current - check out main first" >&2; exit 1; }
base=$(git -C "$dir" rev-parse main)
# pushed first, then local main moved: a push rejected (CD pushed meanwhile) leaves local main as origin's
git -C "$dir" push -q origin "$head:refs/heads/main"
git -C "$dir" merge --ff-only -q "$head"
# the step marked merged, with the main it went onto: the refs check, the restack and the merge order skip merged steps
# (their branches are in main now), and a re-run after an interrupted ledger record finds the step's own change
# (base..tag) to compare with its proof
git -C "$dir" tag -a -m "base $base" "$tag" "$head"
echo "$repo: main is $(git -C "$dir" rev-parse --short main), pushed; tagged $tag"
