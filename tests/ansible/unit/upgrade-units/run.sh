#!/bin/bash
# scripts/upgrade-units.py - the upgrade cycle's pick of the night's Renovate unit - against a throwaway Forgejo API (a
# local server, a process of its own, its answers from the case's fixture, paged as Forgejo pages): units grouped by
# branch across infra, platform and ops, their kind (major by label, wave-patches a patch); the pick's order -
# wave-patches, the family minors in order, other minors, majors - a unit with a try on record (the runner's) behind the
# ones with none; no per-unit hold (a veto or an upgrade-blocked label holds nothing - no blocked state, no veto since
# 2026-11-27); every unit, a major,
# a one-way one and one carrying the agent's fix alike, proven at once - no notice, no clock (operator 2026-11-21); STEPS:
# a unit never goes while a lower step of its dependency is open (17 -> 18 -> 19: held, tried or unlabelled, the lower one
# still holds the higher), test- steps their own path; bodies UNIT DIR - the pull requests' bodies; the kill switch on the dashboard issue (found by its title, on any page;
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
    def do_PATCH(self):  # an issue's edit, as replenish ticks a dashboard: recorded, and the fixture answers with it after
        path = urllib.parse.urlparse(self.path).path.removeprefix("/api/v1")
        payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        fx = json.load(open(os.path.join(W, "fixture.json")))
        repo_issues, _, number = path.rpartition("/")
        issue = next((i for i in fx.get(repo_issues, []) if str(i.get("number")) == number), None)
        if issue is None or fx.get("patch_fails"):
            self.send_response(500); self.end_headers(); self.wfile.write(b'{"message":"no"}'); return
        issue.update(payload)
        json.dump(fx, open(os.path.join(W, "fixture.json"), "w"))
        with open(os.path.join(W, "patches.jsonl"), "a") as f:
            f.write(json.dumps({"path": path, **payload}) + "\n")
        self.send_response(200); self.end_headers(); self.wfile.write(json.dumps(issue).encode())
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port.tmp"), "w").write(str(s.server_port)); os.rename(os.path.join(W, "port.tmp"), os.path.join(W, "port"))
s.serve_forever()
SERVER
python3 "$W/server.py" "$W" & echo $! > "$W/pid"
for _ in $(seq 50); do [ -e "$W/port" ] && break; sleep 0.1; done
[ -e "$W/port" ] || { echo "upgrade-units: the local server did not start"; exit 1; }
W=$W PORT=$(cat "$W/port") python3 - <<'PYCHECK'
import json, os, shutil, subprocess, sys
W, PORT = os.environ["W"], os.environ["PORT"]
TRIES = os.path.join(W, "tries")  # the runner's tries: the case's own, never the checkout's
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
def tries(unit, *keys):
    os.makedirs(TRIES, exist_ok=True)
    open(os.path.join(TRIES, unit), "w").write("".join(f"{k} 2026-11-20T10:00:00Z a try\n" for k in keys))
DASH_TITLE = json.load(open("renovate/upgrade-cycle.json"))["dependencyDashboardTitle"]
DASH_NUMBER = {"infra": 44, "platform": 33, "ops": 56}
def board(units, ticked=()):  # a dashboard's body: Renovate's pending-approval boxes for these units, one ticked or not
    lines = ["This issue lists Renovate updates.", "", "## Pending Approval", "",
             "These branches will be created by Renovate only once you click their checkbox below.", ""]
    lines += [f" - [{'x' if u in ticked else ' '}] <!-- approve-branch=renovate/{u} -->Update {u}" for u in units]
    return "\n".join(lines + ["", "## Detected Dependencies", ""])
def fixture(infra=(), platform=(), ops=(), comments=None, dashboard_labels=(), dashboard=True, others=1, infra_dash=(),
            dash_user="renovate-bot", dash_title=None, platform_dash=(), boxes=None, patch_fails=False):
    # the dashboard behind other open issues (one labelled upgrades-paused itself: the title, not the first issue, decides)
    issues = [{"title": f"an issue {i}", "labels": [{"name": "upgrades-paused"}], "user": {"login": "renovate-bot"}} for i in range(others)]
    boxes = boxes or {}
    if dashboard:
        issues.append({"title": dash_title or DASH_TITLE, "user": {"login": dash_user}, "number": DASH_NUMBER["ops"],
                       "body": board(boxes.get("ops", ())), "labels": [{"name": x} for x in dashboard_labels]})
    fx = {"/repos/schnappy/infra/pulls": list(infra), "/repos/schnappy/platform/pulls": list(platform),
          "/repos/schnappy/ops/pulls": list(ops), "/repos/schnappy/ops/issues": issues,
          "/repos/schnappy/platform/issues": [{"title": DASH_TITLE, "user": {"login": "renovate-bot"},
                                               "number": DASH_NUMBER["platform"], "body": board(boxes.get("platform", ())),
                                               "labels": [{"name": x} for x in platform_dash]}],
          "/repos/schnappy/infra/issues": [{"title": DASH_TITLE, "user": {"login": "renovate-bot"},
                                            "number": DASH_NUMBER["infra"], "body": board(boxes.get("infra", ())),
                                            "labels": [{"name": x} for x in infra_dash]}],
          "patch_fails": patch_fails}
    if os.path.exists(os.path.join(W, "patches.jsonl")):
        os.remove(os.path.join(W, "patches.jsonl"))
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
def run(*args, url=None):
    env = {**os.environ, "UPGRADE_FORGEJO_URL": url or f"http://127.0.0.1:{PORT}/api/v1", "UPGRADE_FORGEJO_TOKEN": "t",
           "UPGRADE_TRIES": TRIES}
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
      "proven after it; the minor first", (run("list")[1].split("\n"), run("pick")),
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
# the Gateway API a unit of its own (renovate/gateway-api-<X.Y>), after the Istio family's - named by its own version under
# istio it read as istio-1.6, picked before istio-1.32 (2026-11-16)
fixture(ops=[pr(1, "gateway-api-1.7"), pr(2, "gateway-api-1.6"), pr(3, "istio-1.32")])
check("Istio's minor before the Gateway API's", run("pick"), (0, "prove istio-1.32 minor"))
fixture(ops=[pr(1, "gateway-api-1.7"), pr(2, "gateway-api-1.6"), pr(3, "kubernetes-1.37")])
check("  the Gateway API one minor at a time, its lowest first - before the families after istio", run("pick"), (0, "prove gateway-api-1.6 minor"))
# a test environment's unit (renovate/test-<unit>, the preset's): merged before its production twin
fixture(infra=[pr(1, "wave-patches"), pr(2, "observability")], platform=[pr(3, "test-observability")])
check("a test environment's unit first, before wave-patches", run("pick"), (0, "test test-observability minor"))
fixture(infra=[pr(1, "test-observability"), pr(2, "test-wave-patches")])
check("test units in their twins' order (wave-patches' first)", run("pick"), (0, "test test-wave-patches patch"))
fixture(infra=[pr(1, "test-istio-1.32", "upgrade-blocked"), pr(2, "istio-1.32"), pr(3, "observability")])
check("an upgrade-blocked label (left from before 2026-11-20) holds nothing: the test unit picked", run("pick"),
      (0, "test test-istio-1.32 minor"))
fixture(infra=[pr(1, "test-istio-1.32"), pr(2, "istio-1.32"), pr(3, "observability")])
tries("test-istio-1.32", "schnappy/infra#1")
check("a production unit waits while its test unit is open - its test unit tried too: the next unit instead", run("pick"),
      (0, "prove observability minor"))
tries("test-istio-1.32")
fixture(infra=[pr(1, "test-grafana-k6-2.x", "major")])
check("a major's test unit: merged as a test unit (its production twin proven after)", run("pick"),
      (0, "test test-grafana-k6-2.x major"))
fixture(infra=[pr(1, "test-grafana-k6-2.x", "veto"), pr(2, "grafana-k6-2.x", "major")])
check("a veto label holds nothing (no veto since 2026-11-27): its test unit first, as any", run("pick"), (0, "test test-grafana-k6-2.x minor"))
# no shadow mode (its pick, the test environment's units left out, gone 2026-11-20): pick takes no option
check("pick takes no option - --shadow nor any other", (run("pick", "--shadow")[0], run("pick", "--all")[0]), (2, 2))
fixture(infra=[pr(2, "istio-x.32"), pr(3, "istio")])
check("a name that only looks versioned is not (istio-x.32 is no istio minor): the family's own unit first",
      run("pick"), (0, "prove istio minor"))
fixture(infra=[pr(2, "istio", "veto"), pr(3, "observability", "upgrade-blocked")])
check("a veto or an upgrade-blocked label holds nothing (no blocked state, no veto): istio first, in its order", run("pick"),
      (0, "prove istio minor"))
# no blocked state (operator 2026-11-20): a unit with a try on record (the runner's) behind the units with none - its own
# pull requests' tries alone (another unit of the name before had other pull requests), a key with no "#" the unit's
fixture(infra=[pr(1, "wave-patches"), pr(2, "observability")], ops=[pr(9, "wave-patches")])
tries("wave-patches", "schnappy/ops#9,schnappy/infra#1")
check("a unit with a try on record (its pull requests', in any order) behind one with none", run("pick"), (0, "prove observability minor"))
tries("wave-patches", "schnappy/infra#1,schnappy/ops#5")
check("  a try of another unit of the name (other pull requests): not this one's - the order kept", run("pick"), (0, "prove wave-patches patch"))
tries("wave-patches", "none")
check("  a try with its pull requests not read (none): the unit's", run("pick"), (0, "prove observability minor"))
tries("observability", "test-environment")
check("  both with tries: their order again", run("pick"), (0, "prove wave-patches patch"))
shutil.rmtree(TRIES)
fixture(infra=[pr(1, "test-observability"), pr(2, "test-wave-patches")])
tries("test-wave-patches", "schnappy/infra#2")
check("  test units the same: the one with a try after", run("pick"), (0, "test test-observability minor"))
shutil.rmtree(TRIES)
fixture(infra=[pr(1, "alpha-2.x", "major"), pr(2, "beta-3.x", "major")])
tries("alpha-2.x", "schnappy/infra#1")
check("  majors the same: the one with no try first", run("pick"), (0, "prove beta-3.x major"))
shutil.rmtree(TRIES)
# a manual- unit (renovate/manual-woodpecker): what the copy cannot prove - applied by hand, never picked
fixture(infra=[pr(1, "manual-woodpecker")])
check("a manual- unit alone: nothing picked (applied by hand)", run("pick"), (0, "NOTHING"))
fixture(infra=[pr(1, "manual-woodpecker"), pr(2, "observability")], platform=[pr(3, "manual-woodpecker")])
check("  beside another unit: that one proven, the manual one left - and listed", (run("pick"), "manual-woodpecker" in run("list")[1]),
      ((0, "prove observability minor"), True))
fixture(infra=[pr(1, "wave-patches")], dashboard_labels=["upgrades-paused"])
check("the kill switch on the dashboard issue: paused, nothing picked", run("pick"), (0, "PAUSED"))
fixture(infra=[pr(3, "postgresql-19.x", "major")])
check("a major: proven and applied in its run like any unit - no notice, no clock (operator 2026-11-21)", run("pick"),
      (0, "prove postgresql-19.x major"))
