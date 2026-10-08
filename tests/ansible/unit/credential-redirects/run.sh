#!/bin/bash
# A uri task that sends a credential - basic auth (force_basic_auth, url_password, password) or an Authorization or token
# header - never follows a redirect: Ansible's default ("safe") follows a GET's to any host with every header kept,
# the Authorization among them (ansible/module_utils/urls.py, redirect_request: only the body's headers dropped), so a
# redirect off the host - a misconfigured proxy, a moved service - hands it the admin's password. follow_redirects:
# none - a redirect is a failed status, said. Every playbook and task file, the tests' too (the copy's runs carry
# production's secrets).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
PY=python3
"$PY" -c 'import ansible, yaml' 2> /dev/null || PY=deploy/ansible/venv/bin/python3
PYTHONDONTWRITEBYTECODE=1 "$PY" - <<'PYCRED'
import sys
sys.path.insert(0, "tests/ansible/unit")
from plays import actions, files, load, tasks  # noqa: E402
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got}, want {want}"))
def sends_credential(v):
    headers = v.get("headers") or {}
    return bool(v.get("force_basic_auth") or v.get("url_password") or v.get("password")
                or any(str(k).lower() == "authorization" or "token" in str(k).lower() for k in headers))
found, follows = 0, []
for f in files():
    for t in tasks(load(f)):
        for mod, v in actions(t):
            if str(mod).split(".")[-1] != "uri" or not isinstance(v, dict) or not sends_credential(v):
                continue
            found += 1
            if str(v.get("follow_redirects", "safe")).lower() not in ("none", "no", "false"):
                follows.append(f"{f}: {t.get('name')}")
check("every uri task sending a credential follows no redirect", len(follows), 0)
for x in follows[:200]:
    print("    " + x)
# the lint sees them: Forgejo's admin (setup-velero's mirror tokens), Keycloak's admin API, Nexus's
check("the tasks found: more than 80, the mirror's token listing among them", found > 80, True)
# its predicate on cases: each credential form seen, a plain GET not
check("the credential forms: basic auth, url_password, an Authorization header, a token header; none on a plain GET",
      [sends_credential(x) for x in ({"force_basic_auth": True, "user": "u", "password": "p"}, {"url_password": "p"},
                                     {"headers": {"Authorization": "Bearer x"}}, {"headers": {"X-Vault-Token": "t"}},
                                     {"url": "https://x", "method": "GET"})], [True, True, True, True, False])
print("credential-redirects: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCRED
