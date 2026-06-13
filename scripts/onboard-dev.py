#!/usr/bin/env python3
"""Onboard a developer.

Two things happen, idempotently:

  1. Keycloak (schnappy realm): create the login account with a temporary
     password (forced reset on first login). Skipped if it already exists.

  2. Forgejo: create a personal organization `<username><ORG_SUFFIX>` owned
     by the developer. This can only happen AFTER the developer has signed
     in to git.pmon.dev once (Forgejo auto-registers them from the keycloak
     OAuth source on first login). The owner is resolved by EMAIL, because a
     developer's Forgejo username is chosen at first login and need not match
     their Keycloak username.

So the flow is: run this once to create the Keycloak account, have the
developer sign in at git.pmon.dev via Keycloak, then run it again to create
their org. Re-running is always safe.

Credentials come from the environment (loaded by `task` from ops/.env):
  KEYCLOAK_ADMIN_PASSWORD, FORGEJO_ADMIN_USER (default forgejo_admin),
  FORGEJO_ADMIN_PASSWORD.

Usage:
  task onboard:dev USER=jane EMAIL=jane@example.com
  ONBOARD_USER=jane ONBOARD_EMAIL=jane@example.com python3 scripts/onboard-dev.py
Set DRY_RUN=1 to print intended changes without making any.
"""
import base64
import json
import os
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

KC = os.environ.get("KEYCLOAK_URL", "https://auth.pmon.dev")
REALM = os.environ.get("KEYCLOAK_REALM", "schnappy")
FORGEJO = os.environ.get("FORGEJO_URL", "https://git.pmon.dev")
ORG_SUFFIX = os.environ.get("ORG_SUFFIX", "-team")
ORG_VISIBILITY = os.environ.get("ORG_VISIBILITY", "private")  # public | limited | private
DRY = os.environ.get("DRY_RUN", "") not in ("", "0", "false", "no")

USERNAME = (os.environ.get("ONBOARD_USER") or "").strip()
EMAIL = (os.environ.get("ONBOARD_EMAIL") or "").strip()
# This realm's user profile requires firstName + lastName. Take a real name via
# NAME="First Last" when known; otherwise fall back to the username so the
# create succeeds (the developer can set their display name on first login).
NAME = (os.environ.get("ONBOARD_NAME") or "").strip()
if NAME:
    _p = NAME.split()
    FIRST, LAST = _p[0], (" ".join(_p[1:]) if len(_p) > 1 else _p[0])
else:
    FIRST = LAST = USERNAME


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def envval(name):
    v = os.environ.get(name)
    if v:
        return v
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")
    try:
        with open(env_path) as fh:
            for line in fh:
                s = line.strip()
                if s.startswith("export "):
                    s = s[7:]
                if s.startswith(name + "="):
                    return s.split("=", 1)[1].strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return None


def post_form(url, fields):
    req = urllib.request.Request(
        url, data=urllib.parse.urlencode(fields).encode(), method="POST")
    return json.load(urllib.request.urlopen(req, timeout=20))


