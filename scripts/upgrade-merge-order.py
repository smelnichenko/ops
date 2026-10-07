#!/usr/bin/env python3
"""upgrade-merge-order.py - is the state between a step's two merges one that was proven?

A step that changes both infra and platform reaches production in two pushes, in the order of its step file's branch
lines; Argo CD syncs after each. The Vagrant run mirrors both at once, so it proves the state before the step and the
state after it, never the one in between. That state is safe only when it IS one of the two: the first repo's merge
alone renders every Argo application that reads a platform chart exactly as before (it waits for the second), or the
second merge renders nothing the first had not (the first did the whole step) - and the merge that changes nothing
rendered changes nothing else either: an infra merge whose diff reaches past the value files these applications read
(a raw manifest, another chart's values, an application's definition) puts that live with platform at the other state.
Production reads platform only through these charts, so a platform merge has no effect past them. Nothing rendered in
any of the three states proves nothing and is refused.

Renders, with helm template from the git refs (no cluster), every Application and ApplicationSet in infra's
clusters/production/argocd/apps that takes a chart from platform: the per-environment ApplicationSets (one per
directory their git generator matches), the single Applications, and the preview environments (one pull request per
source repo, number 1). An application whose template this script cannot evaluate fails the check.

Usage: scripts/upgrade-merge-order.py <step>          (exit 0: one repo, or the order is safe; 1: it is not)
       scripts/upgrade-merge-order.py --all           (every step)
"""
import importlib.machinery
import importlib.util
import os
import re
import subprocess
import sys
import tempfile

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEPS = os.path.join(OPS, "tests", "ansible", "upgrade", "steps")
REPOS = {r: os.path.normpath(os.path.join(OPS, "..", r)) for r in ("infra", "platform")}
APPS = "clusters/production/argocd/apps"
PLATFORM_URL = "https://git.pmon.dev/schnappy/platform.git"
HELM = "helm"  # the binary renders() runs (scripts/argo-helm-diff.py sets one per Helm version)
API_VERSIONS = os.path.join(OPS, "tests", "ansible", "upgrade", "api-versions.txt")
WORK = os.path.join(OPS, ".upgrade")
CAPABILITIES = []  # helm template's --kube-version and --api-versions for the step being rendered (capabilities())
INVENTORY = os.path.join(OPS, "scripts", "upgrade-expected-inventory.py")
_loader = importlib.machinery.SourceFileLoader("upgrade_expected_inventory", INVENTORY)
inv = importlib.util.module_from_spec(importlib.util.spec_from_loader("upgrade_expected_inventory", _loader))
_loader.exec_module(inv)


def git(repo, *args):
    return subprocess.run(["git", "-C", REPOS[repo], *args], capture_output=True, text=True, check=True).stdout


def refs(step):
    out = subprocess.run([INVENTORY, "--refs", step], capture_output=True, text=True)
    if out.returncode:
        sys.exit(out.stderr.strip() or out.stdout.strip())
    return dict(zip(("infra", "platform"), out.stdout.split()))


def capabilities(step):
    """As Argo CD renders, with the cluster's: the Kubernetes version the cluster runs when the step's merges land -
    before the step (its expected inventory; a kubeadm step upgrades after its merge) - and production's API versions
    (api-versions.txt) - without them a template gated on .Capabilities.APIVersions (a ServiceMonitor) rendered in
    neither state, and the comparison never saw it."""
    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    server = next(l.split()[2] for l in inv.expected(names[:names.index(step)]) if l.startswith("k8s server "))
    apis = [l.strip() for l in open(API_VERSIONS) if l.strip() and not l.startswith("#")]
    return ["--kube-version", server.lstrip("v"), "--api-versions", ",".join(apis)]


