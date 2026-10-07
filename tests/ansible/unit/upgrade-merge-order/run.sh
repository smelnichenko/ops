#!/bin/bash
# scripts/upgrade-merge-order.py's verdicts on a temporary infra/platform pair (one Application reading a platform chart
# with a value file from infra, a raw manifest beside it) and a stub helm that fills the chart's {{ .Values.<key> }}:
#   safe      infra first, its values only, unread by the old chart (as before); platform first, infra second with
#             values nothing reads (platform did the whole step);
#   UNSAFE    infra first with a raw manifest too (live with platform before); infra second with a raw manifest (not
#             live while platform is the step); a first merge that renders neither as before nor as after;
#   REFUSED   no application reads a platform chart (its URL spelled without .git: the check passed on nothing).
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
ROOT=$ROOT W=$W python3 - <<'PY'
import contextlib, importlib.machinery, importlib.util, io, os, subprocess

ROOT, W = os.environ["ROOT"], os.environ["W"]
loader = importlib.machinery.SourceFileLoader("mo", os.path.join(ROOT, "scripts", "upgrade-merge-order.py"))
mo = importlib.util.module_from_spec(importlib.util.spec_from_loader("mo", loader))
loader.exec_module(mo)

helm = os.path.join(W, "helm")  # `helm template <release> <chart> -n <ns> -f <file>...`: the templates, values filled
with open(helm, "w") as f:
    f.write("""#!/usr/bin/env python3
import glob, os, re, sys
import yaml
args, values = sys.argv[1:], {}
open(os.environ["HELM_ARGS"], "a").write(" ".join(args) + "\\n")
for i, a in enumerate(args):
    if a == "-f":
        values.update(yaml.safe_load(open(args[i + 1])) or {})
for t in sorted(glob.glob(os.path.join(args[2], "templates", "*"))):
    sys.stdout.write(re.sub(r"\\{\\{ \\.Values\\.(\\w+) \\}\\}", lambda m: str(values.get(m[1], "")), open(t).read()))
""")
os.chmod(helm, 0o755)
os.makedirs(os.path.join(W, "steps"))
for s in ("01-before", "02-step"):
    open(os.path.join(W, "steps", s + ".txt"), "w").close()
os.makedirs(os.path.join(W, ".upgrade"))
mo.HELM, mo.STEPS, mo.OPS = helm, os.path.join(W, "steps"), W
mo.WORK = os.path.join(W, "clean", ".upgrade")  # as CI's fresh checkout has it: not there yet
mo.refs = lambda step: dict.fromkeys(("infra", "platform"), "main" if step == "01-before" else "upgrade/02-step")
mo.capabilities = lambda step: ["--kube-version", "1.34.12", "--api-versions", "monitoring.coreos.com/v1,v1"]
os.environ["HELM_ARGS"] = os.path.join(W, "helm-args")

APP = """apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: demo}
spec:
  destination: {namespace: demo}
  sources:
    - repoURL: %s
      path: charts/demo
      helm: {valueFiles: [$values/values/demo.yaml]}
    - {repoURL: https://git.pmon.dev/schnappy/infra.git, ref: values}
"""


def repo(name, files, step_files):
    """A repo with `files` on main and `step_files` on top of them in branch upgrade/02-step."""
    d = os.path.join(W, case, name)
    git = lambda *a: subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", *a], check=True,
                                    capture_output=True)
    for i, tree in enumerate((files, step_files)):
        for path, text in tree.items():
            os.makedirs(os.path.dirname(os.path.join(d, path)), exist_ok=True)
            open(os.path.join(d, path), "w").write(text)
        if i == 0:
            git("init", "-q", "-b", "main")
        else:
            git("checkout", "-q", "-b", "upgrade/02-step")
        git("add", "-A")
        git("commit", "-q", "--allow-empty", "-m", "c")
    git("checkout", "-q", "main")
    return d


fails = 0


def case_(name, order, infra_step, platform_step, want, words, url=mo.PLATFORM_URL):
    global case, fails
    case = name.replace(" ", "-")
    mo.REPOS = {
        "infra": repo("infra", {"clusters/production/argocd/apps/demo.yaml": APP % url, "values/demo.yaml": "x: 1\n",
                                "raw/cm.yaml": "data: 1\n"}, infra_step),
        "platform": repo("platform", {"charts/demo/Chart.yaml": "name: demo\n",
                                      "charts/demo/templates/cm.yaml": "x: {{ .Values.x }}\n"}, platform_step)}
    mo.inv.branch_order = lambda step: order
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        got = mo.check("02-step")
    ok = got == want and all(w in out.getvalue() for w in words)
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f" (returned {got}, want {want})\n{out.getvalue()}"))


