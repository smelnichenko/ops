#!/bin/bash
# scripts/upgrade-step-checks.sh with every check stubbed, in a copy of its tree: each check's exit judged as its own;
# a check reads nothing of the caller's stdin (job control gave the jobs the caller's pipe - one that read it would
# take the caller's input, or stop on SIGTTIN from a terminal while wait -n waited for ever).
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/deploy/ansible/venv/bin" "$T/bin" "$T/.upgrade"
mkdir -p "$T/scripts/lib"; cp "$ROOT/scripts/lib/process-groups.sh" "$T/scripts/lib/"
cp "$ROOT/scripts/upgrade-step-checks.sh" "$T/scripts/"
cat > "$T/bin/vagrant" <<'STUB'
#!/bin/sh
echo "Host kubeadm"
STUB
# every check: what it read on stdin (nothing, within a second), and exit 1 for the metrics one
cat > "$T/deploy/ansible/venv/bin/ansible-playbook" <<'STUB'
#!/bin/bash
# LONG=<file>: the storage check runs on (its PID in the file) until the script's cleanup stops it - one that ran
# its course leaves <file>.finished (the cleanup's wait waited it out)
# SLOW_TERM: it takes a second to end on a TERM (.slow then). STOPPER=<file>: the data check stops itself (SIGSTOP), its
# PID in the file. ALL_PASS: the metrics check passes too
case "$*" in *storage-check*) [ -z "${LONG:-}" ] || { echo $$ > "$LONG"
  [ -z "${SLOW_TERM:-}" ] || trap 'sleep 1; echo > "$LONG.slow"; exit 143' TERM
  sleep 30 & wait $!; echo > "$LONG.finished"; } ;; esac
case "$*" in *data-check*) [ -z "${STOPPER:-}" ] || { echo $$ > "$STOPPER"; kill -STOP $$; } ;; esac
got=$(timeout 1 cat 2> /dev/null || true)
echo "check $* read stdin: [$got]"
case "$*" in *metrics-check*) [ -n "${ALL_PASS:-}" ] || exit 1 ;; esac
STUB
cat > "$T/scripts/vagrant-smoke.sh" <<'STUB'
#!/bin/bash
got=$(timeout 1 cat 2> /dev/null || true)
echo "smoke read stdin: [$got]"
STUB
chmod +x "$T/bin/vagrant" "$T/deploy/ansible/venv/bin/ansible-playbook" "$T/scripts/vagrant-smoke.sh"
out=$(echo "THE CALLER'S INPUT" | PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy 2>&1)
rc=$?
# a process's parent, process group, session and command name, from /proc (CI's image has no ps)
proc_info() {  # proc_info <pid>: "<ppid> <pgid> <sid> <comm>" - nothing for no such process
  local stat comm
  stat=$(cat "/proc/$1/stat" 2> /dev/null) && comm=$(cat "/proc/$1/comm" 2> /dev/null) || return 0
  set -- ${stat##*) }
  echo "$2 $3 $4 $comm"
}
fails=0
gone() {  # gone <pid file>: the process it names no more there - a moment allowed for its teardown
  local pid; pid=$(cat "$1" 2> /dev/null) || { echo "no-pid"; return; }
  for _ in $(seq 20); do [ -e "/proc/$pid" ] || { echo gone; return; }; sleep 0.1; done
  echo "running"
}
check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got $2, want $3"; printf '%s\n' "$out" | sed 's/^/    /'; fails=$((fails + 1))
}
check "no check read the caller's stdin" "$(grep -c "THE CALLER'S INPUT" <<< "$out")" 0
check "five checks judged" "$(grep -c '^===== check ' <<< "$out")" 5
check "the failing one named, the run failed" "$rc $(grep -o 'STEP CHECKS FAILED: metrics' <<< "$out")" \
  "1 STEP CHECKS FAILED: metrics"

# the script stopped (a TERM, as an interrupted full run sends): the checks still running stopped with it - the storage
# check runs on here until then; the script is this test's own child, checked so before it is signalled
LONG="$T/long.pid" PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy < /dev/null \
  > "$T/term.out" 2>&1 &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ]; do sleep 0.1; done' "$T/long.pid"
if [ "$(proc_info "$sp" | awk '{print $1, $4}')" = "$$ bash" ]; then
  kill -TERM "$sp"
fi
wait "$sp"; rc=$?
out=$(cat "$T/term.out")
check "a TERM to the script: it ends (130), the check still running stopped - its process gone, not left asleep" \
  "$rc $([ -e "$T/long.pid.finished" ] && echo finished || echo stopped) $(gone "$T/long.pid")" "130 stopped gone"

# a check bash collected outside wait -n (a `jobs` reported it ended - out of the job table, wait -n returns 127, `wait
# <pid>` still has its status): judged by that status - a failure failed, all passing passed (measured on bash 5.2)
sed 's|^start smoke scripts/vagrant-smoke.sh "$infra_ref" "$platform_ref"$|&\nsleep 1; jobs > /dev/null|' \
  "$T/scripts/upgrade-step-checks.sh" > "$T/scripts/collected.sh"
