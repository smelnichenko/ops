#!/bin/bash
# upgrade-backup.yml's check that each Scylla snapshot was taken by this backup, its assert evaluated as Ansible does:
# a snapshot named after the backup started passes, one from before fails - both on the node's clock, which names the
# snapshots; a controller whose clock runs ahead of the node's no longer fails a fresh one.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "scylla-snapshot-fresh: no python3 with ansible and yaml (PATH, repo venv)"; exit 2; }
"$PY" - <<'PY'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
def walk(items):
    for t in items or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))
tasks = {t.get("name"): t for p in yaml.safe_load(open("deploy/ansible/playbooks/upgrade-backup.yml"))
         for t in walk(p.get("tasks"))}
fresh = "{{ %s }}" % tasks["Scylla - every snapshot taken by this run"]["ansible.builtin.assert"]["that"]
node_t0, controller = "20261006203000", "20261006T203030Z"  # the controller 30 s ahead of the node
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}")
for tag, want, what in (("sm_20261006203005UTC", True, "taken 5 s into the backup (node clock), controller 30 s ahead"),
                        ("sm_20261006202900UTC", False, "taken a minute before the backup")):
    r = {"stdout": f"Status: DONE\nSnapshot Tag: {tag}\n", "item": "c name t loc"}
    check(f"a snapshot {what}: {'passes' if want else 'fails'}",
          render(fresh, r=r, _stamp=controller, _scylla_t0={"stdout": node_t0}), want)
print("scylla-snapshot-fresh: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
