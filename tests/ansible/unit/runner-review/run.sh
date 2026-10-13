#!/bin/bash
# scripts/upgrade-production.py and tests/ansible/unit/defaults_baseline.py: the mechanisms the review of 2026-10-13
# (its test audit: each mutant measured) found no test bit - finished_job_hints' Job shapes, finished_pod_problems' reads
# and namespaces, a record out of order, a step's soak line, the image parse. Each check below fails against the mutant
# named by its id.
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
