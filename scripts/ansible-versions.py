#!/usr/bin/env python3
"""ansible-versions.py - the Ansible a run uses: ansible-core and the ansible package in the project's venv
(deploy/ansible/venv), each collection requirements.yml names in the project's own collections path
(deploy/ansible/collections - ansible.cfg's collections_path), printed as JSON. A full run's proof records them
(scripts/upgrade-production.py proof-start), production's phases refuse others.

  --check   each as requirements.txt and requirements.yml pin it: the differences named, exit 1 (deploy:install's status:
            it installs again on any)
  --root    another deploy/ansible (a test's fixture)
"""
import json
import os
import re
import subprocess
import sys

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def versions(root):
    out = subprocess.run([os.path.join(root, "venv", "bin", "python3"), "-c",
                          "import importlib.metadata as m; print(m.version('ansible-core'), m.version('ansible'))"],
                         capture_output=True, text=True)
    core, package = out.stdout.split() if out.returncode == 0 and len(out.stdout.split()) == 2 else (None, None)
    collections = {}
    for c in yaml.safe_load(open(os.path.join(root, "requirements.yml")))["collections"]:
        manifest = os.path.join(root, "collections", "ansible_collections", *c["name"].split("."), "MANIFEST.json")
        try:
            collections[c["name"]] = json.load(open(manifest))["collection_info"]["version"]
        except (OSError, ValueError, KeyError):
            collections[c["name"]] = None
    return {"ansible-core": core, "ansible": package, "collections": dict(sorted(collections.items()))}


def pinned(root):
    pins = dict(re.findall(r"(?m)^([a-z-]+)==(\S+)$", open(os.path.join(root, "requirements.txt")).read()))
    collections = {c["name"]: str(c.get("version", "")).removeprefix("==")
                   for c in yaml.safe_load(open(os.path.join(root, "requirements.yml")))["collections"]}
    return {"ansible-core": pins.get("ansible-core"), "ansible": pins.get("ansible"),
            "collections": dict(sorted(collections.items()))}


def main():
    args = sys.argv[1:]
    root = os.path.join(OPS, "deploy", "ansible")
    if "--root" in args:
        root = args[args.index("--root") + 1]
        del args[args.index("--root"):args.index("--root") + 2]
    if args not in ([], ["--check"]):
        sys.exit(__doc__)
    have = versions(root)
    if not args:
        print(json.dumps(have))
        return
    want = pinned(root)
    diff = [f"{k}: {have[k]}, pinned {want[k]}" for k in ("ansible-core", "ansible") if have[k] != want[k]]
    diff += [f"{n}: {have['collections'].get(n)}, pinned {v}" for n, v in want["collections"].items()
             if have["collections"].get(n) != v]
    if diff:
        sys.exit("the Ansible installed is not the pinned one: " + "; ".join(diff))


if __name__ == "__main__":
    main()
