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
# the script's commits by the environments' automation (its playbooks' identity); another's by someone
export GIT_AUTHOR_NAME=env-automation GIT_AUTHOR_EMAIL=a@a GIT_COMMITTER_NAME=env-automation GIT_COMMITTER_EMAIL=a@a
export GIT_CONFIG_NOSYSTEM=1 HOME=$W
someone() { GIT_AUTHOR_NAME=someone GIT_COMMITTER_NAME=someone git "$@"; }
git init -q --bare -b main "$W/remote.git"
git init -q -b main "$W/infra" && git -C "$W/infra" remote add origin "$W/remote.git"
mkdir -p "$W/infra/env" && echo a > "$W/infra/a" && echo e > "$W/infra/env/base" && git -C "$W/infra" add -A \
  && someone -C "$W/infra" commit -qm base && git -C "$W/infra" push -q origin main
if [ ! -x "$S" ]; then
  check "the script there, executable" "missing" "there"
else
  # commit mode: the environment's paths after --, relative to the checkout
  push() { bash "$S" "$W/infra" "$1" "${2:-}" -- env/x env/y 2>&1; }
  echo b > "$W/infra/env/x"
  out=$(push "env: create x"); rc=$?
  check "a change in the environment's paths: committed with the message, pushed to origin's main" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main)" "0 env: create x"
  out=$(push "env: create y"); rc=$?
  check "nothing changed: nothing committed or pushed, said - nothing said pushed (the playbooks' changed reads it)" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main) $(grep -c 'NOTHING TO COMMIT' <<< "$out") \
$(grep -c 'NOTHING TO PUSH' <<< "$out") $(grep -c 'PUSHED' <<< "$out")" "0 env: create x 1 1 0"
  out=$(bash "$S" "$W/infra" "env: create z" "" 2>&1); rc=$?
  check "no paths given: refused (it would stage the whole checkout)" "$rc $(grep -c 'REFUSED' <<< "$out")" "1 1"
  git init -q --bare -b main "$W/other.git"
  git -C "$W/other.git" fetch -q "$W/remote.git" main:main
  rm "$W/infra/env/x"
  out=$(push "env: destroy x" "$W/other.git"); rc=$?
  check "a URL given: pushed there (a removal staged too)" "$rc $(git -C "$W/other.git" log -1 --format=%s main)" \
    "0 env: destroy x"
  # another session's edit outside the environment's paths: refused - nothing staged, committed or pushed
  echo y > "$W/infra/env/y" && echo theirs-wip > "$W/infra/a"
  out=$(push "env: create w"); rc=$?
  check "a change outside the environment's paths (another's work): refused, named - nothing staged, committed, pushed" \
    "$rc $(grep -c 'REFUSED.* a' <<< "$out") $(git -C "$W/infra" diff --cached --name-only | wc -l) \
$(git -C "$W/remote.git" log -1 --format=%s main)" "1 1 0 env: create x"
  git -C "$W/infra" checkout -q a
  out=$(push "env: create w"); rc=$?
  check "... its change gone: the environment's committed, pushed" "$rc $(git -C "$W/remote.git" log -1 --format=%s main)" \
    "0 env: create w"
  # a path there that git knows nothing in (an empty directory): the change of the others committed, pushed (the
  # commit named it and git refused: "pathspec did not match", the change left staged)
  mkdir -p "$W/infra/env/emptydir" && echo v > "$W/infra/env/x"
  out=$(bash "$S" "$W/infra" "env: create v" "" -- env/x env/emptydir 2>&1); rc=$?
  check "a path git knows nothing in (an empty directory) among them: the others' change committed, pushed" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main)" "0 env: create v"
  rmdir "$W/infra/env/emptydir"
  # main checked again before each rebase: another session's switch between the commit and the rebase (its branch
  # rebased onto the remote's main) - refused, its branch as it was. Forced in a copy: the switch right before it
  sed 's|^    onto_remote "\$dir" "\$url"$|    git -C "$dir" checkout -q -b elsewhere\n&|' "$S" > "$W/switching.sh"
  someone clone -q "$W/remote.git" "$W/clone2" && echo m > "$W/clone2/moved" && someone -C "$W/clone2" add moved \
    && someone -C "$W/clone2" commit -qm moved && someone -C "$W/clone2" push -q origin main
  echo w2 > "$W/infra/env/x"
  out=$(bash "$W/switching.sh" "$W/infra" "env: create u" "" -- env/x env/y 2>&1); rc=$?
  check "a branch switched before the rebase (forced): refused, not main - that branch not rebased, nothing pushed" \
    "$(grep -c '^    git -C "\$dir" checkout -q -b elsewhere$' "$W/switching.sh") $rc $(grep -c 'not main' <<< "$out") \
$(git -C "$W/infra" log -1 --format=%s elsewhere) $(git -C "$W/remote.git" log -1 --format=%s main)" \
    "1 1 1 env: create u moved"
  git -C "$W/infra" checkout -q main && git -C "$W/infra" branch -q -D elsewhere
  git -C "$W/infra" fetch -q origin && git -C "$W/infra" reset -q --hard origin/main
  # the remote's main moved meanwhile (another clone's push)
  git clone -q "$W/remote.git" "$W/elsewhere" && echo t > "$W/elsewhere/tag" && git -C "$W/elsewhere" add tag \
    && someone -C "$W/elsewhere" commit -qm "cd: image tag" && git -C "$W/elsewhere" push -q origin main
  echo q > "$W/infra/env/x"
  out=$(push "env: create q"); rc=$?
  check "the remote's main moved meanwhile: rebased onto it, pushed - both there, this run's on top" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main) $(git -C "$W/remote.git" log --format=%s main | grep -c '^cd: image tag$')" \
    "0 env: create q 1"
  # a commit an earlier run made and could not push (rejected): the next run pushes it
  echo p > "$W/infra/env/y" && git -C "$W/infra" add env/y && git -C "$W/infra" commit -qm "env: create p"
  out=$(push "env: create p"); rc=$?
  check "a commit an earlier run could not push (the automation's): pushed by the next, nothing new to commit" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main)" "0 env: create p"
  # a commit of another's ahead (held back, another session's): refused - in both modes - nothing pushed
  echo h > "$W/infra/held" && git -C "$W/infra" add held && someone -C "$W/infra" commit -qm "WIP: held back"
  echo r > "$W/infra/env/x"
  out=$(push "env: create r"); rc=$?
  check "a commit not the automation's ahead: refused, named - nothing pushed" \
    "$rc $(grep -c 'REFUSED.*WIP: held back' <<< "$out") $(git -C "$W/remote.git" log --format=%s main | grep -c 'WIP')" "1 1 0"
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "... ready refuses it too" "$rc $(grep -c 'REFUSED.*WIP: held back' <<< "$out")" "1 1"
  git -C "$W/infra" checkout -q env/x
  git -C "$W/infra" reset -q --hard "$(git -C "$W/remote.git" rev-parse main)"
  # the remote's main read into a ref of the script's own: a fetch of another branch in between (FETCH_HEAD) is no base
  git -C "$W/elsewhere" pull -q --rebase origin main && git -C "$W/elsewhere" checkout -qb other \
    && echo o > "$W/elsewhere/o" && git -C "$W/elsewhere" add o && someone -C "$W/elsewhere" commit -qm "other branch" \
    && git -C "$W/elsewhere" push -q origin other && git -C "$W/elsewhere" checkout -q main
  mkdir -p "$W/wrap" && cat > "$W/wrap/git" <<'WRAP'
