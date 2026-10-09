#!/usr/bin/env python3
"""argo-helm-diff.py - does a new Argo CD's Helm render what the old one did?

Argo CD renders every Helm application itself, with the Helm it bundles. An Argo CD upgrade that moves to another Helm
(3.5: Helm 3.19.4 -> 4.2.1) re-renders every application at the same commits, and any difference is synced at once -
automated sync with selfHeal shows nothing OutOfSync, it just applies it. So before such a step: every application of
infra's clusters/production/argocd/apps at the step's commits rendered with both Helms, object by object.

A step opts in with its line `helm-diff <old helm> <new helm>`; the renders use the official binaries of those versions
(downloaded into .upgrade/helm, checked against their published sha256, pinned here). Platform's charts as upgrade-merge-order.py
renders them (the per-environment ApplicationSets included); the upstream charts from their repositories (HTTP and
OCI), with their value files from infra, inline values and parameters - CRDs included, as Argo CD renders them.

Usage: scripts/argo-helm-diff.py <step>     (exit 0: the same objects, or the step has no helm-diff line)
       scripts/argo-helm-diff.py --all      (every step with one)
       scripts/argo-helm-diff.py --from <step>   (every step with one from it on: a full run's start)
"""
import hashlib
import importlib.machinery
import importlib.util
import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEPS = os.path.join(OPS, "tests", "ansible", "upgrade", "steps")
WORK = os.path.join(OPS, ".upgrade")
BIN = os.path.join(WORK, "helm")
_loader = importlib.machinery.SourceFileLoader("upgrade_merge_order",
                                               os.path.join(OPS, "scripts", "upgrade-merge-order.py"))
mo = importlib.util.module_from_spec(importlib.util.spec_from_loader("upgrade_merge_order", _loader))
_loader.exec_module(mo)


# the published sha256 of each Helm a step's helm-diff line names (get.helm.sh/helm-v<version>-linux-amd64.tar.gz
# .sha256sum, read 2026-10-08 - the archives kept in .upgrade/helm since matching): pinned here, not fetched at each
# use - a sum from the server the archive comes from proves only that the two agree, and its fetch failing ended a boot
HELM_SHA256 = {
    "3.19.4": "759c656fbd9c11e6a47784ecbeac6ad1eb16a9e76d202e51163ab78504848862",
    "4.2.1": "479dca836e5b45e8bd222400c5591b0e3a647378f03ff96597180db97c17fdae",
}


def fetch(url):
    """A download, a transient failure (a 5xx, a 429, the connection lost) tried again as a chart fetch is."""
    for attempt in range(1, FETCH_TRIES + 1):
        try:
            return urllib.request.urlopen(url, timeout=120).read()
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            code = getattr(e, "code", None)
            if attempt == FETCH_TRIES or (code is not None and code < 500 and code != 429):
                raise
            print(f"{url}: a transient failure, try {attempt} of {FETCH_TRIES}: {e}", file=sys.stderr)
            time.sleep(FETCH_WAIT * attempt)


def helm_binary(version):
    """The official linux-amd64 binary of that Helm version, from its archive verified against its pinned sha256 at
    each use: the archive kept here, fetched again when it is not the pinned one; the binary taken from it afresh.
    Nothing cached is run on its word - a binary left in its place (by hand, a wrong build, a plant) said the version
    asked for and was trusted."""
    path = os.path.join(BIN, version, "helm")
    name = f"helm-v{version}-linux-amd64.tar.gz"
    url = f"https://get.helm.sh/{name}"
    want = HELM_SHA256.get(version)
    if not want:
        sys.exit(f"helm {version}: no sha256 pinned (HELM_SHA256 in {__file__}) - add the published one: {url}.sha256sum")
    kept = os.path.join(BIN, version, name)
    archive = open(kept, "rb").read() if os.path.exists(kept) else b""
    if hashlib.sha256(archive).hexdigest() != want:
        archive = fetch(url)
        if hashlib.sha256(archive).hexdigest() != want:
            sys.exit(f"helm {version}: the archive's sha256 is not the pinned one")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # each written beside its place and moved there whole: one cut short left a partial helm that every later run used
    for dest, data in ((kept, lambda: archive), (path, lambda: tarfile.open(fileobj=io.BytesIO(archive))
                                                 .extractfile("linux-amd64/helm").read())):
        fd, part = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".helm-")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data())
            os.chmod(part, 0o755 if dest == path else 0o644)
            os.replace(part, dest)
        finally:
            if os.path.exists(part):
                os.remove(part)
    return path


