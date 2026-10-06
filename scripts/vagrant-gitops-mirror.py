#!/usr/bin/env python3
"""vagrant-gitops-mirror.py — build the Vagrant copy of production's GitOps repos and push it to the Vagrant Forgejo.

The Vagrant upgrade test runs Argo CD against copies of infra and platform, so every upgrade step is the same git
change production gets. This script takes a committed ref of each repo (`main`, or an upgrade step's branch; never
the working tree), adds ONE overlay commit on top, and force-pushes it as `main` (the branch every Argo app tracks)
to the Vagrant Forgejo (pi1 VM) under the `schnappy` org:

  both repos
    - every production LAN address (192.168.11.x) rewritten to its Vagrant counterpart, and the push refused if any
      is left: the Vagrant cluster must not reach production's Vault, backup store or anything else.
  infra overlay
    - repo URLs https://git.pmon.dev/schnappy/<repo>.git -> the Vagrant Forgejo (application images still come from
      git.pmon.dev's registry);
    - left out (operator 2026-10-02: the VM has 20 GB, ten's pods use ~30 GB): the schnappy-test environment,
      kagent, SonarQube; and what cannot run outside production: Woodpecker (OAuth against git.pmon.dev) and the
      PR-environment generator (git.pmon.dev's API);
    - after every `$values/<dir>/<name>.yaml` value file, `$values/<dir>/<name>.vagrant.yaml` with
      ignoreMissingValueFiles: true; those files come from tests/ansible/upgrade/vagrant-overlay/infra/.
  platform overlay
    - left out: the *.pmon.dev wildcard's Certificate (schnappy-mesh). The Vagrant copy serves production's own
      certificate (tests/ansible/upgrade/production-state.yml, operator 2026-10-03), and a Certificate for that Secret
      makes cert-manager replace it at once ("Secret contains a private key that does not match the current
      CertificateRequest", 2026-10-03);
    - files from tests/ansible/upgrade/vagrant-overlay/platform/, if any.

An upgrade step is a branch of infra and/or platform changing the same files production's change would; mirrored
with --infra-ref/--platform-ref, Argo in Vagrant syncs it exactly as Argo on ten would sync it once merged.

Usage: scripts/vagrant-gitops-mirror.py [--infra ../infra] [--platform ../platform] [--forgejo 192.168.56.20:3000]
                                        [--infra-ref main] [--platform-ref main]
Env:   VAGRANT_FORGEJO_ADMIN_USER / VAGRANT_FORGEJO_ADMIN_PASSWORD (default: the Vagrant inventory's). Deliberately
       not FORGEJO_ADMIN_*: the Taskfile loads ops/.env, whose FORGEJO_ADMIN_* are PRODUCTION's credentials.
"""
import argparse
import base64
import ipaddress
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(OPS, ".upgrade")
OVERLAY = os.path.join(OPS, "tests", "ansible", "upgrade", "vagrant-overlay")
PROD_GIT = "https://git.pmon.dev/schnappy/"

# infra paths the Vagrant copy leaves out (relative to the repo root)
INFRA_DROP = [
    "clusters/production/argocd/apps/kagent.yaml",
    "clusters/production/argocd/apps/schnappy-sonarqube.yaml",
    "clusters/production/argocd/apps/schnappy-test.yaml",
    "clusters/production/argocd/apps/schnappy-pr-envs.yaml",
    "clusters/production/argocd/apps/woodpecker.yaml",
    "clusters/production/schnappy-test",
    "clusters/production/schnappy-test-apps",
    "clusters/production/schnappy-test-data",
    "clusters/production/schnappy-test-mesh",
]

# platform paths the Vagrant copy leaves out (see the docstring)
PLATFORM_DROP = [
    "helm/schnappy-mesh/templates/certificates.yaml",
]

# Production LAN -> Vagrant network. Every production address in BOTH repos (Vault, the Pi backup store, the gateway,
# NetworkPolicy ipBlocks, probes) is rewritten, so nothing the Vagrant cluster runs can reach production; push() then
# refuses a repo where any 192.168.11.x is left. (2026-10-02: the first Argo run's ESO tried production Vault.)
ADDRESS_MAP = [
    ("192.168.11.0/24", "192.168.56.0/24"),
    ("192.168.11.2", "192.168.56.10"),   # ten -> the kubeadm VM
    ("192.168.11.4", "192.168.56.20"),   # pi1
    ("192.168.11.5", "192.168.56.50"),   # the Pi VIP
    ("192.168.11.6", "192.168.56.21"),   # pi2
]
# anything else on the production LAN (prose like 192.168.11.{4,5,6}): the subnet, nothing more specific is known
PROD_LAN_PREFIX = ("192.168.11.", "192.168.56.")
PROD_LAN = re.compile(r"192\.168\.11\.")

