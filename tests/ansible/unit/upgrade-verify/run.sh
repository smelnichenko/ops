#!/bin/bash
# scripts/upgrade-verify.sh - the upgrade cycle's check after an apply - with ssh stubbed (each kubectl read answered from
# the case's JSON; the host's uptime moved on 61 s at each look, so the settle and the hold run at once): settled and
# quiet passes - production's size of pod list too; an app out of sync, unhealthy, or with a sync still running, a
# running pod unready - not settled when the settle's time is up; a critical alert during the hold - not quiet, Watchdog
# aside, once it fires the streak's looks in a row (gone before: quiet); hold 0 (the gate's look) - a critical alert is
# part of it; a preview environment's app - no part of production; the merge's commits - an app tracking infra's main
# synced to them or later (a git fixture), still before them not settled; ten unreachable, or an answer that is no JSON -
# not settled, said.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/ssh" <<'STUB'
#!/bin/bash
[ ! -e "$W/down" ] || exit 255
read -r u _ < "$W/uptime"; echo "$((${u%.*} + 61)).00 0.00" > "$W/uptime"
case "$*" in
  *"get applications"*) n=$(cat "$W/looks" 2>/dev/null || echo 0)
    if [[ " $(cat "$W/bad-app-looks" 2>/dev/null) " == *" $n "* ]]; then
      if [ -e "$W/apps-bad.$n.json" ]; then cat "$W/apps-bad.$n.json"; else cat "$W/apps-bad.json"; fi
    else cat "$W/apps.json"; fi ;;
  *"get pods"*) n=$(cat "$W/looks" 2>/dev/null || echo 0); if [ -e "$W/pods.$n.json" ]; then cat "$W/pods.$n.json"; else cat "$W/pods.json"; fi ;;

  *"amtool alert query"*) n=$(cat "$W/looks" 2>/dev/null || echo 0); echo $((n + 1)) > "$W/looks"
    if [ -e "$W/alert-looks" ]; then
      if [[ " $(cat "$W/alert-looks") " == *" $n "* ]]; then cat "$W/alerts.json"; else echo '[]'; fi
    elif [ "$n" -ge "$(cat "$W/alert-after" 2>/dev/null || echo 999)" ] && [ "$n" -lt "$(cat "$W/alert-until" 2>/dev/null || echo 999)" ]; then
      cat "$W/alerts.json"; else echo '[]'; fi ;;
esac
STUB
chmod +x "$W/bin/ssh"
W=$W python3 - <<'PYCHECK'
import json, os, re, subprocess, sys
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def app(name, sync="Synced", health="Healthy", op="Succeeded", sources=None, revisions=None, labels=None, single=False,
        compared=None, namespace=None):
    st = {"sync": {"status": sync}, "health": {"status": health}}
    if op is not None:
        st["operationState"] = {"phase": op}
    a = {"metadata": {"name": name, "labels": labels or {}}, "status": st, "spec": {}}
    if namespace:
        a["spec"]["destination"] = {"namespace": namespace}
    if sources is not None:  # [(repoURL, targetRevision)], their synced commits in revisions; compared as specified
        srcs = [{"repoURL": u, **({"targetRevision": t} if t is not None else {})} for u, t in sources]
        if single:  # the common shape: spec.source and sync.revision
            a["spec"]["source"] = srcs[0]; st["sync"]["revision"] = revisions[0]
            st["sync"]["comparedTo"] = {"source": compared[0] if compared else srcs[0]}
        else:
            a["spec"]["sources"] = srcs; st["sync"]["revisions"] = revisions
            st["sync"]["comparedTo"] = {"sources": compared if compared else srcs}
    return a
def pod(ns, name, phase="Running", ready=(True,), native=None):
    out = {"metadata": {"namespace": ns, "name": name},
           "status": {"phase": phase, "containerStatuses": [{"name": f"c{i}", "ready": r} for i, r in enumerate(ready)]}}
    if native is not None:  # Istio's native sidecar (an init container restarting Always) and a plain init container, done
        out["spec"] = {"initContainers": [{"name": "istio-proxy", "restartPolicy": "Always"}, {"name": "setup"}]}
        out["status"]["initContainerStatuses"] = [{"name": "istio-proxy", "ready": native}, {"name": "setup", "ready": False}]
    return out
def run(apps, pods, alerts=(), alert_after=None, down=False, settle="0", hold="2", pods_raw=None, streak="5", revs="",
        alert_until=None, alert_looks=None, bad_app_looks=None, bad_apps=None, apps_by_look=None, pods_by_look=None):
    for f in [x for x in os.listdir(W) if x.startswith(("apps-bad.", "pods."))] + ["down", "looks", "alert-after", "alert-until", "alert-looks", "bad-app-looks"]:
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
    json.dump({"items": apps}, open(os.path.join(W, "apps.json"), "w"))
    json.dump({"items": pods}, open(os.path.join(W, "pods.json"), "w"))
    if pods_raw is not None:
        open(os.path.join(W, "pods.json"), "w").write(pods_raw)
    json.dump(list(alerts), open(os.path.join(W, "alerts.json"), "w"))
    open(os.path.join(W, "uptime"), "w").write("1000.00 0.00\n")
    if alert_after is not None:
        open(os.path.join(W, "alert-after"), "w").write(str(alert_after))
    if alert_until is not None:
        open(os.path.join(W, "alert-until"), "w").write(str(alert_until))
    if alert_looks is not None:
        open(os.path.join(W, "alert-looks"), "w").write(" ".join(map(str, alert_looks)))
    for name, by_look in (("apps-bad", apps_by_look), ("pods", pods_by_look)):  # an answer of its own at each look
        for n, items in (by_look or {}).items():
            json.dump({"items": items}, open(os.path.join(W, f"{name}.{n}.json"), "w"))
    if bad_app_looks is not None:
        open(os.path.join(W, "bad-app-looks"), "w").write(" ".join(map(str, bad_app_looks)))
        json.dump({"items": apps + (bad_apps or [app("x", health="Progressing")])}, open(os.path.join(W, "apps-bad.json"), "w"))
    if down:
        open(os.path.join(W, "down"), "w").write("")
    env = {**os.environ, "PATH": os.path.join(W, "bin") + ":" + os.environ["PATH"], "W": W,
           "UPGRADE_VERIFY_SETTLE": settle, "UPGRADE_VERIFY_HOLD": hold, "UPGRADE_VERIFY_POLL": "0",
           "UPGRADE_VERIFY_UPTIME": os.path.join(W, "uptime"), "UPGRADE_VERIFY_STREAK": streak,
           "UPGRADE_VERIFY_REVISIONS": revs, "UPGRADE_VERIFY_REPOS": os.path.join(W, "repos")}
    r = subprocess.run(["bash", "scripts/upgrade-verify.sh"], capture_output=True, text=True, env=env, timeout=60)
    return r.returncode, r.stdout
OK_APPS = [app("root", op=None), app("schnappy-production-data")]
OK_PODS = [pod("a", "p1"), pod("a", "done", phase="Succeeded", ready=(False,))]
rc, out = run(OK_APPS, OK_PODS)
check("settled and quiet: passes (a finished pod's unready containers aside)", (rc, out.strip().splitlines()[-1]),
      (0, "SETTLED AND QUIET for 2 min"))
for name, apps in (("an app out of sync", [app("x", sync="OutOfSync")]), ("an app degraded", [app("x", health="Degraded")]),
                   ("a sync still running", [app("x", op="Running")])):
    rc, out = run(apps, OK_PODS)
    check(f"{name}: not settled, named", (rc, "NOT SETTLED" in out, "app x" in out), (1, True, True))
rc, out = run(OK_APPS, [pod("schnappy-production", "monitor-1", ready=(True, False))])
check("a running pod unready: not settled, named", (rc, "pod schnappy-production/monitor-1 unready: c1" in out), (1, True))
rc, out = run(OK_APPS, [pod("schnappy-production", "chat-1", native=False)])
check("a running pod's native sidecar unready: not settled, named", (rc, "pod schnappy-production/chat-1 unready: istio-proxy" in out), (1, True))
rc, out = run(OK_APPS, [pod("schnappy-production", "chat-2", native=True)])
check("  its native sidecar ready, a plain init container done (not ready): settled", rc, 0)
CRIT = [{"labels": {"alertname": "PostgresDown", "severity": "critical"}}]
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_after=1, streak="1")
check("a critical alert during the hold (one look in a row enough): not quiet, named",
      (rc, "NOT QUIET" in out, "critical alert PostgresDown" in out), (1, True, True))
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_after=1, streak="3", hold="15")
check("one still firing 3 looks in a row (the streak): not quiet", (rc, "NOT QUIET during the hold (3 looks in a row)" in out), (1, True))
check("  each look of the streak said as it came - its time first, the count in a row, what fired",
      [re.sub(r"^\d\d:\d\d:\d\d ", "", l) for l in out.splitlines() if re.match(r"\d\d:\d\d:\d\d not quiet", l)],
      [f"not quiet ({n} of 3 looks in a row): critical alert PostgresDown" for n in (1, 2, 3)])
