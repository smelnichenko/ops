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
    if [[ " $(cat "$W/bad-app-looks" 2>/dev/null) " == *" $n "* ]]; then cat "$W/apps-bad.json"; else cat "$W/apps.json"; fi ;;
  *"get pods"*) cat "$W/pods.json" ;;
  *"amtool alert query"*) n=$(cat "$W/looks" 2>/dev/null || echo 0); echo $((n + 1)) > "$W/looks"
    if [ -e "$W/alert-looks" ]; then
      if [[ " $(cat "$W/alert-looks") " == *" $n "* ]]; then cat "$W/alerts.json"; else echo '[]'; fi
    elif [ "$n" -ge "$(cat "$W/alert-after" 2>/dev/null || echo 999)" ] && [ "$n" -lt "$(cat "$W/alert-until" 2>/dev/null || echo 999)" ]; then
      cat "$W/alerts.json"; else echo '[]'; fi ;;
esac
STUB
chmod +x "$W/bin/ssh"
W=$W python3 - <<'PYCHECK'
import json, os, subprocess, sys
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def app(name, sync="Synced", health="Healthy", op="Succeeded", sources=None, revisions=None, labels=None):
    st = {"sync": {"status": sync}, "health": {"status": health}}
    if op is not None:
        st["operationState"] = {"phase": op}
    a = {"metadata": {"name": name, "labels": labels or {}}, "status": st, "spec": {}}
    if sources is not None:  # [(repoURL, targetRevision)], their synced commits in revisions
        a["spec"]["sources"] = [{"repoURL": u, "targetRevision": t} for u, t in sources]
        st["sync"]["revisions"] = revisions
    return a
def pod(ns, name, phase="Running", ready=(True,)):
    return {"metadata": {"namespace": ns, "name": name},
            "status": {"phase": phase, "containerStatuses": [{"name": f"c{i}", "ready": r} for i, r in enumerate(ready)]}}
def run(apps, pods, alerts=(), alert_after=None, down=False, settle="0", hold="2", pods_raw=None, streak="5", revs="",
        alert_until=None, alert_looks=None, bad_app_looks=None):
    for f in ("down", "looks", "alert-after", "alert-until", "alert-looks", "bad-app-looks"):
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
    if bad_app_looks is not None:
        open(os.path.join(W, "bad-app-looks"), "w").write(" ".join(map(str, bad_app_looks)))
        json.dump({"items": apps + [app("x", health="Progressing")]}, open(os.path.join(W, "apps-bad.json"), "w"))
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
CRIT = [{"labels": {"alertname": "PostgresDown", "severity": "critical"}}]
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_after=1, streak="1")
check("a critical alert during the hold (one look in a row enough): not quiet, named",
      (rc, "NOT QUIET" in out, "critical alert PostgresDown" in out), (1, True, True))
rc, out = run(OK_APPS, OK_PODS, alerts=CRIT, alert_after=1, streak="3", hold="15")
check("one still firing 3 looks in a row (the streak): not quiet", (rc, "NOT QUIET during the hold (3 looks in a row)" in out), (1, True))
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
rc, out = run(OK_APPS, OK_PODS, hold="0")
check("hold 0, nothing firing: settled and quiet in one look", (rc, out.strip()), (0, "SETTLED AND QUIET (one look)"))
rc, out = run(OK_APPS + [app("pr-42-monitor", health="Degraded", labels={"preview-env": "true"})], OK_PODS)
check("a preview environment's app broken (a pull request's): no part of production - settled", rc, 0)
rc, out = run(OK_APPS, OK_PODS, alerts=[{"labels": {"alertname": "Watchdog", "severity": "critical"}}], alert_after=0)
check("Watchdog firing (it always does): still quiet", rc, 0)
rc, out = run(OK_APPS, OK_PODS, alerts=[{"labels": {"alertname": "UpgradeCycle", "kind": "one-way-failed", "severity": "critical"}}],
              alert_after=0)
check("the cycle's own UpgradeCycle page (an earlier unit's one-way failure): not this apply's - still quiet", rc, 0)
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
r = subprocess.run(["bash", "scripts/upgrade-verify.sh"], capture_output=True, text=True,
                   env={**os.environ, "UPGRADE_VERIFY_REVISIONS": "infra=main"})
check("revisions that are no commits: refused", r.returncode, 2)
print("upgrade-verify: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
