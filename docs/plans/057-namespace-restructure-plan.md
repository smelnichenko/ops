# Plan 057: Namespace Restructure + Directory Generator

## Namespaces

| Before | After | Contents |
|--------|-------|----------|
| `schnappy` | `schnappy-production` | App workloads + data stores (monitor, admin, chat, chess, site, game-scp, postgres, kafka, redis, scylla, minio for apps) |
| `schnappy` | `schnappy-infra` | Gateway, MinIO for metrics/traces |
| `schnappy` | via `schnappy-observability` app → `schnappy-infra` | Observability (prometheus, grafana, mimir, tempo, elasticsearch, kibana, fluentbit, alertmanager, kube-state-metrics) |
| `schnappy` | via `schnappy-sonarqube` app → `schnappy-infra` | SonarQube + SonarQube Postgres |
| `schnappy-test` | `schnappy-test` (unchanged) | Test env workloads + data stores |

## Architecture

### Gateway in schnappy-infra
- Gateway is shared infrastructure, not owned by any env
- All envs (prod, test, ephemeral) reference it via external gateway config
- Gateway routes split into:
  - `httproutes-gateway.yaml` in mesh chart: redirect + infra routes (ArgoCD, Woodpecker, Hubble, Forgejo proxy, Keycloak proxy)
  - `httproutes.yaml` in mesh chart: app routes (admin, chat, chess, core, site), only when `gateway.enabled && !gateway.infraOnly`
  - `httproutes-external.yaml` in mesh chart: for envs using external gateway
- Observability routes (Grafana, Kibana, Reports) live in the observability chart
- SonarQube route lives in the sonarqube chart
- Each chart references gateway by configurable `gateway.name` + `gateway.namespace`

### Own MinIO per concern
- `schnappy-infra` has MinIO for mimir-blocks/tempo-traces (via `schnappy-infra-data` directory)
- `schnappy-production` has MinIO for email-attachments/hyperfoil-reports/postgres-backups
- No cross-namespace MinIO dependency

### Cross-env NPs use labels
- `gateway: "true"` label on namespace with gateway
- `environment: <name>` label on env namespaces
- No hardcoded namespace names in cross-env NP selectors

### ApplicationSets: git directory generator
```
clusters/production/schnappy-<env>-data/   → schnappy-data chart, ns=schnappy-<env>
clusters/production/schnappy-<env>-apps/   → schnappy chart, ns=schnappy-<env>
clusters/production/schnappy-<env>-mesh/   → schnappy-mesh chart, ns=schnappy-<env>
```
Auto-discovered. Creating/deleting env = creating/deleting directories.

### Static ArgoCD apps (not directory generator)
- `schnappy-observability` → `schnappy-infra`
- `schnappy-sonarqube` → `schnappy-infra`
- `prometheus` → `schnappy-infra`

## Data recovery

| Component | Recovery | Notes |
|-----------|----------|-------|
| PostgreSQL | CNPG backup from Pi MinIO | `recoveryServerName: schnappy-postgres` |
| ScyllaDB | Schema job + backup from Pi MinIO | Chat messages preserved |
| Kafka | Fresh (Strimzi recreates) | Topics from KafkaTopic CRDs |
| Redis | Fresh (volatile cache) | |
| App MinIO | Fresh | Email attachments lost unless PVC copied |
| Infra MinIO | Fresh | Mimir/Tempo start fresh |
| Elasticsearch | Fresh | Logs regenerated |
| Prometheus/Mimir | Fresh | |
| Grafana | Fresh | Dashboards from ConfigMaps |
| SonarQube | Fresh | Re-scan |

## Cross-namespace dependencies (remaining, all configurable)

| From | To | What | How |
|------|----|------|-----|
| All envs | `schnappy-infra` | Gateway HTTPRoute parentRef | Configurable `gateway.namespace` |
| All envs | `schnappy-infra` | Tempo traces OTLP | Configurable `tempoEndpoint` value |
| `istio-system` | `schnappy-infra` | Zipkin tracing | Configurable in istiod values |
| `schnappy-infra` observability | `schnappy-infra` minio | Mimir/Tempo S3 | Same namespace |
| All envs | `istio-system` | Istio control plane | Built-in, label-based |
| All envs | `kube-system` | DNS, K8s API | Built-in |

## Files modified

### Platform (Helm charts)
- `schnappy-mesh/templates/httproutes-gateway.yaml` — NEW: gateway-level infra routes
- `schnappy-mesh/templates/httproutes.yaml` — app routes only, gated on `!infraOnly`
- `schnappy-mesh/values.yaml` — added `gateway.infraOnly` default
- `schnappy-observability/templates/httproutes.yaml` — NEW: Grafana, Kibana, Reports routes
- `schnappy-observability/values.yaml` — added `gateway` config
- `schnappy-sonarqube/templates/sonarqube-httproute.yaml` — NEW: SonarQube route
- `schnappy-sonarqube/values.yaml` — added `gateway` config
- `schnappy-data/templates/cnpg-cluster.yaml` — configurable `recoveryServerName`
- `schnappy-observability/templates/mimir-configmap.yaml` — configurable MinIO endpoint
- `schnappy-observability/templates/tempo-configmap.yaml` — configurable MinIO endpoint

### Infra (values + ArgoCD)
- `argocd/apps/schnappy-{data,apps,mesh}-envs.yaml` — list → git directory generator
- `argocd/apps/{prometheus,schnappy-observability,schnappy-sonarqube}.yaml` — namespace → `schnappy-infra`
- `schnappy-production-{data,apps,mesh}/values.yaml` — renamed from `schnappy-{data,,mesh}`
- `schnappy-infra-{data,mesh}/values.yaml` — NEW: gateway + MinIO for infra
- `schnappy-observability/values.yaml` — gateway config, MinIO endpoint
- `schnappy-sonarqube/values.yaml` — gateway config
- `cluster-config/` — namespace manifests, NPs (label-based), secrets namespace updates
- `velero/values.yaml` — backup namespace → `schnappy-production`
- `istio/istiod-values.yaml` — tracing endpoint
- `prometheus/values.yaml` — remote write, alerting endpoint

### Ops
- `docs/plans/057-namespace-restructure-plan.md` — this file
