#!/usr/bin/env bash
# vagrant-smoke.sh - run production's k6 smoke test against the Vagrant copy of production, on demand (after each
# upgrade step).
#
# The chart's PostSync hook runs it on every sync of the apps, as in production; this runs the very same Job when the
# test asks: rendered from platform's schnappy chart with production's values, changed only in what lets it run beside
# the hook without touching Argo's objects - its own Job and script ConfigMap names (this run's: a run left behind by
# a stopped check never deletes another's), no hook annotations, no retries.
# It reads the client secret the chart's ExternalSecret already made. TLS is verified as in production: the Vagrant
# copy serves production's own *.pmon.dev certificate (tests/ansible/upgrade/production-state.yml). Prints k6's checks;
# exit 0 only if k6 passed (set -e + pipefail carry the remote shell's exit 1 out).
#
# Leaves nothing behind: the remote shell deletes the run's Job and ConfigMap when it ends - also when its connection
# is gone (a heartbeat it writes fails then), its caller stopped.
#
# Usage: scripts/vagrant-smoke.sh [infra ref, default main] [platform ref, default main]
#        (the refs the mirror pushed; read from the ../infra and ../platform checkouts' git, never their working trees)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
infra_ref=${1:-main}
platform_ref=${2:-main}
mkdir -p "$ops/.upgrade"
work=$(mktemp -d "$ops/.upgrade/smoke.XXXX")
trap 'rm -rf "$work"' EXIT
name=vagrant-k6-smoke-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')

git -C "$ops/../platform" archive "$platform_ref" helm/schnappy | tar -x -C "$work"
git -C "$ops/../infra" show "$infra_ref:clusters/production/schnappy-production-apps/values.yaml" > "$work/values.yaml"
helm template schnappy-production "$work/helm/schnappy" -n schnappy-production -f "$work/values.yaml" \
  --set smokeTest.enabled=true > "$work/rendered.yaml"

cat > "$work/pick.py" <<'EOF'
import sys, yaml
docs, name = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d], sys.argv[2]
cms = [d for d in docs if d.get("kind") == "ConfigMap" and d["metadata"]["name"] == "schnappy-k6-smoke"]
jobs = [d for d in docs if d.get("kind") == "Job" and d["metadata"]["name"].endswith("-k6-smoke")]
if len(cms) != 1 or len(jobs) != 1:
    sys.exit(f"smoke render: expected one k6 Job and its script ConfigMap, got {len(jobs)} and {len(cms)}")
cm, job = cms[0], jobs[0]
cm["metadata"] = {"name": name}
job["metadata"] = {"name": name}
job["spec"]["backoffLimit"] = 0
mounts = [v for v in job["spec"]["template"]["spec"]["volumes"]
          if v.get("configMap", {}).get("name") == "schnappy-k6-smoke"]
if len(mounts) != 1:
    sys.exit("smoke render: the Job no longer mounts ConfigMap schnappy-k6-smoke - update this script")
mounts[0]["configMap"]["name"] = name
print(yaml.safe_dump_all([cm, job], sort_keys=False))
EOF
python3 "$work/pick.py" "$work/rendered.yaml" "$name" > "$work/smoke.yaml"

cd "$ops"
# plain ssh with the VMs' config when the caller has it (VAGRANT_SSH_CONFIG, scripts/upgrade-step-checks.sh): Vagrant
# runs one action per machine at a time, so a `vagrant ssh` beside another one fails - and each costs its start-up
# (vagrant ssh's own "Connection ... closed." noise dropped; any other error is kept)
vssh() {
  if [ -n "${VAGRANT_SSH_CONFIG:-}" ]; then
    ssh -F "$VAGRANT_SSH_CONFIG" "$1" "$2"
  else
    vagrant ssh "$1" -c "$2" 2> >(grep -v '^Connection to .* closed\.' >&2)
  fi
}
vssh kubeadm "cat > /tmp/$name.yaml" < "$work/smoke.yaml"
# One remote shell does the whole run, polling the Job's end itself: no waiter to stop, none to outlive it. Each poll
# writes a heartbeat (a carriage return, dropped here): once the connection is gone the write fails and the shell ends
# - its EXIT trap deletes the run's Job and ConfigMap, silently (a write would end it at once).
vssh kubeadm "sudo bash -s $name" <<'SH' | tr -d '\r'
set -u
NAME=$1
K="kubectl --kubeconfig /etc/kubernetes/admin.conf -n schnappy-production"
cleanup() {
  $K delete job "$NAME" --ignore-not-found --wait=false > /dev/null 2>&1
  $K delete configmap "$NAME" --ignore-not-found > /dev/null 2>&1
  rm -f "/tmp/$NAME.yaml"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM PIPE
$K apply -f "/tmp/$NAME.yaml" || { echo "SMOKE FAILED: the Job not applied"; exit 1; }
rm -f "/tmp/$NAME.yaml"
ended=""
for _ in $(seq 180); do  # 15 minutes
  printf '\r' 2> /dev/null
  ended=$($K get job "$NAME" -o jsonpath='{.status.conditions[?(@.status=="True")].type}' 2> /dev/null)
  case "$ended" in *Complete* | *Failed*) break ;; esac
  sleep 5
done
echo "--- k6 checks"
$K logs "job/$NAME" -c k6 --tail=80 | grep -E '[✓✗]|http_req_failed|level=(error|warning)' | head -40
passed=$($K get job "$NAME" -o jsonpath='{.status.succeeded}')
# its checks are printed above; a failed pod left behind would hold the next settle wait (argo-settled.yml) - the
# EXIT trap deletes the Job and its ConfigMap
if [ "$passed" = 1 ]; then echo "SMOKE PASSED"; else echo "SMOKE FAILED${ended:+ ($ended)}"; exit 1; fi
SH
