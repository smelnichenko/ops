#!/usr/bin/env bash
# vagrant-inventory.sh - the Vagrant copy's version inventory into .upgrade/vagrant-inventory.txt: the node's
# (scripts/version-inventory.sh, the isolation probe's namespace left out - it belongs to the test, not to production)
# and each Pi's (scripts/version-inventory-pi.sh). Any host failing fails the whole run (a loop's status used to be
# its last host's). With VAGRANT_SSH_CONFIG set, plain ssh with that config (several callers at once); else vagrant ssh.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
cd "$ops"
mkdir -p .upgrade
on() {
  if [ -n "${VAGRANT_SSH_CONFIG:-}" ]; then ssh -F "$VAGRANT_SSH_CONFIG" "$1" "$2"; else vagrant ssh "$1" -c "$2"; fi
}
out=$(mktemp .upgrade/vagrant-inventory.XXXX)
trap 'rm -f "$out"' EXIT
on kubeadm 'sudo INVENTORY_EXCLUDE_NAMESPACES=isolation-probe bash -s' < scripts/version-inventory.sh \
  | tr -d '\r' > "$out"
for p in pi1 pi2; do
  on "$p" 'sudo bash -s' < scripts/version-inventory-pi.sh | tr -d '\r' >> "$out"
done
mv "$out" .upgrade/vagrant-inventory.txt
trap - EXIT
echo "vagrant inventory: $(wc -l < .upgrade/vagrant-inventory.txt) lines"
