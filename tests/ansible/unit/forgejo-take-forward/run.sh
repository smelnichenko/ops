#!/bin/bash
# upgrade-forgejo.yml's first Pi, its expressions as Ansible evaluates them: a Forgejo whose API is silent while its unit
# is active or activating is starting (a cut-short run's, maybe migrating) - it goes first whatever holds the VIP now,
# never another beside it; two starting at once refuse; with none starting, the VIP's holder goes first.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "forgejo-take-forward: no python3 with ansible and yaml"; exit 2; }
"$PY" - <<'PY'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, condition
tasks = {t.get("name"): t for t in yaml.safe_load(open("deploy/ansible/playbooks/upgrade-forgejo.yml"))[0]["tasks"]}
facts = tasks["Its version numbers - served and installed"]["ansible.builtin.set_fact"]
one = tasks["At most one Forgejo starting (two would be migrating one database)"]["ansible.builtin.assert"]["that"]
first = tasks["The first Pi"]["ansible.builtin.set_fact"]["_first"]
def host(name, served, state, vip):
    h = {"inventory_hostname": name, "_addrs": {"stdout": "inet 192.168.11.5" if vip else ""}}
    # set_fact keeps the bool Ansible's templar returns - selectattr below reads it as Ansible's hostvars hold it
    h["_starting"] = render(facts["_starting"], _served={"status": 200 if served else -1},
                            _unit={"status": {"ActiveState": state}})
    return h
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f": got {got}, want {want}"))
def case(pi1, pi2):
    hv = {"pi1": host("pi1", *pi1), "pi2": host("pi2", *pi2)}
    ctx = {"hostvars": hv, "ansible_play_hosts": ["pi1", "pi2"]}
    return condition(one, **ctx), render(first, **ctx)
check("pi2 migrating (active, silent), the VIP on pi1: pi2 first", case((False, "inactive", True), (False, "active", False)),
      (True, "pi2"))
check("pi2 activating, the VIP on pi1: pi2 first", case((False, "failed", True), (False, "activating", False)),
      (True, "pi2"))
check("both down (inactive), the VIP on pi2: pi2 first", case((False, "inactive", False), (False, "inactive", True)),
      (True, "pi2"))
check("both serving, the VIP on pi1: pi1 first", case((True, "active", True), (True, "active", False)), (True, "pi1"))
check("both starting: refused", case((False, "active", True), (False, "activating", False))[0], False)
# a run taken forward skips every task under `not _forward`: Ansible registers {skipped: true} for each, so a task
# that still runs and reads such a result's field (rc, stdout - not skipped or changed, none with | default) fails
skipped, reads = set(), []
for t in yaml.safe_load(open("deploy/ansible/playbooks/upgrade-forgejo.yml"))[0]["tasks"]:
    when = " ".join(map(str, t.get("when", []) if isinstance(t.get("when"), list) else [t.get("when", "")]))
    forward_skips = bool(__import__("re").search(r"not\s+_forward\b", when))
    if not forward_skips:
        body = yaml.safe_dump({k: v for k, v in t.items() if k != "register"}, width=10000)
        for reg in skipped:
            for m in __import__("re").finditer(rf"\b{reg}\.(\w+)(?!\w)", body):
                if m[1] not in ("skipped", "changed") and not __import__("re").match(r"\s*\|\s*default\b", body[m.end():]):
                    reads.append(f"{t.get('name')}: {reg}.{m[1]}")
    if "register" in t and forward_skips:
        skipped.add(t["register"])
check("taken forward: no task that runs reads a result the run skipped", reads, [])
print("forgejo-take-forward: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
