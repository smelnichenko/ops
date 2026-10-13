#!/bin/bash
# scripts/upgrade-production.py finished_pod_problems: a finished pod (Succeeded or Failed) left under a Deployment keeps
# its next rollout from being woken - the Deployment controller requeues a Deployment on a pod's delete only once none
# of its pods is left, a finished one counted: on 10-velero's merge (2026-10-13) a Recreate rollout sat at 0 pods until
# the pod Velero had left finished since 10-03 was deleted - then within 4 s. begin, merge and playbooks refuse while
# any is left (any Deployment: a step's chart may switch one to Recreate), naming the delete; a running pod, a Job's,
# one of the namespaces left alone (kagent) is not one.
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
got = m.finished_pod_problems({"items": cluster})
check("a finished pod under a Deployment, Recreate or RollingUpdate (a chart may switch it): refused, the delete named",
      got, ["app/web: its finished pod web-1-a (Failed) keeps its next rollout from being woken - "
            "kubectl delete pod -n app web-1-a",
            "velero/velero: its finished pod velero-865d6fc7dc-dr2jg (Succeeded) keeps its next rollout from being "
            "woken - kubectl delete pod -n velero velero-865d6fc7dc-dr2jg"])
cluster[3]["status"]["phase"] = "Failed"
check("a Failed one too", len(m.finished_pod_problems({"items": cluster})), 2)
check("none left: nothing refused (a running pod; kagent's left as they are)",
      m.finished_pod_problems({"items": [o for o in cluster if o["metadata"]["name"] not in
                                         ("velero-865d6fc7dc-dr2jg", "web-1-a")]}), [])
check("a pod no ReplicaSet owns (a Job's): not one", m.finished_pod_problems(
    {"items": [deploy("x", "d", "Recreate"), {"kind": "Pod", "metadata": {"namespace": "x", "name": "j-1",
     "ownerReferences": owned("Job", "j")}, "status": {"phase": "Succeeded"}}]}), [])
print("finished-pods: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_RL
