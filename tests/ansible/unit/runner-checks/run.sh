#!/bin/bash
# scripts/upgrade-production.py, the checks production's phases gained on 2026-10-13 that the judges (proven, frozen in
# a rollout) do not make:
#   finished_job_hints      - each extra image a finished Job carries named with its delete (a Failed one's logs first),
#                             only Jobs the inventory reads
#   preview's Helm refresh  - the step's own playbooks' repositories, as root has them; a failed download refuses
#   critical_alert_problems - production's critical alerts pending or firing, and the rules loaded
#   settled_alert_problems  - a pending alert followed to its end; check() and begin use it
#   controller_problems     - the controller as loaded equal to origin/main's (fetched), its tests too; every phase
#   velero_backup_check     - a backup-check step's Velero backup on the full run's terms
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY_RC'
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
saved_ten = m.ten

# --- finished_job_hints: the extra image lines a finished Job carries, each with its delete
job = lambda ns, n, image, cond=None, owner=None, labels=None: {"kind": "Job", "metadata": {
    "namespace": ns, "name": n, "labels": labels or {},
    **({"ownerReferences": [{"kind": owner, "name": "o"}]} if owner else {})},
    "spec": {"template": {"spec": {"containers": [{"image": image}]}}},
    "status": {"conditions": [{"type": cond, "status": "True"}]} if cond else {"active": 1}}
jobs = {"items": [job("x", "hook-1", "docker.io/velero/velero:v1.18.0@sha256:ab", "Complete"),
                  job("x", "hook-2", "docker.io/velero/velero:v1.18.0", "Failed"),
                  job("x", "hook-3", "docker.io/velero/velero:v1.18.0"),
                  job("x", "cron-run", "docker.io/velero/velero:v1.18.0", "Complete", owner="CronJob"),
                  job("velero", "maint", "docker.io/velero/velero:v1.18.0", "Complete",
                      labels={"velero.io/repo-name": "r"}),
                  job("y", "other", "busybox", "Complete")]}
check("a finished Job carrying an extra image named with its delete (a Failed one's logs first); a running one, a "
      "CronJob's, Velero's maintenance Jobs (the inventory skips them), another image's not",
      m.finished_job_hints(["image docker.io/velero/velero v1.18.0"], jobs, excluded=""),
      ["x/hook-1 (Complete) still carries image docker.io/velero/velero v1.18.0 - kubectl delete job -n x hook-1",
       "x/hook-2 (Failed) still carries image docker.io/velero/velero v1.18.0 - kubectl logs -n x job/hook-2 "
       "(its logs go with it), then kubectl delete job -n x hook-2"])
jobs2 = {"items": [job("schnappy-test", "t", "busybox", "Complete"), job("woodpecker", "wp-1", "busybox", "Complete")]}
check("only Jobs the inventory reads: not an excluded namespace's, not Woodpecker's pipelines",
      m.finished_job_hints(["image busybox latest"], jobs2, excluded="schnappy-test"), [])
m.ten = lambda command, **k: R(0, "<html>")
try:
    check("the Jobs answered with no JSON: said, not a traceback", m.finished_job_hints(["image a b"], excluded=""),
          ["the Jobs not read: no JSON"])
finally:
    m.ten = saved_ten

# --- preview: the step's own playbooks' repositories refreshed on ten (root's), a failed download refused
repos = m.playbook_helm_repos()
check("the playbooks' Helm repositories (helm_repository tasks, read as YAML): eleven, Cilium's and Argo's among them",
      (len(repos), "cilium" in repos, "argo" in repos), (11, True, True))