check "the collecting copy made" "$(grep -c '^sleep 1; jobs > /dev/null$' "$T/scripts/collected.sh")" 1
out=$(PATH="$T/bin:$PATH" bash "$T/scripts/collected.sh" i p 24.8 schnappy < /dev/null 2>&1); rc=$?
check "checks collected outside wait -n: judged by their status - the failing one failed" \
  "$rc $(grep -c '^===== check metrics (exit 1, its status read after)$' <<< "$out") \
$(grep -c '^STEP CHECKS FAILED: metrics$' <<< "$out") $(grep -c 'NOT JUDGED' <<< "$out")" "1 1 1 0"
out=$(ALL_PASS=1 PATH="$T/bin:$PATH" bash "$T/scripts/collected.sh" i p 24.8 schnappy < /dev/null 2>&1); rc=$?
check "checks collected outside wait -n, all passing: the step's checks pass" \
  "$rc $(grep -c '^STEP CHECKS PASSED' <<< "$out") $(grep -c 'NOT JUDGED' <<< "$out")" "0 1 0"
# a check stopped (SIGSTOP): wait -n reports its stop, not its end - not judged, said; the cleanup ends it (a stopped
# group acts on no TERM until continued)
rm -f "$T/stopper.pid"
out=$(STOPPER="$T/stopper.pid" STEP_CHECKS_SECONDS=3 PATH="$T/bin:$PATH" timeout -k 5 30 \
  bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy < /dev/null 2>&1); rc=$?
check "a check stopped by a signal: the checks' bound ends them, said; it not judged, the run fails; the cleanup ends it" \
  "$rc $(grep -c '^STEP CHECKS NOT JUDGED: data$' <<< "$out") $(grep -c 'not ended within 3 s' <<< "$out") \
$(gone "$T/stopper.pid")" "1 1 1 gone"
# a second signal during the cleanup's wait for a check that takes a second to end (a Ctrl-C pressed twice; a kill
# sent twice): the cleanup goes on to its end - the check's own stop done, the run's work directory removed. TERM: a
# background job here ignores INT (no job control), and the trap takes both alike
rm -f "$T/long.pid" "$T/long.pid.slow" "$T/long.pid.finished"; rm -rf "$T/.upgrade"/step-checks.*
LONG="$T/long.pid" SLOW_TERM=1 PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy \
  < /dev/null > "$T/twice.out" 2>&1 &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ]; do sleep 0.1; done' "$T/long.pid"
if [ "$(proc_info "$sp" | awk '{print $1, $4}')" = "$$ bash" ]; then
  kill -TERM "$sp"; sleep 0.3; kill -TERM "$sp" 2> /dev/null
fi
wait "$sp"; rc=$?
check "a TERM twice, the second in the cleanup: it goes on - the check's own stop done, the work directory gone" \
  "$rc $([ -e "$T/long.pid.slow" ] && echo slow-done || echo cut) $(gone "$T/long.pid") \
$(ls -d "$T/.upgrade"/step-checks.* 2> /dev/null | wc -l)" "130 slow-done gone 0"

# a "check" that is no child of the script: its own process, started here - a sleep in a session of its own (job
# control off, so setsid does not fork: $! is the sleep), proven so before its PID is used, killed by this test alone.
# wait -n can never return it: the script must say so (its guard), and its cleanup must signal only its own jobs' groups
# - a PID it did not start (1 would be `kill -- -1`: every process of the user) never
set +m
setsid sleep 1000 < /dev/null > /dev/null 2>&1 &
ghost=$!
trap 'kill "$ghost" 2> /dev/null; rm -rf "$T"' EXIT
# setsid starts its session and execs the sleep in its own time (CI: read still as "setsid" in the shell's group) -
# read until it has, a bounded wait
for _ in $(seq 100); do
  read -r gppid gpgid gsid gcomm <<< "$(proc_info "$ghost")"
  [ "$gpgid $gsid $gcomm" = "$ghost $ghost sleep" ] && break
  sleep 0.05
done
if [ "$gpgid $gsid $gcomm" != "$ghost $ghost sleep" ]; then
  echo "FAIL the test's own process is not a session-leading sleep ($ghost: $gpgid $gsid $gcomm) - not used"
  exit 1
fi
sed -i 's|^start smoke scripts/vagrant-smoke.sh "$infra_ref" "$platform_ref"$|&\nnames+=(ghost); pids+=("$GHOST")|' \
  "$T/scripts/upgrade-step-checks.sh"
check "the ghost added to the copy" "$(grep -c 'pids+=("$GHOST")' "$T/scripts/upgrade-step-checks.sh")" 1
out=$(GHOST=$ghost PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy < /dev/null 2>&1)
rc=$?
check "wait -n with no check ended: the guard says so, the run fails" \
  "$rc $(grep -c 'with no check ended' <<< "$out")" "1 1"
check "the checks not judged named, each with its log (the ghost has none)" \
  "$(grep -c '^STEP CHECKS NOT JUDGED: ghost$' <<< "$out") $(grep -c '^===== check ghost (not judged)$' <<< "$out")" "1 1"
check "the failures judged before it summarized too (metrics, its stub failing)" \
  "$(grep -c '^STEP CHECKS FAILED: metrics$' <<< "$out")" 1
check "its cleanup signalled only its own jobs: the foreign process lives" \
  "$(proc_info "$ghost" | awk '{print $4}')" sleep
if [ "$fails" = 0 ]; then echo "step-checks: ALL-PASS"; else echo "step-checks: $fails FAILED"; exit 1; fi
