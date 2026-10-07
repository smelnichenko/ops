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
# LONG=<file>: the storage check runs on (its PID in the file) - until the script's cleanup stops it
case "$*" in *storage-check*) [ -z "${LONG:-}" ] || { echo $$ > "$LONG"; sleep 30; } ;; esac
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
fails=0
check() {
  if [ "$2" = "$3" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got $2, want $3"; printf '%s\n' "$out" | sed 's/^/    /'; fails=$((fails + 1))
}
check "no check read the caller's stdin" "$(grep -c "THE CALLER'S INPUT" <<< "$out")" 0
check "five checks judged" "$(grep -c '^===== check ' <<< "$out")" 5
check "the failing one named, the run failed" "$rc $(grep -o 'STEP CHECKS FAILED: metrics' <<< "$out")" \
  "1 STEP CHECKS FAILED: metrics"

# a "check" that is no child of the script: its own process, started here - a sleep in a session of its own (job
# control off, so setsid does not fork: $! is the sleep), proven so before its PID is used, killed by this test alone.
# wait -n can never return it: the script must say so (its guard), and its cleanup must signal only its own jobs' groups
# - a PID it did not start (1 would be `kill -- -1`: every process of the user) never
set +m
setsid sleep 1000 < /dev/null > /dev/null 2>&1 &
ghost=$!
read -r gpid gpgid gsid gcomm <<< "$(ps -o pid=,pgid=,sid=,comm= -p "$ghost")"
if [ "$gpid $gpgid $gsid $gcomm" != "$ghost $ghost $ghost sleep" ]; then
  echo "FAIL the test's own process is not a session-leading sleep ($gpid $gpgid $gsid $gcomm) - not used"
  exit 1
fi
trap 'kill "$ghost" 2> /dev/null; rm -rf "$T"' EXIT
sed -i 's|^start smoke scripts/vagrant-smoke.sh "$infra_ref" "$platform_ref"$|&\nnames+=(ghost); pids+=("$GHOST")|' \
  "$T/scripts/upgrade-step-checks.sh"
check "the ghost added to the copy" "$(grep -c 'pids+=("$GHOST")' "$T/scripts/upgrade-step-checks.sh")" 1
out=$(GHOST=$ghost LONG="$T/long.pid" PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy \
  < /dev/null 2>&1)
rc=$?
check "wait -n with no check ended: the guard says so, the run fails" \
  "$rc $(grep -c 'with no check ended - the rest not judged' <<< "$out")" "1 1"
check "its cleanup signalled only its own jobs: the foreign process lives" \
  "$(ps -o comm= -p "$ghost" 2> /dev/null)" sleep
check "and stopped its own: the storage check still running then is gone" \
  "$([ -s "$T/long.pid" ] && { ps -p "$(cat "$T/long.pid")" > /dev/null && echo running || echo gone; })" gone
if [ "$fails" = 0 ]; then echo "step-checks: ALL-PASS"; else echo "step-checks: $fails FAILED"; exit 1; fi