check("one playbook's own: setup-istio.yml's", m.playbook_helm_repos(["setup-istio.yml"]), ["istio"])
def preview_with(listed, update_rc=0, playbooks=("setup-kubeadm.yml --tags cilium",)):
    order = []
    keep = {k: getattr(m, k) for k in ("ledger_for", "proof_problems", "merged_live_problems", "host_work", "record",
                                       "ten")}
    m.ledger_for = lambda st, ph, arg=None: ([st], [], {"branches": [], "playbooks": list(playbooks)})
    m.proof_problems = lambda *a, **k: []
    m.merged_live_problems = lambda *a: []
    m.host_work = lambda cmd: order.append("check-mode run") or R(0)
    m.record = lambda *a: order.append("recorded")
    def ten(command, stdin=None, check=True):
        if command.startswith("sudo -n helm repo list"):
            return R(0, json.dumps([{"name": n} for n in listed])) if listed is not None else R(1, "", "sudo: denied")
        order.append(command)
        return R(update_rc, "", "Unable to get an update")
    m.ten = ten
    try:
        m.preview("11-cilium")
        return order
    except SystemExit:
        return order + ["refused"]
    finally:
        for k, v in keep.items():
            setattr(m, k, v)
kubeadm = m.playbook_helm_repos(["setup-kubeadm.yml"])
check("preview: the step's playbook's repositories root has refreshed (one missing is left to the playbook's own "
      "task), failing on a failed download; then the check-mode run, then recorded",
      preview_with([r for r in kubeadm if r != "cnpg"] + ["sealed-secrets"]),
      ["sudo -n helm repo update --fail-on-repo-update-fail " + " ".join(r for r in kubeadm if r != "cnpg"),
       "check-mode run", "recorded"])
check("preview: a refresh that fails refuses before the check-mode run", preview_with(kubeadm, 1)[-1:], ["refused"])
check("preview: root's repositories not read - refused, nothing run", preview_with(None), ["refused"])
check("preview: a step whose playbooks add no repository - no refresh",
      preview_with(kubeadm, playbooks=("restart-mesh-workloads.yml -e istio_version=1.31.1",)),
      ["check-mode run", "recorded"])

# --- critical alerts: production's own, pending or firing; the rules loaded
rule = lambda name, sev="critical", health="ok": {"name": name, "type": "alerting", "health": health,
                                                  "labels": {"severity": sev}}
RULES = {"status": "success", "data": {"groups": [{"rules": [rule("VeleroDown"), rule("X", "warning")]}]}}
alert = lambda name, state, sev="critical", ns="": {"labels": {"alertname": name, "severity": sev,
                                                               **({"namespace": ns} if ns else {})}, "state": state}
ALERTS = lambda *a: {"status": "success", "data": {"alerts": list(a)}}
check("critical alerts pending or firing named; a warning, an inactive one not",
      m.critical_alert_problems(ALERTS(alert("VeleroDown", "pending", ns="velero"), alert("Crash", "firing", "warning"),
                                       alert("Cert", "inactive")), RULES), ["VeleroDown pending velero"])
check("the test environment's and a preview environment's: not production's",
      m.critical_alert_problems(ALERTS(alert("AppDown", "firing", ns="schnappy-test"),
                                       alert("AppDown", "pending", ns="schnappy-pr-12")), RULES), [])
check("no critical rule loaded (an empty answer is no green): a problem",
      m.critical_alert_problems(ALERTS(), {"status": "success", "data": {"groups": []}}),
      ["Prometheus holds no critical alerting rule - its rules not loaded"])
check("a rule that errs: a problem",
      len(m.critical_alert_problems(ALERTS(), {"status": "success", "data": {"groups": [{"rules": [
          rule("A"), rule("B", health="err")]}]}})), 1)
check("an answer that is no success: a problem",
      m.critical_alert_problems({"status": "error"}, RULES), ["Prometheus' alerts not read"])
m.ten = lambda command, **k: R(1, "", "connection refused")
try:
    check("Prometheus not read: a problem, not a pass", m.critical_alert_problems(), ["Prometheus' alerts not read"])
finally:
    m.ten = saved_ten

def settled(answers, wait_s=120):
    answers, now, asked = list(answers), [0.0], []
    keep = m.critical_alert_problems
    m.critical_alert_problems = lambda: asked.append(1) or (answers.pop(0) if len(answers) > 1 else answers[0])
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            got = m.settled_alert_problems(wait_s=wait_s, poll=30, sleep=lambda s: now.__setitem__(0, now[0] + s),
                                           clock=lambda: now[0])
        return got, len(asked)
    finally:
        m.critical_alert_problems = keep
