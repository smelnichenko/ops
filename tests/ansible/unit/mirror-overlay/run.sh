#!/bin/bash
# scripts/vagrant-gitops-mirror.py's infra overlay on real-shaped Argo manifests. The sync wave's annotation goes after
# the first metadata: block's own `  name: <value>` line - found by a line walk (metadata_name_end) since the regex it
# replaced backtracked super-linearly (Sonar S5852); that regex, with the rest of the old code, is kept here as the
# oracle: every case, and every sequence of up to 4 of 11 line shapes, gives what it gave (a top-level name, a nested
# one, an empty "name: ", a blank or one-space line ending the block, no final newline, a second metadata: block, an
# annotation there already). Also pinned: the address rewrite's digit guard (192.168.11.20 is not ten's .11.2 with a 0
# after it), and that overlay_infra points every app at the copy's Forgejo (repo URL, the Vagrant value files).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
exec python3 - "$PWD" <<'PY_MIRROR_OVERLAY'
import atexit, importlib.machinery, importlib.util, itertools, os, re, shutil, sys, tempfile
ops = sys.argv[1]
L = importlib.machinery.SourceFileLoader("mirror", os.path.join(ops, "scripts", "vagrant-gitops-mirror.py"))
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("mirror", L))
L.exec_module(m)
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def old_overlay(text, wave):
    """The overlay's sync-wave code before the line walk (git show 01ec8e1^:scripts/vagrant-gitops-mirror.py): the new
    text, or the exit it made."""
    if f'argocd.argoproj.io/sync-wave: "{wave}"' in text:
        return text
    if "argocd.argoproj.io/sync-wave" in text:
        new = re.sub(r'(argocd\.argoproj\.io/sync-wave: )"[-0-9]+"', rf'\g<1>"{wave}"', text, count=1)
    else:
        new = re.sub(r"^(metadata:\n(?: {2}.*\n)*? {2}name: [^\n]+\n)",
                     lambda mt: mt.group(1) + f'  annotations:\n    argocd.argoproj.io/sync-wave: "{wave}"\n',
                     text, count=1, flags=re.M)
    return "EXIT could not add" if new == text else new
work = tempfile.mkdtemp()
atexit.register(shutil.rmtree, work, True)
def new_overlay(text, wave):
    """set_sync_wave on the text as a file of a repo: the file it leaves, or the exit it made."""
    p = os.path.join(work, "app.yaml")
    open(p, "w").write(text)
    try:
        m.set_sync_wave(work, "app.yaml", wave)
    except SystemExit as e:
        return "EXIT could not add" if "could not add the sync wave" in str(e.code) else f"EXIT {e.code}"
    return open(p).read()
ANN = '  annotations:\n    argocd.argoproj.io/sync-wave: "-2"\n'
APP = ("apiVersion: argoproj.io/v1alpha1\nkind: Application\nmetadata:\n  name: cert-manager\n  namespace: argocd\n"
       "  finalizers:\n    - resources-finalizer.argocd.argoproj.io\nspec:\n  project: default\n")
APPSET = ("apiVersion: argoproj.io/v1alpha1\nkind: ApplicationSet\nmetadata:\n  labels:\n    name: not-this\n"
          "  name: schnappy-mesh-envs\n  namespace: argocd\nspec:\n  template:\n    metadata:\n"
          "      name: '{{ .path.basenameNormalized }}'\n")
