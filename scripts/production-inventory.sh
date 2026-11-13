#!/usr/bin/env bash
# production-inventory.sh - production's version inventory as it runs now, the record the Vagrant copy is built to and
# judged against. Read-only on production: ten's inventory (scripts/version-inventory.sh; the test
# environment and open preview environments left out - the copy has neither) and both Pis'
# (scripts/version-inventory-pi.sh), sorted into tests/ansible/copy/prod-inventory.txt. Then the Pis' service versions
# into tests/ansible/copy/pi-versions.yml: where a Pi runs another Forgejo, Patroni, Vault, Consul, Keycloak or
# versitygw than the playbooks pin (they install their own where a service is missing), the copy is pinned to
# production's - Forgejo and Vault with the amd64 checksum the playbooks verify (the Vagrant VMs are amd64), kept from
# the file when its version is unchanged, else read from the release; versitygw only where its task file has the
# checksums. Both Pis must run the same version of each; a Pi that does not answer, or answers stale or
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
# (the list read first, on its own: an ssh that failed inside the pipeline read as "no preview open")
namespaces=$("${ssh_[@]}" "$ten" 'kubectl get namespaces -o name')
[ -n "$namespaces" ] || { echo "ten listed no namespace"; exit 1; }
previews=$(sed 's#^namespace/##' <<< "$namespaces" | { grep -E '^schnappy-pr-[0-9]+$' || true; } | tr '\n' ' ')
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
# the Pis' pins from it - both files moved in only once both are written: a failed checksum read leaves neither changed
[ ! -f "$pins" ] || cp "$pins" "$work/pins"
scripts/pi-versions.py "$work/inventory" "$work/pins"
mv "$work/inventory" "$out"
mv "$work/pins" "$pins"
echo "production's inventory: $(wc -l < "$out") lines -> $out (left out: ${excluded% }); the Pis' pins -> $pins"
