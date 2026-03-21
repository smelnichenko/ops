# Alertmanager Integration

## Context

The monitoring stack has Prometheus collecting metrics but no alerting. We need Alertmanager to send email alerts (via Resend HTTP API) for everything: pod health, resources, app metrics, cert expiry, disk usage, backup failures, Kafka, ELK.

**Key design decision:** Alertmanager sends webhook to a new app backend endpoint (`POST /api/webhooks/alertmanager`), which formats and sends email via Resend API. This reuses existing infrastructure (Resend API key, HTTP client) and avoids deploying a separate translation service.

**Metrics gap:** Current Prometheus only scrapes Spring Boot actuator + Vault. Need kube-state-metrics for pod/container/PVC alerts.

## Files to Create

| File | Purpose |
|------|---------|
| `infra/helm/templates/alertmanager-deployment.yaml` | Alertmanager pod (readOnlyRootFs, non-root) |
| `infra/helm/templates/alertmanager-service.yaml` | ClusterIP :9093 |
| `infra/helm/templates/alertmanager-pvc.yaml` | 1Gi state persistence |
| `infra/helm/templates/alertmanager-configmap.yaml` | alertmanager.yml (webhook → app) |
| `infra/helm/templates/alertmanager-secret.yaml` | Resend API key + webhook secret |
| `infra/helm/templates/prometheus-rules-configmap.yaml` | All alert rules (8 categories) |
| `infra/helm/templates/kube-state-metrics-deployment.yaml` | kube-state-metrics pod |
| `infra/helm/templates/kube-state-metrics-service.yaml` | ClusterIP :8080 |
| `infra/helm/templates/kube-state-metrics-rbac.yaml` | SA + ClusterRole + CRB |
| `backend/src/.../webhook/AlertWebhookController.java` | Webhook endpoint |
| `backend/src/.../webhook/AlertWebhookService.java` | Resend email sender |
| `backend/src/.../webhook/AlertmanagerWebhookProperties.java` | Config props |
| `backend/src/.../webhook/AlertmanagerPayload.java` | DTO |
| `tests/ansible/test-alertmanager.yml` | Vagrant integration test |

## Files to Modify

| File | Change |
|------|--------|
| `infra/helm/values.yaml` | Add `alertmanager` + `kubeStateMetrics` sections |
| `infra/helm/templates/_helpers.tpl` | Add label/selector/service/secret helpers |
| `infra/helm/templates/prometheus-configmap.yaml` | Add alerting section, rule_files, ksm + cert-manager scrape |
| `infra/helm/templates/prometheus-deployment.yaml` | Add rules volume mount |
| `infra/helm/templates/network-policies.yaml` | Add alertmanager + ksm NPs, update prometheus + app NPs |
| `infra/helm/templates/external-secrets.yaml` | Add alertmanager ExternalSecret |
| `backend/src/main/resources/application.yml` | Add alertmanager webhook config |
| `backend/src/.../config/SecurityConfig.java` | Add `/api/webhooks/alertmanager` to public paths |
| `Taskfile.yml` | Add `test:alertmanager` task |

## Implementation Steps

### 1. Helm values + helpers
Add to `values.yaml`:
- `alertmanager.enabled: false` (requires prometheus.enabled)
- `alertmanager.image: prom/alertmanager:v0.28.1`
- `alertmanager.resendApiKey`, `alertEmailTo`, `alertEmailFrom: alerts@pmon.dev`
- `alertmanager.webhookSecret`, `existingSecret`
- `alertmanager.groupWait: 30s`, `groupInterval: 5m`, `repeatInterval: 4h`
- `alertmanager.resources`: 25m/200m CPU, 64Mi/128Mi RAM
- `kubeStateMetrics.enabled: false`, `image: registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0`
- `kubeStateMetrics.resources`: 25m/200m CPU, 64Mi/256Mi RAM

