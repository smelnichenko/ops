#!/usr/bin/env python3
"""The objects a chart release dropped, deleted where Argo CD leaves them behind.

Argo CD prunes nothing here (prune is off everywhere): an object a chart stops shipping stays on the cluster, tracked
by its app as needing pruning, and the app stays OutOfSync, so the settle checks after a change never pass. The first
case: scylla-operator v1.23.0 dropped three CRDs and two ClusterRoles, and the data-operators unit stayed red on the
copy (2026-11-26). Which objects may go is declared per app in scripts/upgrade-leftovers.json, each entry with the
release that dropped them and where that is said.

For each declared app whose Application file the change moves (git diff <base>...<head> in infra's
clusters/production/argocd/apps): wait until Argo runs it on the head's chart versions - its spec's targetRevisions
the head's, compared against that spec AND synced at it (a failed render compares the new spec too, then marks every
object "to prune" with status Unknown: never acted on), no error condition, Synced or OutOfSync, Healthy (the new
version rolled out - the vendor's "after the upgrade"), no operation running, nothing out of sync but what needs
pruning - on two looks in a row; then delete each declared object Argo marks as needing pruning (OutOfSync, no hook)
for that app. A CustomResourceDefinition goes only while no object of its kind exists anywhere (deleting it would
delete them too): one that has any refuses the app, and nothing of the app's is deleted. A declaration may name only
controller wiring (CRDs, RBAC, service accounts, webhooks, config maps, services) - never a workload or anything
holding data. An object Argo still ships is not touched; one that needs pruning but is not declared is left and said
- the settle check still fails on it, and names it. On the copy every app is asked to refresh first (the change was
just pushed), and an app showing an error condition is hard-refreshed once (the repo-server serves a cached failed
render for an hour).

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
import re
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
COMPARED = ("Synced", "OutOfSync")  # Unknown: a render or fetch failed - the target taken as empty, everything "to prune"
REFRESH = "argocd.argoproj.io/refresh"
# the kinds a declaration may name: what a chart's controller wiring is made of - never a workload, a volume, a secret
# or anything holding data (a declaration naming another kind refuses the run before anything is read)
DELETABLE = {CRD, "ClusterRole", "ClusterRoleBinding", "Role", "RoleBinding", "ServiceAccount", "ConfigMap", "Service",
             "ValidatingWebhookConfiguration", "MutatingWebhookConfiguration"}
REVISION = r"^[\w./-]+$"


def say(text):
    print(f"LEFTOVERS {text}", flush=True)


def git(infra, *args):
    r = subprocess.run(["git", "-C", infra, *args], capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120)
    return r.returncode, r.stdout


def chart_revisions(spec):
    """The targetRevisions of an Application's chart sources, sorted - what "on the new version" is judged by."""
    sources = spec.get("sources") or ([spec["source"]] if spec.get("source") else [])
    return sorted(str(s.get("targetRevision", "")) for s in sources if s.get("chart"))


def synced_chart_revisions(spec, sync):
    """The revisions Argo last synced the chart sources at (sync.revisions lines up with the sources), sorted - empty
    after a failed render, which is how a target that never rendered is told from one that did."""
    sources = spec.get("sources") or ([spec["source"]] if spec.get("source") else [])
    revisions = sync.get("revisions") or ([sync["revision"]] if sync.get("revision") else [])
    return sorted(str(r) for s, r in zip(sources, revisions) if s.get("chart"))


def declared_in(text, declared):
    """{app: its chart revisions} for each declared Application in one file (a file may hold several)."""
    found = {}
    for doc in yaml.safe_load_all(text):
        if not isinstance(doc, dict) or doc.get("kind") != "Application":
            continue
        name = (doc.get("metadata") or {}).get("name")
        if name in declared:
            found[name] = chart_revisions(doc.get("spec") or {})
    return found


def moved_apps(infra, base, head, declared):
    """{app: the head's chart revisions} for each declared app whose Application file the change moves."""
    rc, out = git(infra, "diff", "--name-only", f"{base}...{head}", "--", APPS_DIR)
    if rc != 0:
        raise RuntimeError(f"git diff {base}...{head} in {infra} failed")
    moved = {}
    for path in filter(None, out.splitlines()):
        rc, text = git(infra, "show", f"{head}:{path}")
        if rc == 0:  # else gone at the head: its app is root's to remove, not a chart's leftover
            moved.update(declared_in(text, declared))
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


def leftover(resource):
    """A tracked object the app's target no longer holds - Argo's requiresPruning on a compared resource. On a failed
    render Argo marks every object requiresPruning too, but with status Unknown: never a leftover."""
    return bool(resource.get("requiresPruning")) and resource.get("status") == "OutOfSync" and not resource.get("hook")


def unsettled(status):
    """Why the app is not compared, synced and healthy on its spec - or None."""
    errors = [c for c in status.get("conditions") or [] if str(c.get("type", "")).endswith("Error")]
    if errors:
        return f"{errors[0].get('type')}: {(errors[0].get('message') or '')[:200]}"
    sync = (status.get("sync") or {}).get("status")
    if sync not in COMPARED:
        return f"its sync status {sync!r} (a render or fetch failed?)"
    health = (status.get("health") or {}).get("status")
    if health != "Healthy":
        return f"its health {health!r} - the new version not yet rolled out"
    return None