NEW_KEY = {"charts/demo/templates/cm.yaml": "x: {{ .Values.x }}\ny: {{ .Values.y }}\n"}
case_("infra first, values the old chart does not read: as before", ["infra", "platform"],
      {"values/demo.yaml": "x: 1\ny: 2\n"}, NEW_KEY, True, ["safe - infra alone renders"])
case_("infra first with a raw manifest too: unsafe", ["infra", "platform"],
      {"values/demo.yaml": "x: 1\ny: 2\n", "raw/cm.yaml": "data: 2\n"}, NEW_KEY, False,
      ["UNSAFE", "also changes raw/cm.yaml - live with platform still before"])
case_("platform first, infra values nothing reads: platform the whole step", ["platform", "infra"],
      {"values/demo.yaml": "x: 1\nw: 3\n"}, {"charts/demo/templates/cm.yaml": "x: {{ .Values.x }}\nz: 1\n"}, True,
      ["safe - platform makes the whole step"])
case_("infra second with a raw manifest: unsafe", ["platform", "infra"],
      {"raw/cm.yaml": "data: 2\n"}, {"charts/demo/templates/cm.yaml": "x: {{ .Values.x }}\nz: 1\n"}, False,
      ["UNSAFE", "also changes raw/cm.yaml - not live while platform is already the step"])
case_("the first merge alone renders neither state: unsafe", ["infra", "platform"],
      {"values/demo.yaml": "x: 2\n"}, {"charts/demo/templates/cm.yaml": "x: {{ .Values.x }}\nz: 1\n"}, False,
      ["UNSAFE", "demo: NEITHER"])
case_("no application reads a platform chart: refused", ["infra", "platform"],
      {"values/demo.yaml": "x: 2\n"}, {"charts/demo/templates/cm.yaml": "x: {{ .Values.x }}\nz: 1\n"}, False,
      ["REFUSED", "nothing proven"], url="https://git.pmon.dev/schnappy/platform")
case_("one repo: nothing between", ["infra"], {"values/demo.yaml": "x: 2\n"}, {}, True, ["one repo"])
# ApplicationSets as production has them (5 of the 8 apps reading a platform chart): a git-directories generator over
# environment directories - one application per directory, each with its own values; a list x pullRequest matrix - one
# per list element; inline helm values rendered; helm valuesObject refused (not evaluated)
SET_GIT = """apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: {name: envs}
spec:
  generators:
    - git: {repoURL: https://git.pmon.dev/schnappy/infra.git, directories: [{path: clusters/production/envs/*}]}
  template:
    metadata: {name: "demo-{{ .path.basenameNormalized }}"}
    spec:
      destination: {namespace: demo}
      sources:
        - repoURL: %s
          path: charts/demo
          helm: {valueFiles: ["$values/{{ .path.path }}/values.yaml"]}
        - {repoURL: https://git.pmon.dev/schnappy/infra.git, ref: values}
""" % mo.PLATFORM_URL
SET_MATRIX = """apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: {name: previews}
spec:
  generators:
    - matrix:
        generators:
          - list: {elements: [{repo: site}, {repo: chat}]}
          - pullRequest: {gitea: {owner: schnappy, repo: x}}
  template:
    metadata: {name: "pr-{{ .number }}-{{ .repo }}"}
    spec:
      destination: {namespace: "pr-{{ .number }}"}
      source:
        repoURL: %s
        path: charts/demo
        helm: {values: "x: inline-{{ .repo }}"}
""" % mo.PLATFORM_URL
def sets_case(name, files, want_names, want_parts, refused=None):
    global case, fails
    case = name.replace(" ", "-")
    mo.REPOS = {"infra": repo("infra", files, {}),
                "platform": repo("platform", {"charts/demo/Chart.yaml": "name: demo\n",
                                              "charts/demo/templates/cm.yaml": "x: {{ .Values.x }}\n"}, {})}
    try:
        got = mo.renders("main", "main", os.path.join(W, case + "-work"))
        ok = refused is None and sorted(got) == want_names and all(part in got[n] for n, part in want_parts)
        detail = got
    except SystemExit as e:
        ok, detail = refused is not None and refused in str(e), str(e)
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"\n  {detail}"))
os.makedirs(os.path.join(W, "sets-work"), exist_ok=True)
sets_case("a git-directories ApplicationSet: an application per directory, its own values",
          {"clusters/production/argocd/apps/envs.yaml": SET_GIT, "clusters/production/envs/a/values.yaml": "x: 1\n",
           "clusters/production/envs/b/values.yaml": "x: 2\n"},
          ["demo-a", "demo-b"], [("demo-a", "x: 1"), ("demo-b", "x: 2")])