check("none: green at once", settled([[]]), ([], 1))
check("a pending one that ends: followed, then green", settled([["A pending"], ["A pending"], []]), ([], 3))
check("a pending one that fires: red when it fires", settled([["A pending"], ["A firing"]]), (["A firing"], 2))
check("one still pending past the wait: red", settled([["A pending"]])[0], ["A pending"])
check("a firing one: red at once, not waited for", settled([["A firing"]]), (["A firing"], 1))
check("Prometheus not read: red at once", settled([["Prometheus' alerts not read"]]), (["Prometheus' alerts not read"], 1))

# check(): the alerts at the first check and at the deciding one
def check_with(alerts, deciding):
    keep = {k: getattr(m, k) for k in ("read_ledger", "inventory_check", "settled", "running_digest_problems", "ansible",
                                       "settled_alert_problems")}
    m.read_ledger = lambda *a, **k: ({}, [])
    m.inventory_check = lambda *a, **k: True
    m.settled = lambda *a, **k: (True, None, [])
    m.running_digest_problems = lambda *a: []
    m.ansible = lambda *a: True
    m.settled_alert_problems = lambda: list(alerts)
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            return m.check("01-argocd-root-retry", deciding=deciding)
    finally:
        for k, v in keep.items():
            setattr(m, k, v)
check("the deciding check: a critical alert - red", check_with(["VeleroDown pending velero"], True), False)
check("the first check too: a critical alert - red (the soak never starts on one)", check_with(["X firing"], False), False)
check("none: green", check_with([], True), True)
# begin: production's alerts its baseline - a step does not start on one pending or firing
keep = {k: getattr(m, k) for k in ("ledger_for", "proof_problems", "vault_login_problems", "finished_pod_problems", "backup_window_problems",
                                   "settled_alert_problems", "inventory_check", "settled", "record")}
m.ledger_for = lambda st, ph, arg=None: (m.step_names(), [], m.step_info(st))
m.proof_problems = lambda *a, **k: []
m.vault_login_problems = m.finished_pod_problems = m.backup_window_problems = lambda: []
m.settled_alert_problems = lambda: ["ALERT-X pending"]
m.inventory_check = lambda *a, **k: True
m.settled = lambda *a, **k: (True, None, ["app"])
recorded = []
m.record = lambda *a, **k: recorded.append(a)
try:
    m.begin("01-argocd-root-retry")
    got = "begun"
except SystemExit as e:
    got = "refused" if "ALERT-X" in str(e.code) else str(e.code)
finally:
    for k, v in keep.items():
        setattr(m, k, v)
check("begin: refused while a critical alert is pending or firing, nothing recorded", (got, recorded), ("refused", []))

# --- the controller as pushed: ledger_for refuses before claiming; controller_problems' reads
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
def controller(fetch=0, main_blob=None, tests="", dirty="", rc=0):
    calls, keep = [], m.run
    def run(cmd, **k):
        calls.append(cmd[3])
        if cmd[3] == "fetch":
            return R(fetch, "", "fatal: unable to access")
        if cmd[3] == "rev-parse":
            return R(rc, (main_blob or m.LOADED_BLOB) + "\n", "fatal: bad revision" if rc else "")
        return R(rc, tests if cmd[3] == "diff" else dirty)
    m.run = run
    try:
        return m.controller_problems(), calls
    finally:
        m.run = keep
got, calls = controller()
check("the controller as loaded is origin/main's, its tests too: nothing - main fetched first", (got, calls[0]),
      ([], "fetch"))
check("ops main not fetched: refused", len(controller(fetch=1)[0]), 1)
check("the controller running differs from origin/main's: refused", len(controller(main_blob="0" * 40)[0]), 1)
check("the unit tests differ from origin/main (committed, not pushed): refused",
      len(controller(tests="tests/ansible/unit/x/run.sh\n")[0]), 1)
check("the unit tests changed, not committed: refused", len(controller(dirty=" M tests/ansible/unit/x/run.sh\n")[0]), 1)
check("not read: refused", len(controller(rc=128)[0]), 1)
check("the loaded blob is this file's git blob id", m.LOADED_BLOB,
      __import__("subprocess").run(["git", "hash-object", "scripts/upgrade-production.py"], capture_output=True,
                                   text=True).stdout.strip())

# --- a backup-check step's Velero backup: on the full run's terms
def velero(phase="Completed", errors=0, pvbs=("Completed", "Completed"), volumes=2, bsl=("Available",),
           dbr="Processed", phases=None, pods_rc=0):
    sent, bsl, phases = [], list(bsl), list(phases or [phase])
    now = [0.0]
    def ten(command, stdin=None, check=True):
        words = command.split()
        sent.append((words[3] if len(words) > 3 else command, stdin))
        if "backupstoragelocations" in command:
            return R(0, bsl.pop(0) if len(bsl) > 1 else bsl[0])
        if "schedules.velero.io" in command:
            return R(0, json.dumps({"spec": {"template": {"includedNamespaces": ["schnappy-production"],
                                                          "defaultVolumesToFsBackup": True}}}))
        if "get pods -l app.kubernetes.io/component=valkey" in command:
            if pods_rc:
                return R(pods_rc, "", "Unable to connect to the server")
            return R(0, json.dumps({"items": [{"spec": {"volumes": [{"name": f"v{i}", "emptyDir": {}}
                                                                     for i in range(volumes)] + [{"name": "cm",
                                                                     "configMap": {}}]}}]}))
        if "create -f -" in command:
            return R(0)
        if "podvolumebackups" in command:
            return R(0, json.dumps({"items": [{"metadata": {"name": f"p{i}"}, "status": {"phase": ph}}
                                              for i, ph in enumerate(pvbs)]}))
        if "deletebackuprequests" in command:
            return R(0, json.dumps({"status": {"phase": dbr}}))
        if "backups.velero.io" in command:
            ph = phases.pop(0) if len(phases) > 1 else phases[0]
            return R(0, json.dumps({"status": {"phase": ph, "errors": errors}}))
        return R(1, "", "unexpected")
    def sleep(s):
        now[0] += s
        if now[0] > 6000:
            raise RuntimeError("spun")
    def clock():
        now[0] += 0.001
        if now[0] > 7000:
            raise RuntimeError("spun without sleeping")
        return now[0]
    m.ten = ten
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            got = m.velero_backup_check(wait_s=60, poll=15, sleep=sleep, clock=clock)
    except RuntimeError as e:  # its own limit: a wait that never ends fails the test, it does not hang the suite
        got = [str(e)]
    finally:
        m.ten = saved_ten
    created = [json.loads(s) for c, s in sent if c == "create"]
    return got, [o["kind"] for o in created], created, out.getvalue()
got, kinds, created, said = velero()
check("Completed, a Completed pod volume backup for each emptyDir: no problem; the backup, then its delete request",
      (got, kinds), ([], ["Backup", "DeleteBackupRequest"]))
check("  the backup: the daily schedule's template, Valkey's pods only, an hour's ttl, labelled",
      (created[0]["spec"]["includedNamespaces"], created[0]["spec"]["labelSelector"], created[0]["spec"]["ttl"],
       created[0]["metadata"]["labels"]),
      (["schnappy-production"], {"matchLabels": {"app.kubernetes.io/component": "valkey"}}, "1h0m0s",
       {"upgrade-test": "backup-check"}))
check("fewer pod volume backups Completed than the emptyDirs (one skipped): refused",
      len(velero(pvbs=("Completed",))[0]), 1)
check("PartiallyFailed: refused, deleted all the same", (len(velero("PartiallyFailed")[0]), velero("PartiallyFailed")[1]),
      (1, ["Backup", "DeleteBackupRequest"]))
check("Completed with errors: refused", len(velero(errors=2)[0]), 1)
queued = velero(phases=["New"])[0]
check("queued past the wait (still New): refused as not ended, not as ended New",
      (len(queued), queued[0].endswith(" not ended within 60 s (phase New)")), (1, True))
