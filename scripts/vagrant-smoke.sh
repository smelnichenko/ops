#!/usr/bin/env bash
# vagrant-smoke.sh - run production's k6 smoke test against the Vagrant copy of production, on demand (after each
# upgrade step).
#
# The chart's PostSync hook runs it on every sync of the apps, as in production; this runs the very same Job when the
# test asks: rendered from platform's schnappy chart with production's values, changed only in what lets it run beside
# the hook without touching Argo's objects - its own Job and script ConfigMap names, no hook annotations, no retries.
# It reads the client secret the chart's ExternalSecret already made. TLS is verified as in production: the Vagrant
# copy serves production's own *.pmon.dev certificate (tests/ansible/upgrade/production-state.yml). Prints k6's checks;
# exit 0 only if k6 passed (set -e + pipefail carry the remote shell's exit 1 out).
#
# Leaves nothing behind.
#
# Usage: scripts/vagrant-smoke.sh [infra checkout] [platform checkout]   (each at its checked-out HEAD)
set -euo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
infra=${1:-$ops/../infra}
platform=${2:-$ops/../platform}
mkdir -p "$ops/.upgrade"
work=$(mktemp -d "$ops/.upgrade/smoke.XXXX")
trap 'rm -rf "$work"' EXIT

helm template schnappy-production "$platform/helm/schnappy" -n schnappy-production \
  -f "$infra/clusters/production/schnappy-production-apps/values.yaml" \
  --set smokeTest.enabled=true > "$work/rendered.yaml"

cat > "$work/pick.py" <<'EOF'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
cms = [d for d in docs if d.get("kind") == "ConfigMap" and d["metadata"]["name"] == "schnappy-k6-smoke"]
jobs = [d for d in docs if d.get("kind") == "Job" and d["metadata"]["name"].endswith("-k6-smoke")]
if len(cms) != 1 or len(jobs) != 1:
    sys.exit(f"smoke render: expected one k6 Job and its script ConfigMap, got {len(jobs)} and {len(cms)}")
cm, job = cms[0], jobs[0]
cm["metadata"] = {"name": "vagrant-k6-smoke"}
job["metadata"] = {"name": "vagrant-k6-smoke"}
job["spec"]["backoffLimit"] = 0
mounts = [v for v in job["spec"]["template"]["spec"]["volumes"]
          if v.get("configMap", {}).get("name") == "schnappy-k6-smoke"]
if len(mounts) != 1:
    sys.exit("smoke render: the Job no longer mounts ConfigMap schnappy-k6-smoke - update this script")
mounts[0]["configMap"]["name"] = "vagrant-k6-smoke"
print(yaml.safe_dump_all([cm, job], sort_keys=False))
EOF
python3 "$work/pick.py" "$work/rendered.yaml" > "$work/smoke.yaml"

cd "$ops"
vagrant ssh kubeadm -c 'cat > /tmp/vagrant-k6-smoke.yaml' < "$work/smoke.yaml" 2>/dev/null
# One remote shell does the whole run: Complete and Failed are awaited side by side there and the loser killed, so no
# waiter outlives the script (a local `vagrant ssh` waiter, killed by PID, left its ssh child holding the output open).
vagrant ssh kubeadm -c 'sudo bash -s' 2>/dev/null <<'SH' | tr -d '\r'
set -u
K="kubectl --kubeconfig /etc/kubernetes/admin.conf -n schnappy-production"
$K delete job vagrant-k6-smoke --ignore-not-found --wait=true > /dev/null
$K apply -f /tmp/vagrant-k6-smoke.yaml
rm -f /tmp/vagrant-k6-smoke.yaml
$K wait job/vagrant-k6-smoke --for=condition=Complete --timeout=900s > /dev/null 2>&1 & ok=$!
$K wait job/vagrant-k6-smoke --for=condition=Failed --timeout=900s > /dev/null 2>&1 & failed=$!
wait -n "$ok" "$failed"
kill "$ok" "$failed" 2> /dev/null
wait 2> /dev/null
echo "--- k6 checks"
$K logs job/vagrant-k6-smoke -c k6 --tail=80 | grep -E '[✓✗]|http_req_failed|level=(error|warning)' | head -40
passed=$($K get job vagrant-k6-smoke -o jsonpath='{.status.succeeded}')
# its checks are printed above; a failed pod left behind would hold the next settle wait (argo-settled.yml)
$K delete job vagrant-k6-smoke --wait=false > /dev/null
$K delete configmap vagrant-k6-smoke > /dev/null
if [ "$passed" = 1 ]; then echo "SMOKE PASSED"; else echo "SMOKE FAILED"; exit 1; fi
SH
