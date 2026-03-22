# Grafana Dashboard Expansion

## Context

Current dashboard ("Web Page Monitor") only has 7 panels covering page monitor metrics. The system now has Prometheus scraping the app, kube-state-metrics, and Vault — but Grafana only visualizes page checks. Need comprehensive dashboards for the full stack.

## Approach

Replace the single dashboard with multiple dashboards organized by domain. All dashboards provisioned via the existing ConfigMap pattern.

## Dashboard 1: Application Overview (home dashboard)

**Row 1: Health at a Glance** (stat panels)
- Pod count (Running vs Total) — `kube_pod_status_ready{namespace="monitor"}`
- Active alerts count — `ALERTS{alertstate="firing"}`
- HTTP request rate — `rate(http_server_requests_seconds_count[5m])`
- HTTP error rate (5xx %) — `rate(...{status=~"5.."}[5m]) / rate(...[5m])`
- Avg response time — `rate(http_server_requests_seconds_sum[5m]) / rate(http_server_requests_seconds_count[5m])`

**Row 2: HTTP Traffic**
- Request rate by endpoint (timeseries) — `rate(http_server_requests_seconds_count[5m])` by `uri`
- Response time percentiles (timeseries) — `histogram_quantile(0.95/0.50, rate(http_server_requests_seconds_bucket[5m]))`
- Status code distribution (pie) — `increase(http_server_requests_seconds_count[1h])` by `status`

**Row 3: JVM**
- Heap usage (timeseries) — `jvm_memory_used_bytes{area="heap"}` vs `jvm_memory_max_bytes`
- GC pause time (timeseries) — `rate(jvm_gc_pause_seconds_sum[5m])`
- Thread count (stat) — `jvm_threads_live_threads`
- CPU usage (timeseries) — `process_cpu_usage`

**Row 4: Database (HikariCP)**
- Active connections (gauge) — `hikaricp_connections_active`
- Idle connections — `hikaricp_connections_idle`
- Pending connections — `hikaricp_connections_pending`
- Connection acquire time — `rate(hikaricp_connections_acquire_seconds_sum[5m])`

## Dashboard 2: Page & RSS Monitors

Keep existing 7 panels + add RSS section:

**Row: RSS Feeds**
- RSS check rate — `rate(rss_check_total[5m])` by `feed`
- RSS check duration — `histogram_quantile(0.95, rate(rss_check_duration_seconds_bucket[5m]))`
- RSS success rate — `rss_check_total{success="true"}` / `rss_check_total`

## Dashboard 3: Infrastructure

**Row 1: Pods**
- Pod status table — `kube_pod_status_ready`, `kube_pod_container_status_restarts_total`
- Pod restarts (timeseries) — `increase(kube_pod_container_status_restarts_total{namespace="monitor"}[1h])`
- Container memory usage vs limits — `container_memory_working_set_bytes / kube_pod_container_resource_limits{resource="memory"}`
- Container CPU usage vs limits — `rate(container_cpu_usage_seconds_total[5m]) / kube_pod_container_resource_limits{resource="cpu"}`

**Row 2: Storage**
- PVC usage (bar gauge) — `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes`

**Row 3: Kafka**
- Kafka broker status — `kube_pod_status_ready{pod=~".*kafka.*"}`

**Row 4: Alerts**
- Firing alerts table — `ALERTS{alertstate="firing"}`

## Files to Modify

| File | Change |
|------|--------|
| `infra/grafana/dashboards/monitor-dashboard.json` | Rename to application overview, add HTTP/JVM/DB rows |
| `infra/grafana/dashboards/monitors-dashboard.json` | NEW: page + RSS monitor panels |
| `infra/grafana/dashboards/infrastructure-dashboard.json` | NEW: pods, storage, kafka, alerts |
| `infra/helm/templates/grafana-dashboards-configmap.yaml` | Add new dashboard files |

## Verification

1. `helm lint` passes
2. Grafana loads all 3 dashboards
3. Panels show data from Prometheus