check("the storage location validated late (after a restart): asked again, then on",
      velero(bsl=("", "", "Available"))[0], [])
check("the storage location never Available: refused, nothing created",
      (len(velero(bsl=("Unavailable",))[0]), velero(bsl=("Unavailable",))[1]), (1, []))
check("no Valkey volume to back up: refused, nothing created", (len(velero(volumes=0)[0]), velero(volumes=0)[1]), (1, []))
# Valkey's pods unread is said so - not "no Valkey volume" (none running is another fault, and its fix another)
check("Valkey's pods not read: refused as unread, the namespace named, nothing created",
      velero(pods_rc=1)[:2], (["Valkey's pods in schnappy-production not read"], []))
check("its delete refused (the backup still running): said, the ttl named", "not deleted" in velero(dbr="InProgress")[3],
      True)
check("the backup-check flag read: steps 10, 25, 43",
      sorted(s for s in m.step_names() if m.step_info(s)["velero_backup"]), ["10-velero", "25-versitygw", "43-kubernetes-1.36"])
# ===== the test audit of 2026-10-13 (round 2): its survivors, each check failing against its mutant (measured) =====
import ast, hashlib, os, subprocess, tempfile, yaml
# F8: controller_problems on a real git repo with a real origin (no stubbed git)
W = tempfile.mkdtemp()
env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
g = lambda *a, cwd=None: subprocess.run(["git", *a], cwd=cwd or W + "/ops", capture_output=True, text=True, env=env)
blob = lambda path: hashlib.sha1(b"blob %d\0" % len(open(path, "rb").read()) + open(path, "rb").read()).hexdigest()
subprocess.run(["git", "init", "-q", "--bare", "-b", "main", W + "/origin.git"], check=True)
os.makedirs(W + "/ops/scripts")
os.makedirs(W + "/ops/tests/ansible/unit/t")
open(W + "/ops/scripts/upgrade-production.py", "w").write("# controller\n")
open(W + "/ops/tests/ansible/unit/t/run.sh", "w").write("# t\n")
open(W + "/ops/README", "w").write("x\n")
g("init", "-q", "-b", "main"); g("add", "-A"); g("commit", "-qm", "c")
g("remote", "add", "origin", W + "/origin.git"); g("push", "-q", "origin", "main"); g("fetch", "-q", "origin")
keep = (m.OPS, m.LOADED_BLOB)
m.OPS, m.LOADED_BLOB = W + "/ops", blob(W + "/ops/scripts/upgrade-production.py")
try:
    check("F8 as pushed: nothing", m.controller_problems(), [])
    open(W + "/ops/README", "a").write("y\n")
    check("F8 another path edited: nothing", m.controller_problems(), [])
    g("checkout", "-q", "--", "README")
    for path, how in (("tests/ansible/unit/t/run.sh", "edited"), ("tests/ansible/unit/new/run.sh", "untracked")):
        os.makedirs(os.path.dirname(W + "/ops/" + path), exist_ok=True)
        open(W + "/ops/" + path, "a").write("# more\n")
        check(f"F8 {path} {how}: refused", len(m.controller_problems()), 1)
        g("add", "-A"); g("commit", "-qm", "local")
        check(f"F8 {path} committed, not pushed: refused", len(m.controller_problems()), 1)
        g("push", "-q", "origin", "main")
        check(f"F8 {path} pushed: nothing", m.controller_problems(), [])
    # another clone pushes a controller fix: this one's loaded controller is no longer main's - fetched, refused
    subprocess.run(["git", "clone", "-q", W + "/origin.git", W + "/other"], check=True, capture_output=True)
    open(W + "/other/scripts/upgrade-production.py", "a").write("# fixed elsewhere\n")
    g("commit", "-qam", "fix", cwd=W + "/other"); g("push", "-q", "origin", "main", cwd=W + "/other")
    check("F8 a controller fix pushed from another clone: the one loaded here refused (main fetched first)",
          len(m.controller_problems()), 1)
    g("pull", "-q", "origin", "main")
    m.LOADED_BLOB = blob(W + "/ops/scripts/upgrade-production.py")
    check("F8 pulled and loaded again: nothing", m.controller_problems(), [])
