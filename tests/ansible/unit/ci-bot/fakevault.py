"""A stateful stand-in for Vault's KV v2 HTTP API (mount secret/), so the REAL community.hashi_vault modules read and
write through it: versions, check-and-set (a write whose cas is not the current version refused, as Vault refuses it),
a missing path answered 404. Only the token in the file named by argv[2] is accepted.

Test-only routes: GET /_state, POST /_reset {path: {"data": {...}, "version": n}}, POST /_fail {method, path (regex),
status, nth} - the nth matching request answered with status; POST /_bump {path} - a write by someone else (the version
moves on, the data stays).
Port: bound to a free one, written to the file named by argv[1].
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse

KV = {}
FAULTS = []
WRITES = []
TOKEN = open(sys.argv[2]).read().strip()


class H(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def answer(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def handle_any(self, method):
        global KV, FAULTS, WRITES
        path = urlparse(self.path).path
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n)) if n else None
        if path == "/_state":
            return self.answer(200, {"kv": KV, "writes": WRITES})
        if path == "/_reset":
            KV, FAULTS, WRITES = body, [], []
            return self.answer(200, {})
        if path == "/_fail":
            FAULTS.append(body)
            return self.answer(200, {})
        if path == "/_bump":
            KV[body["path"]]["version"] += 1
            return self.answer(200, {})
        if self.headers.get("X-Vault-Token") != TOKEN:
            return self.answer(403, {"errors": ["permission denied"]})
        for f in FAULTS:
            if f["method"] == method and re.search(f["path"], path):
                f["seen"] = f.get("seen", 0) + 1
                if f["seen"] == f.get("nth", 1):
                    return self.answer(f["status"], {"errors": [f.get("error", "injected")]})
        if path.endswith("/auth/token/lookup-self"):
            return self.answer(200, {"data": {"policies": ["root"], "ttl": 0}})
        m = re.match(r"^/v1/secret/data/(.+)$", path)
        if not m:
            return self.answer(404, {"errors": []})
        key = m.group(1)
        if method == "GET":
            if key not in KV:
                return self.answer(404, {"errors": []})
            e = KV[key]
            return self.answer(200, {"data": {"data": e["data"], "metadata": {
                "version": e["version"], "created_time": "2026-10-20T00:00:00Z", "deletion_time": "",
                "destroyed": False, "custom_metadata": None}}})
        if method in ("POST", "PUT"):
            cas = (body.get("options") or {}).get("cas")
            current = KV.get(key, {}).get("version", 0)
            if cas is not None and int(cas) != current:
                return self.answer(400, {"errors": ["check-and-set parameter did not match the current version"]})
            KV[key] = {"data": body["data"], "version": current + 1}
            WRITES.append({"path": key, "cas": cas})
            return self.answer(200, {"data": {"version": current + 1}})
        return self.answer(405, {"errors": []})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PUT(self):
        self.handle_any("PUT")


srv = HTTPServer(("127.0.0.1", 0), H)
with open(sys.argv[1], "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
