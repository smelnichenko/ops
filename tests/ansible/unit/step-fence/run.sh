#!/bin/bash
# Every upgrade step's playbook lines within the production runner's allow-list (scripts/upgrade-step-playbooks.sh
# --lint): only --tags and -e <step variable>=<plain value> may reach production - a Vagrant-only setting in a step
# line would be carried to ten.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
scripts/upgrade-step-playbooks.sh --lint && echo "step-fence: ALL-PASS"