### 2. kube-state-metrics templates
- Deployment: uid 65534, readOnlyRootFs, ports 8080+8081
- Service: ClusterIP :8080
- RBAC: ServiceAccount + ClusterRole (list/watch pods, nodes, namespaces, PVCs, jobs, certs) + ClusterRoleBinding

### 3. Alertmanager templates
- Deployment: uid 65534, readOnlyRootFs, strategy Recreate
  - Config mounted from ConfigMap at `/etc/alertmanager/`
  - Secret mounted at `/etc/alertmanager/secrets/` (for bearer_token_file)
  - Data PVC at `/alertmanager`
- Service: ClusterIP :9093
- PVC: 1Gi
- ConfigMap: alertmanager.yml with webhook receiver → `http://app:8080/api/webhooks/alertmanager`
- Secret: RESEND_API_KEY + ALERTMANAGER_WEBHOOK_SECRET

### 4. Prometheus changes
- Add `alerting:` section pointing to alertmanager:9093
- Add `rule_files: ['/etc/prometheus/rules/*.yml']`
- Add kube-state-metrics scrape target
- Add cert-manager scrape target (port 9402)
- Add rules volume mount to deployment

### 5. Alert rules (prometheus-rules-configmap.yaml)
8 categories:
- **Infrastructure**: PodRestartingFrequently (>3/1h), ContainerOOMKilled, PodCrashLoopBackOff, PodNotReady (10m), Watchdog
- **Resources**: ContainerMemoryHigh (>85% limit), ContainerCPUHigh (>90% limit), PVCUsageHigh (>80%), PVCUsageCritical (>90%)
- **Application**: HighHTTPErrorRate (>5% 5xx), HighRequestLatency (p99>5s), AppDown, HikariPoolExhausted (>80%), JVMHeapHigh (>85%)
- **Kafka**: KafkaBrokerDown (pod not ready)
- **Database**: PostgreSQLDown, DatabaseConnectionPoolExhausted (>90%), DatabaseConnectionsPending (>5), ScyllaDBDown
- **Certificates**: CertExpiringIn30Days, CertExpiringIn7Days
- **Backups**: PostgresBackupFailed, PostgresBackupMissed (>26h)
- **ELK**: ElasticsearchDown, FluentbitDown, KibanaDown

### 6. Network policies
- Alertmanager: ingress from prometheus:9093, egress to app:8080 + DNS
- kube-state-metrics: ingress from prometheus:8080, egress to k8s API (443,6443) + DNS
- Prometheus: add egress to alertmanager:9093, ksm:8080, cert-manager:9402
- App: add ingress from alertmanager:8080

### 7. Backend webhook endpoint
- `POST /api/webhooks/alertmanager` — public, Bearer token auth via shared secret
- Parses Alertmanager webhook payload → formats HTML email → sends via Resend API
- Config: `monitor.alertmanager.enabled`, `webhook-secret`, `email-to`, `email-from`
- Add to SecurityConfig public paths + CSRF/rate-limit exempt

### 8. ExternalSecret
When `vault.secretsEnabled` + `alertmanager.enabled`:
- Vault path: `secret/monitor/alertmanager` (resend_api_key, webhook_secret)

### 9. Vagrant test
- Deploy with alertmanager + prometheus + ksm enabled
- Verify pods healthy, rules loaded, Watchdog fires, webhook reachable

## Resource Budget

| Pod | CPU req/limit | Memory req/limit |
|-----|---------------|------------------|
| Alertmanager | 25m / 200m | 64Mi / 128Mi |
| kube-state-metrics | 25m / 200m | 64Mi / 256Mi |

## Verification

1. `helm lint` passes with alertmanager enabled
2. Vagrant test: all pods Running, rules loaded, Watchdog alert fires
3. Alertmanager receives Watchdog → webhook → app endpoint → Resend API → email delivered
4. Production: enable via helmrelease values, seed Vault secret, verify email
