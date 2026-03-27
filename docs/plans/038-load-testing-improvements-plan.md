# Plan 038: Load Testing Improvements

**Status:** TODO
**Created:** 2026-03-27

## Current State

Three k6 scripts in `ops/tests/k6/` — load, stress, spike — run manually via `task test:load*`. All hit unauthenticated endpoints only (`/api/monitor/pages`, `/api/monitor/results`, `/api/actuator/health`). No authentication, no think-times in most scripts, no monitoring integration, no CI automation, no baselines, no failure mode testing. The error rate threshold is 10-30% — far too permissive. Thresholds have no resource-level criteria (heap, connections, CPU).

Separately, the k6 smoke test (PostSync + daily CronJob) covers endpoint availability but not sustained load.

## Problems to Solve

1. **No acceptance criteria** — "p(95)<500ms" is set but arbitrary. No throughput target, no max-user goal, no resource saturation limits. Tests pass/fail but don't answer "can we handle X users?"
2. **Unrealistic traffic** — Scripts hammer 2-3 endpoints with no auth, no session flow, no think-times. Real users browse multiple pages with pauses. A test that spams `/api/monitor/results` with 200 VUs tells you nothing about real capacity.
3. **No visibility during tests** — Response times are collected but JVM heap, GC pauses, DB pool saturation, Kafka lag, and CPU aren't correlated. The bottleneck could be the connection pool exhausting at 80 VUs but you'd never see it.
4. **No baselines or history** — Each run is standalone. No way to detect a 30% regression between releases without manually comparing terminal output.
5. **Not automated** — Manual-only means tests run rarely and regressions ship.
6. **Only happy path** — No testing of degraded dependencies. A slow PostgreSQL query or an unavailable Kafka broker could cascade into user-facing failures that never get caught.

## Phases

### Phase 1: Define SLOs and Rewrite Scenarios

Rewrite all three k6 scripts against concrete targets.

**SLOs:**
- p95 < 300ms, p99 < 1s for read endpoints
- p95 < 500ms, p99 < 2s for write endpoints (manual check triggers, config updates)
- Error rate < 0.1% under normal load, < 1% under stress
- Sustained throughput: 50 rps at 50 VUs without degradation

**Resource ceilings (checked via Prometheus queries in handleSummary):**
- JVM heap < 85% of max
- HikariCP active connections < 80% of pool max (16 of 20)
- HikariCP pending connections = 0
- No connection timeouts

**Scenario rewrite:**
- Authenticate via Keycloak service account (reuse k6-smoke client or create k6-load client)
- Model user session: health → dashboard (pages list) → page detail (results) → RSS feeds → RSS detail → chat channels → config — with 1-3s think-time between steps
- 80/20 read/write split: most iterations read-only, 1 in 5 triggers a manual check or updates config
- Multiple test users (parameterized from CSV or env) to avoid caching on a single user ID
- Tag each request with `group` for clean Grafana breakdown

**Scripts:**
- `load-test.js` — ramp 0→50 VUs over 1m, sustain 5m, ramp down 1m. Validates SLOs.
- `stress-test.js` — ramp 0→50→100→200→300 VUs in steps. Finds the breaking point. Relaxed thresholds.
- `spike-test.js` — 10 VUs steady, spike to 150 for 2m, drop back. Tests recovery time.
- `soak-test.js` (new) — 30 VUs for 30m. Detects memory leaks, connection pool exhaustion, GC pressure over time.

### Phase 2: Monitoring Integration

- All scripts use `--out experimental-prometheus-rw` with native histograms (already configured for smoke tests)
- Create Grafana "Load Test" dashboard combining:
  - k6 metrics: VUs, request rate, p95/p99 duration, error rate, checks pass rate
  - JVM: heap used vs max, GC pause duration, live threads
  - HikariCP: active/idle/pending/max connections, acquire time
  - System: pod CPU/memory usage
  - Kafka: consumer group lag (if chat scenarios included)
- Grafana annotations marking test start/end for correlation with other dashboards
- k6 `handleSummary()` exports JSON summary to `/tmp/k6-results/` for archival

### Phase 3: Baselines and Regression Detection

- Run load-test once in current state → save as `baseline-YYYYMMDD.json`
- Store baselines in `ops/tests/k6/baselines/`
- `handleSummary()` compares current p95/p99/throughput/error-rate against baseline
- Flag regressions > 20% in console output
- Historical results visible in Grafana (k6 metrics in Prometheus have timestamps)