rc, out = run(OK_APPS, OK_PODS, hold="25")
lines = out.strip().splitlines()
held = [re.fullmatch(r"\d\d:\d\d:\d\d quiet - (\d+) of 25 min held", l) for l in lines]
check("a quiet hold of 25 min: its start said with its time, then one line every 10 minutes - how far, never past the hold",
      (rc, bool(re.fullmatch(r"SETTLED at \d\d:\d\d:\d\d - the hold: 25 min", lines[0])), [int(m.group(1)) for m in held if m],
       lines[-1], len(lines)), (0, True, [12, 21], "SETTLED AND QUIET for 25 min", 4))
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_after=1, alert_until=3, streak="3", hold="15")
check("one firing 2 looks, then gone (a rollout's minutes): quiet", (rc, out.strip().splitlines()[-1]), (0, "SETTLED AND QUIET for 15 min"))
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_looks=(1, 2, 4, 5), streak="3", hold="15")
check("firing 2 looks, a clean look, 2 more: never 3 in a row - quiet (a clean look starts every count again)", rc, 0)
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_looks=(1, 2, 4), bad_app_looks=(3,), streak="3", hold="15")
check("firing 2 looks, a look with something else wrong alone, firing again: not 3 in a row - quiet (what a look lacks "
      "starts again)", rc, 0)
# the one look before an apply (settle 0, hold 0): a critical alert already firing is part of it
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_after=0, hold="0")
check("hold 0 (the gate's look), a critical alert firing: not settled, named - never applied on top of it",
      (rc, "critical alert PostgresDown" in out), (1, True))
check("  the gate's one look (settle 0): no progress line - the verdict alone",
      [l for l in out.splitlines() if re.match(r"\d\d:\d\d:\d\d ", l)], [])
rc, out = run(OK_APPS, OK_PODS, hold="0")
check("hold 0, nothing firing: settled and quiet in one look", (rc, out.strip()), (0, "SETTLED AND QUIET (1 look)"))
rc, out = run(OK_APPS, OK_PODS, hold="0", settle="5")
check("hold 0 while waiting for Argo (settle > 0): two clean looks in a row (a look between a compare and its sync is no "
      "settle)", (rc, out.strip(), int(open(os.path.join(W, "looks")).read())), (0, "SETTLED AND QUIET (2 looks in a row)", 2))
rc, out = run(OK_APPS, OK_PODS, hold="0", settle="15", bad_app_looks=(1,))
check("  clean, then not, then clean twice: the count starts again - three clean looks of four, settled on the last two",
      (rc, out.strip().splitlines()[-1], int(open(os.path.join(W, "looks")).read())), (0, "SETTLED AND QUIET (2 looks in a row)", 4))
# the console's progress (operator 2026-11-22: a silent hour read as a hang): each look not settled said as it came, on one
# line, its time first (the runner's test_only skips such lines - never a complaint)
check("  the look not settled said as it came: one line, its time first, what it found",
      [bool(re.fullmatch(r"\d\d:\d\d:\d\d not settled yet: app x Synced Progressing Succeeded", l)) for l in out.strip().splitlines()[:-1]], [True])
rc, out = run(OK_APPS, OK_PODS, hold="0", settle="15", bad_app_looks=(0, 1), bad_apps=[app("x", health="Progressing"), app("y", sync="OutOfSync")])
check("  a look finding two things: both on its one line", [l[9:] for l in out.strip().splitlines()[:-1]],
      ["not settled yet: app x Synced Progressing Succeeded; app y OutOfSync Healthy Succeeded"] * 2)
rc, out = run(OK_APPS + [app("pr-42-monitor", health="Degraded", labels={"preview-env": "true"})], OK_PODS)
check("a preview environment's app broken (a pull request's): no part of production - settled", rc, 0)
rc, out = run(OK_APPS, OK_PODS, alerts=[{"labels": {"alertname": "Watchdog", "severity": "critical"}}], alert_after=0, streak="1")
check("Watchdog firing (it always does), one look in a row enough: still quiet", (rc, "critical alert" in out), (0, False))
rc, out = run(OK_APPS, OK_PODS, alerts=[{"labels": {"alertname": "UpgradeCycle", "kind": "one-way-failed", "severity": "critical"}}],
              alert_after=0, streak="1")
