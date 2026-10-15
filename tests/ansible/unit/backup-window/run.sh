#!/bin/bash
# scripts/upgrade-production.py backup_window_problems: a CNPG backup running, or one scheduled within the window -
# merge and playbooks refuse then: 42-kubernetes-1.35's API server restarted during the hourly backup (2026-10-15), the
# Backup stayed running for ever, CNPG refused every backup after it and PostgresBackupFailed paged. Ended backups
# (CNPG's terminal phases, an invalid definition), a suspended schedule, one due after the window, or past and made
# already: no problem. One due within the last minutes and not made: a problem. A Backup running past the stuck limit:
# said stuck, its delete named. kubectl's answer unread: a problem.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY_BW'
import datetime, importlib.machinery, importlib.util, json, re, subprocess
L = importlib.machinery.SourceFileLoader("up", "scripts/upgrade-production.py")
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("up", L))
L.exec_module(m)
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


NOW = datetime.datetime(2026, 10, 15, 9, 0, 0, tzinfo=datetime.timezone.utc)
iso = lambda minutes: (NOW + datetime.timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
backup = lambda name, phase, started=None, made=None, cluster="pg": {
    "kind": "Backup", "metadata": {"namespace": "p", "name": name, **({"creationTimestamp": iso(made)} if made is not None
                                                                     else {})},
    "spec": {"cluster": {"name": cluster}},
    "status": ({"phase": phase} if phase else {}) | ({"startedAt": iso(started)} if started is not None else {})}
sched = lambda name, minutes, suspend=False: {"kind": "ScheduledBackup", "metadata": {"namespace": "p", "name": name},
                                              "spec": {"suspend": suspend, "cluster": {"name": "pg"}},
                                              "status": {"nextScheduleTime": iso(minutes)}}
got = lambda *items: m.backup_window_problems({"items": list(items)}, now=NOW)
W, LATE, STUCK = m.BACKUP_WINDOW_MINUTES, m.BACKUP_LATE_MINUTES, m.BACKUP_STUCK_HOURS * 60
check("the limits: a 90-minute window, 10 minutes late, 3 hours stuck (platform's PostgresBackupStuck)",
      (W, LATE, STUCK), (90, 10, 180))
check("ended backups and a schedule past the window: nothing",
      got(backup("a", "completed"), backup("b", "failed"), backup("c", "walArchivingFailing"),
          backup("d", "invalid backup definition: no cluster"), sched("daily", W + 1)), [])
check("a backup running: refused, named", [p.split(":")[0] for p in got(backup("r", "running"))], ["p/r"])
check("  one not started yet (no phase): refused too", len(got(backup("n", None))), 1)
check("  running for less than the stuck limit: wait for it, no delete named",
      ["wait for its end" in p and "delete" not in p for p in got(backup("r", "running", started=-(STUCK - 1)))], [True])
check("  running past the stuck limit: stuck, its delete named",
      ["stuck" in p and "kubectl -n p delete backup r" in p for p in got(backup("r", "running", started=-(STUCK + 1)))],
      [True])
check("  not started, made past the stuck limit: stuck too",
      ["stuck" in p for p in got(backup("n", None, made=-(STUCK + 1)))], [True])
check("a scheduled backup due in 5 minutes: refused, its time said",
      ["09:05:00Z" in p for p in got(sched("daily", 5))], [True])
check("  due at the window's edge: refused", len(got(sched("daily", W))), 1)
check("  due just past the window: nothing", got(sched("daily", W + 1)), [])
check("  due a minute ago, no Backup made: refused, said late",
      ["was due" in p and "not made yet" in p for p in got(sched("daily", -1))], [True])
check("  due a minute ago, its Backup made: nothing", got(sched("daily", -1), backup("x", "completed", made=-1)), [])
check("  due a minute ago, only another cluster's Backup made since: refused",
      len(got(sched("daily", -1), backup("x", "completed", made=-1, cluster="other"))), 1)
check("  due a minute ago, only an older Backup: refused",
      len(got(sched("daily", -1), backup("x", "completed", made=-60))), 1)
check("  due past the late limit: nothing (CNPG moved on or never will)", got(sched("daily", -(LATE + 1))), [])
check("  suspended: nothing", got(sched("daily", 5, suspend=True)), [])
check("  a time unread: refused, saying so", ["unread" in p for p in
      m.backup_window_problems({"items": [{"kind": "ScheduledBackup", "metadata": {"namespace": "p", "name": "x"},
                                           "status": {"nextScheduleTime": "soon"}}]}, now=NOW)], [True])
# read on ten: kubectl's answer unread is a problem, never "no backup"
m.ten = lambda *a, **k: subprocess.CompletedProcess(a, 1, "", "the server is currently unable to handle the request")
m.ten_clock = lambda: NOW
check("kubectl failing: a problem, its error said", [p.startswith("production's CNPG backups not read") for p in
                                                     m.backup_window_problems()], [True])
m.ten = lambda *a, **k: subprocess.CompletedProcess(a, 0, "not json", "")
check("  an answer not JSON: a problem", len(m.backup_window_problems()), 1)
# the base-backup playbook's "still running" and its include's wait end on the same phases as the runner
pb = open("deploy/ansible/playbooks/postgres-base-backup.yml").read()
tk = open("deploy/ansible/playbooks/tasks/cnpg-backup.yml").read()
# the quoted names in the "in (...)" / "in [...]" that lists "completed"
ended = lambda text: next(tuple(re.findall(r"\w+", g)) for g in re.findall(r"in [(\[]([^)\]]*)[)\]]", text)
                          if "completed" in g)
check("the playbook's and its include's ended phases are the runner's, an invalid definition ended in each",
      (ended(pb), ended(tk), "startswith(\"invalid\")" in pb, "startswith('invalid')" in tk),
      (m.BACKUP_ENDED_PHASES, m.BACKUP_ENDED_PHASES, True, True))
# merge and playbooks ask it before they change anything
src = open("scripts/upgrade-production.py").read()
body = lambda fn: src[src.index(f"\ndef {fn}("):src.index("\ndef ", src.index(f"\ndef {fn}(") + 1)]
check("merge and playbooks refuse on it, beside the finished pods",
      ["finished_pod_problems() + backup_window_problems()" in body(fn).replace("\n", " ").replace("               ", "")
       or "+ backup_window_problems()" in body(fn) for fn in ("merge", "playbooks")], [True, True])
print("backup-window: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
raise SystemExit(1 if fails else 0)
PY_BW
