#!/bin/bash
# scripts/argo-helm-diff.py's verdict on a step's helm-diff line, the renders stubbed: the same objects under both Helm
# versions pass; an object only one renders, or rendered otherwise, fails naming it; nothing rendered under either
# fails - "the same" over no application proves nothing.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PY'
import contextlib, importlib.machinery, importlib.util, io, os, sys, tempfile
loader = importlib.machinery.SourceFileLoader("hd", "scripts/argo-helm-diff.py")
hd = importlib.util.module_from_spec(importlib.util.spec_from_loader("hd", loader))
loader.exec_module(hd)
work = tempfile.mkdtemp()
os.makedirs(os.path.join(work, ".upgrade"))
open(os.path.join(work, "34-x.txt"), "w").write("helm-diff 3.19.4 4.2.1\n")
hd.STEPS, hd.OPS = work, work
hd.WORK = os.path.join(work, "clean", ".upgrade")  # as CI's fresh checkout has it: not there yet
hd.mo.refs = lambda step: {"infra": "i", "platform": "p"}
hd.helm_binary = lambda version: version
CAPS = ["--kube-version", "1.34.12", "--api-versions", "v1"]
hd.mo.capabilities = lambda step: CAPS
CM = "apiVersion: v1\nkind: ConfigMap\nmetadata: {name: c, namespace: n}\ndata: {k: %s}\n"
fails = 0
def check(name, renders, want, words):
    global fails
    hd.renders = lambda helm, refs, w: renders[helm]
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        got = hd.check("34-x")
    ok = got == want and all(x in out.getvalue() for x in words)
    fails += not ok
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f" (returned {got})\n{out.getvalue()}"))
check("the same objects: passes", {"3.19.4": {"a": CM % 1}, "4.2.1": {"a": CM % 1}}, True,
      ["render the same", "1 applications"])
check("an object rendered otherwise: fails, named", {"3.19.4": {"a": CM % 1}, "4.2.1": {"a": CM % 2}}, False,
      ["a: ConfigMap/n/c (differs)"])
check("nothing rendered: fails", {"3.19.4": {}, "4.2.1": {}}, False, ["nothing proven"])
check_caps = hd.mo.CAPABILITIES == CAPS
fails += not check_caps
print(f"{'PASS' if check_caps else 'FAIL'} the step's --kube-version and --api-versions set for both renders")
# upstream charts (the Application names a chart, not a path): rendered as Argo CD renders them - the chart from its
# repository (an OCI one by oci://), its version, the release and namespace, the CRDs, the cluster's version and API
# versions, the infra value files, inline values and valuesObject, parameters (forceString as --set-string); a stub
# helm records every argument
import json, subprocess
up = tempfile.mkdtemp()
infra = os.path.join(up, "infra")
subprocess.run(["git", "init", "-q", "-b", "main", infra], check=True)
os.makedirs(os.path.join(infra, "clusters/production/argocd/apps"))
os.makedirs(os.path.join(infra, "values"))
open(os.path.join(infra, "values/up.yaml"), "w").write("fromfile: 1\n")
open(os.path.join(infra, "clusters/production/argocd/apps/up.yaml"), "w").write("""apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: up}
spec:
  destination: {namespace: upns}
  sources:
    - repoURL: https://charts.example.com/
      chart: thing
      targetRevision: 1.2.3
      helm:
        releaseName: rel
        valueFiles: [$values/values/up.yaml]
        values: "inline: 2"
        valuesObject: {object: 3}
        parameters: [{name: a, value: "1", forceString: true}, {name: b, value: "2"}]
    - {repoURL: https://git.pmon.dev/schnappy/infra.git, ref: values}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: oci}
spec:
  destination: {namespace: ocins}
  source: {repoURL: registry.example.com/charts, chart: other, targetRevision: 4.5.6}
""")
subprocess.run(["git", "-C", infra, "-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], check=True)
subprocess.run(["git", "-C", infra, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "c"], check=True)
helm = os.path.join(up, "helm")
open(helm, "w").write("#!/usr/bin/env python3\nimport json, os, sys\n"
                      "files = {a: open(a).read() for a in sys.argv if a.endswith('.yaml') and os.path.exists(a)}\n"
                      f"open({os.path.join(up, 'argv')!r}, 'a').write(json.dumps([sys.argv[1:], files]) + '\\n')\n"
                      "print('kind: ConfigMap\\nmetadata: {name: x}')\n")
os.chmod(helm, 0o755)
hd.mo.REPOS = {"infra": infra}
hd.mo.CAPABILITIES[:] = CAPS
work_up = os.path.join(up, "work"); os.makedirs(work_up)
got = hd.upstream(helm, "main", work_up)
calls = {c[0][1]: c for c in (json.loads(l) for l in open(os.path.join(up, "argv")))}
args, files = calls["rel"]
check_ = lambda name, ok, detail="": (print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f": {detail}")), ok)[1]
fails += not check_("upstream: both applications rendered", sorted(got) == ["oci", "up"], sorted(got))
fails += not check_("upstream: the chart from its repository at its version, the release in its namespace",
                    args[:7] == ["template", "rel", "thing", "--repo", "https://charts.example.com", "--version", "1.2.3"]
                    and args[args.index("-n") + 1] == "upns", args)
fails += not check_("upstream: its CRDs and the cluster's version and API versions",
                    "--include-crds" in args and all(c in args for c in CAPS), args)
contents = sorted(files.values())
fails += not check_("upstream: the infra value file, the inline values and valuesObject, each a file",
                    contents == sorted(["fromfile: 1\n", "inline: 2", "object: 3\n"]), contents)
fails += not check_("upstream: parameters - forceString as --set-string",
                    "--set-string" in args and args[args.index("--set-string") + 1] == "a=1"
                    and args[args.index("--set") + 1] == "b=2", args)
fails += not check_("upstream: an OCI chart by oci://", calls["oci"][0][2] == "oci://registry.example.com/charts/other",
                    calls["oci"][0])
fails += not check_("which Helm renders it: only the old one, only the new one",
                    [hd.where("k", {"k": 1}, {}, "3.19", "4.2"), hd.where("k", {}, {"k": 1}, "3.19", "4.2")]
                    == ["only 3.19", "only 4.2"])
print("argo-helm-diff: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