# a chart fetch an upstream answers with a transient failure - a 5xx (blob.istio.io's 502 ended a full run in its first
# minute, 2026-10-08), a 429, a connection reset or timed out: tried again, FETCH_TRIES times at most, FETCH_WAIT
# seconds more each time; any other failure fails at once
TRANSIENT = re.compile(r"failed to fetch .*: (5\d\d|429)\b|connection reset|i/o timeout|TLS handshake timeout"
                       r"|unexpected EOF", re.I)
FETCH_TRIES, FETCH_WAIT = 3, 10


def template(args, cwd):
    """helm template, its fetch's transient failures tried again."""
    for attempt in range(1, FETCH_TRIES + 1):
        r = subprocess.run(args, capture_output=True, text=True, cwd=cwd)
        if r.returncode == 0 or attempt == FETCH_TRIES or not TRANSIENT.search(r.stderr):
            return r
        print(f"helm template: a transient fetch failure, try {attempt} of {FETCH_TRIES}: {r.stderr.strip()[:200]}",
              file=sys.stderr)
        time.sleep(FETCH_WAIT * attempt)
    return r


def upstream(helm, infra_ref, work):
    """{application name: rendered manifests} for every application that takes a chart from an upstream repository."""
    out = {}
    files = [f for f in mo.git("infra", "ls-tree", "--name-only", f"{infra_ref}:{mo.APPS}").split()
             if f.endswith(".yaml")]
    for f in files:
        for doc in yaml.safe_load_all(mo.git("infra", "show", f"{infra_ref}:{mo.APPS}/{f}")):
            if not doc or doc.get("kind") != "Application":
                continue
            spec, name = doc["spec"], doc["metadata"]["name"]
            for src in spec.get("sources") or [spec["source"]]:
                if not src.get("chart"):
                    continue
                h = src.get("helm", {})
                repo = src["repoURL"].rstrip("/")
                if repo.startswith(("http://", "https://")):  # a chart repository
                    chart = [src["chart"], "--repo", repo]
                else:  # an OCI registry (Argo CD takes it without the scheme)
                    chart = [f"oci://{repo.removeprefix('oci://')}/{src['chart']}"]
                args = [helm, "template", h.get("releaseName", name), *chart, "--version", str(src["targetRevision"]),
                        "-n", spec["destination"]["namespace"], "--include-crds", *mo.CAPABILITIES]
                for i, v in enumerate(h.get("valueFiles", [])):
                    if not v.startswith("$values/"):
                        sys.exit(f"{name}: value file {v} is not from infra ($values)")
                    path = os.path.join(work, f"{name}-values-{i}.yaml")
                    with open(path, "w") as fh:
                        fh.write(mo.git("infra", "show", f"{infra_ref}:{v[len('$values/'):]}"))
                    args += ["-f", path]
                for key, value in (("values", h.get("values")), ("valuesObject", h.get("valuesObject"))):
                    if value is not None:
                        path = os.path.join(work, f"{name}-{key}.yaml")
                        with open(path, "w") as fh:
                            fh.write(value if isinstance(value, str) else yaml.safe_dump(value))
                        args += ["-f", path]
                for p in h.get("parameters", []):
                    args += ["--set-string" if p.get("forceString") else "--set", f"{p['name']}={p['value']}"]
                r = template(args, work)
                if r.returncode:
                    sys.exit(f"{name}: {os.path.basename(os.path.dirname(helm))}'s helm template failed:\n{r.stderr}")
                out[name] = r.stdout
    return out


