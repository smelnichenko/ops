#!/bin/bash
# No secret is templated into a shell or command task's script or a task's environment: a script reaches the remote
# shell's command line, the environment Ansible passes reaches sudo's (env VAR=value python), and any local user reads
# those in /proc - and a quote in a password templated into a root shell breaks out of its quoting. Secrets go on stdin
# (read, or a JSON document), into a file of the run's own, or are read on the host from their root-only file. Named:
# a Jinja expression naming a password, secret, token or API key (not a path to one) in a shell/command script (free
# form, cmd: or argv:) or in environment:. Excepted, each for its reason below.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PY'
import re, sys
from ansible.parsing.mod_args import FREEFORM_ACTIONS
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, plays, tasks  # noqa: E402
SECRET = re.compile(r"\{\{[^}]*\b\w*(password|passwd|secret|token|api_key|apikey)\w*\b[^}]*\}\}", re.I)
NOT_A_SECRET = re.compile(r"_(dir|file|path|name|ttl|policy|role)\b", re.I)  # where a secret is, not the secret
# (file, task name): why it cannot go another way
ALLOWED = {
    ("deploy/ansible/playbooks/setup-pi-services.yml",
     "Create Forgejo admin user (with retries — Forgejo can be slow to settle after first start)"):
        "Forgejo's CLI takes the password only as --password",
    ("deploy/ansible/playbooks/setup-patroni.yml", "Recreate Forgejo admin user post-Patroni (if missing)"):
        "Forgejo's CLI takes the password only as --password",
    ("deploy/ansible/playbooks/setup-velero.yml", "Initialize local bare mirror from Forgejo"):
        "the mirror's clone URL (ten's old Velero mirror; to move to a credential helper)",
}


def secrets(text):
    return [m.group(0) for m in SECRET.finditer(str(text or "")) if not NOT_A_SECRET.search(m.group(0))]


def named(task):
    """The templated secrets a task puts on a command line: its script's and its environment's."""
    out = []
    for k, v in actions(task):
        if k in FREEFORM_ACTIONS:
            script = v if isinstance(v, str) else " ".join([str(v.get("cmd") or "")] + [str(a) for a in v.get("argv") or []]) \
                if isinstance(v, dict) else ""
            out += [f"script {s}" for s in secrets(script)]
    if isinstance(task.get("environment"), dict):
        out += [f"environment {k}={s}" for k, v in task["environment"].items() for s in secrets(v)]
    return out


def judged(doc):
    """What can put a secret on a command line: each play (its environment reaches every task of it) and each task."""
    return plays(doc) + list(tasks(doc))


fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + "\n  ".join(map(str, got if isinstance(got, list) else [got]))))


check("a password templated into a script: named",
      bool(named({"ansible.builtin.shell": "curl -u admin:{{ admin_password }} x"})), True)
check("one in a task's environment: named", bool(named({"ansible.builtin.shell": "x", "environment":
                                                         {"P": "{{ db_password }}"}})), True)
check("one in a play's environment: named", [n for t in judged([{"hosts": "all", "environment": {"T": "{{ vault_token }}"},
                                                                 "tasks": [{"ansible.builtin.shell": "x"}]}])
                                            for n in named(t)], ["environment T={{ vault_token }}"])
check("one on stdin, a path to one: not named",
      named({"ansible.builtin.shell": {"cmd": "cat {{ secret_dir }}/x", "stdin": "{{ db_password }}"}}), [])
bad, used = [], set()
for f in files("deploy/ansible"):
    for t in judged(load(f)):
        for n in named(t):
            if (f, t.get("name")) in ALLOWED:
                used.add((f, t.get("name")))
            else:
                bad.append(f"{f}: {t.get('name')}: {n}")
check("no secret on a command line in deploy/ansible (beyond the excepted)", bad, [])
check("every exception still needed (one whose task changed is dropped, not kept)", sorted(set(ALLOWED) - used), [])
print("secrets-off-argv: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
