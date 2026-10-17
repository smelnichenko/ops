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
       scripts/upgrade-merge-order.py --from <step>   (every step from it on: a full run's start)
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


def applications(infra_ref, kinds):
    """(file, document) of each of `kinds` in infra's apps directory at `infra_ref`, in file order."""
    files = [f for f in git("infra", "ls-tree", "--name-only", f"{infra_ref}:{APPS}").split() if f.endswith(".yaml")]
    for f in files:
        for doc in yaml.safe_load_all(git("infra", "show", f"{infra_ref}:{APPS}/{f}")):
            if doc and doc.get("kind") in kinds:
                yield f, doc


def platform_source(doc, where):
    """(spec, source) of the application's one platform chart; None: it reads none."""
    spec = doc["spec"]["template"]["spec"] if doc["kind"] == "ApplicationSet" else doc["spec"]
    sources = spec.get("sources") or [spec["source"]]
    charts_here = [s for s in sources if s.get("repoURL") == PLATFORM_URL]
    if not charts_here:
        return None
    if len(charts_here) != 1 or "path" not in charts_here[0]:
        sys.exit(f"{where}: expected one platform chart source")
    return spec, charts_here[0]


def git_directories(generator, infra_ref):
    """The infra directories a git generator's directory patterns match at `infra_ref`."""
    dirs = []
    for d in generator["directories"]:
        pattern = d["path"]
        parent, glob = pattern.rsplit("/", 1)
        rx = re.compile("^" + re.escape(glob).replace(r"\*", "[^/]*") + "$")
        # NUL-separated: names as they are - split on blanks, "a b-svc" was two names and "ä-svc" git's quoted octal
        listing = git("infra", "ls-tree", "-d", "-z", "--name-only", f"{infra_ref}:{parent}").split("\0")[:-1]
        dirs += [f"{parent}/{x}" for x in listing if rx.match(x)]
    return dirs


def pull_request_contexts(matrix, where):
    """A list x pullRequest matrix's contexts: one pull request per listed source repo, number 1."""
    inner = matrix["generators"]
    lists = [g for g in inner if "list" in g]
    if len(inner) != 2 or len(lists) != 1 or not any("pullRequest" in g for g in inner):
        sys.exit(f"{where}: expected a list x pullRequest matrix")
    return [{".repo": e["repo"], ".number": "1", ".head_short_sha": "0000000"} for e in lists[0]["list"]["elements"]]


def contexts(doc, infra_ref, where):
    """(template contexts, name template) of an application: an Application's one, an ApplicationSet's per what its
    generator yields - one it cannot evaluate refuses."""
    if doc["kind"] == "Application":
        return [{}], doc["metadata"]["name"]
    gens = doc["spec"]["generators"]
    if len(gens) == 1 and "git" in gens[0]:
        out = [{".path.path": p, ".path.basenameNormalized": os.path.basename(p)}
               for p in git_directories(gens[0]["git"], infra_ref)]
    elif len(gens) == 1 and "matrix" in gens[0]:
        out = pull_request_contexts(gens[0]["matrix"], where)
    else:
        sys.exit(f"{where}: an ApplicationSet generator this check cannot evaluate")
    return out, doc["spec"]["template"]["metadata"]["name"]


def render_inputs(spec, helm, name_tpl, ctx, where):
    """(name, release, namespace, infra value files, inline values) of one application in context `ctx`."""
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
    return name, release, namespace, value_files, inline


def chart_dir(charts, chart, work, platform_ref):
    """The chart's directory: platform's tree at `platform_ref` extracted under `work` the first time it is asked."""
    if chart not in charts:
        dest = os.path.join(work, f"{platform_ref.replace('/', '_')}")
        os.makedirs(dest, exist_ok=True)
        archive = subprocess.run(["git", "-C", REPOS["platform"], "archive", platform_ref, chart],
                                 capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", dest], input=archive, check=True)
        charts[chart] = os.path.join(dest, chart)
    return charts[chart]


def values_args(work, n, infra_ref, value_files, inline, read):
    """helm template's -f of the n-th render: each infra value file (added to `read`), then its inline values."""
    args = []
    for i, path in enumerate(value_files):
        f = os.path.join(work, f"values-{n}-{i}.yaml")
        with open(f, "w") as fh:
            fh.write(git("infra", "show", f"{infra_ref}:{path}"))
        args += ["-f", f]
        if read is not None:
            read.add(path)
    if inline is not None:
        f = os.path.join(work, f"inline-{n}.yaml")
        with open(f, "w") as fh:
            fh.write(inline)
        args += ["-f", f]
    return args


def renders(infra_ref, platform_ref, work, read=None):
    """{application name: rendered manifests} for every application that reads a platform chart; the infra value
    files they read added to `read`."""
    out = {}
    charts = {}
    for f, doc in applications(infra_ref, ("Application", "ApplicationSet")):
        where = f"{APPS}/{f}"
        found = platform_source(doc, where)
        if not found:
            continue
        spec, src = found
        helm = src.get("helm", {})
        ctxs, name_tpl = contexts(doc, infra_ref, where)
        for ctx in ctxs:
            name, release, namespace, value_files, inline = render_inputs(spec, helm, name_tpl, ctx, where)
            args = [HELM, "template", release, chart_dir(charts, src["path"], work, platform_ref), "-n", namespace,
                    *CAPABILITIES]
            args += values_args(work, len(out), infra_ref, value_files, inline, read)
            r = subprocess.run(args, capture_output=True, text=True)
            if r.returncode:
                sys.exit(f"{name}: helm template failed at infra {infra_ref}, platform {platform_ref}:\n{r.stderr}")
            out[name] = r.stdout
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


def refs_before(step, names):
    """The refs before the step: the step before it's (names: every step, in order), or main for the first."""
    return refs(names[names.index(step) - 1]) if names.index(step) else {"infra": "main", "platform": "main"}


def check(step):
    order = inv.branch_order(step)
    if len(order) < 2:
        print(f"{step}: one repo - no state between merges")
        return True
    names = sorted(f[:-4] for f in os.listdir(STEPS) if f.endswith(".txt"))
    after = refs(step)
    before = refs_before(step, names)
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
    print_unsafe(step, order, (first_rest, second_rest), (a, m, b))
    return False


def print_unsafe(step, order, rests, states):
    """Why the order is unsafe: each merge's changes past the renders, and each application rendered neither as before
    nor as after with the first merge alone."""
    (first, second), (first_rest, second_rest), (a, m, b) = order, rests, states
    print(f"{step}: UNSAFE in this order ({first} then {second}):")
    if first_rest:
        print(f"  {first} alone renders the applications as before, but its merge also changes "
              f"{', '.join(first_rest)} - live with {second} still before the step")
    if second_rest:
        print(f"  {second} renders nothing new, but its merge also changes {', '.join(second_rest)} - not live "
              f"while {first} is already the step")
    neither = m != a and m != b
    if neither:
        print(f"  with {first} alone these applications render neither as before nor as after:")
    for app in sorted(set(a) | set(m) | set(b)):
        if neither and not (m.get(app) == a.get(app) and m.get(app) == b.get(app)):
            print(f"    {app}: {between_state(app, a, m, b)}")


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
