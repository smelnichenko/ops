#!/bin/bash
# setup-keepalived.yml's play for its drop-in as the playbook holds it, run by ansible-playbook on two local hosts
# (pi1, pi2), every module a stub that logs what it would do, the pending answer given per Pi: a drop-in pending is
# loaded by a daemon-reload - no restart: it sets ExecStopPost alone (the drop-in this playbook writes, pinned here: a
# run-time refusal of its own constant could never clear), which systemd runs at keepalived's next stop from the unit
# as it holds it (a restart moved the VIP for nothing) - and systemd is seen holding it, needing no reload, before the
# record: read from what the stub's systemd last loaded (a reload logged), pending or not; each Pi records its drop-in
# as systemd runs it - pending was read by the clock, wrong both ways on the Pis (no RTC).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W "$PY" - <<'PYBUILD' || { echo "FAIL the plays could not be built"; exit 1; }
import os, yaml
W = os.environ["W"]
plays = [p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-keepalived.yml"))
         if p.get("name", "").startswith(("Keepalived's restart order", "Keepalived restarted where pending",
                                          "Keepalived's drop-in loaded where pending"))]
assert [p["name"] for p in plays] == ["Keepalived's drop-in loaded where pending - a daemon-reload, no restart"], \
    [p.get("name") for p in plays]
LOG = os.path.join(W, "log")
KEEP = ("name", "when", "run_once", "loop", "loop_control", "vars", "changed_when", "failed_when")


def log(text):
    return {"ansible.builtin.shell": f"echo \"{{{{ inventory_hostname }}}} {text}\" >> {LOG}"}


def stub(t):
    """The task as it decides, its effect logged: the pending probe and the drop-in's lines answered from the host's
    vars, systemd's view of the unit too; a reload, a restart and the record logged."""
    if "block" in t:
        return {**{k: v for k, v in t.items() if k not in ("block", "rescue", "always")},
                **{k: [stub(x) for x in t[k]] for k in ("block", "rescue", "always") if k in t}}
    keep = {k: v for k, v in t.items() if k in KEEP}
    inc = t.get("ansible.builtin.include_tasks", "")
    if inc == "tasks/restart-pending.yml":
        return {**keep, "ansible.builtin.set_fact": {"_restart_pending": {"stdout": "{{ answer }}",
                                                                          "stdout_lines": ["{{ answer }}", "c0ffee"]}}}
    if inc == "tasks/restart-recorded.yml":
        return {**keep, **log("recorded {{ loaded_service }} {{ loaded_hash }}")}
    svc = t.get("ansible.builtin.systemd", {})
    if svc.get("state") in ("restarted", "reloaded", "stopped", "started"):
        return {**keep, **log(f"{svc['state']} {svc['name']}")}
    if svc.get("daemon_reload"):
        return {**keep, **log("daemon-reload")}
    argv = (t.get("ansible.builtin.command") or {}).get("argv") if isinstance(t.get("ansible.builtin.command"), dict) \
        else str(t.get("ansible.builtin.command", "")).split()
    if argv and argv[0] == "grep":
        raise SystemExit("the drop-in's lines grepped at run time: a constant this playbook writes - pinned by this "
                         "harness instead (a refusal there could never clear)")
    if argv and argv[:2] == ["systemctl", "show"]:
        # what systemd holds for the unit: the drop-in once a reload loaded it here (current: loaded before), unless
        # the reload was lost or the unit changed since (stale_unit)
        return {**keep, "register": t["register"], "ansible.builtin.shell":
                f"if [ '{{{{ stale_unit | default(false) }}}}' != True ] && {{ [ '{{{{ answer }}}}' = current ] || "
                f"{{ grep -qx '{{{{ inventory_hostname }}}} daemon-reload' {LOG} && "
                f"[ '{{{{ reload_lost | default(false) }}}}' != True ]; }}; }}; then "
                "echo 'ExecStopPost={ path=/etc/keepalived/active_services_backup.sh ; "
                "argv[]=/etc/keepalived/active_services_backup.sh --force ; }'; echo NeedDaemonReload=no; "
                "else echo ExecStopPost=; echo NeedDaemonReload=yes; fi"}
    if any(k in t for k in ("ansible.builtin.set_fact", "ansible.builtin.assert")):
        return {**keep, **{k: v for k, v in t.items() if k.startswith("ansible.builtin.")}}
    raise SystemExit(f"a task this harness does not know: {t.get('name')}")


# the drop-in this playbook writes sets ExecStopPost alone - anything else needs keepalived restarted
book = yaml.safe_load(open("deploy/ansible/playbooks/setup-keepalived.yml"))
drop = [t["ansible.builtin.copy"]["content"] for p in book for t in p.get("tasks") or []
        if (t.get("ansible.builtin.copy") or {}).get("dest") ==
        "/etc/systemd/system/keepalived.service.d/release-active-services.conf"]
import re
assert len(drop) == 1 and all(re.fullmatch(r"\[Service\]|ExecStopPost=.*|#.*|\s*", l) for l in drop[0].splitlines()), \
    f"the drop-in sets more than ExecStopPost: {drop}"
out = []
for p in plays:
    out.append({**{k: v for k, v in p.items() if k not in ("become", "tasks")},
                "tasks": [stub(t) for t in p["tasks"]]})
yaml.safe_dump(out, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
PYBUILD
fails=0
case_() {  # case_ <name> <pi1 answer> <pi2 answer> <pi1's other vars, a: b> <want rc 0|1> <want log, ; between>
  : > "$W/log"
  printf 'all:\n  hosts:\n' > "$W/hosts.yml"
  printf '    pi1: {answer: %s, %s}\n    pi2: {answer: %s}\n' "$2" "$4" "$3" >> "$W/hosts.yml"
  printf '  vars: {ansible_connection: local, ansible_python_interpreter: "{{ ansible_playbook_python }}",
    keepalived_vip: 192.168.11.5}\n  children: {pis: {hosts: {pi1: {}, pi2: {}}}}\n' >> "$W/hosts.yml"
  out=$(ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" 2>&1); rc=$?
  [ $rc = 0 ] || rc=1
  got=$(sort "$W/log" | paste -sd';')
  if [ $rc = "$5" ] && [ "$got" = "$6" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc)"; echo "    got:  $got"; echo "    want: $6"; grep -E "ERROR|fatal" <<< "$out" | head -3
  fails=$((fails + 1))
}
case_ "both pending: each unit read again, no restart, both recorded" pending pending "x: 0" 0 \
  "pi1 daemon-reload;pi1 recorded keepalived c0ffee;pi2 daemon-reload;pi2 recorded keepalived c0ffee"
case_ "both current: nothing reloaded or restarted, both recorded" current current "x: 0" 0 \
  "pi1 recorded keepalived c0ffee;pi2 recorded keepalived c0ffee"
case_ "pending, the reload lost (systemd holds the old unit): fails there, nothing recorded on that Pi" \
  pending pending "reload_lost: true" 1 "pi1 daemon-reload;pi2 daemon-reload;pi2 recorded keepalived c0ffee"
case_ "current by its record, systemd needing a reload all the same: fails there, nothing recorded on that Pi" \
  current current "stale_unit: true" 1 "pi2 recorded keepalived c0ffee"
echo "keepalived-pending: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
