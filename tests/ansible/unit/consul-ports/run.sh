#!/bin/bash
# setup-consul.yml as the playbook holds it (its config rendered, its conditions evaluated by Ansible's templar): the
# WAN ports it closes are the WAN serf it turns off (one datacenter - nothing joins over WAN; left on behind a closed
# port, every server logged its WAN peers failed); its firewall rules run on every Pi and nowhere else (ten has no
# UFW), and a Pi without UFW is refused - it skipped them, RPC and Serf left open to the LAN.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCP'
import re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
from plays import load, tasks  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
book = load("deploy/ansible/playbooks/setup-consul.yml")
every = list(tasks(book))
conf = next(t for t in every if (t.get("ansible.builtin.copy") or {}).get("dest") == "/etc/consul.d/consul.hcl")
hcl = render(conf["ansible.builtin.copy"]["content"], consul_datacenter="dc1", inventory_hostname="pi1",
             node_ip="10.0.0.1", pi1_ip="10.0.0.1", pi2_ip="10.0.0.2", ten_ip="10.0.0.3", consul_encrypt_key="K",
             consul_servers=["pi1", "pi2", "ten"], groups={"pis": ["pi1", "pi2"]})
ports = re.search(r"^ports\s*\{([^}]*)\}", hcl, re.M)
closed = next(t for t in every if (t.get("community.general.ufw") or {}).get("delete") is True)
closed_ports = {str(x["port"]) for x in closed["loop"]}
check("the WAN ports closed, the WAN serf off", ("8302" in closed_ports,
      bool(ports and re.search(r"^\s*serf_wan\s*=\s*-1\s*$", ports.group(1), re.M))), (True, True))
rules = [t for t in every if "community.general.ufw" in t]
def runs(t, host, ufw):
    return condition(t.get("when", True), inventory_hostname=host, groups={"pis": ["pi1", "pi2"]},
                     _ufw={"stat": {"exists": ufw}})
check("every firewall rule on each Pi, none on ten", [(runs(t, "pi1", True), runs(t, "ten", False)) for t in rules],
      [(True, False)] * len(rules))
check("every firewall rule on a Pi whatever it finds (never skipped for want of UFW)",
      all(runs(t, "pi2", False) for t in rules), True)
need = [t for t in every if "ansible.builtin.assert" in t and "_ufw" in str(t["ansible.builtin.assert"].get("that"))]
check("a Pi without UFW refused, ten passes", bool(need) and [
    condition(need[0]["ansible.builtin.assert"]["that"], inventory_hostname=h, groups={"pis": ["pi1", "pi2"]},
              _ufw={"stat": {"exists": u}}) for h, u in (("pi1", True), ("pi1", False), ("ten", False))]
      == [True, False, True], True)
print("consul-ports: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCP
