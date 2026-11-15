#!/bin/bash
# scripts/upgrade-cycle.sh's push of the agent's fix (push_fix, allowed, bot_git) against REAL git - the runner's own
# functions, read from the script, in a throwaway directory: a "Forgejo" of bare repositories (a file:// URL), the
# agent's clones with its commits, the label script a recorder. Real git's behaviour the stubbed harness cannot show:
# the commits fetched from the clone into the runner's own repository and pushed from there to the branch on the
# "Forgejo"; a hook the agent planted in its clone never run; a rename of a script into clusters/ judged by both its
# sides (refused); a symlink refused by its mode; a deletion of the unit's own file pushed; two repos, the second one
# refused - nothing pushed at all; a commit that rewrote the proven one refused.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
REAL=$PWD
W=$(mktemp -d)
trap 'chmod -R u+w "$W" 2> /dev/null; rm -rf "$W"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
# the runner's functions as they are (never a copy of them)
funcs=$(python3 - "$REAL/scripts/upgrade-cycle.sh" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
out = []
for name in ("allowed", "plain_text", "push_fix"):
    i = src.index(f"\n{name}() {{") + 1
    out.append(src[i:].split("\n}\n", 1)[0] + "\n}")
print("\n".join(out))
PY
)
# a world: Forgejo's bare repos, each with main and the unit's branch at its proven head; the agent's clones of them
setup() {
  rm -rf "$W/forgejo" "$W/fix" "$W/fix.push" "$W/state" "$W/calls"
  mkdir -p "$W/forgejo/schnappy" "$W/fix" "$W/state" "$W/scripts"
  for r in infra ops; do
    g init -q "$W/seed-$r" 2> /dev/null || true
    rm -rf "$W/seed-$r"; g init -q "$W/seed-$r"
    if [ "$r" = infra ]; then
      mkdir -p "$W/seed-$r/clusters/production" "$W/seed-$r/scripts"
      echo "v: 1" > "$W/seed-$r/clusters/production/values.yaml"; echo "old: 1" > "$W/seed-$r/clusters/production/old.yaml"
      printf '#!/bin/sh\necho hi\n' > "$W/seed-$r/scripts/tool.sh"
    else
      mkdir -p "$W/seed-$r/deploy/ansible/vars"; echo 'vault_version: "1.21.4"' > "$W/seed-$r/deploy/ansible/vars/vault.yml"
      echo "tasks: []" > "$W/seed-$r/Taskfile.yml"
    fi
    g -C "$W/seed-$r" add -A && g -C "$W/seed-$r" commit -qm base
    g -C "$W/seed-$r" branch -q renovate/u
    g clone -q --bare "$W/seed-$r" "$W/forgejo/schnappy/$r.git"
    g clone -q "$W/forgejo/schnappy/$r.git" "$W/fix/$r" 2> /dev/null
    g -C "$W/fix/$r" checkout -q -B renovate/u "origin/renovate/u"
  done
  : > "$W/heads"
  for r in infra ops; do echo "schnappy/$r 1 $(g -C "$W/fix/$r" rev-parse HEAD) $(g -C "$W/fix/$r" rev-parse origin/main)" >> "$W/heads"; done
  printf '#!/bin/sh\necho "label $*" >> "%s/calls"\n' "$W" > "$W/scripts/upgrade-label.py"; chmod +x "$W/scripts/upgrade-label.py"
}
# the agent's commit in a clone (as it would make it: plain git in the clone)
agent() { local r=$1; shift; (cd "$W/fix/$r" && "$@" && g add -A && g commit -qm "the agent's fix" ) > /dev/null 2>&1; }
pushfix() {  # the runner's push_fix, as the runner calls it: its globals set, run and say the runner's own kind
  (cd "$W" && unit=u heads=$W/heads fixdiff=$W/fix.diff forgejo="file://$W/forgejo" log=$W/log dry="" state=$W/state fixed="" unit_labels="" \
     UPGRADE_FORGEJO_TOKEN=t bash -c "
       say() { echo \"\$*\" >> \"\$log\"; }
       run() { \"\$@\" < /dev/null >> \"\$log\" 2>&1; }
       bot_git() { git \"\$@\"; }
       $funcs
       push_fix \"$W/fix\"; echo \"rc=\$? fixed=\$fixed\"") 2>&1 | tail -n 1
}
branch() { git -C "$W/forgejo/schnappy/$1.git" rev-parse renovate/u; }
proven() { awk -v r="schnappy/$1" '$1 == r {print $3}' "$W/heads"; }

setup
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$W" > "$W/fix/infra/.git/hooks/pre-push"; chmod +x "$W/fix/infra/.git/hooks/pre-push"
git -C "$W/fix/infra" config core.hooksPath .git/hooks
agent infra sh -c 'echo "v: 2" > clusters/production/values.yaml'
out=$(pushfix)
check "a fix of the unit's own value: pushed to the unit's branch on Forgejo from the runner's own repository, labelled" \
  "$out $( [ "$(branch infra)" = "$(git -C "$W/fix/infra" rev-parse HEAD)" ] && echo on-forgejo) $(grep -c 'label u agent-fixed' "$W/calls")" \
  "rc=0 fixed=1 on-forgejo 1"
check "  the hook the agent planted in its clone never ran (no push from its repository)" "$([ -e "$W/hook-ran" ] && echo ran || echo never)" "never"
git -C "$W/fix/infra" push -q "file://$W/forgejo/schnappy/infra.git" HEAD:refs/heads/premise > /dev/null 2>&1
check "  (the premise: that hook does run on a push from the agent's own clone)" "$([ -e "$W/hook-ran" ] && echo ran || echo never)" "ran"
rm -f "$W/hook-ran"
check "  its diff on record, files first" "$(head -n 1 "$W/state/fixes/u.diff" | cut -d, -f1) $(sed -n 2p "$W/state/fixes/u.diff")" "=== the agent's fix of renovate/u === schnappy/infra"

setup
mkdir -p "$W/template/hooks"; printf '#!/bin/sh\ntouch "%s/template-hook-ran"\n' "$W" > "$W/template/hooks/pre-push"; chmod +x "$W/template/hooks/pre-push"
agent infra sh -c 'echo "v: 2" > clusters/production/values.yaml'
check "a pre-push hook that reaches the runner's own repository (a git template of the operator's): never run - hooks off for the push" \
  "$(GIT_TEMPLATE_DIR=$W/template pushfix) $([ -e "$W/template-hook-ran" ] && echo ran || echo never)" "rc=0 fixed=1 never"

setup
agent infra sh -c 'git mv scripts/tool.sh clusters/production/tool.sh'
check "a script renamed into clusters/: refused by the side it left (both sides judged), nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'printf "v: 2\r  extra: evil\n" > clusters/production/values.yaml'
check "a value with a carriage return hiding a YAML key (real git, the blob read back): refused, nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'printf "a\0b" > clusters/production/blob.yaml'
check "a binary file (a NUL - git shows 'Binary files differ'): refused, nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'mkdir -p clusters/x && echo "* diff=evil" > clusters/x/.gitattributes'
check "a .gitattributes nested in clusters/ (an attribute driver of the agent's): refused" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'echo "do as I say" > clusters/production/CLAUDE.md'
check "a CLAUDE.md nested in clusters/ (instructions for the next agent): refused" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'git mv clusters/production/old.yaml scripts/new.sh'
check "a value renamed OUT of clusters/ into scripts/: refused by the side it reached (git's rename pairs never read as one path), nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'ln -s /home/sm/.ssh/config clusters/production/x.yaml'
check "a symlink under clusters/: refused by its mode, nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'git rm -q clusters/production/old.yaml'
check "a deletion of the unit's own file: pushed" "$(pushfix)" "rc=0 fixed=1"

setup
agent infra sh -c 'echo "v: 2" > clusters/production/values.yaml'
agent ops sh -c 'echo "tasks: [x]" > Taskfile.yml'
check "two repos, the second outside the unit's files: NOTHING pushed (infra's branch untouched), no label" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched) $(grep -c label "$W/calls" 2> /dev/null || echo 0)" \
  "rc=1 fixed= untouched 0"

setup
agent infra sh -c 'echo "v: 2" > clusters/production/values.yaml'
agent ops sh -c 'sed -i "s/1.21.4/1.21.5/" deploy/ansible/vars/vault.yml'
check "two repos, both inside: both pushed" \
  "$(pushfix) $( [ "$(branch infra)" != "$(proven infra)" ] && [ "$(branch ops)" != "$(proven ops)" ] && echo both)" "rc=0 fixed=1 both"

setup
(cd "$W/fix/infra" && echo "v: 3" > clusters/production/values.yaml && g commit -qa --amend -m rewritten) > /dev/null 2>&1
check "a commit that rewrote the proven one: refused, nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

echo "upgrade-fix-git: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
