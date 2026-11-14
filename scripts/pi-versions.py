#!/usr/bin/env python3
"""pi-versions.py <inventory> <pins file> - the Pis' service versions production runs (its inventory's `pi <host>
<service> <version>` lines), written as extra vars where the playbooks pin another version, so the Vagrant copy
installs production's (scripts/production-inventory.sh calls it after reading production). Forgejo and Vault carry
their amd64 checksum (kept from the pins file when the version is unchanged, else read from the release); versitygw
only at a version its task file has checksums for. And Debian's packages the Pis report (scripts/version-inventory-pi.sh
lists them) at the versions they run, as pi_apt_versions - Debian's archive serves only the newest, so the copy moves
its own to these (tests/ansible/copy/pi-apt-versions.yml). Refuses: a service or package the Pis run at two versions,
or on one Pi only, or at what is no version.
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
    ("caddy", "caddy_version", lambda: play_var(f"{pb}/setup-caddy.yml", "caddy_version")),
]
# a version as the Pis report one: what production's services say goes into an extra-vars file, where text is a template
VERSION = re.compile(r"[0-9][0-9A-Za-z.+~-]*")
# a Debian package's version: an epoch first, maybe (keepalived 1:2.3.3-1)
DEB_VERSION = re.compile(r"([0-9]+:)?[0-9][0-9A-Za-z.+~-]*")


def debian_packages():
    """The Debian packages scripts/version-inventory-pi.sh reports (its loop over them) - the same list, never a copy."""
    m = re.search(r"^for pkg in ([a-z0-9. +-]+); do", open("scripts/version-inventory-pi.sh").read(), re.M)
    if not m:
        sys.exit("scripts/version-inventory-pi.sh: no `for pkg in ...` loop over Debian's packages")
    return m[1].split()
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
    if not VERSION.fullmatch(running[name]):
        sys.exit(f"the Pis report {name} {running[name]!r} - not a version")


def sha_forgejo(v):
    url = f"https://codeberg.org/forgejo/forgejo/releases/download/v{v}/forgejo-{v}-linux-amd64.sha256"
    return urllib.request.urlopen(url, timeout=60).read().decode().split()[0]


def sha_vault(v):
    url = f"https://releases.hashicorp.com/vault/{v}/vault_{v}_SHA256SUMS"
    for l in urllib.request.urlopen(url, timeout=60).read().decode().splitlines():
        if l.endswith(f"vault_{v}_linux_amd64.zip"):
            return l.split()[0]
    sys.exit(f"vault {v}: no linux_amd64 checksum in {url}")


# Debian's packages, each on both Pis or on neither, at one version
apt = {}
for pkg in debian_packages():
    per_host = {l.split()[1]: l.split()[3] for l in lines if re.match(rf"^pi \S+ {re.escape(pkg)} ", l)}
    if not per_host:
        continue
    hosts = {l.split()[1] for l in lines if l.startswith("pi ")}
    if set(per_host) != hosts or len(set(per_host.values())) != 1:
        sys.exit(f"the Pis run {pkg} {sorted(per_host.items())} - one version on both expected")
    apt[pkg] = per_host.popitem()[1]
    if not DEB_VERSION.fullmatch(apt[pkg]):
        sys.exit(f"the Pis report {pkg} {apt[pkg]!r} - not a Debian version")

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
if apt:
    body["pi_apt_versions"] = apt
head = ("# The Pis' service versions as production runs them, where the playbooks pin another (they install their own where\n"
        "# a service is missing): the Vagrant copy installs production's. Written by scripts/production-inventory.sh\n"
        "# (task test:copy:inventory) from what the Pis run - not edited by hand. amd64 only (the Vagrant VMs). Extra vars,\n"
        "# after vars/vault.yml. pi_apt_versions: Debian's packages at production's versions\n"
        "# (tests/ansible/copy/pi-apt-versions.yml moves the copy's to them).\n")
with open(pins_path, "w") as f:
    f.write(head + (yaml.safe_dump(body, sort_keys=False) if body else "{}\n"))
print("the Pis: " + ", ".join(f"{n} {running[n]}" + (" (pinned)" if var in body else "") for n, var, _ in PINNED)
      + "; Debian's: " + ", ".join(f"{k} {v}" for k, v in apt.items()) + f" -> {pins_path}")
