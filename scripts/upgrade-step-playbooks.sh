#!/usr/bin/env bash
# upgrade-step-playbooks.sh <step> - run the host-side changes (playbook lines) of <step> against the Vagrant
# inventory (scripts/upgrade-expected-inventory.py --playbooks: the step's own, never an earlier step's).
# In an empty environment: the Taskfile loads ops/.env, which holds production's secrets.
#
# The playbooks are production's own, with no Vagrant guard: a step's arguments may not name another inventory, a
# limit, a host address or an extra-vars file (each could aim the run at ten or the Pis), and the guard play
# (tests/ansible/vagrant-only-play.yml) runs first in the same ansible-playbook call - a host that fails it is dropped
# from the step's plays. stdin is closed: a playbook reading it would swallow the step's later lines.
#
# --production <step>: the same lines against production (inventory/production.yml), in the environment the Taskfile
# gives (production's secrets), without the Vagrant guard - `task deploy:upgrade:playbooks`, after the step's Vagrant
# proof and the operator's approval. The argument fence holds there too.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
# --production --check <step>: the same, read-only - ansible's check mode with diffs (no task here overrides it): what
# the step would change on ten and the Pis, before it runs (`task deploy:upgrade:preview`).
production=no; check=""
if [ "${1:-}" = --production ]; then production=yes; shift; fi
if [ "${1:-}" = --check ]; then [ "$production" = yes ] || { echo "--check is for --production" >&2; exit 1; }; check="--check --diff"; shift; fi
lines=$("$ops/scripts/upgrade-expected-inventory.py" --playbooks "$1")
while read -r playbook args; do
  [ -n "$playbook" ] || continue
  for word in $args; do
    case "$word" in
      -i|--inventory|--inventory=*|-i?*|-l|--limit|--limit=*|-l?*|*ansible_host*|@*|-e@*|--extra-vars=@*)
        echo "REFUSED: step $1, $playbook: argument '$word' could point the run away from the Vagrant copy" >&2
        exit 1;;
    esac
  done
  echo "== $playbook $args"
  if [ "$production" = yes ]; then
    # shellcheck disable=SC2086  # the step file's arguments are meant to split into words
    (cd "$ops/deploy/ansible" && venv/bin/ansible-playbook -i inventory/production.yml "playbooks/$playbook" $args $check < /dev/null)
  else
    # shellcheck disable=SC2086
    (cd "$ops/deploy/ansible" && env -i HOME="$HOME" PATH="$PATH" \
       venv/bin/ansible-playbook -i inventory/vagrant.yml ../../tests/ansible/vagrant-only-play.yml "playbooks/$playbook" \
       $args < /dev/null)
  fi
done <<< "$lines"
