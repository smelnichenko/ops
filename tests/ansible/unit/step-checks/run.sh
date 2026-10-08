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
# every check: what it read on stdin (nothing, within a second), and exit 1 for the metrics one. IGNORE_TERM: the
# storage check (LONG) ignores a TERM
cat > "$T/deploy/ansible/venv/bin/ansible-playbook" <<'STUB'
#!/bin/bash
# LONG=<file>: the storage check runs on (its PID in the file) until the script's cleanup stops it - one that ran
# its course leaves <file>.finished (the cleanup's wait waited it out)
# SLOW_TERM: it takes a second to end on a TERM (.stopping as it starts, .slow then). STOPPER=<file>: the data check stops itself (SIGSTOP), its
# PID in the file. ALL_PASS: the metrics check passes too
case "$*" in *storage-check*) [ -z "${LONG:-}" ] || { echo $$ > "$LONG"
  [ -z "${SLOW_TERM:-}" ] || trap 'echo > "$LONG.stopping"; sleep 1; echo > "$LONG.slow"; exit 143' TERM
  [ -z "${IGNORE_TERM:-}" ] || trap '' TERM
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
t0=$(date +%s)
out=$(echo "THE CALLER'S INPUT" | PATH="$T/bin:$PATH" timeout -k 5 60 bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 \
  schnappy 2>&1)
rc=$?
took=$(( $(date +%s) - t0 ))
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
check "it ends once its checks have: the bound's watchdog not waited out" "$([ "$took" -lt 15 ] && echo prompt || echo "$took s")" \
  prompt
# the bound: a whole number of seconds (no number: sleep fails at once - no bound at all), above every check's own -
# each check playbook's until retries and delays summed, the play's vars rendered, and each try's own time (PER_TRY: a
# try is one command over ssh - kubectl, psql, curl - its seconds; none of them carries a timeout of its own, and the
# delays alone left the data check 2 s a try under the old bound); the smoke's own 15 minutes
out=$(STEP_CHECKS_SECONDS=30m PATH="$T/bin:$PATH" timeout -k 5 30 bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 \
  schnappy < /dev/null 2>&1); rc=$?
check "a bound that is no whole number of seconds: refused before any check" \
  "$rc $(grep -c 'not a whole number' <<< "$out") $(grep -c '^===== check' <<< "$out")" "1 1 0"
budget=$(cd "$ROOT" && PY=python3 && { python3 -c 'import ansible' 2> /dev/null || PY=deploy/ansible/venv/bin/python3; } \
  && PYTHONDONTWRITEBYTECODE=1 "$PY" -c '
import re, sys
import yaml
sys.path.insert(0, "tests/ansible/unit")
from templar import render, trust_as_template
def walk(ts):
    for t in ts or []:
        yield t
        for k in ("block", "rescue", "always"):
            yield from walk(t.get(k))
PER_TRY = 5
worst = int(re.search(r"SMOKE_SECONDS:-(\d+)", open("scripts/vagrant-smoke.sh").read()).group(1))
for c in ("data", "survival", "storage", "metrics"):
    total = 0
    for p in yaml.safe_load(open(f"tests/ansible/upgrade/{c}-check.yml")):
        v = {k: trust_as_template(x) if isinstance(x, str) else x for k, x in (p.get("vars") or {}).items()}
        for t in walk(p.get("tasks")):
            if "until" in t:
                total += (int(render(str(t.get("retries", 3)), **v)) + 1) * (int(render(str(t.get("delay", 5)), **v))
                                                                              + PER_TRY)
    worst = max(worst, total)
print(worst)')
default=$(grep -oP 'bound=\$\{STEP_CHECKS_SECONDS:-\K[0-9]+' "$ROOT/scripts/upgrade-step-checks.sh")
check "the bound by default above every check's own (the longest: $budget s)" \
  "$([ -n "$budget" ] && [ -n "$default" ] && [ "$default" -gt "$budget" ] && echo above || echo "${default:-none} vs ${budget:-none}")" \
  above

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

# a TERM between a job's start and its record (its PID not kept yet): stopped with the others, at once - not waited
# out. Forced in a copy: the TERM sent right after the storage check's start, or the watchdog's
for at in storage watchdog; do
  if [ $at = storage ]; then
    sed 's|^  "\$@" > "\$logs/\$name" 2>&1 < /dev/null &$|&\n  [ "$name" != storage ] \|\| kill -TERM $$|' \
      "$T/scripts/upgrade-step-checks.sh" > "$T/scripts/unrecorded.sh"
  else
    sed 's|^  && : > "\$logs/timed-out" && kill -TERM \$\$ ) < /dev/null > /dev/null 2>&1 &$|&\nkill -TERM $$|' \
      "$T/scripts/upgrade-step-checks.sh" > "$T/scripts/unrecorded.sh"
  fi
  check "the copy with a TERM before the $at's record made" "$(grep -c '^ *\(\[.*\] || \)\?kill -TERM \$\$$' "$T/scripts/unrecorded.sh")" 1
  rm -f "$T/long.pid" "$T/long.pid.finished"
  t0=$(date +%s)
  out=$(LONG="$T/long.pid" STEP_CHECKS_SECONDS=20 PATH="$T/bin:$PATH" timeout -k 5 60 \
    bash "$T/scripts/unrecorded.sh" i p 24.8 schnappy < /dev/null 2>&1); rc=$?
  took=$(( $(date +%s) - t0 ))
  check "a TERM before the $at's PID was kept: the run ends at once (130), the storage check stopped, not run out" \
    "$rc $([ "$took" -lt 8 ] && echo prompt || echo "$took s") $([ -e "$T/long.pid.finished" ] && echo finished || echo stopped)" \
    "130 prompt stopped"
done
# the bound reached just as the last check ended (its TERM after the verdict's loop): every check judged - the verdict
# stands, nothing "not judged". Forced in a copy: the watchdog's act right after the loop
sed 's|^own_jobs left_$|: > "$logs/timed-out"; kill -TERM $$\n&|' "$T/scripts/upgrade-step-checks.sh" \
  > "$T/scripts/late.sh"
check "the copy with the bound's act after the loop made" "$(grep -c '^: > "\$logs/timed-out"; kill -TERM \$\$$' "$T/scripts/late.sh")" 1
out=$(ALL_PASS=1 PATH="$T/bin:$PATH" timeout -k 5 60 bash "$T/scripts/late.sh" i p 24.8 schnappy < /dev/null 2>&1); rc=$?
check "the bound reached after every check was judged: the verdict stands (passed), nothing said not judged" \
  "$rc $(grep -c '^STEP CHECKS PASSED' <<< "$out") $(grep -c 'NOT JUDGED\|not ended within' <<< "$out")" "0 1 0"
# the script killed outright (no cleanup runs): its watchdog, left behind, signals nothing when its bound comes - its
# parent gone, the PID may be another process's. Forced in a copy that waits after starting its checks
sed 's|^watchdog=\$!$|&\necho "$watchdog" > "$logs/watchdog.pid"; sleep 6|' "$T/scripts/upgrade-step-checks.sh" \
  > "$T/scripts/killed.sh"
check "the copy that waits made (its watchdog kept, then its PID written)" \
  "$(grep -c '^watchdog=\$!$' "$T/scripts/killed.sh") $(grep -c '^echo "\$watchdog" > "\$logs/watchdog.pid"; sleep 6$' "$T/scripts/killed.sh")" "1 1"
rm -rf "$T/.upgrade"/step-checks.*
ALL_PASS=1 STEP_CHECKS_SECONDS=2 PATH="$T/bin:$PATH" bash "$T/scripts/killed.sh" i p 24.8 schnappy < /dev/null \
  > /dev/null 2>&1 &
sp=$!
# the watchdog started (its PID written), then the script killed
timeout 10 bash -c 'until ls "$0"/step-checks.*/watchdog.pid > /dev/null 2>&1; do sleep 0.1; done' "$T/.upgrade"
wd=$(cat "$T/.upgrade"/step-checks.*/watchdog.pid 2> /dev/null)
if [ "$(proc_info "$sp" | awk '{print $1, $4}')" = "$$ bash" ]; then
  kill -KILL "$sp"
fi
wait "$sp" 2> /dev/null
# its bound come and gone: the watchdog ended (10 s at most) - not a fixed wait
timeout 10 bash -c 'while [ -n "$0" ] && [ -e "/proc/$0" ]; do sleep 0.1; done' "${wd:-}"
check "killed outright: the watchdog's PID read, its bound come and gone" "$([ -n "$wd" ] && [ ! -e "/proc/$wd" ] && echo gone || echo "${wd:-no pid}")" gone
check "killed outright: its watchdog's bound, come, signals nothing (no timed-out mark)" \
  "$(ls "$T/.upgrade"/step-checks.*/timed-out 2> /dev/null | wc -l)" 0
rm -rf "$T/.upgrade"/step-checks.*
# a check that ignores a TERM: killed after the grace, said - its process gone, the run ended
rm -f "$T/long.pid" "$T/long.pid.finished"
LONG="$T/long.pid" IGNORE_TERM=1 STOP_GRACE=1 PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 \
  schnappy < /dev/null > "$T/ignore.out" 2>&1 &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ]; do sleep 0.1; done' "$T/long.pid"
t0=$(date +%s)
if [ "$(proc_info "$sp" | awk '{print $1, $4}')" = "$$ bash" ]; then
  kill -TERM "$sp"
fi
wait "$sp"; rc=$?
took=$(( $(date +%s) - t0 ))
out=$(cat "$T/ignore.out")
check "a check ignoring the TERM: killed after the grace, said; its process gone, the run ended at once after" \
  "$rc $(grep -c 'outlived the stop by 1 s - killed' <<< "$out") $(gone "$T/long.pid") $([ "$took" -lt 8 ] && echo prompt || echo "$took s")" \
  "130 1 gone prompt"

# the stop's grace a whole number of seconds, refused before any check otherwise: a fraction aborted the cleanup's
# arithmetic - nothing KILLed, the checks left running
out=$(STOP_GRACE=1.5 PATH="$T/bin:$PATH" timeout -k 5 30 bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy \
  < /dev/null 2>&1); rc=$?
check "STOP_GRACE=1.5: refused before any check, said" \
  "$rc $(grep -c '^STOP_GRACE=1.5: not a whole number of seconds$' <<< "$out") $(grep -c '^===== check' <<< "$out")" "1 1 0"
# the output's reader gone before the TERM (a tee a Ctrl-C ended): the check ignoring the TERM KILLed all the same, the
# run's work directory removed - a write first ended the cleanup (SIGPIPE) with the check left running
rm -f "$T/long.pid" "$T/long.pid.finished"; rm -rf "$T/.upgrade"/step-checks.*
mkfifo "$T/pipe"
cat "$T/pipe" > /dev/null & reader=$!
LONG="$T/long.pid" IGNORE_TERM=1 STOP_GRACE=1 PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 \
  schnappy < /dev/null > "$T/pipe" 2>&1 &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ]; do sleep 0.1; done' "$T/long.pid"
