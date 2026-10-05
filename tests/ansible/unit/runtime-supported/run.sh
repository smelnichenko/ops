#!/bin/bash
# upgrade-kubeadm.yml's container-runtime floor (deploy/ansible/playbooks/tasks/runtime-supported.yml) on localhost:
# each Kubernetes minor against containerd versions on both sides of its floor - the playbook's own task file.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
# ansible-playbook: PATH (the CI image) or the repo venv
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "runtime-supported: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
out=$(ANSIBLE_NOCOLOR=1 "$AP" -i localhost, "$H/cases.yml" 2>&1); rc=$?
printf '%s\n' "$out" | grep -oE '"msg": "(PASS|FAIL) [^"]*"' | sed 's/"msg": "//; s/"$//'
n=$(printf '%s\n' "$out" | grep -cE '"msg": "PASS ')
[ $rc -eq 0 ] && [ "$n" -eq 12 ] && echo "runtime-supported: ALL-PASS" \
  || { printf '%s\n' "$out" | tail -15; echo "runtime-supported: FAILED (rc $rc, $n of 12 passed)"; exit 1; }
