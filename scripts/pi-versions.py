#!/usr/bin/env python3
"""pi-versions.py <inventory> <pins file> - the Pis' service versions production runs (its inventory's `pi <host>
<service> <version>` lines), written as extra vars where the playbooks pin another version, so the Vagrant copy
installs production's (scripts/production-inventory.sh calls it after reading production). Forgejo and Vault carry
their amd64 checksum (kept from the pins file when the version is unchanged, else read from the release); versitygw
only at a version its task file has checksums for. Refuses: a service the Pis run at two versions, or on neither.
"""
import re
import sys
import urllib.request

import yaml

inventory, pins_path = sys.argv[1], sys.argv[2]
lines = open(inventory).read().splitlines()
pb = "deploy/ansible/playbooks"


def play_var(path, key):
    return yaml.safe_load(open(path))[0]["vars"][key]


def vgw_default():
    return re.search(r"vgw_version \| default\('([0-9.]+)'\)", open(f"{pb}/tasks/versitygw.yml").read())[1]


def vgw_checksums():
    """The versions tasks/versitygw.yml has checksums for (its set_fact's vgw_checksums)."""
    for t in yaml.safe_load(open(f"{pb}/tasks/versitygw.yml")):
        facts = t.get("ansible.builtin.set_fact") or {}
        if "vgw_checksums" in facts:
            return {str(k) for k in facts["vgw_checksums"]}
    sys.exit("tasks/versitygw.yml: no vgw_checksums")


# each Pi service the playbooks install at a version of their own: (its inventory name, the variable, the version the
# playbooks pin) - an extra variable outranks every one of these (vars files, play vars, a default)
PINNED = [
    ("forgejo", "forgejo_version", lambda: yaml.safe_load(open("deploy/ansible/vars/forgejo.yml"))["forgejo_version"]),
    ("patroni", "patroni_version", lambda: yaml.safe_load(open("deploy/ansible/vars/patroni.yml"))["patroni_version"]),
    ("vault", "vault_version", lambda: yaml.safe_load(open("deploy/ansible/vars/vault.yml"))["vault_version"]),
    ("consul", "consul_version", lambda: play_var(f"{pb}/setup-consul.yml", "consul_version")),
    ("keycloak", "keycloak_version", lambda: play_var(f"{pb}/setup-pi-services.yml", "keycloak_version")),
    ("versitygw", "vgw_version", vgw_default),
]
try:
    old = yaml.safe_load(open(pins_path)) or {}
except FileNotFoundError:
    old = {}
running = {}
for name, _, _ in PINNED:
    seen = {l.split()[3] for l in lines if re.match(rf"^pi \S+ {name} ", l)}
    if len(seen) != 1:
        sys.exit(f"the Pis run {name} {sorted(seen) or 'nowhere'} - one version expected on both")
    running[name] = seen.pop()


def sha_forgejo(v):
    url = f"https://codeberg.org/forgejo/forgejo/releases/download/v{v}/forgejo-{v}-linux-amd64.sha256"
    return urllib.request.urlopen(url, timeout=60).read().decode().split()[0]


def sha_vault(v):
    url = f"https://releases.hashicorp.com/vault/{v}/vault_{v}_SHA256SUMS"
    for l in urllib.request.urlopen(url, timeout=60).read().decode().splitlines():
        if l.endswith(f"vault_{v}_linux_amd64.zip"):
            return l.split()[0]
    sys.exit(f"vault {v}: no linux_amd64 checksum in {url}")


FETCH = {"forgejo": sha_forgejo, "vault": sha_vault}
body = {}
for name, var, playbooks in PINNED:
    v = running[name]
    if v == str(playbooks()):
        continue  # the playbooks install production's own
    if name == "versitygw" and v not in vgw_checksums():
        sys.exit(f"the Pis run versitygw {v}: tasks/versitygw.yml's vgw_checksums has none for it - add them first")
    body[var] = v
    if name in FETCH:
        same = str(old.get(var)) == v and (old.get(f"{name}_checksums") or {}).get("amd64")
        body[f"{name}_checksums"] = {"amd64": same or FETCH[name](v)}
head = ("# The Pis' service versions as production runs them, where the playbooks pin another (they install their own where\n"
        "# a service is missing): the Vagrant copy installs production's. Written by scripts/production-inventory.sh\n"
        "# (task test:copy:inventory) from what the Pis run - not edited by hand. amd64 only (the Vagrant VMs). Extra vars,\n"
        "# after vars/vault.yml.\n")
with open(pins_path, "w") as f:
    f.write(head + (yaml.safe_dump(body, sort_keys=False) if body else "{}\n"))
print("the Pis: " + ", ".join(f"{n} {running[n]}" + (" (pinned)" if var in body else "") for n, var, _ in PINNED)
      + f" -> {pins_path}")