#!/bin/bash
/usr/bin/git "$@"; rc=$?
# another fetch right after the script's own, in the same checkout - FETCH_HEAD then the other branch
case "$*" in *" fetch "*" main"*) /usr/bin/git -C "$INFRA" fetch -q origin other ;; esac
exit $rc
WRAP
  chmod +x "$W/wrap/git"
  echo f > "$W/infra/env/x"
  out=$(INFRA=$W/infra PATH="$W/wrap:$PATH" push "env: create f"); rc=$?
  check "another fetch between the script's fetch and its rebase: rebased onto the remote's main, never that branch" \
    "$rc $(git -C "$W/remote.git" log --format=%s main | grep -c '^other branch$')" "0 0"
  # the remote's main moved by another clone right before the script's push (the apps' CD pushing tags): rejected,
  # rebased onto it, pushed again - three tries; moved before each, refused, nothing of this run's pushed
  mkdir -p "$W/move" && cat > "$W/move/git" <<'WRAP'
#!/bin/bash
if [ "$1" = -C ] && [ "$2" = "$INFRA" ] && [ "$3" = push ]; then
  n=$(( $(cat "$MOVED" 2> /dev/null || echo 0) + 1 )); echo "$n" > "$MOVED"
  if [ "$n" -le "$MOVES" ]; then
    echo "$n" > "$ELSEWHERE/tag-${MOVED##*/}-$n" && /usr/bin/git -C "$ELSEWHERE" add . \
      && GIT_AUTHOR_NAME=someone GIT_COMMITTER_NAME=someone /usr/bin/git -C "$ELSEWHERE" commit -qm "cd: tag $n" \
      && /usr/bin/git -C "$ELSEWHERE" pull -q --rebase origin main && /usr/bin/git -C "$ELSEWHERE" push -q origin main
  fi
