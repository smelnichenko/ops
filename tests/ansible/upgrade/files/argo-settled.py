#!/usr/bin/env python3
"""Wait until the Vagrant copy has settled: every Argo CD Application green and every pod ready, held for a while.

Green, per app: Synced (or allowed out of sync), Healthy, no operation running, the last operation not failed, the
sync status computed against the app's current spec (status.sync.comparedTo = spec), and - after a mirror push - on
the pushed commit. Per pod: Succeeded, or Running with every container ready. A failed kubectl call is "not green",
never "nothing to wait for".

Green must hold for --stable-polls polls in a row with no container restarting in between: one green poll can be the
moment between two crash loops, or Argo still showing the health it had before a restart. Restarts since the wait began
are listed when it ends.

Exit 0 settled, 1 not settled in --minutes (the state of everything not green is printed), 2 bad arguments.
--once evaluates one poll and exits; --apps-json/--pods-json evaluate saved `kubectl get -o json` output instead of
the cluster (both for checking this script).
"""
import argparse
import json
import os
import subprocess
import sys
import time

FAILED_PHASES = {"Failed", "Error"}
RUNNING_PHASES = {"Running", "Terminating"}


def kubectl(kubeconfig, *args):
    out = subprocess.run(["kubectl", "--kubeconfig", kubeconfig, *args], capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError(f"kubectl {' '.join(args)}: rc {out.returncode}: {out.stderr.strip()[:300]}")
    return json.loads(out.stdout)


def sources(obj):
    """The source(s) of an Application spec or of its status.sync.comparedTo, as a list."""
    return obj.get("sources") or ([obj["source"]] if obj.get("source") else [])


def app_problems(app, allowed, mirror):
    name = app["metadata"]["name"]
    spec, status = app.get("spec", {}), app.get("status", {})
    sync, health, op = status.get("sync", {}), status.get("health", {}), status.get("operationState", {})
    problems = []
    if sync.get("status") != "Synced" and name not in allowed:
        problems.append(f"sync={sync.get('status', '?')}")
    if health.get("status") != "Healthy":
        problems.append(f"health={health.get('status', '?')}")
    if op.get("phase") in RUNNING_PHASES:
        problems.append(f"operation {op['phase']}")
    if op.get("phase") in FAILED_PHASES:
        problems.append(f"last sync {op['phase']}: {op.get('message', '')[:200]}")
    if sources(sync.get("comparedTo", {})) != sources(spec):
        problems.append("compared against an older spec")
    if mirror:
        revisions = sync.get("revisions") or [sync.get("revision")]
        if any(s.get("repoURL") in mirror and r != mirror[s["repoURL"]] for s, r in zip(sources(spec), revisions)):
            problems.append("not on the pushed commit")
    return problems


def node_shutdown_leftover(status):
    """A pod the kubelet's graceful node shutdown terminated: Failed for good, its owner has started a new one. They
    stay until the pod GC threshold (ten 2026-10-04: 13 of them, 2 to 8 days old, every one replaced)."""
    return (status.get("phase") == "Failed" and status.get("reason") in ("Terminated", "NodeShutdown")
            and "node shutdown" in status.get("message", ""))


def pod_state(pod):
    """(ready, restarts) of a pod: Succeeded, or Running with every container ready; a node-shutdown leftover is no
    pod to wait for."""
    status = pod.get("status", {})
    containers = status.get("containerStatuses") or []
    restarts = sum(c.get("restartCount", 0) for c in containers)
    if status.get("phase") == "Succeeded" or node_shutdown_leftover(status):
        return True, restarts
    ready = status.get("phase") == "Running" and bool(containers) and all(c.get("ready") for c in containers)
    return ready, restarts


def evaluate(apps, pods, allowed, mirror):
    """One poll: (green, app problems by name, pods not ready, restart counts by pod uid)."""
    problems = {a["metadata"]["name"]: p for a in apps["items"] if (p := app_problems(a, allowed, mirror))}
    not_ready, restarts = [], {}
    for pod in pods["items"]:
        meta = pod["metadata"]
        ready, count = pod_state(pod)
        restarts[meta["uid"]] = (f"{meta['namespace']}/{meta['name']}", count)
        if not ready:
            not_ready.append(f"{meta['namespace']}/{meta['name']} ({pod.get('status', {}).get('phase', '?')})")
    green = len(apps["items"]) > 0 and not problems and not not_ready
    return green, problems, not_ready, restarts


def restarted(before, now):
    """Pods (by name) whose containers restarted between two polls - the same pod, or a new one with restarts."""
    return sorted(name for uid, (name, count) in now.items() if count > before.get(uid, (name, 0))[1])


def summary(apps, problems, not_ready, allowed):
    out_of_sync = sorted(n for n in allowed if n not in problems)
    return (f"apps={len(apps['items'])} not_green={len(problems)} pods_not_ready={len(not_ready)}"
            f" out_of_sync_allowed={','.join(out_of_sync) or '-'}")


def report(problems, not_ready):
    for name, p in sorted(problems.items()):
        print(f"  app {name}: {'; '.join(p)}")
    for pod in not_ready:
        print(f"  pod not ready: {pod}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kubeconfig", default="/etc/kubernetes/admin.conf")
    ap.add_argument("--minutes", type=float, default=40)
    ap.add_argument("--poll", type=float, default=10)
    ap.add_argument("--stable-polls", type=int, default=6)
    ap.add_argument("--allow-out-of-sync", default="")
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--apps-json")
    ap.add_argument("--pods-json")
    a = ap.parse_args()
    if a.stable_polls < 1 or bool(a.apps_json) != bool(a.pods_json):
        print("bad arguments", file=sys.stderr)
        return 2
    allowed = set(filter(None, a.allow_out_of_sync.split(",")))
    mirror = json.loads(os.environ.get("MIRROR_REVISIONS") or "{}")

    if a.apps_json:
        with open(a.apps_json) as f_apps, open(a.pods_json) as f_pods:
            apps, pods = json.load(f_apps), json.load(f_pods)
        green, problems, not_ready, _ = evaluate(apps, pods, allowed, mirror)
        print(("GREEN " if green else "NOT GREEN ") + summary(apps, problems, not_ready, allowed))
        report(problems, not_ready)
        return 0 if green else 1

    deadline = time.monotonic() + a.minutes * 60
    first, last, streak = None, None, 0
    while True:
        try:
            apps = kubectl(a.kubeconfig, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json")
            pods = kubectl(a.kubeconfig, "get", "pods", "-A", "-o", "json")
            green, problems, not_ready, restarts = evaluate(apps, pods, allowed, mirror)
            line = summary(apps, problems, not_ready, allowed)
        except (RuntimeError, ValueError, subprocess.TimeoutExpired) as e:
            green, problems, not_ready, restarts, line = False, {}, [], last or {}, f"poll failed: {e}"
        first = first if first is not None else restarts
        churn = restarted(last, restarts) if last is not None else []
        last = restarts
        streak = streak + 1 if green and not churn else (1 if green else 0)
        print(f"{time.strftime('%H:%M:%S')} {line} green_polls={streak}/{a.stable_polls}"
              + (f" restarted={','.join(churn)}" if churn else ""), flush=True)
        if a.once:
            report(problems, not_ready)
            return 0 if green else 1
        if streak >= a.stable_polls:
            since = restarted(first, restarts)
            print(f"ARGO SETTLED: {line}; restarted during the wait: {','.join(since) or 'none'}")
            return 0
        if time.monotonic() >= deadline:
            print(f"NOT SETTLED in {a.minutes:g} min: {line}")
            report(problems, not_ready)
            return 1
        time.sleep(a.poll)


if __name__ == "__main__":
    sys.exit(main())
