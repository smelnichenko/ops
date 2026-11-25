#!/usr/bin/env python3
"""Each mesh policy in a schnappy namespace selects a pod there that runs an Istio proxy.

platform's CI (.woodpecker/mesh-selectors.py) sees every chart's pods but not which namespace runs which: a policy for a
workload that runs elsewhere (ClickHouse's, rendered in production and test while ClickHouse runs in schnappy-infra)
passes there. This reads the cluster: for every AuthorizationPolicy and PeerAuthentication with a selector, the pods it
selects in its own namespace and how many of them carry istio-proxy (a container, or a native sidecar: an init
container that restarts always). One selecting none is enforced by nothing (2026-11-18: eight were, PostgreSQL's among
them); one selecting a pod without a proxy leaves that pod open (a CNPG instance started without injection: its 5432
unguarded while its peer's policy holds). Read three times, READ_GAP seconds apart: only a policy failing every read
fails - a pod between its deletion and its new one (a StatefulSet's roll) is no finding. A policy attached by targetRef
(none today) is named, not judged. Read-only.

usage: KUBECTL="kubectl ..." mesh-policy-audit.py [--allow <namespace>/<name>]...
  --allow   a policy armed for a component that namespace does not run (schnappy-test's centrifugo, opensearch)
env:  READS (default 3), READ_GAP (default 20)
exit 0 all enforced, 3 a policy enforced by nothing (or not on every pod it selects), 1 the cluster not read
"""
import json
import os
import shlex
import subprocess
import sys
import time

KINDS = ("authorizationpolicies.security.istio.io", "peerauthentications.security.istio.io",
         "requestauthentications.security.istio.io")


def get(kubectl, what):
    r = subprocess.run(shlex.split(kubectl) + ["get", what, "-A", "-o", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        print("reading %s failed (rc %d): %s" % (what, r.returncode, r.stderr.strip()), file=sys.stderr)
        sys.exit(1)
    return json.loads(r.stdout)["items"]


def proxied(pod):
    spec = pod.get("spec") or {}
    return any(c.get("name") == "istio-proxy" for c in spec.get("containers") or []) or any(
        c.get("name") == "istio-proxy" and c.get("restartPolicy") == "Always" for c in spec.get("initContainers") or [])


def main(argv):
    allow = set()
    it = iter(argv)
    for a in it:
        if a != "--allow":
            print("unknown argument %r" % a, file=sys.stderr)
            return 1
        allow.add(next(it, ""))
    kubectl = os.environ.get("KUBECTL", "kubectl")
    reads, gap = int(os.environ.get("READS", "3")), float(os.environ.get("READ_GAP", "20"))
    failing = None
    for n in range(reads):
        if n:
            time.sleep(gap)
        bad, table = read_once(kubectl, allow)
        failing = bad if failing is None else failing & bad
        if not failing:
            break
    print("\n".join(table))
    print("mesh policy audit: " + ("every policy enforced by a proxy" if not failing else
                                   "%d enforced by nothing, every read: %s" % (len(failing), " ".join(sorted(failing)))))
    return 3 if failing else 0


def live_pods(kubectl):
    """The pods that enforce, by namespace - a finished pod enforces nothing."""
    pods = {}
    for p in get(kubectl, "pods"):
        if (p.get("status") or {}).get("phase") not in ("Succeeded", "Failed"):
            pods.setdefault(p["metadata"]["namespace"], []).append(p)
    return pods


def judge(pol, pods, allow):
    """One policy's table row and whether it fails; None when not judged (outside schnappy-, namespace-wide)."""
    ns, name = pol["metadata"]["namespace"], pol["metadata"]["name"]
    if not ns.startswith("schnappy-"):
        return None
    spec = pol.get("spec") or {}
    if spec.get("targetRef") or spec.get("targetRefs"):
        return "%-4s %-20s %-42s attached by targetRef - not judged" % (pol["kind"][:4], ns, name), False
    sel = (spec.get("selector") or {}).get("matchLabels")
    if not sel:
        return None  # namespace-wide
    hit = [p for p in pods.get(ns, []) if all((p["metadata"].get("labels") or {}).get(k) == v for k, v in sel.items())]
    bare = [p["metadata"]["name"] for p in hit if not proxied(p)]
    allowed = "%s/%s" % (ns, name) in allow
    if hit and not bare:
        note = ""
    elif not hit:
        note = " (allowed)" if allowed else " - ENFORCED BY NOTHING"
    else:
        note = " - NO PROXY ON %s" % " ".join(bare)
    row = "%-4s %-20s %-42s pods %d, with a proxy %d%s" % (pol["kind"][:4], ns, name, len(hit), len(hit) - len(bare), note)
    return row, bool(bare or (not hit and not allowed))


def read_once(kubectl, allow):
    """The policies failing this read (kind/namespace/name - kinds share names: Kafka's policy and its
    PeerAuthentication) and the read's table."""
    pods = live_pods(kubectl)
    bad, table = set(), []
    for kind in KINDS:
        for pol in get(kubectl, kind):
            judged = judge(pol, pods, allow)
            if judged is None:
                continue
            row, failed = judged
            table.append(row)
            if failed:
                bad.add("%s/%s/%s" % (pol["kind"], pol["metadata"]["namespace"], pol["metadata"]["name"]))
    return bad, table

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
