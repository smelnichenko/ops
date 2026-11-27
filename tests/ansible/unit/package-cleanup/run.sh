#!/bin/bash
# scripts/package-cleanup.py against a fake Forgejo (its packages API, paged; deletions recorded), a stub for the
# cluster's running images and a fixture of infra/platform/ops: the newest 10 of an image and 5 of a build cache kept,
# `latest` kept, a tag infra names (a values file's repository + tag, a name:tag) or the cluster runs kept however old,
# a build cache's version kept for its image's tag in use; a plan only without --apply; with it exactly the plan
# deleted (a name with a slash encoded); a refused deletion stops it; the packages, the cluster's images or the token
# missing - nothing deleted.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
python3 - <<'PYCHECK'
import json, os, subprocess, sys, tempfile, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote
fails = 0
def check(name, got, want):
    global fails
    if got == want:
        print("PASS " + name)
    else:
        fails += 1
        print(f"FAIL {name}\n    got:  {got!r}\n    want: {want!r}")
W = tempfile.mkdtemp()
# 14 masi images (m00 newest .. m13 oldest), 8 masi/cache versions, 3 site images, latest on site
PKGS = [{"name": "masi", "version": f"m{i:02d}", "created_at": f"2026-11-{30 - i:02d}T00:00:00Z"} for i in range(14)]
PKGS += [{"name": "masi/cache", "version": f"c{i:02d}", "created_at": f"2026-11-{30 - i:02d}T00:00:00Z"} for i in range(8)]
PKGS += [{"name": "site", "version": v, "created_at": f"2026-10-0{i + 1}T00:00:00Z"} for i, v in enumerate(["s1", "latest", "s3"])]
state = {"deleted": [], "fail_list": False, "refuse": None}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if state["fail_list"] or self.headers.get("Authorization") != "token t0k":
            self.send_response(500); self.end_headers(); return
        page, limit = int(q["page"][0]), int(q["limit"][0])
        body = json.dumps(PKGS[(page - 1) * limit:page * limit]).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def do_DELETE(self):
        parts = self.path.split("/")  # /api/v1/packages/schnappy/container/<name>/<ver>
        name, ver = unquote(parts[-2]), unquote(parts[-1])
        if state["refuse"] == ver:
            self.send_response(403); self.end_headers(); return
        state["deleted"].append(f"{name}:{ver}"); self.send_response(204); self.end_headers()
srv = ThreadingHTTPServer(("127.0.0.1", 0), H); threading.Thread(target=srv.serve_forever, daemon=True).start()
API = f"http://127.0.0.1:{srv.server_port}/api/v1"
SRC = os.path.join(W, "src")
os.makedirs(os.path.join(SRC, "infra/clusters"), exist_ok=True); os.makedirs(os.path.join(SRC, "platform"), exist_ok=True)
os.makedirs(os.path.join(SRC, "ops"), exist_ok=True)
open(os.path.join(SRC, "infra/clusters/values.yaml"), "w").write(
    "monitor:\n  image:\n    repository: git.pmon.dev/schnappy/masi\n    pullPolicy: IfNotPresent\n    tag: \"m12\"  # masi\n")
open(os.path.join(SRC, "platform/x.yaml"), "w").write("image: git.pmon.dev/schnappy/site:s3\n")
def run(*args, token="t0k", running="echo git.pmon.dev/schnappy/masi:m13; echo git.pmon.dev/schnappy/masi:c07"):
    state["deleted"].clear()
    env = dict(os.environ, PACKAGE_CLEANUP_API=API, PACKAGE_CLEANUP_SRC=SRC, PACKAGE_CLEANUP_RUNNING=running,
               FORGEJO_PACKAGES_TOKEN=token)
    r = subprocess.run([sys.executable, "scripts/package-cleanup.py", *args], capture_output=True, text=True, env=env)
    return r.returncode, r.stdout, sorted(state["deleted"])
rc, out, deleted = run()
check("a plan only: nothing deleted, the counts said", (rc, deleted, [l.split() for l in out.splitlines()[:3]]),
      (0, [], [["masi", "keep", "12", "delete", "2"], ["masi/cache", "keep", "6", "delete", "2"], ["site", "keep", "3", "delete", "0"]]))
rc, out, deleted = run("--apply")
check("--apply: the newest 10 images and 5 caches kept, latest kept, m12 (infra's values) and m13 (running) kept, the cache "
      "version c07 kept for its image's tag in use (running) - the rest deleted, a slash in a name encoded",
      (rc, deleted), (0, ["masi/cache:c05", "masi/cache:c06", "masi:m10", "masi:m11"]))
state["refuse"] = "m11"
rc, out, deleted = run("--apply")
check("a deletion refused: stopped there, said", (rc, "STOPPED: masi:m11" in out, "m10" in " ".join(deleted)), (1, True, True))
state["refuse"] = None
rc, out, deleted = run("--apply", running="exit 3")
check("the cluster's images not read: refused, nothing deleted", (rc, deleted, "REFUSED" in out), (1, [], True))
state["fail_list"] = True
rc, out, deleted = run("--apply")
check("the packages not read: refused, nothing deleted", (rc, deleted, "REFUSED" in out), (1, [], True))
state["fail_list"] = False
rc, out, deleted = run("--apply", token="")
check("no token: refused, nothing read or deleted", (rc, deleted), (1, []))
rc, out, deleted = run("--bogus")
check("an argument it does not know: refused", (rc, deleted), (2, []))
print("package-cleanup: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
