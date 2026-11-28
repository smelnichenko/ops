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
#           UPGRADE_VERIFY_STREAK looks in a row (an app's rollout by CD within the hour is not the apply failing); at its
#           end no Job made during it failed for good (a CronJob's run on a moved image: a failed Job is no running pod,
#           and KubeJobFailed is a warning - no look sees it)
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
def pruning_note(st):
    """What Argo marks as needing pruning - a chart's leftovers (prune is off): named (the copy's argo-settled.py, its twin)."""
    left = [f"{r.get('kind')}/{r.get('name')}" for r in st.get("resources") or []
            if r.get("requiresPruning") and r.get("status") == "OutOfSync" and not r.get("hook")]  # a failed render: Unknown
    more = f" and {len(left) - 5} more" if len(left) > 5 else ""
    return f" - needs pruning: {', '.join(left[:5])}{more}" if left else ""
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
                                                                                 "sync it by hand)" if stalled(a) else "")
                   + pruning_note(st))
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
    # still waiting: what this look found, on one line - the console's progress (the operator 2026-11-22: an hour with
    # no line read as a hang); its time first, so never read as a complaint (the runner's test_only skips such lines)
    echo "$(date '+%T') not settled yet: ${out//$'\n'/; }"
  fi
  sleep "$poll"
done
[ "$hold" -gt 0 ] || { echo "SETTLED AND QUIET ($need look$([ "$need" = 1 ] || echo "s in a row"))"; exit 0; }
echo "SETTLED at $(date '+%T') - the hold: $hold min"
hold_from=$(date -u +%Y-%m-%dT%H:%M:%SZ)
end=$(( $(up) + hold * 60 )); note=$(( $(up) + 600 ))
declare -A seen=()
while [ "$(up)" -lt "$end" ]; do
  sleep "$poll"
  if out=$(look critical); then
    seen=()
    # every 10 minutes of the hold, one line: how far it is
    if [ "$(up)" -ge "$note" ]; then
      echo "$(date '+%T') quiet - $(( (hold * 60 - end + $(up)) / 60 )) of $hold min held"; note=$(( note + 600 ))
    fi
    continue
  fi
  # what is wrong now, counted in a row by its subject - the app, the pod's owner (a pod recreated under a new name is
  # the same failure), the alert - whatever its words this look; gone from a look, its count starts again
  declare -A now=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key=$(subject "$line")
    now[$key]=$(( ${seen[$key]:-0} + 1 ))  # from the last look's count: once a look, however many of its pods are wrong
    echo "$(date '+%T') not quiet (${now[$key]} of $streak looks in a row): $line"
    if [ "${now[$key]}" -ge "$streak" ]; then echo "NOT QUIET during the hold ($streak looks in a row):"; echo "$out"; exit 1; fi
  done <<< "$out"
  seen=(); for k in "${!now[@]}"; do seen[$k]=${now[$k]}; done
  unset now
done
# the Jobs made during the hold (a CronJob's run: etcd's snapshot, the restore checks' age, a backup and its prune): one
# that failed for good (its Failed condition, no success) is the hold's failure - the first runs of an image a unit moved
# (rclone in production's backup Jobs, the wave-patches review of 2026-11-28); a preview's aside; not read, not quiet.
# And k6's smoke run (the apps' PostSync hook, run by a sync during the hold - the runner's after a unit moving a hook's
# image, or CD's): k6 exits 0 when its push to Mimir fails, and K6SmokeMetricsMissing stays quiet after any earlier push
# that day - so each one that succeeded needs a sample of its run behind it, k6_checks_rate{source="k6"} in its namespace
# no older than its start (read from Mimir through the API server; the wave-patches review, 2026-11-28)
failed_jobs=$(HOST="$host" FROM="$hold_from" python3 -I - <<'PY_JOBS'
import calendar, json, os, subprocess, sys, time, urllib.parse
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", os.environ["HOST"]]
MIMIR = "/api/v1/namespaces/schnappy-infra/services/schnappy-mimir:9009/proxy/prometheus/api/v1/query?query="
def read(cmd):
    r = subprocess.run(SSH + [cmd], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120)
    return json.loads(r.stdout)
def newest_k6(ns, since):
    """The newest k6_checks_rate sample's time in ns (seconds), over the time since `since` and ten minutes more; None"""
    window = max(600, int(time.time() - since) + 600)
    q = f'max(max_over_time(timestamp(k6_checks_rate{{source="k6",namespace="{ns}"}})[{window}s:30s]))'
    res = read(f"kubectl --request-timeout=60s get --raw '{MIMIR}{urllib.parse.quote(q)}'")["data"]["result"]
    return float(res[0]["value"][1]) if res else None
try:
    items = read("kubectl --request-timeout=60s get jobs,namespaces -A -o json")["items"]
except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
    sys.exit(3)
preview = {o["metadata"]["name"] for o in items if o.get("kind") == "Namespace"
           and (o["metadata"].get("labels") or {}).get("preview-env") == "true"}
for j in (o for o in items if o.get("kind") == "Job"):
    m, st = j["metadata"], j.get("status") or {}
    gave_up = any(c.get("type") == "Failed" and c.get("status") == "True" for c in st.get("conditions") or [])
    if m.get("creationTimestamp", "") >= os.environ["FROM"] and gave_up and not st.get("succeeded") and m["namespace"] not in preview:
        reason = next((c.get("reason") for c in st["conditions"] if c.get("type") == "Failed"), "") or "failed"
        print(f"job {m['namespace']}/{m['name']} failed ({reason})")
    elif (m.get("creationTimestamp", "") >= os.environ["FROM"] and m["name"].endswith("-k6-smoke") and st.get("succeeded")
          and m["namespace"] not in preview):
        started = st.get("startTime") or m["creationTimestamp"]
        try:
            since = calendar.timegm(time.strptime(started, "%Y-%m-%dT%H:%M:%SZ"))
            newest = newest_k6(m["namespace"], since)
        except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError, IndexError):
            sys.exit(3)
        if newest is None or newest < since:
            print(f"job {m['namespace']}/{m['name']}: its k6 run (started {started}) pushed no metric - no k6_checks_rate "
                  "sample since in Mimir (k6 exits 0 when its push fails)")