fixture(infra=[pr(1, "observability"), pr(3, "postgresql-19.x", "major")])
check("  majors still last: the minor first", run("pick"), (0, "prove observability minor"))
# steps (operator 2026-11-21: an upgrade can take several steps, a 17 -> 19 major among them): one at a time, the lower first
fixture(infra=[pr(3, "postgresql-19.x", "major"), pr(4, "postgresql-18.x", "major")])
check("two steps of one dependency (17 -> 18 -> 19): the lower first", run("pick"), (0, "prove postgresql-18.x major"))
fixture(infra=[pr(3, "postgresql-19.x", "major"), pr(4, "postgresql-18.x", "major", "veto")])
check("  a veto label on the lower holds nothing: the lower first", run("pick"), (0, "prove postgresql-18.x major"))
fixture(infra=[pr(3, "postgresql-19.x", "major"), pr(4, "postgresql-18.x", "major"), pr(5, "observability")])
tries("postgresql-18.x", "schnappy/infra#4")
check("  the lower with a try on record: another unit first - never the higher", run("pick"), (0, "prove observability minor"))
fixture(infra=[pr(3, "postgresql-19.x", "major"), pr(4, "postgresql-18.x", "major")])
check("  the lower with a try and nothing else open: the lower again, never the higher", run("pick"), (0, "prove postgresql-18.x major"))
shutil.rmtree(TRIES)
fixture(infra=[pr(3, "postgresql-19.x", "major"), pr(4, "postgresql-18.x", renovate=False)])
check("  the lower unlabelled (never picked itself): the higher still waits", run("pick"), (0, "NOTHING"))
fixture(infra=[pr(3, "postgresql-19.x", "major")], platform=[pr(4, "postgresql-18.x", "major")])
check("  the lower open in another repository only: still the lower first", run("pick"), (0, "prove postgresql-18.x major"))
fixture(infra=[pr(1, "kubernetes-1.37"), pr(2, "kubernetes-1.36"), pr(3, "gateway-api-1.7"), pr(4, "gateway-api-1.6")])
check("minor steps the same (gateway-api 1.6 before 1.7, kubernetes 1.36 before 1.37)", run("pick"), (0, "prove gateway-api-1.6 minor"))
fixture(infra=[pr(1, "kubernetes-1.37"), pr(2, "kubernetes-1.36")])
tries("kubernetes-1.36", "schnappy/infra#2")
check("  kubernetes 1.36 failing: 1.37 never taken past it", run("pick"), (0, "prove kubernetes-1.36 minor"))
shutil.rmtree(TRIES)
fixture(infra=[pr(1, "test-scylladb-2026.3"), pr(2, "test-scylladb-2026.2"), pr(3, "scylladb-2026.2"), pr(4, "scylladb-2026.3")])
check("test steps their own path: test-scylladb-2026.2 before 2026.3", run("pick"), (0, "test test-scylladb-2026.2 minor"))
fixture(infra=[pr(1, "kube-prometheus-stack-93.x", "major"), pr(2, "kube-prometheus-stack-92.x", "major")])
check("  two majors of one chart: 92 before 93", run("pick"), (0, "prove kube-prometheus-stack-92.x major"))
fixture(infra=[pr(1, "nginx-1.x"), pr(2, "nginx-2.x", "major"), pr(3, "postgresql-17-alpine")])
check("  a minor line and a major of one image: the minor line first; a unit no step (a digest unit) none of this",
      run("pick"), (0, "prove nginx-1.x minor"))
# no clock for a one-way unit or one carrying the agent's fix either
fixture(infra=[pr(1, "observability"), pr(3, "scylladb-2026.3", "one-way")])
check("a one-way minor: proven in its order like any (its store backed up first - the runner's)", run("pick"),
      (0, "prove observability minor"))
fixture(infra=[pr(3, "scylladb-2026.3", "one-way")])
check("  alone: proven (kind kept)", run("pick"), (0, "prove scylladb-2026.3 minor"))
fixture(infra=[pr(1, "istio-1.32", "agent-fixed"), pr(2, "observability")])
check("a unit carrying the agent's fix: proven in its order like any - no notice", run("pick"), (0, "prove istio-1.32 minor"))
fixture(infra=[pr(3, "postgresql-19.x", "major", "veto")])
check("a major labelled veto: picked as any (no veto since 2026-11-27)", run("pick"), (0, "prove postgresql-19.x major"))
fixture(infra=[pr(3, "zzz-2.x", "major"), pr(4, "aaa-3.x", "major")])
check("two majors of different dependencies: in their order", run("pick"), (0, "prove aaa-3.x major"))
fixture(infra=[pr(i, f"other-{i:03d}") for i in range(60)] + [pr(99, "wave-patches")])
check("more than one page of pull requests: the second page read (wave-patches on it)", run("pick"),
      (0, "prove wave-patches patch"))
check("Forgejo unreachable: not read (exit 1), never NOTHING", run("pick", url="http://127.0.0.1:1/api/v1")[0], 1)
# steps by the packages in Renovate's table (a family's minors and its major are named apart): the major waits for the
# lower minor whatever holds it; a patch row (the wave) never holds a step; a test unit waits for the production lower
# step too; the year rolls over (2026.12 before 2027.1); a name that is no step (a digest unit) never waits
def tabled(n, unit, rows, *labels):
    p = pr(n, unit, *labels)
    p["body"] = "This PR contains the following updates:\n\n| Package | Update | Change |\n|---|---|---|\n" + "".join(
        f"| [{pkg}](https://hub.docker.com/r/{pkg}) ([source](https://github.com/{pkg})) | {up} | `{a}` → `{b}` |\n" for pkg, up, a, b in rows)
    return p
fixture(infra=[tabled(7, "scylladb-scylla-2027.x", [("scylladb/scylla", "major", "2026.2.3", "2027.1.0")], "major", "one-way"),
               tabled(6, "scylladb-2026.3", [("scylladb/scylla", "minor", "2026.2.3", "2026.3.1")], "one-way")])
tries("scylladb-2026.3", "schnappy/infra#6")
check("steps by package: a major named apart (scylladb-scylla-2027.x) waits for the lower minor of its package "
      "(scylladb-2026.3) - though that one has a try and the major none", run("pick"), (0, "prove scylladb-2026.3 minor"))
shutil.rmtree(TRIES)
fixture(infra=[tabled(7, "scylladb-scylla-2027.x", [("scylladb/scylla", "major", "2026.2.3", "2027.1.0")], "major", "one-way"),
               tabled(1, "wave-patches", [("scylladb/scylla", "patch", "2026.2.3", "2026.2.4"), ("nginx", "patch", "1.31.8", "1.31.9")])])
tries("wave-patches", "schnappy/infra#1")
check("  a patch row (the wave's) never holds a step: the major goes, the wave with its try after", run("pick"),
      (0, "prove scylladb-scylla-2027.x major"))
shutil.rmtree(TRIES)
fixture(infra=[pr(5, "test-scylladb-2026.4", "one-way"), pr(6, "scylladb-2026.3", "one-way")])
check("  a test unit waits for the production unit of a lower step (the test environment one step ahead at most)",
      run("pick"), (0, "prove scylladb-2026.3 minor"))
fixture(infra=[pr(1, "scylladb-2027.1"), pr(2, "scylladb-2026.12")])
check("  the year rolls over: 2026.12 before 2027.1 (each part a number, the major first)", run("pick"), (0, "prove scylladb-2026.12 minor"))
fixture(infra=[pr(1, "postgresql-17-alpine"), pr(2, "postgresql-16.x", "major")])
check("  a name that is no step (a digest unit, postgresql-17-alpine) never waits - beside postgresql-16.x",
      run("pick"), (0, "prove postgresql-17-alpine minor"))
fixture(infra=[tabled(5, "test-k6-1.8", [("grafana/k6", "minor", "2.4.0", "2.5.0")]), tabled(6, "k6-1.8", [("grafana/k6", "minor", "1.7.1", "1.8.0")])])
check("  a test unit moving a package higher than its production twin (k6: 2.x in test, 1.x in production): no deadlock - the "
      "test unit first (the twin rule)", run("pick"), (0, "test test-k6-1.8 minor"))
nb = tabled(7, "scylladb-scylla-2027.x", [("scylladb/scylla", "major", "2026.2.3", "2027.1.0")], "major", "one-way")
nb["body"] += "\n---\n\n### Release Notes\n\n| Package | Update | Change |\n|---|---|---|\n| [golang](x) | minor | `1.20` → `1.21` |\n"  # lower than golang-1.x's: read as a step, it would hold golang-1.x
fixture(infra=[nb, tabled(8, "golang-1.x", [("golang", "minor", "1.23", "1.24")])])
check("  a table in the release notes (upstream's text) is no step: golang-1.x not held, the major not held by it",
      run("pick"), (0, "prove golang-1.x minor"))
fixture(infra=[tabled(7, "scylladb-scylla-2027.x", [("scylladb/scylla", "major", "2026.2.3", "2027.1.0")], "major", "one-way"),
               tabled(6, "scylladb-2026.3", [("docker.io/scylladb/scylla", "minor", "2026.2.3", "2026.3.1")], "one-way")])
tries("scylladb-2026.3", "schnappy/infra#6")
check("  one package however it is written (with its registry's docker.io/ prefix): the major still waits (the minor has a try)",
      run("pick"), (0, "prove scylladb-2026.3 minor"))
shutil.rmtree(TRIES)
def raw(n, unit, table, *labels):
    p = pr(n, unit, *labels); p["body"] = "This PR contains the following updates:\n\n" + table; return p
REAL_SHAPE = ("| Package | Type | Update | Change | Pending |\n|---|---|---|---|---|\n"
              "| [grafana/agent](https://github.com/grafana/agent) | | major | `2.4.0` -> `3.0.0` | `3.0.1` |\n"
              "| [grafana/agent](https://github.com/grafana/agent) | | digest | `abc1234` -> `def5678` | |\n| short |\n")
OTHER_ORDER = "| Change | Update | Package |\n|---|---|---|\n| `2.4.0` -> `2.5.0` | minor | grafana/agent |\n"
fixture(infra=[raw(7, "grafana-agent-3.x", REAL_SHAPE, "major"), raw(6, "agent-2.5", OTHER_ORDER)])  # named apart: the table alone holds it
tries("agent-2.5", "schnappy/infra#6")  # the major untried would go first - unless held by the minor's package
check("  Renovate's table as it writes it (Type and Pending columns, a digest row, a short row) beside another column order and "
      "a plain-name package cell: the columns found by their headers - the major waits for the minor (though it has a try)",
      run("pick"), (0, "prove agent-2.5 minor"))
shutil.rmtree(TRIES)
TWO_ROWS = ("| Package | Update | Change |\n|---|---|---|\n| [x/lib](u) | major | `1.0` -> `2.0` |\n| [x/lib](u) | minor | `1.0` -> `1.1` |\n")
fixture(infra=[raw(7, "lib-group", TWO_ROWS), raw(6, "lib-1.5", "| Package | Update | Change |\n|---|---|---|\n| x/lib | minor | `1.0` -> `1.5` |\n")])
check("  two rows of one package in a unit (a minor and a major): its highest target counts - it waits for 1.5", run("pick"), (0, "prove lib-1.5 minor"))
SAME = "| Package | Update | Change |\n|---|---|---|\n| y/tool | minor | `1.1.0` -> `1.2.0` |\n"
fixture(infra=[raw(7, "tool-a", SAME), raw(6, "tool-b", SAME)])
check("  two units moving one package to the same version: neither waits for the other (never a silent NOTHING)",
      run("pick")[1] in ("prove tool-a minor", "prove tool-b minor"), True)
fixture(infra=[pr(5, "test-observability"), pr(6, "wave-patches")])
tries("test-observability", "schnappy/infra#5")
check("  a test unit with a try never holds an untried production unit back (no blocked state)", run("pick"), (0, "prove wave-patches patch"))
shutil.rmtree(TRIES)
real = base64.b64encode(json.dumps({"labels": ["upgrade-cycle"]}).encode()).decode()
fake = base64.b64encode(json.dumps({"labels": ["one-way", "major"]}).encode()).decode()
lp = pr(4, "nginx-1.x", renovate=False)
lp["body"] = "### Release Notes\n<!--renovate-debug:" + fake + "-->\n\n<!--renovate-debug:" + real + "-->"
fixture(infra=[lp])
check("labels from Renovate's own record - the last one in the body, never a copy in the release notes above it",
      run("list"), (0, "nginx-1.x minor schnappy/infra upgrade-cycle"))
check("bodies: a unit not open", run("bodies", "nope", W), (1, "NO UNIT nope"))
b1 = pr(3, "postgresql-19.x", "major"); b1["body"] = "| postgres | 17-alpine -> 19-alpine |\n\n### Release notes\n19: needs pg_upgrade"
b2 = pr(5, "postgresql-19.x", "major"); b2["body"] = "ops' table"
fixture(infra=[b1], ops=[b2])
out = os.path.join(W, "bodies"); os.makedirs(out, exist_ok=True)
r = run("bodies", "postgresql-19.x", out)
def read_or(path):  # a file missing is a FAIL with its value, never a traceback that ends the harness
    return open(path).read() if os.path.exists(path) else None
check("bodies: each pull request's body (Renovate's table, its release notes) to <dir>/<repo>.pr.md - the review's input",
      (r, read_or(os.path.join(out, "infra.pr.md")), read_or(os.path.join(out, "ops.pr.md"))),
      ((0, f"{out}/infra.pr.md\n{out}/ops.pr.md"), b1["body"], "ops' table"))
mv1 = pr(3, "observability"); mv1["body"] = ("| Package | Update | Change |\n|---|---|---|\n| [grafana/grafana](https://x) | minor | `13.2.6` → `13.3.2` |\n"
    "| docker.io/grafana/k6 | minor | `1.7.1` → `1.8.3` |\n| nginx | digest | `b4bbd2e` → `c437b7c` |\n\n### Release Notes\n| x | major | `1` → `2` |\n")
mv2 = pr(5, "observability"); mv2["body"] = "| Package | Update | Change |\n|---|---|---|\n| grafana/grafana | minor | `13.2.6` → `13.3.2` |\n"
fixture(infra=[mv1], platform=[mv2])
check("moves: each row's package, from and to, once - a digest row's too (its 7 hex digits); a table in the release notes left out",
      run("moves", "observability"), (0, "grafana/grafana 13.2.6 13.3.2\ngrafana/k6 1.7.1 1.8.3\nnginx b4bbd2e c437b7c digest"))
check("moves: a unit not open", run("moves", "nope"), (1, "NO UNIT nope"))
check("a command it does not take - noticed, apply and notes among them (no notice any more; missing release notes never "
      "stop a unit, operator 2026-11-25)", (run("apply")[0], run("noticed", "postgresql-19.x")[0], run("notes", "istiod-2.x")[0]),
      (2, 2, 2))
fixture(infra=[pr(1, "wave-patches"), pr(2, "istio", "veto"), pr(3, "observability", "upgrade-blocked", "veto")])
check("held: nothing holds a unit by a label (no veto, no blocked state) - nothing for each; an unknown one said",
      (run("held", "wave-patches"), run("held", "istio"), run("held", "observability"), run("held", "nope")),
      ((0, ""), (0, ""), (0, ""), (1, "NO UNIT nope")))
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
fixture(infra=[pr(1, "test-istio-1.32", "agent-fixed")])
check("a test environment's unit labelled agent-fixed (by a hand - the test path has no fix): merged at once as a test "
      "unit (the test environment its own proof)", run("pick"), (0, "test test-istio-1.32 minor"))
