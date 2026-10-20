"""A stateful stand-in for Vault's KV v2 HTTP API (mount secret/), so the REAL community.hashi_vault modules read and
write through it: versions kept (a read of ?version=N, the metadata's version list), check-and-set (a write whose cas
is not the current version refused, as Vault refuses it), a missing path answered 404. Only the token in the file named
by argv[2] is accepted.

Test-only routes: GET /_state, POST /_reset {path: {"data": {...}, "version": n, "history": {"n": {...}}}} (no history:
the data is version n alone), POST /_fail {method, path (regex), nth, and: status - the nth matching request answered
with it; or bump - someone else writes the path (someone=else, the version on) right after that read is answered; or
lose - the write applied, its answer a 500 (a reply lost); or drop - the write answered done, not applied}.
Port: bound to a free one, written to the file named by argv[1].
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

KV = {}
FAULTS = []
WRITES = []
TOKEN = open(sys.argv[2]).read().strip()


def meta(e):
    return {"version": e["version"], "created_time": "2026-10-20T00:00:00Z", "deletion_time": "", "destroyed": False,
            "custom_metadata": None}


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
        url = urlparse(self.path)
        path = url.path
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n)) if n else None
        if path == "/_state":
            return self.answer(200, {"kv": KV, "writes": WRITES})
        if path == "/_reset":
            KV, FAULTS, WRITES = {}, [], []
            for k, e in body.items():
                KV[k] = {"data": e["data"], "version": e["version"],
                         "history": e.get("history") or {str(e["version"]): e["data"]}}
            return self.answer(200, {})
        if path == "/_fail":
            FAULTS.append(body)
            return self.answer(200, {})
        if self.headers.get("X-Vault-Token") != TOKEN:
            return self.answer(403, {"errors": ["permission denied"]})
        bump = lose = drop = False
        # every matching fault counts this request first (one firing must not hide it from the next), then they fire
        hit = [f for f in FAULTS if f["method"] == method and re.search(f["path"], path)]
        for f in hit:
            f["seen"] = f.get("seen", 0) + 1
        for f in hit:
            if f["seen"] == f.get("nth", 1):
                if f.get("bump"):
                    bump = True  # someone else writes the path right after this read
                elif f.get("lose"):
                    lose = True  # the write applied, its answer lost
                elif f.get("drop"):
                    drop = True  # the write answered as done, not applied
                else:
                    return self.answer(f["status"], {"errors": [f.get("error", "injected")]})
        if path.endswith("/auth/token/lookup-self"):
            return self.answer(200, {"data": {"policies": ["root"], "ttl": 0}})
        m = re.match(r"^/v1/secret/metadata/(.+)$", path)
        if m and method == "GET":
            e = KV.get(m.group(1))
            if not e:
                return self.answer(404, {"errors": []})
            return self.answer(200, {"data": {"current_version": e["version"], "versions": {
                v: {"created_time": "2026-10-20T00:00:00Z", "deletion_time": "", "destroyed": False}
                for v in e["history"]}}})
        m = re.match(r"^/v1/secret/data/(.+)$", path)
        if not m:
            return self.answer(404, {"errors": []})
        key = m.group(1)
        if method == "GET":
            if key not in KV:
                return self.answer(404, {"errors": []})
            e = KV[key]
            want = parse_qs(url.query).get("version", ["0"])[0]
            if want not in ("0", str(e["version"])):
                if want not in e["history"]:
                    return self.answer(404, {"errors": []})
                return self.answer(200, {"data": {"data": e["history"][want], "metadata": dict(meta(e),
                                                                                              version=int(want))}})
            self.answer(200, {"data": {"data": e["data"], "metadata": meta(e)}})
            if bump:
                v = e["version"] + 1
                e.update(data=dict(e["data"], someone="else"), version=v)
                e["history"][str(v)] = e["data"]
            return None
        if method in ("POST", "PUT"):
            cas = (body.get("options") or {}).get("cas")
            current = KV.get(key, {}).get("version", 0)
            if cas is not None and int(cas) != current:
                return self.answer(400, {"errors": ["check-and-set parameter did not match the current version"]})
            if drop:
                return self.answer(200, {"data": {"version": current + 1}})
            e = KV.setdefault(key, {"history": {}})
            e.update(data=body["data"], version=current + 1)
            e["history"][str(current + 1)] = body["data"]
            WRITES.append({"path": key, "cas": cas})
            if lose:
                return self.answer(500, {"errors": ["the reply lost"]})
            return self.answer(200, {"data": {"version": current + 1, "created_time": "2026-10-20T00:00:00Z",
                                              "deletion_time": "", "destroyed": False}})
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
