#!/usr/bin/env bash
# upgrade-step-checks.sh - an upgrade step's independent checks, run at the same time instead of one after the other:
#   data       the seeded rows on every Postgres instance, a write on the primary; Kafka's and Scylla's seeded data
#   survival   the observability data the one-way steps must keep; ClickHouse's compatibility setting
#   storage    a new local-path volume provisioned, written and read back
#   metrics    Prometheus reconciled, every target up, Mimir receiving, logs reaching ClickHouse
#   smoke      production's k6 smoke
#   prod       the data paths as production's check reads them (production-data-check.yml)
# None reads what another writes. Each one's log is printed whole as it ends (with its time); the exit is non-zero when
# any failed, naming them. A step paid their sum (a minute or more of every step); it now pays the slowest.
#
# Each check runs in its own process group: an interrupt or a kill of this script stops every check still running
# (background jobs of a non-interactive shell ignore SIGINT, and a kill reached only the script - the checks went on
# changing the copy). Ssh to the VMs gives up on a dead connection within a minute (Vagrant's own config sets no
# keepalive: a stalled VM held a check for hours).
#
# Usage: scripts/upgrade-step-checks.sh <infra ref> <platform ref> <clickhouse compat> <clickhouse users> [<pools gone>]
set -uo pipefail
ops=$(cd "$(dirname "$0")/.." && pwd)
infra_ref=$1 platform_ref=$2 clickhouse_compat=$3 clickhouse_users=$4 pools_gone=${5:-}
cd "$ops" || exit 1
# own_jobs, stop_groups
source scripts/lib/process-groups.sh
# the checks' own bound (below): above every check's own - data-check's retries alone wait up to ~3085 s (each until's
# retries and delays, summed), its 257 tries a few seconds each besides (the slowest check of 240 took 158 s) and what
# a try waits by its own word (a Kafka consumer's 60 s: 4850 s in all) - so it stops only what none of them bounds; a
# value that is no number would make its sleep fail at once and leave no bound
bound=${STEP_CHECKS_SECONDS:-5400}
[[ $bound =~ ^[1-9][0-9]*$ ]] || { echo "STEP_CHECKS_SECONDS=$bound: not a whole number of seconds"; exit 1; }
# the stop's grace too: a fraction aborted the cleanup's arithmetic - nothing KILLed, the checks left running
[[ ${STOP_GRACE:-0} =~ ^(0|[1-9][0-9]*)$ ]] || { echo "STOP_GRACE=$STOP_GRACE: not a whole number of seconds"; exit 1; }
mkdir -p .upgrade
logs=$(mktemp -d "$ops/.upgrade/step-checks.XXXX")
# done_[i]: check i's exit once judged - judged and failed in one assignment (a signal between two left a judged
# failure out of every line)
names=() pids=() done_=() watchdog=""
failures() {  # failures <array>: the checks judged failed, by name
  local -n _failed=$1
  local i
  _failed=()
  for i in "${!done_[@]}"; do [ "${done_[$i]}" = 0 ] || _failed+=("${names[$i]}"); done
}
not_judged() {  # the checks not judged named, each with its log, and the failures judged before; the run fails
  local i unjudged=() failed
  for i in "${!pids[@]}"; do [ -n "${done_[$i]:-}" ] || unjudged+=("${names[$i]}"); done
  echo "STEP CHECKS NOT JUDGED: ${unjudged[*]}"
  for n in "${unjudged[@]}"; do
    echo "===== check $n (not judged)"
    cat "$logs/$n" 2> /dev/null || echo "(no log)"
  done
  failures failed
  [ "${#failed[@]}" -eq 0 ] || echo "STEP CHECKS FAILED: ${failed[*]}"
  exit 1
}
cleanup() {
  local groups
  # no signal cuts it short (a Ctrl-C pressed twice: the second ran the trap again inside it, its checks unwaited);
  # a write to an output whose reader is gone (a tee the Ctrl-C ended) fails, not the cleanup (its work left behind)
  trap '' INT TERM HUP PIPE
  # every job of this script's still its child - a check or the watchdog whose PID was not kept yet (a signal between
  # its start and its record) among them: never a PID it did not start (1 is `kill -- -1`, every process of the user;
  # 2026-10-07 a test's PID 1 ended the operator's session), nor one the system gave to another process after the job
  # ended. Each whole - the playbook under a check's subshell too - bounded
  own_jobs groups
  [ "${#groups[@]}" -eq 0 ] || stop_groups "${STOP_GRACE:-60}" "${groups[@]}"
  # each job waited for but one the KILL did not end (a wait for it never ends)
  for j in "${groups[@]}"; do [[ " $stop_left " == *" $j "* ]] || wait "$j" 2> /dev/null; done
  rm -rf "$logs"
}
on_signal() {  # on_signal <exit>: a signal's first act - no other cuts the stop short; the checks' bound said
  trap '' INT TERM HUP PIPE
  if [ -e "$logs/timed-out" ]; then
    # the bound reached as the last check ended: every one judged, nothing to stop - the verdict goes on
    if [ "${#done_[@]}" -eq "${#pids[@]}" ]; then
      trap 'on_signal 130' INT TERM
      trap 'on_signal 129' HUP
      return
    fi
    echo "STEP CHECKS: not ended within $bound s - stopped"
    not_judged
  fi
  exit "$1"
}
trap cleanup EXIT
trap 'on_signal 130' INT TERM
trap 'on_signal 129' HUP
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
start metrics play ../../tests/ansible/upgrade/metrics-check.yml -e "scrape_pools_gone=$pools_gone"
start smoke scripts/vagrant-smoke.sh "$infra_ref" "$platform_ref"
start prod play playbooks/production-data-check.yml

