#!/bin/bash
# A base backup after a PostgreSQL major upgrade is taken on the new major: postgres-base-backup.yml, given a major
# (pg_major), fails unless the cluster's primary runs it - its conditions as Ansible evaluates them (an old major still
# running made a backup the new one cannot replay, its archiving proven all the same); with none any major. The
# Vagrant copy's check (test:copy:check) passes none: it proves the backup of whatever the copy runs.
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
tf = open("Taskfile.yml").read()
runs = re.findall(r"barman-check\.yml[^\n]*", tf)
check("the copy's check runs one barman check, no major given (any)", (len(runs), any("pg_major" in r for r in runs)),
      (1, False))
print("base-backup-major: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