# Changes to production's own files that are being proven in Vagrant before they go to infra (operator 2026-10-01:
# nothing reaches production until the Vagrant tests pass and the operator approves). Each: file -> sync wave.
# - the application sets wait for Istio (istiod wave 1, istio-cni wave 2): with argoproj.io/Application health in
#   argocd-cm the root app waits for those, so no meshed pod starts before the sidecar injector exists
# - once waves really wait (the health check above), the operators' own order matters: scylla-operator (wave -1) needs
#   cert-manager's CRDs (no wave = 0), and scylla-manager (also -1) needs scylla-operator's ScyllaCluster CRD
# - cluster-config (wave 0) holds ServiceMonitors, whose CRD comes with kube-prometheus-stack (was wave 3): Prometheus
#   moves to -1 with the other operators (its pods are not meshed on ten, so they need not wait for Istio)
INFRA_SYNC_WAVES = {
    "clusters/production/argocd/apps/cert-manager.yaml": "-2",
    "clusters/production/argocd/apps/prometheus.yaml": "-1",
    "clusters/production/argocd/apps/scylla-manager.yaml": "0",
    "clusters/production/argocd/apps/schnappy-mesh-envs.yaml": "4",
    "clusters/production/argocd/apps/schnappy-data-envs.yaml": "4",
    "clusters/production/argocd/apps/schnappy-realtime-envs.yaml": "4",
    "clusters/production/argocd/apps/schnappy-apps-envs.yaml": "4",
    # observability needs the infra data set's S3 secret and the mesh set's ServiceAccounts (both wave 4)
    "clusters/production/argocd/apps/schnappy-observability.yaml": "5",
}

VALUE_FILE = re.compile(r"^(?P<indent>\s*)- (?P<q>['\"]?)(?P<path>\$values/.+?)\.yaml(?P=q)\s*$")
HELM_KEY = re.compile(r"^(?P<indent>\s*)helm:\s*$")


def run(*cmd, cwd=None):
    subprocess.run(cmd, cwd=cwd, check=True)


def api(base, user, password, method, path, body=None, ok=(200, 201)):
    req = urllib.request.Request(f"http://{base}/api/v1{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status
    except urllib.error.HTTPError as e:
        if e.code in ok:
            return e.code
        raise


def add_vagrant_value_files(text):
    """After each `- $values/<p>.yaml` add `- $values/<p>.vagrant.yaml`; mark the source's helm block
    ignoreMissingValueFiles so an app without overlay values renders unchanged."""
    lines = text.split("\n")
    out = []
    helm_lines = []  # indices in `out` of helm: keys that need the flag
    last_helm = None
    for line in lines:
        m_helm = HELM_KEY.match(line)
        if m_helm:
            last_helm = len(out)
        out.append(line)
        m = VALUE_FILE.match(line)
        if m:
            q = m.group("q")
            out.append(f"{m.group('indent')}- {q}{m.group('path')}.vagrant.yaml{q}")
            if last_helm is not None and last_helm not in helm_lines:
                helm_lines.append(last_helm)
    for i in sorted(helm_lines, reverse=True):
        indent = HELM_KEY.match(out[i]).group("indent") + "  "
        block = out[i + 1:i + 20]
        if not any(l.strip() == "ignoreMissingValueFiles: true" for l in block):
            out.insert(i + 1, f"{indent}ignoreMissingValueFiles: true")
    return "\n".join(out)


def overlay_infra(repo, forgejo):
    drop(repo, "infra", INFRA_DROP)
    for rel, wave in INFRA_SYNC_WAVES.items():
        p = os.path.join(repo, rel)
        text = open(p).read()
        # infra carries these from the fresh-install step on: nothing to do where git has the wave already
        if f'argocd.argoproj.io/sync-wave: "{wave}"' in text:
            continue
        if "argocd.argoproj.io/sync-wave" in text:
            new = re.sub(r'(argocd\.argoproj\.io/sync-wave: )"[-0-9]+"', rf'\g<1>"{wave}"', text, count=1)
        else:
            new = re.sub(r"^(metadata:\n(?: {2}.*\n)*? {2}name: [^\n]+\n)",
                         lambda m, wave=wave:
                         m.group(1) + f'  annotations:\n    argocd.argoproj.io/sync-wave: "{wave}"\n',
                         text, count=1, flags=re.M)
        if new == text:
            sys.exit(f"infra overlay: could not add the sync wave to {rel}")
        open(p, "w").write(new)
    apps = os.path.join(repo, "clusters/production/argocd")
    changed = 0
    for root, _, files in os.walk(apps):
        for f in files:
            if not f.endswith((".yaml", ".yml")):
                continue
            p = os.path.join(root, f)
            text = open(p).read()
            new = text.replace(PROD_GIT, f"http://{forgejo}/schnappy/")
            new = add_vagrant_value_files(new)
            if new != text:
                open(p, "w").write(new)
                changed += 1
    if changed == 0:
        sys.exit("infra overlay: no Argo app was rewritten - the repo layout changed")


def drop(repo, name, rels):
    """Remove the paths the Vagrant copy leaves out; abort if one no longer exists (a stale list drops nothing)."""
    for rel in rels:
        p = os.path.join(repo, rel)
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.exists(p):
            os.remove(p)
        else:
            sys.exit(f"{name} overlay: {rel} does not exist in {name} main - the drop list is stale")


def isolate_from_production(repo):
    """Rewrite every production LAN address to its Vagrant counterpart; abort if one is left."""
    files = subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True, check=True).stdout.split()
    for rel in files:
        p = os.path.join(repo, rel)
        try:
            text = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue  # binary, or dropped by the overlay
        new = text
        for prod, vagrant in ADDRESS_MAP:
            new = re.sub(re.escape(prod) + r"(?![0-9])", vagrant, new)
        new = new.replace(*PROD_LAN_PREFIX)
        if new != text:
            open(p, "w", encoding="utf-8").write(new)
    left = []
    for rel in files:
        p = os.path.join(repo, rel)
        try:
            for i, line in enumerate(open(p, encoding="utf-8"), 1):
                if PROD_LAN.search(line):
                    left.append(f"{rel}:{i}: {line.strip()[:120]}")
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue
    if left:
        sys.exit("production addresses left after the rewrite (not pushed):\n" + "\n".join(left[:20]))