# the checks' own bound: one that never ends - stopped by a signal (wait -n waits on it while any other job runs, this
# one always: measured on bash 5.2), or a hang none of them bounds - ends them after STEP_CHECKS_SECONDS, said, those
# left not judged. It signals this script only while it is still its parent: one killed outright (no cleanup ran)
# left it behind, its PID free for another process by the time the bound came
( sleep "$bound" && read -r st < "/proc/$BASHPID/stat" && set -- ${st##*) } && [ "$2" = "$$" ] \
  && : > "$logs/timed-out" && kill -TERM $$ ) < /dev/null > /dev/null 2>&1 &
watchdog=$!
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
    echo "STEP CHECKS: wait returned $rc with no check ended - each left read by its status where bash kept it"
    # a check stopped by a signal: wait -n waits on it while another job runs (the watchdog: it is what ends a stopped
    # check), and returns 127 for it only once none does (bash 5.2, measured); `wait <pid>` gives its stop (147) - not
    # its end: not judged, said; the cleanup ends it (judged, it was waited for by the cleanup for ever)
    stopped=" $(jobs -sp | tr '\n' ' ') "
    for i in "${!pids[@]}"; do
      [ -z "${done_[$i]:-}" ] || continue
      if [[ $stopped == *" ${pids[$i]} "* ]]; then
        echo "STEP CHECKS: check ${names[$i]} stopped by a signal"
        continue
      fi
      # none of them runs (wait -n would wait): a check bash collected outside wait -n (a `jobs` reported its end)
      # has its status still known to `wait` - judged; one it never knew (127) is not
      wait "${pids[$i]}" 2> /dev/null; r=$?
      if [ "$r" != 127 ]; then
        echo "===== check ${names[$i]} (exit $r, its status read after)"
        cat "$logs/${names[$i]}"
        done_[i]=$r
      fi
    done
    # every one judged: the verdict as ever; otherwise those not judged said
    for i in "${!pids[@]}"; do [ -n "${done_[$i]:-}" ] || not_judged; done
    break
  fi
  for i in "${!pids[@]}"; do
    if [ "${pids[$i]}" = "$ended" ]; then
      # printed, then judged: a signal between says it again as not judged - never judged and in no line
      echo "===== check ${names[$i]} (exit $rc, after $(( $(date +%s) - t0 )) s)"
      cat "$logs/${names[$i]}"
      done_[i]=$rc
    fi
  done
  left=$((left - 1))
done
# every check judged: the bound has nothing left to stop - while it is this script's job still (one that ended and was
# reaped: its PID may be another process's)
own_jobs left_
[[ " ${left_[*]} " != *" $watchdog "* ]] || stop_groups 5 "$watchdog"
failures failed
if [ "${#failed[@]}" -gt 0 ]; then
  echo "STEP CHECKS FAILED: ${failed[*]}"
  exit 1
fi
echo "STEP CHECKS PASSED: ${names[*]}"
