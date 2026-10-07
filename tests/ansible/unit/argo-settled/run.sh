#!/bin/bash
# tests/ansible/upgrade/files/argo-settled.py on saved apps and pods (its --apps-json/--pods-json mode): green on a
# settled set; the app floor (--expect-apps: a missing or an unexpected app is not green, an allowed extra is); an app
# compared against an older spec is not green, one whose spec only gained fields Go's omitempty drops is (false, 0,
# a map left empty); the restart history (--restart-history: a pod restarting in two steps running fails, one step's
# restart does not, the first call only records); preview environments' apps and pods left out; every gate; the
# playbook's check of the mode the script reports (restarts expected or judged) against the mode it asked for.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "argo-settled: no python3 with ansible and yaml (PATH, repo venv)"; exit 2; }
"$PY" - <<'PY'
import json
import os
import subprocess
import sys
import tempfile

S = "tests/ansible/upgrade/files/argo-settled.py"
NOW = "2026-10-06T12:00:00Z"
fails = 0
work = tempfile.mkdtemp()


def app(name):
    src = {"repoURL": "https://git.pmon.dev/schnappy/infra.git", "path": name, "targetRevision": "main"}
    return {"metadata": {"name": name}, "spec": {"source": src},
            "status": {"sync": {"status": "Synced", "comparedTo": {"source": dict(src)}, "revision": "abc"},
                       "health": {"status": "Healthy"}, "operationState": {"phase": "Succeeded"}}}


def pod(name, uid, restarts=0, finished="2026-10-06T10:00:00Z", ns="ns", ready=True):
    c = {"ready": ready, "restartCount": restarts}
    if restarts:
        c["lastState"] = {"terminated": {"finishedAt": finished}}
    return {"metadata": {"namespace": ns, "name": name, "uid": uid},
            "status": {"phase": "Running", "containerStatuses": [c]}}


def run(apps, pods, *args, env=None):
    fa, fp = os.path.join(work, "apps.json"), os.path.join(work, "pods.json")
    json.dump({"items": apps}, open(fa, "w"))
    json.dump({"items": pods}, open(fp, "w"))
    r = subprocess.run([sys.executable, S, "--apps-json", fa, "--pods-json", fp, "--now", NOW, *args],
                       capture_output=True, text=True, env={**os.environ, "MIRROR_REVISIONS": "", **(env or {})})
    return r.returncode, r.stdout + r.stderr


def check(name, got, want, out=""):
    global fails
    ok = got == want
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": got {got}, want {want}\n{out}"))


A = [app("a"), app("b")]
P = [pod("p1", "u1"), pod("p2", "u2")]
rc, out = run(A, P)
check("a settled set is green", rc, 0, out)
rc, out = run(A, P, "--expect-apps", "a,b")
check("the expected apps, exactly: green", rc, 0, out)
rc, out = run([app("a")], P, "--expect-apps", "a,b")
check("an expected app missing: not green", (rc, "app b: missing" in out), (1, True), out)
rc, out = run(A + [app("c")], P, "--expect-apps", "a,b")
check("an unexpected app: not green", (rc, "app c: not expected" in out), (1, True), out)
rc, out = run(A + [app("pr-7-monitor")], P, "--expect-apps", "a,b", "--allow-extra-apps", "^pr-[0-9]+-")
check("an extra app the pattern allows: green", rc, 0, out)
# a preview environment comes and goes with its pull request: its app's state and its pods are not production's
starting = app("pr-7-monitor")
starting["status"]["health"]["status"] = "Progressing"
rc, out = run(A + [starting], P, "--expect-apps", "a,b", "--allow-extra-apps", "^pr-[0-9]+-")
check("an extra app the pattern allows, still progressing: green", rc, 0, out)
rc, out = run([app("a"), starting], P, "--expect-apps", "a,b", "--allow-extra-apps", "^pr-[0-9]+-")
check("an expected app missing beside an allowed extra: not green", (rc, "app b: missing" in out), (1, True), out)
PR = "^schnappy-pr-[0-9]+$"
rc, out = run(A, P + [pod("pr-api", "u9", ns="schnappy-pr-7", ready=False)], "--ignore-namespaces", PR)
check("a preview environment's pod not ready, its namespace ignored: green", rc, 0, out)
rc, out = run(A, P + [pod("pr-api", "u9", ns="schnappy-pr-7", ready=False)])
check("the same pod, no namespace ignored: not green", rc, 1, out)
rc, out = run(A, P + [pod("api", "u9", ns="schnappy-production", ready=False)], "--ignore-namespaces", PR)
check("production's pod not ready, the preview namespaces ignored: not green", rc, 1, out)
open(os.path.join(work, "apps.txt"), "w").write("a\nb\n")
rc, out = run([app("a")], P, "--expect-apps", "@" + os.path.join(work, "apps.txt"))
check("the expected apps from a file, one missing: not green", rc, 1, out)
rc, out = run(A, P, "--print-apps")
check("--print-apps names them", out.strip().splitlines()[-1], "APPS a,b", out)

