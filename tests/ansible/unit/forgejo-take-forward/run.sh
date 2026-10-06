#!/bin/bash
# upgrade-forgejo.yml's first Pi, its expressions as Ansible evaluates them: a Forgejo whose API is silent while its unit
# is active or activating is starting (a cut-short run's, maybe migrating) - it goes first whatever holds the VIP now,
# never another beside it; two starting at once refuse; with none starting, the VIP's holder goes first.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "forgejo-take-forward: no python3 with jinja2 and yaml"; exit 2; }
"$PY" - <<'PY'
import sys
import jinja2, yaml
tasks = {t.get("name"): t for t in yaml.safe_load(open("deploy/ansible/playbooks/upgrade-forgejo.yml"))[0]["tasks"]}
env = jinja2.Environment()
env.filters["extract"] = lambda key, hv: hv[key]
env.filters["regex_search"] = lambda s, p: __import__("re").search(p, s) and __import__("re").search(p, s).group(0)
render = lambda text, **ctx: env.from_string(text).render(**ctx).strip()
facts = tasks["Its version numbers - served and installed"]["ansible.builtin.set_fact"]
one = env.compile_expression(tasks["At most one Forgejo starting (two would be migrating one database)"]
                             ["ansible.builtin.assert"]["that"])
first = tasks["The first Pi"]["ansible.builtin.set_fact"]["_first"]
def host(name, served, state, vip):
    h = {"inventory_hostname": name, "_addrs": {"stdout": "inet 192.168.11.5" if vip else ""}}
    h["_starting"] = render(facts["_starting"], _served={"status": 200 if served else -1},
                            _unit={"status": {"ActiveState": state}}) == "True"
    return h
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f": got {got}, want {want}"))
def case(pi1, pi2):
    hv = {"pi1": host("pi1", *pi1), "pi2": host("pi2", *pi2)}
    ctx = {"hostvars": hv, "ansible_play_hosts": ["pi1", "pi2"]}
    return bool(one(**ctx)), render(first, **ctx)
check("pi2 migrating (active, silent), the VIP on pi1: pi2 first", case((False, "inactive", True), (False, "active", False)),
      (True, "pi2"))
check("pi2 activating, the VIP on pi1: pi2 first", case((False, "failed", True), (False, "activating", False)),
      (True, "pi2"))
check("both down (inactive), the VIP on pi2: pi2 first", case((False, "inactive", False), (False, "inactive", True)),
      (True, "pi2"))
check("both serving, the VIP on pi1: pi1 first", case((True, "active", True), (True, "active", False)), (True, "pi1"))
check("both starting: refused", case((False, "active", True), (False, "activating", False))[0], False)
print("forgejo-take-forward: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
