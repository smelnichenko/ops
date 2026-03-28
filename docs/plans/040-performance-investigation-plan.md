# Plan 040: Performance Investigation — Find and Push the Breaking Point

**Status:** TODO
**Created:** 2026-03-28

## Context

Stress testing at 500 VUs (single k6 pod) achieves 1,300 req/s at 0% errors. Scaling to 4 parallel k6 pods (2000 VUs total) does NOT increase throughput — each pod gets ~325 req/s instead of 1,300. Total throughput is capped at ~1,300 req/s regardless of load generator count.

Node CPU at peak: 18% (3.7 cores of 20). Gateway CPU: 700m. Monitor CPU: 700m. The system is not CPU-bound, not memory-bound, not DB-pool-bound (0 pending connections).

Something is limiting throughput at ~1,300 req/s. This plan identifies and eliminates each bottleneck systematically.

## Investigation Sequence

### Step 1: Identify Where Time is Spent

**Hypothesis:** Most request time is I/O wait, not processing.

**Actions:**
- Enable Spring Boot request tracing on gateway: add `management.tracing.enabled=true` or detailed request logging
- Measure time breakdown per request: DNS lookup, TCP connect, JWT validation, proxy to backend, backend processing, response
- Check gateway Netty event loop thread count: `reactor.netty.ioWorkerCount` defaults to `availableProcessors()` — may be 1 in container
- Check if gateway connections to backends are being pooled or created per-request

**Expected outcome:** Gateway Netty event loop thread count is 1-2, bottlenecking all proxy traffic through one thread.

### Step 2: Gateway Connection Pool Tuning

**Hypothesis:** Gateway creates new connections to backend services per-request instead of pooling.

**Actions:**
- Check Spring Cloud Gateway HttpClient pool settings
- Configure explicit connection pool: `spring.cloud.gateway.httpclient.pool.max-connections`, `max-idle-time`
- Increase Netty worker threads: `reactor.netty.ioWorkerCount` env var or system property

**Expected outcome:** Connection pooling eliminates per-request TCP handshake overhead.

### Step 3: Backend Service Concurrency

**Hypothesis:** Virtual threads handle concurrency well but something blocks.

**Actions:**
- Profile monitor service under load: `async-profiler` or JFR (Java Flight Recorder)
- Check for synchronized blocks, connection pool waits, or lock contention
- Verify HikariCP pool size (20) is adequate — check acquire time percentiles
- Check if Redis operations are blocking (Lettuce is async by default, but some patterns block)

**Expected outcome:** Identify specific code path or resource that serializes under load.

### Step 4: Keycloak Token Endpoint

**Hypothesis:** Token endpoint is a bottleneck — each k6 VU calls it on every iteration.

**Actions:**
- Check k6 script: is token cached or fetched per-iteration?
- Measure Keycloak response time under load via k6 metrics `{name="token"}`
- If uncached: fix k6 script to cache token with TTL
- If cached: check if Keycloak itself is slow (single pod, default resources)

**Expected outcome:** Token caching eliminates redundant Keycloak calls.

### Step 5: Netty Event Loop Sizing

**Hypothesis:** Gateway's Netty event loop is undersized.

**Actions:**
- Check: `reactor.netty.ioWorkerCount` defaults to `Runtime.getRuntime().availableProcessors()` — in a container with `cpu.limit=2`, this returns 2
- Set explicitly: `-Dreactor.netty.ioWorkerCount=8` in gateway javaOpts
- Re-run stress test, compare throughput

**Expected outcome:** More event loop threads = more concurrent proxy operations = higher throughput.

### Step 6: Multiple Gateway Replicas

**Hypothesis:** Single gateway pod is the serialization point.

**Actions:**
- Scale gateway to 2 replicas: `replicas: 2`
- Re-run stress test
- Compare: if throughput doubles, gateway was the bottleneck. If unchanged, bottleneck is downstream.

**Expected outcome:** Throughput increases proportionally with gateway replicas.

### Step 7: Backend Replicas

**Actions:**
- If Step 6 shows downstream bottleneck, scale monitor to 2 replicas
- Check if PostgreSQL becomes the bottleneck (connection pool × replicas)
- Consider read replicas if PG is the limit

## Measurement Protocol

For each step:
1. Run stress test: `kubectl create job --from=cronjob/schnappy-k6-stress`
2. Record: total req/s, p95, error rate, node CPU%, gateway CPU, monitor CPU
3. Compare against baseline (1,300 req/s with single k6 pod)
4. Only proceed to next step if current step didn't resolve the bottleneck

## Current Baseline

| Metric | Value |
|--------|-------|
| Throughput | 1,313 req/s |
| p95 | 1.06s |
| Error rate | 0.00% |
| Node CPU | 18% (3.7 cores) |
| Gateway CPU | 700m |
| Monitor CPU | 700m |
| HikariCP active | 0-5 |
| HikariCP pending | 0 |