cases = [  # (case, text, the text with the annotation, None: refused)
    ("a top-level name", APP, APP.replace("  name: cert-manager\n", "  name: cert-manager\n" + ANN)),
    ("a 4-space nested name (labels') before the block's own", APPSET,
     APPSET.replace("  name: schnappy-mesh-envs\n", "  name: schnappy-mesh-envs\n" + ANN)),
    ("an empty 'name: ' is no name: the next block's", "metadata:\n  name: \n  namespace: argocd\n---\nmetadata:\n"
     "  name: second\n", "metadata:\n  name: \n  namespace: argocd\n---\nmetadata:\n  name: second\n" + ANN),
    ("an empty 'name: ' alone: refused", "metadata:\n  name: \n  namespace: argocd\n", None),
    ("a blank line before the name ends the block: refused", "metadata:\n\n  name: x\n", None),
    ("a one-space-indented file: its labels' name is no metadata name, refused",
     "metadata:\n labels:\n  name: x\n", None),
    ("the name the last line, no final newline: refused", "kind: Application\nmetadata:\n  name: x", None),
    ("no final newline after a later line: added", "metadata:\n  name: x\n  namespace: y",
     "metadata:\n  name: x\n" + ANN + "  namespace: y"),
    ("a second metadata: block (the first without a name): the second's", "metadata:\n  labels:\n    a: b\nspec:\n"
     "  name: spec-name\n---\nmetadata:\n  name: two\n", "metadata:\n  labels:\n    a: b\nspec:\n  name: spec-name\n"
     "---\nmetadata:\n  name: two\n" + ANN),
    ("two metadata: blocks with names: the first's only", "metadata:\n  name: one\n---\nmetadata:\n  name: two\n",
     "metadata:\n  name: one\n" + ANN + "---\nmetadata:\n  name: two\n"),
    ("a sync-wave annotation there already: updated", APP.replace("  name: cert-manager\n", "  name: cert-manager\n"
     "  annotations:\n    argocd.argoproj.io/sync-wave: \"3\"\n"), APP.replace("  name: cert-manager\n",
                                                                     "  name: cert-manager\n" + ANN)),
    ("the wave there already: left as it is", APP.replace("  name: cert-manager\n", "  name: cert-manager\n" + ANN),
     APP.replace("  name: cert-manager\n", "  name: cert-manager\n" + ANN)),
    ("no metadata: at all: refused", "kind: Application\nspec:\n  name: x\n", None),
]
for name, text, want in cases:
    want = "EXIT could not add" if want is None else want
    got = new_overlay(text, "-2")
    check(f"sync wave, {name}", got, want)
    check(f"sync wave, {name}: as the old regex did", got, old_overlay(text, "-2"))
# where the walk stops, against the regex's group end - every sequence of up to 4 line shapes, with and without the
# final newline
SHAPES = ["metadata:", "  name: a", "  name: ", "    name: b", " x: y", "", "spec:", "  labels:", "---",
          "  namespace: c", "metadata: {}"]
OLD = re.compile(r"^(metadata:\n(?: {2}.*\n)*? {2}name: [^\n]+\n)", re.M)
differ, n = [], 0
for k in range(1, 5):
    for seq in itertools.product(SHAPES, repeat=k):
        for tail in ("\n", ""):
            text = "\n".join(seq) + tail
            mt = OLD.search(text)
            n += 1
            if m.metadata_name_end(text) != (mt.end() if mt else None):
                differ.append(text)
check(f"metadata_name_end: where the regex's match ended, on all {n} sequences", differ[:3], [])
check("metadata_name_end: found where there is one (the sweep not all None)",
      m.metadata_name_end("metadata:\n  name: a\n"), len("metadata:\n  name: a\n"))
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
for rel in m.INFRA_SYNC_WAVES:
    open(os.path.join(repo, rel), "w").write(HELM_APP)
try:
    m.overlay_infra(repo, "192.168.56.50:3000")
    stopped = None
except SystemExit as e:
    stopped = str(e.code)
check("overlay_infra: runs through", stopped, None)
got = open(os.path.join(repo, "clusters/production/argocd/apps/cert-manager.yaml")).read()
check("overlay_infra: the drop list gone", [r for r in m.INFRA_DROP if os.path.exists(os.path.join(repo, r))], [])
check("overlay_infra: the app's sync wave", 'argocd.argoproj.io/sync-wave: "-2"' in got, True)
check("overlay_infra: the app's repo URL the copy's Forgejo, none of production's left",
      ("repoURL: http://192.168.56.50:3000/schnappy/infra.git" in got, "git.pmon.dev" in got), (True, False))
check("overlay_infra: the Vagrant value file after the app's, missing ones ignored",
      ("- $values/clusters/production/cert-manager/values.vagrant.yaml" in got,
       "ignoreMissingValueFiles: true" in got), (True, True))
print("mirror-overlay: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY_MIRROR_OVERLAY
