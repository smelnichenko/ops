#!/bin/bash
# tests/ansible/upgrade/metrics-check.yml's scrape-target check as the playbook holds it (rendered by Ansible's templar,
# its conditions as Ansible evaluates them), kubectl a stub answering Prometheus: first every active target up now -
# retried, a target the step replaced coming up - the moment they all are recorded (t0); then each target active now
# up for 2 minutes, read from the last sample it was down (a subquery over t0 - 120 s .. now, among the targets active
# now - a replaced pod's last failed scrape is no flap): none - up 2 minutes already - passes at once (most steps: a
# fixed 2-minute wait was 2 hours over a full run); one before t0 (the step's own recovery) waits until 2 minutes after
# it; one after t0 is a flap and fails at once, never waited out (a window sliding with each retry let a flap age out).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# DOWN=1: one target down now; LAST_DOWN=<epoch>: a target's last sample down then (none: no result). Besides, one
# target down by nature, allowed by its scrape pool - its job label is another name (as the smartctl exporter's is)
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
smart='{"scrapePool": "scrapeConfig/ns/smart", "scrapeUrl": "s", "health": "down", "lastError": "refused",
        "labels": {"job": "smart-exporter"}}'
case "$*" in
  *targets*) h=up; [ -z "${DOWN:-}" ] || h=down
    echo "{\"data\": {\"activeTargets\": [{\"scrapePool\": \"p\", \"scrapeUrl\": \"u\", \"health\": \"$h\",
          \"lastError\": \"\", \"labels\": {\"job\": \"j\"}}, $smart]}}" ;;
  *query*) echo "${@: -1}" >> "$W/queries"
    r="{\"metric\": {\"job\": \"smart-exporter\", \"instance\": \"ten\"}, \"value\": [0, \"$(date +%s)\"]}"
    [ -z "${LAST_DOWN:-}" ] || r="$r, {\"metric\": {\"job\": \"j\", \"instance\": \"i\"}, \"value\": [0, \"$LAST_DOWN\"]}"
    echo "{\"data\": {\"result\": [$r]}}" ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import os, re, subprocess, sys, time, urllib.parse
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition, render  # noqa: E402
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
tasks = yaml.safe_load(open("tests/ansible/upgrade/metrics-check.yml"))[0]["tasks"]
cmd = lambda t: t["ansible.builtin.shell"] if isinstance(t["ansible.builtin.shell"], str) else t["ansible.builtin.shell"]["cmd"]
shells = [t for t in tasks if "ansible.builtin.shell" in t]
up_now = next((t for t in shells if "targets?state=active" in cmd(t) and "UP AT" in cmd(t)), None)
stayed = next((t for t in shells if "max_over_time" in cmd(t)), None)
check("an up-now check, then a stayed-up check", (up_now is not None, stayed is not None,
      up_now is not None and stayed is not None and tasks.index(up_now) < tasks.index(stayed)), (True, True, True))
if up_now is None or stayed is None:
    print("metrics-window: " + f"{fails} FAILED")
    sys.exit(1)
env = lambda **k: dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **k)
v = dict(kubeconfig="k", proxy="/p", allowed_down=["scrapeConfig/ns/smart"])
# up now: retried until every active target is; the moment recorded
check("up now: retried", (up_now.get("retries", 0) > 0, str(up_now.get("until", ""))), (True, f"{up_now['register']}.rc == 0"))
r = subprocess.run(["bash", "-c", render(cmd(up_now), **v)], capture_output=True, text=True, env=env())
at = re.search(r"^UP AT (\d+)$", r.stdout, re.M)
check("every target up: passes, the moment recorded", (r.returncode, bool(at) and abs(int(at[1]) - time.time()) < 5),
      (0, True))
r = subprocess.run(["bash", "-c", render(cmd(up_now), **v)], capture_output=True, text=True, env=env(DOWN="1"))
check("one down now: not yet (retried), no moment", (r.returncode != 0, "UP AT" in r.stdout), (True, False))
reg = up_now["register"]
def stayed_run(t0_ago, last_down_ago=None):
    """t0 (all up) t0_ago s before now; a target's last sample down last_down_ago s before now (None: none)."""
    open(os.path.join(W, "queries"), "w").close()
    now = int(time.time())
    ctx = {**v, reg: {"stdout": f"1 targets, 0 down\nUP AT {now - t0_ago}"}}
    script = render(cmd(stayed), **ctx)
    task_env = {n: str(render(str(x), **ctx)) for n, x in (stayed.get("environment") or {}).items()}
    extra = {} if last_down_ago is None else {"LAST_DOWN": str(now - last_down_ago)}
    t = time.monotonic()
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env(**task_env, **extra))
    q = urllib.parse.unquote(open(os.path.join(W, "queries")).read())
    rng = re.search(r"\[(\d+)s:\d+s\]", q)
    return r, q, int(rng[1]) if rng else None, time.monotonic() - t
r, q, rng, took = stayed_run(0)
check("all up at once, none down in the 2 minutes before (the one down by nature allowed by its scrape pool): passes "
      "at once - no wait",
      (r.returncode, took < 5, "stayed up" in r.stdout), (0, True, True))
check("judged from 2 minutes before t0 to now", rng is not None and 118 <= rng <= 125, True)
check("only the series of targets active now (a replaced pod's last scrape no flap)", "and on(job, instance) up" in q,
      True)
r, _, rng, _ = stayed_run(30)
check("t0 30 s ago: the window reaches 2 minutes before it", rng is not None and 148 <= rng <= 155, True)
r, _, _, _ = stayed_run(10, last_down_ago=40)
check("down 40 s ago, before t0 (the step's own recovery): not yet", (r.returncode, "NOT YET" in r.stdout), (2, True))
r, _, _, _ = stayed_run(150, last_down_ago=170)
check("down 170 s ago, before t0: up 2 minutes since - passes", (r.returncode, "stayed up" in r.stdout), (0, True))
r, _, _, _ = stayed_run(60, last_down_ago=20)
check("down 20 s ago, after t0: a flap", (r.returncode, "FLAPPED" in r.stdout), (1, True))
reg2 = stayed["register"]
until = stayed.get("until", "")
check("not yet: retried; a flap: no retry - it fails at once; passed: done",
      [condition(until, **{reg2: {"rc": rc, "stdout": out}}) for rc, out in
       ((2, "NOT YET j i (40 s up of 120)"), (1, "FLAPPED j i"), (0, "stayed up"))], [False, True, True])
check("a flap fails the task", condition(stayed.get("failed_when", f"{reg2}.rc != 0"),
                                         **{reg2: {"rc": 1, "stdout": "FLAPPED j i"}}), True)
check("the retries cover a recovery's 2 minutes", stayed.get("retries", 0) * stayed.get("delay", 5) >= 150, True)
print("metrics-window: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
