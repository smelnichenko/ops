# Plan 051: Performance Optimization — Push Beyond 2,400 req/s

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

### 3. Cap ES CPU limit (~1.5 cores freed under load)

ES uses 3.3 cores under load (indexing access logs). It has a 4-core limit. Cap it to prevent it stealing CPU from app services during stress.

### 4. Use virtual threads for HTTP clients in monitor (minor, reduces thread contention)

Two HTTP clients use `Executors.newFixedThreadPool(10)` instead of virtual threads. With virtual threads enabled for the rest of the app, these are inconsistent and waste platform threads.

### 5. HikariCP pool size alignment

The app config in `application.yml` has `maximum-pool-size: 25` but Helm configmap overrides it to 50. Remove from application.yml to make the Helm value the single source of truth.

## What NOT to do

- **Don't switch ZGC → G1GC**: ZGC is correct for low-latency request serving
- **Don't disable access logging globally**: Needed for observability. The ES CPU cap handles the cost
- **Don't change CPU requests**: Current low requests allow flexible scheduling on single-node
- **Don't remove Tomcat thread config**: Virtual threads handle this already

## Estimated Impact

| Optimization | CPU Freed | Confidence |
|-------------|-----------|------------|
| Remove 8 unnecessary sidecars | ~1.5 cores | High |
| Reduce tracing 10% → 1% | ~0.5 cores | Medium |
| Cap ES CPU 4000m → 2000m | ~1.5 cores | High |
| Virtual thread HTTP clients | ~0.2 cores | Low |
| **Total** | **~3.7 cores** | |

With 3.7 cores freed, estimated new ceiling: **~3,200-3,500 req/s** (from 2,400).

## Verification

1. Apply all changes, wait for ArgoCD sync
2. Verify removed sidecars
3. Run Hyperfoil stress test (same constantRate config: 100/200/400/600)
4. Compare per-phase req/s and latency against Plan 050 baseline
5. Check `kubectl top pods --containers` during rate600 — total sidecar CPU should drop from ~4.5 to ~3 cores
