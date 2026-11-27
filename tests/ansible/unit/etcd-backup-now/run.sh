#!/bin/bash
# scripts/etcd-backup-now.sh - production's etcd snapshot before a one-way Kubernetes change - with ssh stubbed (the
# Job's states, one per read, from the case's list; its logs; a read that fails): the Job Complete - taken, its upload's
# OK line (the snapshot's name) said; still running (no condition) - read again; a pod failed but the Job retrying (its
# Failed condition not set) - read again, then taken; the Job Failed - failed, its logs said; Complete but no OK line in
# the upload's log - not taken as proof; one read failing - read again; reads failing in a row - given up; never done in
# its time - said; the Job not made - said.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
cat > "$W/bin/ssh" <<'STUB'
#!/bin/bash
echo "$*" >> "$W/calls"
case "$*" in
  *"create job"*) exit "$(cat "$W/create.rc" 2>/dev/null || echo 0)" ;;
  *"get job"*) n=$(cat "$W/n" 2>/dev/null || echo 1); echo $((n + 1)) > "$W/n"
    st=$(sed -n "${n}p" "$W/states"); [ -n "$st" ] || st=$(tail -1 "$W/states")
    [ "$st" != FAIL ] || exit 255
    printf '%s' "$st" ;;
  *"-l job-name=etcd-backup-now-"*"field-selector=status.phase=Succeeded"*) [ -e "$W/nopod" ] || { [ ! -e "$W/twopods" ] || echo "pod/etcd-backup-now-x-early"; echo "pod/etcd-backup-now-x-ok"; } ;;
  *"logs pod/etcd-backup-now-x-early -c upload"*) if [ -e "$W/firstok" ]; then cat "$W/upload.log"; else echo "an upload that said nothing"; fi ;;
  *"logs pod/etcd-backup-now-x-ok -c upload"*) cat "$W/upload.log" ;;
  *"-c upload"*) echo "the failed pod's log: no OK line" ;;
  *"--all-containers"*) echo "pod etcd-backup-now-x: upload: connection refused" ;;
esac
STUB
chmod +x "$W/bin/ssh"
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "    got:  $2"; echo "    want: $3"; fails=$((fails + 1)); fi; }
run() {  # run <states, one a line> [create rc]
  rm -f "$W/calls" "$W/n"; printf '%s\n' "$1" > "$W/states"; echo "${2:-0}" > "$W/create.rc"
  printf 'etcd-backup OK: etcd-20261120-030000.db uploaded; current backups:\n  1 2026-11-20 etcd-20261120-030000.db\n  1 a\n  1 b\n  1 c\n  1 d\n' > "$W/upload.log"
  PATH="$W/bin:$PATH" W="$W" ETCD_BACKUP_POLL=0 ETCD_BACKUP_TRIES=${TRIES:-20} ETCD_BACKUP_READ_FAILS=3 \
    bash scripts/etcd-backup-now.sh > "$W/out" 2>&1
  echo "$? $(grep -c 'get job' "$W/calls")"
}
check "the Job Complete at once: taken (exit 0), one read" "$(run 'True/')" "0 1"
check "  its upload's OK line said - the snapshot's name (a restore takes it), though 5 lines follow it" \
  "$(grep -c '^etcd-backup OK: etcd-20261120-030000.db' "$W/out") $(grep -c 'taken' "$W/out")" "1 1"
check "  the Job made from the CronJob" "$(grep -c 'kubectl -n kube-system create job --from=cronjob/etcd-backup etcd-backup-now-' "$W/calls")" 1
check "running (no condition yet), then Complete: read until it is" "$(run $'/\n/\nTrue/')" "0 3"
check "a pod failed, the Job retrying (Failed not set): read on, then Complete - taken, never FAILED on its first pod" \
  "$(run $'/\n/\n/\nTrue/')" "0 4"
r=$(run $'/\n/True'); check "the Job Failed (its retries spent): FAILED (exit 1), its logs said" \
  "$r $(grep -c 'FAILED' "$W/out") $(grep -c 'connection refused' "$W/out")" "1 2 1 1"
# the Vagrant copy's run (test:copy:check: the rclone in its upload run for real, the wave-patches review 2026-11-23):
# its ssh config handed to every ssh, the host its VM; none given - production's, no -F at all
run 'True/' > /dev/null
check "  production's run: ten, no ssh config" "$(grep -c -- '-F ' "$W/calls") $(grep -c ' ten kubectl' "$W/calls")" "0 4"
rm -f "$W/calls" "$W/n"; printf 'True/\n' > "$W/states"
PATH="$W/bin:$PATH" W="$W" ETCD_BACKUP_POLL=0 ETCD_BACKUP_HOST=kubeadm ETCD_BACKUP_SSH_CONFIG="$W/vagrant-ssh" \
  bash scripts/etcd-backup-now.sh > "$W/out" 2>&1; rc=$?
check "the copy's run: every ssh given its config (-F), the host its kubeadm VM; taken" \
  "$rc $(grep -c -- "^-F $W/vagrant-ssh .* kubeadm kubectl" "$W/calls") $(wc -l < "$W/calls")" "0 4 4"
run 'True/' > /dev/null; : > "$W/upload.log"
PATH="$W/bin:$PATH" W="$W" ETCD_BACKUP_POLL=0 bash scripts/etcd-backup-now.sh > "$W/out" 2>&1; rc=$?
check "Complete but no OK line in the upload's log: not taken as proof (exit 1)" "$rc $(grep -c 'not taken as proof' "$W/out")" "1 1"
check "a read failing once (ten's ssh): read again, then taken" "$(run $'/\nFAIL\nTrue/')" "0 3"
check "  the OK line read from the pod that succeeded (a retried Job's failed pod beside it never read)" \
  "$(grep -c 'logs pod/etcd-backup-now-x-ok -c upload' "$W/calls")" "1"
touch "$W/twopods" "$W/firstok"; r=$(run 'True/'); rm -f "$W/twopods" "$W/firstok"
check "two pods succeeded, the first's upload OK: taken from it, the second never read" \
  "$r $(grep -c 'logs pod/etcd-backup-now-x-ok' "$W/calls")" "0 1 0"
touch "$W/twopods"; r=$(run 'True/'); rm -f "$W/twopods"
check "two pods succeeded, the first's upload saying nothing: the second's OK line read - taken" "$r $(grep -c '^etcd-backup OK: ' "$W/out")" "0 1 1"
touch "$W/nopod"; r=$(run 'True/'); rm -f "$W/nopod"
check "Complete, its succeeded pod not found: not taken as proof (exit 1)" "$r $(grep -c 'succeeded pod not found' "$W/out")" "1 1 1"
check "reads failing 3 times, never twice in a row: read on, then taken (a good read starts the count again)" \
  "$(run $'FAIL\n/\nFAIL\n/\nFAIL\nTrue/')" "0 6"
r=$(run $'/\nFAIL\nFAIL\nFAIL\nTrue/'); check "reads failing 3 times in a row: given up (exit 1), said" \
  "$r $(grep -c 'not read 3 times in a row' "$W/out")" "1 4 1"
r=$(TRIES=5 run '/'); check "never done in its time: said (exit 1)" "$r $(grep -c 'not done in' "$W/out")" "1 5 1"
r=$(run 'True/' 1); check "the Job not made: said (exit 1), nothing read" "$r $(grep -c 'its Job not made' "$W/out")" "1 0 1"
echo "etcd-backup-now: $([ $fails -eq 0 ] && echo ALL-PASS || echo "$fails FAILED")"
[ $fails -eq 0 ]
