#!/bin/bash
# deploy/ansible/playbooks/scripts/git-commit-push.sh (create- and destroy-environment's last phase - the playbooks
# called it from 2026-04-10, it was never in git), on a checkout of a bare repository here: a change committed with the
# message and pushed to main (the URL given, origin without one); nothing changed - nothing committed or pushed; a
# checkout not on main refused, nothing staged. And every script a production playbook's script: task names exists.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
ROOT=$PWD
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
S=$ROOT/deploy/ansible/playbooks/scripts/git-commit-push.sh
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1))
}
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 HOME=$W
git init -q --bare -b main "$W/remote.git"
git init -q -b main "$W/infra" && git -C "$W/infra" remote add origin "$W/remote.git"
echo a > "$W/infra/a" && git -C "$W/infra" add a && git -C "$W/infra" commit -qm base && git -C "$W/infra" push -q origin main
if [ ! -x "$S" ]; then
  check "the script there, executable" "missing" "there"
else
  echo b > "$W/infra/b"
  out=$(bash "$S" "$W/infra" "env: create x" 2>&1); rc=$?
  check "a change: committed with the message, pushed to origin's main" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main)" "0 env: create x"
  out=$(bash "$S" "$W/infra" "env: create y" 2>&1); rc=$?
  check "nothing changed: nothing committed or pushed, said" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main) $(grep -c 'NOTHING TO COMMIT' <<< "$out")" "0 env: create x 1"
  git init -q --bare -b main "$W/other.git"
  git -C "$W/other.git" fetch -q "$W/remote.git" main:main
  rm "$W/infra/b"
  out=$(bash "$S" "$W/infra" "env: destroy x" "$W/other.git" 2>&1); rc=$?
  check "a URL given: pushed there" "$rc $(git -C "$W/other.git" log -1 --format=%s main)" "0 env: destroy x"
  git -C "$W/infra" checkout -qb side && echo c > "$W/infra/c"
  out=$(bash "$S" "$W/infra" "env: create z" 2>&1); rc=$?
  check "a checkout not on main: refused, nothing staged" \
    "$rc $(grep -c 'REFUSED' <<< "$out") $(git -C "$W/infra" diff --cached --name-only | wc -l)" "1 1 0"
fi
# every script a production playbook runs by the script module exists (its path as Ansible renders playbook_dir)
missing=$(cd "$ROOT/deploy/ansible/playbooks" && python3 -c '
import glob, re, shlex, yaml
def walk(ts):
    for t in ts or []:
        if isinstance(t, dict):
            yield t
            for k in ("block", "rescue", "always"):
                yield from walk(t.get(k))
for f in sorted(glob.glob("*.yml") + glob.glob("tasks/*.yml")):
    doc = yaml.safe_load(open(f)) or []
    tasks = [t for p in doc for k in ("pre_tasks", "tasks", "post_tasks", "handlers") for t in walk(p.get(k))] \
        if doc and isinstance(doc[0], dict) and "hosts" in doc[0] else list(walk(doc))
    for t in tasks:
        a = t.get("ansible.builtin.script")
        if a is None:
            continue
        cmd = a if isinstance(a, str) else a.get("cmd", "")
        path = shlex.split(cmd.replace("{{ playbook_dir }}", "."))[0]
        if "{{" not in path and not __import__("os").path.isfile(path):
            print(f + ": " + path)
')
check "every script a playbook's script: task names exists" "${missing:-none}" "none"
echo "git-commit-push: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
