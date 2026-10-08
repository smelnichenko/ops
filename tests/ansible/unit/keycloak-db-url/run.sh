#!/bin/bash
# Keycloak's database URL, wherever a playbook writes it: the driver told to take any server (targetServerType=any).
# PgBouncer hands every client the startup parameters of its pool's first server connection and never reads them
# again; one that landed on the replica (HAProxy's servers start up, before their first check) reads in_hot_standby=on
# for good, and Keycloak's default, targetServerType=primary, refused every connection until PgBouncer restarted - the
# Pis' reboot left Keycloak down (Vagrant full run, 2026-10-08). HAProxy's /primary check is what picks the primary.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCHECK'
import re
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
def strings(v):
    if isinstance(v, dict):
        for x in v.values():
            yield from strings(x)
    elif isinstance(v, list):
        for x in v:
            yield from strings(x)
    elif isinstance(v, str):
        yield v
# every URL a task writes into Keycloak's unit (a reader - a grep of the unit - carries no Environment=)
urls = {}
for f in files("deploy/ansible"):
    for t in tasks(load(f)):
        for _, value in actions(t):
            for s in strings(value):
                for u in re.findall(r"Environment=KC_DB_URL=([^\n]+)", s):
                    urls.setdefault(f.split("/")[-1], []).append(u)
check("the writers found: the unit's install and Patroni's port switch",
      sorted(urls), ["setup-patroni.yml", "setup-pi-services.yml"])
for f, found in sorted(urls.items()):
    for u in found:
        q = u.split("?", 1)[1] if "?" in u else ""
        check(f"{f}: {u} - the driver takes any server, no other server type",
              re.findall(r"(?:^|&)targetServerType=([^&\"']*)", q), ["any"])
# the copy given production's unit (tests/ansible/upgrade/production-state.yml): its URL as production's Pis have it,
# before the fix - step 00 moves it
state = [u for t in tasks(load("tests/ansible/upgrade/production-state.yml")) for _, v in actions(t) for s in strings(v)
         for u in re.findall(r"Environment=KC_DB_URL=([^\n]+)", s)]
check("the copy's production state: production's URL (no server type), step 00 moving it to the playbooks'",
      (state, any("playbook setup-pi-services.yml --tags keycloak-db-url" == l.strip()
                  for l in open("tests/ansible/upgrade/steps/00-gluster-boot.txt"))),
      (["jdbc:postgresql://127.0.0.1:6432/keycloak"], True))
# one URL's query on every writer: two that differ restart Keycloak on each other's every run
check("the same query from every writer", len({u.split("?", 1)[-1] for found in urls.values() for u in found}), 1)
print("keycloak-db-url: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
