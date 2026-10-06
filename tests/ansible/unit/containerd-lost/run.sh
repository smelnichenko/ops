#!/bin/bash
# upgrade-containerd's check before the kubelet starts again (tasks/containerd-known-containers.yml): every container
# that ran before the swap known to the runtime - running or exited - or the run fails and the kubelet stays stopped.
# On localhost with a stub crictl: all running passes; one exited meanwhile (a finished Job) passes; one gone fails,
# naming it; crictl failing fails (closed) - its exited listing alone too, with every container running.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "containerd-lost: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
# the stub: RUNNING / EXITED (space-separated ids) answer the two listings; FAIL=1 fails both, FAIL=exited that one
cat > "$W/crictl" <<'STUB'
#!/bin/sh
[ "${FAIL:-}" = 1 ] && { echo "connection refused" >&2; exit 1; }
[ "${FAIL:-}" = exited ] && [ "$*" = "ps -a -q --state exited" ] && { echo "connection refused" >&2; exit 1; }
case "$*" in
  "ps -q --state running") for c in $RUNNING; do echo "$c"; done ;;
  "ps -a -q --state exited") for c in $EXITED; do echo "$c"; done ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$W/crictl"
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars:
    crictl: $W/crictl
    _before: {stdout_lines: [aaa, bbb, ccc]}
  tasks:
    - ansible.builtin.include_tasks: $ROOT/deploy/ansible/playbooks/tasks/containerd-known-containers.yml
PLAY
fails=0
case_() {  # name, want (0 passes / 1 fails), output must contain, env...
  local name=$1 want=$2 grep=$3; shift 3
  out=$(env "$@" ANSIBLE_NOCOLOR=1 "$AP" -c local -i localhost, "$W/play.yml" 2>&1); rc=$?; [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$want" ] && { [ -z "$grep" ] || grep -qF -- "$grep" <<< "$out"; }; then echo "PASS $name"
  else echo "FAIL $name (rc $rc, want $want)"; printf '%s\n' "$out" | tail -5 | sed 's/^/    /'; fails=$((fails + 1)); fi
}
case_ "all still running" 0 "" RUNNING="aaa bbb ccc" EXITED=""
case_ "one exited meanwhile (a finished Job): not lost" 0 "" RUNNING="aaa bbb" EXITED="ccc"
case_ "one the runtime knows no more: lost, named" 1 "CONTAINERS LOST: bbb" RUNNING="aaa ccc" EXITED=""
case_ "crictl failing: refused" 1 "CONTAINERS LOST" FAIL=1 RUNNING="" EXITED=""
case_ "the exited listing failing, every container running: refused (its rc, not a lost one)" 1 "connection refused" \
  FAIL=exited RUNNING="aaa bbb ccc" EXITED=""
echo "containerd-lost: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
