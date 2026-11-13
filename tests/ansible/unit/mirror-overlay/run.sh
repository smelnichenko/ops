#!/bin/bash
# scripts/vagrant-gitops-mirror.py's overlay: the address rewrite's digit guard (192.168.11.20 is not ten's .11.2 with a
# 0 after it); overlay_infra dropping what the copy leaves out and pointing every app at the copy's Forgejo (repo URL,
# the Vagrant value files) - and leaving production's sync waves as infra holds them (it rewrote eight to fixed values,
# undoing a change that moved one); a change that touches what the overlay drops or replaces refused (it would pass
# untested), main never; the overlay read from the repo's own directory.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
exec python3 - "$PWD" <<'PY_MIRROR_OVERLAY'
import atexit, importlib.machinery, importlib.util, os, shutil, subprocess, sys, tempfile
ops = sys.argv[1]
L = importlib.machinery.SourceFileLoader("mirror", os.path.join(ops, "scripts", "vagrant-gitops-mirror.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("mirror", L))
L.exec_module(m)
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
work = tempfile.mkdtemp()
atexit.register(shutil.rmtree, work, True)
APP = ("apiVersion: argoproj.io/v1alpha1\nkind: Application\nmetadata:\n  name: cert-manager\n  namespace: argocd\n"
       "  annotations:\n    argocd.argoproj.io/sync-wave: \"7\"\n"
       "  finalizers:\n    - resources-finalizer.argocd.argoproj.io\nspec:\n  project: default\n")
# the address rewrite: ten's 192.168.11.2 rewritten, .11.20 (not ten) by the subnet alone
p = os.path.join(work, "values.yaml")
open(p, "w").write("ten: 192.168.11.2\napi: 192.168.11.2:6443\nother: 192.168.11.20\nvip: 192.168.11.5\n")
m.rewrite_addresses(p)
check("rewrite_addresses: .11.2 -> ten's VM, .11.20 -> .56.20 (no digit after an address it maps)", open(p).read(),
      "ten: 192.168.56.10\napi: 192.168.56.10:6443\nother: 192.168.56.20\nvip: 192.168.56.50\n")
# overlay_infra on an infra tree: what it drops, the waves, and every app pointed at the copy's Forgejo
repo = tempfile.mkdtemp()
atexit.register(shutil.rmtree, repo, True)
apps = os.path.join(repo, "clusters/production/argocd/apps")
os.makedirs(apps)
for rel in m.INFRA_DROP:
    full = os.path.join(repo, rel)
    if rel.endswith(".yaml"):
        open(full, "w").write(APP)
    else:
        os.makedirs(full)
HELM_APP = APP + ("  sources:\n    - repoURL: https://charts.jetstack.io\n      chart: cert-manager\n      helm:\n"
                  "        valueFiles:\n          - $values/clusters/production/cert-manager/values.yaml\n"
                  "    - repoURL: https://git.pmon.dev/schnappy/infra.git\n      targetRevision: main\n      ref: values\n")
open(os.path.join(apps, "cert-manager.yaml"), "w").write(HELM_APP)
try:
    m.overlay_infra(repo, "192.168.56.50:3000")
    stopped = None
except SystemExit as e:
    stopped = str(e.code)
check("overlay_infra: runs through", stopped, None)
got = open(os.path.join(repo, "clusters/production/argocd/apps/cert-manager.yaml")).read()
check("overlay_infra: the drop list gone", [r for r in m.INFRA_DROP if os.path.exists(os.path.join(repo, r))], [])
check("overlay_infra: the app's sync wave as infra holds it (a change's wave reaches the copy)",
      'argocd.argoproj.io/sync-wave: "7"' in got, True)
check("overlay_infra: the app's repo URL the copy's Forgejo, none of production's left",
      ("repoURL: http://192.168.56.50:3000/schnappy/infra.git" in got, "git.pmon.dev" in got), (True, False))
check("overlay_infra: the Vagrant value file after the app's, missing ones ignored",
      ("- $values/clusters/production/cert-manager/values.vagrant.yaml" in got,
       "ignoreMissingValueFiles: true" in got), (True, True))
# the overlay the mirror copies over infra is the repo's own: a path left at the directory's old name (tests/ansible/
# upgrade, before the directory's rename) copied nothing, every case above passing on its fixture
check("the overlay it copies is the repo's (its Vagrant values among it)",
      os.path.isfile(os.path.join(m.OVERLAY, "infra/clusters/production/schnappy-production-apps/values.vagrant.yaml")),
      True)
# a change's paths the overlay drops (a path, or one under it) or replaces: refused - main never
check("masked: a dropped file, one under a dropped directory, a replaced file; nothing else",
      m.masked(["a/x.yaml", "d/sub/y.yaml", "dd/z.yaml", "r/f.yaml", "ok.yaml"], ["a/x.yaml", "d"], {"r/f.yaml"}),
      ["a/x.yaml", "d/sub/y.yaml", "r/f.yaml"])
g = os.path.join(work, "infra-git")
os.makedirs(os.path.join(g, "clusters/production/argocd/apps"))
def git(*a):
    subprocess.run(["git", "-C", g, "-c", "user.name=t", "-c", "user.email=t@t", *a], check=True, capture_output=True)
git("init", "-q", "-b", "main")
open(os.path.join(g, "clusters/production/argocd/apps/woodpecker.yaml"), "w").write(APP)
open(os.path.join(g, "clusters/production/argocd/apps/velero.yaml"), "w").write(APP)
git("add", "-A"); git("commit", "-q", "-m", "main")
git("checkout", "-q", "-b", "c-ok")
open(os.path.join(g, "clusters/production/argocd/apps/velero.yaml"), "a").write("# changed\n")
git("commit", "-q", "-am", "ok")
git("checkout", "-q", "-b", "c-masked")
open(os.path.join(g, "clusters/production/argocd/apps/woodpecker.yaml"), "a").write("# changed\n")
git("commit", "-q", "-am", "masked")
def refused(ref):
    try:
        m.refuse_masked("infra", g, ref, m.INFRA_DROP)
        return None
    except SystemExit as e:
        return str(e.code)
r = refused("c-masked")
check("a change to a dropped app: refused, the path named",
      (r is not None and "REFUSED" in r, "woodpecker.yaml" in (r or ""), "velero.yaml" in (r or "")), (True, True, False))
check("a change outside the overlay: mirrored", refused("c-ok"), None)
check("main: never refused", refused("main"), None)
print("mirror-overlay: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_MIRROR_OVERLAY
