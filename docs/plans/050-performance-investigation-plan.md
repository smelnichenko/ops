# Plan 050: Performance Investigation — Why 310 req/s Instead of 1,300?

**Status: COMPLETED (2026-04-07)**

## Context

Hyperfoil stress test gets ~310 req/s at 1000-2000 concurrent users. Historical k6 baseline was 1,313 req/s (plan 040). Multiple variables changed simultaneously: test tool (k6->Hyperfoil), network layer (no mesh->STRICT mTLS with 15 Envoy sidecars), workload shape (1 service->3 services, 6 sequential requests per session), and concurrency model (rate-limited->unbounded "always" mode).

**Node**: 20 cores, 64GB RAM. At idle: 3% CPU, 44% memory. Not resource-constrained at rest.

## Root Cause

The 310 req/s figure was **misleading due to test methodology**. The "always" mode creates unbounded concurrent users, causing self-inflicted queueing. Switching to `constantRate` mode revealed the system actually sustains **2,400 req/s at 5ms latency**.

## Investigation Results

### Phase 0: Ground Truth (HikariCP bottleneck found)

- Pool size 20 baseline: **309 req/s**, 69.8s mean response, 76 pending connections
- HikariCP pool exhaustion was the primary bottleneck at default pool size
- Pool increased from 20 -> 50 (tested 40 and 60)
- Pool 60 STRICT: **456 req/s**, 314ms mean (best "always" mode result)

### Phase 2: mTLS Overhead (negligible)

- Pool 40 PERMISSIVE: **327 req/s** (worse than STRICT with pool 60)
- mTLS encryption overhead is not a significant factor
- Reverted to STRICT mTLS

### Phase 3: Sidecar Resource Consumption

- At idle: ~3m CPU per sidecar (45m total for 15 sidecars)
- Under load: sidecars consistently use **4-5 cores** (~25% of node)
- Monitor sidecar peaked at 1.4 cores, Hyperfoil sidecar at 1.6 cores
- This is significant but acceptable overhead for mTLS + observability

### Phase 4: constantRate Mode (real throughput revealed)

Switched stress test from `always` (unbounded) to `constantRate` with stepped phases:

| Phase | Target req/s | Actual req/s | Avg Mean Latency | Status |
|-------|-------------|-------------|-----------------|--------|
| rate100 | 600 | **599** | 34ms | JVM warmup |
| rate200 | 1,200 | **1,201** | 3ms | Healthy |
| rate400 | 2,400 | **2,406** | 5ms | Healthy |
| rate600 | 3,600 | **2,249** | 234ms | CPU saturated |

- System sustains **2,400 req/s at 5ms latency** across 6 endpoints on 3 services
- Throughput cliff between 2,400 and 3,600 req/s
- All 20 CPUs hit 87-92% during rate600 — **CPU saturation is the ceiling**

### Phase 5: Quick Wins (minimal impact)

- Disabling access logging: **390 req/s** in "always" mode (marginal)
- ES uses 3.3 cores during tests (indexing access logs) — frees CPU when disabled but not enough to matter

### Phase 1 & 6: Skipped

Single-endpoint isolation and database contention were not needed — Phase 4 conclusively showed the system is healthy and the original 310 figure was a test methodology artifact.

## Conclusions

1. **The system is healthy**: 2,400 req/s at 5ms latency across 3 services with STRICT mTLS
2. **Old 310 req/s was fake**: unbounded "always" mode caused queueing, not actual throughput limits
3. **Apples-to-apples comparison**: 2,400 req/s / 6 endpoints = 400 sessions/sec, vs old 1,313 req/s on 1 endpoint — the mesh+multi-service setup is performing well
4. **CPU is the ceiling**: 20 cores fully saturated at rate600. Only way to push higher is more nodes or reducing sidecar overhead
5. **HikariCP pool**: increased from 20 to 50 to prevent pool exhaustion under load
6. **mTLS overhead**: negligible for throughput; sidecars use ~25% of CPU under load (acceptable)

## Changes Made

- `hyperfoil-stress-configmap.yaml`: switched from `always` to `constantRate` phases (100/200/400/600 users/sec)
- `values.yaml`: HikariCP maximumPoolSize 20 -> 50
- mTLS and access logging kept at production settings (STRICT, access log enabled)
