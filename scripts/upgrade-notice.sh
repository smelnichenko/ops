#!/usr/bin/env bash
# The upgrade cycle's notices - each posted to production's Alertmanager (its API, JSON - amtool refused a '"' in a
# summary, and the notice was lost) as an UpgradeCycle alert, which its own route mails to the single admin address,
# with no "resolved" mail (platform: alertmanager-configmap's email-notice). A kind is a severity and a lifetime:
#   applied         info      1 h   a patch or minor applied (the operator asked for one after each)
#   veto            warning  24 h   a major's notice: what, the proof, when it applies - a veto stops it
#   blocked         warning   1 h   a unit red after its fix, or a run that could not go on: said, the unit waits
#   one-way-failed  critical  7 d   a one-way change failed: its backup and restore steps - a PAGE: repeated hourly until
#                                   resolved, mailed straight out too (the same sender, Resend's SMTP alerts@pmon.dev, to
#                                   the same address, infra's alertEmailTo - Alertmanager may be what broke), and
#                                   recorded: the runner refuses while one is open
# Each notice carries a label of its own (notice=<time>-<pid>): a second one of a kind for a unit within the first's
# lifetime is a new alert, mailed - one label set the same was deduplicated. It starts now (amtool sent none: the mail
# said the notice started at its end).
#
# Usage: scripts/upgrade-notice.sh <applied|veto|blocked|one-way-failed> <unit> <summary> [<details file>]
#        scripts/upgrade-notice.sh resolve <unit>   a page ended (its fix done): ended now in Alertmanager, its record gone
#        scripts/upgrade-notice.sh repost           every open page posted again, its end a week on (Alertmanager keeps
#                                                    alerts in memory: a restart dropped them, and the page stopped)
#        scripts/upgrade-notice.sh open             the open pages' units, one a line
# Env:   UPGRADE_NOTICE_DRY=1  print what would be posted (and mailed), send nothing
#        UPGRADE_NOTICE_HOST   the host Alertmanager is reached through (default ten)
#        UPGRADE_PAGES         where the open pages are recorded (default ops' .copy/upgrade-pages)
#        RESEND_API_KEY        the direct mail's SMTP password (ops .env, loaded by task)
#        UPGRADE_NOTICE_INFRA_VALUES  where the admin address is read (default ../infra's production observability values)
set -euo pipefail
export LC_ALL=C
ops=$(cd "$(dirname "$0")/.." && pwd)
host=${UPGRADE_NOTICE_HOST:-ten}
pages=${UPGRADE_PAGES:-$ops/.copy/upgrade-pages}
usage="REFUSED: upgrade-notice.sh <applied|veto|blocked|one-way-failed> <unit> <summary> [<details file>] | resolve <unit> | repost | open"
remote="kubectl -n schnappy-infra exec -i deploy/schnappy-alertmanager -c alertmanager -- wget -qO- --header 'Content-Type: application/json' --post-file=/dev/stdin http://localhost:9093/api/v2/alerts"

post() {  # the alert's JSON on stdin, to Alertmanager's API through the host
  if [ -n "${UPGRADE_NOTICE_DRY:-}" ]; then echo "DRY: ssh $host $remote <<< $(cat)"; return 0; fi
  ssh -o ConnectTimeout=15 -o BatchMode=yes "$host" "$remote" > /dev/null
}

alert() {  # labels and annotations from the environment (never through a shell's quoting) - one alert's JSON
  python3 -I - <<'PY'
import json, os
labels = {k: os.environ[v] for k, v in (("alertname", "A_NAME"), ("kind", "A_KIND"), ("unit", "A_UNIT"),
                                          ("severity", "A_SEVERITY"), ("notice", "A_NOTICE"))}
print(json.dumps([{"labels": labels,
                   "annotations": {"summary": os.environ["A_SUMMARY"], "description": os.environ["A_DETAILS"]},
                   "startsAt": os.environ["A_START"], "endsAt": os.environ["A_END"]}]))
PY
}

direct() {  # the same sender and address Alertmanager uses, not through it
  local to values=${UPGRADE_NOTICE_INFRA_VALUES:-$ops/../infra/clusters/production/schnappy-observability/values.yaml}
  if [ -n "${UPGRADE_NOTICE_DRY:-}" ]; then echo "DRY: would mail $kind $unit to infra's alertEmailTo directly"; return 0; fi
  [ -n "${RESEND_API_KEY:-}" ] || { echo "NOT SENT: no RESEND_API_KEY for the direct mail"; return 1; }
  to=$(sed -n "s/^  alertEmailTo: *//p" "$values" 2> /dev/null | tr -d "\"'") || to=""
  [[ $to =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || { echo "NOT SENT: no admin address in $values (alertEmailTo)"; return 1; }
  TO="$to" SUBJECT="[UpgradeCycle] $kind: $unit - $summary" BODY="$summary"$'\n\n'"$details" python3 -I - <<'PY'
import os, smtplib, ssl
from email.message import EmailMessage
m = EmailMessage()
m["From"], m["To"], m["Subject"] = "alerts@pmon.dev", os.environ["TO"], os.environ["SUBJECT"]
m.set_content(os.environ["BODY"])
with smtplib.SMTP("smtp.resend.com", 587, timeout=30) as s:
    s.starttls(context=ssl.create_default_context())
    s.login("resend", os.environ["RESEND_API_KEY"])
    s.send_message(m)
print("MAILED directly")
PY
}

valid_unit() { [[ ${1:-} =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "REFUSED: '${1:-}' is no unit's name"; exit 2; }; }

case "${1:-}" in
  open)
    [ $# -eq 1 ] || { echo "$usage"; exit 2; }
    for f in "$pages"/*.json; do [ -e "$f" ] && basename "$f" .json; done
    exit 0 ;;
  repost)
    [ $# -eq 1 ] || { echo "$usage"; exit 2; }
    rc=0
    for f in "$pages"/*.json; do
      [ -e "$f" ] || continue
      # its end a week on from now: a page lasts until it is resolved
      new=$(END="$(date -u -d '+168 hours' '+%Y-%m-%dT%H:%M:%SZ')" python3 -I -c '
import json, os, sys
a = json.load(open(sys.argv[1])); a[0]["endsAt"] = os.environ["END"]; print(json.dumps(a))' "$f")
      if post <<< "$new"; then
        [ -n "${UPGRADE_NOTICE_DRY:-}" ] || printf '%s\n' "$new" > "$f"
        echo "REPOSTED $(basename "$f" .json)"
      else
        echo "NOT REPOSTED $(basename "$f" .json) - Alertmanager not reached through $host"; rc=1
      fi
    done
    exit "$rc" ;;
  resolve)
    [ $# -eq 2 ] || { echo "$usage"; exit 2; }
    valid_unit "$2"
    f=$pages/$2.json
    [ -e "$f" ] || { echo "REFUSED: no open page for $2"; exit 1; }
    ended=$(END="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" python3 -I -c '
import json, os, sys
a = json.load(open(sys.argv[1])); a[0]["endsAt"] = os.environ["END"]; print(json.dumps(a))' "$f")
    post <<< "$ended" || { echo "NOT RESOLVED: Alertmanager not reached through $host - the record kept"; exit 1; }
    [ -n "${UPGRADE_NOTICE_DRY:-}" ] || rm -f "$f"
    echo "RESOLVED $2"
    exit 0 ;;
esac

kind=${1:-}; unit=${2:-}; summary=${3:-}; details_file=${4:-}
case "$kind" in
  applied) severity=info; hours=1 ;;
  veto) severity=warning; hours=24 ;;
  blocked) severity=warning; hours=1 ;;
  one-way-failed) severity=critical; hours=168 ;;
  *) echo "$usage - not '$kind'"; exit 2 ;;
esac
valid_unit "$unit"
[ -n "$summary" ] || { echo "REFUSED: a notice says what it is about (its summary)"; exit 2; }
details=""
if [ -n "$details_file" ]; then
  [ -r "$details_file" ] || { echo "REFUSED: $details_file not readable"; exit 2; }
  details=$(tail -c 3000 "$details_file")  # a log's end: where it failed (its start is the window and the pick)
fi
json=$(A_NAME=UpgradeCycle A_KIND="$kind" A_UNIT="$unit" A_SEVERITY="$severity" \
       A_NOTICE="$(date -u +%Y%m%dT%H%M%SZ)-$$" A_SUMMARY="$summary" A_DETAILS="$details" \
       A_START="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" A_END="$(date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%SZ')" alert)

if [ "$kind" = one-way-failed ]; then
  # recorded first: the runner refuses while it is open, whether or not Alertmanager took it
  if [ -z "${UPGRADE_NOTICE_DRY:-}" ]; then mkdir -p "$pages"; printf '%s\n' "$json" > "$pages/$unit.json"; fi
  posted=0; mailed=0
  if post <<< "$json"; then echo "POSTED $kind $unit (Alertmanager pages it hourly)"; posted=1
  else echo "Alertmanager not reached through $host"; fi
  direct && mailed=1
  [ "$posted$mailed" != 00 ] || exit 1
  exit 0
fi
if post <<< "$json"; then
  echo "POSTED $kind $unit (Alertmanager mails it)"
  exit 0
fi
echo "NOT POSTED: Alertmanager not reached through $host"
exit 1
