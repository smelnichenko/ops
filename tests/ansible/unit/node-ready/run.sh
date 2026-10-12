#!/bin/bash
# The node-Ready wait (tests/ansible/upgrade/tasks/node-ready.yml) on localhost against a stub kubectl that refuses its
# first connections as an API server still starting does (kubectl wait fails on them at once, it does not wait).
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "node-ready: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
cat > "$stub/kubectl" <<'STUB'
#!/bin/sh
# counts its calls, records its arguments; refuses the first $STUB_REFUSALS as a starting API server does
n=$(( $(cat "$STUB_DIR/calls") + 1 )); echo "$n" > "$STUB_DIR/calls"; echo "$*" > "$STUB_DIR/args"
if [ "$n" -le "$STUB_REFUSALS" ]; then
  echo "The connection to the server 192.168.56.10:6443 was refused - did you specify the right host or port?" >&2
  exit 1
fi
echo "node/kubeadm condition met"
STUB
chmod +x "$stub/kubectl"
out=$(ANSIBLE_NOCOLOR=1 "$AP" -i localhost, -c local "$H/cases.yml" -e stub_dir="$stub" -e ansible_env_path="$PATH" 2>&1)
rc=$?
printf '%s\n' "$out" | grep -oE '"msg": "(PASS|FAIL) [^"]*"' | sed 's/"msg": "//; s/"$//'
n=$(printf '%s\n' "$out" | grep -cE '"msg": "PASS ')
want=$(grep -c "want: " "$H/cases.yml")
[ $rc -eq 0 ] && [ "$n" -eq "$want" ] && echo "node-ready: ALL-PASS" \
  || { printf '%s\n' "$out" | tail -15; echo "node-ready: FAILED (rc $rc, $n of $want passed)"; exit 1; }
