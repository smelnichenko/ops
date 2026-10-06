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
out=$(echo "THE CALLER'S INPUT" | PATH="$T/bin:$PATH" bash "$T/scripts/upgrade-step-checks.sh" i p 24.8 schnappy 2>&1); rc=$?
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got $2, want $3"; printf '%s\n' "$out" | sed 's/^/    /'; fails=$((fails + 1)); fi; }
check "no check read the caller's stdin" "$(grep -c "THE CALLER'S INPUT" <<< "$out")" 0
check "five checks judged" "$(grep -c '^===== check ' <<< "$out")" 5
check "the failing one named, the run failed" "$rc $(grep -o 'STEP CHECKS FAILED: metrics' <<< "$out")" \
  "1 STEP CHECKS FAILED: metrics"
if [ "$fails" = 0 ]; then echo "step-checks: ALL-PASS"; else echo "step-checks: $fails FAILED"; exit 1; fi
