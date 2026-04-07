# Plan 053: CloudNativePG PostgreSQL Migration + Stress Test

**Status: TODO**

## Context

PostgreSQL is currently a hand-rolled Deployment in the `schnappy-data` Helm chart (PG 17-alpine, single replica, Recreate strategy). Five databases (monitor, monitor_admin, monitor_chat, monitor_chess, keycloak), pg_dump backup CronJob, Liquibase schema management.

Migrating to CloudNativePG (CNPG) 0.28.0 / operator 1.28+ replaces the manual Deployment with an operator-managed `Cluster` CRD — declarative PostgreSQL configuration, automated failover, native backup to MinIO via Barman, and rolling updates.

Follows the same pattern as Plan 052 (Strimzi). After migration, run Hyperfoil stress test.

---

## Phase 1: Install CNPG Operator

### 1.1 ArgoCD app

Create `/home/sm/src/infra/clusters/production/argocd/apps/cnpg.yaml`:
- Chart: `cloudnative-pg` from `https://cloudnative-pg.github.io/charts`, version `0.28.0`
- Namespace: `cnpg-system`, sync-wave `-1`
- `ServerSideApply=true`

### 1.2 Operator values

Create `/home/sm/src/infra/clusters/production/cnpg/values.yaml`:
- Resources: 100m/500m CPU, 256Mi/512Mi memory

### 1.3 Verify

```bash
kubectl get pods -n cnpg-system
kubectl get crd | grep cnpg
```

---

## Phase 2: Add CNPG Cluster Template

New templates in `schnappy-data`, guarded by `cnpg.enabled`.

### 2.1 `cnpg-cluster.yaml` — Cluster CRD

- Name: `schnappy-postgres`
- Single instance (`instances: 1` — single node cluster)
- Image: `ghcr.io/cloudnative-pg/postgresql:17`
- `enableSuperuserAccess: true` with `superuserSecret` pointing to a CNPG-formatted ExternalSecret
- Bootstrap via `initdb` with `import` type `monolith` from old instance:
  - `externalClusters` pointing to `schnappy-postgres-old` (the existing Deployment service, temporarily renamed)
  - Databases: monitor, monitor_admin, monitor_chat, monitor_chess, keycloak
- After migration succeeds, switch to plain `initdb` bootstrap for fresh deploys
- PostgreSQL parameters matching current tuning: shared_buffers=512MB, effective_cache_size=2GB, etc.
- Storage: 20Gi, `local-path`
- Resources: 250m/4000m CPU, 1Gi/2Gi memory
- Istio annotation: `proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'`
- Exclude CNPG operator ports from Istio: `traffic.sidecar.istio.io/excludeInboundPorts: "8000"` (CNPG health/status port)

### 2.2 `cnpg-secret.yaml` — ExternalSecret for CNPG superuser

CNPG expects keys `username` and `password` (not `POSTGRES_USER` / `POSTGRES_PASSWORD`). New ExternalSecret `schnappy-postgres-superuser` mapping from same Vault path `secret/data/schnappy/postgres`.

Keep existing `schnappy-postgres` ExternalSecret for app Deployments that read `POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB`.

### 2.3 `cnpg-service-compat.yaml` — ExternalName service

`schnappy-postgres` → `schnappy-postgres-rw.schnappy.svc.cluster.local`

Only created when `cnpg.enabled && !postgres.enabled`.

### 2.4 `cnpg-backup.yaml` — ScheduledBackup CRD

Replace the kubectl-exec pg_dump CronJob with CNPG native backup:
- Schedule: `30 1 * * *` (same as current)
- Backup to MinIO: `s3://postgres-backups/` (new bucket)
- Retention: 7 days
- Uses existing MinIO credentials from `schnappy-minio` secret

### 2.5 Values

Base `schnappy-data/values.yaml`:
```yaml
cnpg:
  enabled: false
```

---

## Phase 3: Network Policy Updates

Same pattern as Strimzi migration.

### CNPG pod labels

```
cnpg.io/cluster: schnappy-postgres
cnpg.io/instanceRole: primary
```

### Changes

Make `schnappy.postgres.selectorLabels` conditional in both charts' `_helpers.tpl`:
```
{{- define "schnappy.postgres.selectorLabels" -}}
{{- if eq (.Values.cnpg.enabled | toString) "true" }}
cnpg.io/cluster: schnappy-postgres
{{- else }}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: postgres
{{- end }}
{{- end }}
```

**Additional NPs in schnappy-data**:
- CNPG operator (cross-namespace from `cnpg-system`): ingress to port 5432 + 8000
- CNPG pod egress: DNS + K8s API (for leader election)
- Guard old postgres NP block with `postgres.enabled`

**schnappy chart**: Add `cnpg.enabled: false` to base values, `true` to production.

---

## Phase 4: Data Migration & Cutover

### 4a. CNPG monolith import (recommended)

CNPG supports importing multiple databases from an existing PostgreSQL via `bootstrap.initdb.import`:

