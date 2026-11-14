#!/bin/bash
# Every `--tags T` a Taskfile command passes to a playbook names a tag that playbook holds - in its plays, its tasks or a
# task file it includes. A tag misspelt, or one removed from the playbook, runs nothing and reports success (the
# operator answered the prompt; deploy:cilium:upgrade upgraded nothing). Walked: Taskfile.yml's commands.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import os, re, sys
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
PB = "deploy/ansible/playbooks"
def tags_of(node, base, seen):
    """Every tag under a play, task or task list - included task files followed (beside the includer, then the
    playbook's directory)."""
    found = set()
    if isinstance(node, list):
        for x in node:
            found |= tags_of(x, base, seen)
    elif isinstance(node, dict):
        t = node.get("tags")
        found |= set([t] if isinstance(t, str) else t or [])
        for k in ("ansible.builtin.include_tasks", "ansible.builtin.import_tasks", "include_tasks", "import_tasks"):
            inc = node.get(k)
            if inc:
                f = inc if isinstance(inc, str) else inc.get("file", "")
                apply = (inc.get("apply") or {}).get("tags") if isinstance(inc, dict) else None
                found |= set([apply] if isinstance(apply, str) else apply or [])
                path = os.path.join(base, f) if os.path.exists(os.path.join(base, f)) else os.path.join(PB, f)
                if path not in seen and os.path.exists(path):
                    seen.add(path)
                    found |= tags_of(yaml.safe_load(open(path)), os.path.dirname(path), seen)
        for k in ("tasks", "pre_tasks", "post_tasks", "handlers", "block", "rescue", "always"):
            found |= tags_of(node.get(k), base, seen)
    return found
uses = []
for task, spec in (yaml.safe_load(open("Taskfile.yml")).get("tasks") or {}).items():
    for c in (spec or {}).get("cmds") or []:
        cmd = c if isinstance(c, str) else (c or {}).get("cmd", "") if isinstance(c, dict) else ""
        for m in re.finditer(r"playbooks/([a-z0-9_-]+\.yml)\b[^\n]*?--tags[ =]([A-Za-z0-9_,-]+)", cmd or ""):
            uses.append((task, m.group(1), m.group(2)))
check("the Taskfile's --tags uses found (deploy:cilium:upgrade's among them)",
      len(uses) >= 5 and ("deploy:cilium:upgrade", "setup-kubeadm.yml", "cilium") in uses, True)
for task, pb, tags in uses:
    have = tags_of(yaml.safe_load(open(os.path.join(PB, pb))), PB, set())
    for t in tags.split(","):
        check(f"{task}: --tags {t} - a tag of {pb}", t in have, True)
print("taskfile-tags: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
