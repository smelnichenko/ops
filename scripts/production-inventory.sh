#!/usr/bin/env bash
# production-inventory.sh - production's version inventory as it runs now, the record the Vagrant copy is built to and
# judged against (plan 117). Read-only on production: ten's inventory (scripts/version-inventory.sh; the test
# environment and open preview environments left out - the copy has neither) and both Pis'
# (scripts/version-inventory-pi.sh), sorted into tests/ansible/copy/prod-inventory.txt. Then the Pis' service versions
# into tests/ansible/copy/pi-versions.yml: where a Pi runs another Forgejo, Patroni or Vault than the playbooks' vars pin
# (the playbooks install their own where a service is missing), the copy is pinned to production's - with the amd64
# checksum the playbooks verify (the Vagrant VMs are amd64), kept from the file when its version is unchanged, else read
# from the release. Both Pis must run the same version of each; a Pi that does not answer, or answers stale or
# not-running, refuses: the copy is not built to a guess.
#
# Usage: scripts/production-inventory.sh
# Env:   PROD_TEN, PROD_PIS (default sm@192.168.11.2; sm@192.168.11.4 sm@192.168.11.6)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
ten=${PROD_TEN:-sm@192.168.11.2}
read -r -a pis <<< "${PROD_PIS:-sm@192.168.11.4 sm@192.168.11.6}"
ssh_=(ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
out=tests/ansible/copy/prod-inventory.txt
pins=tests/ansible/copy/pi-versions.yml
mkdir -p .copy
work=$(mktemp -d "$ops/.copy/production-inventory.XXXX")
trap 'rm -rf "$work"' EXIT

# the namespaces the copy does not have: the test environment's, and the preview environments open now
previews=$("${ssh_[@]}" "$ten" 'kubectl get namespaces -o name' | sed 's#^namespace/##' | grep -E '^schnappy-pr-[0-9]+$' \
  | tr '\n' ' ' || true)
excluded="schnappy-test ${previews}"
"${ssh_[@]}" "$ten" "INVENTORY_EXCLUDE_NAMESPACES='${excluded% }' bash -s" < scripts/version-inventory.sh > "$work/ten"
[ -s "$work/ten" ] || { echo "ten's inventory came back empty"; exit 1; }
for pi in "${pis[@]}"; do
  "${ssh_[@]}" "$pi" 'sudo -n bash -s' < scripts/version-inventory-pi.sh > "$work/pi.$pi"
  [ -s "$work/pi.$pi" ] || { echo "$pi's inventory came back empty"; exit 1; }
done
sort -u "$work/ten" "$work"/pi.* > "$work/inventory"
if grep -E '^pi .* (stale|not-running)$' "$work/inventory"; then
  echo "a Pi service above is stale or not running - production's version is not known: fix the Pi, then read again"
  exit 1
fi
mv "$work/inventory" "$out"
echo "production's inventory: $(wc -l < "$out") lines -> $out (left out: ${excluded% })"

python3 - "$out" "$pins" <<'PY'
import re, sys, urllib.request
import yaml
inventory, pins_path = sys.argv[1], sys.argv[2]
lines = open(inventory).read().splitlines()
vars_dir = "deploy/ansible/vars"
pinned = {"forgejo": yaml.safe_load(open(f"{vars_dir}/forgejo.yml")), "patroni": yaml.safe_load(open(f"{vars_dir}/patroni.yml")),
          "vault": yaml.safe_load(open(f"{vars_dir}/vault.yml"))}
try:
    old = yaml.safe_load(open(pins_path)) or {}
except FileNotFoundError:
    old = {}
running = {}
for name in pinned:
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

body = {}
for name, fetch in (("forgejo", sha_forgejo), ("patroni", None), ("vault", sha_vault)):
    v = running[name]
    if v == str(pinned[name][f"{name}_version"]):
        continue  # the playbooks install production's own
    body[f"{name}_version"] = v
    if fetch:
        same = str(old.get(f"{name}_version")) == v and (old.get(f"{name}_checksums") or {}).get("amd64")
        body[f"{name}_checksums"] = {"amd64": same or fetch(v)}
head = ("# The Pis' service versions as production runs them, where the playbooks' vars pin another (they install their own\n"
        "# where a service is missing): the Vagrant copy installs production's. Written by scripts/production-inventory.sh\n"
        "# (task test:copy:inventory) from what the Pis run - not edited by hand. amd64 only (the Vagrant VMs). Extra vars,\n"
        "# after vars/vault.yml.\n")
with open(pins_path, "w") as f:
    f.write(head + (yaml.safe_dump(body, sort_keys=False) if body else "{}\n"))
print(f"the Pis: " + ", ".join(f"{n} {running[n]}" + ("" if f"{n}_version" not in body else " (pinned)") for n in running)
      + f" -> {pins_path}")
PY
