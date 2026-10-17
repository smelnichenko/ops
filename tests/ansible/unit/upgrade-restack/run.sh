#!/bin/bash
# scripts/upgrade-restack.py on scratch repositories: the step branches put in a new order - each step's own commits
# on the step before it in the new order, numbered by position, the old branches kept as upgrade-old/, the step files'
# git mv lines; a repo with fewer steps; a dropped step (its file gone) renamed and not re-created; --dry-run changes
# nothing; refused before any repo is touched - a dirty tree, a repo off main, an order not naming every step once; a commit that does not apply
# stops the run naming the step and the commit. The script as the repo holds it, in a scratch ops tree of three steps
# (the order names the steps as their files do, by their old numbers).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
g() { local r=$1; shift; git -C "$r" -c user.name=t -c user.email=t@t "$@" > /dev/null 2>&1; }
setup() {  # a scratch ops tree (steps 01-a 02-b 03-c), infra with all three step branches and a dropped 04-d,
           # platform with 02-b only - each step one commit of its own file
  rm -rf "$W/ops" "$W/infra" "$W/platform"
  mkdir -p "$W/ops/scripts" "$W/ops/tests/ansible/upgrade/steps"
  cp scripts/upgrade-restack.py "$W/ops/scripts/"
  for s in 01-a 02-b 03-c; do echo "step $s" > "$W/ops/tests/ansible/upgrade/steps/$s.txt"; done
  local r prev s
  for r in infra platform; do
    mkdir "$W/$r" && g "$W/$r" init -q -b main && echo base > "$W/$r/base" && g "$W/$r" add base && g "$W/$r" commit -qm base
  done
  prev=main
  for s in 01-a 02-b 03-c 04-d; do
    g "$W/infra" checkout -q -b "upgrade/$s" "$prev" && echo "$s" > "$W/infra/${s#*-}" && g "$W/infra" add "${s#*-}" \
      && g "$W/infra" commit -qm "infra $s"
    prev="upgrade/$s"
  done
  g "$W/infra" checkout -q main
  g "$W/platform" checkout -q -b upgrade/02-b main && echo b > "$W/platform/b" && g "$W/platform" add b \
    && g "$W/platform" commit -qm "platform 02-b" && g "$W/platform" checkout -q main
  printf '%s\n' 03-c 01-a 02-b > "$W/order"
}
run() {  # run <args...>: exit code; the output in $W/out
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    python3 "$W/ops/scripts/upgrade-restack.py" --order "$W/order" --repos "$W/infra" "$W/platform" "$@" > "$W/out" 2>&1
  echo "rc=$?"
}
heads() { git -C "$1" for-each-ref --format='%(refname:short)' refs/heads/ | tr '\n' ' ' | sed 's/ $//'; }
subjects() { git -C "$1" log --reverse --format=%s "main..$2" | tr '\n' ',' | sed 's/,$//'; }

setup
check "reordered c, a, b: each step on the one before it in the new order, renumbered" \
  "$(run) $(subjects "$W/infra" upgrade/01-c) | $(subjects "$W/infra" upgrade/02-a) | $(subjects "$W/infra" upgrade/03-b)" \
  "rc=0 infra 03-c | infra 03-c,infra 01-a | infra 03-c,infra 01-a,infra 02-b"
check "  the old branches kept as upgrade-old/ (the dropped 04-d's too), the dropped step not re-created, on main" \
  "$(heads "$W/infra") $(git -C "$W/infra" rev-parse --abbrev-ref HEAD)" \
  "main upgrade-old/01-a upgrade-old/02-b upgrade-old/03-c upgrade-old/04-d upgrade/01-c upgrade/02-a upgrade/03-b main"
check "  the dropped step said; its commits go nowhere" \
  "$(grep -c 'dropped (no step file - kept as upgrade-old/ only): 04-d' "$W/out") $(git -C "$W/infra" log --all --format=%s | grep -c 'infra 04-d')" \
  "1 1"
check "  platform's one step: renumbered by its place in the order, on main" \
  "$(heads "$W/platform") $(subjects "$W/platform" upgrade/03-b)" "main upgrade-old/02-b upgrade/03-b platform 02-b"
check "  the step files' git mv lines, every renamed step's" "$(grep '^git mv' "$W/out" | sed 's#tests/ansible/upgrade/steps/##g' | tr '\n' ';')" \
  "git mv 01-a.txt 02-a.txt;git mv 02-b.txt 03-b.txt;git mv 03-c.txt 01-c.txt;"

setup
check "--dry-run: the plan said, no branch touched" "$(run --dry-run) $(heads "$W/infra") $(grep -c ' -> upgrade/' "$W/out")" \
  "rc=0 main upgrade/01-a upgrade/02-b upgrade/03-c upgrade/04-d 4"

setup; echo dirt > "$W/platform/dirt"
check "a dirty tree (the second repo's): refused before any repo is touched - infra's branches as they were" \
  "$(run) $(grep -c 'platform: uncommitted changes' "$W/out") $(heads "$W/platform") | $(heads "$W/infra")" \
  "rc=1 1 main upgrade/02-b | main upgrade/01-a upgrade/02-b upgrade/03-c upgrade/04-d"
setup; g "$W/infra" checkout -q upgrade/01-a
check "a repo off main: refused before any rename" "$(run) $(grep -c 'infra: not on main' "$W/out") $(heads "$W/infra")" \
  "rc=1 1 main upgrade/01-a upgrade/02-b upgrade/03-c upgrade/04-d"
setup; printf '%s\n' 03-c 01-a > "$W/order"
check "an order missing a step: refused, naming it" "$(run) $(grep -c "missing \['b'\], unknown \[\]" "$W/out") $(heads "$W/platform")" \
  "rc=1 1 main upgrade/02-b"

# a step whose commit depends on the one before it in the old order: moved first, it does not apply - the run stops
# naming the step and the commit, the old branches kept
setup
g "$W/infra" checkout -q upgrade/03-c && echo "c after a" >> "$W/infra/a" && g "$W/infra" commit -qam "infra 03-c edits a"
g "$W/infra" branch -q -f upgrade/04-d upgrade/03-c && g "$W/infra" checkout -q main
c=$(git -C "$W/infra" rev-parse --short=10 upgrade/03-c)
check "a commit that does not apply: the run stopped, the step and the commit named, the old branches kept" \
  "$(run) $(grep -c "infra: 03-c -> upgrade/01-c: $c does not apply on main" "$W/out") $(heads "$W/infra" | grep -o 'upgrade-old/[^ ]*' | tr '\n' ' ')" \
  "rc=1 1 upgrade-old/01-a upgrade-old/02-b upgrade-old/03-c upgrade-old/04-d "
echo "upgrade-restack: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
