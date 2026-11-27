#!/bin/bash
# The branch rule of the two checks that hold ops' defaults to production (argocd-versions, defaults-follow-production),
# exercised on a copy of this tree with the defaults moved and the CI's variables set: equal to production passes
# anywhere; moved ahead passes only on a branch's push (an upgrade unit's), said; moved ahead fails on main's push, on a
# pull request, on a manual run and without CI; moved BACK fails on a branch's push too; and on the moved Argo CD chart
# a pinned image below production's fails. The CI's own variables never leak into a row (each runs with them unset, then
# set as the row says).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
tar --exclude=./.git --exclude=./.copy --exclude=./deploy/ansible/venv -cf - . | tar -C "$W" -xf -
[ -e deploy/ansible/venv ] && ln -s "$(cd deploy/ansible && pwd)/venv" "$W/deploy/ansible/venv"
W=$W python3 - <<'PY_BDS'
import os, re, subprocess
W = os.environ["W"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))

ARGO = os.path.join(W, "deploy/ansible/playbooks/setup-argocd.yml")
KUBEADM = os.path.join(W, "deploy/ansible/playbooks/setup-kubeadm.yml")
ORIG = {p: open(p).read() for p in (ARGO, KUBEADM)}
inventory = open(os.path.join(W, "tests/ansible/copy/prod-inventory.txt")).read()
prod_chart = re.search(r"(?m)^helm argocd/argocd argo-cd-(\S+) ", inventory)[1]
prod_image = re.search(r"(?m)^image quay\.io/argoproj/argocd (v\S+)$", inventory)[1]
prod_cm = re.search(r"(?m)^argo-chart cert-manager cert-manager@(\S+)$", inventory)[1]

def bump(version, by):
    """version with its second number moved by `by` (10.9.7 +1 -> 10.10.7; v1.21.3 -1 -> v1.20.3)"""
    parts = re.split(r"(\d+)", version)
    parts[3] = str(int(parts[3]) + by)
    return "".join(parts)

def set_var(path, key, value):
    text, n = re.subn(r'(?m)^(    %s: )"?[^"\s#]+"?' % re.escape(key), r'\g<1>"%s"' % value, ORIG[path])
    assert n == 1, (path, key)
    open(path, "w").write(text)

def run(harness, env):
    e = {k: v for k, v in os.environ.items() if not k.startswith("CI_")}
    e.update(env)
    r = subprocess.run(["bash", f"tests/ansible/unit/{harness}/run.sh"], cwd=W, env=e, capture_output=True, text=True,
                       timeout=300)
    return r.returncode, r.stdout + r.stderr

PUSH = lambda branch: {"CI_PIPELINE_EVENT": "push", "CI_COMMIT_BRANCH": branch}
ROWS = [  # (name, env, ok expected)
    ("without CI", {}, False),
    ("on renovate/x's push", PUSH("renovate/x"), True),
    ("on main's push", PUSH("main"), False),
    ("on a pull request", {"CI_PIPELINE_EVENT": "pull_request", "CI_COMMIT_BRANCH": "renovate/x",
                           "CI_COMMIT_TARGET_BRANCH": "main"}, False),
    ("on a manual run", {"CI_PIPELINE_EVENT": "manual", "CI_COMMIT_BRANCH": "renovate/x"}, False),
]

# ── argocd-versions ────────────────────────────────────────────────────────────────────────────────────────────
for p in ORIG:
    open(p, "w").write(ORIG[p])
rc, out = run("argocd-versions", PUSH("renovate/x"))
check("argocd-versions, the default equal to production's: passes on a branch's push", rc, 0)
ahead = bump(prod_chart, 1)
set_var(ARGO, "argocd_chart_default", ahead)
for name, env, ok in ROWS:
    if name == "on a pull request":
        continue  # argocd-versions reads no target: a pull request is strict (CI runs on pushes)
    rc, out = run("argocd-versions", env)
    check(f"argocd-versions, the chart moved ahead ({prod_chart} -> {ahead}) {name}: " + ("passes, said" if ok else "fails"),
          (rc == 0, "moves it ahead (an upgrade unit)" in out), (ok, ok))
rc, out = run("argocd-versions", {"CI_PIPELINE_EVENT": "pull_request", "CI_COMMIT_BRANCH": "renovate/x"})
check("argocd-versions, the chart moved ahead on a pull request: fails (no target read here)", rc == 0, False)
back = bump(prod_chart, -1)
set_var(ARGO, "argocd_chart_default", back)
rc, out = run("argocd-versions", PUSH("renovate/x"))
check(f"argocd-versions, the chart moved BACK ({prod_chart} -> {back}) on a branch's push: fails", rc == 0, False)
low = "v3.4.10" if prod_image > "v3.4.10" else "v0.0.1"
text = ORIG[ARGO]
text = re.sub(r'(?m)^(    argocd_chart_default: )"?[^"\s#]+"?', r'\g<1>"%s"' % ahead, text, count=1)
text, n = re.subn(r"(?m)^(    argocd_image_pins:)[^\n]*\n", lambda m: f'{m.group(1)}\n      "{ahead}": {low}\n', text, count=1)
assert n == 1
open(ARGO, "w").write(text)
rc, out = run("argocd-versions", PUSH("renovate/x"))
check(f"argocd-versions, the chart moved ahead with a pin below production's image ({low} < {prod_image}) on a branch's "
      "push: fails", (rc == 0, f"the image pinned on the moved chart {ahead}" in out), (False, True))
open(ARGO, "w").write(ORIG[ARGO])

# ── defaults-follow-production ─────────────────────────────────────────────────────────────────────────────────
rc, out = run("defaults-follow-production", PUSH("renovate/x"))
check("defaults-follow-production, every default equal to production's: passes on a branch's push", rc, 0)
ahead_cm = bump(prod_cm, 1)
set_var(KUBEADM, "cert_manager_version", ahead_cm)
for name, env, ok in ROWS:
    if name == "on a pull request":
        continue  # judged against its target (the clone's origin/main): another row below
    rc, out = run("defaults-follow-production", env)
    check(f"defaults-follow-production, cert-manager moved ahead ({prod_cm} -> {ahead_cm}) {name}: "
          + ("passes, said" if ok else "fails"), (rc == 0, "push moves it ahead" in out), (ok, ok))
back_cm = bump(prod_cm, -1)
set_var(KUBEADM, "cert_manager_version", back_cm)
rc, out = run("defaults-follow-production", PUSH("renovate/x"))
check(f"defaults-follow-production, cert-manager moved BACK ({prod_cm} -> {back_cm}) on a branch's push: fails, said",
      (rc == 0, "moves it BACK, below production" in out), (False, True))
open(KUBEADM, "w").write(ORIG[KUBEADM])
print("branch-defaults-self: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
raise SystemExit(1 if fails else 0)
PY_BDS
