#!/bin/bash
# No task of deploy/ansible names a fixed path in a world-writable directory (/tmp, /var/tmp): the hosts' playbooks run
# as root, and a file or directory planted there under a known name was applied as cluster-admin (setup-caddy's RBAC
# manifest: kubectl apply -f a directory applies every file in it), installed (smartctl_exporter, nerdctl, Nexus,
# Vault, PyTorch wheels), compared (Gluster's entry lists) or written credentials into (Patroni's pgpass). A private
# directory instead (ansible.builtin.tempfile, mktemp -d) or stdin. Every task's action read as Ansible reads it,
# play keywords and loops included; a fixture shows the walk finds each form.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, re, sys, tempfile
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, plays, tasks  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


# a fixed name in /tmp or /var/tmp: the directory itself (dest: /tmp/) or a path in it - not /tmp inside a longer path
SHARED = re.compile(r"(?<![\w./}-])(/var)?/tmp(/[^\s\"'`)}]*)?(?![\w-])")


def found(path):
    """Each task (or play's vars) naming a fixed path in a world-writable directory: (file, task name, the path)."""
    out = []
    doc = load(path)
    for p in plays(doc) or []:
        for m in SHARED.finditer(str(p.get("vars") or "") + str(p.get("environment") or "")):
            out.append((path, "(play vars)", m[0]))
    for t in tasks(doc):
        for _, value in actions(t):
            for m in SHARED.finditer(str(value) + str(t.get("environment") or "") + str(t.get("args") or "")):
                out.append((path, t.get("name", "?"), m[0]))
    return out


# the walk finds each form (a fixture): a dest, a shell's redirect, an argv entry, a block's task, a play's environment
fx = tempfile.mkdtemp()
open(os.path.join(fx, "f.yml"), "w").write("""
- hosts: all
  environment: {TMPDIR: /tmp}
  tasks:
    - name: a
      ansible.builtin.copy: {content: x, dest: /tmp/x.yml}
    - name: b
      ansible.builtin.shell: curl -o /var/tmp/y.tgz https://e
    - block:
        - name: c
          ansible.builtin.command: {argv: [kubectl, apply, -f, /tmp/]}
    - name: d (not shared)
      ansible.builtin.file: {path: "/srv/tmp/z {{ data_dir }}/tmp", state: directory}
    - name: e (a private one)
      ansible.builtin.shell: d=$(mktemp -d); echo > "$d/x"
""")
check("the walk finds each form, nothing else",
      sorted((n, p) for _, n, p in found(os.path.join(fx, "f.yml"))),
      [("(play vars)", "/tmp"), ("a", "/tmp/x.yml"), ("b", "/var/tmp/y.tgz"), ("c", "/tmp/")])
hits = [h for f in files("deploy/ansible") for h in found(f)]
for f, n, p in hits:
    print(f"  {f}: {n}: {p}")
check("no task of deploy/ansible names a fixed path in /tmp or /var/tmp", len(hits), 0)
print("no-shared-tmp: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
