#!/usr/bin/env python3
"""Wait until the Vagrant copy has settled: every Argo CD Application green and every pod ready, held for a while.

Green, per app: Synced (or allowed out of sync), Healthy, no operation running, the last operation not failed, the
sync status computed against the app's current spec (status.sync.comparedTo = spec), and - after a mirror push - on
the pushed commit. Per pod: Succeeded, or Running with every container ready. A failed kubectl call is "not green",
never "nothing to wait for".

Green must hold for --stable-polls polls in a row with no container restarting in between: one green poll can be the
moment between two crash loops, or Argo still showing the health it had before a restart. And no container may have
restarted in the last --restart-quiet seconds (300 = CrashLoopBackOff's longest back-off): a crash loop restarts within
it, so it never settles, while one restart costs at most that long. Restarts since the wait began are listed when it
ends.

--expect-apps <name,...|@file>: exactly these Applications must exist - one missing is not green (a dropped child
app otherwise "settles" by its absence), one more is not green unless its name matches --allow-extra-apps <regex>
(production's preview environments, pr-<N>-<repo>, come and go). --print-apps prints the Applications' names on a
last line, APPS <a,b>.

--restart-history <file> --step <label>: once settled, a pod (by uid) whose containers restarted during this step and
during the step before it fails the wait - a crash loop slower than --restart-quiet settles between two restarts, and
only its next step sees it again. The file (on the host this runs on) keeps each pod's restart count and the last step
it restarted in; the first call records without judging.

Exit 0 settled, 1 not settled in --minutes (the state of everything not green is printed), 2 bad arguments.
--once evaluates one poll and exits; --apps-json/--pods-json evaluate saved `kubectl get -o json` output instead of
the cluster (both for checking this script).
"""
import argparse
import datetime
import json
import os
import re
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
    """A pod the kubelet's graceful node shutdown terminated: Failed for good. They stay until the pod GC threshold
    (ten 2026-10-04: 13 of them, 2 to 8 days old, every one replaced) - one counts as settled only when its owner runs
    a ready pod again (owner_key)."""
    return (status.get("phase") == "Failed" and status.get("reason") in ("Terminated", "NodeShutdown")
            and "node shutdown" in status.get("message", ""))


def owner_key(pod):
    """The workload a pod belongs to: its controller, a ReplicaSet counted as its Deployment (the name without the
    template hash - a replacement may come from a newer ReplicaSet). None for a pod without one."""
    meta = pod["metadata"]
    owner = next((o for o in meta.get("ownerReferences", []) if o.get("controller")), None)
    if owner is None:
        return None
    name = owner["name"]
    if owner["kind"] == "ReplicaSet" and meta.get("labels", {}).get("pod-template-hash"):
        name = name[: -len(meta["labels"]["pod-template-hash"]) - 1]
    return meta["namespace"], owner["kind"] if owner["kind"] != "ReplicaSet" else "Deployment", name


def ready_now(status):
    containers = status.get("containerStatuses") or []
    return status.get("phase") == "Running" and containers and all(c.get("ready") for c in containers)


def last_restart_age(containers, now):
    """Seconds since the latest container restart of a pod (its previous run ended), None if none restarted."""
    ends = [c["lastState"]["terminated"]["finishedAt"] for c in containers
            if c.get("restartCount", 0) > 0 and c.get("lastState", {}).get("terminated", {}).get("finishedAt")]
    if not ends:
        return None
    latest = max(datetime.datetime.fromisoformat(e.replace("Z", "+00:00")) for e in ends)
    return (now - latest).total_seconds()


def pod_state(pod, now=None, quiet=0, replaced=frozenset()):
    """(ready, restarts, why) of a pod: Succeeded, or Running with every container ready and none restarted in the
    last `quiet` seconds; a node-shutdown leftover whose owner runs a ready pod again (its key in `replaced`) is no pod
    to wait for - one whose owner never replaced it is."""
    status = pod.get("status", {})
    containers = status.get("containerStatuses") or []
    restarts = sum(c.get("restartCount", 0) for c in containers)
    if status.get("phase") == "Succeeded":
        return True, restarts, ""
    if node_shutdown_leftover(status):
        key = owner_key(pod)
        return (True, restarts, "") if key in replaced else (False, restarts, "node-shutdown leftover, not replaced")
    if not ready_now(status):
        return False, restarts, status.get("phase", "?")
    age = last_restart_age(containers, now or datetime.datetime.now(datetime.timezone.utc))
    if age is not None and age < quiet:
        return False, restarts, f"restarted {age:.0f} s ago"
    return True, restarts, ""


