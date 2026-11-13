#!/bin/bash
# Scylla Manager still backs up on the Vagrant copy, and after a change that moves it, ScyllaDB or the agents
# (test:copy:check): deploy/ansible/playbooks/scylla-backup-check.yml refuses a backup or repair task whose last
# run failed, a production cluster without a backup task; starts each production cluster's backup task (the test
# environment's has none: skipped by name) and wants it DONE with a snapshot this run took - its tag no older than the
# node's clock at the start (right after the start `sctool progress` may still show the last run, DONE). A preview
# reads only. The playbook on localhost, kubectl and date stubs playing Scylla Manager; then its wiring.
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
PROD=a8548f9c-d7ca-4860-ae70-62c9a01f9a31 TEST=b1111111-d7ca-4860-ae70-62c9a01f9a31 OTHER=c2222222-d7ca-4860-ae70-62c9a01f9a31
mkdir "$W/bin"
cat > "$W/bin/date" <<'STUB'
#!/bin/bash
echo 20261009150000
STUB
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
echo "kubectl $*" >> "$W/calls"
a=" $* "
row() { printf '| %s | | %s | | | 1 | 0 | | | %s | |\n' "$1" "$2" "$3"; }
case "$a" in
  *" sctool cluster list "*)
    echo "| ID | Name | Labels | Port | Credentials |"
    echo "| $PROD | schnappy-production/schnappy-production-scylla | x | default | |"
    [ -n "${NO_TEST:-}" ] || echo "| $TEST | schnappy-test/schnappy-test-scylla | x | default | |"
    [ -z "${OTHER_CLUSTER:-}" ] || echo "| $OTHER | schnappy-other/schnappy-other-scylla | x | default | |" ;;
  *" sctool tasks -c $OTHER "*)
    echo "| Task | Labels | Schedule | Window | Timezone | Success | Error | Last Success | Last Error | Status | Next |"
    row healthcheck/cql "* * * * *" DONE ;;
  *" sctool tasks -c $PROD "*)
    echo "| Task | Labels | Schedule | Window | Timezone | Success | Error | Last Success | Last Error | Status | Next |"
    [ -n "${NO_BACKUP:-}" ] || row backup/schnappy-production-daily-backup "0 3 * * *" "${BACKUP_STATUS:-DONE}"
    row healthcheck/cql "* * * * *" ERROR
    row repair/schnappy-production-weekly-repair "0 4 * * 0" "${REPAIR_STATUS:-NEW}" ;;
  *" sctool tasks -c $TEST "*)
    echo "| Task | Labels | Schedule | Window | Timezone | Success | Error | Last Success | Last Error | Status | Next |"
    row healthcheck/cql "* * * * *" DONE ;;
  *" sctool start "*) : ;;
  *" sctool progress "*)
    printf 'Run:\t\tx\nStatus:\t\t%s\nSnapshot Tag:\t%s\n' "${PROGRESS:-DONE}" "${TAG:-sm_20261009150012UTC}" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$W/bin/date" "$W/bin/kubectl"
[ -f deploy/ansible/playbooks/scylla-backup-check.yml ] && W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/scylla-backup-check.yml"))
for p in play:
    p.pop("become", None)
    p["hosts"] = "target"
    for t in p["tasks"]:  # the stub answers at once: a few tries, no wait between them
        if "retries" in t:
            t["retries"], t["delay"] = 2, 0
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
run() {  # run <env...>: rc and the clusters backups were started on
  : > "$W/calls"
  [ -f "$W/play.yml" ] || { echo "no playbook"; return; }
  env "$@" PATH="$W/bin:$PATH" W="$W" PROD=$PROD TEST=$TEST OTHER=$OTHER ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" \
    -e kubeconfig=/x ${CHECK:+--check} > "$W/out" 2>&1
  echo "rc=$? started=$(grep -o -- 'sctool start -c [a-z0-9-]*' "$W/calls" | cut -c17-24 | paste -sd,)"
}
check "healthy: the production cluster's backup started, DONE with this run's snapshot; the test cluster skipped" \
  "$(run)" "rc=0 started=a8548f9c"
check "  the test cluster said skipped" "$(grep -c 'SKIPPED schnappy-test' "$W/out")" 1
check "a preview: tasks read, no backup started" "$(CHECK=1 run)" "rc=0 started="
check "a repair task whose last run failed: refused, nothing started" "$(run REPAIR_STATUS=ERROR)" "rc=2 started="
check "the backup task's last run aborted: refused" "$(run BACKUP_STATUS=ABORTED)" "rc=2 started="
check "a production cluster with no backup task: refused" "$(run NO_BACKUP=1)" "rc=2 started="
check "  beside one that has one: refused all the same, nothing started" "$(run OTHER_CLUSTER=1)" "rc=2 started="
check "the backup ends in ERROR: failed" "$(run PROGRESS=ERROR | cut -c1-4)" "rc=2"
check "DONE with the last run's snapshot (older than the start): failed" \
  "$(run TAG=sm_20261008030049UTC | cut -c1-4)" "rc=2"
check "the healthchecks' errors are not the backup's" "$(run NO_TEST=1)" "rc=0 started=a8548f9c"
# every check of the copy runs it on the copy (a change's too)
check "test:copy:check runs it on the copy" "$("$PY" -c '
import yaml
c = [str(x.get("cmd", x) if isinstance(x, dict) else x) for x in yaml.safe_load(open("Taskfile.yml"))["tasks"]["test:copy:check"]["cmds"]]
print(sum("playbooks/scylla-backup-check.yml" in x and "inventory/vagrant.yml" in x for x in c))')" "1"
echo "scylla-backup-check: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
