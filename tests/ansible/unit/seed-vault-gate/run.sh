#!/bin/bash
# Drives the masi-key gate of seed-vault-secrets.yml through four env states on
# localhost (no Vault, ~2 s). Exit 1 if any verdict fails.
#   UNSET / EMPTY / WHITESPACE -> the write must be skipped and the notice must run
#   SET                        -> the write must run with a non-empty key, the notice skipped
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
python3 "$H/gen.py" "$PB" "$WORK/harness.yml" || exit 2
rc_all=0
run() {  # $1=label $2=expect_write $3..=args for env(1)
  local label=$1 expect=$2; shift 2
  local out="$WORK/out-$label.txt"
  env "$@" "$AP" -i localhost, "$WORK/harness.yml" -e "expect_write=$expect" > "$out" 2>&1; local rc=$?
  local verdict; verdict=$(grep -oE '"msg": "[^"]*"' "$out" | tail -1)
  printf '%-11s expect_write=%-5s exit=%s  %s\n' "$label" "$expect" "$rc" "$verdict"
  if [ $rc -ne 0 ]; then rc_all=1; grep -vE '^(PLAY|TASK|ok:|skipping:|$)' "$out" | head -12 | sed 's/^/      | /'; fi
}
run UNSET      false -u MASI_ANTHROPIC_API_KEY
run EMPTY      false MASI_ANTHROPIC_API_KEY=
run WHITESPACE false "MASI_ANTHROPIC_API_KEY= "
run SET        true  MASI_ANTHROPIC_API_KEY=sk-ant-dummy
echo "seed-vault-gate: $([ $rc_all -eq 0 ] && echo ALL-PASS || echo SOME-FAILED)"
exit $rc_all
