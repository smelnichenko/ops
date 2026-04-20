# VaultSealed

**Severity:** critical · **For:** 2m

## What fired

Blackbox probe to `https://192.168.11.{4,5,6}:8200/v1/sys/health` returned `503` (sealed) or failed to connect for 2+ min. `$labels.instance` tells you which Pi.

## Impact

- ESO cannot refresh any ExternalSecret → all secrets go stale at TTL
- Keycloak JWKS signing keys may rotate and clients lose auth
- 8 downstream ArgoCD apps eventually Degrade (appTree health)

## First steps

```bash
ssh pi1 sudo systemctl status vault vault-unseal
curl -sk https://192.168.11.5:8200/v1/sys/seal-status
```

If `"sealed": true`, the auto-unseal service failed to run. Manually unseal:

```bash
ssh pi1 'sudo bash -c "export VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=1; \
  for k in \$(sudo head -2 /etc/vault-unseal/unseal-keys); do vault operator unseal \$k; done"'
# repeat on pi2
```

## Root-cause investigation

- `journalctl -u vault-unseal` — script errors?
- `journalctl -u vault` — consul backend healthy?
- Recent Pi reboot? unseal-script bug was fixed in commit `a78974a` (the `until vault status; do sleep 1; done` spun forever on rc=2).

## Fix

Once unsealed, restart ESO to re-establish store connection:

```bash
kubectl -n external-secrets rollout restart deploy external-secrets
```

ClusterSecretStore should move back to Ready within a minute. ArgoCD apps recover on their next refresh cycle.

## Verification

- `kubectl get clustersecretstore vault-backend -o jsonpath='{.status.conditions[*].status}'` → `True`
- `kubectl get externalsecrets -A | grep -v SecretSynced | head` → empty
- Watchdog alert still firing (pipeline intact)
