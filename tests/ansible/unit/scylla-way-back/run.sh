#!/bin/bash
# The way back from a ScyllaDB release line (deploy/ansible/playbooks/scylla-way-back.yml, tasks/scylla-way-back.yml):
# nothing is deleted until every check before it passed - the cluster confirmed by name, a version, a snapshot, keyspaces
# (no system one), the live ScyllaCluster already at the version asked for (git's revert synced), Argo's app Synced, one
# Scylla Manager registration of the cluster, the snapshot and every keyspace in that registration's backups; then the
# data volumes, then the ScyllaCluster, deleted; Argo's rebuild waited for (a new uid, the version, ready), the new
# registration, the schema Job run again; the restore started on the NEW registration from the snapshot found under the
# OLD one's heading (the shared tasks/scylla-restore.yml: --all-clusters only then - deploy:scylla:restore still reads the
# target's own backups alone). A preview deletes nothing. The playbooks on localhost, a kubectl stub playing the cluster,
# Argo and Scylla Manager; then their wiring.
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
# a jsonpath as kubectl must get it: one argument, its braces balanced, no brace beside a space - the command module splits
# an unquoted template with spaces in it ({range .items[*]}, {" "}) into pieces, and kubectl printed the whole object
for x in "$@"; do
  case "$x" in
    jsonpath=*) j=${x#jsonpath=}; o=${j//[^\{]/}; c=${j//[^\}]/}
      if [ "${#o}" != "${#c}" ] || [[ $j == *"{ "* || $j == *" }"* ]]; then echo "broken jsonpath: $x" >&2; exit 9; fi ;;
    '{"'*) printf '%s' "$x" | python3 -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null \
             || { echo "a JSON patch that is no JSON (split by the command module?): $x" >&2; exit 9; } ;;
    *[{}]*) [[ $x == *=* || $x == -* ]] || { echo "a piece of a jsonpath: $x" >&2; exit 9; } ;;
  esac
done
a=" $* "
OLD=11111111-aaaa-4bbb-8ccc-000000000001 NEW=22222222-aaaa-4bbb-8ccc-000000000002
SNAP=sm_20261122180000UTC
gone() { [ -e "$W/deleted" ]; }
listing() {  # listing <cluster id>: one cluster's backups as sctool prints them
  printf 'backup/3dec700b-2bce-44ed-a395-72cba698da55\nSnapshots:\n  - %s (6 MiB, 1 nodes)\nKeyspaces:\n' "${2:-$SNAP}"
  printf '  - system_schema (15 tables)\n  - chat (6 tables)\n'
}
case "$a" in
  *" delete pvc "*) echo pvc >> "$W/deleted" ;;
  *" delete scyllaclusters."*) echo scyllacluster >> "$W/deleted" ;;
  *" get scyllaclusters."*"-o jsonpath={.spec.version}"*)
    printf '%s %s\n' "${LIVE_VERSION:-2026.1.16}" old-uid ;;
  *" get scyllaclusters."*" -o json "*)
    gone && [ -z "${NO_REBUILD:-}" ] || exit 1
    printf '{"metadata": {"uid": "new-uid", "generation": 1}, "spec": {"version": "2026.1.16"}, "status": {"observedGeneration": 1,
      "conditions": [{"type": "Available", "status": "True"}], "racks": {"rack1": {"version": "2026.1.16", "members": 1,
      "readyMembers": 1}}}}\n' ;;
  *" patch applications.argoproj.io "*) [ -z "${NO_SYNC_PATCH_OK:-}" ] || exit 1; touch "$W/synced" ;;
  *" get applications.argoproj.io "*"{.operation.sync}"*) [ -z "${OP_RUNNING:-}" ] || echo '{"revision": "x"}' ;;
  *" get applications.argoproj.io "*) echo "${ARGO:-Synced}" ;;
  *" get pvc,job "*) printf 'PersistentVolumeClaim data-schnappy-production-scylla-datacenter1-rack1-0 old-pvc-uid\n' ;;
  *" get pvc "*) gone && echo new-pvc-uid || echo old-pvc-uid ;;
  *" get job "*"{.status.succeeded}"*) [ -e "$W/synced" ] && echo "new-job-uid 1" || echo "old-job-uid 1" ;;
  *" get job "*) echo old-job-uid ;;
  *" get deployments -o json "*)
    printf '{"items": [%s]}\n' '{"metadata": {"name": "schnappy-production-chat"}, "spec": {"template": {"spec": {"containers": [{"env": [{"name": "SCYLLA_HOST", "value": "schnappy-production-scylla"}]}]}}}},
      {"metadata": {"name": "schnappy-production-admin"}, "spec": {"template": {"spec": {"containers": [{"env": [{"name": "DB", "value": "postgres"}]}]}}}},
      {"metadata": {"name": "schnappy-production-monitor"}, "spec": {"template": {"spec": {"containers": [{"name": "x"}, {"env": [{"name": "SCYLLA_CONTACT_POINTS", "value": "schnappy-production-scylla"}]}]}}}}' ;;
  *" rollout restart "*) echo "${a##* deployment/}" | tr -d ' ' >> "$W/restarted" ;;
  *" rollout status "*) : ;;
  *" sctool cluster list "*)
    echo "| ID | Name | Labels | Port | Credentials |"
    if gone; then [ -n "${NO_REGISTER:-}" ] || echo "| $NEW | schnappy-production/schnappy-production-scylla | x | default | |"
    else echo "| $OLD | schnappy-production/schnappy-production-scylla | x | default | |"; fi
    [ -z "${TWICE:-}" ] || echo "| 33333333-aaaa-4bbb-8ccc-000000000003 | schnappy-production/schnappy-production-scylla | x | default | |"
    echo "| 44444444-aaaa-4bbb-8ccc-000000000004 | schnappy-test/schnappy-test-scylla | x | default | |" ;;
  *" sctool backup list "*"--all-clusters"*)
    # the source's heading holds the snapshot - or, SNAP_UNDER_NEW, only the new cluster's does
    printf 'Cluster: %s\n\n' "$OLD"; listing "$OLD" "$([ -n "${SNAP_UNDER_NEW:-}" ] && echo sm_20261101000000UTC)"
    printf '\nCluster: %s\n\n' "$NEW"; listing "$NEW" ;;
  *" sctool backup list -c $OLD "*) listing "$OLD" "${BACKUP_SNAP:-}" ;;
  *" sctool backup list -c schnappy-production/schnappy-production-scylla "*) listing x ;;
  *" sctool restore "*"--dry-run"*) echo "restore dry run" ;;
  *" sctool restore "*) echo "restore/55555555-aaaa-4bbb-8ccc-000000000005" ;;
  *" sctool progress "*) printf 'Run:\t\tx\nStatus:\t\tDONE\n' ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$W/bin/kubectl"
# the playbooks and their tasks copied, become dropped, retries cut (the stub answers at once)
mkdir -p "$W/playbooks/tasks"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
for src in ("scylla-way-back.yml", "scylla-restore.yml"):
    play = yaml.safe_load(open(f"deploy/ansible/playbooks/{src}"))
    for p in play:
        p.pop("become", None)
    yaml.safe_dump(play, open(os.path.join(W, "playbooks", src), "w"), sort_keys=False)
