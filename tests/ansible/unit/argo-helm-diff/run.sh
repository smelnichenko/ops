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
print("argo-helm-diff: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
