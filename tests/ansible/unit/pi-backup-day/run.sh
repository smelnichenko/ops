#!/bin/bash
# setup-pi-backups.yml's backup script as the playbook writes it, consul and rclone stubs: it runs under Consul's lock
# (the two Pis' timers one at a time); with today's success in the store it stops at once, done; with yesterday's, or
# PI_BACKUP_EVEN_TODAY=1, it goes on to the backup (here: the Consul snapshot, which the stub fails) - and the failure
# reaches the unit through the lock (Consul's exit 2; by default it exits 0). A lock held elsewhere is waited for a
# bounded time, then the run fails. Its retention, the section alone: an old copy another run purged first (the lock
# lost to a dropped Consul session) is purged all the same - the loser's purge failed it after its upload, no
# last-success; one still listed after a failed purge, or a failed listing, fails the run.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "pi-backup-day: no python3 with ansible and yaml"; exit 2; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/consul" <<'STUB'
#!/bin/bash
echo "consul $*" >> "$CALLS"
case "$1" in
  # as Consul 1.20's `consul lock [options] <prefix> <child...>`: the child through a shell; its failure is exit 2 only
  # with -child-exit-code (else 0, the unit green); a lock held elsewhere (HELD=1) is waited for -timeout, then exit 1
  # - without one, forever (here: exit 99 at once)
  lock)
    shift; code=0 timeout=
    while [[ $1 == -* ]]; do
      case "$1" in -child-exit-code | -child-exit-code=true) code=1 ;; -timeout=*) timeout=${1#*=} ;; esac; shift
    done
    shift
    if [ -n "${HELD:-}" ]; then
      [ -n "$timeout" ] || { echo "stub: waits for the lock forever" >&2; exit 99; }
      echo "Lock acquisition failed: timeout after $timeout" >&2; exit 1
    fi
    bash -c "$*" && exit 0
    [ $code = 1 ] && exit 2; exit 0 ;;
  snapshot) echo "snapshot: stub" >&2; exit 7 ;;
esac
STUB
# date: the clock at NOW (epoch seconds) when set - the schedule's firings below
cat > "$W/bin/date" <<STUB
#!/bin/bash
[ -z "\${NOW:-}" ] || exec $(command -v date) -d "@\$NOW" "\$@"
exec $(command -v date) "\$@"
STUB
cat > "$W/bin/rclone" <<'STUB'
#!/bin/bash
echo "rclone $*" >> "$CALLS"
case "$1" in
  cat) [ -n "$LAST" ] && echo "$LAST" || exit 3 ;;
  # the bucket's copies from $DIRS; LSF_FAIL_FROM=<n>: the n-th listing on fails
  lsf) n=$(grep -c "^rclone lsf" "$CALLS"); [ "$n" -lt "${LSF_FAIL_FROM:-999}" ] || exit 5; cat "$DIRS" ;;
  # PURGE=ok: gone; gone: gone, but another run's purge got there first (this one fails); stuck: fails, still there
  purge)
    d=${2##*/}
    [ "${PURGE:-ok}" = stuck ] || { grep -vx "$d/" "$DIRS" > "$DIRS.n"; mv "$DIRS.n" "$DIRS"; }
    [ "${PURGE:-ok}" = ok ] || exit 1 ;;
  rcat) cat > /dev/null ;;
