#!/bin/bash
# scripts/upgrade-apps-merge.py - the app repos' Renovate PRs driven to merged - against a throwaway Forgejo API (a local
# server recording every write): a green (ci/ context), mergeable PR of the bot's merged at the head read; red, pending,
# no ci/ context at all (Renovate's stability status alone), another account's or a fork's: never merged; a green one
# Forgejo cannot merge updated onto main, on a conflict (409) handed to the restack - a refused restack reported once,
# not pending; held while the upgrade run is between its review and its merge (its log: no END, the review started, no
# MERGED after); masi's merges spaced; the bot's token sent, none: refused before any request; done when nothing pends.
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
    def note(self, name, line):
        with open(os.path.join(W, name), "a") as f:
            f.write(line + "\n")
    def do_GET(self):
        self.note("auth", self.headers.get("Authorization") or "")
        fx = json.load(open(os.path.join(W, "fixture.json")))
        p = urllib.parse.urlparse(self.path).path.removeprefix("/api/v1")
        data = fx.get(p)
        self.answer(data if data is not None else {"message": "not found"}, 200 if data is not None else 404)
    def do_POST(self):
        self.note("auth", self.headers.get("Authorization") or "")
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"null")
        u = urllib.parse.urlparse(self.path)
        p = u.path.removeprefix("/api/v1") + (f"?{u.query}" if u.query else "")
        self.note("writes", json.dumps([p, body]))
        fx = json.load(open(os.path.join(W, "fixture.json")))
        code = fx.get("fail_post", {}).get(p)
        self.answer({"message": "no"} if code else {}, code or 200)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port.tmp"), "w").write(str(s.server_port)); os.rename(os.path.join(W, "port.tmp"), os.path.join(W, "port"))
s.serve_forever()
SERVER
python3 "$W/server.py" "$W" & echo $! > "$W/pid"
for _ in $(seq 50); do [ -e "$W/port" ] && break; sleep 0.1; done
[ -e "$W/port" ] || { echo "upgrade-apps-merge: the local server did not start"; exit 1; }
W=$W PORT=$(cat "$W/port") python3 - <<'PYCHECK'
import json, os, subprocess, sys
W, PORT = os.environ["W"], os.environ["PORT"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
# the restack stand-in: says what it was asked and answers as told (RESTACK_RC)
STUB = os.path.join(W, "restack.py")
open(STUB, "w").write("import os, sys\nopen(os.path.join(%r, 'restacked'), 'a').write(' '.join(sys.argv[1:]) + '\\n')\n"
                      "print('REFUSED: the replaced line is not on main' if os.environ.get('RESTACK_RC') == '1' else 'RESTACKED')\n"
                      "sys.exit(int(os.environ.get('RESTACK_RC', '0')))\n" % W)
LOGS = os.path.join(W, "runlogs")
os.makedirs(LOGS)
def pr(repo, n, ci="success", mergeable=True, user="renovate-bot", fork=False, title=None):
    return {"repo": repo, "number": n, "ci": ci, "mergeable": mergeable, "user": user, "fork": fork,
            "title": title or f"update {repo} {n}", "sha": f"{n:040d}"}
def fixture(prs, fail_post=None):
    fx = {"fail_post": fail_post or {}}
    for repo in {p["repo"] for p in prs} | {"admin", "masi"}:
        fx[f"/repos/schnappy/{repo}/pulls"] = []
    for p in prs:
        head = {"ref": f"renovate/x{p['number']}", "sha": p["sha"],
                "repo": {"full_name": ("someone/" if p["fork"] else "schnappy/") + p["repo"]}}
        entry = {"number": p["number"], "title": p["title"], "user": {"login": p["user"]}, "head": head, "mergeable": p["mergeable"]}
        fx[f"/repos/schnappy/{p['repo']}/pulls"].append(entry)
        fx[f"/repos/schnappy/{p['repo']}/pulls/{p['number']}"] = entry
        statuses = [{"context": "renovate/stability-days", "status": "success"}]
        if p["ci"] is not None:
            statuses.insert(0, {"context": "ci/woodpecker/pr/ci", "status": p["ci"]})
        fx[f"/repos/schnappy/{p['repo']}/commits/{p['sha']}/statuses"] = statuses
    with open(os.path.join(W, "fixture.json.tmp"), "w") as f:
        json.dump(fx, f)
    os.replace(os.path.join(W, "fixture.json.tmp"), os.path.join(W, "fixture.json"))
    for name in ("writes", "restacked", "auth"):
        if os.path.exists(os.path.join(W, name)):
            os.remove(os.path.join(W, name))
def run(*args, repos="admin masi", token="BOTTOKEN", env=None):
    e = {**os.environ, "UPGRADE_FORGEJO_URL": f"http://127.0.0.1:{PORT}/api/v1", "APPS_MERGE_REPOS": repos,
         "APPS_MERGE_RUN_LOGS": os.path.join(LOGS, "upgrade-cycle-*.log"), "APPS_MERGE_RESTACK": STUB,
         "RENOVATE_TOKEN": token, **(env or {})}
    r = subprocess.run([sys.executable, "scripts/upgrade-apps-merge.py", *args], capture_output=True, text=True, env=e, timeout=60)
    return r.returncode, r.stdout + r.stderr
def writes():
    try:
        return [json.loads(l) for l in open(os.path.join(W, "writes"))]
    except FileNotFoundError:
        return []
def runlog(text):
    for f in os.listdir(LOGS):
        os.remove(os.path.join(LOGS, f))
    if text is not None:
        open(os.path.join(LOGS, "upgrade-cycle-20261123-134607-1.log"), "w").write(text)
runlog(None)

fixture([pr("admin", 31)])
rc, out = run("--once")
check("green on its ci/ context and mergeable: merged at the head read, as the bot", (rc, writes(), "MERGED admin#31" in out,
      set(open(os.path.join(W, "auth")).read().split("\n")) - {""}),
      (0, [["/repos/schnappy/admin/pulls/31/merge", {"Do": "merge", "head_commit_id": "%040d" % 31, "delete_branch_after_merge": True}]],
       True, {"token BOTTOKEN"}))
fixture([pr("admin", 32, ci="failure"), pr("admin", 33, ci="pending"), pr("admin", 34, ci=None)])
rc, out = run("--once")
check("red (said RED), pending and no ci/ context at all (Renovate's stability status alone): none merged",
      (writes(), "RED admin#32" in out, "round done: 2 pending" in out), ([], True, True))
fixture([pr("admin", 35, user="someone"), pr("admin", 36, fork=True)])
rc, out = run("--once")
check("another account's PR and a fork's branch named like the bot's: neither touched", (writes(), "DONE" in out), ([], True))
fixture([pr("admin", 37, mergeable=False)])
rc, out = run("--once")
check("green, not mergeable: brought onto main by Forgejo's update, pending again", (writes(), "UPDATED onto main" in out,
      "1 pending" in out), ([["/repos/schnappy/admin/pulls/37/update?style=merge", None]], True, True))
fixture([pr("admin", 38, mergeable=False)], fail_post={"/repos/schnappy/admin/pulls/38/update?style=merge": 409})
rc, out = run("--once")
check("a conflict (409 on the update): the restack asked for that PR, then pending (its CI again)",
      (open(os.path.join(W, "restacked")).read(), "RESTACKED admin#38" in out, "1 pending" in out), ("admin 38\n", True, True))
fixture([pr("admin", 38, mergeable=False)], fail_post={"/repos/schnappy/admin/pulls/38/update?style=merge": 409})
rc, out = run(env={"RESTACK_RC": "1"})
check("a conflict the restack refuses: reported CONFLICT with its reason, not pending - the run ends (not looping on it)",
      (rc, "CONFLICT (REFUSED: the replaced line is not on main) admin#38" in out, "DONE" in out), (0, True, True))
fixture([pr("admin", 39)], fail_post={"/repos/schnappy/admin/pulls/39/merge": 409})
rc, out = run("--once")
check("Forgejo refusing the merge (the head moved, 409): said, pending", ("MERGE REFUSED (HTTP 409) admin#39" in out, "1 pending" in out),
      (True, True))
# the upgrade run's window: between its review and its merge no app PR merges - its log read
review = "2026-11-23 14:40:00 RUN claude -p <the review of renovate/wave-patches>\n"
for name, text, merged in (("between the review and the merge (no END, no MERGED)", "2026-11-23 13:46:19 PICK prove wave-patches patch\n" + review, False),
                           ("its review not begun (the copy proof running)", "2026-11-23 13:46:19 PICK prove wave-patches patch\n", True),
                           ("its merge landed (MERGED after the review)", review + "MERGED schnappy/infra#64\n", True),
                           ("the run ended (END) after a review", review + "2026-11-23 14:50:00 STOPPED x\n2026-11-23 14:50:00 END rc=1\n", True)):
    runlog(text)
    fixture([pr("admin", 40)])
    rc, out = run("--once")
    check(f"the upgrade run {name}: {'merged' if merged else 'held, said'}",
          (bool(writes()), "held - the upgrade run is between its review and its merge" in out), (merged, not merged))
runlog(None)
fixture([pr("masi", 278), pr("masi", 279)])
rc, out = run("--once")
check("masi: one merge a round (its deploys spaced - a burst made sources stale)", [w[0] for w in writes()],
      ["/repos/schnappy/masi/pulls/278/merge"])
fixture([pr("masi", 278), pr("masi", 279)])
rc, out = run("--once", env={"MASI_GAP": "0"})
check("masi with no gap: both", len(writes()), 2)
fixture([pr("admin", 31)])
rc, out = run("--once", token="")
check("no bot token: refused, nothing requested", (rc, os.path.exists(os.path.join(W, "auth")), "RENOVATE_TOKEN is empty" in out), (2, False, True))
fixture([pr("admin", 32, ci="failure")])
rc, out = run()
check("without --once: ends at once when nothing is pending (a red one listed)", (rc, "RED admin#32" in out, "DONE" in out), (0, True, True))
print("upgrade-apps-merge: ALL-PASS" if fails == 0 else f"upgrade-apps-merge: {fails} FAILED")
sys.exit(1 if fails else 0)
PYCHECK
