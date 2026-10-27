#!/usr/bin/env python3
"""argocd-repos.py - the Forgejo repositories Argo CD reads, derived from infra's manifests (never restated):

  code   every repoURL of an Application or ApplicationSet (its source, sources, template's) and of an
         ApplicationSet's git generator (at the top or inside a matrix/merge) on the Forgejo host - what Argo CD's
         repo-server clones;
  pulls  every repository an ApplicationSet's pullRequest (gitea) generator lists pull requests of - its repo, or each
         value a list generator beside it (in the same matrix) gives the template '{{ .<key> }}' it names; what the
         PR generator and the stale-PR sweeper read with the read-only token.

Usage: argocd-repos.py <infra tree> <Forgejo host> <org> [<commit>]  -> JSON {"code": [...], "pulls": [...], "commit"}
Fails (exit 1), saying which: a repoURL or generator on the host but outside the org, one it cannot resolve - a
repoURL on the host that is a template ({{ ... }}: which repository it names is the generators' to say, not derivable
here) -, a repository of the org on another host (the Pis' VIP, an address - Argo CD's credentials are for the host
alone), a manifest file it cannot parse (never skipped: an Application in it would go unseen). A key present but null
(YAML's `key:` alone) reads as absent.
"""
import glob
import json
import os
import re
import sys

import yaml

infra, host, org = sys.argv[1], sys.argv[2], sys.argv[3]
commit = sys.argv[4] if len(sys.argv) > 4 else ""
code, pulls, bad = set(), set(), []
URL = re.compile(rf"^(?:https?://){re.escape(host)}/([^/]+)/([^/]+?)(?:\.git)?/?$")
# a repository of the org on any other host
ELSEWHERE = re.compile(rf"^(?:https?://)([^/]+)/{re.escape(org)}/[^/]+?(?:\.git)?/?$")
TEMPLATE = re.compile(r"^\{\{\s*\.(\w+)\s*\}\}$")


def get(d, key, default):
    """d[key], or default where d is no mapping or the key is missing or null (YAML's `key:` with nothing after it)."""
    v = d.get(key) if isinstance(d, dict) else None
    return default if v is None else v


def sources(spec):
    return ([spec["source"]] if isinstance(get(spec, "source", None), dict) else []) + \
        [x for x in get(spec, "sources", []) if isinstance(x, dict)]


def repo_of(url, where):
    if host in url and "{{" in url:
        bad.append(f"{where}: {url} - a templated repoURL on {host}: which repository it names cannot be derived")
        return None
    other = ELSEWHERE.match(url)
    if other and other.group(1) != host:
        bad.append(f"{where}: {url} - a repository of {org} on {other.group(1)}, not {host}")
        return None
    if host not in url:
        return None
    m = URL.match(url)
    if not m or m.group(1) != org:
        bad.append(f"{where}: {url} - on {host} but not a repository of {org}")
        return None
    return m.group(2)


def generators(gens, siblings, where):
    """Each git generator's repoURL (cloned: code) and each pullRequest.gitea generator's repositories (pulls), at the
    top or inside a matrix/merge; a matrix's list elements resolve a pull-request generator's templated repo."""
    for g in gens if isinstance(gens, list) else []:
        if not isinstance(g, dict):
            continue
        if "matrix" in g or "merge" in g:
            inner = get(get(g, "matrix", None) or get(g, "merge", None), "generators", [])
            elements = [e for x in inner if isinstance(x, dict) for e in get(get(x, "list", {}), "elements", [])
                        if isinstance(e, dict)]
            generators(inner, elements, where)
        git = get(g, "git", {})
        if get(git, "repoURL", ""):
            r = repo_of(str(git["repoURL"]), where)
            if r:
                code.add(r)
        pr = get(get(g, "pullRequest", {}), "gitea", None)
        if not pr:
            continue
        api = get(pr, "api", None)
        if str(api or "").rstrip("/") not in (f"https://{host}", f"http://{host}") or get(pr, "owner", None) != org:
            bad.append(f"{where}: a pullRequest generator on {api} / {get(pr, 'owner', None)} - not {host}/{org}")
            continue
        m = TEMPLATE.match(str(get(pr, "repo", "")))
        names = [e.get(m.group(1)) for e in siblings] if m else [get(pr, "repo", None)]
        if not names or not all(isinstance(n, str) and n for n in names):
            bad.append(f"{where}: a pullRequest generator's repo {pr.get('repo')!r} not resolved")
            continue
        pulls.update(names)


files = sorted(glob.glob(os.path.join(infra, "clusters", "**", "*.yaml"), recursive=True)
               + glob.glob(os.path.join(infra, "clusters", "**", "*.yml"), recursive=True))
if not files:
    sys.exit(f"argocd-repos: no manifest under {infra}/clusters - not an infra checkout")
for f in files:
    try:
        docs = list(yaml.safe_load_all(open(f)))
    except yaml.YAMLError as e:
        bad.append(f"{os.path.relpath(f, infra)}: not parsed ({str(e).splitlines()[0]})")
        continue
    for d in docs:
        if not isinstance(d, dict) or str(get(d, "apiVersion", "")).split("/")[0] != "argoproj.io":
            continue
        where = os.path.relpath(f, infra)
        spec = get(d, "spec", {})
        if d.get("kind") == "Application":
            srcs = sources(spec)
        elif d.get("kind") == "ApplicationSet":
            srcs = sources(get(get(spec, "template", {}), "spec", {}))
            generators(get(spec, "generators", []), [], where)
        else:
            continue
        for s in srcs:
            r = repo_of(str(get(s, "repoURL", "")), where)
            if r:
                code.add(r)
if bad:
    sys.exit("argocd-repos: " + "; ".join(bad))
print(json.dumps({"code": sorted(code), "pulls": sorted(pulls), "commit": commit}))
