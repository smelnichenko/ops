# VeleroBSLUnavailable

**Severity:** critical · **For:** 10m

## What fired

No successful `velero-schnappy-daily` backup in the last 30h, or the BackupStorageLocation reports phase `Unavailable`.

## Impact

Backups are not landing. If the cluster is destroyed now, we lose data from the last known-good backup. No immediate user-facing impact.

## First steps

```bash
kubectl -n velero get bsl default -o jsonpath='{.status.phase} {.status.message}{"\n"}'
kubectl -n velero get schedules
kubectl -n velero get backups --sort-by=.status.startTimestamp | tail -5
```

## Common causes

| Symptom | Cause | Fix |
|---|---|---|
| `Unavailable: ... 500 internal error` | Pi MinIO broken | Check `systemctl status minio` on Pi1+Pi2 |
| `NoSuchBucket` | bucket got wiped | `mc mb vip/velero` on a Pi |
| No recent Backup objects | Schedule disabled or paused | `kubectl -n velero get schedule velero-schnappy-daily -o yaml` |
| Kopia-maintain jobs all Error | BackupRepository CRs reference missing kopia paths | `kubectl -n velero delete backuprepository --all` (recreated lazily) |

## Fix

After addressing root cause, trigger an ad-hoc backup to verify:

```bash
kubectl -n velero create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: manual-$(date +%Y%m%d-%H%M)
  namespace: velero
spec:
  includedNamespaces: [schnappy-production]
  defaultVolumesToFsBackup: true
  ttl: 72h0m0s
EOF
```

Wait ~5-10min, expect `status.phase: Completed`.

## Verification

- `kubectl -n velero get bsl default -o jsonpath='{.status.phase}'` → `Available`
- Next scheduled (nightly at 02:00) run completes
