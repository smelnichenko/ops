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
        for k in ("ansible_host_key_checking", "ansible_ssh_host_key_checking"):
            if k in v and str(v[k]).lower() in ("false", "no", "0", "off"):
                out.add(h.name)
    return sorted(out), sorted(h.name for h in inv.get_hosts())
off, hosts = offs("inventory/production.yml")
check("production's inventory: the key check off for no host", (off, len(hosts) >= 3), ([], True))
off, hosts = offs("inventory/vagrant.yml")
check("the Vagrant inventory: off for its own (rebuilt) VMs", off == hosts and len(hosts) >= 3, True)
print("ssh-host-keys: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYSSHK
