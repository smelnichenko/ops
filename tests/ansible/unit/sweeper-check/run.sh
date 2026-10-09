#!/bin/bash
# The stale PR environment sweeper proven against the copy's Vault after the step that moves it (step 01: its Vault
# read verified, its token renewed, its own NetworkPolicy to Vault - infra): the step's sweeper-check line, read as
# such; the full run's step task running tests/ansible/upgrade/sweeper-check.yml on the copy; the step's playbook line
# replacing production's dead cleanup token (setup-vault-cleanup-policy.yml), the playbook that check runs again; that
# playbook replacing a stored token Vault calls dead, a preview minting none; the check guarded to the Vagrant VMs in
# every play. What the check proves on the copy is its own run (the full run); the sweeper's script is infra's
# tests/stale-pr-envs-sweeper.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
s=01-argocd-root-retry
check "$s: its sweeper-check line, read as such; a step without one: no" \
  "$(grep -c '^sweeper-check$' "tests/ansible/upgrade/steps/$s.txt") \
$(scripts/upgrade-expected-inventory.py --sweeper-check "$s" 2> /dev/null) \
$(scripts/upgrade-expected-inventory.py --sweeper-check 02-istio-chart-repo 2> /dev/null)" "1 yes no"
check "$s: its playbook line replaces production's dead cleanup token" \
  "$(scripts/upgrade-expected-inventory.py --playbooks "$s" 2> /dev/null | grep -cx 'setup-vault-cleanup-policy.yml')" 1
check "the full run's step task runs the check on the copy when the step says so" "$("$PY" -c '
import yaml
t = yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:step"]
v = str((t.get("vars") or {}).get("SWEEPER_CHECK"))
c = [str(x.get("cmd", x) if isinstance(x, dict) else x) for x in t["cmds"]]
print("--sweeper-check {{.STEP}}" in v, any("SWEEPER_CHECK" in x and "tests/ansible/upgrade/sweeper-check.yml" in x
                                             and "inventory/vagrant.yml" in x for x in c))')" "True True"
check "the check: every play guarded to the Vagrant VMs first; the step's playbook run again between its plays" "$("$PY" -c '
import yaml
plays = yaml.safe_load(open("tests/ansible/upgrade/sweeper-check.yml"))
guarded = [p["tasks"][0].get("ansible.builtin.import_tasks") == "../vagrant-only.yml" for p in plays if "hosts" in p]
imports = [p["ansible.builtin.import_playbook"] for p in plays if "ansible.builtin.import_playbook" in p]
print(len(guarded) > 0 and all(guarded), imports, "hosts" in plays[0])')" \
  "True ['../../../deploy/ansible/playbooks/setup-vault-cleanup-policy.yml'] True"
check "the playbook: the stored token looked up (a read, in a preview too); a dead one (403) replaced; a preview mints \
none" "$("$PY" -c '
import yaml
t = {x["name"]: x for x in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-cleanup-policy.yml"))[0]["tasks"]}
look = t["Look the stored cleanup token up in Vault"]
issue = next(x for n, x in t.items() if n.startswith("Issue new periodic token"))
store = t["Store cleanup token at secret/argocd/vault-cleanup-token"]
print(look["ansible.builtin.uri"]["url"].endswith("/v1/auth/token/lookup"), look.get("check_mode") is False,
      look["ansible.builtin.uri"]["status_code"] == [200, 403], "_token_lookup.status | default(200) == 403" in issue["when"],
      "not ansible_check_mode" in store["when"], look.get("no_log") is True)')" "True True True True True True"
# the stored token's check as Ansible finalizes it - fail_msg rendered even when the assert passes (ansible-core 2.20):
# a first install has no stored token (the lookup skipped), a dead one answers 403, a live one 200
check "the token check: no token yet (lookup skipped), live, dead - passes, rendered; another answer refused" "$("$PY" -c '
import sys, yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render
t = {x["name"]: x for x in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-cleanup-policy.yml"))[0]["tasks"]}
a = t["The stored token lives, or Vault calls it dead"]["ansible.builtin.assert"]
out = []
for look in ({"skipped": True, "changed": False}, {"status": 200, "json": {}}, {"status": 403, "json": {"errors": ["bad token"]}},
             {"status": 403, "json": {"errors": ["permission denied"]}}):
    try:
        render(a["fail_msg"], _token_lookup=look)
        out.append(condition(a["that"], _token_lookup=look))
    except Exception as e:
        out.append("error: " + type(e).__name__)
print(out)')" "[True, True, True, False]"
echo "sweeper-check: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
