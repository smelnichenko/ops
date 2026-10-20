#!/usr/bin/env python3
"""argocd-repos.py - the Forgejo repositories Argo CD reads, derived from infra's manifests (never restated):

  code   every repoURL of an Application or ApplicationSet (its source, sources, template's) on the Forgejo host -
         what Argo CD's repo-server clones;
  pulls  every repository an ApplicationSet's pullRequest (gitea) generator lists pull requests of - its repo, or each
         value a list generator beside it (in the same matrix) gives the template '{{ .<key> }}' it names; what the
         PR generator and the stale-PR sweeper read with the read-only token.

Usage: argocd-repos.py <infra checkout> <Forgejo host> <org>   -> JSON {"code": [...], "pulls": [...], "commit": sha}
A repoURL or generator on the host but outside the org, or one it cannot resolve, fails it (exit 1), saying which.
"""
import glob
import json
import os
import re
import subprocess
import sys

import yaml

infra, host, org = sys.argv[1], sys.argv[2], sys.argv[3]
code, pulls, bad = set(), set(), []
URL = re.compile(rf"^(?:https?://){re.escape(host)}/([^/]+)/([^/]+?)(?:\.git)?/?$")
TEMPLATE = re.compile(r"^\{\{\s*\.(\w+)\s*\}\}$")


def sources(spec):
    return ([spec["source"]] if isinstance(spec.get("source"), dict) else []) + list(spec.get("sources") or [])


def repo_of(url, where):
    if host not in url:
        return None
    m = URL.match(url)
    if not m or m.group(1) != org:
        bad.append(f"{where}: {url} - on {host} but not a repository of {org}")
        return None
    return m.group(2)


def pull_generators(gens, siblings, where):
    """Each pullRequest.gitea generator's repositories; a matrix's list elements resolve its templated repo."""
    for g in gens or []:
        if "matrix" in g or "merge" in g:
            inner = (g.get("matrix") or g.get("merge"))["generators"]
            elements = [e for x in inner if "list" in x for e in x["list"].get("elements", [])]
            pull_generators(inner, elements, where)
        pr = (g.get("pullRequest") or {}).get("gitea")
        if not pr:
            continue
        if pr.get("api", "").rstrip("/") not in (f"https://{host}", f"http://{host}") or pr.get("owner") != org:
            bad.append(f"{where}: a pullRequest generator on {pr.get('api')} / {pr.get('owner')} - not {host}/{org}")
            continue
        m = TEMPLATE.match(str(pr.get("repo", "")))
        names = [e.get(m.group(1)) for e in siblings] if m else [pr.get("repo")]
        if not names or not all(isinstance(n, str) and n for n in names):
            bad.append(f"{where}: a pullRequest generator's repo {pr.get('repo')!r} not resolved")
            continue
        pulls.update(names)


files = sorted(glob.glob(os.path.join(infra, "clusters", "**", "*.yaml"), recursive=True))
if not files:
    sys.exit(f"argocd-repos: no manifest under {infra}/clusters - not an infra checkout")
for f in files:
    try:
        docs = list(yaml.safe_load_all(open(f)))
    except yaml.YAMLError:
        continue  # a template or a values file infra's tests judge; never an Application
    for d in docs:
        if not isinstance(d, dict) or d.get("apiVersion", "").split("/")[0] != "argoproj.io":
            continue
        where = os.path.relpath(f, infra)
        spec = d.get("spec") or {}
        if d.get("kind") == "Application":
            srcs = sources(spec)
        elif d.get("kind") == "ApplicationSet":
            srcs = sources((spec.get("template") or {}).get("spec") or {})
            pull_generators(spec.get("generators"), [], where)
        else:
            continue
        for s in srcs:
            r = repo_of(str(s.get("repoURL", "")), where)
            if r:
                code.add(r)
if bad:
    sys.exit("argocd-repos: " + "; ".join(bad))
commit = subprocess.run(["git", "-C", infra, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout
print(json.dumps({"code": sorted(code), "pulls": sorted(pulls), "commit": commit.strip()}))
