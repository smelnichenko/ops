#!/bin/bash
# postgres-base-backup.yml's gate before the backup, as the playbook holds it - run by ansible-playbook on localhost
# (become dropped, retries cut to 2 with no delay, the backup itself a no-op), kubectl a stub: CNPG's ContinuousArchiving
# condition alone was the gate, and right after a major upgrade it can still be the old major's True. Now a WAL file is
# switched on the primary and must reach the store (pg_stat_archiver): archived passes; the archiver behind - the
# condition True all the while - fails.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
AP=$(command -v ansible-playbook || echo deploy/ansible/venv/bin/ansible-playbook)
PY=$(dirname "$(readlink -f "$AP")")/python3
[ -x "$PY" ] || PY=python3
unset ANSIBLE_CONFIG
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/kubectl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
case "$*" in
  *ContinuousArchiving*) echo -n True ;;
  *currentPrimary*) echo -n pg-1 ;;
  *pg_switch_wal*) echo 000000010000000000000005 ;;
  *pg_stat_archiver*) echo "$ARCHIVED" ;;
esac
STUB
chmod +x "$W/bin/kubectl"
W=$W "$PY" - <<'PY'
import os, yaml
W = os.environ["W"]
play = yaml.safe_load(open("deploy/ansible/playbooks/postgres-base-backup.yml"))
for p in play:
    p.pop("become", None)
    p["vars"]["kubectl"] = "kubectl"
    for t in p["tasks"]:
        if "retries" in t:
            t["retries"], t["delay"] = 2, 0
        if t.get("ansible.builtin.include_tasks") == "tasks/cnpg-backup.yml":
            t.pop("ansible.builtin.include_tasks")
            t["ansible.builtin.debug"] = {"msg": "BACKUP TAKEN"}
yaml.safe_dump(play, open(os.path.join(W, "play.yml"), "w"), sort_keys=False)
open(os.path.join(W, "hosts.yml"), "w").write(
    "all:\n  hosts:\n    target: {ansible_connection: local, ansible_python_interpreter: '{{ ansible_playbook_python }}'}\n")
PY
fails=0
case_() {  # case_ <name> <archived WAL> <want rc 0|1> <backup taken: 1|0>
  : > "$W/calls"
  out=$(PATH="$W/bin:$PATH" CALLS="$W/calls" ARCHIVED=$2 ANSIBLE_NOCOLOR=1 "$AP" -i "$W/hosts.yml" "$W/play.yml" 2>&1)
  rc=$?; [ $rc = 0 ] || rc=1
  got="$rc $(grep -c 'BACKUP TAKEN' <<< "$out") $(grep -c pg_switch_wal "$W/calls")"
  if [ "$got" = "$3 $4 1" ]; then echo "PASS $1"; return; fi
  echo "FAIL $1: got '$got' (rc, backup, WAL switched), want '$3 $4 1'"; grep -E "fatal|FAILED" <<< "$out" | head -2
  fails=$((fails + 1))
}
case_ "the switched WAL archived: the backup taken" 000000010000000000000005 0 1
case_ "archived past it: the backup taken" 000000010000000000000007 0 1
case_ "the archiver behind it, the condition True: refused, no backup" 000000010000000000000003 1 0
case_ "nothing archived yet: refused" "" 1 0
echo "base-backup-archiving: $([ $fails = 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails = 0 ]