# replenish: the dashboards hold every update for approval; one unit's box ticked when nothing open is left to pick
check("the preset holds every update on the dashboard for approval (replenish's premise)",
      json.load(open("renovate/upgrade-cycle.json")).get("dependencyDashboardApproval"), True)
def patches():
    try:
        return [json.loads(x) for x in open(os.path.join(W, "patches.jsonl")).read().splitlines()]
    except OSError:
        return []
def ticked(repo):  # the units whose box is ticked on that repo's dashboard now
    fx = json.load(open(os.path.join(W, "fixture.json")))
    body = next(i for i in fx[f"/repos/schnappy/{repo}/issues"] if i.get("title") == DASH_TITLE)["body"]
    return sorted(m.split("approve-branch=renovate/")[1].split(" ")[0] for m in body.splitlines() if "- [x] <!--" in m)
PENDING = {"infra": ("wave-patches", "istio-1.33", "kubernetes-1.37", "kubernetes-1.36", "manual-woodpecker"),
           "platform": ("kubernetes-1.36", "kubernetes-1.37"), "ops": ("istio-1.33", "wave-patches")}
fixture(infra=[pr(1, "observability")], boxes=PENDING)
check("replenish: a unit to pick is open - nothing asked of Renovate", (run("replenish"), patches()), ((0, "OPEN"), []))
fixture(boxes=PENDING)
check("replenish: nothing open - the pick's first among the waiting (wave-patches) ticked on every dashboard listing it, "
      "as the bot, and nothing else", (run("replenish"), ticked("infra"), ticked("ops"), ticked("platform"),
                                        sorted(p["path"] for p in patches())),
      ((0, "APPROVED wave-patches infra,ops"), ["wave-patches"], ["wave-patches"], [],
       ["/repos/schnappy/infra/issues/44", "/repos/schnappy/ops/issues/56"]))
before = board(PENDING["infra"])
check("replenish: the body written whole, only the one box changed",
      json.load(open(os.path.join(W, "fixture.json")))["/repos/schnappy/infra/issues"][0]["body"],
      before.replace("- [ ] <!-- approve-branch=renovate/wave-patches -->", "- [x] <!-- approve-branch=renovate/wave-patches -->"))
fixture(boxes={"infra": ("kubernetes-1.37", "kubernetes-1.36", "manual-woodpecker"), "platform": ("kubernetes-1.37", "kubernetes-1.36")})
check("replenish: a step waits for the lower one waiting - kubernetes-1.36 asked, never 1.37 first; a manual- unit never",
      (run("replenish"), ticked("infra"), ticked("platform")), ((0, "APPROVED kubernetes-1.36 infra,platform"),
                                                               ["kubernetes-1.36"], ["kubernetes-1.36"]))
fixture(infra=[pr(2, "kubernetes-1.36", renovate=False)], boxes={"infra": ("kubernetes-1.37", "observability")})
check("replenish: a lower step open but never picked (unlabelled) still holds the higher - the next unit asked instead",
      run("replenish"), (0, "APPROVED observability infra"))
fixture(boxes={"infra": ("scylladb-2026.2", "test-scylladb-2026.2", "wave-patches")})
check("replenish: a test environment's unit before its twin, before the wave", run("replenish"),
      (0, "APPROVED test-scylladb-2026.2 infra"))
fixture(boxes={"infra": ("manual-woodpecker",)})
check("replenish: nothing to ask (a manual- unit alone) - nothing ticked", (run("replenish"), patches()), ((0, "NOTHING"), []))
fixture(boxes=PENDING, dashboard_labels=("upgrades-paused",))
check("replenish: the kill switch - nothing asked", (run("replenish"), patches()), ((0, "PAUSED"), []))
fixture(boxes=PENDING, patch_fails=True)
check("replenish: the dashboard's edit refused - not read (exit 1), never 'approved'", run("replenish")[0], 1)
print("upgrade-units: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