PY_JOBS
) || { echo "NOT QUIET: the Jobs made during the hold not read - none judged"; exit 1; }
if [ -n "$failed_jobs" ]; then echo "NOT QUIET: a Job made during the hold failed:"; echo "$failed_jobs"; exit 1; fi
# what the copy leaves out (scripts/vagrant-gitops-mirror.py's INFRA_DROP) is proven here alone: each such app named, its
# state as read at the hold's end - Synced to its revision, Healthy, its last sync's phase (the wave-patches review,
# 2026-11-27: "unproven" when the proof is this verify)
HOST="$host" MIRROR="$(dirname "$0")/vagrant-gitops-mirror.py" python3 -I - <<'PY_DROPPED'
import json, os, re, subprocess
# INFRA_DROP itself (vagrant-gitops-mirror.py): its app files' stems and its directories - an Application is left out of
# the copy when its name is a stem or starts with one (kagent-crds, schnappy-test-apps), is a directory's, or an
# ApplicationSet named for a stem made it (the preview environments' pr-<n>-<repo>)
src = open(os.environ["MIRROR"]).read()
block = src[src.index("INFRA_DROP = ["):]
block = block[:block.index("]")]
stems = re.findall(r'"clusters/production/argocd/apps/([a-z0-9-]+)\.yaml"', block)
dirs = re.findall(r'"clusters/production/([a-z0-9-]+)"', block)
def left_out(a):
    m = a.get("metadata") or {}
    n = m.get("name") or ""
    owners = [o.get("name") for o in m.get("ownerReferences") or [] if o.get("kind") == "ApplicationSet"]
    return n in dirs or any(n == s or n.startswith(s + "-") for s in stems) or any(o in stems for o in owners)
try:
    # a read bounded (a stalled API server holds an ssh that connected): not read, said - the looks above judged them
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", os.environ["HOST"],
                        "kubectl --request-timeout=60s get -n argocd application.argoproj.io -o json"],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120)
    apps = sorted(json.loads(r.stdout)["items"], key=lambda a: a["metadata"]["name"])
except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError):
    print("the apps the copy leaves out: not read here - the looks above judged them")
    apps = []
for a in (a for a in apps if left_out(a)):
    st = a.get("status") or {}
    sync = st.get("sync") or {}
    rev = sync.get("revision") or ",".join(str(x)[:8] for x in sync.get("revisions") or []) or "?"
    health, phase = (st.get("health") or {}).get("status"), (st.get("operationState") or {}).get("phase") or "none"
    # an app the looks leave unjudged (the test environment's) can stand here not healthy: never called proven
    proven = sync.get("status") == "Synced" and health == "Healthy" and phase in ("Succeeded", "none")
    print("%s (the copy leaves it out): %s - %s/%s at %s, its last sync %s" % (
        "PROVEN IN PRODUCTION ALONE" if proven else "NOT PROVEN IN PRODUCTION", a["metadata"]["name"], sync.get("status"), health,
        str(rev)[:8] if sync.get("revision") else rev, phase))
PY_DROPPED
echo "SETTLED AND QUIET for $hold min"
