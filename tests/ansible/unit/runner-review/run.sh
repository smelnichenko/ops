#!/bin/bash
# scripts/upgrade-production.py and tests/ansible/unit/defaults_baseline.py: the mechanisms the review of 2026-10-13
# (its test audit: each mutant measured) found no test bit - ci_quiet_read's wait, re-reads and refusals, helper_state's
# read, finished_job_hints' Job shapes, finished_pod_problems' reads and namespaces, a record out of order, a step's soak
# line. Each check below fails against the mutant named by its id.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY_AUDIT'
import contextlib, importlib.machinery, importlib.util, io, json, os, shutil, sys, tempfile
L = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
# the namespaces the inventory leaves out are read from ten (open preview environments): none here
m.excluded_namespaces = lambda: m.TEST_NAMESPACES
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


R = lambda rc, out="", err="": type("R", (), {"returncode": rc, "stdout": out, "stderr": err})()
pod = lambda n: {"kind": "Pod", "metadata": {"name": n}, "status": {"phase": "Running"}}
event = lambda n, at, count=1, field="lastTimestamp": {"kind": "Event", "apiVersion": "v1", "involvedObject": {"name": n}, field: at,
                                                       "count": count, "metadata": {"name": f"{n}.{at}"}}


class Spin(Exception):
    pass


def quiet(states, wait_s=60, tries=5):
    """states: a list (each read in turn, the last repeating) or a callable(n) -> items|None"""
    log, now, reads = [], [0.0], []
    def ten(command, stdin=None, check=True):
        log.append(command)
        if callable(states):
            s = states(len(log))
        else:
            s = states[min(len(log) - 1, len(states) - 1)]
        return R(0, json.dumps({"items": s})) if s is not None else R(1, "", "connection refused")
    def sleep(s):
        if now[0] > 10 * wait_s:  # the test's own bound: a wait with no end is a FAIL, not a hang
            raise Spin()
        now[0] += s
    saved, m.ten = m.ten, ten
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            out = m.ci_quiet_read(lambda: reads.append(len(log)) or "INVENTORY", tries=tries, wait_s=wait_s, poll=5,
                                  sleep=sleep, clock=lambda: now[0])
        return out, len(reads)
    except SystemExit as e:
        return "refused: " + str(e.code)[:40], len(reads)
    except Spin:
        return "SPUN past 10x the wait", len(reads)
    finally:
        m.ten = saved


old = event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z")
# R2: the read happens only after the helper ended - the helper read that saw none comes first
order_seen = []
_q = quiet
def quiet_reads(states):
    global order_seen
    return _q(states)
reads_at = []
def ten_r2(n):
    return [[pod("helper-pod-create-pvc-b"), old], [old], [old], [old]][min(n - 1, 3)]
log_reads = []
saved_ci = m.ci_quiet_read
def spy(read, **k):
    return saved_ci(lambda: log_reads.append(len(calls)) or read(), **k)
calls = []
def ten_spy(command, stdin=None, check=True):
    calls.append(command)
    return R(0, json.dumps({"items": ten_r2(len(calls))}))
saved_ten, m.ten = m.ten, ten_spy
try:
    with contextlib.redirect_stdout(io.StringIO()):
        spy(lambda: "INVENTORY", wait_s=60, poll=5, sleep=lambda s: None, clock=lambda: 0.0)
finally:
    m.ten = saved_ten
check("R2 a helper running: the inventory read only after a helper read that saw none (the 2nd)", log_reads, [2])
# Q07: the provisioner's own pod always runs in local-path-storage - it is no helper
prov = pod("local-path-provisioner-6f9d7c8b5-x2k4q")
check("Q07 the provisioner's own pod running: not a helper - read once", quiet([[prov, old], [prov, old]]),
      ("INVENTORY", 1))
# Q09: a helper started during the read, its events not yet in: running at the second look - read again
check("Q09 a helper running when the read ends (no event yet): read again",
      quiet([[old], [pod("helper-pod-create-pvc-d"), old], [old], [old]]), ("INVENTORY", 2))
