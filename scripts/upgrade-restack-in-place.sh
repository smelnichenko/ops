#!/bin/bash
# upgrade-restack-in-place.sh - every upgrade/NN-* branch of a repo put back on the one before it, in the same order
# and under the same names, after a commit was added to an earlier step branch (the later ones do not carry it until
# then, and the runner's refs check stops at the first). Each branch's own commits - its old predecessor..itself, from
# their merge base when it was forked lower - are rebased onto the new predecessor; then every step's own change (its
# changed lines) is compared with what it was. The SHAs before the first run are kept in .git/restack-old-shas: on a
# conflict the rebase is left in progress - resolve it, `git rebase --continue`, run this again. Afterwards check
# every step: scripts/upgrade-expected-inventory.py --refs <step>. To change the order, scripts/upgrade-restack.py.
# Steps production merged (tagged upgrade-merged/<step>) are skipped; the first unmerged one goes onto main - after a
# CD commit moved main during the rollout, this puts the remaining steps back on it.
#
# Usage: scripts/upgrade-restack-in-place.sh <repo dir>    (clean, on main; e.g. ../infra)
set -uo pipefail
dir=$1; repo=$(basename "$dir")
cd "$dir" || exit 1
state=.git/restack-old-shas
mapfile -t heads < <(git for-each-ref --format='%(refname:short)' 'refs/heads/upgrade/*' | sort -t/ -k2 -n)
if [ ! -f "$state" ]; then
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] && [ -z "$(git status --porcelain)" ] \
    || { echo "$repo: not clean on main"; exit 1; }
  { echo "main $(git rev-parse main)"; for b in "${heads[@]}"; do echo "$b $(git rev-parse "$b")"; done; } > "$state"
fi
[ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] \
  && { echo "$repo: a rebase is in progress - finish it first"; exit 1; }
declare -A old
while read -r b s; do old[$b]=$s; done < "$state"
# a step's own change: its changed lines with each hunk's section heading (git's function context - the same lines
# under another YAML key are another change), not the hunks' line numbers (a restack moves them)
own() {
  git diff -U0 "$1" "$2" \
    | awk '/^@@/ {sub(/^@@ [^@]* @@/, "@@"); print; next} /^[-+]/ && !/^(---|\+\+\+) / {print}' \
    | sha256sum | cut -c1-16
}
prev=main; moved=0
for b in "${heads[@]}"; do
  # a step production merged already (tagged by scripts/upgrade-merge-step.sh) is in main: nothing to put back, and
  # the next one goes onto main
  if git rev-parse -q --verify "refs/tags/upgrade-merged/${b#upgrade/}" > /dev/null; then
    [ "$prev" = main ] || { echo "$repo: $b is merged, $prev before it is not - merged out of order"; exit 1; }
    echo "$repo: $b merged - skipped"
    continue
  fi
  prev_old=${old[$prev]}; prev_new=$(git rev-parse "$prev"); cur=$(git rev-parse "$b")
  if git merge-base --is-ancestor "$prev_new" "$b" \
     && { [ "$cur" != "${old[$b]}" ] || [ "$prev_old" = "$prev_new" ]; }; then
    :
  else
    if ! git rebase -q --onto "$prev_new" "$prev_old" "$b" > /dev/null 2>&1; then
      echo "$repo: $b conflicts on its predecessor - left in progress:"
      git status --short | grep -E '^(UU|AA|DU|UD) '
      exit 2
    fi
    moved=$((moved + 1)); echo "$repo: $b moved (${old[$b]:0:7} -> $(git rev-parse --short "$b"))"
  fi
  # the step's own change as before (a branch forked below its predecessor: its own commits start at their merge base)
  if [ "$(own "$(git merge-base "$prev_old" "${old[$b]}")" "${old[$b]}")" != "$(own "$prev_new" "$b")" ]; then
    echo "$repo: $b - its own change differs from before"; git checkout -q main; exit 1
  fi
  prev=$b
done
git checkout -q main
rm -f "$state"
echo "$repo: $moved moved this run, every step's own change as before, each branch on its predecessor"
