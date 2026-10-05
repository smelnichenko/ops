#!/usr/bin/env python3
"""upgrade-base-fingerprint.py - what the upgrade copy's base build (Vagrant VMs, the Pi stack, kubeadm at
production's versions; Taskfile _upgrade:base) is made from, as one hash: the committed contents of every file it
reads and the task definitions that run it. Equal fingerprints build the same base, so the full run restores the
base-ready snapshot instead of an hour's build (Taskfile _upgrade:base-restore).

  --check  exit 0 when .upgrade/base-ready.fingerprint holds this fingerprint, the base-ready snapshot exists on every
           VM and it is younger than MAX_AGE (what the build fetches from outside - Debian's packages, upstream
           images - moves; a snapshot older than that is rebuilt); else exit 1, saying why
  --save   write this fingerprint to .upgrade/base-ready.fingerprint (after the snapshot is taken)
  (none)   print it

Committed contents only (git, HEAD): an uncommitted change is no build input - the full run refuses a dirty tree.
"""
import hashlib
import os
import subprocess
import sys
import time

import yaml

OPS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAMP = os.path.join(OPS, ".upgrade", "base-ready.fingerprint")
MAX_AGE = 3 * 24 * 3600
VMS = ("pi1", "pi2", "kubeadm")
# the files and directories the base build reads
PATHS = (
    "Vagrantfile",
    "deploy/ansible",
    "tests/ansible/isolate-pis.yml",
    "tests/ansible/vagrant-only.yml",
    "tests/ansible/vagrant-only-play.yml",
    "tests/ansible/upgrade/pi-baseline.yml",
    "tests/ansible/upgrade/vms-ready.yml",
)
# the tasks that run it
TASKS = ("_upgrade:base", "_vagrant:pi-stack", "_vagrant:pi-pgbouncer", "_upgrade:snapshot-base", "deploy:install")


def git(*args):
    return subprocess.run(["git", "-C", OPS, *args], check=True, capture_output=True, text=True).stdout.strip()


def fingerprint():
    h = hashlib.sha256()
    for p in PATHS:
        h.update(f"{p} {git('rev-parse', f'HEAD:{p}')}\n".encode())
    tasks = yaml.safe_load(git("show", "HEAD:Taskfile.yml"))["tasks"]
    for t in TASKS:
        h.update(f"{t} {yaml.safe_dump(tasks[t], sort_keys=True)}\n".encode())
    return h.hexdigest()[:16]


def check(fp):
    try:
        saved = open(STAMP).read().split()
    except FileNotFoundError:
        return "no base-ready fingerprint saved"
    if not saved or saved[0] != fp:
        return f"base inputs changed (snapshot {saved[0] if saved else '?'}, now {fp})"
    if len(saved) < 2 or time.time() - float(saved[1]) > MAX_AGE:
        return "base-ready snapshot older than 3 days"
    for vm in VMS:
        out = subprocess.run(["vagrant", "snapshot", "list", vm], cwd=OPS, capture_output=True, text=True).stdout
        if "base-ready" not in out.split():
            return f"no base-ready snapshot on {vm}"
    return None


def main():
    fp = fingerprint()
    if sys.argv[1:] == ["--check"]:
        why = check(fp)
        print(f"BASE {'REUSED' if why is None else 'REBUILT'}: {why or 'inputs unchanged, base-ready snapshot ' + fp}")
        sys.exit(0 if why is None else 1)
    if sys.argv[1:] == ["--save"]:
        os.makedirs(os.path.dirname(STAMP), exist_ok=True)
        with open(STAMP, "w") as f:
            f.write(f"{fp} {int(time.time())}\n")
        print(f"base-ready fingerprint {fp} saved")
        return
    print(fp)


if __name__ == "__main__":
    main()
