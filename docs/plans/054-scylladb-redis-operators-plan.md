# Plan 054: ScyllaDB Operator + Redis Operator Integration

**Status**: In Progress
**Date**: 2026-04-07

## Context

Migrate ScyllaDB from a manually-managed StatefulSet to the ScyllaDB Operator, following the same pattern as CNPG (PostgreSQL) and Strimzi (Kafka). Then compare and integrate a Redis operator. Part of the broader effort to operator-manage all stateful workloads for multi-environment support.

## Phase 1: ScyllaDB Operator

### Current State

- ScyllaDB 6.2 as a plain StatefulSet (1 replica) in `schnappy` namespace
- Schema: PostSync hook Job creates keyspace `chat` with 6 tables
- Connection: `SCYLLA_CONTACT_POINTS=schnappy-scylla:9042`, datacenter `datacenter1`
- Developer mode: `--smp=2 --memory=2G --overprovisioned=1`
- Storage: 20Gi local-path
- Resources: 200m–4000m CPU, 2–4Gi RAM
- Data: chat messages (ephemeral, loss acceptable)

### Operator Details

- **Version**: 1.20 (latest, March 2026)
- **Helm chart**: `scylla-operator` from `https://scylla-operator-charts.storage.googleapis.com/stable`
- **CRD**: `ScyllaCluster` (scylla.scylladb.com/v1)
- **Manager**: Separate component (scylla-manager), NOT mandatory
  - Without Manager: backup/repair CRD tasks are ignored, basic cluster ops work fine
  - With Manager: automated backups to S3/MinIO, scheduled repairs
- **Developer mode**: `developerMode: true` relaxes CPU pinning and QoS requirements

### Decision: Deploy with Manager

Deploy Manager for backup automation to Pi MinIO (same pattern as CNPG). Manager overhead is small — it runs a lightweight ScyllaDB instance for its own state.

### Backups

ScyllaDB Manager supports backup to S3-compatible storage (MinIO):
- Defined in `ScyllaCluster.spec.backups[]` array
- Fields: `cron`, `dc`, `keyspace`, `location` (`s3:<bucket>`), `retention`
- Credentials via Manager Agent config or IAM roles
- Destination: Pi MinIO (`192.168.11.5:9000`), bucket `scylla-backups`
- Deduplication: Manager avoids re-uploading unchanged SSTables
- Restore: manual via `sctool restore` in Manager pod (CRD-based restore not yet implemented)

### Changes

#### Infra repo — new files

| File | Purpose |
|------|---------|
| `clusters/production/argocd/apps/scylla-operator.yaml` | ArgoCD app, sync-wave -1, SSA=true, ns: scylla-operator |
| `clusters/production/argocd/apps/scylla-manager.yaml` | ArgoCD app, sync-wave -1, SSA=true, ns: scylla-manager |
| `clusters/production/scylla-operator/values.yaml` | Operator resources (100m/256Mi → 500m/512Mi) |
| `clusters/production/scylla-manager/values.yaml` | Manager resources, S3 config for Pi MinIO |

#### Infra repo — modified files

| File | Change |
|------|--------|
| `clusters/production/schnappy-data/values.yaml` | `scylla.enabled: false`, `scyllaOperator.enabled: true` with cluster spec |

#### Platform repo — new files

| File | Purpose |
|------|---------|
| `helm/schnappy-data/templates/scylla-cluster.yaml` | ScyllaCluster CRD, guarded by `scyllaOperator.enabled` |
| `helm/schnappy-data/templates/scylla-compat-service.yaml` | ExternalName `schnappy-scylla` → operator client service |

#### Platform repo — modified files

| File | Change |
|------|--------|
| `helm/schnappy-data/templates/network-policies.yaml` | Add ingress from scylla-operator ns on operator ports |
| `helm/schnappy-data/templates/_helpers.tpl` | Conditional scylla selector labels for operator mode |
| `helm/schnappy-data/values.yaml` | Add `scyllaOperator` defaults |
| `helm/schnappy-mesh/templates/peer-authentication.yaml` | PERMISSIVE for agent health ports if needed |

#### Platform repo — deleted after migration