finally:
    m.OPS, m.LOADED_BLOB = keep

# F11: done() of a backup-check step runs the Velero backup at its first call - asked first, recorded, not again
def done_velero(problems=(), recorded_already=False):
    calls, keep = [], {k: getattr(m, k) for k in ("ledger_for", "proof_problems", "merged_live_problems", "soak_state",
                                                  "ten_clock", "confirm", "velero_backup_check", "record", "check",
                                                  "ten_now", "checked_since")}
    events = [(None, "10-velero", "velero-backup", [])] if recorded_already else []
    m.ledger_for = lambda st, ph, arg=None: (m.step_names(), events, m.step_info(st))
    m.proof_problems = lambda *a, **k: []
    m.merged_live_problems = lambda *a: []
    m.soak_state = lambda *a: (None, 0)
    m.ten_clock = m.ten_now = lambda: "2026-10-13T00:00:00Z"
    m.checked_since = lambda *a: None
    m.confirm = lambda q: calls.append(("asked", "Velero backup" in q)) or True
    m.velero_backup_check = lambda: calls.append(("velero",)) or list(problems)
    m.record = lambda st, e, *a, **k: calls.append(("record", e))
    m.check = lambda *a, **k: True
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            m.done("10-velero")
        return calls
    except SystemExit:
        return calls + [("refused",)]
    finally:
        for k, v in keep.items():
            setattr(m, k, v)
check("F11 a backup-check step's first done: asked (naming the Velero backup), backed up, recorded, then checked",
      done_velero(), [("asked", True), ("velero",), ("record", "velero-backup"), ("record", "checked")])
check("F11 the backup red: refused, not recorded", done_velero(["BAD"]), [("asked", True), ("velero",), ("refused",)])
check("F11 recorded already (a red check since): not asked, not backed up again", done_velero(recorded_already=True),
      [("record", "checked")])

# F9, F10, F12: the backup's wait sleeps and ends at its bound; the pod volume backups read are this backup's; the
# delete request names it
def velero_spy(phase="InProgress"):
    sent, sleeps, now = [], [], [0.0]
    def ten(command, stdin=None, check=True):
        sent.append((command, stdin))
        if "backupstoragelocations" in command:
            return R(0, "Available")
        if "schedules.velero.io" in command:
            return R(0, json.dumps({"spec": {"template": {"includedNamespaces": ["p"]}}}))
        if "get pods -l app.kubernetes.io/component=valkey" in command:
            return R(0, json.dumps({"items": [{"spec": {"volumes": [{"name": "v", "emptyDir": {}}]}}]}))
        if "create -f -" in command or "deletebackuprequests" in command:
            return R(0, json.dumps({"status": {"phase": "Processed"}}))
        if "podvolumebackups" in command:
            return R(0, json.dumps({"items": [{"status": {"phase": "Completed"}}]}))
        if "backups.velero.io" in command:
            return R(0, json.dumps({"status": {"phase": phase}}))
        return R(1, "", "unexpected")
    def sleep(s):
        sleeps.append(s); now[0] += s
        if now[0] > 6000:
            raise RuntimeError("spun")
    def clock():
        now[0] += 0.001
        if now[0] > 7000:
            raise RuntimeError("spun without sleeping")
        return now[0]
    m.ten = ten
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            got = m.velero_backup_check(wait_s=60, poll=10, sleep=sleep, clock=clock)
    except RuntimeError as e:
        got = str(e)
    finally:
        m.ten = saved_ten
    return got, sleeps, sent
got, sleeps, _ = velero_spy()
check("F9 a backup never ending: refused at the bound, one sleep of poll per read", (len(got), sleeps.count(10) >= 5),
      (1, True))
