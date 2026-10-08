#!/bin/bash
# tests/ansible/unit/plays.py - the walk the class harnesses share - on a fixture: every task of every play section
# (pre_tasks, tasks, post_tasks, handlers) and of a block (block, rescue, always) found, a task file's too, nothing of a
# vars file; a task's keywords Ansible's own (listen, throttle, timeout - a hand-kept list lacked some), its action the
# rest; a file Ansible cannot read fails, not skipped.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PY'
import os, sys, tempfile
import yaml
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, plays, tasks
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
t = lambda n, **k: {"name": n, "ansible.builtin.command": "true", **k}
book = [{"hosts": "all", "pre_tasks": [t("pre")], "tasks": [t("task"), {"name": "blk", "block": [t("in-block")],
         "rescue": [t("in-rescue")], "always": [t("in-always")]}], "post_tasks": [t("post")],
         "handlers": [t("handler", listen="x")]}, {"import_playbook": "other.yml"}]
check("a playbook: every section's tasks, each block's after it",
      [x["name"] for x in tasks(book)], ["pre", "task", "blk", "in-block", "in-rescue", "in-always", "post", "handler"])
check("a playbook's plays", [p.get("hosts", p.get("import_playbook")) for p in plays(book)], ["all", "other.yml"])
check("a task file: its tasks", [x["name"] for x in tasks([t("a"), t("b")])], ["a", "b"])
check("a vars file, an inventory: none", list(tasks({"all": {"hosts": {"pi1": {}}}, "ansible.builtin.command": "x"})), [])
check("keywords Ansible's own: a task's action is the rest",
      [m for m, _ in actions({"name": "x", "listen": "y", "throttle": 1, "timeout": 5, "with_items": [1],
                               "ansible.builtin.debug": {"msg": 1}})], ["ansible.builtin.debug"])
check("a block: no action", actions({"name": "b", "block": []}), [])
# an import by its full name is a play too (31 files write it so), never a task; an action: key names its module
check("ansible.builtin.import_playbook: a play, not a task", ([p for p in plays([{"ansible.builtin.import_playbook": "o.yml"}])] != [],
      list(tasks([{"name": "i", "ansible.builtin.import_playbook": "o.yml"}]))), (True, []))
check("action: its module (free form, or a mapping)",
      [m for t in ({"action": "ansible.builtin.shell echo x"}, {"action": {"module": "ansible.builtin.shell", "cmd": "x"}})
       for m, _ in actions(t)], ["ansible.builtin.shell", "ansible.builtin.shell"])
check("local_action: its module", [m for m, _ in actions({"local_action": "ansible.builtin.command echo"})],
      ["ansible.builtin.command"])
bad = tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False)
bad.write("- name: x\n  shell: 'unclosed\n")
bad.close()
try:
    load(bad.name)
    got = "read"
except yaml.YAMLError:
    got = "failed"
check("a file Ansible cannot read: fails, not skipped", got, "failed")
os.remove(bad.name)
check("the repo's files: playbooks and tests found, no virtualenv", (len(files()) > 100,
      any("/venv/" in f for f in files())), (True, False))
print("plays-walk: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
