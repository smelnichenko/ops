#!/usr/bin/env python3
"""vagrant-gitops-mirror.py — build the Vagrant copy of production's GitOps repos and push it to the Vagrant Forgejo.

The Vagrant upgrade test runs Argo CD against copies of infra and platform, so every upgrade step is the same git
change production gets. This script takes each repo's committed `main` (never the working tree), adds ONE overlay
commit on top, and force-pushes it to the Vagrant Forgejo (pi1 VM) under the `schnappy` org:

  infra overlay
    - repo URLs https://git.pmon.dev/schnappy/<repo>.git -> the Vagrant Forgejo (application images still come from
      git.pmon.dev's registry);
    - left out (operator 2026-10-02: the VM has 20 GB, ten's pods use ~30 GB): the schnappy-test environment,
      kagent, SonarQube; and what cannot run outside production: Woodpecker (OAuth against git.pmon.dev) and the
      PR-environment generator (git.pmon.dev's API);
    - after every `$values/<dir>/<name>.yaml` value file, `$values/<dir>/<name>.vagrant.yaml` with
      ignoreMissingValueFiles: true; those files come from tests/ansible/upgrade/vagrant-overlay/infra/.
  platform overlay
    - files from tests/ansible/upgrade/vagrant-overlay/platform/, if any.

Upgrade steps are later commits on top of the overlay, changing the same files production's would.

Usage: scripts/vagrant-gitops-mirror.py [--infra ../infra] [--platform ../platform] [--forgejo 192.168.56.20:3000]
Env:   FORGEJO_ADMIN_USER (default forgejo_admin), FORGEJO_ADMIN_PASSWORD (default: the Vagrant inventory's)
"""
import argparse
import base64
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
    for rel in INFRA_DROP:
        p = os.path.join(repo, rel)
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.exists(p):
            os.remove(p)
        else:
            sys.exit(f"infra overlay: {rel} does not exist in infra main - the drop list is stale")
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


def copy_overlay(name, repo):
    src = os.path.join(OVERLAY, name)
    if os.path.isdir(src):
        shutil.copytree(src, repo, dirs_exist_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--infra", default=os.path.join(OPS, "..", "infra"))
    ap.add_argument("--platform", default=os.path.join(OPS, "..", "platform"))
    ap.add_argument("--forgejo", default="192.168.56.20:3000")
    a = ap.parse_args()
    user = os.environ.get("FORGEJO_ADMIN_USER", "forgejo_admin")
    password = os.environ.get("FORGEJO_ADMIN_PASSWORD", "vagrant-forgejo-pw")

    api(a.forgejo, user, password, "POST", "/orgs", {"username": "schnappy", "visibility": "public"}, ok=(201, 422))
    work = tempfile.mkdtemp(prefix="gitops-mirror-", dir=os.path.join(OPS, ".upgrade") if os.path.isdir(
        os.path.join(OPS, ".upgrade")) else None)
    try:
        for name, src in (("infra", a.infra), ("platform", a.platform)):
            api(a.forgejo, user, password, "POST", "/orgs/schnappy/repos",
                {"name": name, "default_branch": "main", "private": False}, ok=(201, 409))
            repo = os.path.join(work, name)
            run("git", "clone", "-q", "--branch", "main", "--single-branch", os.path.abspath(src), repo)
            head = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"],
                                  capture_output=True, text=True, check=True).stdout.strip()
            if name == "infra":
                overlay_infra(repo, a.forgejo)
            copy_overlay(name, repo)
            run("git", "-C", repo, "add", "-A")
            run("git", "-C", repo, "-c", "user.name=vagrant-mirror", "-c", "user.email=mirror@vagrant.test",
                "commit", "-q", "--allow-empty", "-m", f"vagrant overlay on {name} main {head}")
            url = f"http://{user}:{password}@{a.forgejo}/schnappy/{name}.git"
            run("git", "-C", repo, "push", "-q", "--force", url, "HEAD:main")
            print(f"{name}: main {head} + vagrant overlay pushed to http://{a.forgejo}/schnappy/{name}.git")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