def waiting_for(app, want):
    """Why the app is not yet on the head's version with only leftovers out of sync - or None when it is."""
    if app is None:
        return "its Application not read"
    spec, status = app.get("spec") or {}, app.get("status") or {}
    if chart_revisions(spec) != want:
        return f"its spec still at {chart_revisions(spec)}, the change's {want}"
    sync = status.get("sync") or {}
    if chart_revisions(sync.get("comparedTo") or {}) != want:
        return "not yet compared against the change's spec"
    why = unsettled(status)
    if why:
        return why
    if synced_chart_revisions(spec, sync) != want:
        return f"its chart still synced at {synced_chart_revisions(spec, sync)}"
    if app.get("operation") is not None or (status.get("operationState") or {}).get("phase") in BUSY:
        return "a sync under way"
    syncing = [r for r in status.get("resources") or []
               if not r.get("hook") and r.get("status") != "Synced" and not leftover(r)]
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
    pruning = [r for r in (app.get("status") or {}).get("resources") or [] if leftover(r)]
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


def refresh(on, names, how):
    """Argo asked to compare again now (the copy: the change was just pushed; hard: past the repo-server's cache, which
    serves a failed render for an hour). Best effort - the wait judges what Argo shows."""
    if names:
        kubectl(on, "-n", "argocd", "annotate", "applications.argoproj.io", *names, f"{REFRESH}={how}", "--overwrite")


def note_wait(on, name, why, state):
    """A new reason to wait said; on the copy an error condition hard-refreshed, once an app."""
    if why == state["said"].get(name):
        return
    say(f"{name}: waiting - {why}")
    state["said"][name] = why
    if on == "copy" and why.split(":")[0].endswith("Error") and name not in state["hard"]:
        state["hard"].add(name)
        refresh(on, [name], "hard")


def one_round(on, pending, declared, state):
    """One look at each pending app: one ready on two looks in a row cleared and dropped (a look between a compare and
    its sync is no settle), a new reason to wait said. {app: why it waits}, or None on a failure."""
    why = {}
    for name, want in sorted(pending.items()):
        app = read_app(on, name)
        why[name] = waiting_for(app, want)
        if why[name] is not None:
            state["ready"].discard(name)
            note_wait(on, name, why[name], state)
        elif name not in state["ready"]:
            state["ready"].add(name)
            why[name] = "ready at one look - looked at again before anything is deleted"
        elif clear(on, name, app, declared[name]):
            del pending[name]
        else:
            return None
    return why


def load(path):
    """{app: its declared objects} - None (said) when a declaration names a kind no declaration may delete."""
    with open(path) as f:
        data = json.load(f)
    declared = {app: [o for entry in entries for o in entry["objects"]] for app, entries in data.items()}
    bad = [f"{app}: {describe(o)}" for app, objs in declared.items() for o in objs if o.get("kind") not in DELETABLE]
    if bad:
        say(f"REFUSED - declared, of a kind never deleted here: {'; '.join(bad)}")
        return None
    return declared


def wait_and_clear(on, pending, declared, minutes, poll, now=time.monotonic, sleep=time.sleep):
    """Look every poll seconds until each pending app is cleared (0), a clear fails or minutes are up (1)."""
    if on == "copy":
        refresh(on, ["--all"], "normal")
    state = {"ready": set(), "said": {}, "hard": set()}
    deadline = now() + minutes * 60
    while True:
        why = one_round(on, pending, declared, state)
        if why is None:
            return 1
        if not pending:
            return 0
        if now() >= deadline:
            for name in sorted(pending):
                say(f"{name}: not on the change's version within {minutes:g} min - {why[name]}; nothing of it deleted")
            return 1
        sleep(poll)


def parser():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--on", choices=("ten", "copy"), required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--minutes", type=float, default=30)
    p.add_argument("--poll", type=float, default=20)
    return p


def main():
    a = parser().parse_args()
    infra = os.environ.get("UPGRADE_LEFTOVERS_INFRA") or os.path.join(os.path.dirname(OPS), "infra")
    if not (re.match(REVISION, a.base) and re.match(REVISION, a.head)) or "-" in (a.base[:1], a.head[:1]):
        say(f"REFUSED - base {a.base!r} and head {a.head!r}: revisions, both given")
        return 2
    declared = load(os.environ.get("UPGRADE_LEFTOVERS_DECLARED") or os.path.join(OPS, "scripts", "upgrade-leftovers.json"))
    if declared is None:
        return 1
    try:
        pending = moved_apps(infra, a.base, a.head, declared)
    except (RuntimeError, OSError, subprocess.TimeoutExpired, yaml.YAMLError) as e:
        say(f"the change's apps not read: {e}")
        return 1
    if not pending:
        say("no declared app moved by the change")
        return 0
    return wait_and_clear(a.on, pending, declared, a.minutes, a.poll)

if __name__ == "__main__":
    sys.exit(main())
