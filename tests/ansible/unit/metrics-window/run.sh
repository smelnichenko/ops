#!/bin/bash
# tests/ansible/upgrade/metrics-check.yml's scrape-target check as the playbook holds it (rendered by Ansible's templar,
# its conditions as Ansible evaluates them), kubectl a stub answering Prometheus: first every active target up now -
# retried, a target the step replaced coming up - the moment they all are recorded (t0); then each target active now
# up for 2 minutes, read from the last sample it was down and from its first (subqueries over t0 - 120 s .. now, among
# the targets active now - a replaced pod's last failed scrape is no flap; sample times, not the subquery's steps): none
# - up 2 minutes already - passes at once (most steps: a fixed 2-minute wait was 2 hours over a full run); one before t0
# (the step's own recovery) waits until 2 minutes after it; one after t0 of a target there at t0 is a flap and fails at
# once, never waited out (a window sliding with each retry let a flap age out); a target first seen after t0 (a pod the
# settle replaced) waits its 2 minutes from its first sample, its early downs no flap. No active target fails.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# DOWN=1: one target down now; NO_TARGETS=1: none active; LAST_DOWN=<epoch>: a target's last sample down then (none:
# no result); FIRST=<epoch>: its first sample (long before, without). Besides, one target down by nature, allowed by its
# scrape pool - its job label is another name (as the smartctl exporter's is)
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
smart='{"scrapePool": "scrapeConfig/ns/smart", "scrapeUrl": "s", "health": "down", "lastError": "refused",
        "labels": {"job": "smart-exporter"}}'
case "$*" in
  *targets*) h=up; [ -z "${DOWN:-}" ] || h=down
    if [ -n "${NO_TARGETS:-}" ]; then echo '{"data": {"activeTargets": []}}'; exit 0; fi
    echo "{\"data\": {\"activeTargets\": [{\"scrapePool\": \"p\", \"scrapeUrl\": \"u\", \"health\": \"$h\",
          \"lastError\": \"\", \"labels\": {\"job\": \"j\"}}, $smart]}}" ;;
  *query*min_over_time*) echo "${@: -1}" >> "$W/queries"
    long=$(( $(date +%s) - 3000 ))
    echo "{\"data\": {\"result\": [{\"metric\": {\"job\": \"smart-exporter\", \"instance\": \"ten\"}, \"value\": [0, \"$long\"]},
          {\"metric\": {\"job\": \"j\", \"instance\": \"i\"}, \"value\": [0, \"${FIRST:-$long}\"]}]}}" ;;
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
stayed = next((t for t in shells if "$DOWN_Q" in cmd(t)), None)
check("an up-now check, then a stayed-up check", (up_now is not None, stayed is not None,
      up_now is not None and stayed is not None and tasks.index(up_now) < tasks.index(stayed)), (True, True, True))
if up_now is None or stayed is None:
    print("metrics-window: " + f"{fails} FAILED")
    sys.exit(1)
env = lambda **k: dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **k)
play_vars = yaml.safe_load(open("tests/ansible/upgrade/metrics-check.yml"))[0]["vars"]
v = dict(play_vars, kubeconfig="k", proxy="/p", allowed_down=["scrapeConfig/ns/smart"])
# up now: retried until every active target is; the moment recorded
check("up now: retried", (up_now.get("retries", 0) > 0, str(up_now.get("until", ""))), (True, f"{up_now['register']}.rc == 0"))
r = subprocess.run(["bash", "-c", render(cmd(up_now), **v)], capture_output=True, text=True, env=env())
at = re.search(r"^UP AT (\d+)$", r.stdout, re.M)
check("every target up: passes, the moment recorded", (r.returncode, bool(at) and abs(int(at[1]) - time.time()) < 5),
      (0, True))
r = subprocess.run(["bash", "-c", render(cmd(up_now), **v)], capture_output=True, text=True, env=env(DOWN="1"))
check("one down now: not yet (retried), no moment", (r.returncode != 0, "UP AT" in r.stdout), (True, False))
r = subprocess.run(["bash", "-c", render(cmd(up_now), **v)], capture_output=True, text=True, env=env(NO_TARGETS="1"))
check("no active target (a Prometheus with no config loaded): not up", (r.returncode != 0, "UP AT" in r.stdout),
      (True, False))
reg = up_now["register"]
def stayed_run(t0_ago, last_down_ago=None, first_ago=None):
    """t0 (all up) t0_ago s before now; a target's last sample down last_down_ago s before now (None: none), its
    first first_ago s before now (None: long before)."""
    open(os.path.join(W, "queries"), "w").close()
    now = int(time.time())
    ctx = {**v, reg: {"stdout": f"1 targets, 0 down\nUP AT {now - t0_ago}"}}
    script = render(cmd(stayed), **ctx)
    task_env = {n: str(render(str(x), **ctx)) for n, x in (stayed.get("environment") or {}).items()}
    extra = {} if last_down_ago is None else {"LAST_DOWN": str(now - last_down_ago)}
    extra.update({} if first_ago is None else {"FIRST": str(now - first_ago)})
    t = time.monotonic()
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env(**task_env, **extra))
    q = urllib.parse.unquote(open(os.path.join(W, "queries")).read())
    rng = re.search(r"max_over_time.*?\[(\d+)s:\d+s\]", q)
    return r, q, int(rng[1]) if rng else None, time.monotonic() - t
r, q, rng, took = stayed_run(0)
check("all up at once, none down in the 2 minutes before (the one down by nature allowed by its scrape pool): passes "
      "at once - no wait",
      (r.returncode, took < 5, "stayed up" in r.stdout), (0, True, True))
