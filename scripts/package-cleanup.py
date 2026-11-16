#!/usr/bin/env python3
"""Forgejo's container packages pruned by hand (task forgejo:package-cleanup): every CI build pushes an image and its
build cache, nothing ever removed them - 653 GB on the Pis' shared storage by 2026-11-16, 740 GB of it masi's two
months, in no backup (the operator: rely on rebuilding from git). Kept, per package: the newest 10 versions of an image,
the newest 5 of a build cache (a name ending in /cache), `latest`, and every tag in use - each `git.pmon.dev/schnappy/
<name>:<tag>` infra, platform and ops name (an image's repository and tag lines in values files too) and every image a
pod of the cluster runs now (production, test, preview environments). Everything else deleted through Forgejo's API -
only with --apply (else the plan is printed); the first refused deletion stops it. Forgejo removes the blobs no version
holds any more itself (its package cleanup cron).

Usage: scripts/package-cleanup.py [--apply]
Env:   FORGEJO_PACKAGES_TOKEN (a token of the organisation's owner with write:package - by name, never on a command
       line), PACKAGE_CLEANUP_API (default https://git.pmon.dev/api/v1), PACKAGE_CLEANUP_OWNER (schnappy),
       PACKAGE_CLEANUP_SRC (the checkouts' parent, default ops/..), PACKAGE_CLEANUP_RUNNING (a command printing the
       cluster's pod images one a line; default: ten's kubectl over ssh)
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

KEEP_IMAGE, KEEP_CACHE = 10, 5
REF = re.compile(r"git\.pmon\.dev/schnappy/([a-z0-9._/-]+):([A-Za-z0-9._-]+)")
RUNNING = ("ssh -o BatchMode=yes -o ConnectTimeout=10 sm@192.168.11.2 \"kubectl get pods -A -o jsonpath='"
           "{range .items[*]}{range .spec.containers[*]}{.image}{\\\"\\n\\\"}{end}{range .spec.initContainers[*]}"
           "{.image}{\\\"\\n\\\"}{end}{end}'\"")


class Refused(Exception):
    pass


def call(method, path, token, api):
    req = urllib.request.Request(api + path, method=method)
    req.add_unredirected_header("Authorization", f"token {token}")  # a redirect elsewhere never carries the token
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, None
    except (OSError, ValueError) as e:
        raise Refused(f"{method} {path}: {e}") from e


def versions(owner, token, api):
    """Every container package version of the owner: (name, version, created) - all pages."""
    out, page = [], 1
    while True:
        status, items = call("GET", f"/packages/{owner}?type=container&limit=50&page={page}", token, api)
        if status != 200 or not isinstance(items, list):
            raise Refused(f"the packages not read (page {page}: HTTP {status})")
        if not items:
            return out
        out += [(i["name"].lower(), i["version"], i.get("created_at") or "") for i in items]
        page += 1


def referenced(src):
    """Every schnappy image tag the checkouts name: name:tag anywhere, and a values file's repository + tag lines."""
    used = set()
    for repo in ("infra", "platform", "ops"):
        for root, dirs, files in os.walk(os.path.join(src, repo)):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("node_modules", "venv")]
            for fn in files:
                if not fn.endswith((".yaml", ".yml", ".sh", ".py", ".json")):
                    continue
                try:
                    text = open(os.path.join(root, fn), encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                used |= {(n.lower(), t.lower()) for n, t in REF.findall(text)}
                lines = text.splitlines()
                for i, line in enumerate(lines):
                    m = re.search(r"repository:\s*[\"']?git\.pmon\.dev/schnappy/([a-z0-9._/-]+)", line)
                    for nxt in lines[i + 1:i + 5] if m else ():
                        t = re.search(r"\btag:\s*[\"']?([A-Za-z0-9._-]+)", nxt)
                        if t:
                            used.add((m.group(1).lower(), t.group(1).lower()))
                            break
    return used


def running(cmd):
    """The images the cluster's pods run now - read, or no plan (a tag in use deleted is a pod that cannot start)."""
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise Refused(f"the cluster's images not read: {r.stderr.strip()[:200]}")
    return {(n.lower(), t.lower()) for n, t in REF.findall(r.stdout)}


def plan(vers, used):
    """(keep, delete): per package the newest N (5 for a build cache, 10 else), `latest` and every tag in use kept."""
    by = {}
    for name, ver, created in vers:
        by.setdefault(name, []).append((created, ver))
    keep, delete = [], []
    for name, vs in sorted(by.items()):
        n = KEEP_CACHE if name.endswith("/cache") else KEEP_IMAGE
        base = name[:-len("/cache")] if name.endswith("/cache") else name
        for i, (_, ver) in enumerate(sorted(vs, reverse=True)):
            v = ver.lower()
            (keep if i < n or v == "latest" or (name, v) in used or (base, v) in used else delete).append((name, ver))
    return keep, delete


def main(argv):
    apply = argv == ["--apply"]
    if argv not in ([], ["--apply"]):
        print("REFUSED: package-cleanup.py [--apply]")
        return 2
    token = os.environ.get("FORGEJO_PACKAGES_TOKEN", "")
    if not token:
        print("REFUSED: FORGEJO_PACKAGES_TOKEN is empty (ops/.env) - nothing read or deleted")
        return 1
    api = os.environ.get("PACKAGE_CLEANUP_API", "https://git.pmon.dev/api/v1").rstrip("/")
    owner = os.environ.get("PACKAGE_CLEANUP_OWNER", "schnappy")
    src = os.environ.get("PACKAGE_CLEANUP_SRC", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    try:
        used = referenced(src) | running(os.environ.get("PACKAGE_CLEANUP_RUNNING", RUNNING))
        keep, delete = plan(versions(owner, token, api), used)
    except Refused as e:
        print(f"REFUSED: {e}")
        return 1
    names = sorted({n for n, _ in keep + delete})
    for name in names:
        print(f"{name:20} keep {sum(1 for n, _ in keep if n == name):4}  delete {sum(1 for n, _ in delete if n == name):5}")
    print(f"{len(keep)} kept, {len(delete)} to delete ({len(used)} tags in use or named)")
    if not apply:
        print("a plan only - task forgejo:package-cleanup APPLY=true deletes them")
        return 0
    for i, (name, ver) in enumerate(delete, 1):
        path = f"/packages/{owner}/container/{urllib.parse.quote(name, safe='')}/{urllib.parse.quote(ver, safe='')}"
        status, _ = call("DELETE", path, token, api)
        if status not in (204, 404):  # gone already: nothing to do
            print(f"STOPPED: {name}:{ver} not deleted (HTTP {status}) - {i - 1} of {len(delete)} deleted")
            return 1
    print(f"DELETED {len(delete)} versions")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
