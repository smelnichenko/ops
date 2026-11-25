#!/usr/bin/env bash
# An etcd snapshot of production now - a Job made from the etcd-backup CronJob (kube-system: the snapshot, then its
# upload to the Pi backup store), through ten - read until the Job itself is Complete or Failed (its conditions: it
# retries a failed pod - backoffLimit 2 - so a pod failing is not the Job failing), its upload's "etcd-backup OK" line
# said (the snapshot's name: what a restore takes). The backup before a one-way Kubernetes change: the upgrade cycle runs
# it before the merge, so a failure leaves production untouched.
#
# Usage: scripts/etcd-backup-now.sh        exit 0 taken (its name said), 1 not (why said)
# Env:   ETCD_BACKUP_HOST (ten), ETCD_BACKUP_POLL (10 s), ETCD_BACKUP_TRIES (90 - 15 min at 10 s),
#        ETCD_BACKUP_READ_FAILS (6 - reads of the Job failing in a row before it is given up: ten's ssh may drop once),
#        ETCD_BACKUP_SSH_CONFIG (an ssh config file - the Vagrant copy's: test:copy:check runs the Job on its kubeadm VM)
set -uo pipefail
host=${ETCD_BACKUP_HOST:-ten}
poll=${ETCD_BACKUP_POLL:-10}; tries=${ETCD_BACKUP_TRIES:-90}; read_fails=${ETCD_BACKUP_READ_FAILS:-6}
on() { ssh ${ETCD_BACKUP_SSH_CONFIG:+-F "$ETCD_BACKUP_SSH_CONFIG"} -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=10 \
  -o ServerAliveCountMax=3 "$host" "$@" < /dev/null; }
job=etcd-backup-now-$(date -u +%Y%m%d%H%M%S)
on "kubectl -n kube-system create job --from=cronjob/etcd-backup $job" || { echo "ETCD SNAPSHOT: its Job not made"; exit 1; }
failed_reads=0
for _ in $(seq "$tries"); do
  # "<Complete>/<Failed>": each condition's status, empty while the Job runs
  if st=$(on "kubectl -n kube-system get job $job -o jsonpath='{.status.conditions[?(@.type==\"Complete\")].status}/{.status.conditions[?(@.type==\"Failed\")].status}'"); then
    failed_reads=0
    case "$st" in
      True/*)
        # the pods that succeeded (a retried Job has a failed one beside it: logs job/<it> may read that one) - the first
        # whose upload says OK
        pods=$(on "kubectl -n kube-system get pods -l job-name=$job --field-selector=status.phase=Succeeded -o name")
        [ -n "$pods" ] || { echo "ETCD SNAPSHOT $job: the Job Complete, its succeeded pod not found - not taken as proof"; exit 1; }
        ok=""
        for pod in $pods; do
          ok=$(on "kubectl -n kube-system logs $pod -c upload" | grep -m1 '^etcd-backup OK: ') && break
        done
        [ -n "$ok" ] || { echo "ETCD SNAPSHOT $job: the Job Complete, its upload's OK line not read - not taken as proof"; exit 1; }
        echo "$ok"; echo "ETCD SNAPSHOT $job: taken"; exit 0 ;;
      */True)
        on "kubectl -n kube-system logs job/$job --all-containers --tail=20" || echo "(its logs not read)"
        echo "ETCD SNAPSHOT $job: FAILED (the Job failed, its retries spent)"; exit 1 ;;
    esac
  else
    failed_reads=$((failed_reads + 1))
    [ "$failed_reads" -lt "$read_fails" ] || { echo "ETCD SNAPSHOT $job: the Job not read $read_fails times in a row"; exit 1; }
  fi
  sleep "$poll"
done
echo "ETCD SNAPSHOT $job: not done in $((tries * poll / 60)) min"
exit 1
