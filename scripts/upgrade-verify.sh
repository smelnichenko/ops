#!/usr/bin/env bash
# The upgrade cycle's check after an apply (docs/plans/120-automated-upgrade-cycle.md, part 2 step 7): production settled
# and quiet - read only, through ten.
#   settle  within UPGRADE_VERIFY_SETTLE minutes: every Argo app Synced and Healthy, its last operation Succeeded (or none),
#           every running pod ready
#   hold    then for UPGRADE_VERIFY_HOLD minutes, every UPGRADE_VERIFY_POLL seconds: still so, and no critical alert firing
#           (Watchdog aside)
# Usage: scripts/upgrade-verify.sh            exit 0 settled and quiet, 1 what is not (said)
# Env:   UPGRADE_VERIFY_SETTLE (30), UPGRADE_VERIFY_HOLD (60), UPGRADE_VERIFY_POLL (60), UPGRADE_VERIFY_HOST (ten)
set -uo pipefail
export LC_ALL=C
host=${UPGRADE_VERIFY_HOST:-ten}
settle=${UPGRADE_VERIFY_SETTLE:-30}; hold=${UPGRADE_VERIFY_HOLD:-60}; poll=${UPGRADE_VERIFY_POLL:-60}
for v in settle hold poll; do [[ ${!v} =~ ^[0-9]+$ ]] || { echo "REFUSED: $v '${!v}' - a whole number"; exit 2; }; done

# one look: what is not settled, one line each; nothing printed and exit 0 when all is
look() {
  local apps pods alerts
  apps=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$host" 'kubectl -n argocd get applications -o json') || { echo "apps not read"; return 1; }
  pods=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$host" 'kubectl get pods -A -o json') || { echo "pods not read"; return 1; }
  alerts=$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$host" 'kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -c alertmanager -- amtool alert query severity=critical -o json --alertmanager.url=http://localhost:9093') || { echo "alerts not read"; return 1; }
  APPS="$apps" PODS="$pods" ALERTS="$alerts" CRIT="${1:-}" python3 -I - <<'PY'
import json, os, sys
bad = []
for a in json.loads(os.environ["APPS"])["items"]:
    st = a.get("status") or {}
    sync, health = (st.get("sync") or {}).get("status"), (st.get("health") or {}).get("status")
    op = (st.get("operationState") or {}).get("phase", "")
    if sync != "Synced" or health != "Healthy" or op not in ("Succeeded", ""):
        bad.append(f"app {a['metadata']['name']} {sync} {health} {op or '-'}")
for p in json.loads(os.environ["PODS"])["items"]:
    if (p.get("status") or {}).get("phase") != "Running":
        continue
    unready = [c["name"] for c in p["status"].get("containerStatuses") or [] if not c.get("ready")]
    if unready:
        bad.append(f"pod {p['metadata']['namespace']}/{p['metadata']['name']} unready: {', '.join(unready)}")
if os.environ["CRIT"]:
    for al in json.loads(os.environ["ALERTS"] or "[]"):
        name = (al.get("labels") or {}).get("alertname")
        if name != "Watchdog":
            bad.append(f"critical alert {name}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}

up() { local u; read -r u _ < "${UPGRADE_VERIFY_UPTIME:-/proc/uptime}"; echo "${u%.*}"; }
end=$(( $(up) + settle * 60 ))
while ! out=$(look); do
  if [ "$(up)" -ge "$end" ]; then echo "NOT SETTLED after $settle min:"; echo "$out"; exit 1; fi
  sleep "$poll"
done
echo "SETTLED"
end=$(( $(up) + hold * 60 ))
while [ "$(up)" -lt "$end" ]; do
  sleep "$poll"
  out=$(look critical) || { echo "NOT QUIET during the hold:"; echo "$out"; exit 1; }
done
echo "SETTLED AND QUIET for $hold min"
