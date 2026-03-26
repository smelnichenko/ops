# Split Monolithic Argo CD Application by Lifecycle

## Status: COMPLETE (2026-03-26)

Monolithic Helm chart split into 5 lifecycle-based sub-charts, deployed via Argo CD. Old monolith removed. Argo CD upgraded from v2.14.7 to v3.3.5 (PKCE fix). All 5 Applications Synced + Healthy.

**Post-deploy fixes applied:**
- `releaseName: schnappy` on all Applications (NP selector matching)
- Finalizers added to all 5 Applications
- Cross-chart NP conditionals removed (unconditional rules)
- `postgres.database: monitor` added to core chart
- Keycloak SMTP config added to auth chart values
- keycloak-theme CD pipeline targets `schnappy-auth/values.yaml`
- Alertmanager integration restored in core app values
- `wait-for-postgres` init containers on app/admin/chat/chess/keycloak
- Sync wave annotations (data→auth→app→obs/sq)
- Argo CD OIDC config moved into Helm values (v3 selfHeal compatibility)
- Old monolith chart + orphaned PVCs cleaned up

## Motivation

The `schnappy` Argo CD Application deploys a single Helm chart with ~99 templates covering everything in the `schnappy` namespace — from microservices to Kafka/ScyllaDB to ELK to SonarQube. Problems:

- **Blast radius:** A bad SonarQube template change blocks the entire app sync
- **Noisy reconciliation:** Updating a chat image tag reconciles all ~99 resources
- **Single sync status:** Can't tell at a glance if the data layer is healthy vs the app layer
- **Mixed lifecycles:** SonarQube changes monthly, app images change daily — yet they share one sync cycle

Infrastructure components (cert-manager, vault, velero, woodpecker, forgejo) are already separate Applications. The `schnappy` monolith is the last one to split.

## Current Architecture

**One Application** (`schnappy`) → **one Helm chart** (`platform.git/helm`) → **one values file** (`infra.git/clusters/production/schnappy/values.yaml`)

All 8 CD pipelines (monitor, admin, chat, chess, gateway, site, game-scp, keycloak-theme) commit image tags to the same `values.yaml` using sed with comment anchors (e.g., `# admin-service`, `# chat-service`).

**Cross-cutting concerns in the monolith:**
- `network-policies.yaml` (1457 lines) — references pods across all groups
- `external-secrets.yaml` (316 lines) — 13 ExternalSecrets for all components
- `_helpers.tpl` (684 lines) — shared label/name helpers for all components

## Target Architecture

Split into **5 Argo CD Applications**, all deploying to the `schnappy` namespace:

| Application | Chart Path | Changes When | Templates |
|---|---|---|---|
| `schnappy` | `helm/schnappy` | Code pushes (daily) | app, admin, chat, chess, gateway, site, game |
| `schnappy-data` | `helm/schnappy-data` | Version bumps (monthly) | postgres, redis, kafka, scylla, minio, apt-cache |
| `schnappy-auth` | `helm/schnappy-auth` | Auth config changes (rare) | keycloak |
| `schnappy-observability` | `helm/schnappy-observability` | Dashboard/config changes (weekly) | ELK, prometheus, grafana, alertmanager, kube-state-metrics |
| `schnappy-sonarqube` | `helm/schnappy-sonarqube` | QG/rule changes (rare) | sonarqube + sonarqube-postgres |

## Design Decisions

### Resource naming: `nameOverride: schnappy`

Each sub-chart sets `nameOverride: schnappy` in its default values. This makes `schnappy.fullname` resolve to `schnappy` in all charts, keeping resource names identical to the current monolith (e.g., `schnappy-postgres`, `schnappy-app`). Zero resource recreation.

### Cross-chart pod selection: `part-of` + `component` labels

Currently, network policies use `app.kubernetes.io/name` + `instance` + `component` to select pods. After the split, `name` differs per chart. Solution:

Add `app.kubernetes.io/part-of: schnappy` to all resources across all 5 charts. Network policies that reference pods from other charts use only `part-of` + `component`:

```yaml
# Core app chart NP → postgres pod (in data chart)
podSelector:
  matchLabels:
    app.kubernetes.io/part-of: schnappy
    app.kubernetes.io/component: postgres
```

