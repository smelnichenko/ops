#!/usr/bin/env python3
"""production-report.py - the hourly report's facts, read-only: production's alerts (Alertmanager's active ones, each
with its subject, start and silence; Prometheus's pending ones by name), its readiness (Running pods not all ready,
pods Pending, crash-looping or still initialising - a finished pod (Succeeded, Failed: the ones a node's shutdown left)
not counted; Argo applications not Synced and Healthy) and the open pull requests of the org's live repos.

A part not read says NOT READ and the exit is 1 - never a quiet "all well" from an answer that never came.

Usage: scripts/production-report.py
Env:   RENOVATE_TOKEN (the bot's - the pull requests read); REPORT_SSH (default sm@192.168.11.2 - ten);
       UPGRADE_FORGEJO_URL (default https://git.pmon.dev/api/v1)
Exit:  0 every part read; 1 a part not read
"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

SSH = os.environ.get("REPORT_SSH", "sm@192.168.11.2")
API = os.environ.get("UPGRADE_FORGEJO_URL", "https://git.pmon.dev/api/v1").rstrip("/")
AM = "kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -c alertmanager -- wget -qO- "
PENDING = urllib.parse.quote('ALERTS{alertstate="pending"}')


def remote(command):
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", SSH, command],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[-200:] or f"exit {r.returncode}")
    return json.loads(r.stdout)


def alerts():
    lines = []
    for a in remote(AM + "'http://localhost:9093/api/v2/alerts?active=true'"):
        lab, st = a["labels"], a.get("status") or {}
        about = lab.get("unit") or lab.get("source") or lab.get("namespace") or lab.get("instance") or ""
        lines.append(f"- {lab.get('alertname')} [{lab.get('severity')}] {about} since {a.get('startsAt', '')[:16]}Z, "
                     f"{st.get('state')}{', silenced' if st.get('silencedBy') else ''}")
    lines.append(f"{len(lines)} active")
    result = remote(AM + f"'http://schnappy-prometheus.schnappy-infra.svc:9090/api/v1/query?query={PENDING}'")["data"]["result"]
    names = sorted({x["metric"].get("alertname", "?") for x in result})
    lines.append("pending in Prometheus: " + (", ".join(names) or "none"))
    return lines


def not_ready(pods):
    n = 0
    for p in pods["items"]:
        status = p.get("status") or {}
        phase = status.get("phase")
        if phase in ("Succeeded", "Failed"):
            continue
        cs = status.get("containerStatuses") or []  # a waiting container (CrashLoopBackOff, creating) is never ready
        if phase != "Running" or not cs or not all(c.get("ready") for c in cs):
            n += 1
    return n


def readiness():
    pods = remote("kubectl get pods -A -o json")
    apps = remote("kubectl get applications -n argocd -o json")
    off = sum(1 for a in apps["items"] if ((a.get("status") or {}).get("sync") or {}).get("status") != "Synced"
              or ((a.get("status") or {}).get("health") or {}).get("status") != "Healthy")
    return [f"not-ready pods {not_ready(pods)}, argo apps off {off}"]


def get(path):
    req = urllib.request.Request(API + path)
    req.add_unredirected_header("Authorization", "token " + os.environ.get("RENOVATE_TOKEN", ""))  # never across a redirect
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def pull_requests():
    repos = [r for r in get("/orgs/schnappy/repos?limit=50") if not r.get("archived")]
    lines = []
    for r in repos:
        for p in get(f"/repos/{r['full_name']}/pulls?state=open&limit=50"):
            lines.append(f"{r['name']} #{p['number']} {p['user']['login']} {p['created_at'][:16]} {p['title'][:90]}")
    return lines + [f"{len(repos)} repos, {len(lines)} open PRs"]


def main():
    ok = True
    for title, part in (("ALERTS", alerts), ("READINESS", readiness), ("PULL REQUESTS", pull_requests)):
        print(f"== {title}")
        try:
            print("\n".join(part()))
        except (RuntimeError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
            print(f"NOT READ: {e}")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
