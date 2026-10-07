#!/bin/bash
# No secret is templated into a shell or command task's script or a task's environment: a script reaches the remote
# shell's command line, the environment Ansible passes reaches sudo's (env VAR=value python), and any local user reads
# those in /proc - and a quote in a password templated into a root shell breaks out of its quoting. Secrets go on stdin
# (read, or a JSON document) with no_log (a module's arguments, stdin among them, are logged on its host), into a file
# of the run's own, or are read on the host from their root-only file. Named: a Jinja expression naming a password,
# passphrase, secret, token, API or private key or credentials (not a path to one) - or a variable that holds one, set
# by the play, a block or the task, directly or through another - in a shell/command script (free form, cmd: or argv:),
# in environment:, in an argument a module puts on a command line (expect's command, git's repo, helm's set_values,
# pip's extra_args), or on stdin without no_log. Excepted, each for its reason below.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" - <<'PY'
import re, sys
from ansible.parsing.mod_args import FREEFORM_ACTIONS
sys.path.insert(0, "tests/ansible/unit")
import yaml  # noqa: E402
from plays import actions, files, load, plays  # noqa: E402
SECRET = re.compile(r"\{\{[^}]*\b\w*(password|passwd|passphrase|secret|token|api_key|apikey|private_key|credentials?)"
                    r"\w*\b[^}]*\}\}", re.I)
NOT_A_SECRET = re.compile(r"_(dir|file|path|name|ttl|policy|role)\b", re.I)  # where a secret is, not the secret
JINJA = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.S)
# arguments a module puts on a command line
ARGV_ARGS = {"ansible.builtin.expect": ("command",), "ansible.builtin.git": ("repo",),
             "kubernetes.core.helm": ("set_values",), "ansible.builtin.pip": ("extra_args",)}
# (file, task name): why it cannot go another way
ALLOWED = {
    ("deploy/ansible/playbooks/setup-velero.yml", "Initialize local bare mirror from Forgejo"):
        "the mirror's clone URL (ten's old Velero mirror; to move to a credential helper)",
}


def holders(scope):
    """The variables of a scope that hold a secret - templated in, directly or through another such variable."""
    text = {k: yaml.safe_dump(v, width=10000) for k, v in (scope or {}).items()}
    held = {k for k, t in text.items() if secrets(t)}
    while True:
        more = {k for k, t in text.items() if k not in held and refers(t, held)}
        if not more:
            return held
        held |= more


def refers(text, names):
    return any(re.search(rf"\b{re.escape(n)}\b", j) for j in JINJA.findall(str(text or "")) for n in names)


def secrets(text, held=()):
    found = [m.group(0) for m in SECRET.finditer(str(text or "")) if not NOT_A_SECRET.search(m.group(0))]
    return found + ([f"(a variable holding one: {sorted(n for n in held if refers(text, [n]))})"]
                    if held and refers(text, held) else [])


def named(task, scope=None):
    """The templated secrets a task puts on a command line (its script, its environment, a module's argument that
    builds one) or in its host's log (stdin without no_log) - with `scope`, the variables its play and blocks set."""
    held = holders({**(scope or {}), **(task.get("vars") or {})})
    out = []
    for k, v in actions(task):
        if k in FREEFORM_ACTIONS:
            script = v if isinstance(v, str) else " ".join([str(v.get("cmd") or "")] + [str(a) for a in v.get("argv") or []]) \
                if isinstance(v, dict) else ""
            out += [f"script {s}" for s in secrets(script, held)]
            stdin = (v.get("stdin") if isinstance(v, dict) else None) or (task.get("args") or {}).get("stdin")
            if task.get("no_log") is not True:
                out += [f"stdin without no_log {s}" for s in secrets(stdin, held)]
        for a in ARGV_ARGS.get(k, ()) if isinstance(v, dict) else ():
            out += [f"argument {a} {s}" for s in secrets(yaml.safe_dump(v.get(a), width=10000), held)]
    if isinstance(task.get("environment"), dict):
        out += [f"environment {k}={s}" for k, v in task["environment"].items() for s in secrets(v, held)]
    return out