This works because component labels are unique within the namespace.

### Default-deny NetworkPolicy → cluster-config

Move the namespace-wide default-deny from Helm to raw manifest in `cluster-config/`:

```yaml
# clusters/production/cluster-config/schnappy-default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: schnappy-default-deny
  namespace: schnappy
spec:
  podSelector: {}  # matches ALL pods in namespace
  policyTypes:
    - Ingress
    - Egress
  egress:
    - ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

Using `podSelector: {}` instead of label-based matching ensures all pods in the namespace are covered regardless of which chart deployed them. Each chart then only has specific allow rules.

### ExternalSecrets: co-located with consumers

Each chart owns the ExternalSecrets for the secrets it consumes:

| Chart | ExternalSecrets |
|---|---|
| `schnappy` | auth, ai, mail, webhook |
| `schnappy-data` | postgres, redis, kafka, minio |
| `schnappy-auth` | keycloak |
| `schnappy-observability` | elasticsearch, grafana, alertmanager |
| `schnappy-sonarqube` | sonarqube |

### CD pipelines: unchanged targeting

All 8 CD pipelines continue to target `clusters/production/schnappy/values.yaml` — the core app chart's values file. Only the core app chart has image tags that change via CD. Data, auth, observability, and sonarqube values files are updated manually or via dedicated PRs.

## Chart Directory Structure

```
platform/
├── helm/
│   ├── schnappy/                          # Core app services (daily changes)
│   │   ├── Chart.yaml                     # name: schnappy
│   │   ├── values.yaml
│   │   ├── templates/
│   │   │   ├── _helpers.tpl
│   │   │   ├── NOTES.txt
│   │   │   ├── app-deployment.yaml
│   │   │   ├── app-service.yaml
│   │   │   ├── app-ingress.yaml
│   │   │   ├── app-configmap.yaml
│   │   │   ├── admin-deployment.yaml
│   │   │   ├── admin-service.yaml
│   │   │   ├── chat-deployment.yaml
│   │   │   ├── chat-service.yaml
│   │   │   ├── chess-deployment.yaml
│   │   │   ├── chess-service.yaml
│   │   │   ├── gateway-deployment.yaml
│   │   │   ├── gateway-service.yaml
│   │   │   ├── gateway-configmap.yaml
│   │   │   ├── site-deployment.yaml
│   │   │   ├── site-service.yaml
│   │   │   ├── site-games-configmap.yaml
│   │   │   ├── game-deployment.yaml
│   │   │   ├── game-service.yaml
│   │   │   ├── game-ingress.yaml
│   │   │   ├── auth-secret.yaml
│   │   │   ├── ai-secret.yaml
│   │   │   ├── mail-secret.yaml
│   │   │   ├── webhook-secret.yaml
│   │   │   ├── external-secrets.yaml      # auth, ai, mail, webhook ExternalSecrets
│   │   │   ├── network-policies.yaml      # app, gateway, admin, chat, chess, site, game NPs
│   │   │   └── linkerd-auth-policy.yaml
│   │
│   ├── schnappy-data/                     # Stateful data stores (monthly changes)
│   │   ├── Chart.yaml                     # name: schnappy-data
│   │   ├── values.yaml
│   │   ├── templates/
│   │   │   ├── _helpers.tpl
│   │   │   ├── postgres-deployment.yaml
│   │   │   ├── postgres-service.yaml
│   │   │   ├── postgres-pvc.yaml
│   │   │   ├── postgres-secret.yaml
│   │   │   ├── postgres-backup-cronjob.yaml
│   │   │   ├── redis-deployment.yaml
│   │   │   ├── redis-service.yaml
│   │   │   ├── redis-secret.yaml
│   │   │   ├── kafka-statefulset.yaml
│   │   │   ├── kafka-service.yaml
│   │   │   ├── kafka-secret.yaml
│   │   │   ├── kafka-topics-job.yaml
│   │   │   ├── scylla-statefulset.yaml
│   │   │   ├── scylla-service.yaml
│   │   │   ├── scylla-schema-job.yaml
│   │   │   ├── minio-deployment.yaml
│   │   │   ├── minio-service.yaml
│   │   │   ├── minio-pvc.yaml
│   │   │   ├── minio-secret.yaml
│   │   │   ├── apt-cache-deployment.yaml
│   │   │   ├── apt-cache-service.yaml
│   │   │   ├── apt-cache-pvc.yaml
│   │   │   ├── apt-cache-configmap.yaml
│   │   │   ├── external-secrets.yaml      # postgres, redis, kafka, minio ExternalSecrets
│   │   │   └── network-policies.yaml      # postgres, redis, kafka, scylla, minio, apt-cache NPs
│   │
│   ├── schnappy-auth/                     # Authentication (rare changes)
│   │   ├── Chart.yaml                     # name: schnappy-auth
│   │   ├── values.yaml
│   │   ├── templates/
│   │   │   ├── _helpers.tpl
│   │   │   ├── keycloak-deployment.yaml
│   │   │   ├── keycloak-service.yaml
│   │   │   ├── keycloak-ingress.yaml
│   │   │   ├── keycloak-secret.yaml
│   │   │   ├── keycloak-realm-configmap.yaml
│   │   │   ├── external-secrets.yaml      # keycloak ExternalSecret
│   │   │   └── network-policies.yaml      # keycloak NP
│   │
│   ├── schnappy-observability/            # Monitoring + logging (weekly changes)
│   │   ├── Chart.yaml                     # name: schnappy-observability
│   │   ├── values.yaml
│   │   ├── templates/
│   │   │   ├── _helpers.tpl
│   │   │   ├── elasticsearch-statefulset.yaml
│   │   │   ├── elasticsearch-service.yaml
│   │   │   ├── elasticsearch-configmap.yaml
│   │   │   ├── elasticsearch-secret.yaml
│   │   │   ├── elasticsearch-ilm-job.yaml
│   │   │   ├── kibana-deployment.yaml
│   │   │   ├── kibana-service.yaml
│   │   │   ├── kibana-ingress.yaml
│   │   │   ├── kibana-configmap.yaml
│   │   │   ├── fluentbit-daemonset.yaml
│   │   │   ├── fluentbit-configmap.yaml
│   │   │   ├── fluentbit-rbac.yaml
│   │   │   ├── prometheus-deployment.yaml
│   │   │   ├── prometheus-service.yaml
│   │   │   ├── prometheus-pvc.yaml
│   │   │   ├── prometheus-configmap.yaml
│   │   │   ├── prometheus-rules-configmap.yaml
│   │   │   ├── grafana-deployment.yaml
│   │   │   ├── grafana-service.yaml
│   │   │   ├── grafana-ingress.yaml
│   │   │   ├── grafana-pvc.yaml
│   │   │   ├── grafana-secret.yaml
│   │   │   ├── grafana-dashboards-configmap.yaml
│   │   │   ├── grafana-datasources-configmap.yaml
│   │   │   ├── grafana-dashboard-provider-configmap.yaml
│   │   │   ├── alertmanager-deployment.yaml
│   │   │   ├── alertmanager-service.yaml
│   │   │   ├── alertmanager-pvc.yaml
│   │   │   ├── alertmanager-configmap.yaml
│   │   │   ├── alertmanager-secret.yaml
│   │   │   ├── kube-state-metrics-deployment.yaml
│   │   │   ├── kube-state-metrics-service.yaml
│   │   │   ├── kube-state-metrics-rbac.yaml
│   │   │   ├── external-secrets.yaml      # elasticsearch, grafana, alertmanager ExternalSecrets
│   │   │   └── network-policies.yaml      # ES, kibana, fluentbit, prometheus, grafana, alertmanager, KSM NPs
│   │
│   └── schnappy-sonarqube/                # Dev tooling (rare changes)
│       ├── Chart.yaml                     # name: schnappy-sonarqube
│       ├── values.yaml
│       ├── templates/
│       │   ├── _helpers.tpl
│       │   ├── sonarqube-deployment.yaml
│       │   ├── sonarqube-service.yaml
│       │   ├── sonarqube-ingress.yaml
│       │   ├── sonarqube-pvc.yaml
│       │   ├── sonarqube-secret.yaml
│       │   ├── sonarqube-setup-job.yaml
│       │   ├── sonarqube-postgres-statefulset.yaml
│       │   ├── sonarqube-postgres-service.yaml
│       │   ├── external-secrets.yaml      # sonarqube ExternalSecret
│       │   └── network-policies.yaml      # sonarqube + sonarqube-setup NPs
```

## Infra Repo Changes

### Argo CD Application manifests

Replace `argocd/apps/schnappy.yaml` with 5 Application manifests.

Example (`argocd/apps/schnappy.yaml` — updated):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: schnappy
  namespace: argocd
  # NOTE: no finalizer — allows safe deletion without pruning resources
spec:
  project: default
  sources:
    - repoURL: https://git.pmon.dev/schnappy/platform.git
      targetRevision: main
      path: helm/schnappy        # was: helm
      helm:
        valueFiles:
          - $values/clusters/production/schnappy/values.yaml
    - repoURL: https://git.pmon.dev/schnappy/infra.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: schnappy
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

New Applications follow the same pattern with their respective paths and values files:
- `schnappy-data.yaml` → `path: helm/schnappy-data`, values: `$values/clusters/production/schnappy-data/values.yaml`
- `schnappy-auth.yaml` → `path: helm/schnappy-auth`, values: `$values/clusters/production/schnappy-auth/values.yaml`
- `schnappy-observability.yaml` → `path: helm/schnappy-observability`, values: `$values/clusters/production/schnappy-observability/values.yaml`
- `schnappy-sonarqube.yaml` → `path: helm/schnappy-sonarqube`, values: `$values/clusters/production/schnappy-sonarqube/values.yaml`

### Values files split

Split `clusters/production/schnappy/values.yaml` into 5 files. Each chart only gets the value keys it needs.

**`clusters/production/schnappy/values.yaml`** (core app — keeps all image tags):
```yaml
vault:
  secretsEnabled: true
