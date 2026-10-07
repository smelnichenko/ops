#!/bin/bash
# setup-keepalived.yml's restart plays as the playbook holds them - the order (the VIP's holder last) and the restart
# where pending, one Pi at a time - run by ansible-playbook on two local hosts (pi1, pi2), every module a stub that
# logs what it would do, the pending answer given per Pi: each restart reads the unit again first (a drop-in written
# by a run cut short before its handlers was restarted on the old unit), the holder goes last, and each Pi records
# its drop-ins as it runs them (restarted, or found current) - pending was read by the clock, wrong both ways on the
# Pis (no RTC).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W "$PY" - <<'PY' || { echo "FAIL the plays could not be built"; exit 1; }
import os, yaml
W = os.environ["W"]
plays = [p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-keepalived.yml"))
         if p.get("name", "").startswith(("Keepalived's restart order", "Keepalived restarted where pending"))]
assert len(plays) == 2, [p.get("name") for p in plays]
LOG = os.path.join(W, "log")
KEEP = ("name", "when", "run_once", "loop", "loop_control", "vars", "changed_when")


def log(text):
    return {"ansible.builtin.shell": f"echo \"{{{{ inventory_hostname }}}} {text}\" >> {LOG}"}


def stub(t):
    """The task as it decides, its effect logged: the VIP and pending probes answered from the host's vars, add_host
    and set_fact and assert kept, a restart logged with whether it reads the unit again, the record logged."""
    if "block" in t:
        return {**{k: v for k, v in t.items() if k not in ("block", "rescue", "always")},
                **{k: [stub(x) for x in t[k]] for k in ("block", "rescue", "always") if k in t}}
    keep = {k: v for k, v in t.items() if k in KEEP}
    body = str(t)
    inc = t.get("ansible.builtin.include_tasks", "")
    if inc == "tasks/restart-pending.yml":
        return {**keep, "ansible.builtin.set_fact": {"_restart_pending": {"stdout": "{{ answer }}",
                                                                          "stdout_lines": ["{{ answer }}", "c0ffee"]}}}
    if inc == "tasks/restart-recorded.yml":
        return {**keep, **log("recorded {{ loaded_service }} {{ loaded_hash }}")}
    if "ip -o -4 addr show" in body:
        return {**keep, "ansible.builtin.set_fact": {t["register"]: {"stdout": "{{ vip_here }}"}}}
    svc = t.get("ansible.builtin.systemd", {})
    if svc.get("state") == "restarted":
        return {**keep, **log(f"restarted {svc['name']} reload={svc.get('daemon_reload', False)}")}
    if "register" in t and ("ansible.builtin.shell" in t or "ansible.builtin.command" in t
                            or "ansible.builtin.systemd" in t):
        # the old clock check (pending by mtime), the peer's state, the VIP's ping: answered
        return {**keep, "ansible.builtin.set_fact": {t["register"]: {
            "stdout": "{{ answer }}", "stdout_lines": ["{{ answer }}"], "rc": 0,
            "status": {"ActiveState": "active"}}}}
    if any(k in t for k in ("ansible.builtin.add_host", "ansible.builtin.set_fact", "ansible.builtin.assert")):
        return {**keep, **{k: v for k, v in t.items() if k.startswith("ansible.builtin.")}}
    return {**keep, "ansible.builtin.debug": {"msg": "stub"}}


out = []
for p in plays:
    out.append({**{k: v for k, v in p.items() if k not in ("become", "tasks")},
                "tasks": [stub(t) for t in p["tasks"]]})
yaml.safe_dump(out, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
PY
fails=0
case_() {  # case_ <name> <pi1 answer> <pi1 VIP> <pi2 answer> <pi2 VIP> <want log, one line per entry, ; between>
  : > "$W/log"
  printf 'all:\n  hosts:\n' > "$W/hosts.yml"
  printf '    pi1: {answer: %s, vip_here: "%s"}\n    pi2: {answer: %s, vip_here: "%s"}\n' "$2" "$3" "$4" "$5" \
    >> "$W/hosts.yml"
  printf '  vars: {ansible_connection: local, ansible_python_interpreter: "{{ ansible_playbook_python }}",
    keepalived_vip: 192.168.11.5}\n  children: {pis: {hosts: {pi1: {}, pi2: {}}}}\n' >> "$W/hosts.yml"
  out=$(ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" 2>&1); rc=$?
  got=$(paste -sd';' "$W/log")
  if [ $rc = 0 ] && [ "$got" = "$6" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc)"; echo "    got:  $got"; echo "    want: $6"; grep -E "ERROR|fatal" <<< "$out" | head -3
  fails=$((fails + 1))
}
V="inet 192.168.11.5/32"
case_ "both pending, pi1 holds the VIP: pi2 restarted first, the unit read again; both recorded" \
  pending "$V" pending "" \
  "pi2 restarted keepalived reload=True;pi2 recorded keepalived c0ffee;$(
  )pi1 restarted keepalived reload=True;pi1 recorded keepalived c0ffee"
case_ "both current: nothing restarted, both recorded" current "$V" current "" \
  "pi2 recorded keepalived c0ffee;pi1 recorded keepalived c0ffee"
case_ "pi1 pending, pi2 holds the VIP: pi1 restarted, both recorded" pending "" current "$V" \
  "pi1 restarted keepalived reload=True;pi1 recorded keepalived c0ffee;pi2 recorded keepalived c0ffee"
echo "keepalived-pending: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
