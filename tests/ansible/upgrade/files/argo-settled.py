#!/usr/bin/env python3
"""Wait until the Vagrant copy has settled: every Argo CD Application green and every pod ready, held for a while.

Green, per app: Synced (or allowed out of sync), Healthy, no operation running, the last operation not failed, the
sync status computed against the app's current spec (status.sync.comparedTo = spec), and - after a mirror push - on
the pushed commit. Per pod: Succeeded, or Running with every container ready; a failed attempt of a Job that a later
attempt completed is no pod to wait for. No app or no pod at all is not green. A failed kubectl call is "not green",
never "nothing to wait for".

Green must hold for --stable-polls polls in a row with no container restarting in between: one green poll can be the
moment between two crash loops, or Argo still showing the health it had before a restart. And no container may have
restarted in the last --restart-quiet seconds (300 = CrashLoopBackOff's longest back-off): a crash loop restarts within
it, so it never settles, while one restart costs at most that long. Restarts since the wait began are listed when it
ends. --restarted-since <ISO time>: no container may have restarted at or after that time either (production's
deciding check: nothing restarted since its first green check, however long ago).

--expect-apps <name,...|@file>: exactly these Applications must exist - one missing is not green (a dropped child
app otherwise "settles" by its absence), one more is not green unless its name matches --allow-extra-apps <regex>
(production's preview environments, pr-<N>-<repo>, come and go with their pull requests: such an app's state is not
looked at either). --ignore-namespaces <regex>: the pods there are not looked at (the preview environments'
schnappy-pr-<N>: one starting during a production settle is no part of production). --print-apps prints the
Applications' names on a last line, APPS <a,b>.

--restart-history <file> --step <label>: once settled, a pod (by uid) whose containers restarted during this step and
during the step before it fails the wait - a crash loop slower than --restart-quiet settles between two restarts, and
only its next step sees it again. The file (on the host this runs on) keeps the steps in the order they were recorded,
and each pod's restart count and the steps it restarted in; the first call records without judging. The facts stay:
a pod judged to restart in two steps running is judged so again by the step's next call, and a step recorded again
compares with the step before it, not with itself. --restarts-expected: this step's own change restarts the control
plane (a kubeadm upgrade - every controller holding a leader lease restarts with the API server): its restarts are
recorded, not judged - two such steps in a row are no crash loop - and the next step judges its own restarts against
them: a pod restarting there too is a crash loop, caught a step after.

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


# a source's own data, kept as written on both sides: false and 0 are values there, not Go's omitted fields
LITERAL = {"valuesObject", "values"}


def without_empty(value):
    """A spec without the empty fields Go's omitempty leaves out of comparedTo ({}, [], "", None, false, 0): Argo CD
    3.5's spec keeps directory.jsonnet: {}, its comparedTo has none - the same spec, compared literally never equal.
    Helm's values (LITERAL) are compared as they are."""
    if isinstance(value, dict):
        kept = {k: (v if k in LITERAL else without_empty(v)) for k, v in value.items()}
        return {k: v for k, v in kept.items() if k in LITERAL or not empty(v)}
    if isinstance(value, list):
        return [without_empty(v) for v in value]
    return value


def empty(value):
    if isinstance(value, bool):
        return value is False
    if isinstance(value, (int, float)):
        return value == 0
    return value is None or (isinstance(value, (dict, list, str)) and len(value) == 0)


def app_problems(app, allowed, mirror):
    name = app["metadata"]["name"]
    spec, status = app.get("spec") or {}, app.get("status") or {}
    sync, health, op = status.get("sync") or {}, status.get("health") or {}, status.get("operationState") or {}
    problems = []
    if sync.get("status") != "Synced" and name not in allowed:
        problems.append(f"sync={sync.get('status', '?')}")
    if health.get("status") != "Healthy":
        problems.append(f"health={health.get('status', '?')}")
    if op.get("phase") in RUNNING_PHASES:
        problems.append(f"operation {op['phase']}")
    if op.get("phase") in FAILED_PHASES:
        problems.append(f"last sync {op['phase']}: {(op.get('message') or '')[:200]}")
    if without_empty(sources(sync.get("comparedTo") or {})) != without_empty(sources(spec)):
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