# Q05: the second look not answered: no quiet proven - refused
check("Q05 the helpers not read after the inventory: refused", quiet([[old], None])[0][:8], "refused:")
# Q06: a helper during every read: refused after `tries`, never a dirty inventory returned
check("Q06 a helper during every read: refused after 5 reads",
      quiet(lambda n: [old] + [event(f"helper-pod-create-pvc-{k}", "2026-10-13T15:20:01Z") for k in range(n // 2)]),
      ("refused: REFUSED: a CI helper pod ran during each", 5))
# Q03: the same helper name again (a retried PVC op), count 1 again, a later time: read again
check("Q03 the same helper's event at a later time (count unchanged): read again",
      quiet([[old], [old, event("helper-pod-delete-pvc-a", "2026-10-13T15:30:00Z")],
             [old, event("helper-pod-delete-pvc-a", "2026-10-13T15:30:00Z")]]), ("INVENTORY", 2))
# Q02: events.k8s.io-style events carry eventTime, no lastTimestamp
eold = event("helper-pod-delete-pvc-a", "2026-10-13T15:16:43.000000Z", field="eventTime")
check("Q02 an eventTime-only event, the same helper again later: read again",
      quiet([[eold], [eold, event("helper-pod-delete-pvc-a", "2026-10-13T15:30:00.000000Z", field="eventTime")],
             [eold, event("helper-pod-delete-pvc-a", "2026-10-13T15:30:00.000000Z", field="eventTime")]]),
      ("INVENTORY", 2))
# Q10: the deadline itself (the test bounded, not spinning)
check("Q10 helpers running for ever: refused at the wait, named so",
      quiet([[pod("helper-pod-create-pvc-b")]], tries=1)[0].startswith("refused: REFUSED: CI's helper pods still"), True)
# Q12: what is read - ten answers only what the command asks for
def kinds_ten(items):
    def ten(command, stdin=None, check=True):
        if "-n local-path-storage" not in command:
            return R(0, json.dumps({"items": []}))
        ask = command.split(" get ")[1].split()[0].split(",")
        return R(0, json.dumps({"items": [o for o in items if o["kind"].lower() + "s" in ask]}))
    return ten
saved, m.ten = m.ten, kinds_ten([pod("helper-pod-create-pvc-b"), old])
try:
    st = m.helper_state()
finally:
    m.ten = saved
check("Q12 helper_state reads local-path-storage's pods and events", st,
      (["helper-pod-create-pvc-b"], {("helper-pod-delete-pvc-a", "2026-10-13T15:16:43Z", 1)}))
# Q13: inventory_check reads ten's inventory through ci_quiet_read: helpers unreadable -> refused, no inventory read
keep = {k: getattr(m, k) for k in ("ten", "remote", "run", "WORK")}
inv_reads = []
def ten13(command, stdin=None, check=True):
    if "local-path-storage" in command:
        return R(1, "", "connection refused")
    if "INVENTORY_EXCLUDE_NAMESPACES" in command:
        inv_reads.append(command)
    return R(0, "")
m.ten, m.remote, m.run, m.WORK = ten13, (lambda *a, **k: R(0, "")), (lambda cmd, **k: R(0)), tempfile.mkdtemp()
try:
    with contextlib.redirect_stdout(io.StringIO()):
        got = m.inventory_check([])
except SystemExit as e:
    got = "refused"
finally:
    for k, v in keep.items():
        setattr(m, k, v)
check("Q13 inventory_check: the helpers unreadable - refused, ten's inventory never read", (got, inv_reads),
      ("refused", []))

# finished_job_hints
job = lambda ns, n, image, conds=(), init=None: {"kind": "Job", "metadata": {"namespace": ns, "name": n},
    "spec": {"template": {"spec": {"containers": [{"image": "x/app:1"}] if init else [{"image": image}],
                                   **({"initContainers": [{"image": init}]} if init else {})}}},
    "status": {"conditions": [{"type": t, "status": s} for t, s in conds]}}
V = "image docker.io/velero/velero v1.18.0"
check("J04 the image in an initContainer: named",
      m.finished_job_hints([V], {"items": [job("velero", "j", None, [("Complete", "True")],
                                               init="docker.io/velero/velero:v1.18.0")]}),
      ["velero/j (Complete) still carries image docker.io/velero/velero v1.18.0 - kubectl delete job -n velero j"])
check("J06 Kubernetes 1.31+'s finished shape (SuccessCriteriaMet before Complete): named Complete",
      m.finished_job_hints([V], {"items": [job("velero", "j", "docker.io/velero/velero:v1.18.0",
                                               [("SuccessCriteriaMet", "True"), ("Complete", "True")])]}),
      ["velero/j (Complete) still carries image docker.io/velero/velero v1.18.0 - kubectl delete job -n velero j"])
check("J06 a suspended Job: not finished, no hint",
      m.finished_job_hints([V], {"items": [job("velero", "j", "docker.io/velero/velero:v1.18.0",
                                               [("Suspended", "True")])]}), [])
check("J05 a Failed condition not True: not finished, no hint",
      m.finished_job_hints([V], {"items": [job("velero", "j", "docker.io/velero/velero:v1.18.0",
                                               [("Failed", "False")])]}), [])
saved, m.ten = m.ten, (lambda *a, **k: R(1, "", "the API server unreachable"))
try:
    check("J09 the Jobs not read: said so, not silence", m.finished_job_hints([V]),
          ["the Jobs not read: the API server unreachable"])
    check("J07 no extra image: no read of ten at all", m.finished_job_hints([]), [])
finally:
    m.ten = saved
# J08: inventory_check red with an extra image a finished Job carries: the hint printed
keep = {k: getattr(m, k) for k in ("ten", "remote", "run", "WORK")}
def ten08(command, stdin=None, check=True):
    if command.startswith("kubectl get namespaces"):
        return R(0, "namespace/velero\n")
    if "local-path-storage" in command:
        return R(0, json.dumps({"items": []}))
    if command.startswith("kubectl get jobs"):
        return R(0, json.dumps({"items": [job("velero", "maint-1", "docker.io/velero/velero:v0.9.9",
                                              [("Complete", "True")])]}))
    if "INVENTORY_EXCLUDE_NAMESPACES" in command:
        return R(0, "image docker.io/velero/velero v0.9.9\n")
    return R(0, "")
m.ten, m.remote, m.WORK = ten08, (lambda *a, **k: R(0, "")), tempfile.mkdtemp()
m.run = lambda cmd, **k: R(1 if cmd[0].endswith("inventory-diff.sh") else 0)
buf = io.StringIO()
try:
    with contextlib.redirect_stdout(buf):
        red = m.inventory_check([])
finally:
    for k, v in keep.items():
        setattr(m, k, v)
check("J08 inventory red, the extra image a finished Job's: the hint printed, the check still red",
      (red, [l for l in buf.getvalue().splitlines() if l.startswith("FINISHED JOB:")]),
      (False, ["FINISHED JOB: velero/maint-1 (Complete) still carries image docker.io/velero/velero v0.9.9 - "
               "kubectl delete job -n velero maint-1"]))

# finished_pod_problems
def owned(kind, name):
    return [{"kind": kind, "name": name, "controller": True}]
deploy = lambda ns, n, s: {"kind": "Deployment", "metadata": {"namespace": ns, "name": n}, "spec": {"strategy": {"type": s}}}
rs = lambda ns, n, d: {"kind": "ReplicaSet", "metadata": {"namespace": ns, "name": n, "ownerReferences": owned("Deployment", d)}}
rpod = lambda ns, n, o, ph: {"kind": "Pod", "metadata": {"namespace": ns, "name": n, "ownerReferences": owned("ReplicaSet", o)},
                             "status": {"phase": ph}}
check("L06 the same ReplicaSet name in two namespaces: a pod is matched to its own namespace's only",
      m.finished_pod_problems({"items": [deploy("schnappy-production", "api", "Recreate"),
                                         rs("schnappy-production", "api-7c9", "api"),
                                         rpod("schnappy-test", "api-7c9-a", "api-7c9", "Succeeded")]}), [])
saved, m.ten = m.ten, (lambda *a, **k: R(1, "", "the API server unreachable"))
try:
    got = m.finished_pod_problems()
finally:
    m.ten = saved
check("L07 production's Deployments not read: a problem (begin refuses), not silence", len(got), 1)
cl = [deploy("velero", "velero", "Recreate"), rs("velero", "velero-865", "velero"),
      rpod("velero", "velero-865-dr2jg", "velero-865", "Succeeded")]
def kinds_all(command, stdin=None, check=True):
    ask = command.split(" get ")[1].split()[0].split(",")
    plural = {"Deployment": "deployments", "ReplicaSet": "replicasets", "Pod": "pods"}
    return R(0, json.dumps({"items": [o for o in cl if plural[o["kind"]] in ask]}))
saved, m.ten = m.ten, kinds_all
try:
    got = m.finished_pod_problems()
finally:
    m.ten = saved
check("L08 read from ten (what it asks for): the leftover found", len(got), 1)

# defaults_baseline: a record out of order is no baseline
hl = importlib.machinery.SourceFileLoader("defaults_baseline", "tests/ansible/unit/defaults_baseline.py")
helper = importlib.util.module_from_spec(importlib.util.spec_from_loader("defaults_baseline", hl))
hl.exec_module(helper)
d = m.dflt
tree = lambda p: open(p).read()
rec = [l.strip() for l in tree(d.COMMITTED).split("\n") if l.strip() and not l.startswith("#")]
i7, i8 = rec.index("07-gateway-api"), rec.index("08-istio-1.30")
swapped = rec[:]
swapped[i7], swapped[i8] = swapped[i8], swapped[i7]
bad = lambda p: "# committed steps\n" + "\n".join(swapped) + "\n" if p == d.COMMITTED else tree(p)
try:
    helper.baseline(d, bad)
    check("B3 a record out of step order: no baseline", "baseline", "refused")
except ValueError as e:
    check("B3 a record out of step order: no baseline", "not the first steps with default lines" in str(e), True)

# one image parse, the inventory's: a digest dropped, a registry's port no tag
check("I01 image references read as the inventory reads them",
      [m.image_name_tag(r) for r in ("busybox", "docker.io/velero/velero:v1.18.0@sha256:ab", "registry.local:5000/busybox",
                                     "registry.local:5000/busybox:1.37")],
      [("busybox", "latest"), ("docker.io/velero/velero", "v1.18.0"), ("registry.local:5000/busybox", "latest"),
       ("registry.local:5000/busybox", "1.37")])

# step_info: a step's soak line wins over SOAK_MINUTES
tmp = tempfile.mkdtemp()
for f in os.listdir(m.inv.STEPS):
    shutil.copy(os.path.join(m.inv.STEPS, f), tmp)
with open(os.path.join(tmp, "01-argocd-root-retry.txt"), "a") as f:
    f.write("soak 30\n")
saved = m.inv.STEPS, d.STEPS
m.inv.STEPS = d.STEPS = tmp
try:
    check("S1 a step's soak line: its soak, not SOAK_MINUTES", m.step_info("01-argocd-root-retry")["soak"], 30)
finally:
    m.inv.STEPS, d.STEPS = saved
print("runner-review: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_AUDIT
