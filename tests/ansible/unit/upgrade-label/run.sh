#!/bin/bash
# scripts/upgrade-label.py - the upgrade cycle's hands on a unit's pull requests - against a throwaway Forgejo API (a
# local server, a process of its own, recording every write): a label on each pull request (made in a repo where
# missing), the merge - infra, platform, then ops - only when every one is green and mergeable (one
# red, or not mergeable: none merged), its base moved only by CD's app promotions its files untouched (else refused); a
# lost answer read again, unknown is PARTIAL; --green; pause on the dashboard (made under Renovate's title where none is
# open); refused: no pull request for the unit, Forgejo unreachable, a usage it lacks.
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
    def auth(self):
        with open(os.path.join(W, "auth"), "a") as f:
            f.write((self.headers.get("Authorization") or "") + "\n")
    def do_GET(self):
        self.auth()
        fx = json.load(open(os.path.join(W, "fixture.json")))
        u = urllib.parse.urlparse(self.path)
        p = u.path.removeprefix("/api/v1")
        q = urllib.parse.parse_qs(u.query)
        with open(os.path.join(W, "reads"), "a") as f:
            f.write(p + "\n")
        data = fx.get(p)
        if isinstance(data, dict) and "__seq__" in data:  # one answer a read, the last kept
            n_path = os.path.join(W, "seq." + p.replace("/", "_"))
            n = int(open(n_path).read()) if os.path.exists(n_path) else 0
            open(n_path, "w").write(str(n + 1))
            data = data["__seq__"][min(n, len(data["__seq__"]) - 1)]
        if p.endswith(".diff") and isinstance(data, str):  # a pull request's diff: text, as Forgejo serves it
            body = data.encode(); self.send_response(200); self.end_headers(); self.wfile.write(body); return
        if isinstance(data, list) and "page" in q:  # Forgejo's pages, newest first: 50 a page
            limit, page = int(q.get("limit", ["50"])[0]), int(q["page"][0])
            data = data[(page - 1) * limit:page * limit]
        self.answer(data if data is not None else {"message": "not found"}, 200 if data is not None else 404)
    def do_POST(self):
        self.auth()
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"null")
        p = urllib.parse.urlparse(self.path).path.removeprefix("/api/v1")
        fx = json.load(open(os.path.join(W, "fixture.json")))
        query = urllib.parse.urlparse(self.path).query
        with open(os.path.join(W, "writes"), "a") as f:
            f.write(json.dumps([p + (f"?{query}" if query else ""), body]) + "\n")
        if p in fx.get("fail_post", []):  # Forgejo's own no (409: not mergeable, head moved), or a 5xx (fail_code)
            self.answer({"message": "merge failed"}, fx.get("fail_code", 409)); return
        if p in fx.get("drop_post", []):  # the answer lost: the connection closed with none (Forgejo restarting)
            self.close_connection = True; return
        if p == "/repos/schnappy/ops/issues":
            self.answer({"number": 42}); return
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
import json, os, re, subprocess, sys, time
W, PORT = os.environ["W"], os.environ["PORT"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
SHA = {k: (k * 40)[:40] for k in ("a1", "a2", "b1", "c1", "d1")}  # 40 hex characters each
# ops' merge message as the script holds it (read, not restated: the check is that it is sent, and Woodpecker's marker)
import ast  # noqa: E402
OPS_SKIP = next(ast.literal_eval(n.value) for n in ast.parse(open("scripts/upgrade-label.py").read()).body
                if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "OPS_MERGE_MESSAGE")
def pr(n, unit, sha, mergeable=True, user="renovate-bot", fork=False):
    # head.repo filled in by fixture() for its repo (a fork's another's)
    return {"number": n, "head": {"ref": f"renovate/{unit}", "sha": SHA.get(sha, sha), "repo": "FORK" if fork else None},
            "user": {"login": user}, "mergeable": mergeable}
BASE = "e" * 40
def write_fixture(fx):
    """the fake Forgejo's answers, replaced whole (a rename): the server reads the file at every request, and one read
    while it was rewritten in place (open "w" empties it first) met half a file - the connection dropped, the script's
    green wait refused, ops#46's CI red (2026-11-17)"""
    tmp = os.path.join(W, "fixture.json.tmp")
    with open(tmp, "w") as f:
        json.dump(fx, f)
    os.replace(tmp, os.path.join(W, "fixture.json"))


def status(st):
    """Forgejo's combined status: Renovate's stability-days beside Woodpecker's context; "" - nothing reported;
    "stability-only" - Renovate's status alone (its state success), as for a head whose pipeline never started."""
    days = {"context": "renovate/stability-days", "status": "success"}
    if st == "":
        return {"state": "", "statuses": []}
    if st == "stability-only":
        return {"state": "success", "statuses": [days]}
    return {"state": st, "statuses": [days, {"context": "ci/woodpecker/pr/ci", "status": st}]}
def fixture(prs, states, labels=None, base=None, fail_post=(), merged=None, issues=None, drop_post=(), extra=None, fail_code=409):
    fx = {"fail_post": list(fail_post), "drop_post": list(drop_post), "fail_code": fail_code}
    for repo in ("infra", "platform", "ops"):
        fx[f"/repos/schnappy/{repo}/branches/main"] = {"commit": {"id": (base or {}).get(repo, BASE)}}
        for p in prs.get(repo, []):
            p.setdefault("base", {"ref": "main"})
            fx[f"/repos/schnappy/{repo}/pulls/{p['number']}"] = {"merged": (merged or {}).get(f"schnappy/{repo}#{p['number']}", False)}
    if issues is not None:
        fx["/repos/schnappy/ops/issues"] = issues
    for repo in ("infra", "platform", "ops"):
        for p in prs.get(repo, []):
            p["head"]["repo"] = {"full_name": ("someone/" if p["head"]["repo"] in ("FORK", {"full_name": "someone/" + repo})
                                               else "schnappy/") + repo}
        fx[f"/repos/schnappy/{repo}/pulls"] = prs.get(repo, [])
        fx[f"/repos/schnappy/{repo}/labels"] = (labels or {}).get(repo, [])
    for sha, st in states.items():
        for repo in ("infra", "platform", "ops"):
            fx[f"/repos/schnappy/{repo}/commits/{SHA.get(sha, sha)}/status"] = status(st)
    fx.update(extra or {})
    write_fixture(fx)
    for f in ("writes", "auth", "reads"):
        if os.path.exists(os.path.join(W, f)):
            os.remove(os.path.join(W, f))
def writes():
    p = os.path.join(W, "writes")
    return [json.loads(x) for x in open(p)] if os.path.exists(p) else []
def run(*args, url=None, env_extra=None):
    env = {**os.environ, "UPGRADE_FORGEJO_URL": url or f"http://127.0.0.1:{PORT}/api/v1", "UPGRADE_FORGEJO_TOKEN": "t",
           "UPGRADE_MERGE_READS": "3", "UPGRADE_MERGE_WAIT": "0.05", **(env_extra or {})}
    r = subprocess.run([sys.executable, "scripts/upgrade-label.py", *args], capture_output=True, text=True, env=env, timeout=60)
    return r.returncode, r.stdout.strip()
UNIT = {"infra": [pr(1, "wave-patches", "a1"), pr(2, "istio", "a2")], "platform": [pr(5, "wave-patches", "b1")],
        "ops": [pr(8, "wave-patches", "c1")]}
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"},
        labels={"infra": [{"name": "stop-updating", "id": 3}], "platform": [], "ops": []})
