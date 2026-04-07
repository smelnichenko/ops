# Plan 052: Strimzi Kafka Operator Migration + Stress Test

**Status: TODO**

## Context

Kafka is currently a hand-rolled StatefulSet in the `schnappy-data` Helm chart (KRaft mode, `apache/kafka:4.2.0`, 1 replica). Migrating to Strimzi (0.51.0) replaces it with operator-managed CRDs — declarative topic lifecycle via `KafkaTopic`, rolling updates, and standardized configuration. Strimzi 0.51.0 supports Kafka 4.2.0 natively, no version change needed.

PostgreSQL stays unchanged. After migration, run Hyperfoil stress test to validate no regression from ~2,400 req/s baseline.

---

## Phase 1: Install Strimzi Operator

### 1.1 ArgoCD app

Create `/home/sm/src/infra/clusters/production/argocd/apps/strimzi.yaml`:
- Chart: `strimzi-kafka-operator` from `https://strimzi.io/charts/`, version `0.51.0`
- Namespace: `strimzi`, sync-wave `-1` (before schnappy-data at wave 0)
- `ServerSideApply=true` (CRD-heavy)
- Values from `$values/clusters/production/strimzi/values.yaml`

### 1.2 Operator values

Create `/home/sm/src/infra/clusters/production/strimzi/values.yaml`:
- `watchAnyNamespace: true` (manage CRs in `schnappy` namespace)
- Resources: 100m/500m CPU, 256Mi/512Mi memory

### 1.3 Verify

```bash
kubectl get pods -n strimzi
kubectl get crd | grep kafka
```

---

## Phase 2: Add Strimzi CRD Templates

New templates in `/home/sm/src/platform/helm/schnappy-data/templates/`, all guarded by `strimzi.enabled`.

### 2.1 `strimzi-kafka.yaml` — KafkaNodePool + Kafka CRDs

**KafkaNodePool** `schnappy`:
- `roles: [controller, broker]`, 1 replica
- Storage: persistent-claim, 10Gi, `local-path`
- Resources: 250m/2000m CPU, 1536Mi/2Gi memory
- JVM: `-Xms1g -Xmx1g`
- Label: `strimzi.io/cluster: schnappy`

**Kafka** `schnappy`:
- Annotations: `strimzi.io/kraft: enabled`, `strimzi.io/node-pools: enabled`
- Listener: `plain`, port 9092, internal, no TLS
- Config: offsets/transaction replication=1, retention from values
- `entityOperator.topicOperator: {}` for KafkaTopic management
- Bootstrap service will be `schnappy-kafka-bootstrap`

### 2.2 `strimzi-topics.yaml` — KafkaTopic CRDs

Range over existing `.Values.kafka.topics` (reuses current topic config). Replaces the PostSync kafka-topics Job.

### 2.3 `strimzi-service-compat.yaml` — ExternalName service

`schnappy-kafka` → `schnappy-kafka-bootstrap.schnappy.svc.cluster.local`

Only created when `strimzi.enabled && !kafka.enabled` (avoids name conflict).

### 2.4 Values additions

Base `helm/schnappy-data/values.yaml`:
```yaml
strimzi:
  enabled: false
```

Production `clusters/production/schnappy-data/values.yaml` — same, initially `false`.

---

## Phase 3: Network Policy Updates

### Problem

Both `schnappy-data` and `schnappy` charts use `schnappy.kafka.selectorLabels` in NPs, which resolves to `app.kubernetes.io/name: schnappy, app.kubernetes.io/component: kafka`. Strimzi pods use `strimzi.io/cluster: schnappy, strimzi.io/kind: Kafka`.

### Solution

Make `schnappy.kafka.selectorLabels` conditional on `strimzi.enabled` in both charts' `_helpers.tpl`:

```
{{- define "schnappy.kafka.selectorLabels" -}}
{{- if .Values.strimzi.enabled }}
strimzi.io/cluster: schnappy
strimzi.io/kind: Kafka
{{- else }}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: kafka
{{- end }}
{{- end }}
```

All existing NP references automatically pick up the correct labels.

