#!/bin/bash
# A regex in a template ({{ }} in a value - set_fact, vars, a module argument) is written with single backslashes: in a
# template Ansible keeps a string literal's backslash escapes as written, so '^\\s*0\\s*$' (as a folded or plain YAML
# scalar holds it) is a backslash and an s to the regex and matches nothing - setup-gluster's list of the services to
# stop before a fresh-install migration was always empty. (A conditional - when, until, failed_when, that - reads the
# escapes as Jinja does; both forms work there.) Named: a string literal holding \\ before a regex character in a
# template; and setup-gluster's list rendered as Ansible renders it.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
"$PY" -c 'import ansible, yaml' || { echo "jinja-escapes: no python3 with ansible and yaml"; exit 2; }
"$PY" - <<'PY'
import glob, re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render
CONDITIONAL = {"when", "failed_when", "changed_when", "until", "that"}
LITERAL = re.compile(r"'([^']*)'|\"([^\"]*)\"")
DOUBLED = re.compile(r"\\\\[.dswbDSWB()\[\]+*?^$|{}]")
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else ":\n  " + "\n  ".join(map(str, got))))


def strings(node, key=""):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from strings(v, str(k))
    elif isinstance(node, list):
        for v in node:
            yield from strings(v, key)
    elif isinstance(node, str):
        yield key, node


bad = []
for f in sorted(glob.glob("deploy/ansible/**/*.yml", recursive=True) + glob.glob("tests/ansible/**/*.yml", recursive=True)):
    if "/venv/" in f:
        continue
    try:
        doc = yaml.safe_load(open(f))
    except yaml.YAMLError:
        continue
    for key, s in strings(doc):
        if key in CONDITIONAL:
            continue
        for expr in re.findall(r"\{\{(.*?)\}\}", s, re.S):
            for m in LITERAL.finditer(expr):
                lit = m.group(1) if m.group(1) is not None else m.group(2)
                if DOUBLED.search(lit):
                    bad.append(f"{f}: {key}: {lit!r}")
check("no template's regex written with doubled backslashes", bad, [])
play = yaml.safe_load(open("deploy/ansible/playbooks/setup-gluster.yml"))
task = next(t for p in play for t in p.get("tasks") or [] if t.get("name") == "Build list of services to stop before fresh-install migration")
results = [{"stdout": "0", "item": {"stop_service": "forgejo"}}, {"stdout": " 0 \n", "item": {"stop_service": "versitygw"}},
           {"stdout": "3", "item": {"stop_service": "keycloak"}}, {"stdout": "0", "item": {"stop_service": ""}}]
got = render(task["ansible.builtin.set_fact"]["fresh_install_services"], backup_brick_count={"results": results})
check("setup-gluster: the services on an empty brick (0 entries) listed to stop, as Ansible renders it",
      [i["stop_service"] for i in got], ["forgejo", "versitygw"])
print("jinja-escapes: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PY