[ "$(proc_info "$reader" | awk '{print $1, $4}')" = "$$ cat" ] && kill "$reader"
wait "$reader" 2> /dev/null
if [ "$(proc_info "$sp" | awk '{print $1, $4}')" = "$$ bash" ]; then
  kill -TERM "$sp"
fi
wait "$sp"; rc=$?
out=""
check "the output's reader gone: the check ignoring the TERM KILLed all the same, the work directory gone, 130" \
  "$rc $(gone "$T/long.pid") $(ls -d "$T/.upgrade"/step-checks.* 2> /dev/null | wc -l)" "130 gone 0"
pid=$(cat "$T/long.pid" 2> /dev/null)
if [ -n "$pid" ] && [ "$(proc_info "$pid" | awk '{print $4}')" = ansible-playbook ]; then kill -KILL "$pid"; fi
rm -f "$T/pipe"

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
rm -f "$T/long.pid" "$T/long.pid.slow" "$T/long.pid.stopping" "$T/long.pid.finished"; rm -rf "$T/.upgrade"/step-checks.*
LONG="$T/long.pid" SLOW_TERM=1 PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy \
  < /dev/null > "$T/twice.out" 2>&1 &
sp=$!
timeout 10 bash -c 'until [ -s "$0" ]; do sleep 0.1; done' "$T/long.pid"
if [ "$(proc_info "$sp" | awk '{print $1, $4}')" = "$$ bash" ]; then
  # the second once the check's own stop has begun - inside the cleanup's wait
  kill -TERM "$sp"
  timeout 10 bash -c 'until [ -e "$0" ]; do sleep 0.05; done' "$T/long.pid.stopping"
  kill -TERM "$sp" 2> /dev/null
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
