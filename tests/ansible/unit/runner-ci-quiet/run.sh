#!/bin/bash
# scripts/upgrade-production.py, three things production's phases met on 2026-10-13 and the judges (proven, frozen in a
# rollout) cannot take: the inventory read while a CI pipeline's local-path helper pod runs (its busybox caught - 03:56,
# 18:16), a finished Job carrying an image the upgrade replaced (Velero's maintenance Jobs, 18:16), and a preview (check
# mode) installing against ten's stale Helm chart index (11-cilium, 18:35).
#   ci_quiet_read      - the inventory read while no helper pod runs: waited for, and read again if one ran meanwhile
#   finished_job_hints - each image production has beyond the expected inventory that a finished Job carries, named
#                        with its delete
#   preview            - root's Helm repository indexes on ten refreshed before the check-mode run
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY_CIQ'
import importlib.machinery, importlib.util, json, sys
L = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


R = lambda rc, out="", err="": type("R", (), {"returncode": rc, "stdout": out, "stderr": err})()
pod = lambda n: {"kind": "Pod", "metadata": {"name": n}}
event = lambda n, at, count=1: {"kind": "Event", "involvedObject": {"name": n}, "lastTimestamp": at, "count": count,
                                "reason": "Pulled", "metadata": {"name": f"{n}.{at}"}}


def quiet(states, reads=None, wait_s=60):
    """ci_quiet_read with ten answering `states` in turn (each local-path-storage read), the clock moving 5 s a sleep"""
    states, log, now = list(states), [], [0.0]
    def ten(command, stdin=None, check=True):
        s = states.pop(0) if len(states) > 1 else states[0]
        log.append("helpers")
        return R(0, json.dumps({"items": s})) if s is not None else R(1, "", "connection refused")
    reads = reads if reads is not None else []
    saved = m.ten
    m.ten = ten
    try:
        out = m.ci_quiet_read(lambda: reads.append(len(log)) or "INVENTORY", wait_s=wait_s, poll=5,
                              sleep=lambda s: now.__setitem__(0, now[0] + s), clock=lambda: now[0])
        return out, len(reads)
    except SystemExit as e:
        return f"refused: {str(e.code)[:60]}", len(reads)
    finally:
        m.ten = saved


old = event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z")
check("quiet: read once", quiet([[old], [old]]), ("INVENTORY", 1))
check("a helper pod running: waited for, then read once",
      quiet([[pod("helper-pod-create-pvc-b"), old], [old], [old], [old]]), ("INVENTORY", 1))
check("a helper ran while it was read (a new event): read again",
      quiet([[old], [old, event("helper-pod-create-pvc-c", "2026-10-13T15:20:01Z")],
             [old, event("helper-pod-create-pvc-c", "2026-10-13T15:20:01Z")]]), ("INVENTORY", 2))
check("an event repeated meanwhile (its count up): read again",
      quiet([[old], [event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z", 2)],
             [event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z", 2)]]), ("INVENTORY", 2))
check("another pod's event: not a helper's - read once",
      quiet([[old], [old, event("local-path-provisioner-x", "2026-10-13T15:20:01Z")]]), ("INVENTORY", 1))
check("helper pods running past the wait: refused, never read",
      (quiet([[pod("helper-pod-create-pvc-b")]])[0][:8], quiet([[pod("helper-pod-create-pvc-b")]])[1]), ("refused:", 0))
check("the helpers not read (ten unanswered): refused, never read - a wait it cannot judge is no quiet",
      (quiet([None])[0][:8], quiet([None])[1]), ("refused:", 0))

# finished_job_hints: the extra image lines a finished Job carries, each with its delete
job = lambda ns, n, image, cond=None, owner=None: {"kind": "Job", "metadata": {"namespace": ns, "name": n,
    **({"ownerReferences": [{"kind": owner, "name": "o"}]} if owner else {})},
    "spec": {"template": {"spec": {"containers": [{"image": image}]}}},
    "status": {"conditions": [{"type": cond, "status": "True"}]} if cond else {"active": 1}}
jobs = {"items": [job("velero", "maint-1", "docker.io/velero/velero:v1.18.0@sha256:ab", "Complete"),
                  job("velero", "maint-2", "docker.io/velero/velero:v1.18.0", "Failed"),
                  job("velero", "maint-3", "docker.io/velero/velero:v1.18.0"),
                  job("velero", "cron-run", "docker.io/velero/velero:v1.18.0", "Complete", owner="CronJob"),
                  job("x", "other", "busybox", "Complete")]}
check("a finished Job carrying an extra image: named with its delete; a running one, a CronJob's, another image's not",
      m.finished_job_hints(["image docker.io/velero/velero v1.18.0"], jobs),
      ["velero/maint-1 (Complete) still carries image docker.io/velero/velero v1.18.0 - kubectl delete job -n velero maint-1",
       "velero/maint-2 (Failed) still carries image docker.io/velero/velero v1.18.0 - kubectl delete job -n velero maint-2"])
check("an image without a tag read as latest (as the inventory)",
      len(m.finished_job_hints(["image busybox latest"], jobs)), 1)
check("no extra image: no hint", m.finished_job_hints([], jobs), [])

# preview: root's Helm indexes refreshed on ten before the check-mode run
order = []
keep = {k: getattr(m, k) for k in ("ledger_for", "proof_problems", "merged_live_problems", "host_work", "record", "ten")}
m.ledger_for = lambda st, ph, arg=None: ([st], [], {"branches": [], "playbooks": ["p.yml"]})
m.proof_problems = lambda *a, **k: []
m.merged_live_problems = lambda *a: []
m.host_work = lambda cmd: order.append("check-mode run") or R(0)
m.record = lambda *a: order.append("recorded")
m.ten = lambda command, stdin=None, check=True: order.append(command) or R(0, "...Successfully got an update\n")
try:
    m.preview("11-cilium")
finally:
    for k, v in keep.items():
        setattr(m, k, v)
check("preview: root's Helm indexes refreshed on ten, then the check-mode run, then recorded", order,
      ["sudo -n helm repo update", "check-mode run", "recorded"])
print("runner-ci-quiet: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_CIQ