### Phase 4: CI Automation

- **PostSync light load** (new CronJob or extend smoke test): 10 VUs, 30s after every deploy. Validates the system handles concurrent users, not just single requests. Separate from smoke test (which checks endpoint existence).
- **Nightly load test**: CronJob at 3 AM UTC, runs `load-test.js` (50 VUs, 5m). Results in Prometheus. Threshold failures → k6 exit code 99 → Job status Failed → PodRestartingFrequently alert catches it next morning.
- **Weekly stress test**: CronJob Sunday 4 AM, runs `stress-test.js`. Informational — doesn't fail on threshold breach, but results are visible in Grafana.
- All CI tests use the k6 image already used for smoke tests. ConfigMap for scripts, ExternalSecret for Keycloak client credentials.

### Phase 5: Failure Mode Testing (Vagrant)

Automated via `task test:failure-modes` — Ansible playbook in Vagrant, same pattern as `test:dr`, `test:elk`, `test:kafka-scylla`. Safe to run destructive tests because the Vagrant cluster is disposable.

**Vagrant test structure (`tests/ansible/test-failure-modes.yml`):**

The playbook deploys the full stack in Vagrant, seeds test data, then runs each failure scenario as a suite. k6 runs on the host against the Vagrant cluster's NodePort. Each suite:
1. Starts a k6 load test in background (30 VUs, 2min)
2. Injects the failure mid-test
3. Waits for recovery
4. Asserts k6 exit code and checks Prometheus metrics

**Suites:**

- **Suite 1 — Pod failure recovery:** Kill `schnappy-monitor` pod during load. Assert: requests fail < 30s, new pod starts, k6 error rate < 5% overall, all requests succeed after recovery.
- **Suite 2 — Database connection exhaustion:** Patch HikariCP to `maximum-pool-size=3`, run 30 VUs. Assert: pending connections spike, no connection timeout errors (requests queue rather than fail), p99 increases but errors stay < 1%.
- **Suite 3 — Kafka outage isolation:** Scale Kafka to 0 replicas during load. Assert: chat endpoints return 503, all other endpoints (monitors, RSS, admin, inbox) continue at < 500ms p95, error rate for non-chat < 0.1%.
- **Suite 4 — Memory pressure:** Set `JAVA_OPTS=-Xmx256m`, run 20 VUs for 3min. Assert: GC pause frequency increases, p95 degrades but no OOMKilled, app stays responsive.
- **Suite 5 — Rate limiting:** Run 50 VUs from single source IP. Assert: first 300 requests/min succeed (200), subsequent requests get 429, no 500 errors, rate limit resets after 1 minute.
- **Suite 6 — Slow database:** Inject 2s latency on PostgreSQL via `pg_sleep` in a test trigger or tc netem on the postgres pod network. Assert: response times increase proportionally, connection pool doesn't exhaust, no cascading failures to other services.

**Pass criteria:** All 6 suites pass. Any suite failure fails the Vagrant test.

## Implementation Order

Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5

Phase 1 is the most impactful — realistic scenarios with real thresholds replace the current toy tests. Phase 2 gives visibility into why things break. Phase 3 catches regressions. Phase 4 automates it. Phase 5 validates resilience in a disposable environment.

## Files to Change

| File | Action |
|------|--------|
| `ops/tests/k6/load-test.js` | Rewrite with auth, user flows, think-times, SLO thresholds |
| `ops/tests/k6/stress-test.js` | Rewrite with auth, stepped ramp, resource monitoring |
| `ops/tests/k6/spike-test.js` | Rewrite with auth, recovery measurement |
| `ops/tests/k6/soak-test.js` | New — long-duration leak detection |
| `ops/tests/k6/helpers/auth.js` | New — shared Keycloak token helper |
| `ops/tests/k6/helpers/scenarios.js` | New — shared user flow functions |
| `ops/Taskfile.yml` | Add `test:load:soak`, `test:failure-modes`, update existing tasks |
| `platform/helm/schnappy-observability/dashboards/load-test-dashboard.json` | New Grafana dashboard |
| `platform/helm/schnappy/templates/k6-load-*` | CI CronJob + ConfigMap for nightly/weekly |
| `ops/tests/ansible/test-failure-modes.yml` | New — Vagrant failure mode test playbook |