# the spec Argo CD 3.5 keeps carries empty fields its comparedTo leaves out (directory.jsonnet: {}) - the same spec
fresh = app("a")
fresh["spec"]["source"] = dict(fresh["spec"]["source"], directory={"recurse": True, "jsonnet": {}})
fresh["status"]["sync"]["comparedTo"]["source"] = dict(fresh["status"]["sync"]["comparedTo"]["source"],
                                                       directory={"recurse": True})
rc, out = run([fresh, app("b")], P)
check("a spec with an empty field comparedTo omits: green", rc, 0, out)
stale = app("a")
stale["status"]["sync"]["comparedTo"]["source"] = dict(stale["status"]["sync"]["comparedTo"]["source"], path="old")
rc, out = run([stale, app("b")], P)
check("compared against an older spec (another path): not green", (rc, "compared against an older spec" in out),
      (1, True), out)
emptied = app("a")
emptied["status"]["sync"]["comparedTo"]["source"] = dict(emptied["status"]["sync"]["comparedTo"]["source"],
                                                         directory={"recurse": True})
rc, out = run([emptied, app("b")], P)
check("compared against an older spec with a field the spec dropped: not green",
      (rc, "compared against an older spec" in out), (1, True), out)
# Go's omitempty drops false, 0 and a map left empty once its own empty fields are gone; a true is kept
for name, extra, want in (("a map emptied by its own empty field (directory: {jsonnet: {}})",
                           {"directory": {"jsonnet": {}}}, 0),
                          ("recurse: false", {"directory": {"recurse": False}}, 0),
                          ("a 0", {"limit": 0}, 0),
                          ("recurse: true, which comparedTo has not", {"directory": {"recurse": True}}, 1)):
    x = app("a")
    x["spec"]["source"] = dict(x["spec"]["source"], **extra)
    rc, out = run([x, app("b")], P)
    check(f"spec with {name}, comparedTo without it: {'green' if want == 0 else 'not green'}", rc, want, out)

# every gate, red when it should be and green beside it
import copy
def with_(a, path, value):
    a = copy.deepcopy(a)
    d = a
    for k in path[:-1]:
        d = d.setdefault(k, {})
    d[path[-1]] = value
    return a
def gate(name, apps, pods, want_rc, word="", *args, env=None):
    rc, out = run(apps, pods, *args, env=env)
    check(name, (rc, word in out), (want_rc, True), out)
B = app("b")
gate("an app OutOfSync: not green", [with_(app("a"), ["status", "sync", "status"], "OutOfSync"), B], P, 1, "sync=OutOfSync")
gate("the same app allowed out of sync: green", [with_(app("a"), ["status", "sync", "status"], "OutOfSync"), B], P, 0,
     "", "--allow-out-of-sync", "a")
gate("an app Degraded: not green", [with_(app("a"), ["status", "health", "status"], "Degraded"), B], P, 1, "health=Degraded")
gate("an operation Running: not green", [with_(app("a"), ["status", "operationState", "phase"], "Running"), B], P, 1,
     "operation Running")
gate("the last sync Failed: not green, its message shown",
     [with_(with_(app("a"), ["status", "operationState", "phase"], "Failed"), ["status", "operationState", "message"],
            "hook failed"), B], P, 1, "last sync Failed: hook failed")
gate("a null operationState and message: read, not a crash",
     [with_(app("a"), ["status", "operationState"], None), B], P, 0)
gate("a failed sync with a null message: not green, no crash",
     [with_(with_(app("a"), ["status", "operationState", "phase"], "Failed"), ["status", "operationState", "message"],
            None), B], P, 1, "last sync Failed")
MR = {"https://git.pmon.dev/schnappy/infra.git": "abc"}
gate("on the pushed commit: green", A, P, 0, "", env={"MIRROR_REVISIONS": json.dumps(MR)})
gate("on another commit: not green", A, P, 1, "not on the pushed commit",
     env={"MIRROR_REVISIONS": json.dumps({"https://git.pmon.dev/schnappy/infra.git": "def"})})
