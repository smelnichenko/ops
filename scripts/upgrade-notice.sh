#!/usr/bin/env bash
# The upgrade cycle's notices (docs/plans/120-automated-upgrade-cycle.md) - each posted to production's Alertmanager as
# an UpgradeCycle alert, which its own route mails to the single admin address, once, with no "resolved" mail
# (platform: alertmanager-configmap's email-notice). A kind is a severity and a lifetime:
#   applied         info      1 h   a patch or minor applied (the operator asked for one after each)
#   veto            warning  24 h   a major's notice: what, the proof, when it applies - a veto stops it
#   blocked         warning   1 h   a unit red after its fix: it waits, the next unit goes next night
#   one-way-failed  critical  7 d   a one-way change failed: its backup and restore steps - the critical route repeats it
#                                   hourly until resolved; Alertmanager unreachable (the cluster it runs in broken), it
#                                   goes straight out by the same sender (Resend's SMTP, alerts@pmon.dev) to the same
#                                   address (infra's alertEmailTo)
#
# Usage: scripts/upgrade-notice.sh <kind> <unit> <summary> [<details file>]
# Env:   UPGRADE_NOTICE_DRY=1  print what would be posted (and mailed), send nothing
#        UPGRADE_NOTICE_HOST   the host Alertmanager is reached through (default ten)
#        RESEND_API_KEY        the direct mail's SMTP password (ops .env, loaded by task)
#        UPGRADE_NOTICE_INFRA_VALUES  where the admin address is read (default ../infra's production observability values)
set -euo pipefail
export LC_ALL=C
kind=${1:-}; unit=${2:-}; summary=${3:-}; details_file=${4:-}
case "$kind" in
  applied) severity=info; hours=1 ;;
  veto) severity=warning; hours=24 ;;
  blocked) severity=warning; hours=1 ;;
  one-way-failed) severity=critical; hours=168 ;;
  *) echo "REFUSED: upgrade-notice.sh <applied|veto|blocked|one-way-failed> <unit> <summary> [<details file>] - not '$kind'"; exit 2 ;;
esac
[[ $unit =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "REFUSED: '$unit' is no unit's name"; exit 2; }
[ -n "$summary" ] || { echo "REFUSED: a notice says what it is about (its summary)"; exit 2; }
details=""
if [ -n "$details_file" ]; then
  [ -r "$details_file" ] || { echo "REFUSED: $details_file not readable"; exit 2; }
  details=$(head -c 3000 "$details_file")
fi
ops=$(cd "$(dirname "$0")/.." && pwd)
host=${UPGRADE_NOTICE_HOST:-ten}
end=$(date -u -d "+${hours} hours" '+%Y-%m-%dT%H:%M:%SZ')
args=(amtool alert add "alertname=UpgradeCycle" "kind=$kind" "unit=$unit" "severity=$severity"
      "--annotation=summary=$summary" "--annotation=description=$details" "--end=$end"
      "--alertmanager.url=http://localhost:9093")
remote="kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -c alertmanager --$(printf ' %q' "${args[@]}")"

direct() {
  # the same sender and address Alertmanager uses, not through it
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

if [ -n "${UPGRADE_NOTICE_DRY:-}" ]; then
  echo "DRY: ssh $host $remote"
  [ "$kind" != one-way-failed ] || direct
  exit 0
fi
if ssh -o ConnectTimeout=15 -o BatchMode=yes "$host" "$remote"; then
  echo "POSTED $kind $unit (Alertmanager mails it)"
  exit 0
fi
echo "Alertmanager not reached through $host"
if [ "$kind" = one-way-failed ]; then
  direct
else
  exit 1
fi
