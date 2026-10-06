#!/bin/bash
# setup-patroni's guard before a first install clears a Pi's data directory (tasks/patroni-leader-guard.yml), on
# localhost with a stub consul: no leader key ("No key exists") goes on; another node the leader goes on; this node
# the leader refuses; Consul unreachable refuses (it went on: the incident a re-run comes in cleared the data).
set -u
H=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$H/../../../.." && pwd)
AP=$(command -v ansible-playbook 2>/dev/null \
  || { [ -x "$ROOT/deploy/ansible/venv/bin/ansible-playbook" ] && echo "$ROOT/deploy/ansible/venv/bin/ansible-playbook"; })
[ -x "${AP:-}" ] || { echo "patroni-leader-guard: no ansible-playbook found (PATH, repo venv)"; exit 2; }
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
# the stub: LEADER=<node> answers it, LEADER= (empty) the missing key's error, DOWN=1 an unreachable agent - for the
# cluster's leader key only: any other key does not exist (a guard reading the wrong one would always go on)
cat > "$W/consul" <<'STUB'
#!/bin/sh
if [ "${DOWN:-}" = 1 ]; then
  echo 'Error querying Consul agent: Get "http://127.0.0.1:8500/v1/kv/x": dial tcp 127.0.0.1:8500: connect: connection refused' >&2
  exit 1
fi
if [ "$*" != "kv get service/schnappy-postgres/leader" ]; then echo "Error! No key exists at: $3" >&2; exit 1; fi
if [ -z "${LEADER:-}" ]; then echo "Error! No key exists at: $3" >&2; exit 1; fi
echo "$LEADER"
STUB
chmod +x "$W/consul"
cat > "$W/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  vars:
    patroni_scope: schnappy-postgres
    _patroni_first_install: true
  tasks:
    - ansible.builtin.include_tasks: $ROOT/deploy/ansible/playbooks/tasks/patroni-leader-guard.yml
PLAY
fails=0
case_() {  # name, want (0 goes on / 1 refused), output must contain, env...
  local name=$1 want=$2 grep=$3; shift 3
  out=$(env PATH="$W:$PATH" "$@" ANSIBLE_NOCOLOR=1 "$AP" -c local -i localhost, "$W/play.yml" 2>&1); rc=$?
  [ "$rc" = 0 ] || rc=1
  if [ "$rc" = "$want" ] && { [ -z "$grep" ] || grep -qF -- "$grep" <<< "$out"; }; then echo "PASS $name"
  else echo "FAIL $name (rc $rc, want $want)"; printf '%s\n' "$out" | tail -4 | sed 's/^/    /'; fails=$((fails + 1)); fi
}
case_ "no leader key: goes on" 0 "" LEADER=
case_ "another node the leader: goes on" 0 "" LEADER=pi1
case_ "this node the leader: refused" 1 "REFUSED on localhost" LEADER=localhost
case_ "Consul unreachable: refused" 1 "connection refused" DOWN=1
echo "patroni-leader-guard: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
