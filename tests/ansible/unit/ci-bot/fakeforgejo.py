"""A stateful stand-in for the part of Forgejo's API (15.x, Gitea 1.22's) setup-ci-bot.yml talks to, so the REAL
playbook runs against it: users (admin create/edit), an org's teams (units, repositories, members), repositories as a
caller sees them (permissions from the caller's teams, as Forgejo computes them), packages, access tokens (scoped,
basic auth only to list/mint them, as Forgejo wants). Every request is recorded (who asked, how authenticated, its
body); every secret it knows - passwords set, tokens issued - is listed for the argv watch.

Test-only routes: GET /_state, POST /_reset {state}, GET /_secrets, POST /_fail {method, path (regex), nth, and: status -
the nth matching request answered with it; or ignore: [fields] - an edit answered 200, those fields not applied; or
scopes: [...] - a token made with these}.
Port: bound to a free one, written to the file named by argv[1].
"""
import base64
import json
import re
import secrets
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

SCOPES = {f"{rw}:{c}" for rw in ("read", "write") for c in
          ("activitypub", "admin", "issue", "misc", "notification", "organization", "package", "repository", "user")}
UNITS = {"repo.code", "repo.issues", "repo.ext_issues", "repo.wiki", "repo.ext_wiki", "repo.pulls", "repo.releases",
         "repo.projects", "repo.packages", "repo.actions"}
MODES = ["none", "read", "write", "admin", "owner"]
S = {}          # the state
LOG = []        # every request: method, path, auth (kind, user), body
FAULTS = []     # injected answers
EXTRA = set()   # secrets the harness adds (a canary)


def rank(m):
    return MODES.index(m)


def user_json(u):
    return {"id": u["id"], "login": u["login"], "email": u["email"], "is_admin": u["is_admin"],
            "prohibit_login": u["prohibit_login"], "active": u["active"], "restricted": False}


def team_json(t):
    return {k: t[k] for k in ("id", "name", "description", "permission", "units_map", "includes_all_repositories",
                              "can_create_org_repo")}


def unit_mode(login, name, unit):
    """A user's access to one unit of an org repository: the best its teams give (an owner/admin team all of them),
    read on a public repository; a site admin owner."""
    u = S["users"].get(login)
    if u and u["is_admin"]:
        return "owner"
    best = "none"
    for t in S["teams"].values():
        if login in t["members"] and (t["includes_all_repositories"] or name in t["repos"]):
            m = "owner" if t["permission"] in ("owner", "admin") else t["units_map"].get(unit, "none")
            best = max(best, m, key=rank)
    if best == "none" and not S["repos"][name]["private"]:
        best = "read"
    return best


def repo_perm(login, name):
    """(admin, push, pull) of a user on an org repository, or None: no access (Forgejo answers 404). push and admin
    are the code unit's; pull any unit read (a team with pull requests alone sees the repository)."""
    modes = [unit_mode(login, name, un) for un in UNITS]
    code = unit_mode(login, name, "repo.code")
    if max(modes, key=rank) == "none":
        return None
    return rank(code) >= rank("admin"), rank(code) >= rank("write"), True


def package_mode(login):
    u = S["users"].get(login)
    if u and u["is_admin"]:
        return "admin"
    best = "none"
    for t in S["teams"].values():
        if login in t["members"]:
            m = "owner" if t["permission"] in ("owner", "admin") else t["units_map"].get("repo.packages", "none")
            best = max(best, m, key=rank)
    return best


def scope_ok(scopes, category, write):
    if "all" in scopes:
        return True
    return f"write:{category}" in scopes or (not write and f"read:{category}" in scopes)


