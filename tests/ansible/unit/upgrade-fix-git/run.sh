#!/bin/bash
# scripts/upgrade-cycle.sh's push of the agent's fix (push_fix, allowed, bot_git) against REAL git - the runner's own
# functions, read from the script, in a throwaway directory: a "Forgejo" of bare repositories (a file:// URL), the
# agent's clones with its commits, the label script a recorder. Real git's behaviour the stubbed harness cannot show:
# the commits fetched from the clone into the runner's own repository and pushed from there to the branch on the
# "Forgejo"; a hook the agent planted in its clone never run; a rename of a script into clusters/ judged by both its
# sides (refused); a symlink refused by its mode; a deletion of the unit's own file refused; two repos, the second one
# refused - nothing pushed at all; a commit that rewrote the proven one refused; a Unicode line break or invisible
# character refused; a merge of the agent's refused.
# The review's diffs (diffs) against real clones whose content would steer a plain diff: what git holds, written beside
# each clone.
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
for name in ("allowed", "plain_fix", "push_fix", "diffs"):
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
      echo "v: 1.0.0" > "$W/seed-$r/clusters/production/values.yaml"; echo "old: 1" > "$W/seed-$r/clusters/production/old.yaml"
      printf '#!/bin/sh\necho hi\n' > "$W/seed-$r/scripts/tool.sh"
      # files already there (an agent's edit of each judged by its own rule - never masked by "a file of its own")
      # (each edit below one the YAML judge alone would let through - a version moved - so the rule that refuses it is its own)
      echo "version: 1.0.0" > "$W/seed-$r/clusters/production/CLAUDE.md"; echo "version: 1.0.0" > "$W/seed-$r/clusters/production/.gitattributes"
      ln -s 1.0.0 "$W/seed-$r/clusters/production/link.yaml"; printf 'b\000in' > "$W/seed-$r/clusters/production/blob.bin"
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
  (cd "$W" && unit=u heads=$W/heads fixdiff=$W/fix.diff forgejo="file://$W/forgejo" log=$W/log dry="" state=$W/state fixed="" unit_labels="${UL:-}" unit_store="${US:-}" ops="$REAL" \
     UPGRADE_FORGEJO_TOKEN=t bash -c "
       say() { echo \"\$*\" >> \"\$log\"; }
       run() { \"\$@\" < /dev/null >> \"\$log\" 2>&1; }
       bot_git() { git \"\$@\"; }
       $funcs
       push_fix \"$W/fix\"; echo \"rc=\$? fixed=\$fixed\"") 2>&1 | tail -n 1
}
branch() { git -C "$W/forgejo/schnappy/$1.git" rev-parse renovate/u; }
tree() { git -C "$W/forgejo/schnappy/$1.git" rev-parse 'renovate/u^{tree}'; }
proven() { awk -v r="schnappy/$1" '$1 == r {print $3}' "$W/heads"; }
untouched() { [ "$(branch infra)" = "$(proven infra)" ] && [ "$(branch ops)" = "$(proven ops)" ] && echo untouched; }

# the review's diffs: diffs() as the runner calls it, on clones whose content would steer a plain diff - a textconv
# driver (named by a .gitattributes the unit carries), an external diff, colour forced on, a file git takes for binary
# (a NUL hiding a key): the reviewers read what the commit holds, nothing a driver or a setting made of it
setup
git -C "$W/fix/infra" config diff.steer.textconv "printf TEXTCONV-SHOWN; true"
git -C "$W/fix/infra" config diff.external "printf EXTERNAL-SHOWN; true"
git -C "$W/fix/infra" config color.ui always
agent infra sh -c 'echo "*.yaml diff=steer" > .gitattributes; echo "v: 1.0.1" > clusters/production/values.yaml; printf "plain: 1\000\nevil: key\n" > clusters/production/hidden.txt'
out=$(cd "$W" && heads=$W/heads log=$W/log bash -c "$funcs
  diffs \"$W/fix\"; echo rc=\$?" 2>&1 | tail -n 1)
d=$(tr -d '\000' < "$W/fix/infra.diff" 2> /dev/null)
check "the review's diffs: each clone's diff and commits beside it, as git holds them - no textconv, external diff or colour, a binary-looking file shown whole" \
  "$out $(grep -c '^+v: 1.0.1$' <<< "$d") $(grep -c '^+evil: key$' <<< "$d") $(grep -c -e TEXTCONV-SHOWN -e EXTERNAL-SHOWN -e 'Binary files' -e $'\033\[' <<< "$d") $(cut -d' ' -f2- "$W/fix/infra.commits") | $(wc -c < "$W/fix/ops.diff") $(wc -c < "$W/fix/ops.commits")" \
  "rc=0 1 1 0 t <t@t> the agent's fix | 0 0"
# a directory where the diff goes: its write fails as any user (CI's container runs as root - a directory without
# write permission stopped nobody there)
rm -f "$W/fix/"*.diff "$W/fix/"*.commits
mkdir "$W/fix/infra.diff"
out=$(cd "$W" && heads=$W/heads log=$W/log bash -c "$funcs
  diffs \"$W/fix\"; echo rc=\$?" 2>&1 | tail -n 1)
check "  a diff not written: diffs fails at once (nothing after it written) - the runner blocks the unit, no review run" \
  "$out $([ -e "$W/fix/infra.commits" ] && echo commits-written || echo none-after)" "rc=1 none-after"
rmdir "$W/fix/infra.diff"

setup
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$W" > "$W/fix/infra/.git/hooks/pre-push"; chmod +x "$W/fix/infra/.git/hooks/pre-push"
git -C "$W/fix/infra" config core.hooksPath .git/hooks
agent infra sh -c 'echo "v: 1.0.1" > clusters/production/values.yaml'
out=$(pushfix)
check "a fix of the unit's own value: pushed to the unit's branch on Forgejo from the runner's own repository, labelled" \
  "$out $( [ "$(tree infra)" = "$(git -C "$W/fix/infra" rev-parse 'HEAD^{tree}')" ] && echo on-forgejo) $(grep -c 'label u agent-fixed' "$W/calls")" \
  "rc=0 fixed=1 on-forgejo 1"
check "  as one commit of the runner's on the proven head - its author the agent's own, its message the runner's" \
  "$(git -C "$W/forgejo/schnappy/infra.git" log -1 --format='%P|%an <%ae>|%cn|%s' renovate/u)" \
  "$(proven infra)|Upgrade Fix Agent <upgrade-fix@pmon.dev>|Upgrade Fix Agent|upgrade-fix: renovate/u - the agent's fix, judged and committed by the upgrade runner"
check "  the hook the agent planted in its clone never ran (no push from its repository)" "$([ -e "$W/hook-ran" ] && echo ran || echo never)" "never"
git -C "$W/fix/infra" push -q "file://$W/forgejo/schnappy/infra.git" HEAD:refs/heads/premise > /dev/null 2>&1
check "  (the premise: that hook does run on a push from the agent's own clone)" "$([ -e "$W/hook-ran" ] && echo ran || echo never)" "ran"
rm -f "$W/hook-ran"
check "  its diff on record, files first" "$(head -n 1 "$W/state/fixes/u.diff" | cut -d, -f1) $(sed -n 2p "$W/state/fixes/u.diff")" "=== the agent's fix of renovate/u === schnappy/infra"

setup
mkdir -p "$W/template/hooks"; printf '#!/bin/sh\ntouch "%s/template-hook-ran"\n' "$W" > "$W/template/hooks/pre-push"; chmod +x "$W/template/hooks/pre-push"
agent infra sh -c 'echo "v: 1.0.1" > clusters/production/values.yaml'
check "a pre-push hook that reaches the runner's own repository (a git template of the operator's): never run - hooks off for the push" \
  "$(GIT_TEMPLATE_DIR=$W/template pushfix) $([ -e "$W/template-hook-ran" ] && echo ran || echo never)" "rc=0 fixed=1 never"

setup
agent infra sh -c 'git mv scripts/tool.sh clusters/production/tool.sh'
check "a script renamed into clusters/: refused by the side it left (both sides judged), nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'printf "v: 1.0.1\r  extra: evil\n" > clusters/production/values.yaml'
check "a value with a carriage return hiding a YAML key (real git, the blob read back): refused, nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

for ch in '\342\200\250' '\302\205' '\342\200\256' '\342\200\213' '\342\200\251' '\356\200\200' '\315\270'; do
  # U+2028, NEL, a bidi override, a zero-width space, U+2029, a private one (U+E000), an unassigned one (U+0378) - in
  # octal: sh's printf has no \x
  setup
  agent infra sh -c "printf 'v: 1.0.1$ch  privileged: true\n' > clusters/production/values.yaml"
  check "a value with a Unicode line break or invisible character ($ch as bytes - YAML's line, git's none): refused" \
    "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"
done
setup
agent infra sh -c "printf 'v: \\377\\n' > clusters/production/values.yaml"
check "a value that is not UTF-8 (a byte no text has): refused" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"
setup
(cd "$W/fix/infra" && echo "v: 1.0.1" > clusters/production/values.yaml && g commit -qam "$(printf 'fix \033[2J\033]0;owned\007 done')") > /dev/null 2>&1
pushfix > /dev/null
check "a commit subject with terminal escapes: on record (.upgrade-cycle/fixes) with each control byte a '?'" \
  "$(grep -c "$(printf '\033')" "$W/state/fixes/u.diff") $(grep -o 'fix ?\[2J?\]0;owned? done' "$W/state/fixes/u.diff")" "0 fix ?[2J?]0;owned? done"
for added in '\302\240\302\240readOnlyRootFilesystem: false' 'im\320\260ge: x' 'caf\303\251: 1'; do
  # a no-break space indenting a key (another key to YAML, the same to the eye), a Cyrillic a, a letter beyond ASCII
  setup
  agent infra sh -c "printf 'v: 1\n$added\n' > clusters/production/values.yaml"
  check "a line it adds with a character beyond printable ASCII ($added as bytes): refused" \
    "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"
done
setup
(cd "$W/fix/infra" && printf '# caf\303\251 \342\200\224 kept\nv: 1.0.0\n' > clusters/production/values.yaml && g commit -qam "a line beyond ASCII on main" \
  && g push -q origin HEAD:renovate/u) > /dev/null 2>&1
for r in infra ops; do  # that line on the proven head
  sed -i "s|^schnappy/$r 1 [0-9a-f]* |schnappy/$r 1 $(g -C "$W/fix/$r" rev-parse HEAD) |" "$W/heads"; done
agent infra sh -c "printf '# caf\303\251 \342\200\224 kept\nv: 1.0.1\n#\ta tab in a comment\n' > clusters/production/values.yaml"
check "a file holding a line beyond ASCII already, kept as it was; a line added with a tab (a comment's - a new key is no fix): pushed" "$(pushfix)" "rc=0 fixed=1"

setup
(cd "$W/fix/infra" && mkdir -p .woodpecker && echo "steps: [x]" > .woodpecker/x.yaml && ln -s /home/sm/.ssh/id_ed25519 clusters/production/k.yaml \
  && g add -A && g commit -qm "step 1" && git rm -rq .woodpecker clusters/production/k.yaml && echo "v: 1.0.1" > clusters/production/values.yaml \
  && g commit -qam "step 2") > /dev/null 2>&1
out=$(pushfix)
check "a step in between with a CI file and a symlink (gone by its last commit): pushed as one commit - neither ever on Forgejo" \
  "$out $(git -C "$W/forgejo/schnappy/infra.git" rev-list --count "$(proven infra)..renovate/u") $(git -C "$W/forgejo/schnappy/infra.git" log --all --format=%H -- .woodpecker clusters/production/k.yaml | wc -l)" \
  "rc=0 fixed=1 1 0"

setup
(cd "$W/fix/infra" && git checkout -q -b side && echo "s: 1" > clusters/production/side.yaml && g add -A && g commit -qm side \
  && git checkout -q renovate/u && g merge -q --no-ff side -m merged) > /dev/null 2>&1
check "a merge commit of the agent's (main's work or a side branch under the fix's name, never judged file by file): refused, nothing pushed" \
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
check "a deletion of the unit's own file: refused (a NetworkPolicy or a PeerAuthentication gone is no fix), nothing pushed" \
  "$(pushfix) $(untouched)" "rc=1 fixed= untouched"

setup
agent infra sh -c 'echo "v: 1.0.1" > clusters/production/values.yaml'
agent ops sh -c 'echo "tasks: [x]" > Taskfile.yml'
check "two repos, the second outside the unit's files: NOTHING pushed (infra's branch untouched), no label" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched) $(grep -c label "$W/calls" 2> /dev/null || echo 0)" \
  "rc=1 fixed= untouched 0"

setup
agent infra sh -c 'echo "v: 1.0.1" > clusters/production/values.yaml'
agent ops sh -c 'sed -i "s/1.21.4/1.21.5/" deploy/ansible/vars/vault.yml'
check "two repos, both inside: both pushed (a Vault unit's - its store vault, its version its own)" \
  "$(UL=major,one-way,upgrade-cycle US=vault pushfix) $( [ "$(branch infra)" != "$(proven infra)" ] && [ "$(branch ops)" != "$(proven ops)" ] && echo both)" "rc=0 fixed=1 both"

setup
(cd "$W/fix/infra" && echo "v: 1.0.2" > clusters/production/values.yaml && g commit -qa --amend -m rewritten) > /dev/null 2>&1
check "a commit that rewrote the proven one: refused, nothing pushed" \
  "$(pushfix) $( [ "$(branch infra)" = "$(proven infra)" ] && echo untouched)" "rc=1 fixed= untouched"

# what a fix may not do now that it applies in the run that proves it (no notice since 2026-11-21): a file of its own,
# a resource, a permission, another source, a one-way store's version in a unit not labelled one-way - each refused,
# nothing pushed, the reason in the log; the same store's version in a one-way unit pushed
setup
agent infra sh -c 'echo "v: 1" > clusters/production/new.yaml'
check "a fix adding a file of its own (harmless lines, under the unit's own path - the new file alone refuses it): refused, nothing pushed" \
  "$(pushfix) $(untouched)" "rc=1 fixed= untouched"
for added in 'kind: ClusterRoleBinding' 'repository: ghcr.io/someone/else' 'privileged: true' 'extraObjects: []' '  - hostPath: {path: /}'; do
  setup
  agent infra sh -c "printf '%s\n' '$added' >> clusters/production/values.yaml"; : > "$W/log"
  check "a fix adding '$added' to the unit's values: refused, nothing pushed, the reason in the log" \
    "$(pushfix) $(untouched) $(grep -c '^clusters/production/values.yaml: ' "$W/log")" "rc=1 fixed= untouched 1"
done
setup
agent ops sh -c 'echo "vault_version: \"1.21.5\"" > deploy/ansible/vars/vault.yml'; : > "$W/log"
check "a fix moving a one-way store's version (Vault) in a unit not labelled one-way: refused, nothing pushed, said" \
  "$(pushfix) $(untouched) $(grep -c "moves the one-way store vault's version in a unit that is not vault's" "$W/log")" "rc=1 fixed= untouched 1"
setup
agent ops sh -c 'echo "vault_version: \"1.21.5\"" > deploy/ansible/vars/vault.yml'
check "  the same in the store's own unit (vault: its backups planned before the merge): pushed" \
  "$(UL=major,one-way,upgrade-cycle US=vault pushfix) $([ "$(branch ops)" != "$(proven ops)" ] && echo pushed)" "rc=0 fixed=1 pushed"
al() { (bash -c "$funcs
  allowed $1 $2 && echo yes || echo no"); }
check "allowed: platform's chart values alone - never Chart.yaml (another chart as a dependency), a template, a subchart or a chart's files/" \
  "$(al schnappy/platform helm/schnappy-data/values.yaml) $(al schnappy/platform helm/schnappy-data/values-test.yaml) $(al schnappy/platform helm/schnappy/Chart.yaml) $(al schnappy/platform helm/schnappy-data/templates/cnpg.yaml) $(al schnappy/platform helm/schnappy/charts/sub/values.yaml) $(al schnappy/platform helm/schnappy-data/files/init.sql)" \
  "yes yes no no no no"
for how in "CLAUDE.md (an agent's instructions):echo 'version: 1.0.1' > clusters/production/CLAUDE.md" ".gitattributes:echo 'version: 1.0.1' > clusters/production/.gitattributes" \
           "a symlink retargeted:ln -sfn 1.0.1 clusters/production/link.yaml" "a binary file:printf 'b\\000out' > clusters/production/blob.bin" \
           "a value file renamed in place (a deletion and a file of its own):git mv clusters/production/values.yaml clusters/production/values2.yaml"; do
  setup
  agent infra sh -c "${how#*:}"
  check "a fix changing an existing ${how%%:*}: refused, nothing pushed" "$(pushfix) $(untouched)" "rc=1 fixed= untouched"
done
check "allowed: no subfolder a case pattern's * let in (a chart's ci/, ops' tasks/ and vault-recovery/); the unit's own files at any depth under clusters/" \
  "$(al schnappy/platform helm/schnappy/ci/values.yaml) $(al schnappy/ops deploy/ansible/playbooks/tasks/cnpg-backup.yml) $(al schnappy/ops deploy/ansible/vars/vault-recovery/x.yml) $(al schnappy/ops deploy/ansible/vars/vault.yml) $(al schnappy/ops deploy/ansible/playbooks/setup-vault-pi.yml) $(al schnappy/infra clusters/production/a/b/c.yaml) $(al schnappy/infra clusters/production/README.md)" \
  "no no no yes yes yes no"
echo "upgrade-fix-git: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
