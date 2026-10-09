#!/bin/bash
# deploy/ansible/playbooks/production-data-check.yml - every step's check reads that the data paths work, production's
# (upgrade-production.py's check) and the full run's: green when every source answers well; red on a target down, a
# stale Mimir, no log rows, a datasource not OK, an unhealthy CNPG cluster or a replica not streaming, WAL archiving
# failing, a Kafka not Ready, a ScyllaDB node not UN, a critical alert firing - unless the inventory names what the
# environment lacks by nature (the copy's smartctl target, its PublicEndpointDown). Read only: no kubectl verb that
# writes. The playbook on localhost, kubectl a stub playing every source; then its wiring.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0
check() {  # check <name> <got> <want>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi
}
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "$W/calls"
a=" $* "
case "$a" in
  *"targets?state=active"*)
    echo "{\"data\": {\"activeTargets\": [{\"scrapePool\": \"a\", \"scrapeUrl\": \"u\", \"health\": \"up\", \"lastError\": \"\"},
      {\"scrapePool\": \"smart\", \"scrapeUrl\": \"s\", \"health\": \"${SMART:-up}\", \"lastError\": \"x\"}]}}" ;;
  *"max(timestamp(up))"*) echo "{\"data\": {\"result\": [{\"value\": [0, \"$(( $(date +%s) - ${MIMIR_AGE:-5} ))\"]}]}}" ;;
  *"component=clickhouse"*) echo schnappy-clickhouse-0 ;;
  *"clickhouse-client"*) echo "${LOG_ROWS:-42}" ;;
  *"/api/datasources/uid/"*) echo "{\"status\": \"${DS:-OK}\"}" ;;
  *"/api/datasources"*) echo '[{"uid": "prom"}, {"uid": "ch"}]' ;;
  *" get clusters.postgresql.cnpg.io "*)
    echo "{\"items\": [{\"metadata\": {\"namespace\": \"p\", \"name\": \"pg\"}, \"spec\": {\"instances\": 2},
      \"status\": {\"phase\": \"${PG_PHASE:-Cluster in healthy state}\", \"readyInstances\": 2, \"currentPrimary\": \"pg-1\",
      \"conditions\": [{\"type\": \"ContinuousArchiving\", \"status\": \"${ARCHIVING:-True}\"}]}}]}" ;;
  *"pg_stat_replication"*) echo "${STREAMING:-1}" ;;
  *" get kafkas.kafka.strimzi.io "*)
    echo "{\"items\": [{\"metadata\": {\"namespace\": \"p\", \"name\": \"k\"}, \"status\": {\"conditions\": [
      {\"type\": \"Warning\", \"status\": \"True\"}, {\"type\": \"Ready\", \"status\": \"${KAFKA:-True}\"}]}}]}" ;;
  *"pod-type=scylladb-node"*) printf 'p scylla-0\n' ;;
  *"nodetool status"*) printf 'Datacenter: dc1\n--  Address  Load\n%s  10.0.0.1  1 MB\n' "${SCYLLA:-UN}" ;;
  *"/api/v1/alerts"*)
    extra=""
    [ -z "${ALERT:-}" ] || extra=", {\"state\": \"firing\", \"labels\": {\"alertname\": \"$ALERT\", \"severity\": \"critical\"}}"
    echo "{\"data\": {\"alerts\": [{\"state\": \"firing\", \"labels\": {\"alertname\": \"Watchdog\", \"severity\": \"none\"}}$extra]}}" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/production-data-check.yml"))
for p in play:
    p.pop("become", None)
    p["hosts"] = "target"
    for t in p["tasks"]:  # the stub answers at once: one try
        if "retries" in t:
            t["retries"], t["delay"] = 1, 0
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
run() {  # run <env...> [-- -e ...]: the rc
  : > "$W/calls"
  local args=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do args+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  env "${args[@]}" PATH="$W/bin:$PATH" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" -e kubeconfig=/x "$@" \
    > "$W/out" 2>&1
  echo "rc=$?"
}
check "every source well: green" "$(run X=1)" "rc=0"
check "  said" "$(grep -c 'DATA PATHS OK' "$W/out")" 1
check "  nothing written: get, get --raw and exec only" \
  "$(grep -oE '^kubectl (--kubeconfig \S+ )?(-n \S+ )?[a-z]+' "$W/calls" | awk '{print $NF}' | sort -u | paste -sd,)" "exec,get"
check "a target down: red" "$(run SMART=down)" "rc=2"
check "  the environment's own down target named in its inventory: green" \
  "$(run SMART=down -- -e '{"production_check_allowed_down": ["smart"]}')" "rc=0"
check "Mimir's newest sample 5 minutes old: red" "$(run MIMIR_AGE=300)" "rc=2"
check "no log rows: red" "$(run LOG_ROWS=0)" "rc=2"
check "a datasource not OK: red" "$(run DS=ERROR)" "rc=2"
check "a CNPG cluster not healthy: red" "$(run 'PG_PHASE=Waiting for the instances to become active')" "rc=2"
check "a replica not streaming: red" "$(run STREAMING=0)" "rc=2"
check "WAL archiving failing: red" "$(run ARCHIVING=False)" "rc=2"
check "a Kafka not Ready (its Warning beside Ready does not count): red" "$(run KAFKA=False)" "rc=2"
check "a ScyllaDB node down: red" "$(run SCYLLA=DN)" "rc=2"
check "a critical alert firing: red" "$(run ALERT=PostgreSQLDown)" "rc=2"
check "  one the inventory names: green" \
  "$(run ALERT=PublicEndpointDown -- -e '{"production_check_allowed_firing": ["PublicEndpointDown"]}')" "rc=0"
# its wiring: production's check runs it; the full run's step task runs it on the copy; the copy names its own
check "production's check runs it" \
  "$(sed -n '/^def check(step/,/^def done/p' scripts/upgrade-production.py | grep -c 'production-data-check.yml')" 1
# on the copy: one of the step's parallel checks (no time of its own), not a command after them
check "the full run runs it on the copy among the step's parallel checks, not after them" "$("$PY" -c '
import yaml
c = [str(x.get("cmd", x) if isinstance(x, dict) else x) for x in yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:upgrade:step"]["cmds"]]
print(any("production-data-check.yml" in x for x in c))') \
$(grep -cx 'start prod play playbooks/production-data-check.yml' scripts/upgrade-step-checks.sh)" "False 1"
check "the copy's inventory names its smartctl target and PublicEndpointDown; production's names none" "$("$PY" -c '
import yaml
v = yaml.safe_load(open("deploy/ansible/inventory/vagrant.yml"))["all"]["vars"]
p = open("deploy/ansible/inventory/production.yml").read()
print(v.get("production_check_allowed_down"), v.get("production_check_allowed_firing"), "production_check_allowed" in p)')" \
  "['scrapeConfig/schnappy-infra/schnappy-smartctl-exporter'] ['PublicEndpointDown'] False"
echo "production-data-check: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
