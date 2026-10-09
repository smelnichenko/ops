#!/bin/bash
# scripts/upgrade-step-playbooks.sh --lint: each step line outside the allow-list fails, naming what it refused - a
# playbook outside deploy/ansible/playbooks, an inventory, a variable no step owns, an extra-vars file, a value with shell
# in it; a step's own line passes
set -u
cd "$(dirname "$0")/../../../.." || exit 1
script=scripts/upgrade-step-playbooks.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/tests/ansible/upgrade/steps" "$T/deploy/ansible/playbooks"
cp "$script" "$T/scripts/upgrade-step-playbooks.sh"
cp scripts/upgrade-expected-inventory.py "$T/scripts/"
chmod +x "$T/scripts/"*
: > "$T/deploy/ansible/playbooks/setup-kubeadm.yml"
printf 'x\n' > "$T/tests/ansible/upgrade/prod-inventory.txt"
fails=0
lint() {  # name, step line, word the refusal names
  rm -f "$T"/tests/ansible/upgrade/steps/*.txt
  printf 'playbook %s\n' "$2" > "$T/tests/ansible/upgrade/steps/01-x.txt"
  out=$("$T/scripts/upgrade-step-playbooks.sh" --lint 2>&1); rc=$?
  if [ "$rc" != 0 ] && grep -qF -- "$3" <<< "$out"; then echo "PASS $1"; else echo "FAIL $1 (rc $rc): $out"; fails=$((fails + 1)); fi
}
lint "C01/C04 a playbook outside deploy/ansible/playbooks refused" "../../tests/ansible/data-check.yml" "is not a playbook"
lint "C01 an inventory argument refused" "setup-kubeadm.yml -i inventory/vagrant.yml" "argument '-i'"
lint "C01/C02 a variable no step owns refused" "setup-kubeadm.yml -e forgejo_url=http://192.168.56.20:3000" "not a step variable"
lint "C01/C02 an extra-vars file refused" "setup-kubeadm.yml -e @vars/vagrant.yml" "not a step variable"
lint "C01/C02 a step variable with a non-plain value refused" "setup-kubeadm.yml -e cilium_version=1.20.2;id" "not a step variable"
rm -f "$T"/tests/ansible/upgrade/steps/*.txt
printf 'playbook setup-kubeadm.yml --tags cilium -e cilium_version=1.20.2\n' > "$T/tests/ansible/upgrade/steps/01-x.txt"
if "$T/scripts/upgrade-step-playbooks.sh" --lint > /dev/null 2>&1; then echo "PASS a step's own line passes"; else echo "FAIL a step's own line refused"; fails=$((fails + 1)); fi
echo "step-fence: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