# a multi-source app (production's: platform's chart, infra's values as a ref source) - each source's revision
# against its repo's pushed commit: infra's values stale while the chart is current is not on the pushed commit
def multi(platform_rev, infra_rev):
    srcs = [{"repoURL": "https://git.pmon.dev/schnappy/platform.git", "path": "charts/x", "targetRevision": "main"},
            {"repoURL": "https://git.pmon.dev/schnappy/infra.git", "targetRevision": "main", "ref": "values"}]
    m = with_(with_(app("m"), ["spec"], {"sources": srcs}), ["status", "sync", "comparedTo"], {"sources": srcs})
    return with_(m, ["status", "sync", "revisions"], [platform_rev, infra_rev])
MR2 = {"https://git.pmon.dev/schnappy/platform.git": "p1", "https://git.pmon.dev/schnappy/infra.git": "i1"}
gate("multi-source, both sources on their pushed commits: green", [multi("p1", "i1")], P, 0, "",
     env={"MIRROR_REVISIONS": json.dumps(MR2)})
gate("multi-source, infra's values on an older commit: not green", [multi("p1", "i0")], P, 1,
     "not on the pushed commit", env={"MIRROR_REVISIONS": json.dumps(MR2)})
vo = with_(app("a"), ["spec", "source", "helm"], {"valuesObject": {"enabled": False}})
vo = with_(vo, ["status", "sync", "comparedTo", "source", "helm"], {"valuesObject": {}})
gate("helm valuesObject false against none: an older spec (values are data, not omitted fields)", [vo, B], P, 1,
     "compared against an older spec")
gate("no app at all: not green", [], P, 1)
gate("no pod at all: not green", A, [], 1)
pending = pod("p1", "u1"); pending["status"] = {"phase": "Pending", "containerStatuses": []}
gate("a Pending pod: not green", A, [pending, pod("p2", "u2")], 1, "ns/p1 (Pending)")
notready = pod("p1", "u1"); notready["status"]["containerStatuses"][0]["ready"] = False
gate("a Running pod with a container not ready: not green", A, [notready, pod("p2", "u2")], 1, "ns/p1")
gate("a restart 60 s before now, quiet 300: not green", A, [pod("p1", "u1", 1, "2026-10-06T11:59:00Z")], 1,
     "restarted 60 s ago", "--restart-quiet", "300")
gate("a restart 400 s before now, quiet 300: green", A, [pod("p1", "u1", 1, "2026-10-06T11:53:20Z")], 0, "",
     "--restart-quiet", "300")
gate("a restart at/after --restarted-since: not green", A, [pod("p1", "u1", 1, "2026-10-06T11:00:00Z")], 1,
     "after 2026-10-06T10:30:00", "--restart-quiet", "300", "--restarted-since", "2026-10-06T10:30:00Z")
gate("a restart before --restarted-since: green", A, [pod("p1", "u1", 1, "2026-10-06T10:00:00Z")], 0, "",
     "--restart-quiet", "300", "--restarted-since", "2026-10-06T10:30:00Z")
def owned(p, kind, name, labels=None, phase=None):
    p["metadata"]["ownerReferences"] = [{"controller": True, "kind": kind, "name": name}]
    p["metadata"]["labels"] = labels or {}
    if phase:
        p["status"] = {"phase": phase, "containerStatuses": []}
    return p
def leftover(p):
    p["status"] = {"phase": "Failed", "reason": "Terminated", "message": "Pod was terminated in response to imminent node shutdown."}
    return p
old_rs = leftover(owned(pod("w-old-x", "u1"), "ReplicaSet", "w-6d8f", {"pod-template-hash": "6d8f"}))
new_rs = owned(pod("w-new-y", "u2"), "ReplicaSet", "w-7c9a", {"pod-template-hash": "7c9a"})
gate("a node-shutdown leftover replaced by a ready pod from a newer ReplicaSet: green", A, [old_rs, new_rs], 0)
gate("a node-shutdown leftover never replaced: not green", A, [old_rs, pod("p2", "u3")], 1, "not replaced")
failed = owned(pod("job-a", "j1"), "Job", "backup-1", phase="Failed")
done = owned(pod("job-b", "j2"), "Job", "backup-1", phase="Succeeded")
gate("a failed Job attempt a later attempt completed: green", A, [failed, done, pod("p2", "u3")], 0)
gate("a failed Job attempt with no completed one: not green", A, [failed, pod("p2", "u3")], 1, "ns/job-a (Failed)")
# a Succeeded pod excuses failed attempts of its Job only - another kind's failed pod is not "a later attempt completed"
rs_failed = owned(pod("rs-a", "r1"), "ReplicaSet", "web-1", phase="Failed")
rs_done = owned(pod("rs-b", "r2"), "ReplicaSet", "web-1", phase="Succeeded")
gate("a failed ReplicaSet pod beside a Succeeded one of the same owner: not green", A, [rs_failed, rs_done], 1,
     "ns/rs-a (Failed)")
