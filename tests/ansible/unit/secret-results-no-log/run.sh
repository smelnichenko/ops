#!/bin/bash
# A credential an API answers with never in Ansible's output: a task whose registered result is read for a secret
# field (<result>.json.client_secret, .sha1 - Forgejo's new token -, .token, .password, .secret...) is no_log, as
# Ansible prints a task's result at -v and on a failure (setup-woodpecker's OAuth application: its client_secret).
# Every registering task found by its register name in the same file, blocks and handlers included; a fixture shows
# the walk finds a read and its task.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PY'
import os, re, sys, tempfile
sys.path.insert(0, "tests/ansible/unit")
from plays import files, load, tasks  # noqa: E402
fails = 0


def check(name, got, want):
    global fails
    fails += got != want
    print(f"{'PASS' if got == want else 'FAIL'} {name}" + ("" if got == want else f"\n  got  {got}\n  want {want}"))


READ = re.compile(r"\b(\w+)\.json(?:\.|\[['\"])(client_secret|sha1|token|password|secret|secret_key|access_key)\b")


def open_results(path):
    """(register name, secret field, task name) for each registering task whose result is read for a secret and that
    is not no_log - in one file."""
    text = open(path).read()
    reads = {(m[1], m[2]) for m in READ.finditer(text)}
    out = []
    for t in tasks(load(path)):
        for reg, field in sorted(reads):
            if t.get("register") == reg and t.get("no_log") is not True:
                out.append((reg, field, t.get("name", "?")))
    return out


fx = tempfile.mkdtemp()
open(os.path.join(fx, "f.yml"), "w").write("""
- hosts: all
  tasks:
    - name: make a token
      ansible.builtin.uri: {url: https://x}
      register: _tok
    - block:
        - name: make another, hidden
          ansible.builtin.uri: {url: https://y}
          register: _app
          no_log: true
    - name: use them
      ansible.builtin.set_fact:
        a: "{{ _tok.json.sha1 }}"
        b: "{{ _app.json['client_secret'] }}"
""")
check("the walk finds a read secret and its task (a no_log one aside)", open_results(os.path.join(fx, "f.yml")),
      [("_tok", "sha1", "make a token")])
hits = [(f, *h) for f in files("deploy/ansible") for h in open_results(f)]
for h in hits:
    print("  " + ": ".join(h))
check("every task whose result is read for a secret is no_log", len(hits), 0)
print("secret-results-no-log: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
