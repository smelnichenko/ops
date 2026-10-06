#!/usr/bin/env bash
# upgrade-merge-step.sh <step> <infra|platform> - the GitOps half of one production upgrade step: the step's branch
# (upgrade/<step>) in that repo fast-forwarded onto main and pushed. Argo CD reads main of both repos, so the push is
# the production change (platform's CI lints the same commit alongside; it gates nothing). Called by
# scripts/upgrade-production.py merge (`task deploy:upgrade:merge`) after its ledger, proof and merge-order checks.
#
# Refuses unless the step file declares that repo's branch, the repo's working tree is clean, main is origin/main,
# the repo's previous step branch is in main already and this one contains main - so the merge adds this step's
# commits only (stacked branches carry every earlier step's: merged out of order they would bring unproven ones).
# The merged step is tagged upgrade-merged/<step> (annotated: "base <main it went onto>"); a run cut short after its
# push and before its tag is taken up by the next one.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
step=${1:?step}; repo=${2:?infra or platform}
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
# pushed by an earlier run cut short before its tag (a push the server took, the connection gone): origin's main is
# the branch and no tag says so - tagged now with the main it went onto (local main if not moved yet, else where it
# was before the fast-forward), so the re-run is a resume, not a refusal of a change already live
if [ "$(git -C "$dir" rev-parse origin/main)" = "$(git -C "$dir" rev-parse "$branch")" ] \
   && ! git -C "$dir" rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
  if [ "$(git -C "$dir" rev-parse main)" != "$(git -C "$dir" rev-parse "$branch")" ]; then
    base=$(git -C "$dir" rev-parse main)
  else
    base=$(git -C "$dir" rev-parse 'main@{1}')
  fi
  [ "$base" != "$(git -C "$dir" rev-parse "$branch")" ] && git -C "$dir" merge-base --is-ancestor "$base" "$branch" \
    || { echo "REFUSED: $repo main is $branch on origin with no $tag, and its main before is unknown" >&2; exit 1; }
  [ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" = main ] \
    || { echo "REFUSED: $repo is on $(git -C "$dir" rev-parse --abbrev-ref HEAD) - check out main first" >&2; exit 1; }
  git -C "$dir" merge --ff-only -q "$branch"
  git -C "$dir" tag -a -m "base $base" "$tag" "$branch"
  echo "$repo: $branch was pushed already (a run cut short before its tag) - tagged $tag," \
    "base $(git -C "$dir" rev-parse --short "$base")"
  exit 0
fi
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
  git -C "$dir" merge-base --is-ancestor "$prev" main \
    || { echo "REFUSED: $repo $prev (the step before) is not merged into main yet" >&2; exit 1; }
fi
git -C "$dir" merge-base --is-ancestor main "$branch" \
  || { echo "REFUSED: $repo $branch does not contain main - rebase it" >&2; exit 1; }
echo "$repo: main $(git -C "$dir" rev-parse --short main) -> $branch $(git -C "$dir" rev-parse --short "$branch"):"
git -C "$dir" log --oneline "main..$branch"
current=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
[ "$current" = main ] || { echo "REFUSED: $repo is on $current - check out main first" >&2; exit 1; }
base=$(git -C "$dir" rev-parse main)
# pushed first, then local main moved: a push rejected (CD pushed meanwhile) leaves local main as origin's
git -C "$dir" push -q origin "$branch:main"
git -C "$dir" merge --ff-only -q "$branch"
# the step marked merged, with the main it went onto: the refs check, the restack and the merge order skip merged steps
# (their branches are in main now), and a re-run after an interrupted ledger record finds the step's own change
# (base..tag) to compare with its proof
git -C "$dir" tag -a -f -m "base $base" "$tag" "$branch"
echo "$repo: main is $(git -C "$dir" rev-parse --short main), pushed; tagged $tag"
