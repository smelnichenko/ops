#!/bin/bash
# scripts/upgrade-units.py - the upgrade cycle's pick of the night's Renovate unit - against a throwaway Forgejo API (a
# local server, a process of its own, its answers from the case's fixture, paged as Forgejo pages): units grouped by
# branch across infra, platform and ops, their kind (major by label, wave-patches a patch); the pick's order -
# wave-patches, the family minors in order, other minors, majors; blocked and vetoed units left out; a major noticed,
# applied only after its 24 h (an unvetoed one, exactly 24 h its end; the earliest notice its own), the waiting one before
# a new notice (the one noticed first first); the kill switch on the dashboard issue (found by its title, on any page;
# none open - not read, never "not paused"); more than one page of pull requests; Forgejo unreachable - not read, never
# NOTHING.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'kill "$(cat "$W/pid" 2> /dev/null)" 2> /dev/null; rm -rf "$W"' EXIT
cat > "$W/server.py" <<'SERVER'
import http.server, json, os, sys, urllib.parse
W = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        fx = json.load(open(os.path.join(W, "fixture.json")))
        data = fx.get(u.path.removeprefix("/api/v1"))
        if u.path.endswith(".diff") and isinstance(data, str):
            body = data.encode(); self.send_response(200); self.end_headers(); self.wfile.write(body); return
        if data is None:
            self.send_response(404); self.end_headers(); self.wfile.write(b'{"message":"not found"}'); return
        if isinstance(data, list) and not u.path.endswith("/comments"):  # comments: every one at once, no pages
            page, limit = int(q.get("page", ["1"])[0]), int(q.get("limit", ["50"])[0])
            data = data[(page - 1) * limit:page * limit]
        body = json.dumps(data).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port.tmp"), "w").write(str(s.server_port)); os.rename(os.path.join(W, "port.tmp"), os.path.join(W, "port"))
s.serve_forever()
SERVER
python3 "$W/server.py" "$W" & echo $! > "$W/pid"
for _ in $(seq 50); do [ -e "$W/port" ] && break; sleep 0.1; done
[ -e "$W/port" ] || { echo "upgrade-units: the local server did not start"; exit 1; }
W=$W PORT=$(cat "$W/port") python3 - <<'PYCHECK'
import json, os, subprocess, sys
W, PORT = os.environ["W"], os.environ["PORT"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def pr(number, unit, *labels, user="renovate-bot", fork=False, renovate=True):
    # the repository's own branch unless fork (head.repo filled in by fixture() for its repo); Renovate's own label on it
    # (upgrade-cycle, as the preset puts it) unless it has major or one-way, or renovate=False (Forgejo applied none)
    labels = list(labels) + (["upgrade-cycle"] if renovate and not {"upgrade-cycle", "major", "one-way"} & set(labels) else [])
    return {"number": number, "head": {"ref": f"renovate/{unit}", "repo": "FORK" if fork else None},
            "user": {"login": user}, "labels": [{"name": x} for x in labels]}
DASH_TITLE = json.load(open("renovate/upgrade-cycle.json"))["dependencyDashboardTitle"]
def fixture(infra=(), platform=(), ops=(), comments=None, dashboard_labels=(), dashboard=True, others=1, infra_dash=(),
            dash_user="renovate-bot", dash_title=None, platform_dash=()):
    # the dashboard behind other open issues (one labelled upgrades-paused itself: the title, not the first issue, decides)
    issues = [{"title": f"an issue {i}", "labels": [{"name": "upgrades-paused"}], "user": {"login": "renovate-bot"}} for i in range(others)]
    if dashboard:
        issues.append({"title": dash_title or DASH_TITLE, "user": {"login": dash_user}, "labels": [{"name": x} for x in dashboard_labels]})
    fx = {"/repos/schnappy/infra/pulls": list(infra), "/repos/schnappy/platform/pulls": list(platform),
          "/repos/schnappy/ops/pulls": list(ops), "/repos/schnappy/ops/issues": issues,
          "/repos/schnappy/platform/issues": [{"title": DASH_TITLE, "user": {"login": "renovate-bot"},
                                               "labels": [{"name": x} for x in platform_dash]}],
          "/repos/schnappy/infra/issues": [{"title": DASH_TITLE, "user": {"login": "renovate-bot"},
                                            "labels": [{"name": x} for x in infra_dash]}]}
    # a comment: its body (the bot's), or (author, body)
    for (repo, n), bodies in (comments or {}).items():
        fx[f"/repos/schnappy/{repo}/issues/{n}/comments"] = [
            {"body": b[1], "user": {"login": b[0]}} if isinstance(b, tuple) else {"body": b, "user": {"login": "renovate-bot"}}
            for b in bodies]
    for repo, prs in (("infra", infra), ("platform", platform), ("ops", ops)):
        for p in prs:
            p["head"]["repo"] = {"full_name": "someone/" + repo if p["head"]["repo"] == "FORK" else f"schnappy/{repo}"}
            fx.setdefault(f"/repos/schnappy/{repo}/issues/{p['number']}/comments", [])
    json.dump(fx, open(os.path.join(W, "fixture.json"), "w"))
NOW = "2026-11-20T03:00:00Z"
HEADS = "schnappy/infra@" + "a" * 40 + ",schnappy/ops@" + "c" * 40
def run(*args, url=None):
    env = {**os.environ, "UPGRADE_FORGEJO_URL": url or f"http://127.0.0.1:{PORT}/api/v1", "UPGRADE_FORGEJO_TOKEN": "t",
           "UPGRADE_NOW": NOW}
    r = subprocess.run([sys.executable, "scripts/upgrade-units.py", *args], capture_output=True, text=True, env=env, timeout=60)
    return r.returncode, r.stdout.strip()
fixture()
check("no unit open: nothing", run("pick"), (0, "NOTHING"))
fixture(infra=[pr(1, "wave-patches", "upgrade-cycle"), pr(2, "istio", "upgrade-cycle"), pr(3, "postgresql-19.x", "major")],
        platform=[pr(7, "wave-patches")], ops=[pr(9, "istio")])
check("list: one line a unit - its kind, its repos, its labels", run("list"), (0, "\n".join([
    "istio minor schnappy/infra,schnappy/ops upgrade-cycle", "postgresql-19.x major schnappy/infra major",
    "wave-patches patch schnappy/infra,schnappy/platform upgrade-cycle"])))
check("wave-patches first, before the minors and the majors", run("pick"), (0, "prove wave-patches patch"))
fixture(infra=[pr(1, "wave-patches"), pr(3, "sonarqube-26.x", renovate=False)], platform=[pr(7, "wave-patches", renovate=False)])
import base64  # noqa: E402
def blob(text):
    p = pr(5, "rclone-1.x", renovate=False)
    p["body"] = "x\n<!--renovate-debug:" + text + "-->"
    return p
for text, why in (("!!!notbase64", "not base64"), (base64.b64encode(b"not json").decode(), "not JSON"),
                  (base64.b64encode(b"[1, 2]").decode(), "a list, not a record"), (base64.b64encode(b"null").decode(), "null"),
                  (base64.b64encode(json.dumps({"labels": 5}).encode()).decode(), "labels a number"),
                  (base64.b64encode(json.dumps({"labels": "major"}).encode()).decode(), "labels a string"),
                  (base64.b64encode(json.dumps({"labels": {"major": 1}}).encode()).decode(), "labels a mapping"),
                  (base64.b64encode(json.dumps({"labels": [["major"]]}).encode()).decode(), "labels nested")):
    fixture(infra=[blob(text)])
    check(f"Renovate's record malformed ({why}): no label granted, no crash - unlabelled, never picked",
          (run("list"), run("pick")), ((0, "rclone-1.x minor schnappy/infra - UNLABELLED"), (0, "NOTHING")))
def recorded(p, *labels):  # Renovate's own record in the body: the labels it decided (Forgejo dropped them)
    p["body"] = "This PR contains...\n<!--renovate-debug:" + base64.b64encode(json.dumps({"labels": list(labels)}).encode()).decode() + "-->"
    return p
fixture(infra=[recorded(pr(3, "kafka-5.x", renovate=False), "major"), recorded(pr(4, "istio", renovate=False), "upgrade-cycle")])
check("labels Renovate decided and Forgejo dropped (its record in the body): read as its own - a major still a major, "
      "noticed; the minor proven", (run("list")[1].split("\n"), run("pick")),
      (["istio minor schnappy/infra upgrade-cycle", "kafka-5.x major schnappy/infra major"], (0, "prove istio minor")))
fixture(infra=[pr(1, "wave-patches"), pr(3, "sonarqube-26.x", renovate=False)], platform=[pr(7, "wave-patches", renovate=False)])
check("a pull request without Renovate's labels (the repo had none to apply - a major would read as a minor): its unit "
      "never picked, said in the list", (run("pick"), run("list")[1].split("\n")),
      ((0, "NOTHING"),
       ["sonarqube-26.x minor schnappy/infra - UNLABELLED", "wave-patches patch schnappy/infra,schnappy/platform upgrade-cycle UNLABELLED"]))
fixture(infra=[pr(2, "observability"), pr(3, "istio"), pr(4, "cert-manager-1.x"), pr(5, "argocd")])
check("the family minors in their order (istio before observability), before any other minor", run("pick"),
      (0, "prove istio minor"))
fixture(infra=[pr(4, "cert-manager-1.x"), pr(6, "valkey-9.x")])
check("other minors by name when no family's is open", run("pick"), (0, "prove cert-manager-1.x minor"))
# the families moved one minor at a time, named for their minor (renovate/upgrade-cycle.json's branch topics)
fixture(infra=[pr(2, "istio-1.33"), pr(3, "istio-1.32"), pr(4, "kubernetes-1.37"), pr(5, "observability")])
check("a family one minor at a time: its lowest minor first", run("pick"), (0, "prove istio-1.32 minor"))
fixture(infra=[pr(2, "istio-1.10"), pr(3, "istio-1.9")])
check("its minors by number, not by text (1.9 before 1.10)", run("pick"), (0, "prove istio-1.9 minor"))
fixture(infra=[pr(2, "observability"), pr(3, "cilium-1.21"), pr(4, "kubernetes-1.37")])
check("the families' order: kubernetes, then cilium, before observability", run("pick"), (0, "prove kubernetes-1.37 minor"))
fixture(infra=[pr(2, "scylladb-2026.10"), pr(3, "scylladb-2026.9"), pr(4, "zz-other-1.x")])
check("another minor named for its minor: the lowest first, by number", run("pick"), (0, "prove scylladb-2026.9 minor"))
# a test environment's unit (renovate/test-<unit>, the preset's): merged before its production twin
fixture(infra=[pr(1, "wave-patches"), pr(2, "observability")], platform=[pr(3, "test-observability")])
check("a test environment's unit first, before wave-patches", run("pick"), (0, "test test-observability minor"))
fixture(infra=[pr(1, "test-observability"), pr(2, "test-wave-patches")])
check("test units in their twins' order (wave-patches' first)", run("pick"), (0, "test test-wave-patches patch"))
fixture(infra=[pr(1, "test-istio-1.32", "upgrade-blocked"), pr(2, "istio-1.32"), pr(3, "observability")])
check("a production unit waits while its test unit is open - blocked too: the next unit instead", run("pick"),
      (0, "prove observability minor"))
fixture(infra=[pr(1, "test-grafana-k6-2.x", "major")])
check("a major's test unit: merged as a test unit (the 24 h notice is its production twin's)", run("pick"),
      (0, "test test-grafana-k6-2.x major"))
fixture(infra=[pr(1, "test-grafana-k6-2.x", "veto"), pr(2, "grafana-k6-2.x", "major")])
check("a vetoed test unit holds its production twin too: nothing", run("pick"), (0, "NOTHING"))
# a shadow run merges nothing: a test environment's unit there is a comment, no proof (no copy) - every shadow run would
# stop at it; the shadow's pick leaves them out, the production units in their order (a twin still waits for its test unit)
fixture(infra=[pr(1, "wave-patches"), pr(2, "observability")], platform=[pr(3, "test-observability")])
check("--shadow: the test environment's units left out - the first production unit proven", run("pick", "--shadow"),
      (0, "prove wave-patches patch"))
fixture(infra=[pr(1, "test-observability"), pr(2, "observability")])
check("  a production twin still waits while its test unit is open: nothing", run("pick", "--shadow"), (0, "NOTHING"))
check("  pick takes --shadow, nothing else", run("pick", "--all")[0], 2)
fixture(infra=[pr(2, "istio-x.32"), pr(3, "istio")])
check("a name that only looks versioned is not (istio-x.32 is no istio minor): the family's own unit first",
      run("pick"), (0, "prove istio minor"))
fixture(infra=[pr(1, "wave-patches", "upgrade-blocked"), pr(2, "istio", "veto"), pr(3, "observability")])
check("a blocked unit and a vetoed one left out", run("pick"), (0, "prove observability minor"))
# a manual- unit (renovate/manual-woodpecker): what the copy cannot prove - applied by hand, never picked
fixture(infra=[pr(1, "manual-woodpecker")])
check("a manual- unit alone: nothing picked (applied by hand)", (run("pick"), run("pick", "--shadow")), ((0, "NOTHING"), (0, "NOTHING")))
fixture(infra=[pr(1, "manual-woodpecker"), pr(2, "observability")], platform=[pr(3, "manual-woodpecker")])
check("  beside another unit: that one proven, the manual one left - and listed", (run("pick"), "manual-woodpecker" in run("list")[1]),
      ((0, "prove observability minor"), True))
fixture(infra=[pr(1, "wave-patches")], dashboard_labels=["upgrades-paused"])
check("the kill switch on the dashboard issue: paused, nothing picked", run("pick"), (0, "PAUSED"))
fixture(infra=[pr(3, "postgresql-19.x", "major")])
check("a major without its notice: proven, then noticed", run("pick"), (0, "notice postgresql-19.x major"))
check("noticed: none yet", run("noticed", "postgresql-19.x"), (0, "NONE"))
fixture(infra=[pr(3, "postgresql-19.x", "major")], comments={("infra", 3): ["looks fine", "UPGRADE NOTICE 2026-11-19T04:00:00Z - applies after"]})
check("a major noticed 23 h ago: still in its 24 h - nothing", run("pick"), (0, "NOTHING"))
check("noticed: the notice's time", run("noticed", "postgresql-19.x"), (0, "2026-11-19T04:00:00Z"))

fixture(infra=[pr(3, "postgresql-19.x", "major")], comments={("infra", 3): [f"UPGRADE NOTICE 2026-11-19T02:59:00Z heads={HEADS} - x"]})
check("a major noticed 24 h ago, unvetoed: applied (the runner judges whether its heads are the ones announced)", run("pick"),
      (0, "apply postgresql-19.x major"))
check("noticed: its time and the heads it announced", run("noticed", "postgresql-19.x"), (0, f"2026-11-19T02:59:00Z {HEADS}"))
fixture(infra=[pr(3, "postgresql-19.x", "major")], comments={("infra", 3): [f"UPGRADE NOTICE 2026-11-19T03:00:00Z heads={HEADS}"]})
check("a major noticed exactly 24 h ago: its 24 h over - applied", run("pick"), (0, "apply postgresql-19.x major"))
fixture(infra=[pr(3, "postgresql-19.x", "major")],
        comments={("infra", 3): [f"chatter {i}" for i in range(59)] + [f"UPGRADE NOTICE 2026-11-19T02:00:00Z heads={HEADS}"]})
check("a pull request with 60 comments (Forgejo gives them all at once, no pages): its notice, the 60th, found - read once",
      run("noticed", "postgresql-19.x"), (0, f"2026-11-19T02:00:00Z {HEADS}"))
fixture(infra=[pr(3, "postgresql-19.x", "major")], ops=[pr(5, "postgresql-19.x", "major")],
        comments={("infra", 3): ["UPGRADE NOTICE 2026-11-19T10:00:00Z", "UPGRADE NOTICE 2026-11-19T08:00:00Z"],
                  ("ops", 5): ["UPGRADE NOTICE 2026-11-19T09:00:00Z"]})
check("noticed more than once, on more than one pull request: the latest notice is the unit's (noticed again - its "
      "agent's fix - its 24 h start again)", run("noticed", "postgresql-19.x"), (0, "2026-11-19T10:00:00Z"))
fixture(infra=[pr(3, "postgresql-19.x", "major")],
        comments={("infra", 3): ["UPGRADE NOTICE 2026-11-17T00:00:00Z", "UPGRADE NOTICE 2026-11-19T20:00:00Z"]})
check("a major noticed days ago, then again 7 h ago (its fix): still in its 24 h - nothing", run("pick"), (0, "NOTHING"))
# the agent's fix in a unit (agent-fixed): a 24 h notice first, whatever its kind
fixture(infra=[pr(1, "istio-1.32", "agent-fixed"), pr(2, "observability")])
check("a minor carrying the agent's fix: waits for its notice - the next minor proven first", run("pick"),
      (0, "prove observability minor"))
fixture(infra=[pr(1, "istio-1.32", "agent-fixed")])
check("  alone: its notice (kind kept)", run("pick"), (0, "notice istio-1.32 minor"))
fixture(infra=[pr(1, "istio-1.32", "agent-fixed")], comments={("infra", 1): [f"UPGRADE NOTICE 2026-11-19T02:00:00Z heads={HEADS}"]})
check("  noticed 25 h ago, unvetoed, its diff the one announced: applied (kind kept)", run("pick"), (0, "apply istio-1.32 minor"))
fixture(infra=[pr(1, "wave-patches", "agent-fixed")], comments={("infra", 1): ["UPGRADE NOTICE 2026-11-19T20:00:00Z"]})
check("  a patch wave with the agent's fix in its 24 h: nothing", run("pick"), (0, "NOTHING"))
fixture(infra=[pr(3, "aaa-5.x", "major"), pr(4, "zzz-2.x", "major")],
        comments={("infra", 3): ["UPGRADE NOTICE 2026-11-18T02:00:00Z"], ("infra", 4): ["UPGRADE NOTICE 2026-11-17T02:00:00Z"]})
check("two majors past their 24 h: the one noticed first applied first (not the first by name)", run("pick"),
      (0, "apply zzz-2.x major"))
fixture(infra=[pr(3, "postgresql-19.x", "major", "veto")], comments={("infra", 3): ["UPGRADE NOTICE 2026-11-18T00:00:00Z"]})
check("a vetoed major: never applied", run("pick"), (0, "NOTHING"))
fixture(infra=[pr(3, "postgresql-19.x", "major"), pr(4, "kafka-5.x", "major")],
        comments={("infra", 3): ["UPGRADE NOTICE 2026-11-18T00:00:00Z"]})
check("a waiting major applied before a new notice", run("pick"), (0, "apply postgresql-19.x major"))
fixture(infra=[pr(3, "postgresql-19.x", "major"), pr(4, "kafka-5.x", "major")],
        comments={("infra", 3): ["UPGRADE NOTICE 2026-11-19T20:00:00Z"]})
check("one major in its 24 h, another without a notice: that one noticed", run("pick"), (0, "notice kafka-5.x major"))
fixture(infra=[pr(i, f"other-{i:03d}") for i in range(60)] + [pr(99, "wave-patches")])
check("more than one page of pull requests: the second page read (wave-patches on it)", run("pick"),
      (0, "prove wave-patches patch"))
check("Forgejo unreachable: not read (exit 1), never NOTHING", run("pick", url="http://127.0.0.1:1/api/v1")[0], 1)
check("noticed: a unit not open", run("noticed", "nope"), (1, "NO UNIT nope"))
check("a command it does not take", run("apply")[0], 2)
fixture(infra=[pr(1, "wave-patches"), pr(2, "istio", "veto"), pr(3, "observability", "upgrade-blocked", "veto")])
check("held: what holds a unit now - nothing for a free one, its labels for one blocked or vetoed",
      (run("held", "wave-patches"), run("held", "istio"), run("held", "observability"), run("held", "nope")),
      ((0, ""), (0, "veto"), (0, "upgrade-blocked\nveto"), (1, "NO UNIT nope")))
fixture(infra=[pr(1, "wave-patches")], dashboard_labels=["upgrades-paused"])
check("held: the dashboard's kill switch - paused", run("held", "wave-patches"), (0, "paused"))
fixture(infra=[pr(1, "wave-patches")], dashboard_labels=["upgrades-paused"], others=60)
check("the dashboard on the second page of issues: its kill switch read there", (run("pick"), run("held", "wave-patches")),
      ((0, "PAUSED"), (0, "paused")))
fixture(infra=[pr(1, "wave-patches")], dashboard=False)
check("no dashboard issue open (closed, renamed): the kill switch not read - pick and held fail closed (exit 1, said), "
      "never 'not paused'", (run("pick")[0], run("held", "wave-patches")[0], run("pick")[1].startswith("NOT READ")), (1, 1, True))
fixture(infra=[pr(1, "wave-patches")], infra_dash=["upgrades-paused"])
check("the kill switch pulled on infra's dashboard (every repo has one, the same title): paused", (run("pick"), run("held", "wave-patches")),
      ((0, "PAUSED"), (0, "paused")))
fixture(infra=[pr(1, "wave-patches")], platform_dash=["upgrades-paused"])
check("  on platform's: paused", run("pick"), (0, "PAUSED"))
fixture(infra=[pr(1, "wave-patches")], dashboard_labels=["upgrades-paused"], dash_user="mallory")
check("an issue of another account's under the dashboard's title: not the dashboard (ops' then missing: not read)", run("pick")[0], 1)
fixture(infra=[pr(1, "wave-patches")], dashboard_labels=["upgrades-paused"], dash_title="Upgrade cycle - Renovate's dashboard (old)")
check("a title only starting like it: not the dashboard (not read)", run("pick")[0], 1)
check("held: Forgejo unreachable - not read (exit 1), never 'nothing holds it'",
      run("held", "wave-patches", url="http://127.0.0.1:1/api/v1")[0], 1)
fixture(infra=[pr(1, "wave-patches", user="mallory"), pr(2, "istio", fork=True), pr(3, "observability")])
check("another account's pull request, or one from a fork, named renovate/<unit> all the same: no unit",
      (run("pick"), run("list")[1].split("\n")), ((0, "prove observability minor"), ["observability minor schnappy/infra upgrade-cycle"]))
fixture(infra=[pr(3, "postgresql-19.x", "major")],
        comments={("infra", 3): [("mallory", "UPGRADE NOTICE 2026-11-01T00:00:00Z - backdated")]})
check("a notice comment by anyone but the bot: no notice (a backdated one skipped the 24 h)",
      (run("noticed", "postgresql-19.x"), run("pick")), ((0, "NONE"), (0, "notice postgresql-19.x major")))
fixture(infra=[pr(3, "postgresql-19.x", "major")],
        comments={("infra", 3): ["Renovate: release notes\n\nUPGRADE NOTICE 2026-11-01T00:00:00Z - quoted from somewhere"]})
check("a line inside another comment of the bot's (Renovate posts as the same account): no notice - a notice is a comment "
      "that starts as one", (run("noticed", "postgresql-19.x"), run("pick")), ((0, "NONE"), (0, "notice postgresql-19.x major")))
fixture(infra=[pr(1, "test-istio-1.32", "agent-fixed")])
check("a test environment's unit labelled agent-fixed (by a hand - the test path has no fix): merged at once as a test "
      "unit (the test environment its own proof; the 24 h notice is its production twin's)", run("pick"), (0, "test test-istio-1.32 minor"))
print("upgrade-units: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