for src in ("scylla-way-back.yml", "scylla-restore.yml"):
    tasks = yaml.safe_load(open(f"deploy/ansible/playbooks/tasks/{src}"))
    for t in tasks:
        if "retries" in t:
            t["retries"], t["delay"] = 2, 0
    yaml.safe_dump(tasks, open(os.path.join(W, "playbooks", "tasks", src), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
OK=(-e confirm=schnappy-production-scylla -e version=2026.1.16 -e snapshot=sm_20261122180000UTC)
run() {  # run <playbook> <env...> -- <ansible args...>: rc, what was deleted (in order), where a restore was started
  local pb=$1; shift
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  : > "$W/calls"; rm -f "$W/deleted" "$W/synced" "$W/restarted"
  env "${envs[@]}" PATH="$W/bin:$PATH" W="$W" ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/playbooks/$pb" \
    -e kubeconfig=/x "$@" > "$W/out" 2>&1
  local rc=$?
  echo "rc=$rc deleted=$(paste -sd, "$W/deleted" 2>/dev/null) restored=$(grep -v -- '--dry-run' "$W/calls" | grep -o -- 'sctool restore -c [0-9a-z/-]*' | cut -c19-26 | paste -sd,)"
}
check "a way back: every check passed, the volumes then the ScyllaCluster deleted, the rebuild waited for, chat restored on the NEW registration" \
  "$(run scylla-way-back.yml -- "${OK[@]}")" "rc=0 deleted=pvc,scyllacluster restored=22222222"
check "  from the snapshot found under the OLD registration's heading, chat alone, its tables" \
  "$(grep -c -- 'sctool backup list -c 22222222-aaaa-4bbb-8ccc-000000000002 -L s3:scylla-backups --all-clusters' "$W/calls") $(grep -v -- --dry-run "$W/calls" | grep -c -- 'sctool restore -c 22222222-aaaa-4bbb-8ccc-000000000002 -L s3:scylla-backups -T sm_20261122180000UTC -K chat --restore-tables')" "1 1"
check "  said: done, the two registrations named" "$(grep -c 'WAY BACK DONE: schnappy-production-scylla at 2026.1.16, chat restored from sm_20261122180000UTC (restore/55555555-aaaa-4bbb-8ccc-000000000005; Scylla Manager 11111111-aaaa-4bbb-8ccc-000000000001 -> 22222222-aaaa-4bbb-8ccc-000000000002)' "$W/out")" "1"
check "  then the cluster's clients restarted (chat, monitor - not a deployment that names it nowhere), after the restore, each rollout waited for" \
  "$(run scylla-way-back.yml -- "${OK[@]}" >/dev/null; paste -sd, "$W/restarted") $(grep -n -- 'sctool restore -c 2' "$W/calls" | grep -v dry-run | cut -d: -f1) $(grep -n -- 'rollout restart' "$W/calls" | head -1 | cut -d: -f1) $(grep -c -- 'rollout status deployment/schnappy-production-[cm][a-z]* --timeout=600s' "$W/calls")" \
  "schnappy-production-chat,schnappy-production-monitor $(grep -n -- 'sctool restore -c 2' "$W/calls" | grep -v dry-run | cut -d: -f1) $(( $(grep -n -- 'sctool restore -c 2' "$W/calls" | grep -v dry-run | cut -d: -f1) + 3 )) 2"
check "a preview: every check, the restore's dry run against the cluster as it stands - nothing deleted, nothing restored" \
  "$(run scylla-way-back.yml -- "${OK[@]}" --check) $(grep -c 'PREVIEW: every check passed' "$W/out")" "rc=0 deleted= restored= 1"
check "  a preview restarts nothing" "$(run scylla-way-back.yml -- "${OK[@]}" --check >/dev/null; cat "$W/restarted" 2>/dev/null | wc -l)" "0"
check "no confirmation: refused, nothing deleted" "$(run scylla-way-back.yml -- -e version=2026.1.16 -e snapshot=sm_20261122180000UTC)" "rc=2 deleted= restored="
check "the confirmation another cluster's name: refused, nothing deleted" \
  "$(run scylla-way-back.yml -- -e confirm=schnappy-test-scylla -e version=2026.1.16 -e snapshot=sm_20261122180000UTC)" "rc=2 deleted= restored="
check "a system keyspace asked for (one its backup holds): refused, nothing deleted" "$(run scylla-way-back.yml -- "${OK[@]}" -e keyspaces=chat,system_schema)" "rc=2 deleted= restored="
check "the live ScyllaCluster still at the newer version (the revert not synced): refused, nothing deleted" \
  "$(run scylla-way-back.yml LIVE_VERSION=2026.2.3 -- "${OK[@]}") $(grep -q 'revert the release line' "$W/out" && echo said)" "rc=2 deleted= restored= said"
check "Argo's app not Synced: refused, nothing deleted" "$(run scylla-way-back.yml ARGO=OutOfSync -- "${OK[@]}")" "rc=2 deleted= restored="
check "two registrations of the cluster's name: refused, nothing deleted" "$(run scylla-way-back.yml TWICE=1 -- "${OK[@]}")" "rc=2 deleted= restored="
check "the snapshot not among the cluster's backups: refused, nothing deleted" \
  "$(run scylla-way-back.yml BACKUP_SNAP=sm_20261101000000UTC -- "${OK[@]}")" "rc=2 deleted= restored="
check "a keyspace asked for not in its backups: refused, nothing deleted" "$(run scylla-way-back.yml -- "${OK[@]}" -e keyspaces=chat,monitor)" "rc=2 deleted= restored="
check "Argo never rebuilds it: failed, said, nothing restored" \
  "$(run scylla-way-back.yml NO_REBUILD=1 -- "${OK[@]}") $(grep -q 'NOT REBUILT after 15 min' "$W/out" && echo said)" "rc=2 deleted=pvc,scyllacluster restored= said"
check "  the app synced by it (selfHeal runs no hook): the schema Job's sync asked for, prune off" \
  "$(run scylla-way-back.yml -- "${OK[@]}" >/dev/null; grep -c "patch applications.argoproj.io schnappy-production-data --type merge -p .*\"prune\": false" "$W/calls")" "1"
check "an Argo operation still under way on the app: no sync asked over it, nothing restored" \
  "$(run scylla-way-back.yml OP_RUNNING=1 -- "${OK[@]}") $(grep -c 'patch applications' "$W/calls")" "rc=2 deleted=pvc,scyllacluster restored= 0"
check "Scylla Manager never registers the new cluster: failed, nothing restored" \
  "$(run scylla-way-back.yml NO_REGISTER=1 -- "${OK[@]}")" "rc=2 deleted=pvc,scyllacluster restored="
check "the snapshot only under another registration's heading (not the replaced cluster's): refused, nothing restored" \
  "$(run scylla-way-back.yml SNAP_UNDER_NEW=1 -- "${OK[@]}")" "rc=2 deleted=pvc,scyllacluster restored="
check "deploy:scylla:restore unchanged: the target's own backups alone (no --all-clusters), restored into it" \
  "$(run scylla-restore.yml -- -e snapshot=sm_20261122180000UTC -e keyspaces=chat) $(grep -c -- '--all-clusters' "$W/calls")" \
  "rc=0 deleted= restored=schnappy 0"
# the wiring: production's task and the copy's rehearsal
check "deploy:scylla:way-back runs the playbook on production; test:copy:scylla-way-back the rehearsal on the copy, under the copy's lock" "$("$PY" -c '
import yaml
t = yaml.safe_load(open("Taskfile.yml"))["tasks"]
c = lambda n: [str(x.get("cmd", x) if isinstance(x, dict) else x) for x in t[n]["cmds"]]
print(sum("inventory/production.yml playbooks/scylla-way-back.yml" in x for x in c("deploy:scylla:way-back")),
      bool(t["deploy:scylla:way-back"].get("prompt")),
      sum("inventory/vagrant.yml ../../tests/ansible/copy/scylla-way-back-check.yml" in x for x in c("test:copy:scylla-way-back")),
      c("test:copy:scylla-way-back")[0] == "../../scripts/copy-lock.sh")')" "1 True 1 True"
check "the rehearsal runs production's tasks" \
  "$(grep -c 'include_tasks: ../../../deploy/ansible/playbooks/tasks/scylla-way-back.yml' tests/ansible/copy/scylla-way-back-check.yml)" "1"
echo "scylla-way-back: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
