#!/bin/bash
# Every free-form shell or command task (the script as the module's string value) reaches the shell as written: run
# through Ansible's own parser of free-form arguments (parse_kv), it is the YAML's text but for line continuations,
# which bash joins the same way. A token ending in a backslash made the parser join the next line into it: in the
# Keycloak restore a comment's `\` swallowed the printf that writes .pgpass, and psql waited at a password prompt for
# good (full run 2026-10-07 15:11). An apostrophe in a comment broke two playbooks' parsing the same way before. The
# dict form (cmd:) is not parsed so; a key=value the parser would take as its own (chdir=, creates=) is named too.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "free-form-shell: no python3 with ansible and yaml"; exit 2; }
"$PY" - <<'PY'
import glob, re, sys
import yaml
from ansible.parsing.splitter import parse_kv
MODULE = re.compile(r"^(?:ansible\.(?:builtin|legacy)\.)?(shell|command)$")


def tasks(node):
    if isinstance(node, list):
        for x in node:
            yield from tasks(x)
    elif isinstance(node, dict):
        yield node
        for k in ("tasks", "pre_tasks", "post_tasks", "handlers", "block", "rescue", "always"):
            yield from tasks(node.get(k))


def as_bash_reads(text):  # line continuations joined, runs of blanks one
    return re.sub(r"[ \t]+", " ", re.sub(r"\\\n[ \t]*", " ", text)).rstrip()


def altered(text):
    """What Ansible's free-form parser changes in a script: [] when it reaches the shell as written."""
    parsed = parse_kv(text, check_raw=True)
    out = [f"taken as the module's own {k}=" for k in sorted(set(parsed) - {"_raw_params"})]
    a, b = as_bash_reads(text).splitlines(), as_bash_reads(parsed.get("_raw_params") or "").splitlines()
    out += [f"{x.strip()[:70]!r} -> {y.strip()[:70]!r}" for x, y in zip(a, b) if x != y][:1]
    if not out and len(a) != len(b):
        out.append(f"{len(a)} lines -> {len(b)}")
    return out


fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f":\n  " + "\n  ".join(map(str, got))))


# the parser's behaviour this guards against, on a fixture: a comment's backslash joins the next line into it
check("a comment's backslash: the next line joined into the comment (the parser as it is)",
      bool(altered("a=1  # escapes \\ and :\nprintf x > f\n")), True)
check("a line continuation: as bash reads it", altered("echo a \\\n  b\n"), [])
seen, bad = 0, []
for f in sorted(glob.glob("deploy/ansible/**/*.yml", recursive=True) + glob.glob("tests/ansible/**/*.yml", recursive=True)):
    if "/venv/" in f:
        continue
    try:
        doc = yaml.safe_load(open(f))
    except yaml.YAMLError:
        continue  # not YAML Ansible reads (a template); ansible-lint parses the playbooks
    for t in tasks(doc):
        for k, v in t.items():
            if MODULE.match(str(k)) and isinstance(v, str):
                seen += 1
                bad += [f"{f}: {t.get('name')}: {d}" for d in altered(v)]
check(f"every free-form shell and command task as written ({seen} of them)", bad, [])
check("free-form tasks found (the walk reaches them)", seen > 400, True)
print("free-form-shell: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