def evaluate(template, ctx, where):
    """The go-template expressions these application templates use - anything else refuses."""
    def one(m):
        expr = m.group(1).strip()
        if expr in ctx:
            return ctx[expr]
        t = re.fullmatch(r'index \.path\.segments (\d+) \| trimSuffix "([^"]*)"', expr)
        if t:
            seg = ctx[".path.path"].split("/")[int(t.group(1))]
            return seg[:-len(t.group(2))] if t.group(2) and seg.endswith(t.group(2)) else seg
        sys.exit(f"{where}: cannot evaluate {{{{ {expr} }}}}")
    return re.sub(r"\{\{(.*?)\}\}", one, template)


def renders(infra_ref, platform_ref, work, read=None):
    """{application name: rendered manifests} for every application that reads a platform chart; the infra value
    files they read added to `read`."""
    out = {}
    charts = {}

    def render(name, chart, release, namespace, value_files, inline):
        if chart not in charts:
            dest = os.path.join(work, f"{platform_ref.replace('/', '_')}")
            os.makedirs(dest, exist_ok=True)
            archive = subprocess.run(["git", "-C", REPOS["platform"], "archive", platform_ref, chart],
                                     capture_output=True, check=True).stdout
            subprocess.run(["tar", "-x", "-C", dest], input=archive, check=True)
            charts[chart] = os.path.join(dest, chart)
        args = [HELM, "template", release, charts[chart], "-n", namespace, *CAPABILITIES]
        for i, path in enumerate(value_files):
            f = os.path.join(work, f"values-{len(out)}-{i}.yaml")
            with open(f, "w") as fh:
                fh.write(git("infra", "show", f"{infra_ref}:{path}"))
            args += ["-f", f]
            if read is not None:
                read.add(path)
        if inline is not None:
            f = os.path.join(work, f"inline-{len(out)}.yaml")
            with open(f, "w") as fh:
                fh.write(inline)
            args += ["-f", f]
        r = subprocess.run(args, capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"{name}: helm template failed at infra {infra_ref}, platform {platform_ref}:\n{r.stderr}")
        out[name] = r.stdout

    files = [f for f in git("infra", "ls-tree", "--name-only", f"{infra_ref}:{APPS}").split() if f.endswith(".yaml")]
    for f in files:
        for doc in yaml.safe_load_all(git("infra", "show", f"{infra_ref}:{APPS}/{f}")):
            if not doc or doc.get("kind") not in ("Application", "ApplicationSet"):
                continue
            where = f"{APPS}/{f}"
            spec = doc["spec"]["template"]["spec"] if doc["kind"] == "ApplicationSet" else doc["spec"]
            sources = spec.get("sources") or [spec["source"]]
            charts_here = [s for s in sources if s.get("repoURL") == PLATFORM_URL]
            if not charts_here:
                continue
            if len(charts_here) != 1 or "path" not in charts_here[0]:
                sys.exit(f"{where}: expected one platform chart source")
            src = charts_here[0]
            helm = src.get("helm", {})
            if doc["kind"] == "Application":
                contexts = [{}]
                name_tpl = doc["metadata"]["name"]
            else:
                gens = doc["spec"]["generators"]
                if len(gens) == 1 and "git" in gens[0]:
                    dirs = []
                    for d in gens[0]["git"]["directories"]:
                        pattern = d["path"]
                        parent, glob = pattern.rsplit("/", 1)
                        rx = re.compile("^" + re.escape(glob).replace(r"\*", "[^/]*") + "$")
                        listing = git("infra", "ls-tree", "-d", "--name-only", f"{infra_ref}:{parent}").split()
                        dirs += [f"{parent}/{x}" for x in listing if rx.match(x)]
                    contexts = [{".path.path": p, ".path.basenameNormalized": os.path.basename(p)} for p in dirs]
                elif len(gens) == 1 and "matrix" in gens[0]:
                    inner = gens[0]["matrix"]["generators"]
                    lists = [g for g in inner if "list" in g]
                    if len(inner) != 2 or len(lists) != 1 or not any("pullRequest" in g for g in inner):
                        sys.exit(f"{where}: expected a list x pullRequest matrix")
                    contexts = [{".repo": e["repo"], ".number": "1", ".head_short_sha": "0000000"}
                                for e in lists[0]["list"]["elements"]]
                else:
                    sys.exit(f"{where}: an ApplicationSet generator this check cannot evaluate")
                name_tpl = doc["spec"]["template"]["metadata"]["name"]
            for ctx in contexts:
                name = evaluate(name_tpl, ctx, where)
                release = evaluate(helm.get("releaseName", name), ctx, where)
                namespace = evaluate(spec["destination"]["namespace"], ctx, where)
                value_files = []
                for v in helm.get("valueFiles", []):
                    v = evaluate(v, ctx, where)
                    if not v.startswith("$values/"):
                        sys.exit(f"{where}: value file {v} is not from infra ($values)")
                    value_files.append(v[len("$values/"):])
                inline = evaluate(helm["values"], ctx, where) if "values" in helm else None
                if "valuesObject" in helm or "parameters" in helm:
                    sys.exit(f"{where}: helm valuesObject/parameters - not evaluated by this check")
                render(name, src["path"], release, namespace, value_files, inline)
    return out