check("the cycle's own UpgradeCycle page (an earlier unit's one-way failure), one look enough: not this apply's - still quiet",
      (rc, "critical alert" in out), (0, False))
PREVIEW = app("pr-42-monitor", health="Degraded", labels={"preview-env": "true"}, namespace="schnappy-pr-42")
rc, out = run(OK_APPS + [PREVIEW], OK_PODS + [pod("schnappy-pr-42", "monitor-0", ready=(False,))],
              alerts=[{"labels": {"alertname": "PodCrashLooping", "severity": "critical", "namespace": "schnappy-pr-42"}}],
              alert_after=0, streak="1")
check("a preview environment's pod crash-looping and its alert firing (its namespace a preview app's): no part of production",
      (rc, out.strip().splitlines()[-1]), (0, "SETTLED AND QUIET for 2 min"))
rc, out = run(OK_APPS + [PREVIEW], [pod("schnappy-production", "monitor-0", ready=(False,))])
check("  control: the same pod in production's namespace - not settled", (rc, "pod schnappy-production/monitor-0" in out), (1, True))
rc, out = run(OK_APPS + [app("pr-7-site", health="Degraded", labels={"preview-env": "true"})], OK_PODS,
              alerts=[{"labels": {"alertname": "NodeDown", "severity": "critical"}}], alert_after=0, streak="1")
check("a preview app with no destination of its own: no namespace of 'preview' - a critical alert with no namespace (a "
      "node's) still not quiet", (rc, "critical alert NodeDown" in out), (1, True))
# a streak counts its subject, not its words: an app broken all hour while its state flips, a pod recreated under new names
FLIP = [[app("observability", health="Degraded")], [app("observability", health="Progressing")]]
rc, out = run(OK_APPS, OK_PODS, streak="3", hold="15", bad_app_looks=(1, 2, 3, 4), bad_apps=FLIP[0])
check("an app broken through the hold (the same words each look): not quiet", (rc, "NOT QUIET" in out), (1, True))
rc, out = run(OK_APPS, OK_PODS, streak="3", hold="15", bad_app_looks=(1, 2, 3, 4),
              apps_by_look={n: OK_APPS + FLIP[n % 2] for n in (1, 2, 3, 4)})
check("an app broken through the hold, its state flipping each look (Degraded, Progressing): the same subject - not quiet",
      (rc, "NOT QUIET" in out), (1, True))
rc, out = run(OK_APPS, OK_PODS, streak="3", hold="15",
              pods_by_look={n: [pod("schnappy-production", f"monitor-7d9f8b6c4d-{x}", ready=(False,))]
                            for n, x in ((1, "bbbb2"), (2, "cccc4"), (3, "dddd5"), (4, "ffff6"))})
check("a Deployment's pod unready, recreated under a new name each look: its owner the subject - not quiet",
      (rc, "NOT QUIET" in out), (1, True))
rc, out = run(OK_APPS, OK_PODS, streak="3", hold="15", pods_by_look={1: [pod("schnappy-production", f"monitor-7d9f8b6c4d-{x}", ready=(False,))
                                                                         for x in ("aaaa2", "bbbb4", "cccc5")]})
check("three replicas unready in one look, quiet after: one subject counted once - quiet (never three looks in one)",
      (rc, out.strip().splitlines()[-1]), (0, "SETTLED AND QUIET for 15 min"))
# what a complaint is about - the function itself (Kubernetes' own alphabet names a pod's random parts)
vsrc = open("scripts/upgrade-verify.sh").read()
subject_fn = vsrc[vsrc.index("\nsubject() {") + 1:].split("\n}\n", 1)[0] + "\n}"
def subject(line):
    return subprocess.run(["bash", "-c", subject_fn + '\nsubject "$1"', "_", line], capture_output=True, text=True).stdout.strip()
