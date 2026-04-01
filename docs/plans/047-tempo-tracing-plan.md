# Plan 047: Grafana Tempo + Distributed Tracing + Exemplars

## Context

The Schnappy platform has metrics (Prometheus -> Mimir -> Grafana) and logs (Fluent Bit -> Elasticsearch -> Kibana) but zero distributed tracing. This plan adds the third observability pillar: traces via Grafana Tempo, with Grafana's Traces Drilldown view, and exemplars linking metrics to traces.

**Current state:** No tracing backend, no OTEL instrumentation, no trace dependencies in any service, no Istio tracing config. Spring Boot 4.0.3 has built-in Micrometer Tracing support but no tracing bridge dependency is present.

**Goal:** Click a metric exemplar dot -> jump to the trace. Click a trace -> see correlated spans from both app and Envoy sidecar. Use Grafana's Traces Drilldown to explore all traces.

## Architecture

```
Spring Boot apps (monitor, admin, chat, chess)
    | OTLP/gRPC (micrometer-tracing-bridge-otel)
    v
Grafana Tempo (monolithic, MinIO S3)  <-- Istio Envoy proxies (Zipkin protocol)
    |
    v
Grafana (Tempo datasource + exemplars on Mimir datasource)

Exemplar flow:
App metrics (with trace_id exemplar) -> Prometheus -> Mimir -> Grafana exemplar dots
```

## Phases

### Phase 1: Tempo Backend (schnappy-observability chart)

Deploy Tempo in monolithic mode using MinIO S3 (same as Mimir).

New files in `platform/helm/schnappy-observability/templates/`:
- `tempo-configmap.yaml` -- Tempo config: monolithic mode, OTLP gRPC receiver (:4317), Zipkin receiver (:9411), S3 backend on existing MinIO, WAL at `/data/wal`, 72h retention
- `tempo-deployment.yaml` -- Single replica, init container to create MinIO bucket, volumes: config + PVC + tmp
- `tempo-service.yaml` -- Ports: 3200 (HTTP API for Grafana), 4317 (OTLP gRPC for apps), 9411 (Zipkin for Istio)
- `tempo-pvc.yaml` -- 2Gi local-path for WAL
- `tempo-serviceaccount.yaml`

Tempo config key points:
- `server.http_listen_port: 3200`
- `distributor.receivers.otlp.protocols.grpc.endpoint: 0.0.0.0:4317`
- `distributor.receivers.zipkin.endpoint: 0.0.0.0:9411`
- `storage.trace.backend: s3` (reuse MinIO credentials from existing secret)
- `storage.trace.s3.bucket: tempo-traces`
- `metrics_generator.storage.remote_write` -> Mimir (generates span metrics for service graph)

### Phase 2: Grafana Datasources + Exemplars

- Update Mimir datasource: add `exemplarTraceIdDestinations` linking `trace_id` -> Tempo datasource
- Add Tempo datasource: `type: tempo`, `uid: tempo`, `url: http://schnappy-tempo:3200`
- Enable `tracesToMetrics`, `serviceMap`, `nodeGraph` on Tempo datasource
- Add `enableFeatures: [exemplar-storage]` to Prometheus values

### Phase 3: App Instrumentation

Add dependencies to each service's build.gradle:
```gradle
implementation 'io.micrometer:micrometer-tracing-bridge-otel'
implementation 'io.opentelemetry:opentelemetry-exporter-otlp'
```

Spring Boot 4.0.3 auto-configures everything when these are on classpath. No code changes needed.

Add env vars to deployment templates:
```yaml
- name: MANAGEMENT_TRACING_SAMPLING_PROBABILITY
  value: "0.1"
- name: MANAGEMENT_OTLP_TRACING_ENDPOINT
  value: "http://schnappy-tempo.schnappy.svc:4317"
- name: SPRING_APPLICATION_NAME
  value: "<service-name>"
```

### Phase 4: Istio Envoy Tracing

Configure Istio meshConfig to send Envoy proxy spans to Tempo's Zipkin endpoint:
```yaml
meshConfig:
  defaultConfig:
    tracing:
      zipkin:
        address: schnappy-tempo.schnappy.svc:9411
      sampling: 10.0
  enableTracing: true
```

Requires rolling restart of all sidecar-injected pods. Do this last.

### Phase 5: Network Policies

- All schnappy pods -> Tempo :4317 (OTLP) and :9411 (Zipkin)
- Grafana -> Tempo :3200 (HTTP API)
- Tempo -> MinIO :9000 (S3 storage)
- Tempo -> Mimir :9009 (metrics_generator remote_write)

### Phase 6: Production Values

Enable Tempo and tracing in production values files.

## Execution Order

1. Phase 1 + 5 -- Tempo templates + network policies (platform chart)
2. Phase 2 -- Grafana datasources + Prometheus exemplar feature
3. Phase 6 -- Production values (infra repo) -> ArgoCD deploys Tempo
4. Phase 3 -- App dependencies + deployment env vars -> requires CI rebuild
5. Phase 4 -- Istio meshConfig (last -- triggers pod restarts)

## Verification

1. `kubectl get pods -n schnappy | grep tempo` -- Tempo running
2. Grafana -> Explore -> Select "Tempo" datasource -> Traces Drilldown shows search UI
3. Make HTTP requests to the app -> traces appear in Tempo
4. Grafana -> Application dashboard -> hover metric graph -> exemplar dots visible with trace_id
5. Click exemplar -> jumps to trace in Tempo
6. Envoy spans and app spans appear in the same trace (correlated via W3C traceparent)
7. Service graph visible in Grafana (from Tempo's metrics_generator)
