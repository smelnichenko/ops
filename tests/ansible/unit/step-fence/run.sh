#!/bin/bash
# Every upgrade step's playbook lines within the production runner's allow-list (scripts/upgrade-step-playbooks.sh
# --lint): only --tags and -e <step variable>=<plain value> may reach production - a Vagrant-only setting in a step
# line would be carried to ten. A step file that does not parse fails the lint (it passed: the lines were read in a
# here-string, whose failure set -e does not see).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
fails=0
if scripts/upgrade-step-playbooks.sh --lint; then echo "PASS every step's lines"; else echo "FAIL every step's lines"; fails=1; fi
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/tests/ansible/upgrade/steps"
cp scripts/upgrade-step-playbooks.sh scripts/upgrade-expected-inventory.py "$T/scripts/"
printf 'playbook setup-gluster.yml\nnot a step line\n' > "$T/tests/ansible/upgrade/steps/01-broken.txt"
if out=$("$T/scripts/upgrade-step-playbooks.sh" --lint 2>&1); then
  echo "FAIL a step file that does not parse: the lint passed ($out)"; fails=1
else
  echo "PASS a step file that does not parse: the lint fails"
fi
if [ "$fails" = 0 ]; then echo "step-fence: ALL-PASS"; else echo "step-fence: FAILED"; exit 1; fi
