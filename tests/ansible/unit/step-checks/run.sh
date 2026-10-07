#!/bin/bash
# scripts/upgrade-step-checks.sh with every check stubbed, in a copy of its tree: each check's exit judged as its own;
# a check reads nothing of the caller's stdin (job control gave the jobs the caller's pipe - one that read it would
# take the caller's input, or stop on SIGTTIN from a terminal while wait -n waited for ever).
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/deploy/ansible/venv/bin" "$T/bin" "$T/.upgrade"
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
case "$*" in *storage-check*) [ -z "${LONG:-}" ] || { echo $$ > "$LONG"; sleep 30; echo > "$LONG.finished"; } ;; esac
got=$(timeout 1 cat 2> /dev/null || true)
echo "check $* read stdin: [$got]"
case "$*" in *metrics-check*) exit 1 ;; esac
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
check "a TERM to the script: it ends (130), the check still running stopped, not run to its end" \
  "$rc $([ -e "$T/long.pid.finished" ] && echo finished || echo stopped)" "130 stopped"

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
  "$rc $(grep -c 'with no check ended - the rest not judged' <<< "$out")" "1 1"
check "its cleanup signalled only its own jobs: the foreign process lives" \
  "$(proc_info "$ghost" | awk '{print $4}')" sleep
if [ "$fails" = 0 ]; then echo "step-checks: ALL-PASS"; else echo "step-checks: $fails FAILED"; exit 1; fi
