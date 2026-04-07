# Plan 053: CloudNativePG PostgreSQL Migration + Stress Test

**Status: COMPLETED (2026-04-07)**

## Context

PostgreSQL was a hand-rolled Deployment in the `schnappy-data` Helm chart (PG 17-alpine, single replica, Recreate strategy). Four app databases (monitor, monitor_admin, monitor_chat, monitor_chess), pg_dump backup CronJob, Liquibase schema management. Keycloak uses an external database on the Pi, not the in-cluster postgres.

Migrated to CloudNativePG (CNPG) 0.28.0 — operator-managed `Cluster` CRD with declarative PostgreSQL configuration, native backup support, and automated lifecycle management.

---

## What Was Done

### Phase 1: CNPG Operator
- ArgoCD app `cnpg` (chart 0.28.0, namespace `cnpg-system`, sync-wave `-1`, `ServerSideApply=true`)
- Operator resources: 100m/500m CPU, 256Mi/512Mi memory

### Phase 2: CNPG Cluster Templates
- `cnpg-cluster.yaml` — Cluster CRD (`schnappy-postgres`, PG 17, 1 instance)
- `cnpg-secret.yaml` — Two ExternalSecrets:
  - `schnappy-postgres-superuser`: hardcoded `username: postgres`, password from Vault
  - `schnappy-postgres-app`: `username`/`password` from Vault (creates `monitor` app user)
- `cnpg-service-compat.yaml` — ExternalName `schnappy-postgres` → `schnappy-postgres-rw`
- `cnpg-backup.yaml` — ScheduledBackup CRD (daily 01:30 UTC to MinIO)
- Bootstrap: `initdb` with `owner: monitor`, `secret: schnappy-postgres-app`, `postInitSQL` creates extra databases + grants

### Phase 3: Network Policies
- Conditional `schnappy.postgres.selectorLabels` in both charts' `_helpers.tpl` (switches to `cnpg.io/cluster` labels)
- Hardcoded old postgres Deployment/Service selectors to avoid immutable selector conflict
- CNPG NP: ingress from app/admin/chat/chess + CNPG operator (ports 5432, 8000), egress DNS + K8s API + MinIO
- Old postgres NP: added CNPG import ingress rule (for migration phase)

### Phase 4: Data Migration (manual pg_dump/pg_restore)

CNPG monolith import failed due to Istio mTLS intercepting the import pod's connection to old postgres. Used manual approach:

1. Enabled CNPG with empty `initdb` bootstrap (creates databases via `postInitSQL`)
2. Manually applied CNPG NP (ArgoCD sync was stuck waiting for Cluster health)
3. Created `monitor` role, set password from Vault secret, granted privileges on all databases
4. `pg_dump -Fc` from old postgres for each database (monitor, monitor_admin, monitor_chat, monitor_chess)
5. `kubectl cp` dumps to CNPG pod's pgdata volume, `pg_restore --clean --if-exists --no-owner --no-acl`
6. Disabled old postgres (`postgres.enabled: false`), ExternalName compat service took over
7. Restarted all app deployments to reconnect

### Phase 5: Stress Test
- Hyperfoil stress test passed: ~100 req/s at 1.33ms mean latency (rate100 phase), CPUs at 80-94%
- Matches baseline — no regression from CNPG migration

---

## Issues Encountered

1. **CNPG monolith import + Istio**: Import pod's sidecar intercepted outbound connection to old postgres, causing TLS/EOF errors even with `sslmode=disable`. Switched to manual pg_dump/pg_restore.

2. **Immutable selector conflict**: `schnappy.postgres.selectorLabels` helper returned CNPG labels when `cnpg.enabled=true`, breaking the old Deployment's immutable `.spec.selector`. Fixed by hardcoding old labels in `postgres-deployment.yaml` and `postgres-service.yaml`.

3. **CNPG operator HTTP timeout**: Operator in `cnpg-system` couldn't reach CNPG pod port 8000 — NP hadn't been synced (ArgoCD stuck). Manually applied NP to unblock.

4. **App user password missing**: Created `monitor` role via `CREATE ROLE` but forgot to set password. Apps got `password authentication failed`. Fixed by `ALTER ROLE monitor WITH PASSWORD '...'`.

5. **Superuser secret had wrong username**: Vault stores `username: monitor`, but CNPG superuser secret needs `username: postgres`. Fixed with ExternalSecret template that hardcodes `username: postgres`.

6. **Root app managedFields conflict**: New cnpg/strimzi Application resources had `managedFields` that client-side apply rejected. Fixed by stripping `managedFields` from live resources (NOT by enabling SSA on root app).

7. **Keycloak not in-cluster**: Keycloak uses external DB on Pi, removed from `extraDatabases` and NP ingress rules.

---

## Automation (fresh deploy)

On a clean CNPG bootstrap, everything is automated:
- **Superuser** (`postgres`): password from Vault, hardcoded username via ExternalSecret template
- **App user** (`monitor`): created by CNPG `initdb.owner` + `initdb.secret` from `schnappy-postgres-app` ExternalSecret
- **Extra databases**: created via `postInitSQL` with grants to `monitor`
- **NPs**: conditional selectors auto-switch between old/CNPG labels

---

## Files Changed

### Created (infra)
| File | Purpose |
|------|---------|
| `clusters/production/argocd/apps/cnpg.yaml` | ArgoCD app |
| `clusters/production/cnpg/values.yaml` | Operator values |

### Created (platform)
| File | Purpose |
|------|---------|
| `helm/schnappy-data/templates/cnpg-cluster.yaml` | Cluster CRD |
| `helm/schnappy-data/templates/cnpg-secret.yaml` | Superuser + app user ExternalSecrets |
| `helm/schnappy-data/templates/cnpg-service-compat.yaml` | ExternalName compat |
| `helm/schnappy-data/templates/cnpg-backup.yaml` | ScheduledBackup CRD |

### Modified (platform)
| File | Change |
|------|--------|
| `helm/schnappy-data/values.yaml` | Add `cnpg` section, fix username default, remove keycloak from extraDatabases |
| `helm/schnappy-data/templates/_helpers.tpl` | Conditional postgres selector labels |
| `helm/schnappy-data/templates/network-policies.yaml` | CNPG NPs, hardcoded old postgres NP selectors, removed keycloak |
| `helm/schnappy-data/templates/postgres-deployment.yaml` | Hardcoded selectors (avoid immutable conflict) |
| `helm/schnappy-data/templates/postgres-service.yaml` | Hardcoded selectors |
| `helm/schnappy/values.yaml` | Add `cnpg.enabled` |
| `helm/schnappy/templates/_helpers.tpl` | Conditional postgres selector labels |

### Modified (infra)
| File | Change |
|------|--------|
| `clusters/production/schnappy-data/values.yaml` | `postgres.enabled: false`, `cnpg.enabled: true`, removed keycloak |
| `clusters/production/schnappy/values.yaml` | `cnpg.enabled: true` |

## Cleanup (Phase 7, after 1 week stable)

Delete from `helm/schnappy-data/templates/`:
- `postgres-deployment.yaml`, `postgres-pvc.yaml`, `postgres-service.yaml`, `postgres-secret.yaml`, `postgres-backup-cronjob.yaml`

Delete old PVC: `kubectl delete pvc schnappy-postgres -n schnappy`

## Rollback

Revert infra values: `postgres.enabled: true`, `cnpg.enabled: false`. Old PVC with data remains (`helm.sh/resource-policy: keep`).
