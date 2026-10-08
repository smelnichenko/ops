#!/bin/bash
# The controller checks the hosts' keys (deploy/ansible/ansible.cfg, read by Ansible's own config manager, in an
# environment without ANSIBLE_* overrides): a LAN host answering at a Pi's address - with no key known_hosts holds for
# it - gets no connection, so neither the Vault key shares nor the secrets a play sends. Production's inventory turns it
# off nowhere (no host or group var, no ssh argument - in any of ssh's spellings: =no/off/false/accept-new, the space
# form, a known-hosts file of /dev/null, a KnownHostsCommand, another config by -F), nor does anything production runs
# (its playbooks, the ops scripts, bootstrap.sh, the Taskfile's production tasks); the Vagrant inventory does, for its
# own VMs only - rebuilt, each with a new key - and setup-vault-pi's key-share assert takes that word only for a pi2 on
# the Vagrant network.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible' 2> /dev/null || PY=$PWD/deploy/ansible/venv/bin/python3
cd deploy/ansible || exit 1
env -i HOME="$HOME" PATH="$PATH" ANSIBLE_CONFIG=ansible.cfg PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYSSHK'
import os, re, sys
import yaml
sys.path.insert(0, "../../tests/ansible/unit")
from templar import condition, render  # noqa: E402
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
# ssh's ways to accept a host's key unchecked; in ssh's arguments another config file (-F) too
# any separator between the key and its value (=, spaces, a tab, quotes - ssh reads each so); -F with or without a space
# after it, and never -f (ssh's background flag)
OFF = re.compile(r"StrictHostKeyChecking[^a-z0-9/]+(no|off|false|accept-new)\b"
                 r"|(User|Global)KnownHostsFile[^a-z0-9/~]+/dev/null|KnownHostsCommand", re.I)
OFF_ARGS = re.compile(OFF.pattern + r"|(^|[^a-z0-9-])(?-i:-F)", re.I)
forms = ["-o StrictHostKeyChecking=no", "-o StrictHostKeyChecking=false", "-o 'StrictHostKeyChecking no'",
         "-o StrictHostKeyChecking=accept-new", "-o UserKnownHostsFile=/dev/null", "-o GlobalKnownHostsFile=/dev/null",
         "-o KnownHostsCommand=/bin/echo", "-o \"StrictHostKeyChecking off\"",
         # a tab between, quotes around the value, no space after -o (ssh reads each as =no)
         "-o StrictHostKeyChecking\tno", "-o StrictHostKeyChecking='no'", "-oStrictHostKeyChecking=no",
         "-o UserKnownHostsFile='/dev/null'"]
check("every spelling of an unchecked key read as one", [f for f in forms if not OFF.search(f)], [])
check("checked ones not", [f for f in ["-o StrictHostKeyChecking=yes", "-o UserKnownHostsFile=/var/lib/x/known_hosts",
                                       "-o ServerAliveInterval=15", "-f -N", "-o ForwardAgent=no"] if OFF_ARGS.search(f)],
      [])
check("another config by -F, a space after it or none", [f for f in ["-F /etc/x", "-F/etc/x", "-C -F/x"]
                                                         if not OFF_ARGS.search(f)], [])
def offs(inventory):
    loader = DataLoader()
    inv = InventoryManager(loader=loader, sources=[inventory])
    vm = VariableManager(loader=loader, inventory=inv)
    out = set()
    for h in inv.get_hosts():
        v = vm.get_vars(host=h, include_hostvars=False)
        for k in ("ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_scp_extra_args",
                  "ansible_sftp_extra_args"):
            if OFF_ARGS.search(str(v.get(k, ""))):
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
# each way an inventory says it, alone - the Vagrant copy's own word, another config file, a check turned off
import tempfile  # noqa: E402
for name, var in (("its own word", "host_keys_unchecked_rebuilt_vms: true"),
                  ("another ssh config", "ansible_ssh_common_args: -F /tmp/x"),
                  ("ssh's =false", "ansible_ssh_extra_args: -o StrictHostKeyChecking=false"),
                  ("Ansible's check off", "ansible_host_key_checking: false")):
    fx = tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False)
    fx.write(f"all:\n  hosts:\n    h1:\n      ansible_host: 10.0.0.1\n      {var}\n    h2:\n      ansible_host: 10.0.0.2\n")
    fx.close()
    check(f"an inventory turning it off by {name}: that host named, the other not", offs(fx.name)[0], ["h1"])
    os.remove(fx.name)
# nor by ssh's own arguments anywhere production runs: its playbooks, the ops scripts, bootstrap.sh
import glob
srcs = sorted(glob.glob("playbooks/**/*.yml", recursive=True) + glob.glob("playbooks/scripts/*")
              + glob.glob("../../scripts/*") + ["../../bootstrap.sh"])
# a comment's words, and setup-vault-pi's own detector (its list of the spellings) aside
detector = {e for p in yaml.safe_load(open("playbooks/setup-vault-pi.yml")) for t in p.get("tasks") or []
            for e in (t.get("vars") or {}).get("_unchecked_ssh") or []}
def own_entry(line):
    x = line.strip()
    return x.startswith("- ") and x[2:].strip().strip("'\"") in detector
hits = [f"{os.path.relpath(f, '../..')}:{n}" for f in srcs if os.path.isfile(f)
        for n, line in enumerate(open(f, errors="replace"), 1)
        if OFF.search(line) and not line.lstrip().startswith("#") and not own_entry(line)]