fi
exec /usr/bin/git "$@"
WRAP
  chmod +x "$W/move/git"
  git -C "$W/elsewhere" pull -q --rebase origin main
  echo m > "$W/infra/env/x"
  out=$(INFRA=$W/infra ELSEWHERE=$W/elsewhere MOVES=1 MOVED=$W/moved1 PATH="$W/move:$PATH" push "env: create m"); rc=$?
  check "the remote moved just before the push: rejected, rebased, pushed on the second try - both there, ours on top" \
    "$rc $(cat "$W/moved1") $(git -C "$W/remote.git" log -1 --format=%s main) \
$(git -C "$W/remote.git" log --format=%s main | grep -c '^cd: tag 1$')" "0 2 env: create m 1"
  echo n > "$W/infra/env/x"
  out=$(INFRA=$W/infra ELSEWHERE=$W/elsewhere MOVES=3 MOVED=$W/moved3 PATH="$W/move:$PATH" push "env: create n"); rc=$?
  check "the remote moved before each of three pushes: refused, said - nothing of this run's pushed" \
    "$rc $(cat "$W/moved3") $(grep -c 'not pushed to .* in three tries' <<< "$out") \
$(git -C "$W/remote.git" log --format=%s main | grep -c '^env: create n$')" "1 3 1 0"
  git -C "$W/infra" fetch -q origin main && git -C "$W/infra" reset -q --hard "$(git -C "$W/remote.git" rev-parse main)"
  # a rename staged from outside the environment's paths into them (git mv a env/y): its source is another's change -
  # refused, named; its status line names the destination alone (R  a -> env/y), and the commit took the whole index
  echo a > "$W/infra/outside" && git -C "$W/infra" add outside && { git -C "$W/infra" rm -q --ignore-unmatch env/y; } \
    && git -C "$W/infra" commit -qm "env: outside file, no y" && git -C "$W/infra" push -q origin main
  git -C "$W/infra" mv outside env/y
  check "the rename staged as one (R  outside -> env/y)" "$(git -C "$W/infra" status --porcelain | grep -c '^R  outside -> env/y$')" 1
  out=$(push "env: create renamed"); rc=$?
  check "a rename staged from outside into the environment's paths: refused, its source named - nothing pushed" \
    "$rc $(grep -c 'REFUSED.*outside' <<< "$out") $(git -C "$W/remote.git" ls-tree --name-only main | grep -c '^outside$')" \
    "1 1 1"
  git -C "$W/infra" reset -q --hard "$(git -C "$W/remote.git" rev-parse main)"
  # another session in the same checkout while the script runs: a file of its own staged after the script's check,
  # a commit of its own made after the script's - neither pushed (the commit takes the environment's paths alone, the
  # push the head the script checked)
  mkdir -p "$W/race" && cat > "$W/race/git" <<'WRAP'
#!/bin/bash
if [ "$1" = -C ] && [ "$2" = "$INFRA" ]; then
  case "$3 $4" in
    "add -A") echo theirs > "$INFRA/staged-by-another" && /usr/bin/git -C "$INFRA" add staged-by-another ;;
    "push -q") [ -z "${COMMIT_BEFORE_PUSH:-}" ] || { echo w > "$INFRA/wip" && /usr/bin/git -C "$INFRA" add wip \
      && GIT_AUTHOR_NAME=someone GIT_COMMITTER_NAME=someone /usr/bin/git -C "$INFRA" commit -qm "WIP: another's" -- wip; } ;;
  esac
fi
exec /usr/bin/git "$@"
WRAP
  chmod +x "$W/race/git"
  echo s > "$W/infra/env/x"
  out=$(INFRA=$W/infra PATH="$W/race:$PATH" push "env: create s"); rc=$?
  check "another's file staged after the script's check: the environment's commit without it, pushed" \
    "$rc $(git -C "$W/remote.git" show --name-only --format= main | tr '\n' ' ')" "0 env/x "
  git -C "$W/infra" reset -q staged-by-another && rm -f "$W/infra/staged-by-another"
  echo t > "$W/infra/env/x"
  out=$(INFRA=$W/infra COMMIT_BEFORE_PUSH=1 PATH="$W/race:$PATH" push "env: create t"); rc=$?
  check "another's commit made just before the push: the head the script checked pushed, never that commit" \
    "$rc $(git -C "$W/remote.git" log -1 --format=%s main) $(git -C "$W/remote.git" log --format=%s main | grep -c "^WIP: another's$")" \
    "0 env: create t 0"
  git -C "$W/infra" reset -q staged-by-another 2> /dev/null; rm -f "$W/infra/staged-by-another"
  git -C "$W/infra" reset -q --hard "$(git -C "$W/remote.git" rev-parse main)"
  # the same line changed on both sides: refused, nothing pushed, the checkout not left mid-rebase
  git -C "$W/elsewhere" pull -q --rebase origin main && echo theirs > "$W/elsewhere/env/x" \
    && someone -C "$W/elsewhere" commit -qam "theirs" && git -C "$W/elsewhere" push -q origin main
  echo ours > "$W/infra/env/x"
  out=$(push "env: create c"); rc=$?
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
  echo n > "$W/elsewhere/n" && git -C "$W/elsewhere" add n && someone -C "$W/elsewhere" commit -qm "newer" \
    && git -C "$W/elsewhere" push -q origin main
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "ready, clean and behind: brought up to date, said (a change)" \
    "$rc $(git -C "$W/infra" log -1 --format=%s main) $(grep -c 'READY.*UPDATED' <<< "$out")" "0 newer 1"
  out=$(bash "$S" ready "$W/infra" 2>&1); rc=$?
  check "ready, up to date already: no change said" "$rc $(grep -c READY <<< "$out") $(grep -c UPDATED <<< "$out")" "0 1 0"
  git -C "$W/infra" checkout -qb side && echo c > "$W/infra/env/x"
  out=$(push "env: create z"); rc=$?
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
    # the paths it commits: every one a task of it writes, relative to the checkout
    play = yaml.safe_load(open(book + ".yml"))[0]
    vf = {k: v for f in play.get("vars_files") or [] for k, v in (yaml.safe_load(open(f)) or {}).items()}
    paths = [str(x) for x in {**vf, **(play.get("vars") or {})}.get("_infra_env_paths") or []]
    written = {str((t.get(m) or {}).get(k)).replace("{{ item }}", str(i)) for t in tasks
               for m in ("ansible.builtin.copy", "ansible.builtin.file", "ansible.builtin.lineinfile",
                         "ansible.builtin.template") for k in ("dest", "path")
               if isinstance(t.get(m), dict) and (t.get(m) or {}).get(k) for i in (t.get("loop") or ["{{ item }}"])}
    rel = lambda w: w.replace("{{ cluster_dir }}", "clusters/production")
    covered = all(any(rel(w) == p or rel(w).startswith(p + "/") for p in paths) or rel(w) in (
        "clusters/production/cluster-config", "clusters/production/argocd/apps") for w in written)  # dirs made, no file
    print(book, "git-commit-push.sh ready" in first, "git-commit-push.sh ready" not in last and "git-commit-push.sh" in last
          and " -- " in last and "_infra_env_paths" in last, ident, bool(paths) and covered, end=" ")
')
check "both playbooks: ready first; committed last with the environment's paths (every one a task writes); identity" \
  "$order" "create-environment True True True True destroy-environment True True True True "
# one list of the environment's paths, both playbooks' (two copies drifted: a path one wrote and the other's commit
# left out); env_name held to one pattern by both before anything - destroy's took any (a path out of the checkout,
# a quote into its inline Python)
same=$(cd "$ROOT/deploy/ansible/playbooks" && python3 -c '
import yaml
out = []
for book in ("create-environment", "destroy-environment"):
    play = yaml.safe_load(open(book + ".yml"))[0]
    first = (play.get("pre_tasks") or [{}])[0]
    that = (first.get("ansible.builtin.assert") or {}).get("that") or []
    out.append((book, "_infra_env_paths" in (play.get("vars") or {}), play.get("vars_files"),
                any("^[a-z0-9-]+$" in str(x) and "match" in str(x) for x in that)))
print(out)
')
check "both playbooks: one list of the environment paths (a vars file, no copy of their own); env_name matched first" \
  "$same" "[('create-environment', False, ['../vars/environment-paths.yml'], True), ('destroy-environment', False, ['../vars/environment-paths.yml'], True)]"
# the commit reported changed when it pushed alone (it said "changed" on every run, nothing pushed among them)
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=$ROOT/deploy/ansible/venv/bin/python3
changed=$(cd "$ROOT" && PYTHONDONTWRITEBYTECODE=1 "$PY" -c '
import sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition
for book in ("create-environment", "destroy-environment"):
    tasks = [t for p in yaml.safe_load(open(f"deploy/ansible/playbooks/{book}.yml")) for k in ("pre_tasks", "tasks")
             for t in p.get(k) or []]
    t = next(t for t in tasks if " -- " in str((t.get("ansible.builtin.script") or {}).get("cmd", "")))
    reg = t.get("register", "_none")
    print(book, [condition(t.get("changed_when", True), **{reg: {"stdout": out}})
                 for out in ("PUSHED: env: create x\n", "NOTHING TO COMMIT\nNOTHING TO PUSH\n")], end=" ")
')
check "both playbooks' commit: changed when it pushed, not when nothing was" "$changed" \
  "create-environment [True, False] destroy-environment [True, False] "
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
