#!/bin/bash
# Argo CD's health for a Job (setup-argocd.yml's resource.customizations.health.batch_Job), run as Argo runs it -
# Lua 5.1 (gopher-lua): a Job is Degraded only once Kubernetes failed it (backoff exhausted - its Failed condition), not
# while it retries after a failed pod (full run 14: the k6 smoke's first pod missed its latency on a cold copy, its
# retry passed, the hook was failed at the first pod and the sync with it); succeeded once - Healthy, a failed pod
# before or not.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
command -v lua5.1 > /dev/null || { echo "FAIL lua5.1 missing (the CI image has it)"; echo "argocd-job-health: 1 FAILED"; exit 1; }
PY=python3
"$PY" -c 'import yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import json, subprocess, sys
import yaml


def find(node, key):
    if isinstance(node, dict):
        if key in node:
            return node[key]
        node = list(node.values())
    if isinstance(node, list):
        for v in node:
            hit = find(v, key)
            if hit is not None:
                return hit
    return None


lua = find(yaml.safe_load(open("deploy/ansible/playbooks/setup-argocd.yml")), "resource.customizations.health.batch_Job")
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


def table(v):
    if isinstance(v, dict):
        return "{" + ", ".join(f"[{json.dumps(k)}] = {table(x)}" for k, x in v.items()) + "}"
    if isinstance(v, list):
        return "{" + ", ".join(table(x) for x in v) + "}"
    return json.dumps(v)


def health(status):
    obj = {"status": status} if status is not None else {}
    prog = f"obj = {table(obj)}\nlocal f = assert(loadstring({json.dumps(lua)}))\nlocal hs = f()\nio.write(hs.status, '|', hs.message or '')\n"
    r = subprocess.run(["lua5.1", "-"], input=prog, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else "error: " + r.stderr.strip()


check("the check found", isinstance(lua, str) and "hs.status" in lua, True)
st = lambda s: health(s).split("|")[0]
check("no status yet, one running: Progressing", (st(None), st({"active": 1})), ("Progressing", "Progressing"))
check("a pod succeeded: Healthy - a failed one before it or not",
      (st({"succeeded": 1}), st({"succeeded": 1, "failed": 1})), ("Healthy", "Healthy"))
check("a pod failed, the Job retrying (another running, or between them, not Failed): Progressing",
      (st({"failed": 1, "active": 1}), st({"failed": 1}), st({"failed": 2, "conditions": [{"type": "Complete", "status": "False"}]})),
      ("Progressing", "Progressing", "Progressing"))
out = health({"failed": 4, "conditions": [{"type": "Failed", "status": "True", "reason": "BackoffLimitExceeded",
                                            "message": "Job has reached the specified backoff limit"}]})
check("the Job failed (backoff exhausted): Degraded, its condition's message said",
      (out.split("|")[0], "reached the specified backoff limit" in out, "4 pod(s) failed" in out), ("Degraded", True, True))
print("argocd-job-health: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
