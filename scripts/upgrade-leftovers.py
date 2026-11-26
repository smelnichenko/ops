#!/usr/bin/env python3
"""The objects a chart release dropped, deleted where Argo CD leaves them behind.

Argo CD prunes nothing here (prune is off everywhere): an object a chart stops shipping stays on the cluster, tracked
by its app as needing pruning, and the app stays OutOfSync, so the settle checks after a change never pass. The first
case: scylla-operator v1.23.0 dropped three CRDs and two ClusterRoles, and the data-operators unit stayed red on the
copy (2026-11-26). Which objects may go is declared per app in scripts/upgrade-leftovers.json, each entry with the
release that dropped them and where that is said.

For each declared app whose Application file the change moves (git diff <base>...<head> in infra's
clusters/production/argocd/apps): wait until Argo runs it on the head's chart versions - its spec's targetRevisions
the head's, compared against that spec, no operation running, nothing out of sync but what needs pruning - then delete
each declared object Argo marks as needing pruning for that app. A CustomResourceDefinition goes only while no object
of its kind exists anywhere (deleting it would delete them too): one that has any refuses the app, and nothing of the
app's is deleted. An object Argo still ships is not touched; one that needs pruning but is not declared is left and
said - the settle check still fails on it, and names it.

Usage: scripts/upgrade-leftovers.py --on ten|copy --base <rev> --head <rev> [--minutes N] [--poll S]
  ten   production, through ssh (BatchMode)
  copy  the Vagrant copy's node (kubeadm) as root with the admin kubeconfig, through vagrant ssh (plain ssh with
        VAGRANT_SSH_CONFIG)
  The revisions are infra's (the checkout beside ops, or UPGRADE_LEFTOVERS_INFRA).
Exit 0: nothing declared moved, or each declared leftover deleted; 1: not reached in time, refused or failed (said);
2: usage.
"""
import argparse
import json
import os
import shlex
import subprocess
import sys
import time

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS_DIR = "clusters/production/argocd/apps/"
CRD = "CustomResourceDefinition"
COPY_KUBECTL = "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf"
BUSY = ("Running", "Terminating")


def say(text):
    print(f"LEFTOVERS {text}", flush=True)


def git(infra, *args):
    r = subprocess.run(["git", "-C", infra, *args], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120)
    return r.returncode, r.stdout


def chart_revisions(spec):
    """The targetRevisions of an Application's chart sources, sorted - what "on the new version" is judged by."""
    sources = spec.get("sources") or ([spec["source"]] if spec.get("source") else [])
    return sorted(str(s.get("targetRevision", "")) for s in sources if s.get("chart"))


def moved_apps(infra, base, head, declared):
    """{app: the head's chart revisions} for each declared app whose Application file the change moves."""
    rc, out = git(infra, "diff", "--name-only", f"{base}...{head}", "--", APPS_DIR)
    if rc != 0:
        raise RuntimeError(f"git diff {base}...{head} in {infra} failed")
    moved = {}
    for path in filter(None, out.splitlines()):
        rc, text = git(infra, "show", f"{head}:{path}")
        if rc != 0:
            continue  # gone at the head: its app is root's to remove, not a chart's leftover
        for doc in yaml.safe_load_all(text):
            if isinstance(doc, dict) and doc.get("kind") == "Application":
                name = (doc.get("metadata") or {}).get("name")
                if name in declared:
                    moved[name] = chart_revisions(doc.get("spec") or {})
    return moved


def kubectl(on, *args):
    """One kubectl command on the cluster: (rc, its output)."""
    words = " ".join(shlex.quote(a) for a in args)
    if on == "ten":
        argv = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "ten", f"kubectl {words}"]
    elif os.environ.get("VAGRANT_SSH_CONFIG"):
        argv = ["ssh", "-F", os.environ["VAGRANT_SSH_CONFIG"], "kubeadm", f"{COPY_KUBECTL} {words}"]
    else:
        argv = ["vagrant", "ssh", "kubeadm", "-c", f"{COPY_KUBECTL} {words}"]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=300, cwd=OPS)
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)
    return r.returncode, r.stdout.replace("\r", "")


def read_app(on, name):
    rc, out = kubectl(on, "-n", "argocd", "get", "application", name, "-o", "json")
    if rc != 0:
        return None
    try:
        return json.loads(out)
    except ValueError:
        return None