# found (an empty set would exempt nothing and say nothing): each of its entries a line of setup-vault-pi
vp_lines = [line for line in open("playbooks/setup-vault-pi.yml") if own_entry(line)]
check("the detector's spellings found to set aside, each its own line of setup-vault-pi",
      (bool(detector), len(vp_lines) == len(detector)), (True, True))
# the Taskfile's production tasks (deploy:*, or any on the production inventory) - its Vagrant ones reach the copy's VMs
tf = yaml.safe_load(open("../../Taskfile.yml"))["tasks"]
for name, t in tf.items():
    cmds = " ".join(str(c.get("cmd", "") if isinstance(c, dict) else c) for c in (t or {}).get("cmds") or [])
    if (name.startswith("deploy:") or "inventory/production.yml" in cmds) and OFF_ARGS.search(cmds):
        hits.append(f"Taskfile.yml: {name}")
check(f"nothing production runs turns ssh's key check off ({len(srcs)} files, the Taskfile's production tasks)", hits, [])
# setup-vault-pi's key-share assert: the same spellings refused in this run's ssh arguments; the copy's word taken only
# for a pi2 on the Vagrant network (a production inventory saying it would send the shares unchecked)
vp = [t for p in yaml.safe_load(open("playbooks/setup-vault-pi.yml")) for t in p.get("tasks") or []
      if t.get("name") == "Host keys checked - the shares only to pi2 itself"]
that = vp[0]["ansible.builtin.assert"]["that"] if vp else []
unchecked = "|".join((vp[0].get("vars") or {}).get("_unchecked_ssh") or []) if vp else ""
check("the assert's ssh-argument pattern (its list, joined) read by it, refuses every spelling, passes checked ones",
      ("is not search(_unchecked_ssh | join('|'), ignorecase=True)" in " ".join(" ".join(that).split()),
       [f for f in forms + ["-F /etc/x", "-F/etc/x"] if not (unchecked and re.search(unchecked, f, re.I))],
       [f for f in ["-o StrictHostKeyChecking=yes", "-o ServerAliveInterval=15", "-f -N"]
        if unchecked and re.search(unchecked, f, re.I)]),
      (True, [], []))
# Ansible's own check off, as the copy's run has it (its config lookup put as that value)
LOOKUP = "lookup('ansible.builtin.config', 'host_key_checking', plugin_type='connection', plugin_name='ssh') | bool"
first = " ".join(str(that[0]).split()) if that else ""
check("the assert's first clause reads Ansible's own check", first.count(LOOKUP), 1)
word = lambda flag, pi2: condition(first.replace(LOOKUP, "false"), host_keys_unchecked_rebuilt_vms=flag,
                                   hostvars={"pi2": {"ansible_host": pi2}})
check("the copy's word taken for a pi2 on the Vagrant network, not for one elsewhere; no word, no check: refused",
      [word(True, "192.168.56.21"), word(True, "192.168.11.6"), word(False, "192.168.56.21")], [True, False, False])
# the Vagrant network: every Vagrant VM on it, no production host
def addrs(inventory):
    inv = InventoryManager(loader=DataLoader(), sources=[inventory])
    vm = VariableManager(loader=DataLoader(), inventory=inv)
    return [str(vm.get_vars(host=h, include_hostvars=False).get("ansible_host", "")) for h in inv.get_hosts()]
net = re.search(r"is match\('\^?(.*?)'\)", first)
net = net.group(1).replace("[.]", ".") if net else "none"
check(f"the Vagrant network ({net}): every Vagrant VM on it, no production host",
      (all(a.startswith(net) for a in addrs("inventory/vagrant.yml")),
       [a for a in addrs("inventory/production.yml") if a.startswith(net)]), (True, []))
# the git mirror's push to the VIP (pi1's or pi2's address, by keepalived): both Pis' own keys under one alias
mirror = next(p for p in yaml.safe_load(open("playbooks/setup-velero.yml")) if "git mirror" in p.get("name", "").lower())
text = yaml.safe_dump(mirror)
keys = [t for t in mirror["tasks"] if "/etc/ssh/ssh_host_ed25519_key.pub" in str(t.get("ansible.builtin.slurp"))]
check("the mirror's push: checked against both Pis' own host keys (read from each Pi), under the VIP's alias",
      ("HostKeyAlias=" in text, "StrictHostKeyChecking=yes" in text,
       [(t.get("loop"), t.get("delegate_to")) for t in keys]),
      (True, True, [("{{ groups['pis'] }}", "{{ item }}")]))
# the known_hosts it writes: one line per Pi, the alias and the key (its comment dropped)
kh = next(t for t in mirror["tasks"] if "_pi_host_keys.results" in str(t.get("ansible.builtin.copy")))
import base64
res = [{"content": base64.b64encode(f"ssh-ed25519 AAAA{n} root@{n}\n".encode()).decode()} for n in ("pi1", "pi2")]
check("the known hosts written: each Pi's key under the alias",
      render(kh["ansible.builtin.copy"]["content"], _pi_host_keys={"results": res}, **mirror["vars"]),
      "pi-vip ssh-ed25519 AAAApi1\npi-vip ssh-ed25519 AAAApi2\n")
print("ssh-host-keys: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYSSHK
