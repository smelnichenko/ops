#!/bin/bash
# setup-vault-pi.yml's firewall for Vault's cluster port (8201: request forwarding and HA between the two Vaults): open
# to the two Pis only - the narrow rules first, then the rule that opened it to the whole LAN (production's, both
# families: pi1 read 2026-10-08) removed, as setup-consul closes Consul's; no Pi loses its peer in between. 8200 (the
# API) is not touched here: the operator's.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYVU'
import sys
import yaml
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
play = next(p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
            if any("UFW default deny" == t.get("name") for t in p.get("tasks") or []))
tasks = play["tasks"]
ufw = [(i, t["community.general.ufw"]) for i, t in enumerate(tasks) if "community.general.ufw" in t]
narrow = [i for i, u in ufw if str(u.get("port")) == "8201" and u.get("from_ip") and not u.get("delete")]
closed = [(i, u) for i, u in ufw if u.get("delete") is True]
check("8201 opened to the Pis (the narrow rule)", len(narrow), 1)
check("one delete: 8201/tcp's rule from anywhere - nothing else", [(str(u.get("port")), u.get("proto"), "from_ip" in u,
                                                                    u.get("rule")) for _, u in closed],
      [("8201", "tcp", False, "allow")])
check("the narrow rule before the delete (no Pi loses its peer between)",
      bool(narrow and closed) and narrow[0] < closed[0][0], True)
print("vault-ufw: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYVU
