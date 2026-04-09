# Plan 056: Separate Database Names and Users Per Service

## Context

Currently all 4 services (monitor, admin, chat, chess) share a single PostgreSQL user `monitor` and use databases named `monitor`, `monitor_admin`, `monitor_chat`, `monitor_chess`. Goal:
- Database names: `monitor`, `admin`, `chat`, `chess` (drop the `monitor_` prefix)
- Each service gets its own DB user: `monitor`, `admin`, `chat`, `chess`
- Each user only has access to its own database
- Separate credentials in Vault for prod and test environments
- No default fallbacks — missing config should fail explicitly

## Current State

- Single Vault secret `secret/schnappy/postgres` with `username=monitor`, `password=<shared>`
- Single CNPG `app` secret with shared credentials
- All 4 deployments read from the same K8s secret (`schnappy-postgres`)
- CNPG `postInitSQL` creates extra databases and grants all to the shared user
- Admin/chat/chess use `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` env vars
- Monitor uses `POSTGRES_HOST`, `POSTGRES_USERNAME`, `POSTGRES_PASSWORD` (hardcoded DB name `monitor` in application.yml)

## Changes

### 1. Vault secrets — `ops/deploy/ansible/playbooks/seed-vault-secrets.yml`

Add per-service postgres secrets (keep original for CNPG app user):

```yaml
vault kv put secret/{{ vault_prefix }}/postgres-monitor database=monitor username=monitor password="{{ MONITOR_DB_PASSWORD }}"
vault kv put secret/{{ vault_prefix }}/postgres-admin database=admin username=admin password="{{ ADMIN_DB_PASSWORD }}"
vault kv put secret/{{ vault_prefix }}/postgres-chat database=chat username=chat password="{{ CHAT_DB_PASSWORD }}"
vault kv put secret/{{ vault_prefix }}/postgres-chess database=chess username=chess password="{{ CHESS_DB_PASSWORD }}"
```

### 2. Environment variables — `ops/.env` and `ops/.env.test`

Add new password variables (generate unique passwords):

```
ADMIN_DB_PASSWORD=<generated>
CHAT_DB_PASSWORD=<generated>
CHESS_DB_PASSWORD=<generated>
```

### 3. Per-service ExternalSecrets — `platform/helm/schnappy-data/templates/external-secrets.yaml`

Add ExternalSecrets for each service pulling from `postgres-{service}` Vault path.

### 4. DB init Job — `platform/helm/schnappy-data/templates/cnpg-init-users.yaml` (NEW)

Kubernetes Job that runs as ArgoCD Sync hook (wave 5, after CNPG cluster):
1. Connects as superuser
2. Creates each user with password from its K8s secret
3. Creates each database owned by its user (or renames from old name)
4. Grants schema permissions

### 5. App deployment templates — `platform/helm/schnappy/templates/`

Update each service deployment to use its own postgres secret:
- admin → `schnappy-postgres-admin`
- chat → `schnappy-postgres-chat`
- chess → `schnappy-postgres-chess`
- monitor → `schnappy-postgres-monitor`

### 6. CNPG cluster — `platform/helm/schnappy-data/templates/cnpg-cluster.yaml`

Update `extraDatabases` from string list to object list. Remove default fallbacks.

### 7. Production migration

Rename databases: `ALTER DATABASE monitor_admin RENAME TO admin;` etc.
Transfer ownership and grant schema permissions.

## Files to modify

| File | Change |
|------|--------|
| `ops/deploy/ansible/playbooks/seed-vault-secrets.yml` | Add per-service postgres secrets |
| `ops/.env` | Add ADMIN_DB_PASSWORD, CHAT_DB_PASSWORD, CHESS_DB_PASSWORD |
| `ops/.env.test` | Same |
| `platform/helm/schnappy-data/values.yaml` | Change extraDatabases to objects |
| `platform/helm/schnappy-data/templates/cnpg-cluster.yaml` | Update postInitSQL for new format |
| `platform/helm/schnappy-data/templates/external-secrets.yaml` | Add per-service ExternalSecrets |
| `platform/helm/schnappy-data/templates/cnpg-init-users.yaml` | NEW: init Job for users/DBs |
| `platform/helm/schnappy/templates/_helpers.tpl` | Add per-service secret name helpers |
| `platform/helm/schnappy/templates/admin-deployment.yaml` | Use admin-specific postgres secret |
| `platform/helm/schnappy/templates/chat-deployment.yaml` | Use chat-specific postgres secret |
| `platform/helm/schnappy/templates/chess-deployment.yaml` | Use chess-specific postgres secret |
| `platform/helm/schnappy/templates/app-deployment.yaml` | Use monitor-specific postgres secret |
| `infra/clusters/production/schnappy-data/values.yaml` | Update extraDatabases |
| `infra/clusters/production/schnappy-test-data/values.yaml` | Update extraDatabases |

## Migration order

1. Seed new Vault secrets (per-service passwords)
2. Push platform changes (ExternalSecrets, init Job, deployment updates)
3. ArgoCD syncs → ExternalSecrets create per-service K8s secrets
4. Init Job runs → creates users, renames databases, grants permissions
5. App deployments restart with new secrets → each connects to its own DB as its own user
6. Verify all services start and Liquibase migrations succeed

## Verification

1. `helm template` renders all ExternalSecrets and init Job correctly
2. Each service connects to its renamed database as its own user
3. Liquibase migrations succeed (schema ownership is correct)
4. Services cannot access each other's databases (cross-user isolation)
5. Test environment works identically (different Vault path, same structure)