class _Loader(yaml.SafeLoader):
    """PyYAML's safe loader, but a bare `=` (a CRD's enum value) is the string it is, not YAML 1.1's value tag."""


_Loader.add_constructor("tag:yaml.org,2002:value", lambda loader, node: loader.construct_scalar(node))


def objects(manifests):
    """{(apiVersion, kind, namespace, name): object} of a render (comments and document order do not count)."""
    out = {}
    for doc in yaml.load_all(manifests, Loader=_Loader):  # noqa: S506 - a safe loader with one scalar constructor
        if isinstance(doc, dict) and doc.get("kind"):
            meta = doc.get("metadata") or {}
            out[(doc.get("apiVersion"), doc["kind"], meta.get("namespace", ""), meta.get("name"))] = doc
    return out


def renders(helm, refs, work):
    os.makedirs(work, exist_ok=True)
    mo.HELM = helm
    out = mo.renders(refs["infra"], refs["platform"], os.path.join(work, "platform"))
    os.makedirs(os.path.join(work, "upstream"), exist_ok=True)
    out.update(upstream(helm, refs["infra"], os.path.join(work, "upstream")))
    return out


def where(key, oa, ob, old, new):
    """Which Helm renders the object: only the old one, only the new one, or both, otherwise."""
    if key not in ob:
        return "only " + old
    if key not in oa:
        return "only " + new
    return "differs"


def check(step):
    lines = [l.split() for l in open(os.path.join(STEPS, step + ".txt")) if l.startswith("helm-diff ")]
    if not lines:
        return True
    old, new = lines[0][1], lines[0][2]
    refs = mo.refs(step)
    mo.CAPABILITIES[:] = mo.capabilities(step)  # the cluster's version and API versions, as Argo CD passes them
    os.makedirs(WORK, exist_ok=True)  # a fresh checkout has none
    with tempfile.TemporaryDirectory(dir=WORK) as work:
        a = renders(helm_binary(old), refs, os.path.join(work, old))
        b = renders(helm_binary(new), refs, os.path.join(work, new))
    if not a or not b:
        print(f"{step}: REFUSED - Helm {old} rendered {len(a)} applications, Helm {new} {len(b)} at infra "
              f"{refs['infra']}, platform {refs['platform']}: nothing proven")
        return False
    differ = []
    for app in sorted(set(a) | set(b)):
        oa, ob = objects(a.get(app, "")), objects(b.get(app, ""))
        for key in sorted(set(oa) | set(ob), key=str):
            if oa.get(key) != ob.get(key):
                differ.append(f"  {app}: {'/'.join(str(k) for k in key[1:] if k)} "
                              f"({where(key, oa, ob, old, new)})")
    if differ:
        print(f"{step}: Helm {new} renders other objects than Helm {old} at infra {refs['infra']}, platform "
              f"{refs['platform']}:")
        print("\n".join(differ))
        return False
    print(f"{step}: Helm {old} and {new} render the same objects - {len(a)} applications at infra {refs['infra']}, "
          f"platform {refs['platform']}")
    return True


def main():
    args = sys.argv[1:]
    if len(args) != (2 if args[:1] == ["--from"] else 1):
        sys.exit(__doc__)
    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    first = args[-1] if args[0] != "--all" else names[0]
    if first not in names:
        sys.exit(f"no step {first}")
    # --from: the steps from a full run's start on (those before it production merged already)
    steps = names[names.index(first):] if args[0] in ("--all", "--from") else [first]
    failed = 0
    for s in steps:  # every step judged, each printing its verdict - not stopped at the first
        failed += not check(s)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
