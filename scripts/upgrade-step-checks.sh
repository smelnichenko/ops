#!/usr/bin/env bash
# upgrade-step-checks.sh - an upgrade step's independent checks, run at the same time instead of one after the other:
#   data       the seeded rows on every Postgres instance, a write on the primary; Kafka's and Scylla's seeded data
#   survival   the observability data the one-way steps must keep; ClickHouse's compatibility setting
#   storage    a new local-path volume provisioned, written and read back
#   metrics    Prometheus reconciled, every target up, Mimir receiving, logs reaching ClickHouse
#   smoke      production's k6 smoke
#   inventory  the copy's version inventory (the step runner compares it with the step's expected one)
# None reads what another writes. Each one's output goes to its own log, printed whole and in this order once all have
# ended (a step's log stays readable); the exit is non-zero when any failed, naming them. A step paid their sum (a
# minute or more of every step); it now pays the slowest.
#
# Usage: scripts/upgrade-step-checks.sh <infra ref> <platform ref> <clickhouse compat> <clickhouse users>
set -uo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
infra_ref=$1 platform_ref=$2 clickhouse_compat=$3 clickhouse_users=$4
cd "$ops"
mkdir -p .upgrade
logs=$(mktemp -d "$ops/.upgrade/step-checks.XXXX")
trap 'rm -rf "$logs"' EXIT
play() { (cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml "$@"); }
# the VMs' ssh config, read once: Vagrant runs one action per machine at a time, so parallel `vagrant ssh` calls fail
# (the smoke and the inventory both reach kubeadm)
vagrant ssh-config > "$logs/ssh-config" 2>/dev/null || { echo "vagrant ssh-config failed"; exit 1; }
export VAGRANT_SSH_CONFIG=$logs/ssh-config

names=(data survival storage metrics smoke inventory)
t0=$(date +%s)
play ../../tests/ansible/upgrade/data-check.yml -e mode=verify > "$logs/data" 2>&1 & pids[0]=$!
play ../../tests/ansible/upgrade/survival-check.yml -e mode=verify -e clickhouse_compat="$clickhouse_compat" \
  -e clickhouse_users="$clickhouse_users" > "$logs/survival" 2>&1 & pids[1]=$!
play ../../tests/ansible/upgrade/storage-check.yml > "$logs/storage" 2>&1 & pids[2]=$!
play ../../tests/ansible/upgrade/metrics-check.yml > "$logs/metrics" 2>&1 & pids[3]=$!
scripts/vagrant-smoke.sh "$infra_ref" "$platform_ref" > "$logs/smoke" 2>&1 & pids[4]=$!
# the isolation probe's namespace is the test's own (tests/ansible/upgrade/isolate-cluster.yml), not production's
{ ssh -F "$VAGRANT_SSH_CONFIG" kubeadm 'sudo INVENTORY_EXCLUDE_NAMESPACES=isolation-probe bash -s' < scripts/version-inventory.sh | tr -d '\r' > .upgrade/vagrant-inventory.txt \
    && for p in pi1 pi2; do ssh -F "$VAGRANT_SSH_CONFIG" $p 'sudo bash -s' < scripts/version-inventory-pi.sh | tr -d '\r'; done \
       >> .upgrade/vagrant-inventory.txt; } > "$logs/inventory" 2>&1 & pids[5]=$!

failed=()
for i in "${!names[@]}"; do
  wait "${pids[$i]}"; rc=$?
  echo "===== check ${names[$i]} (exit $rc, done by $(( $(stat -c %Y "$logs/${names[$i]}") - t0 )) s)"
  cat "$logs/${names[$i]}"
  [ "$rc" = 0 ] || failed+=("${names[$i]}")
done
if [ "${#failed[@]}" -gt 0 ]; then
  echo "STEP CHECKS FAILED: ${failed[*]}"
  exit 1
fi
echo "STEP CHECKS PASSED: ${names[*]}"
