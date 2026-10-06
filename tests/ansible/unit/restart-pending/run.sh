#!/bin/bash
# tasks/restart-pending.yml's shell as the playbooks hold it (the stamp directory moved, systemctl a stub for the start
# time): with a stamp, the content decides - equal is current, different is pending, a file written with the clock
# ahead (mtime in the future) is current while its content is what was loaded; with no stamp yet, the clock once - a
# file newer than the start is pending, an older one current. Its second line is the content's sha256.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "restart-pending: no python3 with jinja2 and yaml"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin" "$W/stamps"
cat > "$W/bin/systemctl" <<'STUB'
#!/bin/sh
echo "$STARTED"
STUB
chmod +x "$W/bin/systemctl"
W=$W "$PY" - <<'PY'
import hashlib, os, shlex, subprocess, sys, time
import jinja2, yaml
W = os.environ["W"]
task = yaml.safe_load(open("deploy/ansible/playbooks/tasks/restart-pending.yml"))[0]
env = jinja2.Environment()
env.filters["quote"] = shlex.quote
conf, unit = os.path.join(W, "svc.hcl"), os.path.join(W, "svc.service")
open(conf, "w").write("a = 1\n"); open(unit, "w").write("[Service]\n")
script = env.from_string(task["ansible.builtin.shell"]["cmd"]).render(
    loaded_service="svc", loaded_files=[conf, unit]).replace("/var/lib/config-loaded", os.path.join(W, "stamps"))
sha = lambda: hashlib.sha256(open(conf, "rb").read() + open(unit, "rb").read()).hexdigest()
stamp = os.path.join(W, "stamps", "svc.sha256")
def run(started):
    r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                       env=dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], STARTED=started))
    return r.returncode, r.stdout.split()
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f": got {got}, want {want}"))
long_ago, later = "Mon 2026-10-05 10:00:00 UTC", "Fri 2026-10-30 10:00:00 UTC"
check("no stamp, the files newer than the start: pending (the clock, once)", run(long_ago), (0, ["pending", sha()]))
check("no stamp, the files older than the start: current", run(later), (0, ["current", sha()]))
open(stamp, "w").write(sha() + "\n")
check("the stamp the files' content: current", run(long_ago), (0, ["current", sha()]))
future = time.time() + 30 * 86400
os.utime(conf, (future, future))
check("a file written with the clock ahead, its content loaded: current", run(long_ago), (0, ["current", sha()]))
open(conf, "w").write("a = 2\n")
check("the content changed since it was loaded: pending, even started later", run(later), (0, ["pending", sha()]))
print("restart-pending: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
