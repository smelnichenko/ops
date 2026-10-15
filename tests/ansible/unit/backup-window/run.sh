#!/bin/bash
# scripts/upgrade-production.py backup_window_problems: a CNPG backup running, or one scheduled within the window -
# merge and playbooks refuse then: 42-kubernetes-1.35's API server restarted during the hourly backup (2026-10-15), the
# Backup stayed running for ever, CNPG refused every backup after it and PostgresBackupFailed paged. Ended backups, a
# suspended schedule, one due after the window or past already: no problem; kubectl's answer unread: a problem.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY_BW'
import datetime, importlib.machinery, importlib.util, json, subprocess
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
backup = lambda name, phase: {"kind": "Backup", "metadata": {"namespace": "p", "name": name},
                              "status": ({"phase": phase} if phase else {})}
sched = lambda name, minutes, suspend=False: {"kind": "ScheduledBackup", "metadata": {"namespace": "p", "name": name},
                                              "spec": {"suspend": suspend}, "status": {"nextScheduleTime": iso(minutes)}}
got = lambda *items: m.backup_window_problems({"items": list(items)}, now=NOW)
check("ended backups and a schedule an hour off: nothing", got(backup("a", "completed"), backup("b", "failed"),
                                                              sched("daily", 60)), [])
check("a backup running: refused, named", [p.split(":")[0] for p in got(backup("r", "running"))], ["p/r"])
check("  one not started yet (no phase): refused too", len(got(backup("n", None))), 1)
check("a scheduled backup due in 5 minutes: refused, its time said",
      ["09:05:00Z" in p for p in got(sched("daily", 5))], [True])
check("  due just past the window (16 minutes): nothing", got(sched("daily", 16)), [])
check("  due at the window's edge (15 minutes): refused", len(got(sched("daily", 15))), 1)
check("  its time past already (CNPG has not moved it yet): nothing", got(sched("daily", -1)), [])
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
# merge and playbooks ask it before they change anything
src = open("scripts/upgrade-production.py").read()
body = lambda fn: src[src.index(f"\ndef {fn}("):src.index("\ndef ", src.index(f"\ndef {fn}(") + 1)]
check("merge and playbooks refuse on it, beside the finished pods",
      ["finished_pod_problems() + backup_window_problems()" in body(fn).replace("\n", " ").replace("               ", "")
       or "+ backup_window_problems()" in body(fn) for fn in ("merge", "playbooks")], [True, True])
print("backup-window: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
raise SystemExit(1 if fails else 0)
PY_BW
