#!/bin/bash
# setup-istio.yml (task deploy:istio) against production's shape (read 2026-10-08): the gateway that serves pmon.dev
# is the infra environment's - the mesh chart's Gateway <release>-gateway in namespace schnappy-infra (the
# ApplicationSet's path segment), Istio's Service for it <gateway>-istio, external IP ten's - and no namespace carries
# istio-injection: a pod is injected by its own label (sidecar.istio.io/inject: "true", the webhook's object
# selector), so the playbook labels no namespace (it labelled `schnappy`, a namespace production no longer has, and
# waited 5 minutes for a Service there). Its health probe judged: no answer at all (the gateway unreachable, its TLS
# failing) fails; an application's own status (a first install's apps still starting) is said, not failed.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYIG'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render, trust_as_template  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-istio.yml"))[0]
v = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in play["vars"].items()}
tasks = play["tasks"]
wait = next((t for t in tasks if (t.get("kubernetes.core.k8s_info") or {}).get("kind") == "Service"), None)
got = (str(render(str(wait["kubernetes.core.k8s_info"]["namespace"]), **v)),
       str(render(str(wait["kubernetes.core.k8s_info"]["name"]), **v))) if wait else None
check("the gateway waited for: the infra environment's, as Istio names it", got,
      ("schnappy-infra", "schnappy-infra-gateway-istio"))
check("no namespace labelled for injection (a pod's own label injects it)",
      [t.get("name") for t in tasks if "istio-injection" in str(t)], [])
probe = next((t for t in tasks if "api/health" in str(t.get("ansible.builtin.shell", ""))), None)
reg = probe.get("register") if probe else None
judge = lambda out: condition(probe.get("failed_when", False), **{reg: {"stdout": out, "rc": 0 if out != "000" else 7}})
check("the health probe: no answer (000) fails; an application's 503 or 200 does not",
      [judge("000"), judge("503"), judge("200")] if probe else None, [True, False, False])
print("istio-gateway: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYIG
