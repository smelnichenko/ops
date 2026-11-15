#!/usr/bin/env bash
# The upgrade cycle's check after an apply (and, settle 0 and hold 0, its look at production before one): production
# settled and quiet - read only, through ten. Preview environments' apps (preview-env=true: a pull request's, broken or
# not) are no part of production's state.
#   settle  within UPGRADE_VERIFY_SETTLE minutes: every Argo app Synced and Healthy, its last operation Succeeded (or none),
#           every running pod ready - and, given the merge's commits (UPGRADE_VERIFY_REVISIONS), every app tracking
#           infra's or platform's main synced to them or later (Argo polls the repos: before it has, the state it shows
#           is the one before the merge - "settled" on that was no check of the apply); with hold 0, no critical alert
#           firing either (the one look before an apply)
#   hold    then for UPGRADE_VERIFY_HOLD minutes, every UPGRADE_VERIFY_POLL seconds: still so, and no critical alert firing
#           (Watchdog aside, and the cycle's own UpgradeCycle page: an open one-way failure is the runner's to refuse on,
#           never every later apply's verify - each failed and paged again, a cascade) - one thing wrong for
#           UPGRADE_VERIFY_STREAK looks in a row (an app's rollout by CD within the hour is not the apply failing)
# Usage: scripts/upgrade-verify.sh            exit 0 settled and quiet, 1 what is not (said)
# Env:   UPGRADE_VERIFY_SETTLE (30), UPGRADE_VERIFY_HOLD (60), UPGRADE_VERIFY_POLL (60), UPGRADE_VERIFY_STREAK (5),
#        UPGRADE_VERIFY_HOST (ten), UPGRADE_VERIFY_REVISIONS ("infra=<sha> platform=<sha>": the merge's commits on main),
#        UPGRADE_VERIFY_REPOS (the directory holding the infra and platform checkouts - default ops' parent)
set -uo pipefail
export LC_ALL=C
host=${UPGRADE_VERIFY_HOST:-ten}
settle=${UPGRADE_VERIFY_SETTLE:-30}; hold=${UPGRADE_VERIFY_HOLD:-60}; poll=${UPGRADE_VERIFY_POLL:-60}
streak=${UPGRADE_VERIFY_STREAK:-5}
for v in settle hold poll streak; do [[ ${!v} =~ ^[0-9]+$ ]] || { echo "REFUSED: $v '${!v}' - a whole number"; exit 2; }; done
[[ ${UPGRADE_VERIFY_REVISIONS:-} =~ ^(((infra|platform)=[0-9a-f]{40})( |$))*$ ]] \
  || { echo "REFUSED: UPGRADE_VERIFY_REVISIONS '${UPGRADE_VERIFY_REVISIONS:-}' - \"infra=<sha> platform=<sha>\""; exit 2; }
repos=${UPGRADE_VERIFY_REPOS:-$(cd "$(dirname "$0")/../.." && pwd)}

# one look: what is not settled, one line each; nothing printed and exit 0 when all is. Python makes the reads itself:
# production's pod list is megabytes - through the environment it was "Argument list too long" (one variable's cap is
# 128 KiB), every look failed, and the check could never pass (2026-11-14)
look() {
  HOST="$host" CRIT="${1:-}" REVS="${UPGRADE_VERIFY_REVISIONS:-}" REPOS="$repos" python3 -I - <<'PY'
import json, os, subprocess, sys
HOST = os.environ["HOST"]
REVS = dict(x.split("=") for x in os.environ["REVS"].split())
def contains(repo, want, rev):
    """rev (an app's synced commit) is want or later on the repo's history - the local checkout fetched when it lacks it"""
    d = os.path.join(os.environ["REPOS"], repo)
    def git(*a):
        return subprocess.run(["git", "-C", d, *a], capture_output=True, text=True).returncode == 0
    if not git("cat-file", "-e", f"{rev}^{{commit}}"):
        git("fetch", "-q", "origin", "main")
    return git("merge-base", "--is-ancestor", want, rev)
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
    if (a["metadata"].get("labels") or {}).get("preview-env") == "true":
        continue  # a pull request's preview environment: no part of production
    st = a.get("status") or {}
    sync, health = (st.get("sync") or {}).get("status"), (st.get("health") or {}).get("status")
    op = (st.get("operationState") or {}).get("phase", "")
    if sync != "Synced" or health != "Healthy" or op not in ("Succeeded", ""):
        bad.append(f"app {a['metadata']['name']} {sync} {health} {op or '-'}")
    spec = a.get("spec") or {}
    sources = spec.get("sources") or ([spec["source"]] if spec.get("source") else [])
    synced = (st.get("sync") or {}).get("revisions") or [(st.get("sync") or {}).get("revision")]
    for i, src in enumerate(sources):
        repo = (src.get("repoURL") or "").removeprefix("https://git.pmon.dev/schnappy/").removesuffix(".git")
        if repo in REVS and src.get("targetRevision", "HEAD") in ("main", "HEAD", ""):
            rev = synced[i] if i < len(synced) else None
            if not rev or not contains(repo, REVS[repo], rev):
                bad.append(f"app {a['metadata']['name']} {repo} at {(rev or 'none')[:12]}, not yet the merge's {REVS[repo][:12]}")
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
crit=""; [ "$hold" -gt 0 ] || crit=critical  # one look before an apply: the alerts are part of it
end=$(( $(up) + settle * 60 ))
while ! out=$(look $crit); do
  if [ "$(up)" -ge "$end" ]; then echo "NOT SETTLED after $settle min:"; echo "$out"; exit 1; fi
  sleep "$poll"
done
[ "$hold" -gt 0 ] || { echo "SETTLED AND QUIET (one look)"; exit 0; }
echo "SETTLED"
end=$(( $(up) + hold * 60 ))
declare -A seen=()
while [ "$(up)" -lt "$end" ]; do
  sleep "$poll"
  out=$(look critical) && { seen=(); continue; }
  # what is wrong now, counted in a row; gone from a look, its count starts again
  declare -A now=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    now[$line]=$(( ${seen[$line]:-0} + 1 ))
    if [ "${now[$line]}" -ge "$streak" ]; then echo "NOT QUIET during the hold ($streak looks in a row):"; echo "$out"; exit 1; fi
  done <<< "$out"
  seen=(); for k in "${!now[@]}"; do seen[$k]=${now[$k]}; done
  unset now
done
echo "SETTLED AND QUIET for $hold min"
