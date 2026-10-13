#!/bin/bash
# scripts/upgrade-production.py, three things production's phases met on 2026-10-13 and the judges (proven, frozen in a
# rollout) cannot take: the inventory read while a CI pipeline's local-path helper pod runs (its busybox caught - 03:56,
# 18:16), a finished Job carrying an image the upgrade replaced (Velero's maintenance Jobs, 18:16), and a preview (check
# mode) installing against ten's stale Helm chart index (11-cilium, 18:35).
#   ci_quiet_read      - the inventory read while no helper pod runs: waited for, and read again if one ran meanwhile
#                        (a new event, or the read holding the helper's own image line)
#   finished_job_hints - each image production has beyond the expected inventory that a finished Job carries, named
#                        with its delete - only Jobs the inventory reads; a Failed one's logs first
#   preview            - the playbooks' Helm repositories refreshed on ten (root's) before the check-mode run; a
#                        failed refresh refuses
# and three more the review of 2026-10-13 found: critical alerts pending at the deciding check, the backup-check steps'
# Velero backup (the flag was never read in production), and the controller as pushed (left out of the proof).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY_CIQ'
import contextlib, importlib.machinery, importlib.util, io, json, sys
L = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


R = lambda rc, out="", err="": type("R", (), {"returncode": rc, "stdout": out, "stderr": err})()
pod = lambda n, phase="Running": {"kind": "Pod", "metadata": {"name": n}, "status": {"phase": phase}}
event = lambda n, at, count=1, api="v1": {"kind": "Event", "apiVersion": api, "involvedObject": {"name": n},
                                         "lastTimestamp": at, "count": count, "reason": "Pulled",
                                         "metadata": {"name": f"{n}.{at}"}}


class Spin(Exception):
    pass


def quiet(states, reads=None, wait_s=60, suspect=None, out="INVENTORY", at=None):
    """ci_quiet_read with ten answering `states` in turn (each local-path-storage read), the clock moving 5 s a sleep;
    `at`, given a list, gets each read's place among ten's answers. A wait that would never end stops the test (Spin)
    at ten times the wait - a test without its own limit hangs the suite instead of failing"""
    states, log, now = list(states), [], [0.0]
    def sleep(s):
        now[0] += s
        if now[0] > 10 * wait_s:
            raise Spin(f"still waiting after {now[0]} s")
    def ten(command, stdin=None, check=True):
        s = states.pop(0) if len(states) > 1 else states[0]
        log.append("helpers")
        return R(0, json.dumps({"items": s})) if s is not None else R(1, "", "connection refused")
    reads = reads if reads is not None else []
    saved = m.ten
    m.ten = ten
    try:
        got = m.ci_quiet_read(lambda: reads.append(len(log)) or out, suspect=suspect, wait_s=wait_s, poll=5,
                              sleep=sleep, clock=lambda: now[0])
        if at is not None:
            at.extend(reads)
        return got, len(reads)
    except SystemExit as e:
        return f"refused: {str(e.code)[:200]}", len(reads)
    except Spin as e:
        return f"spun: {e}", len(reads)
    finally:
        m.ten = saved


old = event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z")
check("quiet: read once", quiet([[old], [old]]), ("INVENTORY", 1))
at = []
check("a helper pod running: waited for, then read once - after the second helper read, the first that saw none",
      (quiet([[pod("helper-pod-create-pvc-b"), old], [old], [old], [old]], at=at), at), (("INVENTORY", 1), [2]))
check("a helper ran while it was read (a new event): read again",
      quiet([[old], [old, event("helper-pod-create-pvc-c", "2026-10-13T15:20:01Z")],
             [old, event("helper-pod-create-pvc-c", "2026-10-13T15:20:01Z")]]), ("INVENTORY", 2))