rc, out = run("wave-patches", "stop-updating")
w = writes()
check("label: on each of the unit's pull requests (not istio's), the repo's own id; made where missing",
      (rc, [x[0] for x in w], [x[1] for x in w]),
      (0, ["/repos/schnappy/infra/issues/1/labels", "/repos/schnappy/platform/labels", "/repos/schnappy/platform/issues/5/labels",
           "/repos/schnappy/ops/labels", "/repos/schnappy/ops/issues/8/labels"],
       [{"labels": [3]}, {"name": "stop-updating", "color": "#d93f0b"}, {"labels": [77]},
        {"name": "stop-updating", "color": "#d93f0b"}, {"labels": [77]}]))
fixture(UNIT, {})
rc, heads_out = run("wave-patches", "--heads")
check("heads: each of the unit's pull requests, its number, its head and its base branch's commit - nothing written; "
      "every request with the bot's token",
      (rc, heads_out.split("\n"), writes(), set(open(os.path.join(W, "auth")).read().split("\n")) - {""}),
      (0, [f"schnappy/infra 1 {SHA['a1']} {BASE}", f"schnappy/platform 5 {SHA['b1']} {BASE}", f"schnappy/ops 8 {SHA['c1']} {BASE}"],
       [], {"token t"}))
PROVEN = os.path.join(W, "proven")
def proven(text=heads_out):
    open(PROVEN, "w").write(text + "\n")
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"})
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: every one green and the proven commit - infra, platform, then ops, each at that commit, its branch deleted;"
      " ops' merge commit [CI SKIP] (its record's commit judged), infra's and platform's never (their pipelines deploy)",
      (rc, [x[0] for x in writes()], [json.dumps(x[1], sort_keys=True) for x in writes()]),
      (0, ["/repos/schnappy/infra/pulls/1/merge", "/repos/schnappy/platform/pulls/5/merge", "/repos/schnappy/ops/pulls/8/merge"],
       [json.dumps(dict({"Do": "merge", "delete_branch_after_merge": True, "head_commit_id": SHA[k]},
                        **({"MergeMessageField": OPS_SKIP} if k == "c1" else {})), sort_keys=True)
        for k in ("a1", "b1", "c1")]))
check("merge: ops' skip is Woodpecker's own marker, at the message's start", OPS_SKIP.startswith("[CI SKIP] "), True)
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
for bad in ("", f"schnappy/infra 1 nothex {BASE}", f"schnappy/infra 1 {SHA['a1']} nothex", f"schnappy/infra 1 {SHA['a1']}",
            f"schnappy/elsewhere 1 {SHA['a1']} {BASE}", "just words"):
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
      (rc, out.split("\n"), run("wave-patches", "stop-updating")[0], [x[0] for x in writes()][-1]),
      (0, [f"schnappy/ops 8 {SHA['c1']} {BASE}"], 0, "/repos/schnappy/ops/issues/8/labels"))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, base={"platform": "f" * 40})
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: a base branch moved since the proof (a merge onto a main nobody proved) - none merged, named",
      (rc, writes(), "platform's main moved since the proof" in out), (1, [], True))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/platform/pulls/5/merge"])
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: platform's failing after infra's went in - PARTIAL (exit 3), what went in named, ops not tried",
      (rc, out.split("\n")[0], "PARTIAL: merged schnappy/infra#1; schnappy/platform#5 not" in out,
       [x[0] for x in writes()]),
      (3, "MERGED schnappy/infra#1", True, ["/repos/schnappy/infra/pulls/1/merge", "/repos/schnappy/platform/pulls/5/merge"]))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/infra/pulls/1/merge"])
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: the first refused by Forgejo (409), not merged (read again) - nothing in: refused (exit 1), nothing after it tried",
      (rc, out.startswith("REFUSED"), [x[0] for x in writes()]), (1, True, ["/repos/schnappy/infra/pulls/1/merge"]))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/infra/pulls/1/merge"], fail_code=502)
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: the first answered 502 (Caddy, Forgejo slow) and not merged when read again and again - not known: PARTIAL "
      "(exit 3), never 'nothing merged'", (rc, "not known" in out), (3, True))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/infra/pulls/1/merge"], fail_code=500,
        extra={f"/repos/schnappy/infra/compare/main...{SHA['a1']}": {"total_commits": 0, "commits": []}})
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: a 500 after the merge commit went in (the pull request not yet marked; its head on main) - merged, the rest "
      "merged (exit 0)", (rc, "MERGED schnappy/infra#1 (its answer lost" in out, len(writes())), (0, True, 3))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/infra/pulls/1/merge"],
        merged={"schnappy/infra#1": True})
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: an answer lost that did merge (read again: merged) - counted, the rest merged (exit 0)",
      (rc, "MERGED schnappy/infra#1 (its answer lost" in out, len(writes())), (0, True, 3))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/infra/pulls/1/merge"],
        extra={"/repos/schnappy/infra/pulls/1": None})
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: the first refused, its state then not read - not known: PARTIAL (exit 3), never 'nothing merged'",
      (rc, "PARTIAL: merged nothing known; schnappy/infra#1 not known" in out), (3, True))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/platform/pulls/5/merge"],
        extra={"/repos/schnappy/platform/pulls/5": None})
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: the second refused after the first went in, its state not read - PARTIAL (exit 3), the first named",
      (rc, "PARTIAL: merged schnappy/infra#1; schnappy/platform#5 not known" in out), (3, True))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, drop_post=["/repos/schnappy/infra/pulls/1/merge"])
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: the first's answer lost (no HTTP answer), not merged when read again and again - not known: PARTIAL "
      "(exit 3), read 3 times", (rc, "not known" in out, open(os.path.join(W, "reads")).read().split().count("/repos/schnappy/infra/pulls/1")),
      (3, True, 3))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, drop_post=["/repos/schnappy/infra/pulls/1/merge"],
        merged={"schnappy/infra#1": True})
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: an answer lost that did merge - counted, the rest merged (exit 0)",
      (rc, "MERGED schnappy/infra#1 (its answer lost" in out, len(writes())), (0, True, 3))
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"}, fail_post=["/repos/schnappy/infra/pulls/1/merge"],
        extra={"/repos/schnappy/infra/pulls/1": [1]})
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: an error of any other kind once a merge was asked for (an answer of the wrong shape) - PARTIAL (exit 3)",
      (rc, out.startswith("PARTIAL")), (3, True))
# infra's main moved since the proof: by CD's app promotions alone (scripts/cd-promotions.json), the unit touching none
# of their files - merged (the proven tree plus app tags); anything else - refused
CDF = ["clusters/production/schnappy-production-apps/values.yaml", "clusters/production/schnappy-test-apps/values.yaml"]
NEW = "9" * 40
def cdc(email="woodpecker@pmon.dev", files=(CDF[0],)):
    return {"commit": {"author": {"email": email}}, "files": [{"filename": f} for f in files]}
def moved(commits, unit_files=("clusters/production/cert-manager/values.yaml",), behind=0, total=None):
    return {f"/repos/schnappy/infra/compare/{NEW}...{BASE}": {"total_commits": behind, "commits": []},
            f"/repos/schnappy/infra/compare/{BASE}...{NEW}": {"total_commits": len(commits) if total is None else total,
                                                              "commits": commits},
            "/repos/schnappy/infra/pulls/1/files": [{"filename": f} for f in unit_files]}
GREEN = {"a1": "success", "b1": "success", "c1": "success"}
fixture(UNIT, GREEN, base={"infra": NEW}, extra=moved([cdc(), cdc(files=CDF)]))
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: infra's main moved by CD's promotions alone, their files untouched by the unit - merged, said",
      (rc, "BASE schnappy/infra: moved since the proof by CD's app promotions alone" in out, len(writes())), (0, True, 3))
fixture(UNIT, GREEN, base={"infra": NEW}, extra=moved([cdc()], unit_files=(CDF[1],)))
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("  the unit changing another line of CD's file (k6's image beside the app tags): merged - Forgejo's mergeable judges "
      "whether the two meet", (rc, len(writes())), (0, 3))
for why, extra in (("a CD commit touching another file", moved([cdc(), cdc(files=("clusters/production/istio/values.yaml",))])),
                   ("a commit by another author", moved([cdc(), cdc(email="someone@pmon.dev")])),
                   ("the proven base no longer on main (a force push)", moved([cdc()], behind=1)),
                   ("a list of commits cut short", moved([cdc()], total=300)),
                   ("a commit with no files (a merge)", moved([cdc(files=())]))):
    fixture(UNIT, GREEN, base={"infra": NEW}, extra=extra)
    rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
    check(f"  {why}: none merged, named", (rc, writes(), "infra's main moved since the proof" in out), (1, [], True))
fixture({**UNIT, "ops": [pr(8, "wave-patches", "c1")]}, GREEN, base={"ops": NEW},
        extra={f"/repos/schnappy/ops/compare/{NEW}...{BASE}": {"total_commits": 0, "commits": []},
               f"/repos/schnappy/ops/compare/{BASE}...{NEW}": {"total_commits": 1, "commits": [cdc()]}})
check("  ops (no CD files of its own) moved by such a commit: none merged", run("wave-patches", "--merge", "--expect", PROVEN)[0], 1)
fixture(UNIT, {"a1": "success", "b1": "success", "c1": "success"})
rc, out = run("wave-patches", "--green")
check("green: every head's CI success - exit 0, each said", (rc, out.split("\n")),
      (0, ["schnappy/infra#1 success", "schnappy/platform#5 success", "schnappy/ops#8 success"]))
fixture(UNIT, {"a1": "success", "b1": "pending", "c1": "failure"})
rc, out = run("wave-patches", "--green")
check("green: one running, one red - red (exit 4: the unit breaks its own checks), the red one named", (rc, out.split("\n")[-1]),
      (4, "RED: red: schnappy/ops#8"))
fixture(UNIT, {"a1": "success", "b1": "pending", "c1": "success"})
rc, out = run("wave-patches", "--green")
check("green: one still running, no wait asked - not green yet (exit 1), named", (rc, out.split("\n")[-1]),
      (1, "REFUSED: not green yet: schnappy/platform#5"))
import threading  # noqa: E402
fixture(UNIT, {"a1": "success", "b1": "pending", "c1": "success"})
def flip():
    time.sleep(0.6)
    fx = json.load(open(os.path.join(W, "fixture.json")))
    fx[f"/repos/schnappy/platform/commits/{SHA['b1']}/status"] = status("success")
    write_fixture(fx)
t = threading.Thread(target=flip); t.start()
env = {**os.environ, "UPGRADE_FORGEJO_URL": f"http://127.0.0.1:{PORT}/api/v1", "UPGRADE_FORGEJO_TOKEN": "t", "UPGRADE_GREEN_POLL": "0.1"}
r = subprocess.run([sys.executable, "scripts/upgrade-label.py", "wave-patches", "--green", "60"], capture_output=True, text=True, env=env, timeout=60)
t.join()
check("green with a wait: the running one waited for until it is green - exit 0", (r.returncode, r.stdout.strip().split("\n")[-1]),
      (0, "schnappy/ops#8 success"))
# the console's progress through the wait (operator 2026-11-22: a silent hour read as a hang): the heads' states said when
# they change - once while the same, its time first; the verdict as before
waited = [l for l in r.stdout.splitlines() if " waiting for CI: " in l]
check("  while it waits: one line (the states unchanged), its time first, every head's state",
      [re.sub(r"^\d\d:\d\d:\d\d ", "", l) for l in waited],
      ["waiting for CI: schnappy/infra#1 success, schnappy/platform#5 pending, schnappy/ops#8 success"])
fixture(UNIT, {"a1": "success", "b1": "pending", "c1": "success"})
r = subprocess.run([sys.executable, "scripts/upgrade-label.py", "wave-patches", "--green", "1"], capture_output=True, text=True,
                   env={**env, "UPGRADE_GREEN_POLL": "0.2"}, timeout=60)
check("  still running at the wait's end: not green yet (exit 1)", (r.returncode, "not green yet" in r.stdout), (1, True))
fixture(UNIT, {"a1": "success", "b1": "error", "c1": "success"})
check("green: a CI that errored (no build ran) is red too (exit 4)", run("wave-patches", "--green")[0], 4)
fixture(UNIT, {"a1": "success", "b1": "", "c1": "pending"})
rc, out = run("wave-patches", "--green")
check("green: a head no CI ever reported on (Forgejo's state \"\") at the wait's end: no CI (exit 5 - no pipeline started), named "
      "- never 'running'", (rc, out.split("\n")[-1]), (5, "NO CI: no CI on: schnappy/platform#5"))
fixture(UNIT, {"a1": "success", "b1": "stability-only", "c1": "success"})
rc, out = run("wave-patches", "--green")
check("green: a head \"success\" by Renovate's stability-days alone - its pipeline never started (2026-11-19) - no CI "
      "(exit 5), named: never green", (rc, out.split("\n")[-1]), (5, "NO CI: no CI on: schnappy/platform#5"))
fixture(UNIT, {"a1": "success", "b1": "stability-only", "c1": "success"})
proven()
rc, out = run("wave-patches", "--merge", "--expect", PROVEN)
check("merge: a head \"success\" by stability-days alone - not green, none merged, named",
      (rc, writes(), "platform#5 not green (its CI: none)" in out), (1, [], True))
fixture(UNIT, {})
rc, out = run("wave-patches", "--update")
check("update: a pull request whose compare is not read: refused (exit 1), nothing updated", (rc, writes()), (1, []))
many = {"infra": [pr(i, f"other-{i:03d}", "a2") for i in range(1, 61)] + [pr(99, "wave-patches", "a1")]}
fixture(many, {})
check("heads: more than one page of pull requests - the unit's on the second page found",
      run("wave-patches", "--heads"), (0, f"schnappy/infra 99 {SHA['a1']} {BASE}"))
TITLE = json.load(open("renovate/upgrade-cycle.json"))["dependencyDashboardTitle"]
OTHER = {"number": 2, "title": "an issue of its own", "labels": [], "user": {"login": "renovate-bot"}}
IMPOSTER = {"number": 1, "title": TITLE, "labels": [], "user": {"login": "mallory"}}
DASH = [IMPOSTER, OTHER, {"number": 3, "title": TITLE, "labels": [], "user": {"login": "renovate-bot"}}]
fixture({}, {}, labels={"ops": []}, issues=DASH)
rc, out = run("--pause", "a one-way failure: kubernetes-1.37 - see the mail")
check("pause: the dashboard issue (its title exactly, the bot's - behind another account's issue under the same title "
      "and another open issue) labelled upgrades-paused (the label made where missing), the reason its comment",
      (rc, [x[0] for x in writes()], writes()[-1][1]["body"] if writes() else None),
      (0, ["/repos/schnappy/ops/labels", "/repos/schnappy/ops/issues/3/labels", "/repos/schnappy/ops/issues/3/comments"],
       "a one-way failure: kubernetes-1.37 - see the mail"))
fixture({}, {}, labels={"ops": [{"name": "upgrades-paused", "id": 9}]}, issues=DASH)
rc, out = run("--pause", "x")
check("pause, the label there already: no label made, its own id used", (rc, [x for x in writes() if x[0].endswith("/3/labels")],
      [x[0] for x in writes() if x[0] == "/repos/schnappy/ops/labels"]), (0, [["/repos/schnappy/ops/issues/3/labels", {"labels": [9]}]], []))
fixture({}, {}, labels={"ops": [{"name": "upgrades-paused", "id": 9}]}, issues=[OTHER])
rc, out = run("--pause", "the reason")
w = writes()
check("pause without a dashboard issue open: one made under Renovate's own title (the preset's), labelled, the reason "
      "its body and comment - the kill switch never missing when pulled",
      (rc, [x[0] for x in w], w[0][1] if w else None, "MADE schnappy/ops#42" in out),
      (0, ["/repos/schnappy/ops/issues", "/repos/schnappy/ops/issues/42/comments"],
       {"title": TITLE, "body": "the reason", "labels": [9]}, True))
fixture(UNIT, {})
rc, out = run("nope", "--heads")
check("no pull request for the unit: refused", (rc, out.startswith("REFUSED"), writes()), (1, True, []))
check("Forgejo unreachable: refused", run("wave-patches", "agent-fixed", url="http://127.0.0.1:1/api/v1")[0], 1)
for args in (("wave-patches",), ("Bad/Unit", "x"), ("wave-patches", "--comment", "x"), ("wave-patches", "Bad Label")):
    check(f"usage refused: {args}", (run(*args)[0], writes()), (2, []))  # --comment: the veto notice's, gone 2026-11-21
# a main commit's CI after a merge that restarted CI's own database (upgrade-cycle.sh): green 0, red 1, none or not
# finished in the wait 3 - only a ci/ context counts (Renovate's status alone is no CI)
M = "9" * 40
outs = []
for st, want in (("success", 0), ("failure", 1), ("error", 1), ("pending", 3), ("", 3), ("stability-only", 3)):
    fixture(UNIT, {M: st})
    rc, out = run("--main-ci", "schnappy/infra", M, "0")
    outs.append((st, rc == want, out.split(" ")[0]))
check("--main-ci: green 0, red 1, pending or no CI (Renovate's status alone) 3 - each said", outs,
      [("success", True, "GREEN"), ("failure", True, "RED"), ("error", True, "RED"), ("pending", True, "NOT"), ("", True, "NOT"),
       ("stability-only", True, "NOT")])
check("  its arguments: a schnappy repo, a whole commit, minutes - else usage",
      [run(*a_)[0] for a_ in (("--main-ci", "other/infra", M, "0"), ("--main-ci", "schnappy/infra", "abc", "0"), ("--main-ci", "schnappy/infra", M, "x"))],
      [2, 2, 2])
# a merged pull request's own merge commit (main's head may be a CD commit since); a pipeline canceled for a later push
# followed to main's head; a read failing waited through to the end - never a red, never a traceback
N = "8" * 40
def ci(st, desc=""):
    return {"state": st, "statuses": [{"context": "ci/woodpecker/push/ci", "status": st, "description": desc}]}
def pr_merged(merged=True, sha=M):  # a merge commit named either way: "merged" is what decides
    return {"/repos/schnappy/infra/pulls/4": {"merged": merged, "merge_commit_sha": sha}}
fixture(UNIT, {}, extra={**pr_merged(), f"/repos/schnappy/infra/commits/{M}/status": ci("success")})
rc, out = run("--main-ci", "schnappy/infra#4", "0")
reads = open(os.path.join(W, "reads")).read().split()
check("--main-ci REPO#PR: the pull request's merge commit read, its CI judged", (rc, out, "/repos/schnappy/infra/pulls/4" in reads),
      (0, f"GREEN schnappy/infra {M}", True))
fixture(UNIT, {}, extra={**pr_merged(False), f"/repos/schnappy/infra/commits/{M}/status": ci("success")})
check("  a pull request not merged: not judged (3), said", run("--main-ci", "schnappy/infra#4", "0")[:2], (3, "NOT MERGED schnappy/infra#4: no merge commit"))
CANCELED = ci("failure", "Pipeline was canceled")
fixture(UNIT, {}, base={"infra": N}, extra={**pr_merged(), f"/repos/schnappy/infra/commits/{M}/status": CANCELED,
                                            f"/repos/schnappy/infra/commits/{N}/status": ci("success")})
rc, out = run("--main-ci", "schnappy/infra#4", "1", env_extra={"UPGRADE_GREEN_POLL": "0.05"})
check("  its pipeline canceled for a later push: main's head followed - green there, green", (rc, out.splitlines()[0].split(" ")[0], out.splitlines()[-1]),
      (0, "CANCELED", f"GREEN schnappy/infra {N}"))
fixture(UNIT, {}, base={"infra": M}, extra={**pr_merged(), f"/repos/schnappy/infra/commits/{M}/status": CANCELED})
check("  canceled with nothing later on main (canceled by hand): red", run("--main-ci", "schnappy/infra#4", "1", env_extra={"UPGRADE_GREEN_POLL": "0.05"})[0], 1)
fixture(UNIT, {}, extra={**pr_merged(), f"/repos/schnappy/infra/commits/{M}/status": ci("failure", "Pipeline failed")})
check("  red for its own reason: red, the reason said", run("--main-ci", "schnappy/infra#4", "0"), (1, f"RED schnappy/infra {M}: failure (Pipeline failed)"))
fixture(UNIT, {}, extra=pr_merged())
rc, out = run("--main-ci", "schnappy/infra#4", "0")
check("  a read failing (Forgejo's 404/5xx): waited through to the end - not finished (3), the failure said, no traceback",
      (rc, out.startswith(f"NOT FINISHED schnappy/infra {M}") and "the last read failed" in out, "Traceback" in out), (3, True, False))
# polling: pending three reads 0.6 s apart, then green - within a minute's wait green (one read, or a bound read as
# seconds, gives not finished)
for f in os.listdir(W):
    if f.startswith("seq."):
        os.remove(os.path.join(W, f))
fixture(UNIT, {}, extra={**pr_merged(), f"/repos/schnappy/infra/commits/{M}/status": {"__seq__": [ci("pending")] * 3 + [ci("success")]}})
rc, out = run("--main-ci", "schnappy/infra#4", "1", env_extra={"UPGRADE_GREEN_POLL": "0.6"})
reads = open(os.path.join(W, "reads")).read().split()
check("  pending, then green within the wait: polled until green", (rc, out, reads.count(f"/repos/schnappy/infra/commits/{M}/status")),
      (0, f"GREEN schnappy/infra {M}", 4))
check("  REPO#PR's arguments: a schnappy repo, a number, minutes - else usage",
      [run(*a_)[0] for a_ in (("--main-ci", "other/infra#4", "0"), ("--main-ci", "schnappy/infra#x", "0"), ("--main-ci", "schnappy/infra#4", "x"))],
      [2, 2, 2])
print("upgrade-label: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