sets_case("a list x pullRequest ApplicationSet: an application per element, its inline values",
          {"clusters/production/argocd/apps/previews.yaml": SET_MATRIX},
          ["pr-1-chat", "pr-1-site"], [("pr-1-site", "x: inline-site"), ("pr-1-chat", "x: inline-chat")])
sets_case("helm valuesObject: refused, not evaluated",
          {"clusters/production/argocd/apps/demo.yaml": (APP % mo.PLATFORM_URL).replace(
              "helm: {valueFiles: [$values/values/demo.yaml]}", "helm: {valuesObject: {x: 3}}")},
          [], [], refused="valuesObject")
# what the check cannot evaluate is refused, never skipped (each skipped, its applications went unjudged - the order
# proven for what it left out): a matrix other than list x pullRequest, another generator, a value file from outside
# infra
sets_case("a matrix of two lists: refused",
          {"clusters/production/argocd/apps/previews.yaml": SET_MATRIX.replace(
              "- pullRequest: {gitea: {owner: schnappy, repo: x}}", "- list: {elements: [{number: '7'}]}")},
          [], [], refused="list x pullRequest")
sets_case("a clusters generator: refused",
          {"clusters/production/argocd/apps/envs.yaml": SET_GIT.replace(
              "- git: {repoURL: https://git.pmon.dev/schnappy/infra.git, directories: [{path: clusters/production/envs/*}]}",
              "- clusters: {}")},
          [], [], refused="cannot evaluate")
sets_case("a value file from outside infra: refused",
          {"clusters/production/argocd/apps/demo.yaml": (APP % mo.PLATFORM_URL).replace(
              "helm: {valueFiles: [$values/values/demo.yaml]}", "helm: {valueFiles: [values/demo.yaml]}")},
          [], [], refused="is not from infra")
# as Argo CD renders: the cluster's Kubernetes version and API versions passed to every helm template
calls = open(os.environ["HELM_ARGS"]).read().splitlines()
check_ = lambda name, ok: (print(f"{'PASS' if ok else 'FAIL'} {name}"), ok)[1]
fails += not check_("every render with the step's --kube-version and --api-versions",
                    calls and all("--kube-version 1.34.12 --api-versions monitoring.coreos.com/v1,v1" in c for c in calls))
loader2 = importlib.machinery.SourceFileLoader("mo2", os.path.join(ROOT, "scripts", "upgrade-merge-order.py"))
real = importlib.util.module_from_spec(importlib.util.spec_from_loader("mo2", loader2))
loader2.exec_module(real)
caps = real.capabilities("34-argocd-3.5")
fails += not check_("step 34's capabilities: Kubernetes 1.34.12 (13's, before it), production's API list",
                    caps[:2] == ["--kube-version", "1.34.12"] and "monitoring.coreos.com/v1" in caps[3].split(","))
# as the cluster runs when the step's merges land: before the step - a kubeadm step upgrades after its merge
fails += not check_("step 43's: 1.35.9 (its merge lands before its kubeadm upgrade to 1.36.5)",
                    real.capabilities("43-kubernetes-1.36")[:2] == ["--kube-version", "1.35.9"])
# Argo CD passes group/version/Kind too: a chart gated on "monitoring.coreos.com/v1/ServiceMonitor" rendered nothing
# under either Helm, and the comparison passed without the object
apis = caps[3].split(",")
fails += not check_("the API list holds group/version/Kind as Argo passes it (a ServiceMonitor's)",
                    "monitoring.coreos.com/v1/ServiceMonitor" in apis and "v1/ConfigMap" in apis)
versions = [a for a in apis if a == "v1" or (a.count("/") == 1 and not a.startswith("v1/"))]  # v1/<Kind>: core kinds
fails += not check_("every group/version in it with its kinds", len(versions) > 50 and all(
    any(k.startswith(gv + "/") and k.count("/") == gv.count("/") + 1 for k in apis) for gv in versions))
print("upgrade-merge-order: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
raise SystemExit(1 if fails else 0)
PY
