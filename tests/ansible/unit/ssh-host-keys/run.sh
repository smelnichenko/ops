#!/bin/bash
# The controller checks the hosts' keys (deploy/ansible/ansible.cfg, read by Ansible's own config manager, in an
# environment without ANSIBLE_* overrides): a LAN host answering at a Pi's address - with no key known_hosts holds for
# it - gets no connection, so neither the Vault key shares nor the secrets a play sends. Production's inventory turns it
# off nowhere (no host or group var, no ssh argument); the Vagrant inventory does, for its own VMs only - rebuilt, each
# with a new key.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=$PWD/deploy/ansible/venv/bin/python3
cd deploy/ansible || exit 1
env -i HOME="$HOME" PATH="$PATH" ANSIBLE_CONFIG=ansible.cfg PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYSSHK'
import os, re, sys
from ansible.config.manager import ConfigManager
from ansible.inventory.manager import InventoryManager
from ansible.parsing.dataloader import DataLoader
from ansible.vars.manager import VariableManager
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
# the value and where it came from: the file itself (Ansible's default is True too - a file it failed to read, or one
# without the line, would pass on the default)
cfg = os.path.abspath("ansible.cfg")
check("ansible.cfg: host keys checked, said in the file",
      ConfigManager(cfg).get_config_value_and_origin("HOST_KEY_CHECKING"), (True, cfg))
OFF = re.compile(r"StrictHostKeyChecking=(no|off|accept-new)|UserKnownHostsFile=/dev/null", re.I)
def offs(inventory):
    loader = DataLoader()
    inv = InventoryManager(loader=loader, sources=[inventory])
    vm = VariableManager(loader=loader, inventory=inv)
    out = set()
    for h in inv.get_hosts():
        v = vm.get_vars(host=h, include_hostvars=False)
        for k in ("ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_scp_extra_args",
                  "ansible_sftp_extra_args"):
            if OFF.search(str(v.get(k, ""))):
                out.add(h.name)
        # the Vagrant copy's own word that its VMs' keys go unchecked (setup-vault-pi's key-share assert takes it)
        if str(v.get("host_keys_unchecked_rebuilt_vms", "")).lower() in ("true", "yes", "1", "on"):
            out.add(h.name)
        for k in ("ansible_host_key_checking", "ansible_ssh_host_key_checking"):
            if k in v and str(v[k]).lower() in ("false", "no", "0", "off"):
                out.add(h.name)
    return sorted(out), sorted(h.name for h in inv.get_hosts())
off, hosts = offs("inventory/production.yml")
check("production's inventory: the key check off for no host", (off, len(hosts) >= 3), ([], True))
off, hosts = offs("inventory/vagrant.yml")
check("the Vagrant inventory: off for its own (rebuilt) VMs", off == hosts and len(hosts) >= 3, True)
# nor by ssh's own arguments anywhere production runs: its playbooks, the ops scripts, bootstrap.sh
import glob
srcs = sorted(glob.glob("playbooks/**/*.yml", recursive=True) + glob.glob("playbooks/scripts/*")
              + glob.glob("../../scripts/*") + ["../../bootstrap.sh"])
hits = [f"{os.path.relpath(f, '../..')}:{n}" for f in srcs if os.path.isfile(f)
        for n, line in enumerate(open(f, errors="replace"), 1) if OFF.search(line)]
check(f"nothing production runs turns ssh's key check off ({len(srcs)} files)", hits, [])
# the git mirror's push to the VIP (pi1's or pi2's address, by keepalived): both Pis' own keys under one alias
import yaml
mirror = next(p for p in yaml.safe_load(open("playbooks/setup-velero.yml")) if "git mirror" in p.get("name", "").lower())
text = yaml.safe_dump(mirror)
keys = [t for t in mirror["tasks"] if "/etc/ssh/ssh_host_ed25519_key.pub" in str(t.get("ansible.builtin.slurp"))]
check("the mirror's push: checked against both Pis' own host keys (read from each Pi), under the VIP's alias",
      ("HostKeyAlias=" in text, "StrictHostKeyChecking=yes" in text,
       [(t.get("loop"), t.get("delegate_to")) for t in keys]),
      (True, True, [("{{ groups['pis'] }}", "{{ item }}")]))
# the known_hosts it writes: one line per Pi, the alias and the key (its comment dropped)
sys.path.insert(0, "../../tests/ansible/unit")
from templar import render  # noqa: E402
kh = next(t for t in mirror["tasks"] if "_pi_host_keys.results" in str(t.get("ansible.builtin.copy")))
import base64
res = [{"content": base64.b64encode(f"ssh-ed25519 AAAA{n} root@{n}\n".encode()).decode()} for n in ("pi1", "pi2")]
check("the known hosts written: each Pi's key under the alias",
      render(kh["ansible.builtin.copy"]["content"], _pi_host_keys={"results": res}, **mirror["vars"]),
      "pi-vip ssh-ed25519 AAAApi1\npi-vip ssh-ed25519 AAAApi2\n")
print("ssh-host-keys: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYSSHK
