#!/bin/bash
# The copy's namespaces made before Argo carry ten's injection label: made bare, the apps' pods started before Argo's
# cluster-config labelled them, ran without sidecars and never reached the STRICT-mTLS Postgres (full run 14).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import sys
import yaml
ps = yaml.safe_load(open("tests/ansible/upgrade/production-state.yml"))
tasks = next(p for p in ps if p.get("hosts") == "target")["tasks"]
t = next(t for t in tasks if (t.get("kubernetes.core.k8s") or {}).get("definition", {}).get("kind") == "Namespace")
labels = t["kubernetes.core.k8s"]["definition"]["metadata"].get("labels") or {}
got = (sorted(t.get("loop", [])), labels.get("istio.io/rev"))
want = (["schnappy-infra", "schnappy-production"], "default")
print(("PASS" if got == want else f"FAIL got {got} want {want}") + " both namespaces made with istio.io/rev=default")
print("production-state-ns-labels: " + ("ALL-PASS" if got == want else "1 FAILED"))
sys.exit(got != want)
PY