TABLE = [("pod ns/monitor-7d9f8b6c4d-x2k9p unready: c", "pod ns/monitor"), ("pod ns/monitor-bcdfghjklm-x2k9p unready: c", "pod ns/monitor"),
         ("pod ns/kafka-0 unready: c", "pod ns/kafka"), ("pod ns/kafka-1 unready: c", "pod ns/kafka"),
         ("pod ns/redis-6379-1 unready: c", "pod ns/redis-6379"), ("pod ns/pg15-7d9f8b6c4d-x2k9p unready: c", "pod ns/pg15"),
         ("pod ns/node-exporter-x7k2q unready: c", "pod ns/node-exporter"), ("pod ns/etcd-ten unready: c", "pod ns/etcd-ten"),
         ("app observability Synced Degraded -", "app observability"), ("app observability OutOfSync Healthy Running", "app observability"),
         ("critical alert NodeDown", "critical alert NodeDown"), ("apps not read", "apps not read"),
         ("pod ns/api-6d4cf56d-x2k9p unready: c", "pod ns/api"), ("pod ns/node-exporter-zx7k2 unready: c", "pod ns/node-exporter"),
         # a name of its own whose last part only looks generated - a vowel, a 0, a 1 or a 3 (never in Kubernetes'
         # alphabet), four characters where it makes five: kept whole
         ("pod ns/x-bcdfa unready: c", "pod ns/x-bcdfa"), ("pod ns/x-bcdf0 unready: c", "pod ns/x-bcdf0"),
         ("pod ns/x-bcdf1 unready: c", "pod ns/x-bcdf1"), ("pod ns/x-bcdf3 unready: c", "pod ns/x-bcdf3"),
         ("pod ns/x-cache unready: c", "pod ns/x-cache"), ("pod ns/web-6d4cf56d4-x2k9 unready: c", "pod ns/web-6d4cf56d4-x2k9"),
         ("pod ns/web-bcdf unready: c", "pod ns/web-bcdf")]
check("a complaint's subject: a ReplicaSet's pods by their name (a hash with no digit too), a StatefulSet's by theirs, a "
      "DaemonSet's, a name of its own as it is (a part that only looks generated kept); an app whatever its state; an "
      "alert by its name",
      [(l, subject(l), w) for l, w in TABLE if subject(l) != w], [])
STALL = app("cert-manager", sync="OutOfSync")
STALL["spec"]["syncPolicy"] = {"automated": {}}
STALL["status"]["operationState"] = {"phase": "Succeeded", "operation": {"initiatedBy": {"automated": True}}}
rc, out = run([STALL], OK_PODS)
check("an app stalled (an automated sync Argo will not start again): not settled, said as STALLED", (rc, "STALLED" in out), (1, True))
rc, out = run(OK_APPS, OK_PODS, down=True)
check("ten unreachable: not settled, said", (rc, "apps not read" in out), (1, True))
# production's list: 300 pods with long names and labels - over the 128 KiB one environment variable may hold (the
# script passed it so: "Argument list too long", never settled, 2026-11-14)
big = [dict(pod("schnappy-production", f"monitor-{i:04d}-" + "x" * 300), spec={"pad": "y" * 400}) for i in range(300)]
assert len(json.dumps({"items": big})) > 200 * 1024
rc, out = run(OK_APPS, big)
check("production's size of pod list (over 128 KiB): read, settled and quiet", (rc, out.strip().splitlines()[-1]),
      (0, "SETTLED AND QUIET for 2 min"))
rc, out = run(OK_APPS, OK_PODS, pods_raw="Error from server (ServiceUnavailable)\n")
check("an answer that is no JSON: not settled, said what (never a traceback)",
      (rc, "pods not read" in out, "Traceback" in out), (1, True, False))
r = subprocess.run(["bash", "scripts/upgrade-verify.sh"], capture_output=True, text=True,
                   env={**os.environ, "UPGRADE_VERIFY_HOLD": "an hour"})
check("a setting that is no number: refused", r.returncode, 2)
# the merge's commits (UPGRADE_VERIFY_REVISIONS): every app tracking infra's or platform's main synced to them or later
repo = os.path.join(W, "repos", "infra")
os.makedirs(repo)
def g(*a):
    return subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", *a], capture_output=True,
                          text=True, check=True).stdout.strip()
g("init", "-q", "-b", "main")
c = []
for i in range(3):
    g("commit", "-q", "--allow-empty", "-m", f"c{i}")
    c.append(g("rev-parse", "HEAD"))
INFRA = "https://git.pmon.dev/schnappy/infra.git"
def tracking(rev, target="HEAD"):
    return app("observability", sources=[("https://charts.example", "1.2.3"), (INFRA, target)], revisions=["1.2.3", rev])
rc, out = run([tracking(c[0])], OK_PODS, revs=f"infra={c[1]}")
check("an app still on the commit before the merge (Argo not yet polled): not settled, named",
      (rc, "app observability infra at" in out, "not yet the merge's" in out), (1, True, True))
for rev, why in ((c[1], "on the merge's commit"), (c[2], "on a later one (CD moved main since)")):
    check(f"an app {why}: settled", run([tracking(rev)], OK_PODS, revs=f"infra={c[1]}")[0], 0)
