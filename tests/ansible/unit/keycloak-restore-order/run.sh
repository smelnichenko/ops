#!/bin/bash
# tasks/patroni-keycloak-restore.yml's order as it holds it, run by ansible-playbook on local hosts (pi1 the leader,
# pi2), its effects logged: Keycloak stopped and started on both Pis, the restore - the database's table counts
# answered per case. The tables were counted once, before Keycloak was stopped: a Keycloak running on the empty
# database could build its schema in between, the dump (one transaction) then failed on it and every later run refused
# the database in use. Now counted again with Keycloak stopped; a database in use before is refused without a stop.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
W=$W "$PY" - <<'PY' || { echo "FAIL the play could not be built"; exit 1; }
import os, yaml
W = os.environ["W"]
LOG = os.path.join(W, "log")
counts = 0


def stub(t):
    global counts
    if "block" in t:
        return {**{k: v for k, v in t.items() if k not in ("block", "rescue", "always")},
                **{k: [stub(x) for x in t[k]] for k in ("block", "rescue", "always") if k in t}}
    keep = {k: v for k, v in t.items() if k in ("name", "when", "run_once", "loop", "changed_when")}
    cmd = str(t.get("ansible.builtin.command", ""))
    if "pg_tables" in cmd:  # the n-th count answers the case's n-th number
        counts += 1
        return {**keep, "ansible.builtin.set_fact": {t["register"]: {"stdout": f"{{{{ tables[{counts - 1}] }}}}"}}}
    svc = t.get("ansible.builtin.systemd")
    if svc:
        return {**keep, "ansible.builtin.shell": f"echo \"{{{{ item }}}} {svc['name']} {svc['state']}\" >> {LOG}"}
    if "psql" in str(t.get("ansible.builtin.shell", "")):
        return {**keep, "ansible.builtin.shell": f"echo restored >> {LOG}", "register": t["register"]}
    return {**keep, **{k: v for k, v in t.items() if k.startswith("ansible.builtin.")}}


tasks = [stub(t) for t in yaml.safe_load(open("deploy/ansible/playbooks/tasks/patroni-keycloak-restore.yml"))]
yaml.safe_dump([{"hosts": "pi1", "gather_facts": False, "tasks": tasks}], open(os.path.join(W, "play.yml"), "w"),
               sort_keys=False)
PY
fails=0
case_() {  # case_ <name> <table counts, JSON list> <want rc 0|1> <want log, ; between>
  : > "$W/log"
  cat > "$W/hosts.yml" <<HOSTS
all:
  vars: {ansible_connection: local, ansible_python_interpreter: "{{ ansible_playbook_python }}", tables: $2,
         pg_password: x}
  children: {pis: {hosts: {pi1: {}, pi2: {}}}}
HOSTS
  out=$(ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" 2>&1); rc=$?
  [ $rc = 0 ] || rc=1
  got=$(paste -sd';' "$W/log")
  if [ "$rc" = "$3" ] && [ "$got" = "$4" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1 (rc $rc)"; echo "    got:  $got"; echo "    want: $4"; grep -E "ERROR|fatal" <<< "$out" | head -3
  fails=$((fails + 1))
}
S="pi1 keycloak stopped;pi2 keycloak stopped" R="pi1 keycloak started;pi2 keycloak started"
case_ "empty, and still empty with Keycloak stopped: restored, Keycloak started again" "[0, 0]" 0 "$S;restored;$R"
case_ "empty, then its schema built before Keycloak stopped: refused, nothing restored, Keycloak started again" \
  "[0, 92]" 1 "$S;$R"
case_ "in use before: refused, Keycloak never stopped" "[92, 92]" 1 ""
echo "keycloak-restore-order: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