def iso(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))


def last_restart(containers):
    """When the latest container restart of a pod happened (its previous run ended), None if none restarted."""
    ends = [c["lastState"]["terminated"]["finishedAt"] for c in containers
            if c.get("restartCount", 0) > 0 and ((c.get("lastState") or {}).get("terminated") or {}).get("finishedAt")]
    return max(iso(e) for e in ends) if ends else None


def pod_state(pod, now=None, quiet=0, replaced=frozenset(), since=None, completed=frozenset()):
    """(ready, restarts, why) of a pod: Succeeded, or Running with every container ready and none restarted in the
    last `quiet` seconds nor at or after `since`; a node-shutdown leftover whose owner runs a ready pod again (its key
    in `replaced`) is no pod to wait for - one whose owner never replaced it is; a failed attempt of a Job a later
    attempt completed (its key in `completed`) is none either."""
    status = pod.get("status") or {}
    containers = status.get("containerStatuses") or []
    restarts = sum(c.get("restartCount", 0) for c in containers)
    if status.get("phase") == "Succeeded":
        return True, restarts, ""
    if node_shutdown_leftover(status):
        key = owner_key(pod)
        return (True, restarts, "") if key in replaced else (False, restarts, "node-shutdown leftover, not replaced")
    if status.get("phase") == "Failed" and owner_key(pod) in completed:
        return True, restarts, ""
    if not ready_now(status):
        return False, restarts, status.get("phase", "?")
    latest = last_restart(containers)
    if latest is not None:
        age = ((now or datetime.datetime.now(datetime.timezone.utc)) - latest).total_seconds()
        if age < quiet:
            return False, restarts, f"restarted {age:.0f} s ago"
        if since is not None and latest >= since:
            return False, restarts, f"restarted at {latest.isoformat()}, after {since.isoformat()}"
    return True, restarts, ""


def without(pods, namespaces):
    """The pods outside the namespaces matching the regex `namespaces` (all of them without one)."""
    if not namespaces:
        return pods
    return {**pods, "items": [p for p in pods["items"] if not re.search(namespaces, p["metadata"]["namespace"])]}


def evaluate(apps, pods, allowed, mirror, now=None, quiet=0, expected=None, extra=None, since=None):
    """One poll: (green, app problems by name, pods not ready, restart counts by pod uid). With `expected` (a set of
    names) every one of them must exist, and no other app unless its name matches the regex `extra`."""
    problems = {a["metadata"]["name"]: p for a in apps["items"]
                if not (extra and re.search(extra, a["metadata"]["name"])) and (p := app_problems(a, allowed, mirror))}
    if expected is not None:
        names = {a["metadata"]["name"] for a in apps["items"]}
        for name in sorted(expected - names):
            problems[name] = ["missing"]
        for name in sorted(names - expected):
            if not (extra and re.search(extra, name)):
                problems.setdefault(name, []).append("not expected")
    not_ready, restarts = [], {}
    replaced = {owner_key(p) for p in pods["items"] if ready_now(p.get("status") or {})} - {None}
    completed = {k for p in pods["items"] if (p.get("status") or {}).get("phase") == "Succeeded"
                 and (k := owner_key(p)) is not None and k[1] == "Job"}
    for pod in pods["items"]:
        meta = pod["metadata"]
        ready, count, why = pod_state(pod, now, quiet, replaced, since, completed)
        restarts[meta["uid"]] = (f"{meta['namespace']}/{meta['name']}", count)
        if not ready:
            not_ready.append(f"{meta['namespace']}/{meta['name']} ({why})")
    green = len(apps["items"]) > 0 and len(pods["items"]) > 0 and not problems and not not_ready
    return green, problems, not_ready, restarts


