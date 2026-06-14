#!/usr/bin/env python3
"""Onboard a developer — one idempotent command, no manual login step.

Three things happen, idempotently:

  1. Keycloak (schnappy realm): create the login account with a temporary
     password (forced reset on first login). Skipped if it already exists.

  2. Forgejo: pre-create the developer's account, linked to their Keycloak
     identity (source_id = the keycloak OAuth source, login_name = the KC
     `sub` UUID, which we know because we mint the Keycloak user). Forgejo
     matches the eventual "Sign in with Keycloak" by that sub against the
     user table, so the developer's first login authenticates straight into
     this account — no duplicate, no account-link prompt. This is exactly how
     an already-logged-in user's row looks (login_type=OAuth2, login_source,
     login_name=sub); it needs no app.ini change.

  3. Forgejo: create a personal organization `<username><ORG_SUFFIX>` owned
     by the developer (owner resolved by email).

So onboarding is a single run; the developer signs in whenever they like.
Re-running is always safe — existing Keycloak user / Forgejo account / org
are detected and skipped.

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
# Forgejo login source for Keycloak (verified live: login_source id=1, type OAuth2).
FORGEJO_SOURCE_ID = int(os.environ.get("FORGEJO_SOURCE_ID", "1"))
DRY = os.environ.get("DRY_RUN", "") not in ("", "0", "false", "no")

USERNAME = (os.environ.get("ONBOARD_USER") or "").strip()
EMAIL = (os.environ.get("ONBOARD_EMAIL") or "").strip()
# This realm's user profile requires firstName + lastName. Take a real name via
# NAME="First Last" when known; otherwise fall back to the username so the
# create succeeds (the developer can set their display name on first login).
NAME = (os.environ.get("ONBOARD_NAME") or "").strip()
if NAME == "<no value>":  # Task renders an unset variable as this literal
    NAME = ""
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


def _ensure_kc_name(token, u):
    """Correct a Keycloak user's firstName/lastName if a real NAME was passed
    and differs (e.g. an earlier run created the user without forwarding NAME)."""
    if not NAME or (u.get("firstName") == FIRST and u.get("lastName") == LAST):
        return
    # Update the in-memory record first so the Forgejo full_name derives from
    # the corrected name (also makes the dry-run preview accurate).
    u["firstName"], u["lastName"] = FIRST, LAST
    if DRY:
        print(f"[kc]      [dry-run] would update name to '{FIRST} {LAST}'")
        return
    code, resp = http(f"{KC}/admin/realms/{REALM}/users/{u['id']}", "PUT", token=token, data=u)
    if code in (200, 204):
        print(f"[kc]      updated name to '{FIRST} {LAST}'")
    else:
        print(f"[kc]      warn: could not update name: HTTP {code} {resp}")


def ensure_kc_user(token):
    q = urllib.parse.quote(USERNAME)
    _, users = http(f"{KC}/admin/realms/{REALM}/users?username={q}&exact=true", token=token)
    if users:
        u = users[0]
        print(f"[kc]      user '{USERNAME}' already exists ({u['id']})")
        _ensure_kc_name(token, u)
        return u
    if not EMAIL:
        die("EMAIL is required to create a new Keycloak user")
    if DRY:
        print(f"[kc]      [dry-run] would create user '{USERNAME}' "
              f"(email={EMAIL}, name='{FIRST} {LAST}') + temp password")
        return None
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
    return users[0]


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


def ensure_forgejo_user(creds, kc_user):
    """Pre-create the developer's Forgejo account linked to their Keycloak sub.

    Forgejo's OIDC callback matches an incoming login by (login_type=OAuth2,
    login_source, login_name=sub) against the user table first, so setting
    login_name to the KC sub makes the eventual first login authenticate into
    this exact account — no duplicate, no link prompt. The display name
    (full_name) is taken from the Keycloak identity (firstName + lastName). The
    local `password` is required by the API but unused for an OAuth account; we
    generate it high-entropy and discard it.
    """
    if kc_user is None:  # DRY run that would have just created the Keycloak user
        print(f"[forgejo] [dry-run] would pre-create OAuth2 user '{USERNAME}' linked to the new Keycloak sub")
        return USERNAME
    kc_sub = kc_user["id"].lower()
    full_name = " ".join(p for p in (kc_user.get("firstName"), kc_user.get("lastName")) if p).strip()
    existing = forgejo_user_by_email(creds)
    if existing:
        print(f"[forgejo] account for {EMAIL} already exists ('{existing}')")
        _ensure_forgejo_fullname(creds, existing, kc_sub, full_name)
        return existing
    if DRY:
        print(f"[forgejo] [dry-run] would pre-create OAuth2 user '{USERNAME}' "
              f"(source_id={FORGEJO_SOURCE_ID}, login_name={kc_sub}, full_name='{full_name}')")
        return USERNAME
    body = {"username": USERNAME, "email": EMAIL, "full_name": full_name,
            "login_name": kc_sub, "source_id": FORGEJO_SOURCE_ID,
            "password": secrets.token_urlsafe(32), "must_change_password": False,
            "send_notify": False}
    code, resp = http(f"{FORGEJO}/api/v1/admin/users", "POST", basic=creds, data=body)
    if code == 201:
        print(f"[forgejo] pre-created OAuth2 user '{USERNAME}' (full_name='{full_name}') "
              f"linked to Keycloak sub {kc_sub}")
        return USERNAME
    if code == 422:  # name/email already taken — treat as idempotent success
        print(f"[forgejo] user '{USERNAME}' already exists (422) — continuing")
        owner = forgejo_user_by_email(creds) or USERNAME
        _ensure_forgejo_fullname(creds, owner, kc_sub, full_name)
        return owner
    die(f"[forgejo] failed to pre-create user '{USERNAME}': HTTP {code} {resp}")


def _ensure_forgejo_fullname(creds, login, kc_sub, full_name):
    """Set the Forgejo account's display name from Keycloak if it's missing/stale.

    EditUserOption requires login_name + source_id, so pass them through unchanged.
    """
    if not full_name:
        return
    code, u = http(f"{FORGEJO}/api/v1/users/{urllib.parse.quote(login)}", basic=creds)
    if code != 200 or (u.get("full_name") or "") == full_name:
        return
    if DRY:
        print(f"[forgejo] [dry-run] would set full_name of '{login}' to '{full_name}'")
        return
    code, resp = http(f"{FORGEJO}/api/v1/admin/users/{urllib.parse.quote(login)}", "PATCH",
                      basic=creds,
                      data={"login_name": kc_sub, "source_id": FORGEJO_SOURCE_ID, "full_name": full_name})
    if code == 200:
        print(f"[forgejo] set full_name of '{login}' to '{full_name}'")
    else:
        print(f"[forgejo] warn: could not set full_name of '{login}': HTTP {code} {resp}")


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
    kc_user = ensure_kc_user(kc_token())
    if kc_user is None and not DRY:
        die("could not determine the Keycloak account for Forgejo pre-provisioning")
    forgejo_creds = (envval("FORGEJO_ADMIN_USER") or "forgejo_admin",
                     envval("FORGEJO_ADMIN_PASSWORD") or die("FORGEJO_ADMIN_PASSWORD not set"))
    ensure_forgejo_user(forgejo_creds, kc_user)
    done = ensure_forgejo_org(forgejo_creds)
    print("== done" if done else "== Keycloak account ready; org pending (dry run)")


if __name__ == "__main__":
    main()
