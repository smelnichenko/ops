# Plan 050: Performance Investigation — Why 310 req/s Instead of 1,300?

## Context

Hyperfoil stress test gets ~310 req/s at 1000-2000 concurrent users. Historical k6 baseline was 1,313 req/s (plan 040). Multiple variables changed simultaneously: test tool (k6→Hyperfoil), network layer (no mesh→STRICT mTLS with 15 Envoy sidecars), workload shape (1 service→3 services, 6 sequential requests per session), and concurrency model (rate-limited→unbounded "always" mode).

**Node**: 20 cores, 64GB RAM. At idle: 3% CPU, 44% memory. Not resource-constrained at rest.

**Key insight**: The old 1,313 req/s was likely single-endpoint. New test does 6 requests per user session across 3 services through mTLS sidecars. Apples-to-apples: 1313 / 6 / ~1.3x mesh overhead ≈ 168 req/s per "session", making 310 req/s actually **better** than expected. But we should verify this and find the real ceiling.

## Investigation Sequence

### Phase 0: Ground Truth (baseline with resource monitoring)

Run stress test while capturing per-pod CPU (app + sidecar separately), HikariCP metrics, and Envoy stats.

```bash
# During stress test, capture every 30s:
kubectl top pods -n schnappy --containers | sort -k3 -rn > /tmp/stress-top-$(date +%s).txt

# HikariCP metrics:
MONITOR_IP=$(kubectl get svc schnappy-monitor -n schnappy -o jsonpath='{.spec.clusterIP}')
curl -s http://${MONITOR_IP}:8080/api/actuator/prometheus | grep hikari

# Envoy connection stats on monitor sidecar:
kubectl exec deploy/schnappy-monitor -n schnappy -c istio-proxy -- curl -s localhost:15000/stats | grep -E 'downstream_cx_active|upstream_cx_active|downstream_rq'
```

**Record**: req/s per phase, p50/p99, peak CPU per pod+sidecar, HikariCP pending, Envoy active connections.

### Phase 1: Single-Endpoint Throughput

Create a minimal benchmark hitting only `/api/health` on monitor with same concurrency levels. This isolates infrastructure capacity from workload complexity.

**File**: `hyperfoil-stress-configmap.yaml` — temporary single-endpoint variant

**Pass**: If single-endpoint gets >1000 req/s → workload shape is the bottleneck, not infrastructure.
**Fail**: If still ~300 req/s → infrastructure/sidecar issue.

### Phase 2: Quantify Istio Sidecar Overhead

**Step 2a**: Switch PeerAuthentication to PERMISSIVE (keeps sidecars, skips encryption).
**Step 2b**: Disable sidecars on monitor/chat/chess temporarily (`sidecar.istio.io/inject: "false"`).

Compare throughput: STRICT vs PERMISSIVE vs no-sidecar.

**Pass**: >30% improvement with PERMISSIVE or no-sidecar → mesh overhead is significant.

### Phase 3: Envoy Resource Consumption Under Load

During stress test, measure sidecar CPU. At idle they use ~3m each (45m total). Under 2000 users with 6 requests/session through 2 proxies per hop, sidecar CPU could spike to several cores.

Set sidecar limits if needed:
```yaml
# Pod annotations:
sidecar.istio.io/proxyCPU: "100m"
sidecar.istio.io/proxyCPULimit: "1000m"
```

### Phase 4: Hyperfoil "always" Mode vs constantRate

Replace `always` phases with `constantRate` to find the actual sustainable throughput:

```yaml
phases:
  - steady200:
      constantRate:
        usersPerSec: 200
        duration: 120s
        maxSessions: 500
        scenario: *scenario
```

200 users/sec × 6 requests = 1,200 req/s target. If latencies stay flat, the system handles 1,200 req/s and "always" mode was causing self-inflicted queueing.

### Phase 5: Quick Wins to Test

- Disable Envoy access logging (`accessLogFile: ""`) during stress
- Disable tracing sampling (`sampling: 0`) during stress  
- Scale down non-essential pods (ES, Kibana, Mimir, Tempo, Grafana) to free resources

### Phase 6: Database Contention

Check HikariCP pool exhaustion and PostgreSQL query performance during load:

```bash
kubectl exec -it $(kubectl get pod -n schnappy -l app.kubernetes.io/component=postgres -o name) \
  -n schnappy -c postgres -- psql -U postgres -c \
  "SELECT datname, numbackends FROM pg_stat_database WHERE datname LIKE 'monitor%';"
```

## Decision Tree

```
Phase 0 (ground truth) → Phase 1 (single endpoint)
  ├─ >1000 req/s → workload shape is the cause → Phase 4 (constantRate)
  └─ ~300 req/s  → infrastructure issue → Phase 2 (mTLS)
       ├─ >30% improvement → mesh overhead → Phase 3 (sidecar limits) + Phase 5 (quick wins)
       └─ no improvement → Phase 6 (database)
```

## Critical Files

- `/home/sm/src/platform/helm/schnappy/templates/hyperfoil-stress-configmap.yaml` — stress test benchmark
- `/home/sm/src/platform/helm/schnappy-mesh/templates/peer-authentication.yaml` — mTLS mode
- `/home/sm/src/infra/clusters/production/schnappy-mesh/values.yaml` — mesh values
- `/home/sm/src/platform/helm/schnappy/templates/app-deployment.yaml` — monitor resources
- `/home/sm/src/monitor/src/main/resources/application.yml` — HikariCP config

## Verification

After each phase, run the same Hyperfoil stress test and compare req/s, p50, p99 against Phase 0 baseline. Changes that don't improve throughput by >10% are not worth keeping.
