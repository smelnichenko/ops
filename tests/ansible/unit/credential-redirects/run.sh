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
# nor a Python script's request: urllib's redirect keeps every header added by add_header or the constructor's
# headers= (Authorization among them) - to any host; add_unredirected_header's never follow a redirect
import glob, re  # noqa: E401,E402
PY_AUTH = re.compile(r"add_header\(\s*['\"]Authorization['\"]|\[\s*['\"]Authorization['\"]\s*\]\s*=|['\"]Authorization['\"]\s*:")
py_hits = [f"{f}:{n}" for f in sorted(glob.glob("scripts/*.py") + glob.glob("deploy/ansible/playbooks/scripts/*.py"))
           for n, line in enumerate(open(f, errors="replace"), 1) if PY_AUTH.search(line)]
check("no Python script hands urllib an Authorization header a redirect keeps (add_unredirected_header alone)", py_hits, [])
# and that header, as urllib sends it, stays off a redirect: two local servers, the first redirecting to the second
import http.server, threading, urllib.request  # noqa: E401,E402
got = {}
class Second(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        got["second"] = self.headers.get("Authorization")
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a):
        pass
second = http.server.HTTPServer(("127.0.0.1", 0), Second)
class First(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(302); self.send_header("Location", f"http://127.0.0.1:{second.server_port}/x"); self.end_headers()
    def log_message(self, *a):
        pass
first = http.server.HTTPServer(("127.0.0.1", 0), First)
for srv in (first, second):
    threading.Thread(target=srv.serve_forever, daemon=True).start()
def follow(add):
    got.clear()
    r = urllib.request.Request(f"http://127.0.0.1:{first.server_port}/")
    getattr(r, add)("Authorization", "Basic c2VjcmV0")
    urllib.request.urlopen(r, timeout=10).read()
    return got.get("second")
check("measured: add_header's Authorization reaches the redirect's host, add_unredirected_header's does not",
      (follow("add_header"), follow("add_unredirected_header")), ("Basic c2VjcmV0", None))
print("credential-redirects: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCRED
