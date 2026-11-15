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
SHA = {k: (k * 40)[:40] for k in ("a1", "a2", "b1", "c1", "d1")}  # 40 hex characters each
def pr(n, unit, sha, mergeable=True, user="renovate-bot", fork=False):
    # head.repo filled in by fixture() for its repo (a fork's another's)
    return {"number": n, "head": {"ref": f"renovate/{unit}", "sha": SHA.get(sha, sha), "repo": "FORK" if fork else None},
            "user": {"login": user}, "mergeable": mergeable}
def fixture(prs, states, labels=None):
    fx = {}
    for repo in ("infra", "platform", "ops"):
        for p in prs.get(repo, []):
            p["head"]["repo"] = {"full_name": ("someone/" if p["head"]["repo"] in ("FORK", {"full_name": "someone/" + repo})
                                               else "schnappy/") + repo}
        fx[f"/repos/schnappy/{repo}/pulls"] = prs.get(repo, [])
        fx[f"/repos/schnappy/{repo}/labels"] = (labels or {}).get(repo, [])
    for sha, st in states.items():
        for repo in ("infra", "platform", "ops"):
            fx[f"/repos/schnappy/{repo}/commits/{SHA.get(sha, sha)}/status"] = {"state": st}
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
fixture(UNIT, {})
rc, heads_out = run("wave-patches", "--heads")
check("heads: each of the unit's pull requests, its number and head - nothing written",
      (rc, heads_out.split("\n"), writes()),
      (0, [f"schnappy/infra 1 {SHA['a1']}", f"schnappy/platform 5 {SHA['b1']}", f"schnappy/ops 8 {SHA['c1']}"], []))
PROVEN = os.path.join(W, "proven")
def proven(text=heads_out):
    open(PROVEN, "w").write(text + "\n")
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"})
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: every one green and the proven commit - infra, platform, then ops, each at that commit, its branch deleted",
      (rc, [x[0] for x in writes()], [json.dumps(x[1], sort_keys=True) for x in writes()]),
      (0, ["/repos/schnappy/infra/pulls/1/merge", "/repos/schnappy/platform/pulls/5/merge", "/repos/schnappy/ops/pulls/8/merge"],
       [json.dumps({"Do": "merge", "delete_branch_after_merge": True, "head_commit_id": SHA[k]}, sort_keys=True)
        for k in ("a1", "b1", "c1")]))
fixture({**UNIT, "platform": [pr(5, "wave-patches", "d1")]}, {"a1": "success", "d1": "success", "c1": "success"})
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: one pull request moved since its proof (a push after it) - none merged, named",
      (rc, writes(), "platform#5 moved since its proof" in out), (1, [], True))
fixture({**UNIT, "ops": []}, {"a1": "success", "b1": "success"})
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: the pull requests not the ones proven (one gone, or one new) - none merged",
      (rc, writes(), "not the ones proven" in out), (1, [], True))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"})
for bad in ("", "schnappy/infra 1 nothex", "schnappy/elsewhere 1 " + SHA["a1"], "just words"):
    proven(bad)
    check(f"merge: proven heads that are none ({bad!r}): refused, nothing merged",
          (run("wave-patches", "--merge", "--expect", PROVEN)[0], writes()), (1, []))
check("merge without the proven heads: a usage it lacks (never a merge of whatever is there)",
      (run("wave-patches", "--merge")[0], writes()), (2, []))
fixture(UNIT, {"a1": "success", "b1": "failure", "c1": "success"})
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: one red - none merged, named", (rc, writes(), "platform#5 not green" in out), (1, [], True))
fixture(UNIT, {"a1": "success", "b1": "pending", "c1": "success"})
check("merge: one still running - none merged", (run("wave-patches", "--merge", "--expect", PROVEN)[0], writes()), (1, []))
fixture({**UNIT, "ops": [pr(8, "wave-patches", "c1", mergeable=False)]}, {"a1": "success", "b1": "success", "c1": "success"})
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: one not mergeable - none merged", (rc, writes(), "not mergeable" in out), (1, [], True))
fixture({"infra": [pr(1, "wave-patches", "a1", user="mallory")], "platform": [pr(5, "wave-patches", "b1", fork=True)],
         "ops": [pr(8, "wave-patches", "c1")]}, {"a1": "success", "b1": "success", "c1": "success"})
rc, out = run("wave-patches", "--heads")
check("another account's pull request, or a fork's, named renovate/<unit>: none of the unit's (heads, labels)",
      (rc, out.split("\n"), run("wave-patches", "upgrade-blocked")[0], [x[0] for x in writes()][-1]),
      (0, [f"schnappy/ops 8 {SHA['c1']}"], 0, "/repos/schnappy/ops/issues/8/labels"))
fixture(UNIT, {})
rc, out = run("nope", "--heads")
check("no pull request for the unit: refused", (rc, out.startswith("REFUSED"), writes()), (1, True, []))
check("Forgejo unreachable: refused", run("wave-patches", "veto", url="http://127.0.0.1:1/api/v1")[0], 1)
for args in (("wave-patches",), ("Bad/Unit", "x"), ("wave-patches", "--comment", ""), ("wave-patches", "Bad Label")):
    check(f"usage refused: {args}", run(*args)[0], 2)
print("upgrade-label: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