def between_state(app, a, m, b):
    """How an application renders with the first merge alone: as before, as after, or neither."""
    if m.get(app) == a.get(app):
        return "as before"
    if m.get(app) == b.get(app):
        return "as after"
    return "NEITHER"


def outside(repo, before_ref, after_ref, read):
    """The repo's changed files whose effect the renders do not show (none for platform: see the top)."""
    if repo == "platform":
        return []
    return [f for f in git("infra", "diff", "--name-only", before_ref, after_ref).split() if f not in read]


def check(step):
    order = inv.branch_order(step)
    if len(order) < 2:
        print(f"{step}: one repo - no state between merges")
        return True
    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    after = refs(step)
    before = refs(names[names.index(step) - 1]) if names.index(step) else {"infra": "main", "platform": "main"}
    first, second = order
    between = dict(before, **{first: after[first]})
    CAPABILITIES[:] = capabilities(step)
    read = set()
    os.makedirs(WORK, exist_ok=True)  # a fresh checkout has none
    with tempfile.TemporaryDirectory(dir=WORK) as work:
        a, m, b = (renders(s["infra"], s["platform"], os.path.join(work, k), read)
                   for k, s in (("before", before), ("between", between), ("after", after)))
    if not (a and m and b):
        print(f"{step}: REFUSED - an application reading a platform chart rendered in none of the states (before "
              f"{len(a)}, between {len(m)}, after {len(b)}): nothing proven")
        return False
    first_rest = outside(first, before[first], after[first], read) if m == a else []
    second_rest = outside(second, before[second], after[second], read) if m == b else []
    if m == a and not first_rest:
        print(f"{step}: safe - {first} alone renders every platform-chart application as before; {second} makes the "
              "step")
        return True
    if m == b and not second_rest:
        print(f"{step}: safe - {first} makes the whole step; {second} renders nothing new")
        return True
    print(f"{step}: UNSAFE in this order ({first} then {second}):")
    if first_rest:
        print(f"  {first} alone renders the applications as before, but its merge also changes "
              f"{', '.join(first_rest)} - live with {second} still before the step")
    if second_rest:
        print(f"  {second} renders nothing new, but its merge also changes {', '.join(second_rest)} - not live "
              f"while {first} is already the step")
    if m != a and m != b:
        print(f"  with {first} alone these applications render neither as before nor as after:")
    for app in sorted(set(a) | set(m) | set(b)):
        if m != a and m != b and not (m.get(app) == a.get(app) and m.get(app) == b.get(app)):
            print(f"    {app}: {between_state(app, a, m, b)}")
    return False


def main():
    args = sys.argv[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    steps = names if args[0] == "--all" else [args[0]]
    if steps[0] not in names:
        sys.exit(f"no step {steps[0]}")
    failed = 0
    for s in steps:  # every step judged, each printing its verdict - not stopped at the first
        failed += not check(s)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
