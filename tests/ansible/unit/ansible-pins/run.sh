#!/bin/bash
# The Ansible a run uses is the one its proof records, and production's phases run on the same: ansible-core and the
# ansible package pinned in requirements.txt, each collection the playbooks use pinned exactly in requirements.yml and
# installed into the project's own path (ansible.cfg's collections_path) - ~/.ansible/collections, shared with every
# project on the host, shadowed the venv's (community.general 13.1.0 over 12.4.0). scripts/ansible-versions.py reads
# them (--check: as pinned); deploy:install reinstalls on any difference, not only on a missing venv.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 W=$W "$PY" - <<'PY'
import glob, json, os, re, subprocess, sys
import yaml
W = os.environ["W"]
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


# every collection the playbooks' tasks name (a module's namespace.collection.module), each pinned to one version
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
used = set()
for f in files("deploy/ansible") + files("tests/ansible"):
    for t in tasks(load(f)):
        for module, _ in actions(t):
            if module.count(".") == 2:
                used.add(module.rsplit(".", 1)[0])
used -= {"ansible.builtin"}
req = {c["name"]: str(c.get("version", "")) for c in yaml.safe_load(open("deploy/ansible/requirements.yml"))["collections"]}
check("every collection the playbooks use is required", sorted(used - set(req)), [])
check("each required collection pinned to one version", sorted(n for n, v in req.items()
                                                                if not re.fullmatch(r"(==)?\d+\.\d+\.\d+", v)), [])
# the project's own collection path, nothing shared: ansible.cfg's, relative to it
cfg = open("deploy/ansible/ansible.cfg").read()
check("ansible.cfg: the project's own collections path",
      re.findall(r"(?m)^collections_path\s*=\s*(\S+)$", cfg), ["collections"])
check("the project's collections are not committed",
      subprocess.run(["git", "check-ignore", "-q", "deploy/ansible/collections"]).returncode, 0)
# deploy:install: into that path, and again whenever the installed versions differ from the pins
inst = yaml.safe_load(open("Taskfile.yml"))["tasks"]["deploy:install"]
cmds = " ".join(c if isinstance(c, str) else c.get("cmd", "") for c in inst["cmds"])
check("deploy:install installs the collections into the project's path", "-r requirements.yml -p collections" in cmds,
      True)
check("deploy:install reinstalls when the versions differ from the pins",
      any("ansible-versions.py --check" in s for s in inst.get("status") or []), True)

# ansible-versions.py on a fixture: a venv's package versions and the collections' MANIFEST.json
root = os.path.join(W, "ansible")
for name, version in (("kubernetes/core", "6.3.0"), ("community/general", "13.1.0")):
    d = os.path.join(root, "collections", "ansible_collections", name)
    os.makedirs(d)
    json.dump({"collection_info": {"version": version}}, open(os.path.join(d, "MANIFEST.json"), "w"))
os.makedirs(os.path.join(root, "venv", "bin"))
py = os.path.join(root, "venv", "bin", "python3")
open(py, "w").write("#!/bin/sh\necho '2.20.3 13.4.0'\n")
os.chmod(py, 0o755)
open(os.path.join(root, "requirements.txt"), "w").write("ansible==13.4.0\nansible-core==2.20.3\n")
yaml.safe_dump({"collections": [{"name": "kubernetes.core", "version": "==6.3.0"},
                                {"name": "community.general", "version": "==13.1.0"}]},
               open(os.path.join(root, "requirements.yml"), "w"))
av = lambda *a: subprocess.run(["scripts/ansible-versions.py", "--root", root, *a], capture_output=True, text=True)
r = av()
check("the versions read", json.loads(r.stdout) if r.returncode == 0 else r.stderr,
      {"ansible-core": "2.20.3", "ansible": "13.4.0",
       "collections": {"community.general": "13.1.0", "kubernetes.core": "6.3.0"}})
check("--check: as pinned", av("--check").returncode, 0)
json.dump({"collection_info": {"version": "12.4.0"}},
          open(os.path.join(root, "collections/ansible_collections/community/general/MANIFEST.json"), "w"))
r = av("--check")
check("--check: a collection at another version - failed, named", (r.returncode, "community.general" in r.stderr),
      (1, True))
os.remove(os.path.join(root, "collections/ansible_collections/community/general/MANIFEST.json"))
r = av("--check")
check("--check: a collection missing - failed, named", (r.returncode, "community.general" in r.stderr), (1, True))
# deploy:install puts every pinned collection into the project's path: galaxy skips one the ansible package bundles
# ("already installed") and the check reads the project's path alone - kubernetes.core and community.hashi_vault were
# never installed there, and proof-start refused the run (2026-10-10)
inst = yaml.safe_load(open("Taskfile.yml"))["tasks"]["deploy:install"]["cmds"]
galaxy = [c for c in inst if "ansible-galaxy collection install" in str(c)]
check("deploy:install forces the pinned collections into the project's path",
      [("-p collections" in str(c), "--force" in str(c)) for c in galaxy], [(True, True)])
print("ansible-pins: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