def evaluate(apps, pods, allowed, mirror, now=None, quiet=0, expected=None, extra=None):
    """One poll: (green, app problems by name, pods not ready, restart counts by pod uid). With `expected` (a set of
    names) every one of them must exist, and no other app unless its name matches the regex `extra`."""
    problems = {a["metadata"]["name"]: p for a in apps["items"] if (p := app_problems(a, allowed, mirror))}
    if expected is not None:
        names = {a["metadata"]["name"] for a in apps["items"]}
        for name in sorted(expected - names):
            problems[name] = ["missing"]
        for name in sorted(names - expected):
            if not (extra and re.search(extra, name)):
                problems.setdefault(name, []).append("not expected")
    not_ready, restarts = [], {}
    replaced = {owner_key(p) for p in pods["items"] if ready_now(p.get("status", {}))} - {None}
    for pod in pods["items"]:
        meta = pod["metadata"]
        ready, count, why = pod_state(pod, now, quiet, replaced)
        restarts[meta["uid"]] = (f"{meta['namespace']}/{meta['name']}", count)
        if not ready:
            not_ready.append(f"{meta['namespace']}/{meta['name']} ({why})")
    green = len(apps["items"]) > 0 and not problems and not not_ready
    return green, problems, not_ready, restarts


def restart_history(path, step, pods):
    """Pods (by uid) that restarted during `step` and during the step recorded before it, by name; records this step.
    The first call (no file) records only."""
    try:
        with open(path) as f:
            hist = json.load(f)
    except FileNotFoundError:
        hist = None
    old = (hist or {}).get("pods", {})
    prev = (hist or {}).get("last_step")
    twice, now = [], {}
    for pod in pods["items"]:
        meta = pod["metadata"]
        count = sum(c.get("restartCount", 0) for c in pod.get("status", {}).get("containerStatuses") or [])
        rec = old.get(meta["uid"])
        restarted_now = hist is not None and count > (rec["count"] if rec else 0)
        last = step if restarted_now else (rec or {}).get("last_restart_step")
        if restarted_now and prev is not None and (rec or {}).get("last_restart_step") == prev:
            twice.append(f"{meta['namespace']}/{meta['name']}")
        now[meta["uid"]] = {"name": f"{meta['namespace']}/{meta['name']}", "count": count, "last_restart_step": last}
    with open(path + ".new", "w") as f:
        json.dump({"last_step": step, "pods": now}, f)
    os.replace(path + ".new", path)
    return sorted(twice), prev


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
    ap.add_argument("--restart-quiet", type=float, default=300)
    ap.add_argument("--now", help="the time to judge restarts by (ISO 8601; with --apps-json), default now")
    ap.add_argument("--allow-out-of-sync", default="")
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--apps-json")
    ap.add_argument("--pods-json")
    ap.add_argument("--expect-apps")
    ap.add_argument("--allow-extra-apps")
    ap.add_argument("--print-apps", action="store_true")
    ap.add_argument("--restart-history")
    ap.add_argument("--step")
    a = ap.parse_args()
    if a.stable_polls < 1 or bool(a.apps_json) != bool(a.pods_json) or bool(a.restart_history) != bool(a.step):
        print("bad arguments", file=sys.stderr)
        return 2
    allowed = set(filter(None, a.allow_out_of_sync.split(",")))
    mirror = json.loads(os.environ.get("MIRROR_REVISIONS") or "{}")
    expected = None
    if a.expect_apps is not None:
        names = open(a.expect_apps[1:]).read().split() if a.expect_apps.startswith("@") else a.expect_apps.split(",")
        expected = set(filter(None, names))
        if not expected:
            print("--expect-apps names no app", file=sys.stderr)
            return 2

    def finish(apps, pods):
        """The settled end: the restart history judged and recorded, the app names printed - 0, or 1 for a pod that
        restarted in two steps running."""
        rc = 0
        if a.restart_history:
            twice, prev = restart_history(a.restart_history, a.step, pods)
            if twice:
                print(f"RESTARTED IN TWO STEPS RUNNING ({prev}, {a.step}): {', '.join(twice)}")
                rc = 1
        if a.print_apps:
            print("APPS " + ",".join(sorted(x["metadata"]["name"] for x in apps["items"])))
        return rc

    if a.apps_json:
        with open(a.apps_json) as f_apps, open(a.pods_json) as f_pods:
            apps, pods = json.load(f_apps), json.load(f_pods)
        now = datetime.datetime.fromisoformat(a.now.replace("Z", "+00:00")) if a.now else None
        green, problems, not_ready, _ = evaluate(apps, pods, allowed, mirror, now, a.restart_quiet, expected,
                                                 a.allow_extra_apps)
        print(("GREEN " if green else "NOT GREEN ") + summary(apps, problems, not_ready, allowed))
        report(problems, not_ready)
        return finish(apps, pods) if green else 1

    deadline = time.monotonic() + a.minutes * 60
    first, last, streak = None, None, 0
    while True:
        try:
            apps = kubectl(a.kubeconfig, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json")
            pods = kubectl(a.kubeconfig, "get", "pods", "-A", "-o", "json")
            green, problems, not_ready, restarts = evaluate(apps, pods, allowed, mirror, None, a.restart_quiet,
                                                            expected, a.allow_extra_apps)
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
            return finish(apps, pods) if green else 1
        if streak >= a.stable_polls:
            since = restarted(first, restarts)
            print(f"ARGO SETTLED: {line}; restarted during the wait: {','.join(since) or 'none'}")
            return finish(apps, pods)
        if time.monotonic() >= deadline:
            print(f"NOT SETTLED in {a.minutes:g} min: {line}")
            report(problems, not_ready)
            return 1
        time.sleep(a.poll)


if __name__ == "__main__":
    sys.exit(main())