got, _, sent = velero_spy("Completed")
name = json.loads([s for c, s in sent if "create -f -" in c][0])["metadata"]["name"]
check("F10 the pod volume backups read are this backup's", any(f"velero.io/backup-name={name}" in c and
                                                               "podvolumebackups" in c for c, _ in sent), True)
check("F12 the delete request names the backup it made",
      [json.loads(s)["spec"]["backupName"] for c, s in sent if s and '"DeleteBackupRequest"' in s], [name])

# F17, F20: answers with no JSON are problems, not "nothing"
m.ten = lambda command, **k: R(0, "<html>proxy</html>")
try:
    check("F17 production's pods answered with no JSON: a problem", len(m.finished_pod_problems()), 1)
    check("F20 Prometheus answered with no JSON: a problem", m.critical_alert_problems(), ["Prometheus' alerts not read"])
finally:
    m.ten = saved_ten
# F19: the namespaces finished_job_hints leaves out are read (excluded_namespaces) when not given
keep_ex = m.excluded_namespaces
m.excluded_namespaces = lambda: "x"
try:
    check("F19 the namespaces left out read when not given",
          m.finished_job_hints(["image docker.io/velero/velero v1.18.0"], jobs), [])
finally:
    m.excluded_namespaces = keep_ex
# F21: the alerts read where production-data-check.yml reads them (its proxy, Prometheus' service and port)
pdc = yaml.safe_load(open("deploy/ansible/playbooks/production-data-check.yml"))[0]["vars"]["proxy"]
check("F21 Prometheus' API through the service proxy production-data-check.yml uses",
      m.PROMETHEUS_API, pdc + "/schnappy-prometheus:9090/proxy/api/v1")

# F4: each rules value the controller's, assigned once there (a controller-local value shadows nothing unseen)
rules_src = open("scripts/upgrade-rules.py").read()
names = [n.targets[0].id for n in ast.parse(rules_src).body if isinstance(n, ast.Assign) and
         isinstance(n.targets[0], ast.Name)] + [e.id for n in ast.parse(rules_src).body if isinstance(n, ast.Assign) and
         isinstance(n.targets[0], ast.Tuple) for e in n.targets[0].elts]
ctrl = ast.parse(open("scripts/upgrade-production.py").read())
assigned = [t.id for n in ctrl.body if isinstance(n, ast.Assign) for tt in n.targets
            for t in (tt.elts if isinstance(tt, ast.Tuple) else [tt]) if isinstance(t, ast.Name)]
check("F4 every rules value is the controller's, assigned there once (from rules)",
      {n: (getattr(m, n) == getattr(m.rules, n), assigned.count(n)) for n in names},
      {n: (True, 1) for n in names})
# F5: the rules file among the proven paths' files
listed = subprocess.run(["git", "ls-files", "--", *m.PROVEN_PATHS], capture_output=True, text=True).stdout.split()
check("F5 scripts/upgrade-rules.py is proven", "scripts/upgrade-rules.py" in listed, True)
# F23: a check's settle can hold green: its window longer than the quiet time and the stable polls together
check("F23 CHECK_MINUTES outlasts SETTLE_QUIET and SETTLE_STABLE polls",
      m.CHECK_MINUTES * 60 > m.SETTLE_QUIET + m.SETTLE_STABLE * m.SETTLE_POLL, True)
# F6: the playbooks' repositories read independently (a plain YAML walk counting the tasks), the names pinned
count = sum(open(os.path.join(r, f)).read().count("kubernetes.core.helm_repository:")
            for r, _, fs in os.walk("deploy/ansible/playbooks") for f in fs if f.endswith(".yml"))
check("F6 every helm_repository task's name read (as many names as tasks, less the two Istio ones that share one)",
      (len(repos) + 1, count), (count, count))
check("F6 setup-kubeadm.yml's repositories, pinned",
      m.playbook_helm_repos(["setup-kubeadm.yml"]),
      ["cilium", "cnpg", "external-secrets", "istio", "jetstack", "metrics-server", "prometheus-community",
       "scylla-operator", "strimzi"])
print("runner-checks: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_RC
