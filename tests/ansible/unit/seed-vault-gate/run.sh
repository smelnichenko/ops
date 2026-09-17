#!/bin/bash
# Localhost harnesses for seed-vault-secrets.yml (no Vault, a few seconds):
#   gate.yml    UNSET / EMPTY / WHITESPACE -> masi write skipped, notice runs; SET -> write runs, notice skipped
#   resolve.yml the existing-secret read tolerates ONLY a missing path, and the resolve step
#               reuses an existing password / generates a fresh 32-char one
# Exit 1 if any verdict fails.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
PB="$ROOT/deploy/ansible/playbooks/seed-vault-secrets.yml"
# ansible-playbook: PATH (the CI image), the repo venv, or the venv behind a pipx ansible-lint
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; } \
  || { L=$(command -v ansible-lint 2>/dev/null) && echo "$(dirname "$(readlink -f "$L")")/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "seed-vault-gate: no ansible-playbook found (PATH, repo venv, pipx ansible-lint)"; exit 2; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_DISPLAY_SKIPPED_HOSTS=true ANSIBLE_NOCOLOR=1
unset ANSIBLE_CONFIG
python3 "$H/gen.py" "$PB" "$WORK" || exit 2
rc_all=0
run() {  # $1=play $2=label $3=expect_write $4..=args for env(1)
  local play=$1 label=$2 expect=$3; shift 3
  local out="$WORK/out-$label.txt"
  env "$@" "$AP" -i localhost, "$WORK/$play" -e "expect_write=$expect" > "$out" 2>&1; local rc=$?
  local verdict; verdict=$(grep -oE '"msg": "[^"]*"' "$out" | tail -1)
  printf '%-11s exit=%s  %s\n' "$label" "$rc" "$verdict"
  if [ $rc -ne 0 ]; then rc_all=1; grep -vE '^(PLAY|TASK|ok:|skipping:|$)' "$out" | head -12 | sed 's/^/      | /'; fi
}
run gate.yml UNSET      false -u MASI_ANTHROPIC_API_KEY
run gate.yml EMPTY      false MASI_ANTHROPIC_API_KEY=
run gate.yml WHITESPACE false "MASI_ANTHROPIC_API_KEY= "
run gate.yml SET        true  MASI_ANTHROPIC_API_KEY=sk-ant-dummy
run resolve.yml RESOLVE false -u MASI_ANTHROPIC_API_KEY
echo "seed-vault-gate: $([ $rc_all -eq 0 ] && echo ALL-PASS || echo SOME-FAILED)"
exit $rc_all
