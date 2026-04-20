# ClusterSecretStoreNotReady

**Severity:** critical · **For:** 5m

## What fired

ESO's ClusterSecretStore `vault-backend` condition `Ready=true` is false for 5 min.

## Impact

All ExternalSecrets sourced from this store stop syncing. Existing Secrets already in the cluster continue to work (ESO doesn't delete them), but any new values from Vault won't propagate.

## First steps

```bash
kubectl get clustersecretstore vault-backend -o jsonpath='{.status}' | jq
kubectl -n external-secrets logs deploy/external-secrets --tail=50
```

Look for: `unable to create client`, `connection refused`, `401 Unauthorized`, `kubernetes auth`.

## Common causes

| Error message | Likely cause |
|---|---|
| `Vault is sealed` | → [VaultSealed](VaultSealed.md) |
| `401 Unauthorized` | SA token or role mapping broken — check `vault auth list kubernetes/` |
| `connection refused` / timeout | NetworkPolicy or Pi MinIO/Vault down |
| `permission denied` | eso-reader policy missing `secret/data/*` read |

## Fix

- If Vault was sealed: unseal first (see VaultSealed runbook), then `kubectl -n external-secrets rollout restart deploy external-secrets`.
- If 401: re-run `task deploy:vault` to re-apply auth config.

## Verification

- `kubectl get clustersecretstore vault-backend -o jsonpath='{.status.conditions[*].status}'` → `True`
- `kubectl get externalsecrets -A --no-headers | awk '{print $6}' | sort -u` → only `SecretSynced`
