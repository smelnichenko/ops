#!/bin/bash
# ops' own CI runs nothing as root (operator 2026-11-20: no CI as root): every clone
# and step in .woodpecker/*.yaml sets a security context that is non-root - runAsNonRoot and a uid other than 0 - but a
# Kaniko image build, the one exception, which says so (uid 0, runAsNonRoot false); and run inside Woodpecker, this very
# step is not uid 0.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
fails=0
check() {  # name got want
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got  $2"; echo "    want $3"; fails=$((fails + 1)); fi
}
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
check "every clone and step in ops' pipelines non-root (a Kaniko build the one exception, said)" "$("$PY" - <<'PYNONROOT'
import glob, yaml
bad = []
for path in sorted(glob.glob(".woodpecker/*.yaml") + glob.glob(".woodpecker/*.yml")):
    doc = yaml.safe_load(open(path)) or {}
    for kind in ("clone", "steps", "services"):
        items = doc.get(kind) or []
        if isinstance(items, dict):  # the map form: name -> step
            items = [dict(v, name=k) for k, v in items.items()]
        for step in items:
            sc = ((step.get("backend_options") or {}).get("kubernetes") or {}).get("securityContext") or {}
            kaniko = "kaniko-project/executor" in str(step.get("image", ""))
            if kaniko:
                ok = sc.get("runAsUser") == 0 and sc.get("runAsNonRoot") is False
            else:
                ok = sc.get("runAsNonRoot") is True and isinstance(sc.get("runAsUser"), int) and sc["runAsUser"] != 0
            if not ok:
                bad.append(f"{path} {kind}/{step.get('name')}")
print(bad)
PYNONROOT
)" "[]"
if [ "${CI:-}" = woodpecker ]; then
  check "  this step, in Woodpecker, is not root" "$([ "$(id -u)" != 0 ] && echo non-root || echo root)" "non-root"
fi
if [ "$fails" = 0 ]; then echo "ci-nonroot: ALL-PASS"; else echo "ci-nonroot: $fails FAILED"; exit 1; fi
