#!/bin/bash
# Every Helm repository task runs in check mode too (check_mode: false): it only writes the node's local chart index,
# and a step's preview (check mode) then installs against the index as it is. Skipped there, 11-cilium's preview
# (2026-10-13) asked ten's index of April 2 for cilium 1.19.8 and failed - the real run refreshes it first.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 exec "$PY" - <<'PY_HRCM'
import glob, sys, yaml
def walk(ts):
    for t in ts or []:
        if isinstance(t, dict):
            yield t
            for k in ("block", "rescue", "always"):
                yield from walk(t.get(k))
found, bad = 0, []
for path in sorted(glob.glob("deploy/ansible/playbooks/**/*.yml", recursive=True)):
    doc = yaml.safe_load(open(path))
    plays = doc if isinstance(doc, list) else []
    tasks = [t for p in plays if isinstance(p, dict) for k in ("tasks", "pre_tasks", "post_tasks", "handlers")
             for t in walk(p.get(k))] + ([t for t in walk(plays)] if plays and "hosts" not in plays[0] else [])
    for t in tasks:
        if "kubernetes.core.helm_repository" in t or "helm_repository" in t:
            found += 1
            if t.get("check_mode") is not False:
                bad.append(f"{path}: {t.get('name')}")
fails = 0
print(("PASS" if found >= 12 else "FAIL") + f" {found} Helm repository tasks found (at least 12)")
fails += found < 12
for b in bad:
    print(f"FAIL runs not in check mode: {b}")
fails += len(bad)
print("helm-repo-check-mode: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_HRCM
