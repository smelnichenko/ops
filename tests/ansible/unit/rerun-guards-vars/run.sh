#!/bin/bash
# test-pi-rerun-guards.yml's plays render what they use from their own vars and the Vagrant inventory - a play's vars
# are its own: one that names setup-consul's (pi1_ip, pi2_ip, ten_ip) without defining them fails on the Pis before
# its proof runs. Every task's loop and every plain {{ name }} in the Consul plays rendered with the play's vars and
# the inventory's hosts.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYRGV'
import re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, trust_as_template  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
inv = yaml.safe_load(open("deploy/ansible/inventory/vagrant.yml"))
hosts = {}
def walk(g):
    for n, h in ((g or {}).get("hosts") or {}).items():
        hosts.setdefault(n, {}).update(h or {})
    for c in ((g or {}).get("children") or {}).values():
        walk(c)
walk(inv.get("all", inv))
plays = [p for p in yaml.safe_load(open("tests/ansible/test-pi-rerun-guards.yml")) if "tasks" in p]
SERVERS = ("pi1_ip", "pi2_ip", "ten_ip")
users = [p for p in plays if any(re.search(r"\b%s\b" % n, str(p["tasks"])) for n in SERVERS)]
check("plays naming the servers' addresses found", len(users) > 0, True)
for p in users:
    # a play's vars are templates to Ansible (its loader marks them trusted), as they are here
    v = dict({k: trust_as_template(x) if isinstance(x, str) else x for k, x in (p.get("vars") or {}).items()},
             hostvars=hosts, inventory_hostname="pi1", groups={"pis": ["pi1", "pi2"]})
    try:
        got = [str(render("{{ %s }}" % n, **v)) for n in SERVERS]
    except Exception as e:  # noqa: BLE001 - the templar's undefined is what this looks for
        got = f"{type(e).__name__}: {str(e).splitlines()[0]}"
    check(f"{p['name']}: the servers' addresses defined in the play, the inventory's",
          got, [str(hosts[h]["ansible_host"]) for h in ("pi1", "pi2", "target")])
print("rerun-guards-vars: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYRGV
