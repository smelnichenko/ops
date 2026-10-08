#!/bin/bash
# tasks/restart-pending.yml's shell as the playbooks hold it (the stamp directory moved, systemctl a stub for the start
# time), rendered by Ansible's templar: with a stamp, the content decides - equal is current, different is pending, a
# file written with the clock ahead (mtime in the future) is current while its content is what was loaded; with no
# stamp yet, the clock once - a file newer than the start is pending, an older one current; a service this run started
# from inactive runs the files as they are - current, a stale stamp notwithstanding (it restarted a service it had just
# started). Its second line is the content's sha256.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "restart-pending: no python3 with ansible and yaml"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin" "$W/stamps"
cat > "$W/bin/systemctl" <<'STUB'
#!/bin/sh
echo "$STARTED"
STUB
chmod +x "$W/bin/systemctl"
W=$W "$PY" - <<'PY'
import hashlib, os, subprocess, sys, time
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
task = yaml.safe_load(open("deploy/ansible/playbooks/tasks/restart-pending.yml"))[0]
conf, unit = os.path.join(W, "svc.hcl"), os.path.join(W, "svc.service")
open(conf, "w").write("a = 1\n"); open(unit, "w").write("[Service]\n")
def script(**extra):  # the task's shell for the service; extra: the playbook's optional vars
    return render(task["ansible.builtin.shell"]["cmd"], loaded_service="svc", loaded_files=[conf, unit],
                  **extra).replace("/var/lib/config-loaded", os.path.join(W, "stamps"))
sha = lambda: hashlib.sha256(open(conf, "rb").read() + open(unit, "rb").read()).hexdigest()
stamp = os.path.join(W, "stamps", "svc.sha256")
def run(started, **extra):
    r = subprocess.run(["bash", "-c", script(**extra)], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], STARTED=started))
    return r.returncode, r.stdout.split()
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f": got {got}, want {want}"))
# every time relative to now - a fixed date aged the test out (the files are written as it runs): the files a day old,
# the service started two days ago (before them) or twelve hours ago (after them)
day = 86400
for f in (conf, unit):
    os.utime(f, (time.time() - day, time.time() - day))
at = lambda seconds_ago: time.strftime("%a %Y-%m-%d %H:%M:%S UTC", time.gmtime(time.time() - seconds_ago))
long_ago, later = at(2 * day), at(day / 2)
check("no stamp, the files newer than the start: pending (the clock, once)", run(long_ago), (0, ["pending", sha()]))
check("no stamp, the files older than the start: current", run(later), (0, ["current", sha()]))
open(stamp, "w").write(sha() + "\n")
check("the stamp the files' content: current", run(long_ago), (0, ["current", sha()]))
future = time.time() + 30 * 86400
os.utime(conf, (future, future))
check("a file written with the clock ahead, its content loaded: current", run(long_ago), (0, ["current", sha()]))
open(conf, "w").write("a = 2\n")
check("the content changed since it was loaded: pending, even started later", run(later), (0, ["pending", sha()]))
check("not started by this run (running already), the stamp stale: pending",
      run(later, loaded_started_now=False), (0, ["pending", sha()]))
check("started by this run from inactive, the stamp stale: current - it runs these files",
      run(later, loaded_started_now=True), (0, ["current", sha()]))
# each playbook's loaded_started_now reads a register of its own service's systemd task (the status as that task found
# it) - a name that matches none is undefined, its default "running", and the answer by the stamp again
import glob, re
def tasks_of(node):
    if isinstance(node, list):
        for x in node:
            yield from tasks_of(x)
    elif isinstance(node, dict):
        yield node
        for k in ("tasks", "pre_tasks", "post_tasks", "handlers", "block", "rescue", "always"):
            yield from tasks_of(node.get(k))
def as_run(f):
    """A playbook's tasks as run: a statically imported task file's in its place."""
    out = []
    for t in tasks_of(yaml.safe_load(open(f))):
        ref = t.get("ansible.builtin.import_tasks")
        out += list(tasks_of(yaml.safe_load(open(os.path.join(os.path.dirname(f), str(ref)))))) if ref else [t]
    return out
def start_reg(expr):
    return re.search(r"\b(_\w+)\b", expr).group(1)
users, exprs = {}, {}
for f in sorted(glob.glob("deploy/ansible/playbooks/*.yml")):
    ts = as_run(f)
    for t in ts:
        v = t.get("vars") or {}
        if "restart-pending" in str(t.get("ansible.builtin.include_tasks", "")) and "loaded_started_now" in v:
            reg = start_reg(v["loaded_started_now"])
            svc = [(t2.get("ansible.builtin.systemd") or t2.get("ansible.builtin.systemd_service") or {}).get("name")
                   for t2 in ts if t2.get("register") == reg]
            users[(os.path.basename(f), v["loaded_service"])] = svc
            exprs[(os.path.basename(f), v["loaded_service"])] = v["loaded_started_now"]
# (setup-patroni's Keycloak: it starts no Keycloak - the restart's, through tasks/keycloak-restart.yml, takes the
# default: not started now)
check("loaded_started_now in consul, keepalived, patroni, vault, keycloak: each its own service's systemd register",
      users, {**{(f"setup-{n}.yml", s_): [s_] for n, s_ in (("consul", "consul"), ("keepalived", "keepalived"),
                                                           ("patroni", "patroni"), ("vault-pi", "vault"),
                                                           ("pi-services", "keycloak"))},
              ("setup-patroni.yml", "keycloak"): []})
# and each one's expression, as Ansible renders it, for what its start task can find: started now from inactive or
# failed; not when it ran already (active, activating), nor when the status is not there (a default of "running")
STATES = (("inactive", True), ("failed", True), ("active", False), ("activating", False), (None, False))
for f, svc_ in sorted(exprs):
    expr = exprs[(f, svc_)]
    reg = start_reg(expr)
    got = [render(expr, **{reg: {"status": {"ActiveState": st}} if st else {}}) for st, _ in STATES]
    check(f"{f} ({svc_}): started now - inactive, failed: yes; active, activating, no status: no", got,
          [w for _, w in STATES])
print("restart-pending: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
