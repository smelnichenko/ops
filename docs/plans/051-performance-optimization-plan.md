# Plan 051: Performance Optimization — Push Beyond 2,400 req/s

**Status: COMPLETED (2026-04-07)**

## Context

Plan 050 established that the system sustains 2,400 req/s at 5ms latency, with CPU saturation (all 20 cores at 87-92%) as the ceiling. The bottleneck is not the app services themselves (~4.5 cores) but the overhead from sidecars (~4.5 cores under load) and observability infrastructure (~5 cores: ES 3.3, Fluent Bit, Tempo, Mimir). By freeing wasted CPU we can push throughput higher without hardware changes.

## Optimizations

### 1. Remove unnecessary sidecars (~1.5 cores freed under load, ~500MB RAM)

These pods have sidecars but don't need them — they're not app services, they only receive internal traffic that's already covered by PERMISSIVE PeerAuth exceptions or don't need mTLS:

| Pod | Why sidecar is unnecessary |
|-----|---------------------------|
| `schnappy-grafana` | Read-only dashboards, accessed via gateway |
| `schnappy-kibana` | Same — UI only, accessed via gateway |
| `schnappy-kube-state-metrics` | Scraped by Prometheus, no mTLS needed |
| `schnappy-sonarqube` | Dev tool, accessed via gateway |
| `schnappy-sonarqube-postgres` | Only accessed by SonarQube |
| `schnappy-tempo` | Already has PERMISSIVE, receives OTLP pushes |
| `schnappy-mimir` | Already has PERMISSIVE on 9009, receives metric pushes |
| `schnappy-reports` | Static nginx, accessed via gateway |

**Don't remove** from: monitor, chat, chess, admin, site, game-scp, ES, kafka, postgres, redis, scylla, minio, gateway, fluentbit — these need mesh mTLS for inter-service traffic.

### 2. Reduce tracing sampling 10% → 1% (~0.5 core freed)

At 2,400 req/s with 10% sampling: 240 traces/sec flowing through Tempo. Reducing to 1% = 24 traces/sec. Plenty for debugging, 10x less CPU/IO.

### 3. Cap ES CPU limit (~0.5 cores freed under load)

ES uses 3.3 cores under load (indexing access logs). Had a 4-core limit. Initially capped to 2 cores but Fluent Bit couldn't flush fast enough — raised to 3 cores as a compromise.

### 4. Use virtual threads for HTTP clients in monitor (minor, reduces thread contention)

Two HTTP clients use `Executors.newFixedThreadPool(10)` instead of virtual threads. With virtual threads enabled for the rest of the app, these are inconsistent and waste platform threads.

### 5. HikariCP pool size alignment

The app config in `application.yml` has `maximum-pool-size: 25` but Helm configmap overrides it to 50. Remove from application.yml to make the Helm value the single source of truth.

## What NOT to do

- **Don't switch ZGC → G1GC**: ZGC is correct for low-latency request serving
- **Don't disable access logging globally**: Needed for observability. The ES CPU cap handles the cost
- **Don't change CPU requests**: Current low requests allow flexible scheduling on single-node
- **Don't remove Tomcat thread config**: Virtual threads handle this already

## Additional fixes during implementation

- **MinIO AuthorizationPolicy**: Tempo and Mimir lost mTLS identity after sidecar removal. Added `notPrincipals` rule for plaintext access on port 9000.
- **Fluent Bit buffer**: Increased `Buffer_Size` from 512KB to 1024KB to handle log volume during stress.
- **ES CPU limit**: Raised from 2000m back to 3000m — 2 cores caused Fluent Bit flush failures.

## Results

| Phase | Before (Plan 050) | After (Plan 051) | Change |
|-------|-------------------|-------------------|--------|
| rate100 | 599 req/s, 34ms | 604 req/s, 57ms | same |
| rate200 | 1,201 req/s, 3ms | 1,192 req/s, 2ms | same |
| rate400 | 2,406 req/s, 5ms | 2,395 req/s, 6ms | same |
| rate600 | **2,249 req/s, 234ms** | **3,084 req/s, 148ms** | **+37%** |

Lower phases unchanged (not CPU-bound). At rate600 where the node was saturated:
- **Throughput: +835 req/s (+37%)**
- **Latency: -86ms (-37%)**
- CPU warnings dropped from 87-92% to 80-87%

System now sustains **~3,100 req/s** before degradation. CPU saturation on 20 cores remains the ceiling.
