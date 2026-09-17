"""A four-path stand-in for Vault's KV v2 HTTP API, so the REAL vault_kv2_get module
can be driven through 200 / 404 / 403 / 503 without a Vault. Port from argv."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

ANSWERS = {
    "/v1/secret/data/schnappy/keep": (200, {"data": {"data": {"password": "KEEP-REAL"},
                                                     "metadata": {"version": 1, "custom_metadata": None}}}),
    "/v1/secret/data/schnappy/fresh": (404, {"errors": []}),
    "/v1/secret/data/schnappy/forbidden": (403, {"errors": ["1 error occurred:\n\t* permission denied\n\n"]}),
    "/v1/secret/data/schnappy/sealed": (503, {"errors": ["Vault is sealed"]}),
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path.endswith("/auth/token/lookup-self"):
            code, body = 200, {"data": {"policies": ["root"], "ttl": 0}}
        else:
            code, body = ANSWERS.get(self.path, (404, {"errors": ["no route"]}))
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
