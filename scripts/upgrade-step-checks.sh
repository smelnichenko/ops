#!/usr/bin/env bash
# upgrade-step-checks.sh - an upgrade step's independent checks, run at the same time instead of one after the other:
#   data       the seeded rows on every Postgres instance, a write on the primary; Kafka's and Scylla's seeded data
#   survival   the observability data the one-way steps must keep; ClickHouse's compatibility setting
#   storage    a new local-path volume provisioned, written and read back
#   metrics    Prometheus reconciled, every target up, Mimir receiving, logs reaching ClickHouse
#   smoke      production's k6 smoke
# None reads what another writes. Each one's log is printed whole as it ends (with its time); the exit is non-zero when
# any failed, naming them. A step paid their sum (a minute or more of every step); it now pays the slowest.
#
# Each check runs in its own process group: an interrupt or a kill of this script stops every check still running
# (background jobs of a non-interactive shell ignore SIGINT, and a kill reached only the script - the checks went on
# changing the copy). Ssh to the VMs gives up on a dead connection within a minute (Vagrant's own config sets no
# keepalive: a stalled VM held a check for hours).
#
# Usage: scripts/upgrade-step-checks.sh <infra ref> <platform ref> <clickhouse compat> <clickhouse users>
set -uo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
infra_ref=$1 platform_ref=$2 clickhouse_compat=$3 clickhouse_users=$4
cd "$ops" || exit 1
mkdir -p .upgrade
logs=$(mktemp -d "$ops/.upgrade/step-checks.XXXX")
names=() pids=() done_=()
cleanup() {
  local i own
  # a group signalled only while it is one of this script's jobs: never a PID it did not start (1 is `kill -- -1`,
  # every process of the user; 2026-10-07 a test's PID 1 ended the operator's session), nor one the system gave to
  # another process after the job ended
  own=" $(jobs -p | tr '\n' ' ') "
  for i in "${!pids[@]}"; do
    [ -z "${done_[$i]:-}" ] && [[ $own == *" ${pids[$i]} "* ]] && kill -TERM -- "-${pids[$i]}" 2> /dev/null
  done
  wait 2> /dev/null
  rm -rf "$logs"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
# own process groups for the jobs (job control), so a group kill reaches each check's whole tree
set -m

# the VMs' ssh config, read once: Vagrant runs one action per machine at a time, so parallel `vagrant ssh` calls fail;
# keepalives so a dead connection ends
vagrant ssh-config > "$logs/ssh-config" 2> /dev/null || { echo "vagrant ssh-config failed"; exit 1; }
printf '\nHost *\n  ServerAliveInterval 15\n  ServerAliveCountMax 4\n  ConnectTimeout 30\n  LogLevel ERROR\n' \
  >> "$logs/ssh-config"
export VAGRANT_SSH_CONFIG=$logs/ssh-config

play() { (cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml "$@"); }
start() {  # name, command... - stdin from /dev/null: under job control a job gets the caller's (a check reading it
  # would take the caller's input, or stop on SIGTTIN at a terminal while wait -n waited for ever)
  local name=$1; shift
  "$@" > "$logs/$name" 2>&1 < /dev/null &
  names+=("$name"); pids+=("$!")
}
t0=$(date +%s)
start data play ../../tests/ansible/upgrade/data-check.yml -e mode=verify
start survival play ../../tests/ansible/upgrade/survival-check.yml -e mode=verify \
  -e clickhouse_compat="$clickhouse_compat" -e clickhouse_users="$clickhouse_users"
start storage play ../../tests/ansible/upgrade/storage-check.yml
start metrics play ../../tests/ansible/upgrade/metrics-check.yml
start smoke scripts/vagrant-smoke.sh "$infra_ref" "$platform_ref"

failed=()
left=${#pids[@]}
while [ "$left" -gt 0 ]; do
  running=()
  for i in "${!pids[@]}"; do [ -n "${done_[$i]:-}" ] || running+=("${pids[$i]}"); done
  ended=""
  wait -n -p ended "${running[@]}"; rc=$?
  # a return with no job ended (127: none of them a child any more - one killed by a signal and reaped already) judges
  # no check - never the last one again; bash unsets `ended` then (set -u would end the script before this said why).
  # The checks left named, each with what its log holds
  if [ -z "${ended:-}" ]; then
    echo "STEP CHECKS: wait returned $rc with no check ended - the rest not judged"
    unjudged=()
    for i in "${!pids[@]}"; do
      [ -z "${done_[$i]:-}" ] || continue
      # none of them runs (wait -n would wait): a check bash collected outside wait -n has its status still known to
      # `wait` - judged; one it never knew (127) is not
      wait "${pids[$i]}" 2> /dev/null; r=$?
      if [ "$r" != 127 ]; then
        done_[i]=1
        echo "===== check ${names[$i]} (exit $r, its status read after)"
        cat "$logs/${names[$i]}"
        [ "$r" = 0 ] || failed+=("${names[$i]}")
      else
        unjudged+=("${names[$i]}")
      fi
    done
    echo "STEP CHECKS NOT JUDGED: ${unjudged[*]}"
    for n in "${unjudged[@]}"; do
      echo "===== check $n (not judged)"
      cat "$logs/$n" 2> /dev/null || echo "(no log)"
    done
    # and what was judged before: the failures said too
    [ "${#failed[@]}" -eq 0 ] || echo "STEP CHECKS FAILED: ${failed[*]}"
    exit 1
  fi
  for i in "${!pids[@]}"; do
    if [ "${pids[$i]}" = "$ended" ]; then
      done_[i]=1
      echo "===== check ${names[$i]} (exit $rc, after $(( $(date +%s) - t0 )) s)"
      cat "$logs/${names[$i]}"
      [ "$rc" = 0 ] || failed+=("${names[$i]}")
    fi
  done
  left=$((left - 1))
done
if [ "${#failed[@]}" -gt 0 ]; then
  echo "STEP CHECKS FAILED: ${failed[*]}"
  exit 1
fi
echo "STEP CHECKS PASSED: ${names[*]}"