| File | Reason |
|------|--------|
| `scylla-statefulset.yaml` | Replaced by ScyllaCluster CRD |
| `scylla-service.yaml` | Replaced by operator-generated services |

#### Keep

| File | Reason |
|------|--------|
| `scylla-schema-job.yaml` | Still needed — operator doesn't manage application schemas |

#### Ops repo

| File | Purpose |
|------|---------|
| `docs/plans/054-scylladb-redis-operators-plan.md` | This plan |

#### Pi MinIO

- Create `scylla-backups` bucket on pi1 and pi2
- Add to `setup-pi-services.yml` bucket list
- Store credentials in Vault: `secret/schnappy/minio-backup` (already exists, same Pi MinIO)

### ScyllaCluster CR

```yaml
apiVersion: scylla.scylladb.com/v1
kind: ScyllaCluster
metadata:
  name: schnappy-scylla
spec:
  repository: docker.io/scylladb/scylla
  version: "6.2"
  agentVersion: "3.9.0"
  developerMode: true
  datacenter:
    name: datacenter1
    racks:
      - name: rack1
        members: 1
        storage:
          capacity: 20Gi
          storageClassName: local-path
        resources:
          requests:
            cpu: 200m
            memory: 2Gi
          limits:
            cpu: 4000m
            memory: 4Gi
        agentResources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
  backups:
    - name: daily
      cron: "0 2 * * *"
      keyspace: ["chat"]
      location: ["s3:scylla-backups"]
      retention: 7
```

### Migration Steps

1. Deploy scylla-operator ArgoCD app (sync-wave -1)
2. Deploy scylla-manager ArgoCD app (sync-wave -1)
3. Wait for operator + manager pods ready
4. Enable `scyllaOperator.enabled: true` in schnappy-data values (keep `scylla.enabled: true` temporarily)
5. ScyllaCluster deploys alongside old StatefulSet
6. Run schema job against new cluster
7. Verify CQL connectivity from chat service
8. Switch `scylla.enabled: false` → apps use new operator cluster
9. Chat data is ephemeral — no migration needed
10. Delete old StatefulSet/Service templates
11. Verify backup runs to Pi MinIO

### ignoreDifferences

Add to schnappy-data ArgoCD app (same pattern as CNPG):
```yaml
- group: scylla.scylladb.com
  kind: ScyllaCluster
  jqPathExpressions:
    - .spec.datacenter.racks[]?.placement
    # Additional defaults TBD after first deployment
```

## Phase 2: Redis Operator Comparison

### Candidates

| Feature | Spotahome | OpsTree |
|---------|-----------|---------|
| Last release | Jan 2022 (slow) | Nov 2022 |
| Modes | HA with Sentinel | Standalone/Cluster/Replication/Sentinel |
| Monitoring | Manual | Built-in redis-exporter |
| CRDs | RedisFailover | Redis, RedisCluster, RedisReplication, RedisSentinel |
| Helm chart | spotahome/redis-operator | ot-helm/redis-operator |
| Maturity | Older, proven | Newer, more features |

### Current Redis State

- Simple `redis:7-alpine` Deployment (1 replica)
- Volatile cache — no persistence, no replication
- Used by: monitor, admin, chat, chess services for session/cache
- Connection: `REDIS_HOST=schnappy-redis:6379`

### Recommendation

**OpsTree Redis Operator** — more actively maintained, supports standalone mode (matches current use case), built-in monitoring, cleaner CRD model.

But: for a volatile cache with no persistence, the operator adds complexity without significant benefit. Recommend deferring Redis operator until multi-replica or persistence is needed. For multi-env support, just parameterize the current Deployment names.

### Decision: Defer Redis operator

Keep simple Deployment for now. Parameterize names for multi-env. Revisit when Redis persistence or HA is needed.

## Verification

1. ScyllaDB Operator + Manager pods running in their namespaces
2. ScyllaCluster shows Ready status
3. Schema job creates keyspace and tables on new cluster
4. Chat service connects, sends/receives messages
5. Backup runs to Pi MinIO (`scylla-backups` bucket)
6. All ArgoCD apps Synced Healthy
7. Stress test maintains baseline throughput
