#!/bin/bash
# Localhost harnesses for seed-vault-secrets.yml (no Vault, a few seconds):
#   gate.yml    the masi key is required: UNSET / EMPTY / WHITESPACE -> the required-env assert stops the run,
#               naming it, nothing written; SET / PADDED -> past it, written trimmed, the summary says so
#   resolve.yml the read tolerance evaluated against the module's real messages; the index + resolve
#               steps reuse existing fields and generate distinct fresh ones
#   rescue.yml  the read and write abort messages list every failed item and survive a missing msg
#   write.yml   the write's cas expression: omitted for an existing entry, 0 (create-only) for a fresh one
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
run rescue.yml  RESCUE  false ''           -u MASI_ANTHROPIC_API_KEY
run write.yml   WRITE   false ''           -u MASI_ANTHROPIC_API_KEY
if "$PY" -c 'import hvac' 2>/dev/null; then
  python3 "$H/fakevault.py" "$VAULT_PORT" & VAULT_PID=$!
  sleep 0.5
  run oracle.yml ORACLE false ''           -u MASI_ANTHROPIC_API_KEY
else
  echo "ORACLE      SKIPPED here: no hvac in $(dirname "$AP") — the CI image runs it"
fi
# --tags generatable: the VIP holder, the root token, the generatable read / resolve / write (their aborts, rescue tasks,
# take the block's tag; --list-tasks does not list a rescue) - no
# env-sourced write (an empty .env value would overwrite a live secret) and no retired path deleted
want="The Pi holding the VIP|The Pi holding the VIP is in this run|The other Pis end here|Ensure python3-hvac is installed (required by community.hashi_vault.*)|Read Vault root token|Set token fact|Read existing generatable secrets (404 OK on first run)|Index existing generatable secrets by path|Resolve generatable secret values (existing or fresh, one lookup per field)|Write generatable secrets|"
got=$("$AP" --list-tasks --tags generatable -i localhost, "$PB" 2> /dev/null | sed -n 's/^      \(.*\)\tTAGS: .*/\1/p' | tr '\n' '|')
if [ "$got" = "$want" ]; then echo "TAGS        PASS --tags generatable runs the generatable part alone"
else echo "TAGS        FAIL --tags generatable: got $got"; rc_all=1; fi
# clickhouse's generatable entry, as the play holds it (parsed: a comment or another entry's field is no answer), carries
# the key platform's chart reads for Grafana's own ClickHouse user (external-secrets.yaml: property grafana_password)
if "$PY" - "$PB" <<'PYGRAFANACH'
import sys, yaml
play = yaml.safe_load(open(sys.argv[1]))[0]
entry = [e for e in play["vars"]["generatable_secrets"] if e["path"] == "clickhouse"]
sys.exit(0 if len(entry) == 1 and "grafana_password" in entry[0]["secrets"] and "password" in entry[0]["secrets"] else 1)
PYGRAFANACH
then echo "GRAFANA-CH  PASS clickhouse carries grafana_password (platform's clickhouse.grafanaUser)"
else echo "GRAFANA-CH  FAIL clickhouse has no grafana_password"; rc_all=1; fi
echo "seed-vault-gate: $([ $rc_all -eq 0 ] && echo ALL-PASS || echo SOME-FAILED)"
exit $rc_all
