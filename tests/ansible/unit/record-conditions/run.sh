#!/bin/bash
# setup-consul.yml's and setup-vault-pi.yml's record of the config a service runs (tasks/restart-recorded.yml), its
# condition as the playbook holds it, evaluated by ansible-playbook: found current, or restarted and its check
# passed - recorded; pending and not restarted here (skipped, the check never reached) or the check failed - never
# recorded (the next run would read the new config as loaded, and its restart was lost for good).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
SKIPPED, OK, FAILED = {"skipped": True, "changed": False}, {"rc": 0, "failed": False}, {"rc": 1, "failed": True}
cases = [("current", "current", None), ("pending, restarted and checked", "pending", OK),
         ("pending, its restart skipped here", "pending", SKIPPED),
         ("pending, the check never reached", "pending", "-"), ("pending, the check failed", "pending", FAILED)]
plays = []
for f, name, pend, health, as_list in (
        ("setup-consul.yml", "Consul's config as it runs it, recorded", "_consul_pending", "_consul_health", False),
        ("setup-vault-pi.yml", "Vault's config as it runs it, recorded", "_vault_pending", "_vault_back", True)):
    task = next(t for p in yaml.safe_load(open("deploy/ansible/playbooks/" + f)) for t in p.get("tasks") or []
                if t.get("name") == name)
    for label, state, h in cases:
        answer = [state, "c0ffee"] if as_list else {"stdout_lines": [state, "c0ffee"]}
        facts = {pend: answer, **({health: h} if h not in (None, "-") else {})}
        # a host of its own per case: a fact set in one play stays on its host for the next
        host = f"case{len(plays)}"
        plays.append({"hosts": host, "gather_facts": False, "name": f"{f}: {label}", "tasks": [
            {"ansible.builtin.set_fact": facts},
            {"name": "recorded", "ansible.builtin.debug": {"msg": f"RECORDED {f}: {label}"}, "when": task["when"]},
            {"name": "not", "ansible.builtin.debug": {"msg": f"NOT RECORDED {f}: {label}"},
             "when": f"not ({task['when']})"}]})
# Vault's answer read only when its own check ran (Vault was running): a pending answer setup-consul left in the same
# run (its register of the same name) is not Vault's
answer = next(t for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-vault-pi.yml"))
              for t in p.get("tasks") or [] if t.get("name", "").startswith("Its answer") and "_vault_pending" in str(t))
for label, active in (("vault inactive, consul's answer left", "inactive"), ("vault active", "active")):
    plays.append({"hosts": f"case{len(plays)}", "gather_facts": False, "name": label, "tasks": [
        {"ansible.builtin.set_fact": {"_restart_pending": {"stdout_lines": ["pending", "consul-sha"]},
                                      "_vault_before": {"status": {"ActiveState": active}}}},
        answer,
        {"ansible.builtin.debug": {"msg": "VAULT ANSWER " + label + ": {{ _vault_pending | join('/') }}"}}]})
yaml.safe_dump(plays, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
yaml.safe_dump({"all": {"hosts": {p["hosts"]: {"ansible_connection": "local",
                                                 "ansible_python_interpreter": "{{ ansible_playbook_python }}"}
                                  for p in plays}}}, open(os.path.join(W, "hosts.yml"), "w"))
PY
out=$(ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" 2>&1) \
  || { echo "$out" | grep -E "ERROR|fatal" | head -3; }
fails=0
for f in setup-consul.yml setup-vault-pi.yml; do
  for c in "current:RECORDED" "pending, restarted and checked:RECORDED" \
           "pending, its restart skipped here:NOT RECORDED" "pending, the check never reached:NOT RECORDED" \
           "pending, the check failed:NOT RECORDED"; do
    label=${c%%:*} want=${c#*:}
    if grep -qF "\"msg\": \"$want $f: $label\"" <<< "$out"; then echo "PASS $f: $label: $want"
    else echo "FAIL $f: $label: want $want"; fails=$((fails + 1)); fi
  done
done
for c in "vault inactive, consul's answer left: /" "vault active: pending/consul-sha"; do
  if grep -qF "\"msg\": \"VAULT ANSWER $c\"" <<< "$out"; then echo "PASS Vault's answer, $c"
  else echo "FAIL Vault's answer, want $c"; fails=$((fails + 1)); fi
done
echo "record-conditions: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