# a Failed pod is a node-shutdown leftover only by the kubelet's own message - one terminated otherwise is a failure,
# whatever replaced it
other = with_(old_rs, ["status", "message"], "Pod was terminated in response to an eviction.")
gate("a pod terminated otherwise (not the node's shutdown), its owner running again: not green", A, [other, new_rs],
     1, "Failed")
# a restart exactly at --restarted-since is after the step began: judged
gate("a restart at the very --restarted-since: not green", A, [pod("p1", "u1", 1, "2026-10-06T10:30:00Z")], 1,
     "after 2026-10-06T10:30:00", "--restart-quiet", "300", "--restarted-since", "2026-10-06T10:30:00Z")

# the poll loop, against a kubectl stub: one failed poll is a red poll, not the end; restarts between polls never settle
def loop(mode, *args):
    d = tempfile.mkdtemp()
    json.dump({"items": A}, open(os.path.join(d, "apps.json"), "w"))
    with open(os.path.join(d, "kubectl"), "w") as f:
        f.write(f"""#!/bin/bash
n=$(cat {d}/n 2>/dev/null || echo 0); n=$((n + 1)); echo $n > {d}/n
case "$*" in *applications*) ;; *) p=1;; esac
if [ {mode} = fail-first ] && [ $n = 1 ]; then echo "connection refused" >&2; exit 1; fi
if [ -z "${{p:-}}" ]; then cat {d}/apps.json; exit 0; fi
r=0; [ {mode} = churn ] && r=$n
printf '{{"items":[{{"metadata":{{"namespace":"ns","name":"p1","uid":"u1"}},"status":{{"phase":"Running",'
printf '"containerStatuses":[{{"ready":true,"restartCount":%d}}]}}}}]}}' $r
""")
    os.chmod(os.path.join(d, "kubectl"), 0o755)
    r = subprocess.run([sys.executable, S, "--kubeconfig", "x", "--poll", "0", "--stable-polls", "2", *args],
                       capture_output=True, text=True, env={**os.environ, "PATH": d + ":" + os.environ["PATH"],
                                                             "MIRROR_REVISIONS": ""})
    return r.returncode, r.stdout + r.stderr
rc, out = loop("fail-first", "--minutes", "0.05", "--restart-quiet", "0")
check("a failed poll first: red, then settled", (rc, "poll failed" in out, "ARGO SETTLED" in out), (0, True, True), out)
rc, out = loop("churn", "--minutes", "0.02", "--restart-quiet", "0")
check("a restart between every two polls: never settled", (rc, "NOT SETTLED" in out, "restarted=ns/p1" in out),
      (1, True, True), out)

H = os.path.join(work, "history.json")
rc, out = run(A, [pod("p1", "u1", 3)], "--restart-history", H, "--step", "10")
check("the first call records, judging nothing (restarts from before)", rc, 0, out)
rc, out = run(A, [pod("p1", "u1", 4)], "--restart-history", H, "--step", "11")
check("a restart in one step: green", rc, 0, out)
rc, out = run(A, [pod("p1", "u1", 4)], "--restart-history", H, "--step", "12")
check("no restart in the next: green", rc, 0, out)
rc, out = run(A, [pod("p1", "u1", 5)], "--restart-history", H, "--step", "13")
check("a restart again, a step apart: green", rc, 0, out)
rc, out = run(A, [pod("p1", "u1", 6)], "--restart-history", H, "--step", "14")
check("a restart in two steps running: fails, naming the pod", (rc, "ns/p1" in out and "(13, 14)" in out), (1, True), out)
rc, out = run(A, [pod("p1", "u9", 1)], "--restart-history", H, "--step", "15")
check("a new pod (another uid) with a restart: one step only, green", rc, 0, out)
rc, out = run(A, [pod("p1", "u1", 0)], "--restart-history", H)
check("--restart-history without --step: bad arguments", rc, 2, out)

