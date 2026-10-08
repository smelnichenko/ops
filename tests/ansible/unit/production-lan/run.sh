#!/bin/bash
# Production's LAN (ten and the Pis: its IPv4 and IPv6 prefixes, ten's addresses, the VIP) said once, in
# deploy/ansible/vars/production-lan.yml: what production's firewalls open to (setup-nexus, setup-vault-pi) and what
# the Vagrant copy's isolations drop (isolate-pis, isolate-cluster) - each play reads that file, and no playbook of
# deploy/ or tests/ansible restates its prefixes (seven places did: one changed, the others left behind).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYPL'
import glob, os, sys
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
VARS = "deploy/ansible/vars/production-lan.yml"
lan = yaml.safe_load(open(VARS)) if os.path.exists(VARS) else {}
check("the file says them", sorted(lan), ["production_lan", "production_lan6", "production_ten_ip", "production_ten_ipv6",
                                         "production_vip"])
users = {"deploy/ansible/playbooks/setup-nexus.yml": "Install Nexus on pi1 + pi2",
         "deploy/ansible/playbooks/setup-vault-pi.yml": "Install Vault on pi1 + pi2",
         "deploy/ansible/playbooks/setup-keepalived.yml": "Setup Keepalived",
         "tests/ansible/isolate-pis.yml": "Isolate the Vagrant Pis from production",
         "tests/ansible/upgrade/isolate-cluster.yml": "Isolate the Vagrant cluster from production"}
for f, name in users.items():
    play = next((p for p in yaml.safe_load(open(f)) if p.get("name") == name), {})
    files = [os.path.normpath(os.path.join(os.path.dirname(f), v)) for v in play.get("vars_files") or []]
    check(f"{f}: its play reads the file", os.path.normpath(VARS) in files, True)
    check(f"{f}: its play defines none of them itself", sorted(set(play.get("vars") or {}) & set(lan)), [])
import re
# the prefixes - the LAN itself (ten's and the VIP's addresses, defaults an inventory overrides, are another matter)
values = [re.compile(r"(?<![\w.:])" + re.escape(str(lan.get(k, "-"))) + r"(?![\w:])") for k in ("production_lan",)] \
    + [re.compile(re.escape(str(lan.get("production_lan6", "-")).split("/")[0]))]
# the Vagrant guard decides on the host's own addresses and no variable, by design (vagrant-only.yml): its own literal
GUARD = {"tests/ansible/vagrant-only.yml"}
said = [f"{f}:{n}" for f in sorted(glob.glob("deploy/ansible/playbooks/**/*.yml", recursive=True)
                                   + glob.glob("tests/ansible/*.yml") + glob.glob("tests/ansible/upgrade/**/*.yml",
                                                                                 recursive=True)) if f not in GUARD
        for n, line in enumerate(open(f), 1) if not line.lstrip().startswith("#") and any(v.search(line) for v in values)]
check("no playbook restates them", said, [])
print("production-lan: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYPL
