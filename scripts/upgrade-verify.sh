#!/usr/bin/env bash
# The upgrade cycle's check after an apply (and, settle 0 and hold 0, its look at production before one): production
# settled and quiet - read only, through ten. Preview environments (preview-env=true: a pull request's, broken or not)
# are no part of production's state - their apps, the pods in their namespaces, alerts from there.
#   settle  within UPGRADE_VERIFY_SETTLE minutes: every Argo app Synced and Healthy, its last operation Succeeded (or none),
#           every running pod ready - and, given the merge's commits (UPGRADE_VERIFY_REVISIONS), every app tracking
#           infra's or platform's main synced to them or later (Argo polls the repos: before it has, the state it shows
#           is the one before the merge - "settled" on that was no check of the apply); every app compared against its
#           spec as it stands (a child app's chart moved by the merge shows its old "Synced" until it compares again)
#           and none stalled (an automated sync Argo will not start again: said, never synced from here); with hold
#           0, no critical alert firing either - one look before an apply (settle 0), two in a row when it waits for
#           Argo (settle > 0: a look between a compare and its sync is no settle)
#   hold    then for UPGRADE_VERIFY_HOLD minutes, every UPGRADE_VERIFY_POLL seconds: still so, and no critical alert firing
#           (Watchdog aside, and the cycle's own UpgradeCycle page: an open one-way failure is the runner's to refuse on,
#           never every later apply's verify - each failed and paged again, a cascade) - one thing wrong for
#           UPGRADE_VERIFY_STREAK looks in a row (an app's rollout by CD within the hour is not the apply failing)
# Usage: scripts/upgrade-verify.sh            exit 0 settled and quiet, 1 what is not (said)
# Env:   UPGRADE_VERIFY_SETTLE (30), UPGRADE_VERIFY_HOLD (60), UPGRADE_VERIFY_POLL (60), UPGRADE_VERIFY_STREAK (10),
#        UPGRADE_VERIFY_HOST (ten), UPGRADE_VERIFY_REVISIONS ("infra=<sha> platform=<sha>": the merge's commits on main),
#        UPGRADE_VERIFY_REPOS (the directory holding the infra and platform checkouts - default ops' parent)
set -uo pipefail
export LC_ALL=C
host=${UPGRADE_VERIFY_HOST:-ten}
settle=${UPGRADE_VERIFY_SETTLE:-30}; hold=${UPGRADE_VERIFY_HOLD:-60}; poll=${UPGRADE_VERIFY_POLL:-60}
streak=${UPGRADE_VERIFY_STREAK:-10}
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
        try:
            return subprocess.run(["git", "-C", d, *a], capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL,
                                  env={**os.environ, "GIT_TERMINAL_PROMPT": "0"}).returncode == 0
        except subprocess.TimeoutExpired:
            return False
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
def srcs(obj):  # an Application spec's source(s), or its status.sync.comparedTo's, as a list
    return obj.get("sources") or ([obj["source"]] if obj.get("source") else [])
def empty(v):
    if isinstance(v, bool):
        return v is False
    if isinstance(v, (int, float)):
        return v == 0
    return v is None or (isinstance(v, (dict, list, str)) and len(v) == 0)
def without_empty(v):
    """A spec without the empty fields Go's omitempty leaves out of comparedTo (the copy's argo-settled.py, its twin);
    Helm's values compared as they are."""
    if isinstance(v, dict):
        kept = {k: (x if k in ("valuesObject", "values") else without_empty(x)) for k, x in v.items()}
        # Helm's values as written (false and 0 are values there), the key itself dropped when empty as omitempty does
        return {k: x for k, x in kept.items() if not empty(x) or (k in ("valuesObject", "values") and x not in ("", None, {}))}
    if isinstance(v, list):
        return [without_empty(x) for x in v]
    return v
def stalled(a):
    spec, st = a.get("spec") or {}, a.get("status") or {}
    auto, op = (spec.get("syncPolicy") or {}).get("automated"), st.get("operationState") or {}
    return (auto is not None and auto.get("enabled") is not False and (st.get("sync") or {}).get("status") == "OutOfSync"
            and a.get("operation") is None and op.get("phase") == "Succeeded" and not op.get("syncResult")
            and ((op.get("operation") or {}).get("initiatedBy") or {}).get("automated") is True)
preview = {((a.get("spec") or {}).get("destination") or {}).get("namespace") for a in apps["items"]
           if (a["metadata"].get("labels") or {}).get("preview-env") == "true"} - {None, ""}
bad = []
for a in apps["items"]:
    if (a["metadata"].get("labels") or {}).get("preview-env") == "true":
        continue  # a pull request's preview environment: no part of production
    st = a.get("status") or {}
    sync, health = (st.get("sync") or {}).get("status"), (st.get("health") or {}).get("status")
    op = (st.get("operationState") or {}).get("phase", "")
    if sync != "Synced" or health != "Healthy" or op not in ("Succeeded", ""):
        bad.append(f"app {a['metadata']['name']} {sync} {health} {op or '-'}" + (" STALLED (Argo will not sync it again: "
                                                                                 "sync it by hand)" if stalled(a) else ""))
    spec = a.get("spec") or {}
    if without_empty(srcs((st.get("sync") or {}).get("comparedTo") or {})) != without_empty(srcs(spec)):
        bad.append(f"app {a['metadata']['name']} compared against an older spec")
    sources = spec.get("sources") or ([spec["source"]] if spec.get("source") else [])
    synced = (st.get("sync") or {}).get("revisions") or [(st.get("sync") or {}).get("revision")]
    for i, src in enumerate(sources):
        repo = (src.get("repoURL") or "").removeprefix("https://git.pmon.dev/schnappy/").removesuffix(".git")
        if repo in REVS and src.get("targetRevision", "HEAD") in ("main", "HEAD", ""):
            rev = synced[i] if i < len(synced) else None
            if not rev or not contains(repo, REVS[repo], rev):
                bad.append(f"app {a['metadata']['name']} {repo} at {(rev or 'none')[:12]}, not yet the merge's {REVS[repo][:12]}")
for p in pods["items"]:
    if (p.get("status") or {}).get("phase") != "Running" or p["metadata"].get("namespace") in preview:
        continue
    # its containers and its native sidecars (init containers restarting Always - Istio's istio-proxy when native)
    sidecars = {c.get("name") for c in (p.get("spec") or {}).get("initContainers") or [] if c.get("restartPolicy") == "Always"}
    unready = [c["name"] for c in (p["status"].get("containerStatuses") or [])
               + [i for i in p["status"].get("initContainerStatuses") or [] if i.get("name") in sidecars] if not c.get("ready")]
    if unready:
        bad.append(f"pod {p['metadata']['namespace']}/{p['metadata']['name']} unready: {', '.join(unready)}")
if os.environ["CRIT"]:
    for al in alerts or []:
        name = (al.get("labels") or {}).get("alertname")
        if name not in ("Watchdog", "UpgradeCycle") and (al.get("labels") or {}).get("namespace") not in preview:
            bad.append(f"critical alert {name}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}

up() { local u; read -r u _ < "${UPGRADE_VERIFY_UPTIME:-/proc/uptime}"; echo "${u%.*}"; }
subject() {  # what a complaint is about: "app <name>", "pod <ns>/<owner>" (a ReplicaSet's or a StatefulSet's pods), "critical alert <name>", the line else
  case "$1" in
    "app "*) cut -d' ' -f1-2 <<< "$1" ;;
    "pod "*) local p=${1#pod }; p=${p%% *}
      # Kubernetes names a pod's random parts from its own alphabet (no vowels, no 0, 1, 3): a ReplicaSet's pod
      # <name>-<8-10 of it>-<5 of it>, a DaemonSet's or a Job's <name>-<5 of it>, a StatefulSet's <name>-<number>
      local a=bcdfghjklmnpqrstvwxz2456789
      if [[ $p =~ ^(.+)-[$a]{8,10}-[$a]{5}$ ]]; then echo "pod ${BASH_REMATCH[1]}"
      elif [[ $p =~ ^(.+)-([0-9]+|[$a]{5})$ ]]; then echo "pod ${BASH_REMATCH[1]}"
      else echo "pod $p"; fi ;;
    "critical alert "*) cut -d' ' -f1-3 <<< "$1" ;;
    *) echo "$1" ;;
  esac
}
crit=""; [ "$hold" -gt 0 ] || crit=critical  # with no hold the alerts are part of the settle
need=1; [ "$hold" -gt 0 ] || [ "$settle" -eq 0 ] || need=2  # waiting for Argo with no hold: two clean looks in a row
end=$(( $(up) + settle * 60 )); clean=0
while :; do
  if out=$(look $crit); then
    clean=$((clean + 1)); [ "$clean" -ge "$need" ] && break
  else
    clean=0
    if [ "$(up)" -ge "$end" ]; then echo "NOT SETTLED after $settle min:"; echo "$out"; exit 1; fi
  fi
  sleep "$poll"
done
[ "$hold" -gt 0 ] || { echo "SETTLED AND QUIET ($need look$([ "$need" = 1 ] || echo "s in a row"))"; exit 0; }
echo "SETTLED"
end=$(( $(up) + hold * 60 ))
declare -A seen=()
while [ "$(up)" -lt "$end" ]; do
  sleep "$poll"
  out=$(look critical) && { seen=(); continue; }
  # what is wrong now, counted in a row by its subject - the app, the pod's owner (a pod recreated under a new name is
  # the same failure), the alert - whatever its words this look; gone from a look, its count starts again
  declare -A now=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key=$(subject "$line")
    now[$key]=$(( ${seen[$key]:-0} + 1 ))  # from the last look's count: once a look, however many of its pods are wrong
    if [ "${now[$key]}" -ge "$streak" ]; then echo "NOT QUIET during the hold ($streak looks in a row):"; echo "$out"; exit 1; fi
  done <<< "$out"
  seen=(); for k in "${!now[@]}"; do seen[$k]=${now[$k]}; done
  unset now
done
echo "SETTLED AND QUIET for $hold min"
