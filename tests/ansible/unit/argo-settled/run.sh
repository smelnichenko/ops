#!/bin/bash
# tests/ansible/upgrade/files/argo-settled.py on saved apps and pods (its --apps-json/--pods-json mode): green on a
# settled set; the app floor (--expect-apps: a missing or an unexpected app is not green, an allowed extra is); an app
# compared against an older spec is not green, one whose spec only gained empty fields is; the restart history (--restart-history: a pod restarting in two steps running fails, one step's restart does not, the
# first call only records).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
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
            "status": {"sync": {"status": "Synced", "comparedTo": {"source": src}, "revision": "abc"},
                       "health": {"status": "Healthy"}, "operationState": {"phase": "Succeeded"}}}


def pod(name, uid, restarts=0, finished="2026-10-06T10:00:00Z"):
    c = {"ready": True, "restartCount": restarts}
    if restarts:
        c["lastState"] = {"terminated": {"finishedAt": finished}}
    return {"metadata": {"namespace": "ns", "name": name, "uid": uid},
            "status": {"phase": "Running", "containerStatuses": [c]}}


def run(apps, pods, *args):
    fa, fp = os.path.join(work, "apps.json"), os.path.join(work, "pods.json")
    json.dump({"items": apps}, open(fa, "w"))
    json.dump({"items": pods}, open(fp, "w"))
    r = subprocess.run([sys.executable, S, "--apps-json", fa, "--pods-json", fp, "--now", NOW, *args],
                       capture_output=True, text=True)
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

print("argo-settled: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
