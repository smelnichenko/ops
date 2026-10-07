#!/bin/bash
# setup-patroni.yml's restart play as the playbook holds it - its facts and conditions run by ansible-playbook on two
# local hosts (pi1, pi2), every other module a stub, tasks/restart-pending.yml's answer given: a first install on both
# Pis, on one (the other's Patroni kept), the unit current, the unit pending - the play ends, and Patroni's unit is
# recorded on each node (a first install, current, or restarted). A first install has no pending answer read: the
# record's condition read it first and the play failed on every new Pi pair.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
case_() {  # case_ <name> <pi1 first install> <pi2 first install> <pending answer> <want: recorded on pi1,pi2>
  W=$W FIRST1=$2 FIRST2=$3 ANSWER=$4 "$PY" - <<'PY' || { echo "FAIL $1: the play could not be built"; return 1; }
import os, yaml
W = os.environ["W"]
play = next(p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-patroni.yml"))
            if p.get("name", "").startswith("A changed config reloaded"))
REG = {"rc": 0, "stdout": "", "stdout_lines": [], "changed": True,
       "json": {"patroni": {"version": "4.0.0"}, "role": "replica"}}
KEEP = ("name", "when", "run_once", "loop", "loop_control", "vars")


def stub(t):
    """The task as it decides: set_fact and assert kept, the pending check answered, the record kept as a fact,
    anything else a set_fact of its register (or a no-op) under its own condition."""
    if "block" in t:
        return {**{k: v for k, v in t.items() if k not in ("block", "rescue", "always")},
                **{k: [stub(x) for x in t[k]] for k in ("block", "rescue", "always") if k in t}}
    keep = {k: v for k, v in t.items() if k in KEEP}
    inc = t.get("ansible.builtin.include_tasks", "")
    if inc == "tasks/restart-pending.yml":
        return {**keep, "ansible.builtin.set_fact": {"_restart_pending": {
            "stdout_lines": [os.environ["ANSWER"], "c0ffee"]}}}
    if inc == "tasks/restart-recorded.yml":
        return {**keep, "ansible.builtin.set_fact": {"_recorded": "{{ loaded_hash }}"}}
    if "ansible.builtin.set_fact" in t or "ansible.builtin.assert" in t:
        return {**keep, **{k: v for k, v in t.items() if k.startswith("ansible.builtin.")}}
    if "register" in t:
        return {**keep, "ansible.builtin.set_fact": {t["register"]: REG}}
    return {**keep, "ansible.builtin.debug": {"msg": "stub"}}


play = {**{k: v for k, v in play.items() if k not in ("become", "vars_files", "tasks")},
        "vars_files": [os.path.abspath("deploy/ansible/vars/patroni.yml")],
        "tasks": [stub(t) for t in play["tasks"]] + [
            {"name": "recorded", "ansible.builtin.debug": {"msg": "RECORDED {{ inventory_hostname }}={{ _recorded | default('none') }}"}}]}
yaml.safe_dump([play], open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
yaml.safe_dump({"all": {"hosts": {h: {
    "ansible_connection": "local", "ansible_python_interpreter": "{{ ansible_playbook_python }}",
    "_patroni_first_install": os.environ[v] == "true"} for h, v in (("pi1", "FIRST1"), ("pi2", "FIRST2"))}}},
    open(os.path.join(W, "hosts.yml"), "w"))
PY
  out=$(ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" 2>&1); rc=$?
  got=$(sed -n 's/.*"msg": "RECORDED \(.*\)".*/\1/p' <<< "$out" | sort | paste -sd,)
  if [ $rc = 0 ] && [ "$got" = "$5" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc, recorded '$got', want '$5'):"; grep -E "ERROR|FAILED|fatal" <<< "$out" | head -3
  fails=$((fails + 1))
}
case_ "a first install on both Pis: recorded on both" true true current pi1=c0ffee,pi2=c0ffee
case_ "a first install on one Pi, the other's unit current: recorded on both" true false current pi1=c0ffee,pi2=c0ffee
case_ "the unit current on both: recorded on both" false false current pi1=c0ffee,pi2=c0ffee
case_ "the unit pending: restarted, recorded on both" false false pending pi1=c0ffee,pi2=c0ffee
echo "patroni-pending: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
