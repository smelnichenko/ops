#!/bin/bash
# A file the playbooks write with no_log or diff: false holds secrets (their own word): every other task that edits it -
# a line, a block, a replace - is no_log or diff: false. A --diff run prints a changed line with three lines around it: setup-
# patroni's KC_DB_URL edit printed production's KC_DB_PASSWORD two lines below it (Keycloak's unit), Forgejo's HOST
# edit app.ini's database password.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
WRITERS = ("copy", "template")
EDITORS = ("lineinfile", "blockinfile", "replace", "ini_file")
def target(v):
    return str(v.get("dest") or v.get("path") or "") if isinstance(v, dict) else ""
secret, edits = set(), []
for f in files("deploy/ansible"):
    for t in tasks(load(f)):
        for mod, v in actions(t):
            m = str(mod).split(".")[-1]
            if m in WRITERS and (t.get("no_log") is True or t.get("diff") is False) and target(v):
                secret.add(target(v))
            elif m in EDITORS and target(v):
                edits.append((f, t.get("name"), target(v), t.get("no_log") is True or t.get("diff") is False))
check("secret files found by the playbooks' own no_log or diff: false (Keycloak's unit, Forgejo's app.ini among them)",
      {"/etc/systemd/system/keycloak.service", "/var/lib/forgejo/custom/conf/app.ini"} <= secret, True)
bad = [(f, n, p) for f, n, p, quiet in edits if p in secret and not quiet]
check("every edit of a secret file no_log or diff: false", len(bad), 0)
for f, n, p in bad:
    print(f"    {f}: {n} ({p})")
print("secret-file-diffs: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