```yaml
bootstrap:
  initdb:
    import:
      type: monolith
      databases:
        - monitor
        - monitor_admin
        - monitor_chat
        - monitor_chess
        - keycloak
      roles:
        - postgres
    database: monitor
    owner: postgres
    secret:
      name: schnappy-postgres-superuser
externalClusters:
  - name: old-postgres
    connectionParameters:
      host: schnappy-postgres-old
      user: postgres
      dbname: postgres
      port: "5432"
    password:
      name: schnappy-postgres
      key: POSTGRES_PASSWORD
```

### 4b. Migration steps

1. Rename old postgres Service from `schnappy-postgres` to `schnappy-postgres-old` (add new value for old service name)
2. Enable `cnpg.enabled: true` with the import bootstrap pointing to `schnappy-postgres-old`
3. ArgoCD syncs: CNPG creates cluster, runs pg_dump/pg_restore from old instance
4. Once CNPG cluster is Ready, create the ExternalName compat service `schnappy-postgres` → `schnappy-postgres-rw`
5. Disable `postgres.enabled: false` to remove old Deployment + old service
6. Apps reconnect via same `schnappy-postgres:5432` DNS

**Alternative (simpler, brief downtime):**
1. Scale down apps to zero
2. Disable old postgres, enable CNPG with plain `initdb` bootstrap (creates empty DBs)
3. Manually pg_dump from old PVC, pg_restore into CNPG
4. Create compat service, scale apps back up

### 4c. Infra values at cutover

```yaml
postgres:
  enabled: false
cnpg:
  enabled: true
```

---

## Phase 5: Backup Update

- Remove old `postgres-backup-cronjob.yaml` (kubectl exec pg_dump approach)
- CNPG's `ScheduledBackup` CRD handles backups natively to MinIO
- Add `postgres-backups` to MinIO bucket list in values

---

## Phase 6: Stress Test

```bash
task test:hyperfoil:stress
```

Baseline: ~2,400 req/s at 5ms mean.

If regression, check:
1. ExternalName resolution overhead
2. CNPG pod resource allocation
3. NPs blocking traffic
4. PostgreSQL parameter differences (CNPG may apply defaults differently)

---

## Phase 7: Cleanup (after 1 week stable)

Delete from `helm/schnappy-data/templates/`:
- `postgres-deployment.yaml`
- `postgres-pvc.yaml`
- `postgres-service.yaml`
- `postgres-secret.yaml`
- `postgres-backup-cronjob.yaml`

Clean up old `postgres.enabled` guards and ExternalSecret.
Delete old PVC: `kubectl delete pvc schnappy-postgres -n schnappy`

---

## Files Summary

### Create (infra)
| File | Purpose |
|------|---------|
| `clusters/production/argocd/apps/cnpg.yaml` | ArgoCD app |
| `clusters/production/cnpg/values.yaml` | Operator values |

### Create (platform)
| File | Purpose |
|------|---------|
| `helm/schnappy-data/templates/cnpg-cluster.yaml` | Cluster CRD |
| `helm/schnappy-data/templates/cnpg-secret.yaml` | CNPG superuser ExternalSecret |
| `helm/schnappy-data/templates/cnpg-service-compat.yaml` | ExternalName compat |
| `helm/schnappy-data/templates/cnpg-backup.yaml` | ScheduledBackup CRD |

### Modify (platform)
| File | Change |
|------|--------|
| `helm/schnappy-data/values.yaml` | Add `cnpg.enabled` |
| `helm/schnappy-data/templates/_helpers.tpl` | Conditional postgres selector labels |
| `helm/schnappy-data/templates/network-policies.yaml` | Add CNPG NPs, guard old PG NPs |
| `helm/schnappy-data/templates/external-secrets.yaml` | Add CNPG superuser secret |
| `helm/schnappy/values.yaml` | Add `cnpg.enabled` |
| `helm/schnappy/templates/_helpers.tpl` | Conditional postgres selector labels |

### Modify (infra)
| File | Change |
|------|--------|
| `clusters/production/schnappy-data/values.yaml` | Add `cnpg.enabled`, flip `postgres.enabled`, add MinIO bucket |
| `clusters/production/schnappy/values.yaml` | Add `cnpg.enabled: true` |

### Delete (Phase 7)
- `postgres-deployment.yaml`, `postgres-pvc.yaml`, `postgres-service.yaml`, `postgres-secret.yaml`, `postgres-backup-cronjob.yaml`

## Rollback

Revert infra values: `postgres.enabled: true`, `cnpg.enabled: false`. Old PVC with data remains (helm resource-policy: keep).

## Lessons from Strimzi (Plan 052)

- Exclude operator control ports from Istio sidecar interception
- Disable Istio sidecar on operator helper pods (entity-operator equivalent = CNPG jobs)
- Apply Istio annotations via CR pod template, not manual patches
- Test NP ports before cutover — operator pods need cross-namespace access