**Additional NPs in schnappy-data**:
- Strimzi Entity Operator pod: egress to Kafka broker + K8s API
- Strimzi operator namespace: cross-namespace access to Kafka pods
- Guard old kafka NP and kafka-job NP blocks with `kafka.enabled`

**schnappy chart**: Add `strimzi.enabled: false` to base values, `true` to production values (at cutover).

---

## Phase 4: Cutover

Single commit to infra repo values. Kafka topics are ephemeral (7-day retention) — data loss acceptable.

`clusters/production/schnappy-data/values.yaml`:
```yaml
kafka:
  enabled: false    # removes old StatefulSet + Service + Job
strimzi:
  enabled: true     # creates Kafka CRD + topics + compat service
```

`clusters/production/schnappy/values.yaml`:
```yaml
strimzi:
  enabled: true     # switches NP selectors to Strimzi labels
```

### What happens on ArgoCD sync

1. Old StatefulSet, Service, topics Job pruned
2. Strimzi `Kafka` + `KafkaNodePool` CRDs created → operator provisions broker
3. `KafkaTopic` CRDs created → Entity Operator creates topics
4. ExternalName `schnappy-kafka` created → apps resolve same DNS
5. Apps reconnect (Spring Kafka auto-reconnects)

### ExternalSecret

Old Kafka ExternalSecret (`KAFKA_CLUSTER_ID`) no longer needed — Strimzi generates its own. Already guarded by `kafka.existingSecret`, so disabling `kafka.enabled` prevents the old secret template from rendering. Guard explicitly if needed.

---

## Phase 5: Stress Test

```bash
task test:hyperfoil:stress
```

**Baseline**: ~2,400 req/s at 5ms mean (Plan 050/051).

If regression, check:
1. ExternalName resolution overhead → switch to ClusterIP with Strimzi labels
2. Entity Operator resource usage
3. NPs blocking Strimzi pod traffic
4. Broker resource limits vs old StatefulSet

---

## Phase 6: Cleanup (after 1 week stable)

Delete from `helm/schnappy-data/templates/`:
- `kafka-statefulset.yaml`
- `kafka-service.yaml`
- `kafka-secret.yaml`
- `kafka-topics-job.yaml`

Remove from `external-secrets.yaml`: Kafka CLUSTER_ID block.
Remove from `network-policies.yaml`: old kafka and kafka-job NP blocks.
Delete old PVC: `kubectl delete pvc data-schnappy-kafka-0 -n schnappy`

---

## Files Summary

### Create (infra)
| File | Purpose |
|------|---------|
| `clusters/production/argocd/apps/strimzi.yaml` | ArgoCD app |
| `clusters/production/strimzi/values.yaml` | Operator values |

### Create (platform)
| File | Purpose |
|------|---------|
| `helm/schnappy-data/templates/strimzi-kafka.yaml` | Kafka + KafkaNodePool CRDs |
| `helm/schnappy-data/templates/strimzi-topics.yaml` | KafkaTopic CRDs |
| `helm/schnappy-data/templates/strimzi-service-compat.yaml` | ExternalName compat |

### Modify (platform)
| File | Change |
|------|--------|
| `helm/schnappy-data/values.yaml` | Add `strimzi.enabled` |
| `helm/schnappy-data/templates/_helpers.tpl` | Conditional kafka selector labels |
| `helm/schnappy-data/templates/network-policies.yaml` | Guard old Kafka NPs, add Strimzi NPs |
| `helm/schnappy-data/templates/external-secrets.yaml` | Guard Kafka secret |
| `helm/schnappy/values.yaml` | Add `strimzi.enabled` |
| `helm/schnappy/templates/_helpers.tpl` | Conditional kafka selector labels |

### Modify (infra)
| File | Change |
|------|--------|
| `clusters/production/schnappy-data/values.yaml` | Add `strimzi.enabled`, flip `kafka.enabled` |
| `clusters/production/schnappy/values.yaml` | Add `strimzi.enabled: true` |

### Delete (Phase 6)
- `kafka-statefulset.yaml`, `kafka-service.yaml`, `kafka-secret.yaml`, `kafka-topics-job.yaml`

## Rollback

Revert infra values: `kafka.enabled: true`, `strimzi.enabled: false`. ArgoCD syncs and restores old StatefulSet. Old PVC remains until explicitly deleted.