check("an event repeated meanwhile (its count up): read again",
      quiet([[old], [event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z", 2)],
             [event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z", 2)]]), ("INVENTORY", 2))
check("another pod's event: not a helper's - read once",
      quiet([[old], [old, event("local-path-provisioner-x", "2026-10-13T15:20:01Z")]]), ("INVENTORY", 1))
check("helper pods running past the wait: refused, naming them, never read",
      quiet([[pod("helper-pod-create-pvc-b")]]),
      ("refused: REFUSED: CI's helper pods still run after 60 s (helper-pod-create-pvc-b)", 0))
check("the helpers not read (ten unanswered): refused, never read - a wait it cannot judge is no quiet",
      (quiet([None])[0][:8], quiet([None])[1]), ("refused:", 0))
check("a finished helper pod (left by a provisioner restart): not running - read once",
      quiet([[pod("helper-pod-create-pvc-z", "Succeeded"), old], [pod("helper-pod-create-pvc-z", "Succeeded"), old]]),
      ("INVENTORY", 1))
check("the helpers not read after the inventory: refused, not read again as if one had run",
      (quiet([[old], None])[0][:51], quiet([[old], None])[1]), ("refused: REFUSED: ten's local-path helper pods not ", 1))
tries = []
check("the read holding the helper's own line (its events late): read again until it does not (here: every try)",
      quiet([[old], [old]], suspect=lambda o: tries.append(o) or True)[0][:8], "refused:")
check("  each try's read judged", len(tries), 5)
check("an event of another shape (events.k8s.io): not read - refused",
      quiet([[event("helper-pod-x", "2026-10-13T15:20:01Z", api="events.k8s.io/v1")]])[0][:8], "refused:")
sent_kinds = []
saved_ten = m.ten
m.ten = lambda command, **k: sent_kinds.append(command.split()[4]) or R(0, json.dumps({"items": []}))
try:
    m.ci_quiet_read(lambda: "x", sleep=lambda s: None, clock=lambda: 0)
finally:
    m.ten = saved_ten
check("before the read the events are listed first, after it the pods first", sent_kinds, ["events,pods", "pods,events"])
cm = {"data": {"helperPod.yaml": "apiVersion: v1\nkind: Pod\nmetadata:\n  name: helper-pod\nspec:\n  containers:\n"
                                 "  - name: helper-pod\n    image: busybox\n"}}
m.ten = lambda command, **k: R(0, json.dumps(cm))
try:
    check("the helper's image line read from the provisioner's config (busybox, no tag: latest)", m.helper_image_line(),
          "image busybox latest")
finally:
    m.ten = saved_ten

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
      m.finished_job_hints(["image docker.io/velero/velero v1.18.0"], jobs, excluded=""),
      ["velero/maint-1 (Complete) still carries image docker.io/velero/velero v1.18.0 - kubectl delete job -n velero maint-1",
       "velero/maint-2 (Failed) still carries image docker.io/velero/velero v1.18.0 - kubectl logs -n velero job/maint-2 "
       "(its logs go with it), then kubectl delete job -n velero maint-2"])
check("an image without a tag read as latest (as the inventory)",
      len(m.finished_job_hints(["image busybox latest"], jobs, excluded="")), 1)
check("no extra image: no hint", m.finished_job_hints([], jobs, excluded=""), [])
jobs2 = {"items": [job("schnappy-test", "t", "busybox", "Complete"), job("woodpecker", "wp-1", "busybox", "Complete")]}
check("only Jobs the inventory reads: not an excluded namespace's, not Woodpecker's pipelines",
      m.finished_job_hints(["image busybox latest"], jobs2, excluded="schnappy-test"), [])

# preview: the playbooks' Helm repositories refreshed on ten (root's) before the check-mode run; a failure refuses
repos = m.playbook_helm_repos()
check("the playbooks' Helm repositories (their helm_repository tasks): eleven, Cilium's and Argo's among them",
      (len(repos), "cilium" in repos, "argo" in repos, "sealed-secrets" in repos), (11, True, True, False))
def preview_with(rc):
    order = []
    keep = {k: getattr(m, k) for k in ("ledger_for", "proof_problems", "merged_live_problems", "host_work", "record",
                                       "ten")}
    m.ledger_for = lambda st, ph, arg=None: ([st], [], {"branches": [], "playbooks": ["p.yml"]})
    m.proof_problems = lambda *a, **k: []
    m.merged_live_problems = lambda *a: []
    m.host_work = lambda cmd: order.append("check-mode run") or R(0)
    m.record = lambda *a: order.append("recorded")
    m.ten = lambda command, stdin=None, check=True: order.append(command) or R(rc, "...", "Unable to get an update")
    try:
        m.preview("11-cilium")
        return order
    except SystemExit:
        return order + ["refused"]
    finally:
        for k, v in keep.items():
            setattr(m, k, v)
check("preview: the playbooks' repositories refreshed on ten, then the check-mode run, then recorded", preview_with(0),
      ["sudo -n helm repo update " + " ".join(repos), "check-mode run", "recorded"])
check("preview: a refresh that fails refuses before the check-mode run", preview_with(1)[1:], ["refused"])

# the deciding check: a critical alert pending or firing is red; a warning, an inactive one is not
alerts = {"data": {"alerts": [
    {"labels": {"alertname": "VeleroDown", "severity": "critical", "namespace": "velero"}, "state": "pending"},
    {"labels": {"alertname": "KubePodCrashLooping", "severity": "warning"}, "state": "firing"},
    {"labels": {"alertname": "CertExpiringIn7Days", "severity": "critical"}, "state": "inactive"}]}}
check("critical alerts pending or firing named; a warning, an inactive one not", m.critical_alert_problems(alerts),
      ["VeleroDown pending velero"])
m.ten = lambda command, **k: R(1, "", "connection refused")
try:
    check("Prometheus not read: a problem, not a pass", len(m.critical_alert_problems()), 1)
finally:
    m.ten = saved_ten

# a backup-check step's Velero backup: Completed with its pod volume backups - else refused; deleted either way
def velero(phase="Completed", errors=0, pvbs=("Completed",), bsl="Available"):
    sent = []
    def ten(command, stdin=None, check=True):
        sent.append((command.split()[3] if len(command.split()) > 3 else command, stdin))
        if "backupstoragelocations" in command:
            return R(0, bsl)
        if "schedules.velero.io" in command:
            return R(0, json.dumps({"spec": {"template": {"includedNamespaces": ["schnappy-production"],
                                                          "defaultVolumesToFsBackup": True}}}))
        if "create -f -" in command:
            return R(0)
        if "podvolumebackups" in command:
            return R(0, json.dumps({"items": [{"metadata": {"name": f"p{i}"}, "status": {"phase": ph}}
                                              for i, ph in enumerate(pvbs)]}))
        if "backups.velero.io" in command:
            return R(0, json.dumps({"status": {"phase": phase, "errors": errors}}))
        return R(1, "", "unexpected")
    m.ten = ten
    try:
        got = m.velero_backup_check(wait_s=60, poll=10, sleep=lambda s: None, clock=iter(range(0, 999, 10)).__next__)
    finally:
        m.ten = saved_ten
    created = [json.loads(s) for c, s in sent if c == "create"]
    return got, [o["kind"] for o in created], created
got, kinds, created = velero()
check("Velero backup Completed, its pod volume backups Completed: no problem; the backup, then its delete request",
      (got, kinds), ([], ["Backup", "DeleteBackupRequest"]))
check("  the backup: the daily schedule's template, Valkey's pods only, an hour's ttl",
      (created[0]["spec"]["includedNamespaces"], created[0]["spec"]["labelSelector"], created[0]["spec"]["ttl"]),
      (["schnappy-production"], {"matchLabels": {"app.kubernetes.io/component": "valkey"}}, "1h0m0s"))
check("PartiallyFailed: refused, deleted all the same", (len(velero("PartiallyFailed")[0]), velero("PartiallyFailed")[1]),
      (1, ["Backup", "DeleteBackupRequest"]))
check("Completed with errors: refused", len(velero(errors=2)[0]), 1)
check("no pod volume backup made: refused", len(velero(pvbs=())[0]), 1)
check("a pod volume backup Failed: refused", len(velero(pvbs=("Completed", "Failed"))[0]), 1)
check("the storage location not Available: refused, nothing created", (len(velero(bsl="Unavailable")[0]),
                                                                       velero(bsl="Unavailable")[1]), (1, []))
check("the backup-check flag read: steps 10, 25, 43", sorted(s for s in m.step_names() if m.step_info(s)["velero_backup"]),
      ["10-velero", "25-versitygw", "43-kubernetes-1.36"])

# the controller as ops main has it: an edit not committed, a commit not pushed - refused, named
def controller(dirty="", diff="", rc=0):
    saved_run = m.run
    m.run = lambda cmd, **k: R(rc, dirty if "status" in cmd else diff, "fatal: bad revision" if rc else "")
    try:
        return m.controller_problems()
    finally:
        m.run = saved_run
check("the controller as pushed: nothing", controller(), [])
check("an edit not committed: refused", len(controller(dirty=" M scripts/upgrade-production.py\n")), 1)
check("a commit not on origin/main: refused", len(controller(diff="scripts/upgrade-production.py\n")), 1)
check("not read: refused", len(controller(rc=128)), 1)
# check(): a critical alert pending makes the deciding call red - and only the deciding call asks
def check_with(alerts, deciding):
    asked = []
    keep = {k: getattr(m, k) for k in ("read_ledger", "inventory_check", "settled", "running_digest_problems", "ansible",
                                       "critical_alert_problems")}
    m.read_ledger = lambda *a, **k: ({}, [])
    m.inventory_check = lambda *a, **k: True
    m.settled = lambda *a, **k: (True, None, [])
    m.running_digest_problems = lambda *a: []
    m.ansible = lambda *a: True
    m.critical_alert_problems = lambda: asked.append(1) or list(alerts)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            return m.check("01-argocd-root-retry", deciding=deciding), len(asked)
    finally:
        for k, v in keep.items():
            setattr(m, k, v)
check("the deciding check: a critical alert pending - red", check_with(["VeleroDown pending velero"], True), (False, 1))
check("the deciding check: none - green", check_with([], True), (True, 1))
check("a first check: alerts not asked (pending may still clear in the soak)", check_with(["X pending"], False), (True, 0))

# ledger_for: the controller not as pushed refuses before the phase claims the step
def ledger_with(controller):
    keep = {k: getattr(m, k) for k in ("read_ledger", "problems", "controller_problems", "record")}
    recorded = []
    m.read_ledger = lambda *a, **k: ({}, [])
    m.problems = lambda *a, **k: []
    m.controller_problems = lambda: list(controller)
    m.record = lambda *a, **k: recorded.append(a)
    try:
        m.ledger_for("01-argocd-root-retry", "begin")
        return "claimed", len(recorded)
    except SystemExit as e:
        return ("refused" if "CONTROLLER-X" in str(e.code) else str(e.code)), len(recorded)
    finally:
        for k, v in keep.items():
            setattr(m, k, v)
        m.CLAIMED.clear()
check("a phase with the controller not as pushed: refused, the step not claimed", ledger_with(["CONTROLLER-X"]),
      ("refused", 0))
check("  as pushed: the step claimed", ledger_with([]), ("claimed", 1))
print("runner-ci-quiet: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_CIQ
