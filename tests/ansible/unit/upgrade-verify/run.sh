#!/bin/bash
# scripts/upgrade-verify.sh - the upgrade cycle's check after an apply - with ssh stubbed (each kubectl read answered from
# the case's JSON; the host's uptime moved on 61 s at each look, so the settle and the hold run at once): settled and
# quiet passes - production's size of pod list too; an app out of sync, unhealthy, or with a sync still running, a
# running pod unready - not settled when the settle's time is up; a critical alert during the hold - not quiet, Watchdog
# aside; ten unreachable, or an answer that is no JSON - not settled, said.
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
  *"get applications"*) cat "$W/apps.json" ;;
  *"get pods"*) cat "$W/pods.json" ;;
  *"amtool alert query"*) n=$(cat "$W/looks" 2>/dev/null || echo 0); echo $((n + 1)) > "$W/looks"
    if [ "$n" -ge "$(cat "$W/alert-after" 2>/dev/null || echo 999)" ]; then cat "$W/alerts.json"; else echo '[]'; fi ;;
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
def app(name, sync="Synced", health="Healthy", op="Succeeded"):
    st = {"sync": {"status": sync}, "health": {"status": health}}
    if op is not None:
        st["operationState"] = {"phase": op}
    return {"metadata": {"name": name}, "status": st}
def pod(ns, name, phase="Running", ready=(True,)):
    return {"metadata": {"namespace": ns, "name": name},
            "status": {"phase": phase, "containerStatuses": [{"name": f"c{i}", "ready": r} for i, r in enumerate(ready)]}}
def run(apps, pods, alerts=(), alert_after=None, down=False, settle="0", hold="2", pods_raw=None):
    for f in ("down", "looks", "alert-after"):
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
    if down:
        open(os.path.join(W, "down"), "w").write("")
    env = {**os.environ, "PATH": os.path.join(W, "bin") + ":" + os.environ["PATH"], "W": W,
           "UPGRADE_VERIFY_SETTLE": settle, "UPGRADE_VERIFY_HOLD": hold, "UPGRADE_VERIFY_POLL": "0",
           "UPGRADE_VERIFY_UPTIME": os.path.join(W, "uptime")}
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
rc, out = run(OK_APPS, OK_PODS, alerts=[{"labels": {"alertname": "PostgresDown", "severity": "critical"}}], alert_after=1)
check("a critical alert during the hold: not quiet, named", (rc, "NOT QUIET" in out, "critical alert PostgresDown" in out),
      (1, True, True))
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
print("upgrade-verify: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