# control-plane upgrades in a row (steps 42 and 43): every leader-elected controller restarts in both, not after
H2 = os.path.join(work, "history-control-plane.json")
run(A, [pod("op", "o1", 0)], "--restart-history", H2, "--step", "41")
rc, out = run(A, [pod("op", "o1", 1)], "--restart-history", H2, "--step", "42", "--restarts-expected")
check("a restart in a control-plane step: green", rc, 0, out)
rc, out = run(A, [pod("op", "o1", 2)], "--restart-history", H2, "--step", "43", "--restarts-expected")
check("a restart in the next control-plane step: green (both expected)", rc, 0, out)
rc, out = run(A, [pod("op", "o1", 2)], "--restart-history", H2, "--step", "44")
check("no restart in the step after them: green", rc, 0, out)
rc, out = run(A, [pod("op", "o1", 3)], "--restart-history", H2, "--step", "45")
check("one restart a step later: green", rc, 0, out)
rc, out = run(A, [pod("op", "o1", 4)], "--restart-history", H2, "--step", "46")
check("and again in the next: a crash loop, caught", (rc, "ns/op" in out and "(45, 46)" in out), (1, True), out)
rc, out = run(A, [pod("op", "o1", 4)], "--restart-history", H2, "--step", "46")
check("the step's next call: caught again (the facts stay)", (rc, "(45, 46)" in out), (1, True), out)

# an app crash-looping slowly through the control-plane steps: not judged there, caught by the step after them
H3 = os.path.join(work, "history-app.json")
run(A, [pod("app", "a1", 1)], "--restart-history", H3, "--step", "41")
run(A, [pod("app", "a1", 25)], "--restart-history", H3, "--step", "42", "--restarts-expected")
rc, out = run(A, [pod("app", "a1", 60)], "--restart-history", H3, "--step", "43", "--restarts-expected")
check("an app restarting in two control-plane steps: green there (not judged)", rc, 0, out)
rc, out = run(A, [pod("app", "a1", 61)], "--restart-history", H3, "--step", "44")
check("and in the step after them: caught there", (rc, "ns/app" in out and "(43, 44)" in out), (1, True), out)
rc, out = run(A, [pod("op", "o1", 0)], "--restart-history", H3, "--step", "44", "--restarts-expected")
check("--restarts-expected says so", "restarts expected" in out, True, out)

# a step recorded twice compares with the step before it, not with itself
H4 = os.path.join(work, "history-rerun.json")
run(A, [pod("p", "r1", 0)], "--restart-history", H4, "--step", "21")
rc, out = run(A, [pod("p", "r1", 1)], "--restart-history", H4, "--step", "22")
check("a restart in 22: green", rc, 0, out)
rc, out = run(A, [pod("p", "r1", 2)], "--restart-history", H4, "--step", "22")
check("another on 22's second call: green - 22 is compared with 21, where it did not restart", rc, 0, out)
rc, out = run(A, [pod("p", "r1", 3)], "--restart-history", H4, "--step", "23")
check("restarted in 22 and 23: caught", (rc, "(22, 23)" in out), (1, True), out)

# a file of the earlier form (last_step, last_restart_step) is read as its steps
H5 = os.path.join(work, "history-old.json")
json.dump({"last_step": "30", "pods": {"x1": {"name": "ns/x", "count": 2, "last_restart_step": "30"}}}, open(H5, "w"))
rc, out = run(A, [pod("x", "x1", 3)], "--restart-history", H5, "--step", "31")
check("the earlier file's last restart step counts", (rc, "(30, 31)" in out), (1, True), out)

# argo-settled.yml's command line, rendered by Ansible's templar as the playbook holds it: --restarts-expected exactly
# when the step asks (the runner passes its yes / no) - a wiring that always passed it would record every crash loop
# and never judge one; the restart history only with a step
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
play = yaml.safe_load(open("tests/ansible/upgrade/argo-settled.yml"))[0]
script = next(t for t in play["tasks"] if "ansible.builtin.script" in t)["ansible.builtin.script"]["cmd"]
base = {k: v for k, v in play["vars"].items() if k != "mirror_revisions"}
for step, asked, want in (("20", "no", (True, False)), ("20", "yes", (True, True)), ("", "no", (False, False))):
    argv = render(script, **{**base, "restart_step": step, "restarts_expected": asked}).split()
    check(f"the playbook's command line, step {step or 'none'}, restarts expected {asked}: history, expected",
          ("--restart-history" in argv, "--restarts-expected" in argv), want)

print("argo-settled: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
