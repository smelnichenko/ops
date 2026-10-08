#!/bin/bash
# deploy/ansible/playbooks/scripts/git-commit-push.sh (create- and destroy-environment's last phase - the playbooks
# called it from 2026-04-10, it was never in git), on a checkout of a bare repository here: a change committed with the
# message and pushed to main (the URL given, origin without one); nothing changed - nothing committed or pushed; a
# checkout not on main refused, nothing staged. The remote's main moves on its own (the apps' CD pushes image tags):
# rebased onto, then pushed; a commit an earlier run could not push is pushed by the next, never "nothing to commit"
# and left; a conflict refused, the checkout left as it was. Before either playbook writes into the checkout it is made
# ready - on main, nothing uncommitted or untracked (it would be pushed with the environment's change), up to date.
# And every script a production playbook's script: task names exists.
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
  # the remote's main moved meanwhile (another clone's push)
  git clone -q "$W/remote.git" "$W/elsewhere" && echo t > "$W/elsewhere/tag" && git -C "$W/elsewhere" add tag \
    && git -C "$W/elsewhere" commit -qm "cd: image tag" && git -C "$W/elsewhere" push -q origin main
  echo q > "$W/infra/q"
  out=$(bash "$S" "$W/infra" "env: create q" 2>&1); rc=$?
  check "the remote's main moved meanwhile: rebased onto it, pushed - both there, this run's on top" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main) $(git -C "$W/remote.git" log --format=%s main | grep -c '^cd: image tag$')" \
    "0 env: create q 1"
  # a commit an earlier run made and could not push (rejected): the next run pushes it
  echo p > "$W/infra/p" && git -C "$W/infra" add p && git -C "$W/infra" commit -qm "env: create p"
  out=$(bash "$S" "$W/infra" "env: create p" 2>&1); rc=$?
  check "a commit an earlier run could not push: pushed by the next, nothing new to commit" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main)" "0 env: create p"
  # the same line changed on both sides: refused, nothing pushed, the checkout not left mid-rebase
  git -C "$W/elsewhere" pull -q --rebase origin main && echo theirs > "$W/elsewhere/a" \
    && git -C "$W/elsewhere" commit -qam "theirs" && git -C "$W/elsewhere" push -q origin main
  echo ours > "$W/infra/a"
  out=$(bash "$S" "$W/infra" "env: create c" 2>&1); rc=$?
  check "a conflict with the remote's main: refused, nothing pushed, no rebase left in progress" \
    "$rc $(grep -c 'REFUSED' <<< "$out") $(git -C "$W/remote.git" log -1 --format=%s main) \
$(ls -d "$(git -C "$W/infra" rev-parse --absolute-git-dir)"/rebase-* 2> /dev/null | wc -l) \
$(git -C "$W/infra" branch --show-current)" "1 1 theirs 0 main"
  git -C "$W/infra" reset -q --hard "$(git -C "$W/remote.git" rev-parse main)"
  # ready: before a playbook writes into the checkout
  echo d > "$W/infra/a"
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "ready, a change not committed: refused" "$rc $(grep -c 'REFUSED' <<< "$out")" "1 1"
  git -C "$W/infra" checkout -q a && echo u > "$W/infra/untracked"
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "ready, a file not tracked: refused" "$rc $(grep -c 'REFUSED' <<< "$out")" "1 1"
  rm "$W/infra/untracked"
  echo n > "$W/elsewhere/n" && git -C "$W/elsewhere" add n && git -C "$W/elsewhere" commit -qm "newer" \
    && git -C "$W/elsewhere" push -q origin main
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "ready, clean and behind: brought up to date, said (a change)" \
    "$rc $(git -C "$W/infra" log -1 --format=%s main) $(grep -c 'READY.*UPDATED' <<< "$out")" "0 newer 1"
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "ready, up to date already: no change said" "$rc $(grep -c READY <<< "$out") $(grep -c UPDATED <<< "$out")" "0 1 0"
  git -C "$W/infra" checkout -qb side && echo c > "$W/infra/c"
  out=$(bash "$S" "$W/infra" "env: create z" 2>&1); rc=$?
  check "a checkout not on main: refused, nothing staged" \
    "$rc $(grep -c 'REFUSED' <<< "$out") $(git -C "$W/infra" diff --cached --name-only | wc -l)" "1 1 0"
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "ready, not on main: refused" "$rc $(grep -c 'REFUSED' <<< "$out")" "1 1"
fi
# both playbooks: the checkout made ready before anything reads or writes it, the commit after; git's identity on both
order=$(cd "$ROOT/deploy/ansible/playbooks" && python3 -c '
import yaml
for book in ("create-environment", "destroy-environment"):
    tasks = [t for p in yaml.safe_load(open(book + ".yml")) for k in ("pre_tasks", "tasks") for t in p.get(k) or []]
    infra = [t for t in tasks if "cluster_dir" in str(t) or "infra_dir" in str(t)]
    first, last = (str((t.get("ansible.builtin.script") or {}).get("cmd", "")) for t in (infra[0], infra[-1]))
    ident = all("GIT_COMMITTER_NAME" in (t.get("environment") or {}) for t in (infra[0], infra[-1]))
    print(book, "git-commit-push.sh ready" in first, "git-commit-push.sh ready" not in last and "git-commit-push.sh" in last,
          ident, end=" ")
')
check "both playbooks: ready first, before reading or writing the checkout; committed last; git's identity on both" \
  "$order" "create-environment True True True destroy-environment True True True "
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
