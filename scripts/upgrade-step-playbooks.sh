#!/usr/bin/env bash
# upgrade-step-playbooks.sh <step> - run the host-side changes (playbook lines) of <step> against the Vagrant
# inventory (scripts/upgrade-expected-inventory.py --playbooks: the step's own, never an earlier step's).
# In an empty environment: the Taskfile loads ops/.env, which holds production's secrets.
#
# The playbooks are production's own, with no Vagrant guard: a step's arguments are an allow-list - `--tags <tags>`
# and `-e <name>=<value>` for the step variables below, nothing else (an inventory, a limit, a host address, an
# extra-vars file, or a Vagrant-only setting such as the Vagrant Forgejo's address would aim the run elsewhere - those
# live in inventory/vagrant.yml) - and the guard play (tests/ansible/vagrant-only-play.yml) runs first in the same
# ansible-playbook call - a host that fails it is dropped from the step's plays. stdin is closed: a playbook reading it
# would swallow the step's later lines.
#
# --production <step>: the same lines against production (inventory/production.yml), with production's secrets
# (-e @vars/vault.yml, as the production setup tasks pass them), without the Vagrant guard - `task
# deploy:upgrade:playbooks`, after the step's Vagrant proof and the operator's approval. The allow-list holds there too.
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
# --production --check <step>: the same, read-only - ansible's check mode with diffs (no task here overrides it): what
# the step would change on ten and the Pis, before it runs (`task deploy:upgrade:preview`).
step_vars=" argocd_version cilium_version containerd_upgrade_to gateway_api_version istio_version k8s_upgrade_to "
step_vars+="kubelet_grace_in_kubelet_config_map local_path_provisioner_version pg_major pg_namespaces vgw_version "
# fence <playbook> <args...>: exit 1 naming the first argument outside the allow-list
fence() {
  local playbook=$1 name; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --tags) [[ ${2:-} =~ ^[a-z0-9,-]+$ ]] || { echo "REFUSED: $playbook: --tags '${2:-}'" >&2; return 1; }; shift 2;;
      -e) name=${2:-}; name=${name%%=*}
          [[ ${2:-} == *=* && $step_vars == *" $name "* && ${2#*=} =~ ^[A-Za-z0-9._,:-]+$ ]] \
            || { echo "REFUSED: $playbook: -e '${2:-}' is not a step variable with a plain value" >&2; return 1; }
          shift 2;;
      *) echo "REFUSED: $playbook: argument '$1' (only --tags and -e <step variable>=<value>)" >&2; return 1;;
    esac
  done
}
# --lint: every step's playbook lines through the fence, nothing run
if [ "${1:-}" = --lint ]; then
  for f in "$ops"/tests/ansible/upgrade/steps/*.txt; do
    step=$(basename "$f" .txt)
    while read -r playbook args; do
      [ -n "$playbook" ] || continue
      # shellcheck disable=SC2086  # the step file's arguments are meant to split into words
      fence "$playbook" $args || { echo "  in step $step" >&2; exit 1; }
    done <<< "$("$ops/scripts/upgrade-expected-inventory.py" --playbooks "$step")"
  done
  echo "every step's playbook lines within the allow-list"
  exit 0
fi
production=no; check=""
if [ "${1:-}" = --production ]; then production=yes; shift; fi
if [ "${1:-}" = --check ]; then
  [ "$production" = yes ] || { echo "--check is for --production" >&2; exit 1; }
  check="--check --diff"; shift
fi
lines=$("$ops/scripts/upgrade-expected-inventory.py" --playbooks "$1")
while read -r playbook args; do
  [ -n "$playbook" ] || continue
  # shellcheck disable=SC2086  # the step file's arguments are meant to split into words
  fence "$playbook" $args || exit 1
  echo "== $playbook $args"
  if [ "$production" = yes ]; then
    # shellcheck disable=SC2086  # the step file's arguments are meant to split into words
    (cd "$ops/deploy/ansible" && venv/bin/ansible-playbook -i inventory/production.yml "playbooks/$playbook" \
       -e @vars/vault.yml $args $check < /dev/null)
  else
    # shellcheck disable=SC2086
    (cd "$ops/deploy/ansible" && env -i HOME="$HOME" PATH="$PATH" \
       venv/bin/ansible-playbook -i inventory/vagrant.yml ../../tests/ansible/vagrant-only-play.yml \
       "playbooks/$playbook" $args < /dev/null)
  fi
done <<< "$lines"
