#!/bin/bash
# Every free-form task (shell, command, raw, script - Ansible's own FREEFORM_ACTIONS; the script as the module's string
# value) reaches the shell as written: run through Ansible's own parser of free-form arguments (parse_kv), it is the
# YAML's text exactly but for line continuations, which bash joins the same way. Every task of every play section and
# block (tests/ansible/unit/plays.py's walk); a file Ansible cannot read fails it. A token ending in a backslash made
# the parser join the next line into it: in the Keycloak restore a comment's `\` swallowed the printf that writes
# .pgpass, and psql waited at a password prompt for good (full run 2026-10-07 15:11). An apostrophe in a comment broke
# two playbooks' parsing the same way before. The dict form (cmd:) is not parsed so; a key=value the parser would take
# as its own (chdir=, creates=) is named too.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "free-form-shell: no python3 with ansible and yaml"; exit 2; }
"$PY" - <<'PY'
import re, sys
from ansible.parsing.mod_args import FREEFORM_ACTIONS
from ansible.errors import AnsibleParserError
from ansible.parsing.splitter import parse_kv
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402


def logical(text):
    """bash's lines: [(line, joined)] - a line ending in an odd run of backslashes joined to the next (joined: True)."""
    out, cur, joined = [], "", False
    for line in text.split("\n"):
        if (len(line) - len(line.rstrip("\\"))) % 2:
            cur, joined = cur + line[:-1] + " ", True
            continue
        out.append((cur + line, joined))
        cur, joined = "", False
    if cur:
        out.append((cur, joined))
    while out and not out[-1][0].strip():
        out.pop()
    return out


def squash(line):  # a joined line's blanks: the parser and bash space a continuation differently, both one separator
    return re.sub(r"[ \t]+", " ", line).strip()


def altered(text, raw=None):
    """What Ansible's free-form parser changes in a script (`raw`: what it made of it, else parse_kv's): [] when it
    reaches the shell as written - every line exact (trailing blanks aside), a continuation's joined line up to its
    blanks."""
    try:
        parsed = parse_kv(text, check_raw=True) if raw is None else {"_raw_params": raw}
    except AnsibleParserError as e:  # Ansible cannot run it at all: named, not a crash of the harness
        return [f"unparseable: {str(e).splitlines()[0][:90]}"]
    out = [f"taken as the module's own {k}=" for k in sorted(set(parsed) - {"_raw_params"})]
    a, b = logical(text), [line for line, _ in logical(parsed.get("_raw_params") or "")]
    out += [f"{x.strip()[:70]!r} -> {y.strip()[:70]!r}" for (x, joined), y in zip(a, b)
            if (squash(x) != squash(y) if joined else x.rstrip() != y.rstrip())][:1]
    if not out and len(a) != len(b):
        out.append(f"{len(a)} lines -> {len(b)}")
    return out


fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f":\n  " + "\n  ".join(map(str, got if isinstance(got, list) else [got]))))


# the parser's behaviour this guards against, on a fixture: a comment's backslash joins the next line into it
check("a comment's backslash: the next line joined into the comment (the parser as it is)",
      bool(altered("a=1  # escapes \\ and :\nprintf x > f\n")), True)
check("a line continuation: as bash reads it", altered("echo a \\\n  b\n"), [])
check("an apostrophe in a comment: unparseable, named", bool(altered("# it's\necho x\n")), True)
# the comparison exact where no continuation is: blanks inside a quoted string changed are a change
check("blanks changed inside a quoted string: named", bool(altered("echo 'a  b'\n", raw="echo 'a b'\n")), True)
check("a continuation spaced otherwise: the same", altered("echo a \\\n    b\n", raw="echo a  b\n"), [])
seen, bad = 0, []
for f in files():
    for t in tasks(load(f)):
        for module, value in actions(t):
            if module in FREEFORM_ACTIONS and isinstance(value, str):
                seen += 1
                bad += [f"{f}: {t.get('name')}: {d}" for d in altered(value)]
check(f"every free-form task (shell, command, raw, script...) as written ({seen} of them)", bad, [])
check("free-form tasks found (the walk reaches them)", seen > 500, True)
print("free-form-shell: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