def copy_overlay(name, repo):
    src = os.path.join(OVERLAY, name)
    if os.path.isdir(src):
        shutil.copytree(src, repo, dirs_exist_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infra", default=os.path.join(OPS, "..", "infra"))
    ap.add_argument("--platform", default=os.path.join(OPS, "..", "platform"))
    ap.add_argument("--forgejo", default="192.168.56.20:3000")
    ap.add_argument("--infra-ref", default="main", help="infra branch to mirror (an upgrade step's)")
    ap.add_argument("--platform-ref", default="main", help="platform branch to mirror (an upgrade step's)")
    a = ap.parse_args()
    # the mirror pushes and rewrites repos: only ever into the Vagrant Forgejo (192.168.56.0/24), never production's
    host = a.forgejo.rsplit(":", 1)[0]
    try:
        vagrant = ipaddress.ip_address(host) in ipaddress.ip_network("192.168.56.0/24")
    except ValueError:
        vagrant = False
    if not vagrant:
        sys.exit(f"REFUSED: --forgejo {a.forgejo} is not a Vagrant address (192.168.56.0/24)")
    user = os.environ.get("VAGRANT_FORGEJO_ADMIN_USER", "forgejo_admin")
    password = os.environ.get("VAGRANT_FORGEJO_ADMIN_PASSWORD", "vagrant-forgejo-pw")

    api(a.forgejo, user, password, "POST", "/orgs", {"username": "schnappy", "visibility": "public"}, ok=(201, 422))
    os.makedirs(WORK, exist_ok=True)
    work = tempfile.mkdtemp(prefix="gitops-mirror-", dir=WORK)
    pushed = {}
    try:
        for name, src, ref in (("infra", a.infra, a.infra_ref), ("platform", a.platform, a.platform_ref)):
            api(a.forgejo, user, password, "POST", "/orgs/schnappy/repos",
                {"name": name, "default_branch": "main", "private": False}, ok=(201, 409))
            repo = os.path.join(work, name)
            run("git", "clone", "-q", "--branch", ref, "--single-branch", os.path.abspath(src), repo)
            head = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"],
                                  capture_output=True, text=True, check=True).stdout.strip()
            if name == "infra":
                overlay_infra(repo, a.forgejo)
            else:
                drop(repo, "platform", PLATFORM_DROP)
            copy_overlay(name, repo)
            isolate_from_production(repo)
            run("git", "-C", repo, "add", "-A")
            run("git", "-C", repo, "-c", "user.name=vagrant-mirror", "-c", "user.email=mirror@vagrant.test",
                "commit", "-q", "--allow-empty", "-m", f"vagrant overlay on {name} {ref} {head}")
            url = f"http://{user}:{password}@{a.forgejo}/schnappy/{name}.git"
            run("git", "-C", repo, "push", "-q", "--force", url, "HEAD:main")
            pushed[f"http://{a.forgejo}/schnappy/{name}.git"] = subprocess.run(
                ["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
            print(f"{name}: {ref} {head} + vagrant overlay pushed as main to http://{a.forgejo}/schnappy/{name}.git")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    # the commits Argo must sync to before the copy counts as settled (tests/ansible/upgrade/argo-settled.yml)
    with open(os.path.join(WORK, "mirror-revisions.json"), "w") as f:
        json.dump(pushed, f, indent=2)


if __name__ == "__main__":
    main()
