#!/bin/bash
# scripts/upgrade-production.py recreate_leftover_problems: a finished pod (Succeeded or Failed) left under a Deployment
# whose strategy is Recreate holds that Deployment's next rollout: on 10-velero's merge (2026-10-13) the controller
# stopped the new pod for the chart's second change and never started the next one, until the pod Velero had left
# finished since 10-03 was deleted - then within 4 s. begin refuses while any is left, naming the delete; a finished pod
# under a RollingUpdate Deployment, a running one, one of the namespaces left alone (kagent) is not one.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY_RL'
import importlib.machinery, importlib.util, sys
L = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


def owned(kind, name):
    return [{"kind": kind, "name": name, "controller": True}]


def deploy(ns, name, strategy):
    return {"kind": "Deployment", "metadata": {"namespace": ns, "name": name}, "spec": {"strategy": {"type": strategy}}}


def rs(ns, name, deployment):
    return {"kind": "ReplicaSet", "metadata": {"namespace": ns, "name": name,
                                               "ownerReferences": owned("Deployment", deployment)}}


def pod(ns, name, owner, phase):
    return {"kind": "Pod", "metadata": {"namespace": ns, "name": name, "ownerReferences": owned("ReplicaSet", owner)},
            "status": {"phase": phase}}


cluster = [deploy("velero", "velero", "Recreate"), rs("velero", "velero-865d6fc7dc", "velero"),
           rs("velero", "velero-69886b455", "velero"),
           pod("velero", "velero-865d6fc7dc-dr2jg", "velero-865d6fc7dc", "Succeeded"),
           deploy("app", "web", "RollingUpdate"), rs("app", "web-1", "web"), pod("app", "web-1-a", "web-1", "Failed"),
           deploy("data", "db", "Recreate"), rs("data", "db-1", "db"), pod("data", "db-1-a", "db-1", "Running"),
           deploy("kagent", "kagent-postgresql", "Recreate"), rs("kagent", "kagent-postgresql-1", "kagent-postgresql"),
           pod("kagent", "kagent-postgresql-1-a", "kagent-postgresql-1", "Succeeded")]
got = m.recreate_leftover_problems({"items": cluster})
check("a finished pod under a Recreate Deployment: refused, the delete named", got,
      ["velero/velero: its finished pod velero-865d6fc7dc-dr2jg (Succeeded) holds its next Recreate rollout back - "
       "kubectl delete pod -n velero velero-865d6fc7dc-dr2jg"])
cluster[3]["status"]["phase"] = "Failed"
check("a Failed one too", len(m.recreate_leftover_problems({"items": cluster})), 1)
check("none left: nothing refused (RollingUpdate's finished pod, a running pod, kagent's left as they are)",
      m.recreate_leftover_problems({"items": [o for o in cluster if o["metadata"]["name"] != "velero-865d6fc7dc-dr2jg"]}),
      [])
check("a pod no ReplicaSet owns (a Job's): not one", m.recreate_leftover_problems(
    {"items": [deploy("x", "d", "Recreate"), {"kind": "Pod", "metadata": {"namespace": "x", "name": "j-1",
     "ownerReferences": owned("Job", "j")}, "status": {"phase": "Succeeded"}}]}), [])
print("recreate-leftovers: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_RL
