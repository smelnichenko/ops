#!/bin/bash
# A base backup after a PostgreSQL major upgrade is taken on the new major: postgres-base-backup.yml, given the step's
# major (pg_major), fails unless the cluster's primary runs it - its conditions as Ansible evaluates them (an old major
# still running made a backup the new one cannot replay, its archiving proven all the same); with none (CNPG's, its
# store's steps) any major. The Vagrant runner's two calls and production's two pass the step's own
# (upgrade-expected-inventory.py's pg_major).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import importlib.machinery, importlib.util, re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
tasks = yaml.safe_load(open("deploy/ansible/playbooks/postgres-base-backup.yml"))[0]["tasks"]
t = next((t for t in tasks if "server_version_num" in str(t)), None)
check("the playbook reads the primary's server_version_num", t is not None, True)
if t:
    order = [x.get("name") for x in tasks]
    check("read before the WAL switch and the base backup",
          order.index(t["name"]) < min(i for i, x in enumerate(tasks) if "pg_switch_wal" in str(x)), True)
    fw = t.get("failed_when")
    out = lambda v, rc=0: {"rc": rc, "stdout": v}
    for name, version, major, want in (("18 running, 18 asked", "180006", "18", False),
                                       ("17 still running, 18 asked: fails", "170006", "18", True),
                                       ("no major asked: any", "170006", "", False),
                                       ("the read failing: fails", "", "18", True)):
        check(f"the major: {name}", condition(fw, _server_version=out(version, 0 if version else 1), pg_major=major),
              want)
l = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", l))
l.exec_module(m)
calls = []
m.ansible = lambda *a: calls.append(list(a)) or True
m.confirm = lambda q: True
m.ledger_for = lambda st, ph, arg=None: (m.step_names(), [], m.step_info(st))
m.proof_problems = lambda *a, **k: []
m.soak_state = lambda *a: (None, 0)
m.check = lambda *a, **k: True
m.record = lambda *a, **k: None
m.ten_now = lambda: "2026-10-07T10:00:00Z"
# the merge live on origin/main: read in the step's repos beside ops (CI's checkout has none) - not this test's
m.merged_live_problems = lambda *a: []
try:
    m.done("47-postgres-18")
except SystemExit:
    pass
check("production's done takes 47's base backup on 18", [c for c in calls if "postgres-base-backup" in c[0]],
      [["playbooks/postgres-base-backup.yml", "-e", "pg_major=18"]])
calls.clear()
try:
    m.done("24-cnpg")
except SystemExit:
    pass
check("CNPG's own step (no major of its own): done's base backup takes any", [c for c in calls if "postgres-base-backup" in c[0]],
      [["playbooks/postgres-base-backup.yml", "-e", "pg_major="]])
# the step's major from its step file - CNPG's own image line alone (another registry's postgresql is no cluster of
# ours); the CLI the Taskfile reads it with
import os, subprocess, tempfile
li = importlib.machinery.SourceFileLoader("inv", "scripts/upgrade-expected-inventory.py")
inv = importlib.util.module_from_spec(importlib.util.spec_from_loader("inv", li))
li.exec_module(inv)
cli = lambda st: subprocess.run(["scripts/upgrade-expected-inventory.py", "--pg-major", st], capture_output=True,
                                text=True).stdout.strip()
check("the CLI: 47's major 18, CNPG's own step none", (cli("47-postgres-18"), cli("24-cnpg")), ("18", ""))
fx = tempfile.mkdtemp()
open(os.path.join(fx, "x.txt"), "w").write("image docker.io/bitnami/postgresql 16 => image docker.io/bitnami/postgresql 17\n")
open(os.path.join(fx, "y.txt"), "w").write("image ghcr.io/cloudnative-pg/postgresql 17 => "
                                           "image ghcr.io/cloudnative-pg/postgresql 18.6-system-bullseye\n")
inv.STEPS = fx
check("another registry's postgresql: no major; CNPG's: its new one", (inv.pg_major("x"), inv.pg_major("y")), ("", "18"))
tf = open("Taskfile.yml").read()
runs = re.findall(r"barman-check\.yml[^\n]*", tf)
check("the Vagrant runner's barman checks pass the step's major", (len(runs), all("pg_major={{.PG_MAJOR}}" in r for r in runs)),
      (2, True))
check("the step's major from its step file", "PG_MAJOR:\n        sh: scripts/upgrade-expected-inventory.py --pg-major {{.STEP}}" in tf,
      True)
print("base-backup-major: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