check("judged from 2 minutes before t0 to now", rng is not None and 118 <= rng <= 125, True)
check("only the series of targets active now (a replaced pod's last scrape no flap)", "and on(job, instance) up" in q,
      True)
check("the samples' own times (timestamp() of an expression gives the subquery's step times: a down sample at 90 s "
      "read 100 - promtool 3.10)", ("(timestamp(up) and up == 0)" in q, "timestamp(up == 0)" in q), (True, False))
r, _, rng, _ = stayed_run(30)
check("t0 30 s ago: the window reaches 2 minutes before it", rng is not None and 148 <= rng <= 155, True)
r, _, _, _ = stayed_run(10, last_down_ago=40)
check("down 40 s ago, before t0 (the step's own recovery): not yet", (r.returncode, "NOT YET" in r.stdout), (2, True))
r, _, _, _ = stayed_run(150, last_down_ago=170)
check("down 170 s ago, before t0: up 2 minutes since - passes", (r.returncode, "stayed up" in r.stdout), (0, True))
r, _, _, _ = stayed_run(60, last_down_ago=20)
check("down 20 s ago, after t0: a flap", (r.returncode, "FLAPPED" in r.stdout), (1, True))
r, _, _, _ = stayed_run(30, last_down_ago=90)
check("down 90 s ago, before t0: not yet (up 2 minutes, not 1)", (r.returncode, "NOT YET" in r.stdout), (2, True))
r, _, _, _ = stayed_run(100, last_down_ago=119)
check("down 119 s ago: not yet", (r.returncode, "NOT YET" in r.stdout), (2, True))
r, _, _, _ = stayed_run(100, last_down_ago=121)
check("down 121 s ago: passes", (r.returncode, "stayed up" in r.stdout), (0, True))
r, _, _, _ = stayed_run(60, last_down_ago=55)
check("down 5 s after t0: a flap", (r.returncode, "FLAPPED" in r.stdout), (1, True))
r, _, _, _ = stayed_run(60, last_down_ago=59)
check("down 1 s after t0 (a scrape in flight at t0): no flap, not yet", (r.returncode, "NOT YET" in r.stdout), (2, True))
r, _, _, _ = stayed_run(60, last_down_ago=20, first_ago=30)
check("a target first seen after t0, down in its first scrapes: no flap, not yet", (r.returncode, "NOT YET" in r.stdout),
      (2, True))
r, _, _, _ = stayed_run(60, first_ago=30)
check("a target first seen 30 s ago, never down: not yet - its 2 minutes from its first sample",
      (r.returncode, "NOT YET" in r.stdout), (2, True))
r, _, _, _ = stayed_run(150, first_ago=130)
check("a target first seen 130 s ago, never down: passes", (r.returncode, "stayed up" in r.stdout), (0, True))
# a target first seen late (a pod the settle replaced, a Job's): its 2 minutes waited for while within the wait after
# t0 - never cut by a count of tries from the first poll; past it, given up (a target that never stays up) - said
wait_for = int(play_vars["up_wait_seconds"])
r, _, _, _ = stayed_run(wait_for - 60, first_ago=10)
check("a target first seen %d s after t0, up since: not yet - waited for, within the wait" % (wait_for - 70),
      (r.returncode, "NOT YET" in r.stdout, "GIVE UP" in r.stdout), (2, True, False))
r, _, _, _ = stayed_run(wait_for + 10, first_ago=10)
check("past the wait after t0, a target still not up 2 minutes: given up, said", (r.returncode, "GIVE UP" in r.stdout),
      (1, True))
r, q, _, _ = stayed_run(30)
frng = re.search(r"min_over_time.*?\[(\d+)s:\d+s\]", q)
check("its first sample read over a window 2 minutes longer (an old target's first sample in it is the window's start, "
      "give or take a scrape interval - never within 2 minutes of now)", frng is not None and 268 <= int(frng[1]) <= 275,
      True)
# the PromQL as Prometheus evaluates it: tests/promql/metrics-check.test.yml (promtool, CI's promql step) holds the
# same expressions, its window named
pt = yaml.safe_load(open("tests/promql/metrics-check.test.yml"))
exprs = {re.sub(r"\[\d+s:", "[RANGE:", e["expr"]) for t in pt["tests"] for e in t["promql_expr_test"]}
check("promtool evaluates the playbook's own expressions",
      ({play_vars["down_query"], play_vars["first_query"]} <= exprs), True)
reg2 = stayed["register"]
until = stayed.get("until", "")
check("not yet: retried; a flap: no retry - it fails at once; given up: no retry; passed: done",
      [condition(until, **{reg2: {"rc": rc, "stdout": out}}) for rc, out in
       ((2, "NOT YET j i (40 s up of 120)"), (1, "FLAPPED j i"), (1, "NOT YET j i\nGIVE UP"), (0, "stayed up"))],
      [False, True, True, True])
check("a flap fails the task", condition(stayed.get("failed_when", f"{reg2}.rc != 0"),
                                         **{reg2: {"rc": 1, "stdout": "FLAPPED j i"}}), True)
check("the retries cover the wait after t0 (the polls start at t0, or after)",
      int(render(str(stayed.get("retries", 0)), **v)) * stayed.get("delay", 5) >= wait_for, True)
check("the wait covers a recovery's 2 minutes, and a target first seen as late again after t0",
      wait_for >= 2 * int(play_vars["up_for_seconds"]), True)
print("metrics-window: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
