#!/bin/bash
# scripts/production-report.py - the hourly report's facts - against an ssh that answers as ten would (kubectl and the
# Alertmanager/Prometheus reads it is given) and a throwaway Forgejo API: an alert with its subject, start and silence;
# the pending alerts by name; a Running pod with a container not ready, a Pending pod and a crash-looping one counted,
# finished ones (Succeeded, a Failed one a shutdown left) not; Argo applications not Synced or not Healthy counted; the
# open PRs of the live repos (an archived one left out). ten not answering: NOT READ and exit 1, never "0 not ready".
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'kill "$(cat "$W/pid" 2> /dev/null)" 2> /dev/null; rm -rf "$W"' EXIT
cat > "$W/server.py" <<'SERVER'
import http.server, json, os, sys, urllib.parse
W = sys.argv[1]
FX = {"/orgs/schnappy/repos": [{"full_name": "schnappy/infra", "name": "infra", "archived": False},
                               {"full_name": "schnappy/old", "name": "old", "archived": True}],
      "/repos/schnappy/infra/pulls": [{"number": 64, "user": {"login": "renovate-bot"}, "created_at": "2026-11-23T10:00:00Z", "title": "update wave"}],
      "/repos/schnappy/old/pulls": [{"number": 1, "user": {"login": "x"}, "created_at": "2026-01-01T00:00:00Z", "title": "stale"}]}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        open(os.path.join(W, "auth"), "a").write((self.headers.get("Authorization") or "") + "\n")
        data = FX.get(urllib.parse.urlparse(self.path).path.removeprefix("/api/v1"))
        body = json.dumps(data if data is not None else {}).encode()
        self.send_response(200 if data is not None else 404); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port.tmp"), "w").write(str(s.server_port)); os.rename(os.path.join(W, "port.tmp"), os.path.join(W, "port"))
s.serve_forever()
SERVER
python3 "$W/server.py" "$W" & echo $! > "$W/pid"
for _ in $(seq 50); do [ -e "$W/port" ] && break; sleep 0.1; done
[ -e "$W/port" ] || { echo "production-report: the local server did not start"; exit 1; }
mkdir -p "$W/bin"
cat > "$W/bin/ssh" <<'FAKESSH'
#!/usr/bin/env python3
import json, os, sys
cmd = sys.argv[-1]
if os.environ.get("TEN_DOWN"):
    print("ssh: connect to host 192.168.11.2 port 22: No route to host", file=sys.stderr); sys.exit(255)
def pod(phase, ready=(True,), waiting=None):
    cs = [{"ready": r, "state": {"waiting": {"reason": waiting}} if waiting else {"running": {}}} for r in ready]
    return {"status": {"phase": phase, "containerStatuses": cs}}
if "api/v2/alerts" in cmd:
    print(json.dumps([{"labels": {"alertname": "Watchdog", "severity": "none"}, "startsAt": "2026-11-23T05:32:00Z", "status": {"state": "active"}},
                      {"labels": {"alertname": "PodRestartingFrequently", "severity": "warning", "namespace": "schnappy-production"},
                       "startsAt": "2026-11-23T05:39:00Z", "status": {"state": "active", "silencedBy": ["s1"]}}]))
elif "api/v1/query" in cmd:
    print(json.dumps({"data": {"result": [{"metric": {"alertname": "ScyllaBackupNeverSucceeded"}}, {"metric": {"alertname": "ScyllaBackupNeverSucceeded"}}]}}))
elif "get pods" in cmd:
    print(json.dumps({"items": [pod("Running"), pod("Running", (True, False)), pod("Pending", ()), pod("Running", (False,), "CrashLoopBackOff"),
                                pod("Succeeded", (False,)), pod("Failed", (False,)), pod("Running", (True, True))]}))
elif "get applications" in cmd:
    print(json.dumps({"items": [{"status": {"sync": {"status": "Synced"}, "health": {"status": "Healthy"}}},
                                {"status": {"sync": {"status": "OutOfSync"}, "health": {"status": "Healthy"}}},
                                {"status": {"sync": {"status": "Synced"}, "health": {"status": "Progressing"}}}]}))
else:
    print("unexpected command: " + cmd, file=sys.stderr); sys.exit(2)
FAKESSH
chmod +x "$W/bin/ssh"
W=$W PORT=$(cat "$W/port") python3 - <<'PYCHECK'
import os, subprocess, sys
W, PORT = os.environ["W"], os.environ["PORT"]
fails = 0
def check(name, got, want):
    global fails
    fails += got != want
    print(("PASS " if got == want else "FAIL ") + name + ("" if got == want else f": got {got!r}, want {want!r}"))
def run(**env):
    e = {**os.environ, "PATH": os.path.join(W, "bin") + ":" + os.environ["PATH"], "RENOVATE_TOKEN": "BOT",
         "UPGRADE_FORGEJO_URL": f"http://127.0.0.1:{PORT}/api/v1", **env}
    r = subprocess.run([sys.executable, "scripts/production-report.py"], capture_output=True, text=True, env=e, timeout=60)
    return r.returncode, r.stdout.splitlines()
rc, out = run()
check("the alerts: each with its subject, start and silence; their count; Prometheus's pending ones by name, once each",
      [l for l in out[1:5]], ["- Watchdog [none]  since 2026-11-23T05:32Z, active",
                              "- PodRestartingFrequently [warning] schnappy-production since 2026-11-23T05:39Z, active, silenced",
                              "2 active", "pending in Prometheus: ScyllaBackupNeverSucceeded"])
check("readiness: a container not ready, a Pending pod and a crash-looping one counted - finished pods not; Argo's out of sync and not healthy counted",
      "not-ready pods 3, argo apps off 2" in out, True)
check("the open PRs of the live repos (an archived one left out), read as the bot", (out[-2:], set(open(os.path.join(W, "auth")).read().split()) - {""}),
      (["infra #64 renovate-bot 2026-11-23T10:00 update wave", "1 repos, 1 open PRs"], {"token", "BOT"}))
check("every part read: exit 0", rc, 0)
rc, out = run(TEN_DOWN="1")
check("ten not answering: alerts and readiness NOT READ (never a quiet 0), exit 1 - the PRs still read",
      (rc, sum(1 for l in out if l.startswith("NOT READ")), any("not-ready pods" in l for l in out), "1 repos, 1 open PRs" in out),
      (1, 2, False, True))
print("production-report: ALL-PASS" if fails == 0 else f"production-report: {fails} FAILED")
sys.exit(1 if fails else 0)
PYCHECK
