# Plan 046: VictoriaMetrics → Prometheus + Mimir Migration

**Status:** Completed (2026-04-01)

## Context

Replaced VictoriaMetrics (single-binary metrics DB + vmalert) with Prometheus Operator
(CRD-based scraping + alerting) and Grafana Mimir (long-term S3-backed storage via MinIO).

## Architecture

```
App pods (port 8080/metrics)
    ↑ scrape via ServiceMonitor CRDs
Prometheus (15d local retention, kube-prometheus-stack)
    │ remote_write
    ↓
Mimir (monolithic mode, 90d retention)
    │ S3 blocks
    ↓
MinIO (schnappy-minio, existing)

Grafana → queries Mimir (Prometheus-compatible API on :9009/prometheus)
Prometheus → evaluates PrometheusRule CRDs → Alertmanager → webhook
```

## Components

| Component | Before | After |
|-----------|--------|-------|
| Metrics DB | VictoriaMetrics v1.117.1 | Prometheus (kube-prometheus-stack v72.3.0) |
| Long-term storage | VictoriaMetrics PVC (90d) | Grafana Mimir 2.16.0 (MinIO S3, 90d) |
| Alert rules | vmalert (ConfigMap) | PrometheusRule CRDs |
| Scrape config | ConfigMap (static) | ServiceMonitor CRDs |
| Alertmanager | Unchanged | Unchanged |
| Grafana | Datasource: VictoriaMetrics:8428 | Datasource: Mimir:9009/prometheus |
| kube-state-metrics | Unchanged | Unchanged |

## Key Decisions

- **Prometheus in mesh with sidecar** — needed for STRICT mTLS to reach scrape targets and alertmanager
- **Prometheus Operator outside mesh** — no sidecar, needs K8s API access
- **Admission webhooks disabled** — avoided NP/mTLS issues with webhook cert creation
- **Mimir monolithic mode** — single pod with `-target=all`, suitable for single-node cluster
- **Mimir env var expansion** — `--config.expand-env=true` for MinIO credentials from secrets
- **Default-deny NP updated** — added K8s API egress (ports 443/6443) for operator + kube-state-metrics

## Files Changed

### infra repo
- `clusters/production/argocd/apps/prometheus.yaml` — new ArgoCD app
- `clusters/production/prometheus/values.yaml` — kube-prometheus-stack values
- `clusters/production/schnappy-observability/values.yaml` — removed VM, added mimir+prometheus
- `clusters/production/cluster-config/schnappy-default-deny.yaml` — K8s API egress

### platform repo (schnappy-observability)
- Deleted: victoriametrics-{deployment,configmap,rules-configmap,pvc,service}.yaml
- Added: mimir-{deployment,configmap,service,pvc}.yaml
- Added: servicemonitors.yaml, prometheus-rules.yaml
- Modified: grafana-datasources-configmap.yaml, network-policies.yaml, values.yaml, _helpers.tpl

### platform repo (schnappy-mesh)
- service-accounts.yaml — replaced victoriametrics SA with mimir SA
- authorization-policies.yaml — added mimir SA to MinIO policy

## Lessons Learned

- Mimir `ingestion_rate: 0` means disabled, not unlimited — set to 100000
- Mimir ruler data dir and ruler storage dir must not overlap
- `profile: ambient` removed during sidecar migration eliminates HBONE issues
- kube-prometheus-stack admission webhooks need K8s API access — disable in locked-down namespaces
- Prometheus needs sidecar for STRICT mTLS — scraping through sidecar works fine
