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
def flat(items):  # each task, a block's own after it (its rescue too)
    for t in items or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from flat(t.get(k))
tasks = list(flat(play["tasks"]))
idx = lambda pred: next((i for i, t in enumerate(tasks) if pred(t)), None)
dump = idx(lambda t: (t.get("ansible.builtin.stat") or {}).get("path") == "/var/backups/patroni-first-install/keycloak.sql")
stop = idx(lambda t: (t.get("ansible.builtin.systemd") or {}).get("name") == "keycloak"
           and (t.get("ansible.builtin.systemd") or {}).get("state") == "stopped")
create = idx(lambda t: str(t.get("name", "")).startswith("Create forgejo + keycloak databases"))
check("the dump looked for, Keycloak stopped, then its database created", (dump is not None and stop is not None
      and create is not None and dump < stop < create), True)
# whether its database exists, read before the stop: only its creation opens the window - beside a database there
# (in use: the restore refuses; empty: the restore stops Keycloak and counts again) Keycloak keeps serving
db = idx(lambda t: "pg_database" in str(t.get("ansible.builtin.command", t.get("ansible.builtin.shell", "")))
         and "keycloak" in str(t.get("ansible.builtin.command", t.get("ansible.builtin.shell", ""))) and "register" in t)
check("the keycloak database's existence read before the stop", db is not None and stop is not None and db < stop, True)
if stop is not None:
    t = tasks[stop]
    check("stopped on both Pis", (t.get("delegate_to"), t.get("loop")), ("{{ item }}", "{{ groups['pis'] }}"))
    reg = tasks[db]["register"] if db is not None else "_none"
    cases = [(True, ""), (True, "1"), (False, "")]
    check("stopped when a dump waits and its database is not there yet; not beside one there, not without a dump",
          [condition(t.get("when", True), **{"_keycloak_dump": {"stat": {"exists": e}}, reg: {"stdout": out}})
           for e, out in cases], [True, False, False])
# a creation failing after the stop: said - Keycloak left stopped on both Pis (a re-run creates it and restores)
blk = next((t for t in play["tasks"] if "block" in t and any(x is tasks[stop] for x in t["block"])), None) \
    if stop is not None else None
said = [x for x in (blk or {}).get("rescue") or [] if "KEYCLOAK" in str(x.get("ansible.builtin.debug", ""))]
check("the stop and the creation in one block, a failure saying Keycloak is left stopped",
      (blk is not None and any(x is tasks[create] for x in blk["block"]), len(said) == 1,
       any("ansible.builtin.fail" in x for x in (blk or {}).get("rescue") or [])), (True, True, True))
# said only where Keycloak was stopped: not where the stop was skipped (no dump waiting), nor where it never ran
if said:
    stop_reg = tasks[stop].get("register") if stop is not None else None
    check("the message only where Keycloak was stopped (the stop ran; skipped or never reached: nothing said)",
          [condition(said[0].get("when", True), **ctx) for ctx in
           ({stop_reg: {"changed": True}}, {stop_reg: {"skipped": True}}, {})], [True, False, False])
print("keycloak-stop-first: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
