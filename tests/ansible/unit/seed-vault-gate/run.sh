#!/bin/bash
# Localhost harnesses for seed-vault-secrets.yml (no Vault, a few seconds):
#   gate.yml    UNSET / EMPTY / WHITESPACE -> masi write skipped, notice runs, summary says SKIPPED;
#               SET / PADDED -> write runs with the trimmed key, notice skipped, summary says seeded
#   resolve.yml the read tolerance evaluated against the module's real messages; the index + resolve
#               steps reuse existing fields and generate distinct fresh ones
#   oracle.yml  the shipped read task through the REAL module against fakevault.py (needs hvac —
#               present in the CI image; skipped visibly when the local ansible venv lacks it)
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
PY="$(dirname "$AP")/python3"; [ -x "$PY" ] || PY=python3
WORK=$(mktemp -d)
VAULT_PORT=18200
VAULT_PID=""
trap 'rm -rf "$WORK"; [ -n "$VAULT_PID" ] && kill "$VAULT_PID" 2>/dev/null' EXIT
export ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_DISPLAY_SKIPPED_HOSTS=true ANSIBLE_NOCOLOR=1
unset ANSIBLE_CONFIG
python3 "$H/gen.py" "$PB" "$WORK" "$VAULT_PORT" || exit 2
rc_all=0
run() {  # $1=play $2=label $3=expect_write $4=expect_key $5..=args for env(1)
  local play=$1 label=$2 expect=$3 key=$4; shift 4
  local out="$WORK/out-$label.txt"
  env "$@" "$AP" -i localhost, "$WORK/$play" -e "expect_write=$expect" -e "expect_key=$key" > "$out" 2>&1; local rc=$?
  local verdict; verdict=$(grep -oE '"msg": "[^"]*"' "$out" | tail -1)
  printf '%-11s exit=%s  %s\n' "$label" "$rc" "$verdict"
  if [ $rc -ne 0 ]; then rc_all=1; grep -vE '^(PLAY|TASK|ok:|skipping:|$)' "$out" | head -12 | sed 's/^/      | /'; fi
}
run gate.yml UNSET      false ''           -u MASI_ANTHROPIC_API_KEY
run gate.yml EMPTY      false ''           MASI_ANTHROPIC_API_KEY=
run gate.yml WHITESPACE false ''           "MASI_ANTHROPIC_API_KEY= "
run gate.yml SET        true  sk-ant-dummy MASI_ANTHROPIC_API_KEY=sk-ant-dummy
run gate.yml PADDED     true  sk-ant-dummy "MASI_ANTHROPIC_API_KEY= sk-ant-dummy "
run resolve.yml RESOLVE false ''           -u MASI_ANTHROPIC_API_KEY
if "$PY" -c 'import hvac' 2>/dev/null; then
  python3 "$H/fakevault.py" "$VAULT_PORT" & VAULT_PID=$!
  sleep 0.5
  run oracle.yml ORACLE false ''           -u MASI_ANTHROPIC_API_KEY
else
  echo "ORACLE      SKIPPED here: no hvac in $(dirname "$AP") — the CI image runs it"
fi
echo "seed-vault-gate: $([ $rc_all -eq 0 ] && echo ALL-PASS || echo SOME-FAILED)"
exit $rc_all
