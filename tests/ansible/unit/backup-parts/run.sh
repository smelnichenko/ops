#!/bin/bash
# Wave 0's upload in parts and the restores' download (deploy/ansible/playbooks/tasks/upgrade-backup-{upload,download}
# .yml) on localhost against a fake store (./curl): files on both sides of a part boundary come back the same; a
# changed, missing or unlisted part, a wrong whole sha256 and a store reading back other bytes are each refused.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "backup-parts: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
out=$(ANSIBLE_NOCOLOR=1 "$AP" -c local -i localhost, "$H/cases.yml" -e work="$WORK" 2>&1); rc=$?
printf '%s\n' "$out" | grep -oE '"msg": "(PASS|FAIL) [^"]*"' | sed 's/"msg": "//; s/"$//'
n=$(printf '%s\n' "$out" | grep -cE '"msg": "PASS ')
[ $rc -eq 0 ] && [ "$n" -eq 10 ] && echo "backup-parts: ALL-PASS" \
  || { printf '%s\n' "$out" | tail -20; echo "backup-parts: FAILED (rc $rc, $n of 10 passed)"; exit 1; }
