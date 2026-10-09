#!/bin/bash
# Planner statistics after a PostgreSQL major upgrade (deploy/ansible/playbooks/postgres-analyze.yml): from 18 on
# pg_upgrade carries most statistics over, but not the extended ones (CREATE STATISTICS) nor the cumulative ones that
# trigger autovacuum. PostgreSQL 18's pg_upgrade docs: first `vacuumdb --all --analyze-in-stages --missing-stats-only`
# (minimal statistics where there are none, fast), then `vacuumdb --all --analyze-only` (every relation analysed) - on
# each cluster's primary, in that order; nothing in a preview. A major below 18 is refused: its vacuumdb has no
# --missing-stats-only. The playbook run on localhost, kubectl a stub logging its calls.
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
case "$*" in
  *" get clusters.postgresql.cnpg.io -A "*) printf 'ns-a pg\nns-b pg\n' ;;
  *" get clusters.postgresql.cnpg.io pg -o json") echo '{"spec": {"instances": 2}, "status": {"phase": "Cluster in healthy state", "readyInstances": 2, "currentPrimary": "pg-1"}}' ;;
  *" get clusters.postgresql.cnpg.io pg -o jsonpath="*) printf 'pg-1' ;;
  *" exec pg-1 -c postgres -- psql "*) echo "${VERSION:-180006}" ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/postgres-analyze.yml"))
for p in play:
    p.pop("become", None)
    p["hosts"] = "target"
    for t in p["tasks"]:  # the stub answers at once: no 15 s between the health checks' tries
        if "delay" in t:
            t["delay"] = 0
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
run() {  # run <major> [env...]: the rc and the vacuumdb calls made, in order (namespace and arguments)
  local major=$1; shift
  : > "$W/calls"
  env "$@" PATH="$W/bin:$PATH" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" -e pg_major="$major" \
    ${CHECK:+--check} > "$W/out" 2>&1
  echo "rc=$? $(grep ' vacuumdb ' "$W/calls" | sed -E 's/.* -n ([^ ]+) exec pg-1 -c postgres -- vacuumdb (.*)/\1: \2/' | paste -sd'|')"
}
S1="--all --analyze-in-stages --missing-stats-only" S2="--all --analyze-only"
check "18: on each primary, the missing statistics in stages, then every relation analysed" \
  "$(run 18)" "rc=0 ns-a: $S1|ns-a: $S2|ns-b: $S1|ns-b: $S2"
check "a preview: nothing run" "$(CHECK=1 run 18)" "rc=0 "
check "a cluster not yet on the major: waits, never analysed" "$(run 18 VERSION=170005 | cut -c1-5)" "rc=2 "
# a cluster on 17 (the stub says so): refused before anything is read, not analysed with a recipe 17 lacks
check "17 refused (its vacuumdb has no --missing-stats-only)" \
  "$(run 17 VERSION=170005) $(grep -c . "$W/calls")" "rc=2  0"
# the steps that move a cluster's major (their statistics line): their abort starts with CNPG's own rollback - the
# upgrade Job failed, the image reverted, the operator deletes the Job and starts the old major on its data, which the
# upgrade never changed (pg_upgrade --link into new directories, swapped in only on success; CNPG's major-upgrade docs)
for f in $(grep -l '^playbook postgres-analyze\.yml' tests/ansible/upgrade/steps/*.txt); do
  check "$(basename "$f" .txt): its abort starts with the failed upgrade Job's revert" \
    "$(grep -m1 '^# abort:' "$f" | grep -c 'upgrade Job failed.*revert')" 1
done
check "  the steps found" "$(grep -l '^playbook postgres-analyze\.yml' tests/ansible/upgrade/steps/*.txt | wc -l)" 2
echo "postgres-analyze: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