def waiting_for(app, want):
    """Why the app is not yet on the head's version with only leftovers out of sync - or None when it is."""
    if app is None:
        return "its Application not read"
    spec, status = app.get("spec") or {}, app.get("status") or {}
    sync = status.get("sync") or {}
    if chart_revisions(spec) != want:
        return f"its spec still at {chart_revisions(spec)}, the change's {want}"
    if chart_revisions(sync.get("comparedTo") or {}) != want:
        return "not yet compared against the change's spec"
    if app.get("operation") is not None or (status.get("operationState") or {}).get("phase") in BUSY:
        return "a sync under way"
    syncing = [r for r in status.get("resources") or [] if r.get("status") == "OutOfSync" and not r.get("requiresPruning")]
    if syncing:
        return f"{len(syncing)} object(s) not yet synced, e.g. {syncing[0].get('kind')}/{syncing[0].get('name')}"
    return None


def key(obj):
    return obj.get("kind"), obj.get("name"), obj.get("namespace") or ""


def describe(obj):
    return f"{obj.get('kind')}/{obj.get('name')}" + (f" in {obj['namespace']}" if obj.get("namespace") else "")


def instances(on, crd):
    """The objects of a CRD's kind, anywhere - None when not read."""
    rc, out = kubectl(on, "get", crd, "--all-namespaces", "-o", "name")
    return out.split() if rc == 0 else None


def resource_type(obj):
    group = obj.get("group") or ""
    return obj["kind"].lower() + (f".{group}" if group else "")


def kinds_empty(on, name, doomed):
    """Every doomed CRD's kind has no object anywhere - else said, and False (nothing of the app's deleted)."""
    for r in doomed:
        if r.get("kind") != CRD:
            continue
        found = instances(on, r["name"])
        if found is None:
            say(f"{name}: the objects of {r['name']} not read - nothing of {name}'s deleted")
            return False
        if found:
            say(f"{name}: REFUSED - {r['name']} still has {len(found)} object(s) ({', '.join(found[:3])}): deleting "
                f"the CRD deletes them; nothing of {name}'s deleted")
            return False
    return True


def clear(on, name, app, objects):
    """Delete the app's declared leftovers - each CRD's kind checked empty first, all before any delete. True when done."""
    declared = {key(o) for o in objects}
    pruning = [r for r in (app.get("status") or {}).get("resources") or [] if r.get("requiresPruning")]
    doomed = [r for r in pruning if key(r) in declared]
    for r in pruning:
        if key(r) not in declared:
            say(f"{name}: {describe(r)} needs pruning but is not declared - left (scripts/upgrade-leftovers.json)")
    if not kinds_empty(on, name, doomed):
        return False
    for r in doomed:
        args = ["delete", resource_type(r), r["name"], "--ignore-not-found", "--wait=true", "--timeout=120s"]
        if r.get("namespace"):
            args += ["-n", r["namespace"]]
        if kubectl(on, *args)[0] != 0:
            say(f"{name}: deleting {describe(r)} failed")
            return False
        say(f"{name}: deleted {describe(r)}")
    if not doomed:
        say(f"{name}: on its new version, nothing declared left behind")
    return True


def one_round(on, pending, declared):
    """One look at each pending app: the ready ones cleared and dropped. {app: why it waits}, or None on a failure."""
    why = {}
    for name, want in sorted(pending.items()):
        app = read_app(on, name)
        why[name] = waiting_for(app, want)
        if why[name] is not None:
            continue
        if not clear(on, name, app, declared[name]):
            return None
        del pending[name]
    return why


def load(path):
    with open(path) as f:
        data = json.load(f)
    return {app: [o for entry in entries for o in entry["objects"]] for app, entries in data.items()}


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--on", choices=("ten", "copy"), required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--minutes", type=float, default=30)
    p.add_argument("--poll", type=float, default=20)
    a = p.parse_args()
    infra = os.environ.get("UPGRADE_LEFTOVERS_INFRA") or os.path.join(os.path.dirname(OPS), "infra")
    declared = load(os.path.join(OPS, "scripts", "upgrade-leftovers.json"))
    try:
        pending = moved_apps(infra, a.base, a.head, declared)
    except (RuntimeError, OSError, subprocess.TimeoutExpired, yaml.YAMLError) as e:
        say(f"the change's apps not read: {e}")
        return 1
    if not pending:
        say("no declared app moved by the change")
        return 0
    deadline = time.monotonic() + a.minutes * 60
    while True:
        why = one_round(a.on, pending, declared)
        if why is None:
            return 1
        if not pending:
            return 0
        if time.monotonic() >= deadline:
            for name in sorted(pending):
                say(f"{name}: not on the change's version within {a.minutes:g} min - {why[name]}; nothing of it deleted")
            return 1
        time.sleep(a.poll)

if __name__ == "__main__":
    sys.exit(main())
