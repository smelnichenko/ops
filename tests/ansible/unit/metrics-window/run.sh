#!/bin/bash
# tests/ansible/upgrade/metrics-check.yml's scrape-target check as the playbook holds it (rendered by Ansible's templar,
# its conditions as Ansible evaluates them), kubectl a stub answering Prometheus: first every active target up now -
# retried, a target the step replaced coming up (a window fixed before that judged its recovery a flap, and its
# retries could never pass) - the moment they all are recorded; then up for 2 minutes since that moment among the
# targets active now (a replaced pod's last failed scrape is no flap) - a flap since then fails at once, never waited
# out (each retry of the old check read the 2 minutes before its own time: a flap aged out).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
# DOWN=1: one target down now; FLAPPED=1: the window's query finds a series down since the start
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
case "$*" in
  *targets*) h=up; [ -z "${DOWN:-}" ] || h=down
    echo "{\"data\": {\"activeTargets\": [{\"scrapePool\": \"p\", \"scrapeUrl\": \"u\", \"health\": \"$h\",
          \"lastError\": \"\", \"labels\": {\"job\": \"j\"}}]}}" ;;
  *query*) echo "${@: -1}" >> "$W/queries"
    if [ -n "${FLAPPED:-}" ]; then echo '{"data": {"result": [{"metric": {"job": "j", "instance": "i"}}]}}'
    else echo '{"data": {"result": []}}'; fi ;;
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
stayed = next((t for t in shells if "min_over_time" in cmd(t)), None)
check("an up-now check, then a stayed-up check", (up_now is not None, stayed is not None,
      up_now is not None and stayed is not None and tasks.index(up_now) < tasks.index(stayed)), (True, True, True))
if up_now is None or stayed is None:
    print("metrics-window: " + f"{fails} FAILED")
    sys.exit(1)
env = lambda **k: dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], W=W, **k)
v = dict(kubeconfig="k", proxy="/p", allowed_down=[])
# up now: retried until every active target is; the moment recorded
check("up now: retried", (up_now.get("retries", 0) > 0, str(up_now.get("until", ""))), (True, f"{up_now['register']}.rc == 0"))
r = subprocess.run(["bash", "-c", render(cmd(up_now), **v)], capture_output=True, text=True, env=env())
at = re.search(r"^UP AT (\d+)$", r.stdout, re.M)
check("every target up: passes, the moment recorded", (r.returncode, bool(at) and abs(int(at[1]) - time.time()) < 5),
      (0, True))
r = subprocess.run(["bash", "-c", render(cmd(up_now), **v)], capture_output=True, text=True, env=env(DOWN="1"))
check("one down now: not yet (retried), no moment", (r.returncode != 0, "UP AT" in r.stdout), (True, False))
# stayed up since that moment, among the targets active now
reg = up_now["register"]
def stayed_run(ago, **k):
    open(os.path.join(W, "queries"), "w").close()
    ctx = {**v, reg: {"stdout": f"1 targets, 0 down\nUP AT {int(time.time()) - ago}"}}
    script = render(cmd(stayed), **ctx)
    task_env = {n: str(render(str(x), **ctx)) for n, x in (stayed.get("environment") or {}).items()}
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env(**task_env, **k))
    q = urllib.parse.unquote(open(os.path.join(W, "queries")).read())
    rng = re.search(r"up\[(\d+)s\]", q)
    return r, q, int(rng[1]) if rng else None
r, q, rng = stayed_run(130)
check("up for 130 s since then, no flap: passes, judged over those 130 s",
      (r.returncode, rng is not None and abs(rng - 130) <= 2), (0, True))
check("only the series of targets active now (a replaced pod's last scrape no flap)", "and on(job, instance) up" in q,
      True)
r, _, _ = stayed_run(30)
check("30 s since then: not yet", (r.returncode != 0, "NOT YET" in r.stdout), (True, True))
r, _, _ = stayed_run(60, FLAPPED="1")
check("a flap since then: FLAPPED", (r.returncode != 0, "FLAPPED" in r.stdout), (True, True))
reg2 = stayed["register"]
until = stayed.get("until", "")
check("not yet: retried; a flap: no retry - it fails at once; passed: done",
      [condition(until, **{reg2: {"rc": rc, "stdout": out}}) for rc, out in
       ((2, "NOT YET (30 s of 120)"), (1, "FLAPPED j i"), (0, "stayed up"))], [False, True, True])
check("a flap fails the task", condition(stayed.get("failed_when", f"{reg2}.rc != 0"),
                                         **{reg2: {"rc": 1, "stdout": "FLAPPED j i"}}), True)
print("metrics-window: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
