#!/bin/bash
# Renders every copy-content template of create-environment.yml through Ansible and
# parses the output as YAML (~2 s, localhost, nothing touched). Exit 1 on a template
# that no longer parses — the class of defect Argo would otherwise report after the push.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
PB="$ROOT/deploy/ansible/playbooks/create-environment.yml"
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; } \
  || { L=$(command -v ansible-lint 2>/dev/null) && echo "$(dirname "$(readlink -f "$L")")/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "create-environment-values: no ansible-playbook found"; exit 2; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_NOCOLOR=1
unset ANSIBLE_CONFIG
python3 "$H/gen.py" "$PB" "$WORK/render.yml" "$WORK/out" || exit 2
mkdir -p "$WORK/out"
"$AP" -i localhost, "$WORK/render.yml" > "$WORK/log.txt" 2>&1; rc=$?
grep -oE '"stdout": "[^"]*"|parsed [0-9]+ templates' "$WORK/log.txt" | tail -1
if [ $rc -ne 0 ]; then grep -vE '^(PLAY|TASK|ok:|changed:|$)' "$WORK/log.txt" | head -15 | sed 's/^/      | /'; fi
echo "create-environment-values: $([ $rc -eq 0 ] && echo ALL-PASS || echo SOME-FAILED)"
exit $rc