def http(url, method="GET", token=None, basic=None, data=None):
    headers = {}
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token
    if basic:
        headers["Authorization"] = "Basic " + base64.b64encode(
            f"{basic[0]}:{basic[1]}".encode()).decode()
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        resp = urllib.request.urlopen(req, timeout=20)
        raw = resp.read()
        return resp.getcode(), (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            parsed = json.loads(raw) if raw else None
        except Exception:
            parsed = raw.decode(errors="replace")
        return e.code, parsed


# ---- Keycloak --------------------------------------------------------------

def kc_token():
    pw = envval("KEYCLOAK_ADMIN_PASSWORD") or die("KEYCLOAK_ADMIN_PASSWORD not set")
    for u in ("admin", "temp-admin"):
        try:
            return post_form(KC + "/realms/master/protocol/openid-connect/token",
                             {"grant_type": "password", "client_id": "admin-cli",
                              "username": u, "password": pw})["access_token"]
        except Exception:
            continue
    die("could not authenticate to Keycloak")


def ensure_kc_user(token):
    q = urllib.parse.quote(USERNAME)
    _, users = http(f"{KC}/admin/realms/{REALM}/users?username={q}&exact=true", token=token)
    if users:
        print(f"[kc]      user '{USERNAME}' already exists ({users[0]['id']})")
        return
    if not EMAIL:
        die("EMAIL is required to create a new Keycloak user")
    if DRY:
        print(f"[kc]      [dry-run] would create user '{USERNAME}' "
              f"(email={EMAIL}, name='{FIRST} {LAST}') + temp password")
        return
    code, resp = http(f"{KC}/admin/realms/{REALM}/users", "POST", token=token,
                      data={"username": USERNAME, "email": EMAIL,
                            "firstName": FIRST, "lastName": LAST,
                            "enabled": True, "emailVerified": True})
    if code != 201:
        die(f"[kc] failed to create user (HTTP {code}): {resp}")
    _, users = http(f"{KC}/admin/realms/{REALM}/users?username={q}&exact=true", token=token)
    uid = users[0]["id"]
    temp = secrets.token_urlsafe(12)
    code, _ = http(f"{KC}/admin/realms/{REALM}/users/{uid}/reset-password", "PUT", token=token,
                   data={"type": "password", "value": temp, "temporary": True})
    if code not in (204, 200):
        die(f"[kc] user created but setting temp password failed (HTTP {code})")
    print(f"[kc]      created user '{USERNAME}' ({uid})")
    print(f"[kc]      TEMPORARY PASSWORD (share securely, forced reset on first login): {temp}")


# ---- Forgejo ---------------------------------------------------------------

def forgejo_user_by_email(creds):
    page = 1
    while True:
        code, users = http(f"{FORGEJO}/api/v1/admin/users?limit=50&page={page}", basic=creds)
        if code != 200 or not users:
            return None
        for u in users:
            if (u.get("email") or "").lower() == EMAIL.lower():
                return u.get("login") or u.get("username")
        if len(users) < 50:
            return None
        page += 1


def ensure_forgejo_org(creds):
    if not EMAIL:
        die("EMAIL is required to resolve the Forgejo account")
    owner = forgejo_user_by_email(creds)
    if not owner:
        print(f"[forgejo] no account with email {EMAIL} yet — the developer must sign in "
              f"once at\n          {FORGEJO} via \"Sign in with Keycloak\", then re-run this.")
        return False
    org = f"{USERNAME}{ORG_SUFFIX}"
    code, _ = http(f"{FORGEJO}/api/v1/orgs/{urllib.parse.quote(org)}", basic=creds)
    if code == 200:
        print(f"[forgejo] org '{org}' already exists (owner resolved: '{owner}')")
        return True
    if DRY:
        print(f"[forgejo] [dry-run] would create org '{org}' owned by '{owner}' "
              f"(visibility={ORG_VISIBILITY})")
        return True
    code, resp = http(f"{FORGEJO}/api/v1/admin/users/{urllib.parse.quote(owner)}/orgs",
                      "POST", basic=creds,
                      data={"username": org, "visibility": ORG_VISIBILITY,
                            "repo_admin_change_team_access": True})
    if code == 201:
        print(f"[forgejo] created org '{org}' owned by '{owner}' (visibility={ORG_VISIBILITY})")
        return True
    die(f"[forgejo] failed to create org '{org}': HTTP {code} {resp}")


# ---- main ------------------------------------------------------------------

def main():
    if not USERNAME:
        die("USER is required (task onboard:dev USER=jane EMAIL=jane@example.com)")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]*", USERNAME):
        die(f"invalid username '{USERNAME}' (letters, digits, '.', '_', '-')")
    print(f"== onboarding '{USERNAME}'{' (DRY RUN)' if DRY else ''} "
          f"-> org '{USERNAME}{ORG_SUFFIX}'")
    ensure_kc_user(kc_token())
    forgejo_creds = (envval("FORGEJO_ADMIN_USER") or "forgejo_admin",
                     envval("FORGEJO_ADMIN_PASSWORD") or die("FORGEJO_ADMIN_PASSWORD not set"))
    done = ensure_forgejo_org(forgejo_creds)
    print("== done" if done else "== Keycloak account ready; org pending first login")


if __name__ == "__main__":
    main()
