#!/usr/bin/env bash
# Tests for the armed waiters (wait-until, forgejo-ci-wait). No network: forgejo-ci-wait is pointed at a fake API on
# loopback and a fake Woodpecker probe; HOME is a scratch directory holding a fake credential.
#
#   .claude/bin/tests/test-waiters.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/home/sm/scratch}/waiters.XXXXXX")
pids=()
cleanup() {
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
    rm -rf "$scratch"
}
trap cleanup EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1: $2"; fails=$((fails + 1)); }

export WAIT_UNTIL_POLL=1

# --- wait-until ------------------------------------------------------------------------------------------------------

# a condition given as separate arguments keeps them: a path with a space is one argument, not two
( sleep 2; touch "$scratch/a b" ) &
out=$("$here/wait-until" spaced 20 test -f "$scratch/a b" 2>&1); rc=$?
[[ $rc == 0 ]] && pass "argv condition keeps its quoting" || fail "argv condition keeps its quoting" "rc=$rc: $out"

# a single string is still a shell condition: pipes and quotes in it work
out=$("$here/wait-until" piped 10 "printf 'x y\n' | grep -q 'x y'" 2>&1); rc=$?
[[ $rc == 0 ]] && pass "string condition runs in a shell" || fail "string condition runs in a shell" "rc=$rc: $out"

# a pipe into grep -q holds on a match although grep's early exit SIGPIPEs the writer (no pipefail)
out=$("$here/wait-until" sigpipe 10 "seq 1 200000 | grep -q '^5$'" 2>&1); rc=$?
[[ $rc == 0 ]] && pass "a grep -q pipe holds despite SIGPIPE" || fail "a grep -q pipe holds despite SIGPIPE" "rc=$rc: $out"

# a probe that cannot run at all is a broken waiter, not a condition that has not held yet: it ends at once
start=$(date +%s)
out=$("$here/wait-until" broken 60 no-such-command-for-wait-until 2>&1); rc=$?
took=$(( $(date +%s) - start ))
[[ $rc == 3 && $took -lt 10 ]] && pass "an unrunnable probe ends at once" || fail "an unrunnable probe ends at once" "rc=$rc after ${took}s: $out"

# the same through a shell string (a quoting mistake yields 'command not found' inside bash -c)
out=$("$here/wait-until" broken-string 60 "no-such-command-for-wait-until --flag | grep -q x" 2>&1); rc=$?
[[ $rc == 3 ]] && pass "an unrunnable string probe ends at once" || fail "an unrunnable string probe ends at once" "rc=$rc: $out"

# a timeout says what the probe last printed, so a probe that could never hold is seen as one
# (the marker is computed, so the condition's own text, which the timeout also quotes, cannot supply it)
out=$("$here/wait-until" says-why 2 'echo said-$((6 * 7)); false' 2>&1); rc=$?
[[ $rc == 2 && $out == *said-42* ]] && pass "a timeout shows the probe's last output" || fail "a timeout shows the probe's last output" "rc=$rc: $out"

# --- forgejo-ci-wait -------------------------------------------------------------------------------------------------

mkdir -p "$scratch/home" "$scratch/api"
printf 'https://sm:fake-token@git.pmon.dev\n' > "$scratch/home/.git-credentials"
# the fake API answers /repos/o/r/commits/<sha>/status with whatever status.json holds at that moment
cat > "$scratch/api/serve.py" <<'EOF'
import http.server, json, os, sys
root = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if not self.path.endswith('/status'):
            self.send_response(404); self.end_headers(); return
        body = open(os.path.join(root, 'status.json'), 'rb').read()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a):
        pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
open(os.path.join(root, 'port'), 'w').write(str(s.server_port))
s.serve_forever()
EOF
status() {   # status <state> <updated_at>
    printf '{"state":"%s","statuses":[{"status":"%s","target_url":"http://ci/1","updated_at":"%s"}]}' "$1" "$1" "$2" > "$scratch/api/status.json"
}
none() { printf '{"state":"","statuses":[]}' > "$scratch/api/status.json"; }
none
python3 "$scratch/api/serve.py" "$scratch/api" & pids+=($!)
for _ in $(seq 50); do [[ -s $scratch/api/port ]] && break; sleep 0.1; done
export FORGEJO_API="http://127.0.0.1:$(cat "$scratch/api/port")"
export CI_WAIT_POLL=1
sha=0123456789abcdef0123456789abcdef01234567
ci_wait() { HOME="$scratch/home" "$here/forgejo-ci-wait" "$@"; }

# --fresh: a verdict posted before the waiter started is the PREVIOUS run's; only a later one counts
status failure "2026-01-01T00:00:00Z"
( sleep 3; status success "$(date -u +%Y-%m-%dT%H:%M:%SZ -d '+1 minute')" ) &
out=$(ci_wait --fresh o/r "$sha" 30 2>&1); rc=$?
[[ $rc == 0 && $out == *"CI success"* ]] && pass "--fresh waits past the previous run's verdict" || fail "--fresh waits past the previous run's verdict" "rc=$rc: $out"

# without --fresh a finished status is reported as it stands (a waiter armed after CI ended must not hang)
status failure "2026-01-01T00:00:00Z"
out=$(ci_wait o/r "$sha" 10 2>&1); rc=$?
[[ $rc == 1 ]] && pass "a standing verdict is reported at once" || fail "a standing verdict is reported at once" "rc=$rc: $out"

# a pipeline Woodpecker could not even create posts nothing on the commit: after the grace the waiter asks Woodpecker
none
cat > "$scratch/wp-errors" <<'EOF'
#!/usr/bin/env bash
# exactly what `sqlite3 -json` prints for the pipelines table (errors is a JSON string column)
printf '%s\n' '[{"number":343,"errors":"[{\"type\":\"generic\",\"message\":\"could not load config from forge: context deadline exceeded\",\"is_warning\":false,\"data\":null}]"}]'
EOF
chmod +x "$scratch/wp-errors"
start=$(date +%s)
out=$(CI_WAIT_NONE_GRACE=2 CI_WAIT_PIPELINE_ROWS="$scratch/wp-errors" ci_wait o/r "$sha" 60 2>&1); rc=$?
took=$(( $(date +%s) - start ))
[[ $rc == 1 && $out == *"could not load config"* && $took -lt 30 ]] && pass "a silent pipeline error ends the wait" || fail "a silent pipeline error ends the wait" "rc=$rc after ${took}s: $out"

# no status and no pipeline error: the waiter keeps waiting (a pipeline that is merely queued)
cat > "$scratch/wp-errors" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
out=$(CI_WAIT_NONE_GRACE=1 CI_WAIT_PIPELINE_ROWS="$scratch/wp-errors" ci_wait o/r "$sha" 4 2>&1); rc=$?
[[ $rc == 2 ]] && pass "no status and no error keeps waiting" || fail "no status and no error keeps waiting" "rc=$rc: $out"

# a queue of an hour and more is normal now: the default must outlast it
grep -qE '^repo=.*timeout=\$\{3:-(10800|[0-9]{6,})\}|timeout=\$\{timeout:-(10800|[0-9]{6,})\}' "$here/forgejo-ci-wait" \
    && pass "the default timeout outlasts a queued pipeline" || fail "the default timeout outlasts a queued pipeline" "default is under 3 h"

echo
(( fails == 0 )) && echo "all passed" || echo "$fails failed"
exit $(( fails > 0 ))
