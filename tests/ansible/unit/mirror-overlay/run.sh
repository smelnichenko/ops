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
# production's main: origin's (a change is judged against it, never against a local main)
git("update-ref", "refs/remotes/origin/main", "main")
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
# production's main moved on after c-ok was cut, in a file the overlay drops: the change is c-ok's own diff
# (origin/main...ref), not main's moves since read backwards (..) - accepted. The local main stays behind (not fetched
# into): a change cut from production's new main is judged against origin's, never against the stale local one
git("checkout", "-q", "-b", "prod", "main")
open(os.path.join(g, "clusters/production/argocd/apps/woodpecker.yaml"), "a").write("# main moved\n")
git("commit", "-q", "-am", "main moved")
git("update-ref", "refs/remotes/origin/main", "prod")
check("a change cut before production's main moved a dropped file: its own diff judged, accepted", refused("c-ok"), None)
git("checkout", "-q", "-b", "c-new", "prod")
open(os.path.join(g, "clusters/production/argocd/apps/velero.yaml"), "a").write("# new\n")
git("commit", "-q", "-am", "new")
check("a change cut from production's main, the local main behind it: accepted (production's moves are not its own)",
      refused("c-new"), None)
# a rename out of a dropped path: the old path gone counts - refused
git("checkout", "-q", "-b", "c-rename", "prod")
os.makedirs(os.path.join(g, "elsewhere"))
git("mv", "clusters/production/argocd/apps/woodpecker.yaml", "elsewhere/woodpecker.yaml")
git("commit", "-q", "-m", "rename")
r = refused("c-rename")
check("a rename out of a dropped path: refused, the old path named",
      (r is not None and "REFUSED" in r, "clusters/production/argocd/apps/woodpecker.yaml" in (r or "")), (True, True))
# a values key the overlay's <name>.vagrant.yaml sets too: the copy runs the overlay's value - refused, the key named;
# a key beside it, mirrored; a whole subtree replaced over the overlay's key, refused
check("masked_keys: a key the overlay sets, one under it, one over it - not one beside it",
      m.masked_keys({"s": {"d": {"paused": False, "ttl": "1h"}, "l": [1]}},
                    {"s": {"d": {"paused": True, "ttl": "2h"}, "l": [2]}, "n": {"x": 1}},
                    {"s": {"d": {"paused": True}}, "n": 0}),
      ["n.x", "s.d.paused"])
check("masked_keys: a key set whole (null to a list) where the overlay sets one under it: masked",
      m.masked_keys({"x": None}, {"x": [1]}, {"x": {"y": 1}}), ["x"])
kov = os.path.join(work, "key-overlay")
os.makedirs(os.path.join(kov, "infra/clusters/production/velero"))
open(os.path.join(kov, "infra/clusters/production/velero/values.vagrant.yaml"), "w").write(
    "schedules:\n  daily:\n    paused: true\n")
git("checkout", "-q", "-b", "values-base", "prod")
os.makedirs(os.path.join(g, "clusters/production/velero"))
open(os.path.join(g, "clusters/production/velero/values.yaml"), "w").write(
    "schedules:\n  daily:\n    paused: false\n    ttl: 1h\n")
git("add", "-A"); git("commit", "-q", "-m", "values")
git("update-ref", "refs/remotes/origin/main", "values-base")
def values_change(branch, text):
    git("checkout", "-q", "-b", branch, "values-base")
    open(os.path.join(g, "clusters/production/velero/values.yaml"), "w").write(text)
    git("commit", "-q", "-am", branch)
real_overlay, m.OVERLAY = m.OVERLAY, kov
values_change("k-paused", "schedules:\n  daily:\n    paused: true\n    ttl: 1h\n")
values_change("k-ttl", "schedules:\n  daily:\n    paused: false\n    ttl: 2h\n")
values_change("k-whole", "schedules: []\n")
r1, r2, r3 = refused("k-paused"), refused("k-ttl"), refused("k-whole")
m.OVERLAY = real_overlay
check("a values key the overlay sets (schedules.daily.paused): refused, the file and key named",
      (r1 is not None and "REFUSED" in r1, "clusters/production/velero/values.yaml: schedules.daily.paused" in (r1 or "")),
      (True, True))
check("  a key beside it (ttl): mirrored", r2, None)
check("  the subtree replaced over it: refused", r3 is not None and "REFUSED" in r3, True)
# the overlay's own files: a change to a path the overlay writes over is refused
ov = os.path.join(work, "overlay")
os.makedirs(os.path.join(ov, "infra/clusters/production/argocd/apps"))
open(os.path.join(ov, "infra/clusters/production/argocd/apps/velero.yaml"), "w").write("x")
real_overlay, m.OVERLAY = m.OVERLAY, ov
r = refused("c-ok")
m.OVERLAY = real_overlay
check("a change to a file the overlay replaces (walked from the overlay directory): refused, named",
      (r is not None and "REFUSED" in r, "velero.yaml" in (r or "")), (True, True))
# main() refuses before anything is cloned or pushed - infra's drop list for infra, platform's for platform
pg = os.path.join(work, "platform-git")
os.makedirs(os.path.join(pg, "helm/schnappy-mesh/templates"))
subprocess.run(["git", "-C", pg, "init", "-q", "-b", "main"], check=True)
open(os.path.join(pg, "helm/schnappy-mesh/templates/certificates.yaml"), "w").write("a: 1\n")
open(os.path.join(pg, "README"), "w").write("r\n")
for args in (["add", "-A"], ["commit", "-q", "-m", "main"], ["update-ref", "refs/remotes/origin/main", "main"],
             ["checkout", "-q", "-b", "p-masked"]):
    subprocess.run(["git", "-C", pg, "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True)
open(os.path.join(pg, "helm/schnappy-mesh/templates/certificates.yaml"), "a").write("b: 2\n")
subprocess.run(["git", "-C", pg, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-am", "masked"],
               check=True, capture_output=True)
calls = []
real = (m.api, m.run)
m.api = lambda *a, **k: calls.append(("api", a[3], a[4])) or 201
m.run = lambda *a, **k: calls.append(("run",) + a[:2])
def main_with(*argv):
    sys.argv = ["vagrant-gitops-mirror.py", "--infra", g, "--platform", pg, "--forgejo", "192.168.56.50:3000", *argv]
    try:
        m.main()
        return None
    except SystemExit as e:
        return str(e.code)
    except Exception as e:  # it went on past the refusal (the stubs do not clone): not refused
        return f"went on: {type(e).__name__}"
r = main_with("--infra-ref", "c-masked")
check("main(): an infra change to a dropped app refused before any API call or clone",
      (r is not None and "REFUSED" in r, calls), (True, []))
calls.clear()
r = main_with("--platform-ref", "p-masked")
check("main(): a platform change to its dropped file (platform's drop list) refused - before infra is touched",
      (r is not None and "REFUSED" in r, "certificates.yaml" in (r or ""), calls), (True, True, []))
m.api, m.run = real
print("mirror-overlay: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_MIRROR_OVERLAY