app: { ... }        # image tag, resources, ingress, hikari
site: { ... }       # image tag, resources
games: [ ... ]      # image tags
gateway: { ... }    # image tag, resources, cors
admin: { ... }      # image tag, resources
chatService: { ... } # image tag, resources
chessService: { ... } # image tag, resources
auth: { ... }       # existingSecret
chat: { ... }       # e2eEnabled
monitor: { ... }    # http settings
captcha: { ... }
ai: { ... }         # model, existingSecret
mail: { ... }       # SMTP config, existingSecret
webhook: { ... }    # existingSecret
linkerd: { ... }
networkPolicies:
  enabled: true
```

**`clusters/production/schnappy-data/values.yaml`**:
```yaml
vault:
  secretsEnabled: true
postgres: { ... }   # image, storage, tuning, existingSecret
redis: { ... }      # image, resources, existingSecret
kafka: { ... }      # image, storage, topics, existingSecret
scylla: { ... }     # image, storage, args
minio: { ... }      # image, storage, existingSecret
aptCache: { ... }   # storage
networkPolicies:
  enabled: true
```

**`clusters/production/schnappy-auth/values.yaml`**:
```yaml
vault:
  secretsEnabled: true
keycloak: { ... }   # image, hostname, clients, ingress, existingSecret
networkPolicies:
  enabled: true
```

**`clusters/production/schnappy-observability/values.yaml`**:
```yaml
vault:
  secretsEnabled: true
elk: { ... }          # ES, kibana, fluentbit images/storage/ingress
prometheus: { ... }   # image, retention, storage, scrape targets
grafana: { ... }      # image, ingress, OAuth, existingSecret
alertmanager: { ... } # existingSecret, email config
kubeStateMetrics: { ... }
networkPolicies:
  enabled: true
```

**`clusters/production/schnappy-sonarqube/values.yaml`**:
```yaml
vault:
  secretsEnabled: true
sonarqube: { ... }  # image, ingress, storage, setup, existingSecret
networkPolicies:
  enabled: true
```

### Default-deny NetworkPolicy

New file `clusters/production/cluster-config/schnappy-default-deny.yaml`:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: schnappy-default-deny
  namespace: schnappy
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  egress:
    - ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

## _helpers.tpl Strategy

Each chart gets its own `_helpers.tpl` with:
1. **Standard chart helpers** (fullname, chart, labels) — identical boilerplate, `nameOverride: schnappy` ensures consistent naming
2. **Own component helpers** (labels, selectorLabels, serviceName, secretName) — for its own templates
3. **Cross-chart reference helpers** — minimal helpers for referencing pods in other charts via `part-of` + `component`:

```yaml
{{/* Cross-chart pod selector: use only part-of + component */}}
{{- define "schnappy.crossChart.selectorLabels" -}}
app.kubernetes.io/part-of: schnappy
app.kubernetes.io/component: {{ .component }}
{{- end }}
```

All charts add `app.kubernetes.io/part-of: schnappy` to all their labels:
```yaml
{{- define "schnappy-data.labels" -}}
helm.sh/chart: {{ include "schnappy-data.chart" . }}
{{ include "schnappy-data.selectorLabels" . }}
app.kubernetes.io/part-of: schnappy
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

## Network Policy Changes

### Within-chart NPs (no change needed)

NPs that only reference pods from their own chart keep using chart-local selectorLabels. Example: kibana → elasticsearch (both in observability chart).

### Cross-chart NPs

NPs that reference pods in other charts switch to `part-of` + `component` selectors. Example in core app chart:

```yaml
# Before (monolith):
- to:
    - podSelector:
        matchLabels:
          {{- include "schnappy.postgres.selectorLabels" . | nindent 14 }}

# After (cross-chart):
- to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/part-of: schnappy
          app.kubernetes.io/component: postgres
```

### Cross-chart NP dependency map

| Chart | NP Pod | Needs ingress from (other charts) | Needs egress to (other charts) |
|---|---|---|---|
| **data** | postgres | app, admin, chat, chess (core), keycloak (auth) | — |
| **data** | redis | app, gateway, admin, chat, chess (core) | — |
| **data** | kafka | app, admin, chat, chess (core) | — |
| **data** | scylla | app, chat (core) | — |
| **data** | minio | app (core) | — |
| **core** | app | prometheus (obs), alertmanager (obs) | postgres, redis, kafka, scylla, minio (data), elasticsearch (obs), keycloak (auth) |
| **core** | gateway | — | keycloak (auth), redis (data) |
| **core** | admin | prometheus (obs) | postgres, redis, kafka (data), keycloak (auth) |
| **core** | chat | prometheus (obs) | postgres, redis, kafka, scylla (data) |
| **core** | chess | prometheus (obs) | postgres, redis, kafka (data) |
| **obs** | prometheus | grafana (self) | app, admin, chat, chess, gateway (core) |
| **obs** | alertmanager | — | app (core) |
| **obs** | grafana | — | keycloak (auth) |
| **obs** | elasticsearch | app (core), fluentbit (self), es-ilm-job (self) | — |
| **auth** | keycloak | gateway, admin (core), grafana (obs) | postgres (data) |

## Migration Strategy (Zero-Downtime)

### Phase 1: Label preparation (deploy to monolith)

Update the monolithic chart without splitting:

1. Add `app.kubernetes.io/part-of: schnappy` to all resources (every labels block and selectorLabels block)
2. **Do NOT change selectorLabels on Deployments/StatefulSets** — changing selector labels requires resource recreation. Instead, only add `part-of` to `metadata.labels` and `spec.template.metadata.labels` (pod template). Selector labels (`spec.selector.matchLabels`) remain unchanged.
3. Update all cross-chart NP pod selectors to use `part-of` + `component` pattern
4. Deploy via normal CD flow and verify everything works
5. **Verify:** All NPs still allow correct traffic, all pods have `part-of` label

**Risk:** Label changes to pod templates trigger rolling restarts. This is expected and safe with rolling update strategy.

### Phase 2: Chart split (platform repo)

1. Create 5 chart directories under `helm/`
2. Move templates to their respective charts
3. Create per-chart `Chart.yaml` with `nameOverride: schnappy`
4. Create per-chart `_helpers.tpl` (subset of original)
5. Create per-chart `values.yaml` (chart defaults only, not production overrides)
6. **Validate:** `helm template` each chart locally and diff against monolith output
7. Push to `platform.git` main branch

**The old `helm/` directory (monolith) can be removed once the new charts are in place.** The old Application still points to `helm` path, so this must be coordinated with Phase 3.

Actually — keep the old `helm/` directory temporarily during Phase 3. Move it to `helm/_old` or leave it until switchover is confirmed.

