#!/bin/bash
# The copy's Velero schedules paused (its overlay over infra's velero values): a full run crossing a schedule's hour (the
# daily 02:00 UTC, the weekly Sunday 03:00 UTC) queued its own backups behind production's full backup - Velero runs one
# at a time - and the restore check timed out on a Queued backup (2026-10-11). backup-check.yml and restore-check.yml
# prove the backup path on the copy; backup-check reads the daily schedule's template, paused or not.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, sys
import yaml
p = "tests/ansible/upgrade/vagrant-overlay/infra/clusters/production/velero/values.vagrant.yaml"
v = yaml.safe_load(open(p)) if os.path.exists(p) else {}
got = {n: (s or {}).get("paused") for n, s in ((v or {}).get("schedules") or {}).items()}
want = {"schnappy-daily": True, "full-weekly": True}
ok = got == want
print(("PASS" if ok else f"FAIL got {got} want {want}") + " the copy's daily and weekly Velero schedules paused")
print("copy-velero-schedules: " + ("ALL-PASS" if ok else "1 FAILED"))
sys.exit(0 if ok else 1)
PY