def walk(items, scope):
    """(task, the variables set around it) - a block's vars reach its tasks."""
    for t in items or []:
        if isinstance(t, dict):
            yield t, scope
            inner = {**scope, **(t.get("vars") or {})}
            for k in ("block", "rescue", "always"):
                yield from walk(t.get(k), inner)


def judged(doc):
    """What can put a secret on a command line, each with the variables set around it: each play (its environment
    reaches every task of it) and each task."""
    out = []
    for p in plays(doc):
        out.append((p, {}))
        for k in ("pre_tasks", "tasks", "post_tasks", "handlers"):
            out += list(walk(p.get(k), p.get("vars") or {}))
    if not plays(doc) and isinstance(doc, list):
        out += list(walk(doc, {}))
    return out


fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + "\n  ".join(map(str, got if isinstance(got, list) else [got]))))


check("a password templated into a script: named",
      bool(named({"ansible.builtin.shell": "curl -u admin:{{ admin_password }} x"})), True)
check("one in a task's environment: named", bool(named({"ansible.builtin.shell": "x", "environment":
                                                         {"P": "{{ db_password }}"}})), True)
check("one in a play's environment: named", [n for t, sc in judged([{"hosts": "all", "environment": {"T": "{{ vault_token }}"},
                                                                     "tasks": [{"ansible.builtin.shell": "x"}]}])
                                            for n in named(t, sc)], ["environment T={{ vault_token }}"])
check("one on stdin with no_log, a path to one: not named",
      named({"ansible.builtin.shell": {"cmd": "cat {{ secret_dir }}/x", "stdin": "{{ db_password }}"}, "no_log": True})
      + named({"ansible.builtin.shell": "cat x", "args": {"stdin": "{{ db_password }}"}, "no_log": True}), [])
check("one on stdin without no_log (logged on its host): named",
      [bool(named({"ansible.builtin.shell": {"cmd": "cat", "stdin": "{{ db_password }}"}})),
       bool(named({"ansible.builtin.shell": "cat", "args": {"stdin": "{{ db_password }}"}}))], [True, True])
check("one through a variable - the task's, a block's, the play's, through another variable: named",
      [bool(named({"vars": {"c": "mc alias set x {{ minio_secret_key }}"}, "ansible.builtin.shell": "{{ c }}"})),
       bool([n for t, sc in judged([{"hosts": "all", "tasks": [{"vars": {"k": "{{ a_password }}"}, "block": [
           {"ansible.builtin.shell": "x {{ k }}"}]}]}]) for n in named(t, sc)]),
       bool([n for t, sc in judged([{"hosts": "all", "vars": {"k": "{{ a_token }}", "o": {"cmd": ["sh", "{{ k }}"]}},
                                     "tasks": [{"ansible.builtin.shell": "run '{{ o | to_json }}'"}]}])
             for n in named(t, sc)])], [True, True, True])
check("a variable holding no secret, one named alike in plain text: not named",
      named({"vars": {"k": "{{ minio_url }}"}, "ansible.builtin.shell": "echo k {{ k }}"}), [])
check("a module that puts an argument on a command line (git's repo): named; a passphrase too",
      [bool(named({"ansible.builtin.git": {"repo": "https://u:{{ forgejo_token }}@x/r.git", "dest": "/d"}})),
       bool(named({"ansible.builtin.shell": "x {{ key_passphrase }}"}))], [True, True])
bad, used = [], set()
for f in files("deploy/ansible"):
    for t, scope in judged(load(f)):
        for n in named(t, scope):
            if (f, t.get("name")) in ALLOWED:
                used.add((f, t.get("name")))
            else:
                bad.append(f"{f}: {t.get('name')}: {n}")
check("no secret on a command line in deploy/ansible (beyond the excepted)", bad, [])
check("every exception still needed (one whose task changed is dropped, not kept)", sorted(set(ALLOWED) - used), [])
print("secrets-off-argv: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
