#!/usr/bin/env bash
# The upgrade cycle's check after an apply (docs/plans/120-automated-upgrade-cycle.md, part 2 step 7): production settled
# and quiet - read only, through ten.
#   settle  within UPGRADE_VERIFY_SETTLE minutes: every Argo app Synced and Healthy, its last operation Succeeded (or none),
#           every running pod ready
#   hold    then for UPGRADE_VERIFY_HOLD minutes, every UPGRADE_VERIFY_POLL seconds: still so, and no critical alert firing
#           (Watchdog aside, and the cycle's own UpgradeCycle page: an open one-way failure is the runner's to refuse on,
#           never every later apply's verify - each failed and paged again, a cascade)
# Usage: scripts/upgrade-verify.sh            exit 0 settled and quiet, 1 what is not (said)
# Env:   UPGRADE_VERIFY_SETTLE (30), UPGRADE_VERIFY_HOLD (60), UPGRADE_VERIFY_POLL (60), UPGRADE_VERIFY_HOST (ten)
set -uo pipefail
export LC_ALL=C
host=${UPGRADE_VERIFY_HOST:-ten}
settle=${UPGRADE_VERIFY_SETTLE:-30}; hold=${UPGRADE_VERIFY_HOLD:-60}; poll=${UPGRADE_VERIFY_POLL:-60}
for v in settle hold poll; do [[ ${!v} =~ ^[0-9]+$ ]] || { echo "REFUSED: $v '${!v}' - a whole number"; exit 2; }; done

# one look: what is not settled, one line each; nothing printed and exit 0 when all is. Python makes the reads itself:
# production's pod list is megabytes - through the environment it was "Argument list too long" (one variable's cap is
# 128 KiB), every look failed, and the check could never pass (2026-11-14)
look() {
  HOST="$host" CRIT="${1:-}" python3 -I - <<'PY'
import json, os, subprocess, sys
HOST = os.environ["HOST"]
def read(what, cmd):
    """The read's JSON - or, not read (ten away, kubectl failing, an answer that is no JSON), said, and this look fails."""
    try:
        r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", HOST, cmd], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=120)
        if r.returncode == 0:
            return json.loads(r.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    print(f"{what} not read")
    sys.exit(1)
apps = read("apps", "kubectl -n argocd get applications -o json")
pods = read("pods", "kubectl get pods -A -o json")
alerts = read("alerts", "kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -c alertmanager -- amtool alert query "
              "severity=critical -o json --alertmanager.url=http://localhost:9093")
bad = []
for a in apps["items"]:
    st = a.get("status") or {}
    sync, health = (st.get("sync") or {}).get("status"), (st.get("health") or {}).get("status")
    op = (st.get("operationState") or {}).get("phase", "")
    if sync != "Synced" or health != "Healthy" or op not in ("Succeeded", ""):
        bad.append(f"app {a['metadata']['name']} {sync} {health} {op or '-'}")
for p in pods["items"]:
    if (p.get("status") or {}).get("phase") != "Running":
        continue
    unready = [c["name"] for c in p["status"].get("containerStatuses") or [] if not c.get("ready")]
    if unready:
        bad.append(f"pod {p['metadata']['namespace']}/{p['metadata']['name']} unready: {', '.join(unready)}")
if os.environ["CRIT"]:
    for al in alerts or []:
        name = (al.get("labels") or {}).get("alertname")
        if name not in ("Watchdog", "UpgradeCycle"):
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
