#!/usr/bin/env bash
# upgrade-step-playbooks.sh <step> - run the host-side changes (playbook lines) of every upgrade step up to and
# including <step> against the Vagrant inventory, in step order (scripts/upgrade-expected-inventory.py --playbooks).
# In an empty environment: the Taskfile loads ops/.env, which holds production's secrets.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
"$ops/scripts/upgrade-expected-inventory.py" --playbooks "$1" | while read -r playbook args; do
  echo "== $playbook $args"
  # shellcheck disable=SC2086  # the step file's arguments are meant to split into words
  (cd "$ops/deploy/ansible" && env -i HOME="$HOME" PATH="$PATH" \
     venv/bin/ansible-playbook -i inventory/vagrant.yml "playbooks/$playbook" $args)
done
