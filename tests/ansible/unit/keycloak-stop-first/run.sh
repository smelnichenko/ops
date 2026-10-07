#!/bin/bash
# setup-patroni.yml's first install with a Keycloak dump waiting: Keycloak stopped on both Pis before its empty database
# is created - one running reconnected to the new empty database, built its schema there, and the restore then
# refused the database in use (the run stopped for a hand fix). The play's order as it holds it: the dump looked for,
# Keycloak stopped when there is one (its condition as Ansible evaluates it), then the databases created.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
play = next(p for p in yaml.safe_load(open("deploy/ansible/playbooks/setup-patroni.yml"))
            if p.get("name") == "Bootstrap users + keycloak DB on the Patroni primary")
tasks = play["tasks"]
idx = lambda pred: next((i for i, t in enumerate(tasks) if pred(t)), None)
dump = idx(lambda t: (t.get("ansible.builtin.stat") or {}).get("path") == "/var/backups/patroni-first-install/keycloak.sql")
stop = idx(lambda t: (t.get("ansible.builtin.systemd") or {}).get("name") == "keycloak"
           and (t.get("ansible.builtin.systemd") or {}).get("state") == "stopped")
create = idx(lambda t: str(t.get("name", "")).startswith("Create forgejo + keycloak databases"))
check("the dump looked for, Keycloak stopped, then its database created", (dump is not None and stop is not None
      and create is not None and dump < stop < create), True)
if stop is not None:
    t = tasks[stop]
    check("stopped on both Pis", (t.get("delegate_to"), t.get("loop")), ("{{ item }}", "{{ groups['pis'] }}"))
    check("stopped when a dump waits, not otherwise",
          [condition(t.get("when", True), _keycloak_dump={"stat": {"exists": e}}) for e in (True, False)], [True, False])
print("keycloak-stop-first: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