check("an app tracking a tag of infra, not its main: not judged by the merge", run([tracking(c[0], "v1")], OK_PODS,
                                                                                   revs=f"infra={c[1]}")[0], 0)
check("no revisions given (the gate before an apply): not judged", run([tracking(c[0])], OK_PODS)[0], 0)
first = app("observability", sources=[(INFRA, "HEAD"), ("https://charts.example", "1.2.3")], revisions=[c[0], "1.2.3"])
check("infra the FIRST of two sources, still before the merge: not settled (each source's own revision, by its place)",
      run([first], OK_PODS, revs=f"infra={c[1]}")[0], 1)
first_at = app("observability", sources=[(INFRA, "HEAD"), ("https://charts.example", "1.2.3")], revisions=[c[1], "1.2.3"])
check("  infra the first source, at the merge (the chart's revision after it): settled - its own revision read, not the last",
      run([first_at], OK_PODS, revs=f"infra={c[1]}")[0], 0)
one = app("cluster-config", sources=[(INFRA, None)], revisions=[c[0]], single=True)
check("a single-source app (spec.source, sync.revision), its targetRevision unset (main), still before the merge: not settled",
      run([one], OK_PODS, revs=f"infra={c[1]}")[0], 1)
check("  at the merge: settled", run([app("cluster-config", sources=[(INFRA, None)], revisions=[c[1]], single=True)], OK_PODS,
                                    revs=f"infra={c[1]}")[0], 0)
empty_values = app("observability", sources=[(INFRA, "HEAD")], revisions=[c[1]], compared=[{"repoURL": INFRA, "targetRevision": "HEAD"}])
empty_values["spec"]["sources"][0]["helm"] = {"values": "", "skipCrds": False}
check("a spec carrying what Go leaves out of comparedTo (helm.values \"\", skipCrds false): the same spec - settled",
      run([empty_values], OK_PODS, revs=f"infra={c[1]}")[0], 0)
zero = app("observability", sources=[(INFRA, "HEAD")], revisions=[c[1]], compared=[{"repoURL": INFRA, "targetRevision": "HEAD",
                                                                                     "helm": {"valuesObject": {}}}])
zero["spec"]["sources"][0]["helm"] = {"valuesObject": {"replicas": 0, "enabled": False}}
check("  Helm values of false and 0 against none compared: values, not emptiness - an older spec", run([zero], OK_PODS, revs=f"infra={c[1]}")[0], 1)
older = app("observability", sources=[(INFRA, "HEAD")], revisions=[c[1]], compared=[{"repoURL": INFRA, "targetRevision": "HEAD",
                                                                                       "helm": {"valuesObject": {"v": 1}}}])
rc, out = run([older], OK_PODS, revs=f"infra={c[1]}")
check("an app compared against an older spec (its chart moved by the merge, not yet compared again): not settled, said",
      (rc, "compared against an older spec" in out), (1, True))
# the merge's commit fetched when the checkout lacks it (an origin with it, a clone without)
origin = os.path.join(W, "repos-origin"); other = os.path.join(W, "repos-other")
subprocess.run(["git", "clone", "-q", "--bare", repo, origin], check=True)
subprocess.run(["git", "clone", "-q", origin, other], check=True)
subprocess.run(["git", "-C", other, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "c3"], check=True)
subprocess.run(["git", "-C", other, "push", "-q", "origin", "HEAD:main"], check=True, capture_output=True)
c3 = subprocess.run(["git", "-C", origin, "rev-parse", "main"], capture_output=True, text=True, check=True).stdout.strip()
g("remote", "add", "origin", origin)
gc = subprocess.run(["git", "-C", repo, "cat-file", "-e", c3 + "^{commit}"], capture_output=True).returncode
check("  (the checkout lacks the app's commit before the look)", gc != 0, True)
check("an app on a commit the checkout lacks (CD moved main since its last fetch): fetched, then judged - settled",
      run([tracking(c3)], OK_PODS, revs=f"infra={c[1]}")[0], 0)
g("remote", "set-url", "origin", os.path.join(W, "nowhere"))
check("  an app on a commit nowhere to be fetched: not settled", run([tracking("9" * 40)], OK_PODS, revs=f"infra={c[1]}")[0], 1)
r = subprocess.run(["bash", "scripts/upgrade-verify.sh"], capture_output=True, text=True,
                   env={**os.environ, "UPGRADE_VERIFY_REVISIONS": "infra=main"})
check("revisions that are no commits: refused", r.returncode, 2)
print("upgrade-verify: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
