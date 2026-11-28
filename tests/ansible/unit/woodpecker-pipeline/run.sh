#!/bin/bash
# scripts/woodpecker-pipeline.sh against a throwaway Woodpecker API (a local server answering from a fixture): the steps
# listed with their states and exit codes; a step's log decoded whole; --done 0 on a final pipeline, 1 on a running one,
# 3 unreadable; a step it lacks refused (2); bad arguments refused (2); the token sent as a Bearer header - read from
# ops/.env when the environment has none - and on no command line (curl's header from a file descriptor).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'kill "$(cat "$W/pid" 2> /dev/null)" 2> /dev/null; rm -rf "$W"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
cat > "$W/server.py" <<'SERVER'
import base64, http.server, json, os, sys
W = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        open(os.path.join(W, "auth"), "a").write((self.headers.get("Authorization") or "") + "\n")
        fx = json.load(open(os.path.join(W, "fixture.json")))
        data = fx.get(self.path.removeprefix("/api/"))
        body = json.dumps(data).encode()
        self.send_response(200 if data is not None else 404); self.end_headers(); self.wfile.write(body)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(W, "port"), "w").write(str(s.server_address[1]))
s.serve_forever()
SERVER
python3 "$W/server.py" "$W" & echo $! > "$W/pid"
for _ in $(seq 50); do [ -s "$W/port" ] && break; sleep 0.1; done
URL="http://127.0.0.1:$(cat "$W/port")"
fixture() {  # fixture <status>
  python3 - "$W/fixture.json" "$1" <<'PYFX'
import base64, json, sys
log = [{"data": base64.b64encode(b"line one").decode()}, {"data": base64.b64encode("line two ✓".encode()).decode()}]
json.dump({"repos/lookup/schnappy/ops": {"id": 8},
           "repos/8/pipelines/1230": {"number": 1230, "status": sys.argv[2], "commit": "87437dc11a14abcd",
                                      "workflows": [{"children": [{"id": 1, "name": "git", "state": "success", "exit_code": 0},
                                                                  {"id": 2, "name": "ansible-lint", "state": "failure", "exit_code": 2}]}]},
           "repos/8/logs/1230/2": log}, open(sys.argv[1], "w"))
PYFX
}
fixture failure
run() { WOODPECKER_URL="$URL" WOODPECKER_API_TOKEN=tok-env scripts/woodpecker-pipeline.sh "$@" > "$W/out" 2> "$W/err"; echo $?; }
rc=$(run ops 1230)
check "the steps: the pipeline's status and commit, each step's state and exit code" "$rc|$(tr '\n' '|' < "$W/out")" \
  "0|pipeline 1230 failure 87437dc1|  git success exit=0|  ansible-lint failure exit=2|"
rc=$(run ops 1230 ansible-lint)
check "a step's log, whole, decoded" "$rc|$(tr '\n' '|' < "$W/out")" "0|line one|line two ✓|"
check "  the token as a Bearer header" "$(sort -u "$W/auth")" "Bearer tok-env"
rc=$(run ops 1230 no-such)
check "a step the pipeline lacks: refused (2), named" "$rc $(grep -c 'no step no-such' "$W/err")" "2 1"
check "--done: a final pipeline 0" "$(run ops 1230 --done)" "0"
fixture killed
check "  a killed one (canceled for a later push) 0 - final too" "$(run ops 1230 --done)" "0"
fixture running
check "  a running one 1" "$(run ops 1230 --done)" "1"
check "  a pipeline not read (none such) 3" "$(run ops 999 --done)" "3"
check "bad arguments refused (2): no pipeline, a pipeline not a number, a repo not a name" \
  "$(run ops) $(run ops abc) $(run 'Ops/x' 1)" "2 2 2"
# the token from ops/.env when the environment has none: a copy of the script beside its own .env
mkdir -p "$W/ops/scripts"; cp scripts/woodpecker-pipeline.sh "$W/ops/scripts/"; echo "WOODPECKER_API_TOKEN=tok-file" > "$W/ops/.env"
: > "$W/auth"; fixture success
rc=$(env -u WOODPECKER_API_TOKEN WOODPECKER_URL="$URL" "$W/ops/scripts/woodpecker-pipeline.sh" ops 1230 > /dev/null 2>&1; echo $?)
check "  the token from ops/.env when the environment has none" "$rc $(sort -u "$W/auth")" "0 Bearer tok-file"
rc=$(env -u WOODPECKER_API_TOKEN WOODPECKER_URL="$URL" bash -c 'rm -f "$0/ops/.env"; "$0/ops/scripts/woodpecker-pipeline.sh" ops 1230' "$W" > /dev/null 2>&1; echo $?)
check "  no token anywhere: not read (3)" "$rc" "3"
# never on a command line: curl's Authorization header from a file descriptor, the token's value nowhere in an argument
check "the token never on a command line: curl's header from a file descriptor, no -H naming the token" \
  "$(grep -c "curl -fsS --max-time 30 -H @<(printf 'Authorization: Bearer %s\\\\n' \"\$token\")" scripts/woodpecker-pipeline.sh) $(grep -cE -- "-H \"Authorization|-H 'Authorization" scripts/woodpecker-pipeline.sh)" "1 0"
echo "woodpecker-pipeline: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