def restart_history(path, step, pods, expected=False):
    """Pods (by uid) that restarted during `step` and during the step recorded before it, by name, and that step;
    records this step. The first call (no file) records only; with `expected` (the step restarts the control plane)
    nothing is judged - its restarts are recorded, and the next step judges against them. A file of the earlier form
    (last_step, each pod's last_restart_step) is read as its one or two steps."""
    try:
        with open(path) as f:
            hist = json.load(f)
    except FileNotFoundError:
        hist = None
    steps = list((hist or {}).get("steps") or ([hist["last_step"]] if hist and hist.get("last_step") else []))
    if step not in steps:
        steps.append(step)
    prev = steps[steps.index(step) - 1] if steps.index(step) > 0 else None
    twice, now = [], {}
    for pod in pods["items"]:
        meta = pod["metadata"]
        count = sum(c.get("restartCount", 0) for c in (pod.get("status") or {}).get("containerStatuses") or [])
        rec = ((hist or {}).get("pods") or {}).get(meta["uid"]) or {}
        restart_steps = list(rec.get("restart_steps") or ([rec["last_restart_step"]] if rec.get("last_restart_step")
                                                          else []))
        if hist is not None and count > rec.get("count", 0) and step not in restart_steps:
            restart_steps.append(step)
        if not expected and step in restart_steps and prev is not None and prev in restart_steps:
            twice.append(f"{meta['namespace']}/{meta['name']}")
        now[meta["uid"]] = {"name": f"{meta['namespace']}/{meta['name']}", "count": count,
                            "restart_steps": restart_steps[-3:]}
    with open(path + ".new", "w") as f:
        json.dump({"steps": steps, "pods": now}, f)
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
    ap.add_argument("--ignore-namespaces")
    ap.add_argument("--print-apps", action="store_true")
    ap.add_argument("--restart-history")
    ap.add_argument("--step")
    ap.add_argument("--restarts-expected", action="store_true")
    ap.add_argument("--restarted-since", help="no container restarted at or after this time (ISO 8601)")
    a = ap.parse_args()
    if a.stable_polls < 1 or bool(a.apps_json) != bool(a.pods_json) or bool(a.restart_history) != bool(a.step):
        print("bad arguments", file=sys.stderr)
        return 2
    allowed = set(filter(None, a.allow_out_of_sync.split(",")))
    since = iso(a.restarted_since) if a.restarted_since else None
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
            print(f"RESTART HISTORY: step {a.step}" + (" (restarts expected: recorded, not judged)"
                                                       if a.restarts_expected else ""))
            twice, prev = restart_history(a.restart_history, a.step, pods, a.restarts_expected)
            if twice:
                print(f"RESTARTED IN TWO STEPS RUNNING ({prev}, {a.step}): {', '.join(twice)}")
                rc = 1
        if a.print_apps:
            print("APPS " + ",".join(sorted(x["metadata"]["name"] for x in apps["items"])))
        return rc

    if a.apps_json:
        with open(a.apps_json) as f_apps, open(a.pods_json) as f_pods:
            apps, pods = json.load(f_apps), without(json.load(f_pods), a.ignore_namespaces)
        now = iso(a.now) if a.now else None
        green, problems, not_ready, _ = evaluate(apps, pods, allowed, mirror, now, a.restart_quiet, expected,
                                                 a.allow_extra_apps, since)
        print(("GREEN " if green else "NOT GREEN ") + summary(apps, problems, not_ready, allowed))
        report(problems, not_ready)
        return finish(apps, pods) if green else 1

    deadline = time.monotonic() + a.minutes * 60
    first, last, streak = None, None, 0
    while True:
        try:
            apps = kubectl(a.kubeconfig, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json")
            pods = without(kubectl(a.kubeconfig, "get", "pods", "-A", "-o", "json"), a.ignore_namespaces)
            green, problems, not_ready, restarts = evaluate(apps, pods, allowed, mirror, None, a.restart_quiet,
                                                            expected, a.allow_extra_apps, since)
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
