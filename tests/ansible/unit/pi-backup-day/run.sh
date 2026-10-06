#!/bin/bash
# setup-pi-backups.yml's backup script as the playbook writes it, consul and rclone stubs: it runs under Consul's lock
# (the two Pis' timers one at a time); with today's success in the store it stops at once, done; with yesterday's, or
# PI_BACKUP_EVEN_TODAY=1, it goes on to the backup (here: the Consul snapshot, which the stub fails).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import jinja2, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import jinja2, yaml' || { echo "pi-backup-day: no python3 with jinja2 and yaml"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/consul" <<'STUB'
#!/bin/bash
echo "consul $*" >> "$CALLS"
case "$1" in
  lock) shift 2; exec bash "$@" ;;   # consul lock <prefix> <child>: the child, under the lock
  snapshot) echo "snapshot: stub" >&2; exit 7 ;;
esac
STUB
cat > "$W/bin/rclone" <<'STUB'
#!/bin/bash
case "$1" in cat) [ -n "$LAST" ] && echo "$LAST" || exit 3 ;; esac
STUB
chmod +x "$W/bin"/*
W=$W "$PY" - <<'PY'
import datetime, os, subprocess, sys
import jinja2, yaml
W = os.environ["W"]
task = next(t for t in yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-backups.yml"))[0]["tasks"]
            if t.get("name") == "The backup script")
script = os.path.join(W, "backup.sh")
open(script, "w").write(jinja2.Environment().from_string(task["ansible.builtin.copy"]["content"]).render()
                        .replace("/var/backups/pi-tier0", os.path.join(W, "pi-tier0")))  # its work directory, here
os.chmod(script, 0o700)
today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
yesterday = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).strftime("%Y%m%dT%H%M%SZ")
def run(last, **extra):
    calls = os.path.join(W, "calls")
    open(calls, "w").close()
    env = dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], CALLS=calls, LAST=last,
               PI_BACKUP_BUCKET="b", PI_BACKUP_RETENTION_DAYS="30", PI_BACKUP_KEEP="7", **extra)
    r = subprocess.run(["bash", script], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout + r.stderr, open(calls).read().split("\n")
fails = 0
def check(name, ok, detail):
    global fails
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
rc, out, calls = run(today)
check("today's success in the store: done at once, under the lock", rc == 0 and "today's backup is done" in out
      and calls[0].startswith("consul lock pi-tier0-backup") and not any("snapshot" in c for c in calls), (rc, out, calls))
rc, out, calls = run(yesterday)
check("yesterday's: on to the backup", rc != 0 and any(c.startswith("consul snapshot save") for c in calls), (rc, out, calls))
rc, out, calls = run("")
check("no success ever: on to the backup", rc != 0 and any(c.startswith("consul snapshot save") for c in calls), (rc, out, calls))
rc, out, calls = run(today, PI_BACKUP_EVEN_TODAY="1")
check("today's, but PI_BACKUP_EVEN_TODAY=1: on to the backup", rc != 0 and any("snapshot save" in c for c in calls),
      (rc, out, calls))
print("pi-backup-day: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
