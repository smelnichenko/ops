#!/bin/bash
# The cleanups of a Postgres side cluster - restore-check.yml's (the recovering block's always:) and the Wave 0 dump's
# (tasks/wave0-pg-dump.yml) - as the files hold them, run by ansible-playbook on localhost, their steps stubbed and
# logged: the side cluster removed, then its policies, and restore-check's Backup object - also when removing the side
# cluster fails (it outlived its bound): a failed task in always: ended the cleanup there, the rest left behind.
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


def stub(t):
    if any(k in t for k in ("block", "rescue", "always")):
        return {**{k: v for k, v in t.items() if k not in ("block", "rescue", "always")},
                **{k: [stub(x) for x in t[k]] for k in ("block", "rescue", "always") if k in t}}
    keep = {k: v for k, v in t.items() if k in ("name", "when")}
    inc = str(t.get("ansible.builtin.include_tasks", ""))
    cmd = str(t.get("ansible.builtin.command", ""))
    if inc.endswith("side-cluster-delete.yml"):  # the case says: removed, or outlived its bound
        return {**keep, "ansible.builtin.shell": f"echo side-cluster >> {LOG}; exit {{{{ 1 if side_fails else 0 }}}}"}
    if inc.endswith("side-cluster-policies.yml"):
        return {**keep, "ansible.builtin.shell": f"echo policies-{t['vars']['side_state']} >> {LOG}"}
    if "delete backups.postgresql.cnpg.io" in cmd:
        return {**keep, "ansible.builtin.shell": f"echo backup >> {LOG}"}
    raise SystemExit(f"a cleanup step this harness does not know: {t.get('name')}")


def removes(items):
    """Whether these tasks (their blocks too) remove a side cluster."""
    return any(str(x.get("ansible.builtin.include_tasks", "")).endswith("side-cluster-delete.yml")
               or removes(x.get("block")) or removes(x.get("rescue")) or removes(x.get("always")) for x in items or [])


def cleanup(items):
    """The outermost always: that removes a side cluster, wherever in the file it is."""
    for t in items or []:
        if removes(t.get("always")):
            return t["always"]
        found = cleanup(t.get("block")) or cleanup(t.get("rescue")) or cleanup(t.get("always"))
        if found:
            return found
    return None


tasks = [{"name": "the work as the case says", "ansible.builtin.command": "{{ 'false' if work_fails else 'true' }}"}]
for name, path in (("restore-check", "tests/ansible/upgrade/restore-check.yml"),
                   ("wave0-pg-dump", "tests/ansible/upgrade/tasks/wave0-pg-dump.yml")):
    doc = yaml.safe_load(open(path))
    found = cleanup(doc[0]["tasks"] if "hosts" in doc[0] else doc)
    if not found:
        raise SystemExit(f"{path}: no side cluster's cleanup found")
    yaml.safe_dump([{"hosts": "localhost", "gather_facts": False, "tasks": [
        {"name": "the work, its own steps stubbed", "block": tasks, "always": [stub(x) for x in found]}]}],
        open(os.path.join(W, name + ".yml"), "w"), sort_keys=False)
PY
fails=0
case_() {  # case_ <name> <play> <work_fails> <side_fails> <want rc 0|1> <want log, ; between>
  : > "$W/log"
  out=$(ANSIBLE_NOCOLOR=1 "$AP" -i localhost, -c local "$W/$2.yml" -e "{\"work_fails\": $3, \"side_fails\": $4, \"dump_name\": \"d\"}" 2>&1)
  rc=$?; [ $rc = 0 ] || rc=1
  got=$(paste -sd';' "$W/log")
  if [ "$rc" = "$5" ] && [ "$got" = "$6" ]; then echo "PASS $2: $1"; return; fi
  echo "FAIL $2: $1 (rc $rc)"; echo "    got:  $got"; echo "    want: $6"; grep -E "ERROR|fatal" <<< "$out" | head -3
  fails=$((fails + 1))
}
R="backup;side-cluster;policies-absent" D="side-cluster;policies-absent"
case_ "done: the Backup, the side cluster, then its policies removed" restore-check false false 0 "$R"
case_ "failed: all three removed, the run fails" restore-check true false 1 "$R"
case_ "the side cluster outliving its bound: the Backup and the policies removed all the same" restore-check \
  false true 1 "$R"
case_ "done: the side cluster, then its policies removed" wave0-pg-dump false false 0 "$D"
case_ "the side cluster outliving its bound: its policies removed all the same" wave0-pg-dump false true 1 "$D"
echo "restore-check-cleanup: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
