#!/bin/bash
# metrics-check.yml's scrape-pool record is the build's (-e record_scrape_pools=true), never a step's: each step is
# compared with that baseline - rewritten after every step, a transient extra target (the k6 smoke runs beside the
# check) became a minimum, and the next step failed "smaller". The record task's condition, evaluated as Ansible does.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "scrape-pools-record: no python3 with ansible and yaml"; exit 2; }
"$PY" - <<'PY'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
tasks = yaml.safe_load(open("tests/ansible/upgrade/metrics-check.yml"))[0]["tasks"]
record = next(t for t in tasks if "scrape_pools_file" in str(t.get("ansible.builtin.copy", {}).get("dest", "")))
whens = record.get("when", [])
whens = whens if isinstance(whens, list) else [whens]
writes = lambda flag: all(render("{{ %s }}" % w, record_scrape_pools=flag) for w in whens)
fails = 0
for flag, want, what in ((True, True, "the build's Argo stage records"), (False, False, "a step's check leaves the record")):
    ok = writes(flag) == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {what}")
print("scrape-pools-record: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
