# Plan 039: Resource Optimization

**Status:** TODO
**Created:** 2026-03-28

## Context

Single-node k3s cluster: 20 logical cores (10 physical + HT), 64GB RAM, NVMe storage. One active user. Current resource allocation is based on production sizing guidelines for multi-user deployments that never materialized.

At idle: total CPU usage ~180m (0.9% of 20 cores), total RAM ~18Gi (28% of 64Gi). Under 50 VU load test: CPU peaks at ~300m, RAM unchanged. Every service is operating at <2% CPU utilization against its limit.

## Current State (measured)

| Service | CPU used | CPU limit | RAM used | RAM limit |
|---------|----------|-----------|----------|-----------|
| sonarqube | 9m | 4000m | 3.8Gi | 10Gi |
| elasticsearch | 14m | 4000m | 3.1Gi | 8Gi |
| kafka | 16m | 4000m | 2.3Gi | 8Gi |
| postgres | 9m | 4000m | 183Mi | 8Gi |
| monitor | 8m | 4000m | 1.2Gi | 4Gi |
| scylla | 27m | 4000m | 292Mi | 4Gi |
| redis | 16m | 1000m | 18Mi | 4Gi |
| chat | 9m | 2000m | 786Mi | 4Gi |
| admin | 7m | 2000m | 707Mi | 4Gi |
| chess | 8m | 2000m | 527Mi | 4Gi |
| keycloak | 5m | 2000m | ~800Mi | 2Gi |
| gateway | 7m | 2000m | 494Mi | 2Gi |
| kibana | 11m | 1000m | 722Mi | 2Gi |
| **Total** | **~180m** | **44000m** | **~18Gi** | **~72Gi** |

CPU overcommit: 220%. Memory overcommit: 112% (can't actually allocate 72Gi from 64Gi if everything hits limits simultaneously).

## Optimization Principles

1. **Requests = expected steady-state usage** — scheduler uses this for placement. Should be close to actual usage with ~50% headroom.
2. **Limits = burst ceiling** — prevents runaway processes. Should allow 2-5x burst over steady state.
3. **JVM services**: heap is the dominant memory consumer. Set `-Xmx` to ~75% of limit so there's room for metaspace, threads, native memory.
4. **Don't over-optimize** — the machine has 20 cores and 64Gi. Saving 100m CPU on a service using 9m is pointless. Focus on memory — that's the finite resource that causes OOMKills.

## Phase 1: Quick Wins (memory savings, no risk)

### Redis: 4Gi → 512Mi limit
Using 18Mi. It's a session cache and chat presence store. Even under heavy load, Redis won't use more than 256Mi on this workload. Save 3.5Gi.

### Postgres: 8Gi → 4Gi limit, reduce shared_buffers
Using 183Mi. The `shared_buffers=4GB` setting pre-allocates 4Gi at startup regardless of usage. For a single-user DB with tiny tables, `shared_buffers=1GB` is more than enough. Save 4Gi + 3Gi from shared_buffers = ~7Gi total system memory freed.

Also reduce `effective_cache_size` proportionally (12GB → 4GB), `maintenance_work_mem` (512MB → 128MB).

### ScyllaDB: 4Gi → 2Gi limit
Using 292Mi. Chat messages table with minimal data. Save 2Gi.

### Site: 2 CPU → 500m limit
Nginx serving static files. 100m would be fine but keep some headroom for gzip compression on slow connections.

## Phase 2: SonarQube Scaling

SonarQube uses 3.8Gi RAM and 9m CPU at idle — it's a JVM app with a large heap that sits idle 99.9% of the time (only active during CI scans). Two options:

### Option A: Scale to zero when not scanning
- Set `replicas: 0` by default
- CI pipeline scales up before scan, scales down after
- Saves 4Gi RAM + 4 CPU limits permanently
- Downside: 30-60s startup time before each scan

### Option B: Reduce JVM heap
- Current: `-Xmx6g` (using 3.8Gi)
- Reduce to `-Xmx2g`, limit to 4Gi
- Saves 6Gi limit capacity
- SQ CE with small codebase (7 projects, <50k LOC total) doesn't need 6Gi

**Recommendation: Option B** — simpler, no CI pipeline changes needed.

## Phase 3: JVM Service Right-sizing

All JVM services (monitor, admin, chat, chess, gateway) have `-Xmx` set much higher than actual heap usage.

| Service | Xmx | Heap used | Proposed Xmx | Proposed limit |
|---------|-----|-----------|-------------|----------------|
| monitor | 3g | ~800Mi | 2g | 3Gi |
| admin | 2g | ~500Mi | 1g | 2Gi |
| chat | 2g | ~500Mi | 1g | 2Gi |
| chess | 2g | ~400Mi | 1g | 2Gi |
| gateway | 1g | ~400Mi | 512m | 1Gi |

These should be validated under load first — run `task test:load` after each change and compare p95/heap on the Load Test dashboard.

## Phase 4: CPU Request Right-sizing

CPU requests affect scheduling and node resource accounting. Current requests total 5.5 cores but actual usage is ~180m. Reduce requests to ~2x actual with headroom for bursts:

| Service | Current req | Proposed req |
|---------|-------------|-------------|
| postgres | 1000m | 250m |
| kafka | 1000m | 250m |
| monitor | 500m | 200m |
| scylla | 500m | 200m |
| elasticsearch | 500m | 250m |
| sonarqube | 500m | 200m |
| keycloak | 500m | 200m |
| gateway | 500m | 200m |
| admin | 250m | 100m |
| chat | 250m | 100m |
| chess | 250m | 100m |
| prometheus | 250m | 100m |

Leave CPU limits as-is — they're burst ceilings and don't consume resources unless used.

## Phase 5: Elasticsearch Tuning

Using 3.1Gi of 8Gi limit. JVM heap is 2Gi (`-Xms2g -Xmx2g`), rest is Lucene file cache. For a log aggregation use case (podlogs, 30-day retention):

- Reduce limit to 4Gi (2Gi heap + 2Gi file cache)
- Current heap is fine for the index sizes (~2Gi total across all indices)
- Save 4Gi limit

## Expected Results

| Phase | Memory saved (limits) | Notes |
|-------|----------------------|-------|
| 1 | ~12Gi | Redis, Postgres, ScyllaDB, Site |
| 2 | ~6Gi | SonarQube heap reduction |
| 3 | ~7Gi | JVM service right-sizing |
| 4 | ~3 cores requests | Better scheduling headroom |
| 5 | ~4Gi | Elasticsearch |
| **Total** | **~29Gi limits freed** | From 72Gi → 43Gi (67% of RAM) |

## Validation

Each phase should be validated by:
1. Apply changes
2. Wait 10min for services to stabilize
3. Run `task test:load` (50 VUs, 6min)
4. Check Load Test dashboard — p95 should stay under 30ms
5. Check Infrastructure dashboard — no OOMKills, no restart spikes
6. Monitor for 24h before next phase

## Files to Change

| File | Changes |
|------|---------|
| `infra/clusters/production/schnappy/values.yaml` | App service resources, javaOpts |
| `infra/clusters/production/schnappy-data/values.yaml` | Postgres, Redis, Kafka, ScyllaDB resources + PG args |
| `infra/clusters/production/schnappy-observability/values.yaml` | ES, Prometheus resources |
| `infra/clusters/production/schnappy-sonarqube/values.yaml` | SonarQube heap + resources |
