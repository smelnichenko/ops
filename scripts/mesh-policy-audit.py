#!/usr/bin/env python3
"""Each mesh policy in a schnappy namespace selects a pod there that runs an Istio proxy.

platform's CI (.woodpecker/mesh-selectors.py) sees every chart's pods but not which namespace runs which: a policy for a
workload that runs elsewhere (ClickHouse's, rendered in production and test while ClickHouse runs in schnappy-infra)
passes there. This reads the cluster: for every AuthorizationPolicy and PeerAuthentication with a selector, the pods it
selects in its own namespace and how many of them carry istio-proxy (a container, or a native sidecar: an init
container that restarts always). One selecting none - or only pods without a proxy - is enforced by nothing (2026-11-18:
eight were, PostgreSQL's among them). Read-only.

usage: KUBECTL="kubectl ..." mesh-policy-audit.py [--allow <namespace>/<name>]...
  --allow   a policy armed for a component that namespace does not run (schnappy-test's centrifugo, opensearch)
exit 0 all enforced, 3 a policy enforced by nothing, 1 the cluster not read
"""
import json
import os
import shlex
import subprocess
import sys

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
    pods = {}
    for p in get(kubectl, "pods"):
        if (p.get("status") or {}).get("phase") in ("Succeeded", "Failed"):
            continue  # a finished pod enforces nothing
        pods.setdefault(p["metadata"]["namespace"], []).append(p)
    bad = []
    for kind in KINDS:
        for pol in get(kubectl, kind):
            ns, name = pol["metadata"]["namespace"], pol["metadata"]["name"]
            if not ns.startswith("schnappy-"):
                continue
            sel = ((pol.get("spec") or {}).get("selector") or {}).get("matchLabels")
            if not sel:
                continue  # namespace-wide
            hit = [p for p in pods.get(ns, []) if all((p["metadata"].get("labels") or {}).get(k) == v for k, v in sel.items())]
            prox = [p for p in hit if proxied(p)]
            ok = bool(prox) or "%s/%s" % (ns, name) in allow
            print("%-4s %-20s %-42s pods %d, with a proxy %d%s" % (
                pol["kind"][:4], ns, name, len(hit), len(prox), "" if prox else (" (allowed)" if ok else " - ENFORCED BY NOTHING")))
            if not ok:
                bad.append("%s/%s" % (ns, name))
    print("mesh policy audit: " + ("every policy enforced by a proxy" if not bad else "%d enforced by nothing: %s" % (len(bad), " ".join(bad))))
    return 3 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
