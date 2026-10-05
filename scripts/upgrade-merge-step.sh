#!/usr/bin/env bash
# upgrade-merge-step.sh <step> <infra|platform> - the GitOps half of one production upgrade step: the step's branch
# (upgrade/<step>) in that repo fast-forwarded onto main and pushed. Argo CD reads main of both repos, so the push is
# the production change (platform's CI lints the same commit alongside; it gates nothing). Called by
# scripts/upgrade-production.py merge (`task deploy:upgrade:merge`) after its ledger, proof and merge-order checks.
#
# Refuses unless the step file declares that repo's branch, the repo's working tree is clean, main is origin/main,
# the repo's previous step branch is in main already and this one contains main - so the merge adds this step's
# commits only (stacked branches carry every earlier step's: merged out of order they would bring unproven ones).
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
[ "$(git -C "$dir" rev-parse main)" = "$(git -C "$dir" rev-parse origin/main)" ] \
  || { echo "REFUSED: $repo main is not origin/main" >&2; exit 1; }
git -C "$dir" rev-parse -q --verify "refs/heads/$branch" > /dev/null \
  || { echo "REFUSED: no $repo branch $branch" >&2; exit 1; }
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
git -C "$dir" merge --ff-only -q "$branch"
git -C "$dir" push -q origin main
echo "$repo: main is $(git -C "$dir" rev-parse --short main), pushed"