class H(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def answer(self, code, body=None, headers=None):
        raw = b"" if body is None else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(raw)

    def auth(self):
        """(kind, login, scopes) of the caller, or None; ('bad', ...) for credentials Forgejo refuses."""
        h = self.headers.get("Authorization", "")
        if h.startswith("Basic "):
            login, _, pw = base64.b64decode(h[6:]).decode().partition(":")
            t = next((t for t in S["tokens"].values() if t["sha1"] == pw), None)
            if t:
                return ("token", t["user"], t["scopes"])
            u = S["users"].get(login)
            if not u or u["password"] != pw or u["prohibit_login"] or not u["active"]:
                return ("bad", login, None)
            return ("basic", login, None)
        if h.startswith("Bearer "):
            j = S.setdefault("jwts", {}).get(h[7:])
            return ("token", j["user"], j["scopes"]) if j else ("bad", None, None)
        if h.startswith("token "):
            t = next((t for t in S["tokens"].values() if t["sha1"] == h[6:]), None)
            return ("token", t["user"], t["scopes"]) if t else ("bad", None, None)
        return None

    def handle_any(self, method):
        url = urlparse(self.path)
        path, q = url.path, parse_qs(url.query)
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        body = json.loads(raw) if raw else None
        if path.startswith("/_"):
            return self.test_route(method, path, body)
        who = self.auth()
        LOG.append({"method": method, "path": path, "auth": who[:2] if who else None, "body": body})
        fault = {}
        # every matching fault counts this request first (one firing must not hide it from the next), then they fire
        hit = [f for f in FAULTS if f["method"] == method and re.search(f["path"], path)]
        for f in hit:
            f["seen"] = f.get("seen", 0) + 1
        for f in hit:
            if f["seen"] == f.get("nth", 1):
                if "status" in f:
                    return self.answer(f["status"], {"message": "injected"})
                fault = f  # Forgejo doing otherwise than asked: an edit not applied, a token's scopes its own
        if path.startswith("/v2/"):
            return self.registry(method, path, who)
        if not path.startswith("/api/v1/"):
            return self.answer(404, {"message": "not found"})
        p = path[len("/api/v1"):]
        if who and who[0] == "bad":
            return self.answer(401, {"message": "unauthorized"})
        if who is None:
            return self.answer(401, {"message": "token is required"})
        kind, login, scopes = who
        me = S["users"][login]
        write = method != "GET"
        category = ("admin" if p.startswith("/admin/") else "user" if p == "/user" or re.match(r"^/users/[^/]+$", p)
                    else "organization" if p.startswith(("/orgs/", "/teams/")) else "repository"
                    if p.startswith("/repos/") else "package" if p.startswith("/packages/") else None)
        if re.match(r"^/users/[^/]+/tokens", p):
            if kind != "basic":
                return self.answer(401, {"message": "basic auth required"})
        elif kind == "token" and not scope_ok(scopes, category, write):
            return self.answer(403, {"message": f"token does not have at least one of required scope(s): {category}"})
        limit = min(int(q.get("limit", ["30"])[0]), 50)
        page = int(q.get("page", ["1"])[0])
        pg = lambda xs: xs[(page - 1) * limit:page * limit]  # noqa: E731
        admin_only = p.startswith(("/admin/", "/orgs/", "/teams/")) or re.match(r"^/users/[^/]+$", p)
        if admin_only and not me["is_admin"]:
            return self.answer(403, {"message": "forbidden"})
        m = re.match(r"^/users/([^/]+)$", p)
        if m and method == "GET":
            u = S["users"].get(m.group(1))
            return self.answer(200, user_json(u)) if u else self.answer(404, {"message": "user redirect does not exist"})
        if p == "/admin/users" and method == "POST":
            if not body.get("username") or not body.get("email") or not body.get("password"):
                return self.answer(422, {"message": "username, email, password required"})
            if body["username"] in S["users"]:
                return self.answer(422, {"message": "user already exists"})
            S["seq"] += 1
            S["users"][body["username"]] = {
                "id": S["seq"], "login": body["username"], "email": body["email"], "password": body["password"],
                "is_admin": False, "prohibit_login": False, "active": True,
                # Forgejo's default when the field is left out
                "must_change_password": body.get("must_change_password", True)}
            return self.answer(201, user_json(S["users"][body["username"]]))
        m = re.match(r"^/admin/users/([^/]+)$", p)
        if m and method == "PATCH":
            u = S["users"].get(m.group(1))
            if not u:
                return self.answer(404, {"message": "no user"})
            if "login_name" not in body or "source_id" not in body:
                return self.answer(422, {"message": "login_name and source_id required"})
            for k, f in (("password", "password"), ("admin", "is_admin"), ("must_change_password", "must_change_password"),
                         ("prohibit_login", "prohibit_login"), ("active", "active")):
                if k in body and k not in fault.get("ignore", []):  # a field Forgejo will not change
                    u[f] = body[k]
            return self.answer(200, user_json(u))
        if p == "/user" and method == "GET":
            return self.answer(200, user_json(me))
        m = re.match(r"^/orgs/([^/]+)/teams$", p)
        if m:
            if method == "GET":
                return self.answer(200, pg([team_json(t) for t in S["teams"].values()]))
            err = self.bad_team(body)
            if err:
                return self.answer(422, {"message": err})
            if any(t["name"] == body["name"] for t in S["teams"].values()):
                return self.answer(422, {"message": "team already exists"})
            S["seq"] += 1
            t = {"id": S["seq"], "members": [], "repos": []}
            self.set_team(t, body)
            S["teams"][str(t["id"])] = t
            return self.answer(201, team_json(t))
        m = re.match(r"^/teams/(\d+)(/.*)?$", p)
        if m:
            t = S["teams"].get(m.group(1))
            if not t:
                return self.answer(404, {"message": "no team"})
            rest = m.group(2) or ""
            if rest == "" and method == "GET":
                return self.answer(200, team_json(t))
            if rest == "" and method == "PATCH":
                err = self.bad_team(body)
                if err:
                    return self.answer(422, {"message": err})
                self.set_team(t, {k: v for k, v in body.items() if k not in fault.get("ignore", [])})
                return self.answer(200, team_json(t))
            if rest == "/members" and method == "GET":
                return self.answer(200, pg([user_json(S["users"][x]) for x in t["members"]]))
            mm = re.match(r"^/members/([^/]+)$", rest)
            if mm and method == "PUT":
                if mm.group(1) not in S["users"]:
                    return self.answer(404, {"message": "no user"})
                if mm.group(1) not in t["members"]:
                    t["members"].append(mm.group(1))
                return self.answer(204)
            if rest == "/repos" and method == "GET":
                return self.answer(200, pg([{"name": r, "full_name": f"{S['org']}/{r}", "owner": {"login": S["org"]}}
                                            for r in t["repos"]]))
            mm = re.match(r"^/repos/([^/]+)/([^/]+)$", rest)
            if mm and method in ("PUT", "DELETE"):
                if mm.group(1) != S["org"] or mm.group(2) not in S["repos"]:
                    return self.answer(404, {"message": "no repository"})
                if method == "PUT" and mm.group(2) not in t["repos"]:
                    t["repos"].append(mm.group(2))
                if method == "DELETE" and mm.group(2) in t["repos"]:
                    t["repos"].remove(mm.group(2))
                return self.answer(204)
        m = re.match(r"^/orgs/([^/]+)/repos$", p)
        if m and method == "GET":
            return self.answer(200, pg([{"name": r, "full_name": f"{S['org']}/{r}", "private": v["private"]}
                                        for r, v in sorted(S["repos"].items())]))
        m = re.match(r"^/repos/([^/]+)/([^/]+)/(branches|pulls)$", p)
        if m and method == "GET":
            if m.group(1) != S["org"] or m.group(2) not in S["repos"]:
                return self.answer(404, {"message": "no repository"})
            unit = "repo.code" if m.group(3) == "branches" else "repo.pulls"
            if unit_mode(login, m.group(2), unit) == "none":
                return self.answer(404 if repo_perm(login, m.group(2)) is None else 403, {"message": "no access"})
            return self.answer(200, [])
        m = re.match(r"^/repos/([^/]+)/([^/]+)/branch_protections$", p)
        if m and method == "GET":
            if m.group(1) != S["org"] or m.group(2) not in S["repos"]:
                return self.answer(404, {"message": "no repository"})
            return self.answer(200, S["repos"][m.group(2)].get("protections", []))
        m = re.match(r"^/repos/([^/]+)/([^/]+)$", p)
        if m and method == "GET":
            if m.group(1) != S["org"] or m.group(2) not in S["repos"]:
                return self.answer(404, {"message": "no repository"})
            perm = repo_perm(login, m.group(2))
            if perm is None:
                return self.answer(404, {"message": "no repository"})
            return self.answer(200, {"name": m.group(2), "full_name": f"{S['org']}/{m.group(2)}",
                                     "private": S["repos"][m.group(2)]["private"],
                                     "permissions": dict(zip(("admin", "push", "pull"), perm))})
        m = re.match(r"^/packages/([^/]+)$", p)
        if m and method == "GET":
            if m.group(1) != S["org"] or package_mode(login) == "none":
                return self.answer(404, {"message": "no packages"})
            return self.answer(200, [])
        m = re.match(r"^/users/([^/]+)/tokens(?:/([^/]+))?$", p)
        if m:
            owner, tid = m.group(1), m.group(2)
            if owner != login and not me["is_admin"]:
                return self.answer(403, {"message": "forbidden"})
            mine = [t for t in S["tokens"].values() if t["user"] == owner]
            if method == "GET" and not tid:
                return self.answer(200, pg([{k: t[k] for k in ("id", "name", "token_last_eight", "scopes")}
                                            for t in sorted(mine, key=lambda t: t["id"])]))
            if method == "POST" and not tid:
                if any(t["name"] == body.get("name") for t in mine):
                    return self.answer(400, {"message": "access token name has been used already"})
                if not body.get("scopes") or set(body["scopes"]) - SCOPES:
                    return self.answer(400, {"message": "invalid access token scope"})
                S["seq"] += 1
                sha1 = secrets.token_hex(20)
                t = {"id": S["seq"], "user": owner, "name": body["name"], "sha1": sha1,
                     "token_last_eight": sha1[-8:], "scopes": sorted(fault.get("scopes") or body["scopes"])}
                S["tokens"][str(t["id"])] = t
                return self.answer(201, {k: t[k] for k in ("id", "name", "sha1", "token_last_eight", "scopes")})
            if method == "DELETE" and tid:
                t = S["tokens"].get(tid)
                if not t or t["user"] != owner:
                    return self.answer(404, {"message": "no token"})
                del S["tokens"][tid]
                return self.answer(204)
        return self.answer(404, {"message": f"no route {method} {p}"})

    def registry(self, method, path, who):
        """Forgejo's container registry, the push path Kaniko takes: /v2/token (basic auth - a user and a token) gives a
        bearer; with it an upload starts (POST .../blobs/uploads/ - package write, the token's write:package) and is
        cancelled (DELETE its Location)."""
        if who is None or who[0] == "bad":
            return self.answer(401, {"errors": [{"code": "UNAUTHORIZED"}]})
        kind, login, scopes = who
        if path == "/v2/token" and method == "GET":
            jwt = "jwt" + secrets.token_hex(16)
            S.setdefault("jwts", {})[jwt] = {"user": login, "scopes": scopes or ["all"]}
            return self.answer(200, {"token": jwt})
        if self.headers.get("Authorization", "").split(" ")[0] != "Bearer":
            return self.answer(401, {"errors": [{"code": "UNAUTHORIZED"}]})
        # reads: an image's tags, a manifest - package read (the token's read:package or write:package)
        m = re.match(r"^/v2/([^/]+)/([^/]+)/(tags/list|manifests/([^/]+))$", path)
        if m and method in ("GET", "HEAD"):
            owner, image, what, ref = m.groups()
            if owner != S["org"] or rank(package_mode(login)) < rank("read") or not scope_ok(scopes, "package", False):
                return self.answer(401, {"errors": [{"code": "DENIED"}]})
            tags = S.get("images", {}).get(image)
            if tags is None or (ref and ref not in tags):
                return self.answer(404, {"errors": [{"code": "MANIFEST_UNKNOWN"}]})
            if what == "tags/list":
                return self.answer(200, {"name": f"{owner}/{image}", "tags": tags})
            return self.answer(200, {"schemaVersion": 2, "mediaType": "application/vnd.oci.image.manifest.v1+json"},
                               {"Docker-Content-Digest": "sha256:" + "0" * 64})
        m = re.match(r"^/v2/([^/]+)/([^/]+)/blobs/uploads/(.*)$", path)
        if not m:
            return self.answer(404, {"errors": [{"code": "NAME_UNKNOWN"}]})
        owner, image, uid = m.groups()
        if owner != S["org"] or rank(package_mode(login)) < rank("write") or not scope_ok(scopes, "package", True):
            return self.answer(401, {"errors": [{"code": "DENIED"}]})
        ups = S.setdefault("uploads", [])
        if method == "POST" and uid == "":
            uid = secrets.token_hex(8)
            ups.append(f"{owner}/{image}/{uid}")
            return self.answer(202, None, {"Location": f"/v2/{owner}/{image}/blobs/uploads/{uid}",
                                           "Docker-Upload-UUID": uid})
        if method == "DELETE" and f"{owner}/{image}/{uid}" in ups:
            ups.remove(f"{owner}/{image}/{uid}")
            return self.answer(204)
        return self.answer(404, {"errors": [{"code": "BLOB_UPLOAD_UNKNOWN"}]})

    @staticmethod
    def bad_team(body):
        if not body or not body.get("name"):
            return "name required"
        if body.get("permission", "read") not in ("read", "write", "admin"):
            return "permission must be read, write or admin"
        um = body.get("units_map") or {}
        if set(um) - UNITS or set(um.values()) - set(MODES[:4]):
            return "bad units_map"
        return None

    @staticmethod
    def set_team(t, body):
        """A create sets every field (false where left out); an edit only those it sends - the others stay as they
        were (Forgejo's EditTeamOption: pointers, nil = unchanged)."""
        create = "units_map" not in t
        if create or "units_map" in body:
            t["units_map"] = dict(body.get("units_map") or {})
        perm = body.get("permission", t.get("permission", "read"))
        if perm != "admin" and t["units_map"]:  # Forgejo: the team's level is its units' lowest
            perm = min(t["units_map"].values(), key=rank)
        t.update(name=body["name"], permission=perm)
        for k, default in (("description", ""), ("includes_all_repositories", False), ("can_create_org_repo", False)):
            if create or k in body:
                t[k] = body.get(k, default)

    def test_route(self, method, path, body):
        global S, LOG, FAULTS
        if path == "/_state":
            return self.answer(200, {"state": S, "log": LOG})
        if path == "/_reset":
            S, LOG, FAULTS = body, [], []
            return self.answer(200, {})
        if path == "/_fail":
            FAULTS.append(body)
            return self.answer(200, {})
        if path == "/_canary":
            EXTRA.add(body["secret"])
            return self.answer(200, {})
        if path == "/_secrets":
            known = {u["password"] for u in S.get("users", {}).values()} | {t["sha1"] for t in S.get("tokens", {}).values()}
            # every password and token seen in a request body too (the bot's random password, once sent)
            for e in LOG:
                b = e.get("body") or {}
                if isinstance(b, dict) and isinstance(b.get("password"), str):
                    known.add(b["password"])
            known |= set(S.get("jwts", {}))
            return self.answer(200, sorted(x for x in known | EXTRA if x))
        return self.answer(404, {})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PATCH(self):
        self.handle_any("PATCH")

    def do_PUT(self):
        self.handle_any("PUT")

    def do_DELETE(self):
        self.handle_any("DELETE")


srv = HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[1], "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
