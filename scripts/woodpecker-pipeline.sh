#!/usr/bin/env bash
# woodpecker-pipeline.sh <repo> <pipeline> [<step> | --done] - a Woodpecker pipeline read through its API:
#   (no third argument)  the pipeline's status and commit, then each step: its name, its state, its exit code
#   <step>               that step's log, whole (the API's lines decoded)
#   --done               exit 0 once the pipeline is final (success, failure, error, killed), 1 while it is not - a waiter's
#                        condition; 3 when it cannot be read
# The repo by its name under schnappy (its id looked up); the token ops/.env's WOODPECKER_API_TOKEN (or the environment's),
# handed to curl on a file descriptor - never on a command line (ps shows those).
# Env: WOODPECKER_URL (https://ci.pmon.dev), WOODPECKER_API_TOKEN
set -euo pipefail
[ "$#" -ge 2 ] && [[ $1 =~ ^[a-z0-9-]+$ ]] && [[ $2 =~ ^[0-9]+$ ]] \
  || { echo "usage: woodpecker-pipeline.sh <repo> <pipeline> [<step> | --done]" >&2; exit 2; }
ops=$(cd "$(dirname "$0")/.." && pwd)
url=${WOODPECKER_URL:-https://ci.pmon.dev}
# (no .env: none - the check below says so; a failed read is never set -e's exit)
token=${WOODPECKER_API_TOKEN:-$({ sed -n 's/^WOODPECKER_API_TOKEN=//p' "$ops/.env" 2> /dev/null || true; } | head -1)}
[ -n "$token" ] || { echo "no WOODPECKER_API_TOKEN (ops/.env or the environment)" >&2; exit 3; }
api() { curl -fsS --max-time 30 -H @<(printf 'Authorization: Bearer %s\n' "$token") "$url/api/$1"; }
id=$(api "repos/lookup/schnappy/$1" | python3 -c 'import json, sys; print(json.load(sys.stdin)["id"])') \
  || { echo "repo schnappy/$1 not read from Woodpecker" >&2; exit 3; }
pipeline=$(api "repos/$id/pipelines/$2") || { echo "pipeline $2 of schnappy/$1 not read" >&2; exit 3; }
case "${3:-}" in
  "")
    python3 -c '
import json, sys
d = json.loads(sys.argv[1])
print("pipeline %s %s %s" % (d["number"], d["status"], d.get("commit", "")[:8]))
for w in d.get("workflows") or []:
    for s in w.get("children") or []:
        print("  %s %s exit=%s" % (s["name"], s["state"], s.get("exit_code")))' "$pipeline" ;;
  --done)
    python3 -c 'import json, sys; sys.exit(0 if json.loads(sys.argv[1])["status"] in ("success", "failure", "error", "killed") else 1)' "$pipeline" ;;
  *)
    sid=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
ids = [s["id"] for w in d.get("workflows") or [] for s in w.get("children") or [] if s["name"] == sys.argv[2]]
print(ids[0] if ids else "")' "$pipeline" "$3")
    [ -n "$sid" ] || { echo "no step $3 in pipeline $2 of schnappy/$1" >&2; exit 2; }
    api "repos/$id/logs/$2/$sid" | python3 -c '
import base64, json, sys
for e in json.load(sys.stdin) or []:
    sys.stdout.write(base64.b64decode(e.get("data") or b"").decode("utf-8", "replace") + "\n")' ;;
esac