esac
STUB
# the clock's sync state (NTPSynchronized): yes from the SYNCED_FROM-th look on (1: at once); sleep recorded, not slept
cat > "$W/bin/timedatectl" <<'STUB'
#!/bin/bash
echo "timedatectl $*" >> "$CALLS"
[ "$(grep -c '^timedatectl' "$CALLS")" -ge "${SYNCED_FROM:-1}" ] && echo yes || echo no
STUB
printf '#!/bin/bash\necho "sleep $*" >> "$CALLS"\n' > "$W/bin/sleep"
chmod +x "$W/bin"/*
W=$W "$PY" - <<'PY'
import datetime, os, subprocess, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
W = os.environ["W"]
task = next(t for t in yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-backups.yml"))[0]["tasks"]
            if t.get("name") == "The backup script")
script = os.path.join(W, "backup.sh")
content = render(task["ansible.builtin.copy"]["content"])
open(script, "w").write(content.replace("/var/backups/pi-tier0", os.path.join(W, "pi-tier0")))  # its work directory
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
work = [c for c in calls if c and not c.startswith(("timedatectl", "sleep"))]
check("today's success in the store: done at once, under the lock", rc == 0 and "today's backup is done" in out
      and work[0].startswith("consul lock ") and " pi-tier0-backup " in work[0]
      and not any("snapshot" in c for c in calls), (rc, out, calls))
rc, out, calls = run(yesterday)
check("yesterday's: on to the backup, its failure through the lock (exit 2)",
      rc == 2 and any(c.startswith("consul snapshot save") for c in calls), (rc, out, calls))
rc, out, calls = run("")
check("no success ever: on to the backup, its failure through the lock",
      rc == 2 and any(c.startswith("consul snapshot save") for c in calls), (rc, out, calls))
rc, out, calls = run(today, PI_BACKUP_EVEN_TODAY="1")
check("today's, but PI_BACKUP_EVEN_TODAY=1: on to the backup", rc == 2 and any("snapshot save" in c for c in calls),
      (rc, out, calls))
rc, out, calls = run(yesterday, HELD="1")
check("the lock held by the other Pi's hung run: waited a bounded time, then failed", rc == 1
      and "Lock acquisition failed" in out and not any("snapshot" in c for c in calls), (rc, out, calls))
# the clock synchronized before anything: after a boot the timer's catch-up run (Persistent) can start on the time a
# Pi kept without a battery - the day it reads, its backup's name and the retention's cutoff all wrong. Waited for a
# bounded time, then nothing done
looks = lambda calls: sum(c.startswith("timedatectl") for c in calls)
rc, out, calls = run(yesterday, SYNCED_FROM="3")
check("the clock synchronized at the third look: then on to the backup", rc == 2 and looks(calls) == 3
      and any(c.startswith("consul snapshot save") for c in calls), (rc, out, calls))
rc, out, calls = run(yesterday, SYNCED_FROM="9999")
check("the clock never synchronized: failed after its bounded wait, said so, nothing read or backed up",
      rc == 1 and "not synchronized" in out and looks(calls) == 60
      and not any(c.startswith(("consul", "rclone")) for c in calls), (rc, out, calls[:3], looks(calls)))
# the timer's firings through a year's turns (both DST changes, midsummer): each day's first run, the day before's
# success in the store, backs up; the other Pi's, 25 minutes later (it waited on the lock), finds the day done. The
# timer's spec as the playbook sets it; with no zone in it, the Pis' (Europe/Tallinn, read on both 2026-10-07)
import re, zoneinfo
spec = yaml.safe_load(open("deploy/ansible/playbooks/setup-pi-backups.yml"))[0]["vars"]["pi_backup_on_calendar"]
m = re.fullmatch(r"\*-\*-\* (\d\d):(\d\d):(\d\d)(?: (\S+))?", spec)
check(f"the timer's spec is a daily time ({spec})", bool(m), spec)
zone = zoneinfo.ZoneInfo(m[4] or "Europe/Tallinn") if m else None
fire = lambda d: datetime.datetime(d.year, d.month, d.day, int(m[1]), int(m[2]), int(m[3]), tzinfo=zone)
stamp = lambda t: t.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
days = [datetime.date(2027, mo, 1) + datetime.timedelta(n)
        for mo, span in ((3, 40), (6, 10), (10, 40)) for n in range(span)]
wrong = []
for prev, day in zip(days, days[1:]) if m else ():
    if (day - prev).days != 1:
        continue
    t = fire(day)
    rc, out, calls = run(stamp(fire(prev) + datetime.timedelta(minutes=2)), NOW=str(int(t.timestamp())))
    if not any(c.startswith("consul snapshot save") for c in calls):
        wrong.append(f"{day}: the first run at {stamp(t)} found the day done ({stamp(fire(prev))}'s success)")
    later = t + datetime.timedelta(minutes=25)
    rc, out, calls = run(stamp(t + datetime.timedelta(minutes=2)), NOW=str(int(later.timestamp())))
    if rc != 0 or any("snapshot" in c for c in calls):
        wrong.append(f"{day}: the other Pi's run at {stamp(later)} backed up again (the day's success at {stamp(t)})")
check("a year's firings: one backup a day, through both DST changes and midsummer", not wrong, wrong[:3])
# the retention, the script's own lines from the old copies' purge to last-success, after this run's upload ($ts)
lines = content.splitlines()
first = next(i for i, l in enumerate(lines) if "the old ones gone" in l)
last = next(i for i, l in enumerate(lines) if "last-success" in l and "rcat" in l)
retention = os.path.join(W, "retention.sh")
open(retention, "w").write("set -euo pipefail\n" + "\n".join(lines[first:last + 1]) + "\n")
old = [(datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d)).strftime("%Y%m%dT%H%M%SZ")
       for d in (90, 60, 0)]
def retain(**extra):
    calls, dirs = os.path.join(W, "calls"), os.path.join(W, "dirs")
    open(calls, "w").close()
    open(dirs, "w").write("".join(d + "/\n" for d in old))
    env = dict(os.environ, PATH=os.path.join(W, "bin") + ":" + os.environ["PATH"], CALLS=calls, DIRS=dirs,
               PI_BACKUP_BUCKET="b", PI_BACKUP_RETENTION_DAYS="30", PI_BACKUP_KEEP="1", ts=old[-1], **extra)
    r = subprocess.run(["bash", retention], capture_output=True, text=True, env=env)
    c = open(calls).read()
    return r.returncode, c.count("rclone purge"), "rclone rcat" in c, r.stdout + r.stderr
check("retention: the two old copies purged, then last-success", retain()[:3] == (0, 2, True), retain())
check("retention: an old copy another run purged first - purged all the same, last-success written",
      retain(PURGE="gone")[:3] == (0, 2, True), retain(PURGE="gone"))
check("retention: a copy still listed after its failed purge - fails, no last-success",
      (retain(PURGE="stuck")[0] != 0, retain(PURGE="stuck")[2]) == (True, False), retain(PURGE="stuck"))
check("retention: the listing after a failed purge failing - fails, no last-success",
      (retain(PURGE="gone", LSF_FAIL_FROM="2")[0] != 0, retain(PURGE="gone", LSF_FAIL_FROM="2")[2]) == (True, False),
      retain(PURGE="gone", LSF_FAIL_FROM="2"))
print("pi-backup-day: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
