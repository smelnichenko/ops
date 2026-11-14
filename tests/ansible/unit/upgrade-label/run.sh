#!/bin/bash
# scripts/upgrade-label.py - the upgrade cycle's hands on a unit's pull requests - against a throwaway Forgejo API (a
# local server, a process of its own, recording every write): a label on each pull request (made in a repo where
# missing), a comment on each, the merge - infra, platform, then ops - only when every one is green and mergeable (one
# red, or not mergeable: none merged); refused: no pull request for the unit, Forgejo unreachable, a usage it lacks.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'kill "$(cat "$W/pid" 2> /dev/null)" 2> /dev/null; rm -rf "$W"' EXIT
cat > "$W/server.py" <<'SERVER'
import http.server, json, os, sys, urllib.parse
W = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def answer(self, data, code=200):
        body = json.dumps(data).encode(); self.send_response(code); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        fx = json.load(open(os.path.join(W, "fixture.json")))
        p = urllib.parse.urlparse(self.path).path.removeprefix("/api/v1")
        data = fx.get(p)
        self.answer(data if data is not None else {"message": "not found"}, 200 if data is not None else 404)
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"null")
        p = urllib.parse.urlparse(self.path).path.removeprefix("/api/v1")
        with open(os.path.join(W, "writes"), "a") as f:
            f.write(json.dumps([p, body]) + "\n")
        self.answer({"id": 77} if p.endswith("/labels") and "labels" not in (body or {}) else {})
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port.tmp"), "w").write(str(s.server_port)); os.rename(os.path.join(W, "port.tmp"), os.path.join(W, "port"))
s.serve_forever()
SERVER
python3 "$W/server.py" "$W" & echo $! > "$W/pid"
for _ in $(seq 50); do [ -e "$W/port" ] && break; sleep 0.1; done
[ -e "$W/port" ] || { echo "upgrade-label: the local server did not start"; exit 1; }
W=$W PORT=$(cat "$W/port") python3 - <<'PYCHECK'
import json, os, subprocess, sys
W, PORT = os.environ["W"], os.environ["PORT"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def pr(n, unit, sha, mergeable=True):
    return {"number": n, "head": {"ref": f"renovate/{unit}", "sha": sha}, "mergeable": mergeable}
def fixture(prs, states, labels=None):
    fx = {}
    for repo in ("infra", "platform", "ops"):
        fx[f"/repos/schnappy/{repo}/pulls"] = prs.get(repo, [])
        fx[f"/repos/schnappy/{repo}/labels"] = (labels or {}).get(repo, [])
    for sha, st in states.items():
        for repo in ("infra", "platform", "ops"):
            fx[f"/repos/schnappy/{repo}/commits/{sha}/status"] = {"state": st}
    json.dump(fx, open(os.path.join(W, "fixture.json"), "w"))
    if os.path.exists(os.path.join(W, "writes")):
        os.remove(os.path.join(W, "writes"))
def writes():
    p = os.path.join(W, "writes")
    return [json.loads(x) for x in open(p)] if os.path.exists(p) else []
def run(*args, url=None):
    env = {**os.environ, "UPGRADE_FORGEJO_URL": url or f"http://127.0.0.1:{PORT}/api/v1", "UPGRADE_FORGEJO_TOKEN": "t"}
    r = subprocess.run([sys.executable, "scripts/upgrade-label.py", *args], capture_output=True, text=True, env=env, timeout=60)
    return r.returncode, r.stdout.strip()
UNIT = {"infra": [pr(1, "wave-patches", "a1"), pr(2, "istio", "a2")], "platform": [pr(5, "wave-patches", "b1")],
        "ops": [pr(8, "wave-patches", "c1")]}
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"},
        labels={"infra": [{"name": "upgrade-blocked", "id": 3}], "platform": [], "ops": []})
rc, out = run("wave-patches", "upgrade-blocked")
w = writes()
check("label: on each of the unit's pull requests (not istio's), the repo's own id; made where missing",
      (rc, [x[0] for x in w], [x[1] for x in w]),
      (0, ["/repos/schnappy/infra/issues/1/labels", "/repos/schnappy/platform/labels", "/repos/schnappy/platform/issues/5/labels",
           "/repos/schnappy/ops/labels", "/repos/schnappy/ops/issues/8/labels"],
       [{"labels": [3]}, {"name": "upgrade-blocked", "color": "#d93f0b"}, {"labels": [77]},
        {"name": "upgrade-blocked", "color": "#d93f0b"}, {"labels": [77]}]))
fixture(UNIT, {})
rc, out = run("wave-patches", "--comment", "UPGRADE NOTICE 2026-11-20T03:00:00Z - applies after 24 h")
check("comment: on each, the text whole", (rc, [(x[0], x[1]["body"][:14]) for x in writes()]),
      (0, [(f"/repos/schnappy/{r}/issues/{n}/comments", "UPGRADE NOTICE") for r, n in (("infra", 1), ("platform", 5), ("ops", 8))]))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"})
rc, out = run("wave-patches", "--merge")
check("merge: every one green - infra, platform, then ops, each branch deleted",
      (rc, [x[0] for x in writes()], {json.dumps(x[1], sort_keys=True) for x in writes()}),
      (0, ["/repos/schnappy/infra/pulls/1/merge", "/repos/schnappy/platform/pulls/5/merge", "/repos/schnappy/ops/pulls/8/merge"],
       {json.dumps({"Do": "merge", "delete_branch_after_merge": True}, sort_keys=True)}))
fixture(UNIT, {"a1": "success", "b1": "failure", "c1": "success"})
rc, out = run("wave-patches", "--merge")
check("merge: one red - none merged, named", (rc, writes(), "platform#5 not green" in out), (1, [], True))
fixture(UNIT, {"a1": "success", "b1": "pending", "c1": "success"})
check("merge: one still running - none merged", (run("wave-patches", "--merge")[0], writes()), (1, []))
fixture({**UNIT, "ops": [pr(8, "wave-patches", "c1", mergeable=False)]}, {"a1": "success", "b1": "success", "c1": "success"})
rc, out = run("wave-patches", "--merge")
check("merge: one not mergeable - none merged", (rc, writes(), "not mergeable" in out), (1, [], True))
fixture(UNIT, {})
rc, out = run("nope", "--merge")
check("no pull request for the unit: refused", (rc, out.startswith("REFUSED"), writes()), (1, True, []))
check("Forgejo unreachable: refused", run("wave-patches", "veto", url="http://127.0.0.1:1/api/v1")[0], 1)
for args in (("wave-patches",), ("Bad/Unit", "x"), ("wave-patches", "--comment", ""), ("wave-patches", "Bad Label")):
    check(f"usage refused: {args}", run(*args)[0], 2)
print("upgrade-label: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
