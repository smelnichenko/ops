#!/bin/bash
# tests/ansible/upgrade/keycloak-realm.yml's admin token: asked of a Keycloak that may still be starting (the seed
# runs right after the Pis' services - Caddy answers 502 until Keycloak listens), it waits for it - each answer judged
# as Ansible judges its until - for as long as a Keycloak start takes (the restart's own wait, 240 s), not failed at
# the first 502 with nothing said.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYKRT'
import sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import condition  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
play = next(p for p in yaml.safe_load(open("tests/ansible/upgrade/keycloak-realm.yml")) if p.get("hosts") == "pi1")
t = next(t for t in play["tasks"] if t.get("name") == "Keycloak admin token")
reg = t.get("register")
ok = {"status": 200, "json": {"access_token": "x"}}
check("the token waited for: a 502 (Keycloak starting) and a refused connection (-1) tried again, a token taken",
      [condition(t["until"], **{reg: r}) if "until" in t else None
       for r in ({"status": 502, "failed": True}, {"status": -1, "failed": True}, ok)], [False, False, True])
# a refused password (401) is no Keycloak starting: not waited on (five minutes of retries, then the same failure)
check("a 401 (the admin's password refused) ends the wait at once - failing",
      (condition(t["until"], **{reg: {"status": 401, "failed": True}}) if "until" in t else None), True)
check("for as long as a Keycloak start takes (240 s at least)",
      int(t.get("retries", 0)) * int(t.get("delay", 5)) >= 240, True)
check("its failure still a failure once the wait is over (its status not widened)",
      t.get("ansible.builtin.uri", {}).get("status_code", 200) in (200, [200]), True)
print("keycloak-realm-token: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYKRT
