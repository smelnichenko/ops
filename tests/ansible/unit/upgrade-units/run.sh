#!/bin/bash
# scripts/upgrade-units.py - the upgrade cycle's pick of the night's Renovate unit - against a throwaway Forgejo API (a
# local server, a process of its own, its answers from the case's fixture, paged as Forgejo pages): units grouped by
# branch across infra, platform and ops, their kind (major by label, wave-patches a patch); the pick's order -
# wave-patches, the family minors in order, other minors, majors; blocked and vetoed units left out; a major noticed,
# applied only after its 24 h (an unvetoed one), the waiting one before a new notice; the kill switch on the dashboard
# issue; more than one page of pull requests; Forgejo unreachable - not read, never NOTHING.
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
        if data is None:
            self.send_response(404); self.end_headers(); self.wfile.write(b'{"message":"not found"}'); return
        if isinstance(data, list):
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
def pr(number, unit, *labels):
    return {"number": number, "head": {"ref": f"renovate/{unit}"}, "labels": [{"name": x} for x in labels]}
def fixture(infra=(), platform=(), ops=(), comments=None, dashboard_labels=()):
    fx = {"/repos/schnappy/infra/pulls": list(infra), "/repos/schnappy/platform/pulls": list(platform),
          "/repos/schnappy/ops/pulls": list(ops),
          "/repos/schnappy/ops/issues": [{"title": "Upgrade cycle - Renovate's dashboard (label upgrades-paused: the cycle stops)",
                                          "labels": [{"name": x} for x in dashboard_labels]}]}
    for (repo, n), bodies in (comments or {}).items():
        fx[f"/repos/schnappy/{repo}/issues/{n}/comments"] = [{"body": b} for b in bodies]
    for repo, prs in (("infra", infra), ("platform", platform), ("ops", ops)):
        for p in prs:
            fx.setdefault(f"/repos/schnappy/{repo}/issues/{p['number']}/comments", [])
    json.dump(fx, open(os.path.join(W, "fixture.json"), "w"))
NOW = "2026-11-20T03:00:00Z"
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
fixture(infra=[pr(2, "observability"), pr(3, "istio"), pr(4, "cert-manager-1.x"), pr(5, "argocd")])
check("the family minors in their order (istio before observability), before any other minor", run("pick"),
      (0, "prove istio minor"))
fixture(infra=[pr(4, "cert-manager-1.x"), pr(6, "valkey-9.x")])
check("other minors by name when no family's is open", run("pick"), (0, "prove cert-manager-1.x minor"))
fixture(infra=[pr(1, "wave-patches", "upgrade-blocked"), pr(2, "istio", "veto"), pr(3, "observability")])
check("a blocked unit and a vetoed one left out", run("pick"), (0, "prove observability minor"))
fixture(infra=[pr(1, "wave-patches")], dashboard_labels=["upgrades-paused"])
check("the kill switch on the dashboard issue: paused, nothing picked", run("pick"), (0, "PAUSED"))
fixture(infra=[pr(3, "postgresql-19.x", "major")])
check("a major without its notice: proven, then noticed", run("pick"), (0, "notice postgresql-19.x major"))
check("noticed: none yet", run("noticed", "postgresql-19.x"), (0, "NONE"))
fixture(infra=[pr(3, "postgresql-19.x", "major")], comments={("infra", 3): ["looks fine", "UPGRADE NOTICE 2026-11-19T04:00:00Z - applies after"]})
check("a major noticed 23 h ago: still in its 24 h - nothing", run("pick"), (0, "NOTHING"))
check("noticed: the notice's time", run("noticed", "postgresql-19.x"), (0, "2026-11-19T04:00:00Z"))
fixture(infra=[pr(3, "postgresql-19.x", "major")], comments={("infra", 3): ["UPGRADE NOTICE 2026-11-19T02:59:00Z"]})
check("a major noticed 24 h ago, unvetoed: applied", run("pick"), (0, "apply postgresql-19.x major"))
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
print("upgrade-units: " + ("ALL-PASS" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
PYCHECK