### Phase 3: Infra repo switchover

**Step 1:** Update `argocd/apps/schnappy.yaml` to remove the finalizer:
```yaml
metadata:
  name: schnappy
  namespace: argocd
  # finalizers: REMOVED
```
Push, wait for root Application to sync and remove the finalizer from the live Application.

**Step 2:** In a single commit:
- Delete `argocd/apps/schnappy.yaml`
- Add 5 new Application manifests (`schnappy.yaml`, `schnappy-data.yaml`, `schnappy-auth.yaml`, `schnappy-observability.yaml`, `schnappy-sonarqube.yaml`)
- Add `cluster-config/schnappy-default-deny.yaml`
- Create 5 values files (`schnappy/values.yaml`, `schnappy-data/values.yaml`, etc.)
- Push to `infra.git`

**What happens:**
1. Root Application syncs
2. Old `schnappy` Application deleted (no finalizer → resources orphaned, not deleted)
3. Five new Applications created
4. Each Application syncs and adopts existing resources (same names, same namespace)
5. `cluster-config` Application syncs and creates the default-deny NP

**Step 3:** Verify all 5 Applications show Healthy + Synced in Argo CD UI at `cd.pmon.dev`.

### Phase 4: Cleanup

1. Remove old monolith chart directory (`helm/_old` or `helm/Chart.yaml` + `helm/templates/` + `helm/values.yaml`)
2. Add `resources-finalizer.argocd.argoproj.io` finalizer to all 5 new Applications
3. Remove old `clusters/production/schnappy/values.yaml` backup if kept
4. Update Vagrant test playbooks to deploy 5 charts instead of 1
5. Update `CLAUDE.md` to document new chart structure

## CD Pipeline Impact

**No changes needed to any CD pipeline.** All 8 repos' `update-infra` steps continue to:
- Clone `infra.git`
- `sed` the image tag in `clusters/production/schnappy/values.yaml` (the core app chart's values file)
- Push

The sed anchors (`# schnappy-monitor`, `# admin-service`, `# chat-service`, `# chess-service`, `# api-gateway`, `# site`, `# game-scp`, `# keycloak-theme`) remain in the core app values file. Only the core app Argo CD Application watches this file, so only app services get resynced on image tag changes.

## Vagrant Test Changes

Current tests deploy the monolithic chart with `helm install schnappy helm/`. After the split:

```bash
helm install schnappy-data helm/schnappy-data -n schnappy --create-namespace
helm install schnappy-auth helm/schnappy-auth -n schnappy
helm install schnappy helm/schnappy -n schnappy
helm install schnappy-observability helm/schnappy-observability -n schnappy
helm install schnappy-sonarqube helm/schnappy-sonarqube -n schnappy
```

Order matters: data first (postgres, kafka needed by app), then auth (keycloak needed by gateway), then core app, then observability and sonarqube (independent).

Update the Taskfile `task test:*` commands and Ansible test playbooks accordingly. Each `task test:*` only deploys the charts it needs (e.g., `task test:elk` only deploys `schnappy-data` + `schnappy-observability`).

## Risks

| Risk | Mitigation |
|---|---|
| Resource recreation on switchover | `nameOverride: schnappy` keeps all names identical; remove finalizer before deleting old Application |
| Network policy gaps during migration | Phase 1 adds `part-of` labels while still in monolith, NPs validated before split |
| Wrong values in wrong file | `helm template` each chart and diff against monolith output pre-switchover |
| Concurrent CD pushes during switchover | Coordinate: pause CD pipelines (disable Woodpecker repos) during Phase 3 |
| Selector label changes on StatefulSets | Explicitly do NOT change `spec.selector.matchLabels` — only pod template labels |
| Argo CD resource tracking conflicts | Verify no resource is claimed by two Applications (each resource has unique GVK+namespace+name) |

## Implementation Order

1. Phase 1: Label preparation (~1h, deploy via normal flow)
2. Phase 2: Chart split (~3h, platform repo restructuring)
3. Phase 3: Switchover (~30min, infra repo commits)
4. Phase 4: Cleanup (~1h, remove old chart, update docs/tests)

Total: ~1 day of focused work, zero downtime if phases are executed in order.
