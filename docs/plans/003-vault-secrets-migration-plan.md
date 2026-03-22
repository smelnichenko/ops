# Migrate Monitor Secrets from .env to Vault

## Context

Secrets were in a `.env` file on `ten`, read by Ansible via `lookup('env', ...)`, passed through Helm values, and rendered into k8s Secrets. Vault HA + ESO were already deployed but unused for the monitor app. This migration makes Vault the single source of truth for runtime secrets, eliminating the `.env` dependency for app deploys.

## Secrets

| Vault Path | Keys | k8s Secret Name | k8s Secret Keys |
|---|---|---|---|
| `secret/monitor/auth` | `jwt_secret` | `monitor-auth` | `JWT_SECRET` |
| `secret/monitor/postgres` | `database`, `username`, `password` | `monitor-postgres` | `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` |
| `secret/monitor/redis` | `password` | `monitor-redis` | `REDIS_PASSWORD` |
| `secret/monitor/mail` | `password` | `monitor-mail` | `MAIL_PASSWORD` |
| `secret/monitor/ai` | `api_key` | `monitor-ai` | `ANTHROPIC_API_KEY` |
| `secret/monitor/webhook` | `signing_secret`, `api_key` | `monitor-webhook` | `RESEND_WEBHOOK_SECRET`, `RESEND_API_KEY` |
| `secret/monitor/minio` | `access_key`, `secret_key` | `monitor-minio` | `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` |
| `secret/monitor/grafana` | `admin_user`, `admin_password` | `monitor-grafana` | `admin-user`, `admin-password` |

## Implementation Steps

### Step 1: Add `existingSecret` support to all Helm secret types [DONE]

Extended the existing postgres/grafana `existingSecret` pattern to auth, mail, ai, webhook, redis, minio:

- `values.yaml`: Added `existingSecret: ""` to auth, mail, ai, webhook, redis, minio sections; added `vault.secretsEnabled: false` toggle
- `_helpers.tpl`: Added `monitor.X.secretName` helper for each type (returns `existingSecret` name or generates default)
- Each `*-secret.yaml`: Skip Secret creation when `existingSecret` is set
- `app-deployment.yaml`: All `secretKeyRef` names use `{{ include "monitor.X.secretName" . }}` helpers
- `redis-deployment.yaml`: Password conditions check `or .Values.redis.password .Values.redis.existingSecret`
- `minio-deployment.yaml`: Secret refs use `{{ include "monitor.minio.secretName" . }}`

### Step 2: Add ExternalSecret template to Helm chart [DONE]

New file `templates/external-secrets.yaml` -- creates ExternalSecret CRDs when `vault.secretsEnabled: true`.

Each ExternalSecret:
- `secretStoreRef` -> ClusterSecretStore `vault-backend`
- `refreshInterval: 1h`
- `target.name` matches existing k8s secret names (e.g., `monitor-auth`)
- `remoteRef.key` -> `secret/data/monitor/<name>` (KV v2 data prefix)

Conditional creation by feature flag:
- Auth + Postgres: always (when vault.secretsEnabled)
- Redis: when `redis.password` or `redis.existingSecret` set
- Mail: when `mail.enabled`
- AI: when `ai.apiKey` or `ai.existingSecret` set
- Webhook: when `webhook.enabled`
- MinIO: when `minio.enabled`
- Grafana: when `grafana.enabled` and `grafana.existingSecret` set

### Step 3: Seed secrets into Vault KV [DONE]

Added Phase 12 to `setup-vault.yml` -- writes app secrets from `.env` into Vault KV v2 via `kubectl exec vault-0 -- vault kv put`.

- Guarded by `vault_seed_secrets: true` flag (default false)
- Uses `vault_seed_token` for authentication
- Each secret group is a separate task, skipped if env vars are empty
- Idempotent: `vault kv put` overwrites safely

### Step 4: Update production.yml [DONE]

Switched from `lookup('env')` to `existingSecret` references:

- Added `vault.secretsEnabled: true`
- All secret types use `existingSecret: "monitor-<name>"` instead of inline values
- Removed all `lookup('env', 'SECRET_*')` for runtime secrets
- Kept non-secret config: `mail.host`, `mail.port`, `ai.model`, feature flags, resource limits
- Kept Forgejo/Velero deploy-time secrets as `lookup('env')` (not runtime k8s secrets)

### Step 5: Update CD pipeline [DONE]

Removed `.env` sourcing from the deploy step. The CD pipeline only needs `production.yml` (which references `existingSecret` names, not actual values).

### Step 6: Update docs [DONE]

Updated `CLAUDE.md` to document the new secrets flow.

### Step 7: Add Redis password support [DONE]

Added `spring.data.redis.password` to `application.yml` (reads from `REDIS_PASSWORD` env var, defaults to empty). Production Redis now uses a password from Vault via ESO.

## Deployment Procedure

### One-time: Seed secrets into Vault

```bash
# On ten (where .env lives)
set -a && source /home/sm/src/.env && set +a

cd /home/sm/src/monitor/deploy/ansible
ansible-playbook -i inventory/production.yml playbooks/setup-vault.yml \
  -e @vars/vault.yml -e @vars/vault-pi-runtime.yml \
  -e "vault_seed_secrets=true" \
  -e "vault_seed_token=$VAULT_ROOT_TOKEN"
```

### Adding new secrets to Vault

```bash
# From ten, exec into the vault pod
ssh ten 'sudo k3s kubectl exec -it -n vault vault-0 -- /bin/sh'

# Inside the vault pod
export VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt
export VAULT_TOKEN="<root-token>"

# Write a new secret path
vault kv put secret/monitor/<name> key1=value1 key2=value2

# Then add a matching ExternalSecret in external-secrets.yaml
# and update the Helm chart to reference it
```

### Deploy with Vault secrets

```bash
# No .env needed for app secrets anymore
task deploy:prod
```

### Verify

```bash
# Check ExternalSecrets are synced
ssh ten 'sudo k3s kubectl get externalsecrets -n monitor'

# All should show status: SecretSynced
ssh ten 'sudo k3s kubectl get externalsecrets -n monitor -o jsonpath="{range .items[*]}{.metadata.name}: {.status.conditions[0].reason}{\"\\n\"}{end}"'

# App health
curl https://pmon.dev/api/health
```

## Vagrant Testing

ESO integration tested with `task test:eso`:
1. Sets up vault-pi and k3s Vault from scratch
2. Seeds test secrets into Vault KV
3. Deploys chart with `vault.secretsEnabled: true` and `existingSecret` values
4. Verifies 3/3 ExternalSecrets sync (auth, postgres, redis)
5. Verifies k8s Secret content matches Vault values (JWT_SECRET)

App CrashLoopBackOff is expected in Vagrant (no Docker image), but Redis password auth errors confirm the password flow works correctly.

## Backward Compatibility

The chart is fully backward-compatible:

- **Without `existingSecret`**: Helm creates Secrets from inline values (same as before)
- **With `existingSecret`**: Helm skips Secret creation, uses the named Secret (created by ESO or manually)
- **With `vault.secretsEnabled`**: ExternalSecret CRDs created, ESO syncs from Vault into k8s Secrets

## Rollback

Revert `production.yml` to pass secrets directly via `lookup('env')`. Helm recreates k8s Secrets from values, overriding ESO-managed ones. `.env` stays on ten unchanged throughout.

To fully revert:
1. `git revert` the commit with these changes
2. Re-source `.env` and redeploy: `set -a && source .env && set +a && task deploy:prod`
3. ExternalSecrets become orphaned (harmless) -- clean up with `kubectl delete externalsecrets -n monitor --all`
