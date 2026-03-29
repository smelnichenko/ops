# Plan 042: Gatling + VictoriaMetrics (Prometheus Replacement)

**Status:** COMPLETE (Phases 1-7). Phase 8 (Vagrant tests) TODO.
**Created:** 2026-03-29

## Context

Hyperfoil load/stress tests work but have limitations:
- No Prometheus/Grafana integration (HTML reports only, no dashboards)
- Complex YAML DSL with limited documentation
- `!param` templating unreliable — needed sed/awk workarounds
- No real-time metrics visibility during test runs
- Exit code issues (returns non-zero on CPU threshold warnings)

Gatling is a mature JVM-based load testing framework with native Graphite protocol output → VictoriaMetrics → Grafana dashboards. Java DSL fits the project stack (Java 25, Spring Boot 4.0). Pre-built Grafana dashboards available.

## Architecture

```
Gatling (CronJob) → Graphite protocol (TCP 2003) → VictoriaMetrics → Grafana dashboard
                  → Backend services directly (bypass Envoy)
```

## Components

| Component | Image | Purpose |
|-----------|-------|---------|
| Gatling | Custom (gatling:3.15.0 + simulations) | Load/stress test runner |
| VictoriaMetrics | victoriametrics/victoria-metrics | Time-series DB with Graphite input + Prometheus-compatible queries |
| Grafana | existing (12.4.0) | Dashboard |

### Why VictoriaMetrics (replacing Prometheus)

- Drop-in Prometheus replacement — same scrape config, same PromQL, same Grafana datasource
- Accepts Graphite protocol natively (Gatling's output format) — no extra components
- 5-10x less memory than Prometheus for the same data
- Long-term retention built-in (90 days vs Prometheus 15-day default)
- Single binary, no extra components
- All existing Grafana dashboards work unchanged

## Phase 1: Replace Prometheus with VictoriaMetrics

VictoriaMetrics is a drop-in Prometheus replacement: same scrape config format, same PromQL queries, same Grafana datasource type. Additionally accepts Graphite protocol (port 2003) for Gatling metrics. Single binary, 5-10x less memory, long-term retention.

Rename existing Prometheus templates → VictoriaMetrics:
- `prometheus-deployment.yaml` → `victoriametrics-deployment.yaml`
- `prometheus-configmap.yaml` → `victoriametrics-configmap.yaml` (same scrape config)
- `prometheus-service.yaml` → `victoriametrics-service.yaml`
- `prometheus-pvc.yaml` → `victoriametrics-pvc.yaml`
- `prometheus-rules-configmap.yaml` — keep (VM supports `rule_files`)

**Image:** `victoriametrics/victoria-metrics-single:v1.117.1`

Replace Prometheus in the `schnappy-observability` Helm chart:
- Deployment (stateless, single binary) with 5Gi PVC for data
- Graphite input on port 2003 (`-graphiteListenAddr=:2003`)
- Prometheus-compatible HTTP API on port 8428
- Retention: 90 days (`-retentionPeriod=90d`)
- Network policy: ingress from Gatling pods (2003) + Grafana (8428)
- Resources: 100m/500m CPU, 128Mi/512Mi memory

**Files:**
- `helm/schnappy-observability/templates/victoriametrics-deployment.yaml` (NEW)
- `helm/schnappy-observability/templates/victoriametrics-service.yaml` (NEW)
- `helm/schnappy-observability/templates/network-policies.yaml` (update)
- `helm/schnappy-observability/values.yaml` (add victoriametrics section)
- `infra/clusters/production/schnappy-observability/values.yaml` (enable)

**VictoriaMetrics args:**
```yaml
args:
  - -promscrape.config=/etc/prometheus/prometheus.yml
  - -storageDataPath=/data
  - -retentionPeriod=90d
  - -graphiteListenAddr=:2003
  - -httpListenAddr=:8428
```

Same scrape config as Prometheus — no changes needed. Ports: 8428 (HTTP/PromQL), 2003 (Graphite).

**Grafana datasource:** Change URL from `http://schnappy-prometheus:9090` to `http://schnappy-victoriametrics:8428`. Type stays `prometheus`. All existing dashboards work unchanged.

**Alertmanager:** VictoriaMetrics supports `-notifier.url` for Alertmanager and `rule_files` for alerting rules.

## Phase 2: Gatling Docker Image

Build a custom Gatling image with simulations baked in (or mount via ConfigMap).

**Option A: Custom Docker image** (preferred — simulations compiled at build time)
- Dockerfile based on `eclipse-temurin:25-jre-alpine`
- Gatling 3.15.0 binary distribution
- Java simulations compiled with Gradle/Maven
- Push to `git.pmon.dev/schnappy/gatling-tests`

**Option B: ConfigMap with Gatling base image**
- Use community Gatling image
- Mount simulation .java files via ConfigMap
- Gatling compiles at runtime (slower startup)

**Recommendation: Option A** — faster startup, caught compile errors at build time, CI/CD tested.

**Simulation structure (Java DSL):**
```java
public class LoadSimulation extends Simulation {

    String monitorUrl = System.getenv("MONITOR_URL");
    String chatUrl = System.getenv("CHAT_URL");
    String chessUrl = System.getenv("CHESS_URL");
    String keycloakUrl = System.getenv("KEYCLOAK_URL");
    String clientSecret = System.getenv("K6_CLIENT_SECRET");

    HttpProtocolBuilder monitorProtocol = http.baseUrl(monitorUrl);

    // Token fetch + extract
    ChainBuilder getToken = exec(
        http("Token").post(keycloakUrl + "/realms/schnappy/protocol/openid-connect/token")
            .formParam("client_id", "k6-smoke")
            .formParam("client_secret", clientSecret)
            .formParam("grant_type", "client_credentials")
            .check(jsonPath("$.access_token").saveAs("token"))
            .check(jmesPath("sub").saveAs("uuid"))  // from JWT decode
    );

    // Authenticated requests
    ChainBuilder browse = exec(
        http("Health").get("/api/health"),
        http("Pages").get("/api/monitor/pages")
            .header("Authorization", "Bearer #{token}")
            .header("X-User-UUID", "#{uuid}")
            .header("X-User-Email", "k6-smoke@pmon.dev"),
        http("Feeds").get("/api/rss/feeds")
            .header("Authorization", "Bearer #{token}")
            .header("X-User-UUID", "#{uuid}")
            .header("X-User-Email", "k6-smoke@pmon.dev"),
        http("Inbox").get("/api/inbox/emails")
            .header("Authorization", "Bearer #{token}")
            .header("X-User-UUID", "#{uuid}")
            .header("X-User-Email", "k6-smoke@pmon.dev")
    );

    ScenarioBuilder scn = scenario("Load")
        .exec(getToken)
        .forever().on(exec(browse));

    { setUp(
        scn.injectOpen(
            rampUsersPerSec(5).to(50).during(60),
            constantUsersPerSec(50).during(180)
        )
    ).protocols(monitorProtocol); }
}
```

## Phase 3: Gatling Helm Templates

Replace Hyperfoil templates with Gatling:

**Delete:**
- `helm/schnappy/templates/hyperfoil-load-configmap.yaml`
- `helm/schnappy/templates/hyperfoil-load-cronjob.yaml`
- `helm/schnappy/templates/hyperfoil-stress-configmap.yaml`
- `helm/schnappy/templates/hyperfoil-stress-job.yaml`

**Create:**
- `helm/schnappy/templates/gatling-load-cronjob.yaml` — daily CronJob
- `helm/schnappy/templates/gatling-stress-job.yaml` — manual trigger CronJob
- `helm/schnappy/templates/gatling-configmap.yaml` — gatling.conf with Graphite output

**CronJob structure:**
- Image: `git.pmon.dev/schnappy/gatling-tests:<tag>`
- Command: `gatling.sh -s LoadSimulation --non-interactive -nr`
- Env: MONITOR_URL, CHAT_URL, CHESS_URL, KEYCLOAK_URL, K6_CLIENT_SECRET, INFLUXDB_HOST
- Resources: 500m/2000m CPU, 512Mi/1Gi memory
- Security: non-root, drop ALL, readOnlyRootFilesystem

**gatling.conf:**
```hocon
gatling {
  data {
    writers = [console, graphite]
    graphite {
      host = "schnappy-victoriametrics"
      port = 2003
      protocol = "tcp"
      rootPathPrefix = "gatling"
    }
  }
}
```

**Values:**
```yaml
gatling:
  enabled: false
  image:
    repository: git.pmon.dev/schnappy/gatling-tests
    tag: "latest"
  load:
    schedule: "0 3 * * *"
  stress:
    schedule: "0 0 31 2 *"
    suspend: true
```

## Phase 4: Grafana Dashboard

- Add VictoriaMetrics as Grafana datasource (Prometheus type — native support)
- Build custom Gatling dashboard with PromQL queries on Graphite-ingested metrics
- Panels: response times (p50/p95/p99), throughput (req/s), error rates, active users
- Add to existing Grafana at `grafana.pmon.dev`

**Datasource config:**
```yaml
grafana:
  datasources:
    - name: VictoriaMetrics
      type: prometheus
      url: http://schnappy-victoriametrics:8428
      access: proxy
```

## Phase 5: Network Policies

Update NPs:
- Gatling pods → VictoriaMetrics (TCP 2003 Graphite)
- Gatling pods → backend services (TCP 8080)
- Gatling pods → Keycloak (TCP 8080)
- Gatling pods → DNS (UDP/TCP 53)
- Grafana → VictoriaMetrics (TCP 8428 HTTP API)
- Rename hyperfoil-load/stress labels to gatling-load/stress in all service NPs

## Phase 6: CI/CD Pipeline

New `schnappy/gatling-tests` repo with Woodpecker CI:
- Build Gatling simulations with Gradle
- Build Docker image with Kaniko
- Push to Forgejo registry
- Update infra repo values with new tag

## Phase 7: Cleanup

- Remove Hyperfoil templates from schnappy chart
- Remove `hyperfoil` values from chart and production values
- Update CLAUDE.md
- Update Plan 038 references

## Phase 8: Vagrant Integration Tests

### Gatling Test (`task test:gatling`)
- Deploy VictoriaMetrics + Gatling in Vagrant k3s
- Run load simulation against test backend
- Verify metrics arrive in VictoriaMetrics (query Graphite DB)
- Verify Grafana datasource connectivity
- Verify CronJob creation and execution
- Verify network policies (Gatling → backends, Gatling → VictoriaMetrics, Grafana → VictoriaMetrics)

### Envoy Gateway Test (`task test:envoy`)
- Deploy Envoy Gateway + SecurityPolicy + BackendTrafficPolicy + ClientTrafficPolicy in Vagrant k3s
- Deploy Keycloak + backend service (monitor)
- Verify JWT validation (valid token → 200, no token → 401 on protected paths, public paths → 200)
- Verify rate limiting (exceed 50 req/s → 429)
- Verify ClientTrafficPolicy (X-Forwarded-For client IP detection)
- Verify claimToHeaders (X-User-UUID, X-User-Email populated from JWT)
- Verify network policies (Traefik → Envoy → backends)

**Files:**
- `tests/ansible/test-gatling.yml` (NEW)
- `tests/ansible/test-envoy.yml` (NEW)
- `Taskfile.yml` — add `test:gatling` and `test:envoy` tasks

## Validation

1. Deploy VictoriaMetrics, verify Graphite listener on port 2003
2. Run Gatling load test manually, verify metrics in VictoriaMetrics
3. Open Grafana dashboard, verify real-time metrics during test
4. Run stress test, verify 70%+ node CPU utilization
5. Verify daily CronJob execution
6. Check no pod restarts or OOMKills during test
7. `task test:gatling` passes in Vagrant
8. `task test:envoy` passes in Vagrant

## Files Summary

| File | Action |
|------|--------|
| `helm/schnappy-observability/templates/prometheus-*.yaml` | rename → `victoriametrics-*.yaml` (4 files) |
| `helm/schnappy-observability/templates/network-policies.yaml` | update labels + ports |
| `helm/schnappy-observability/templates/grafana-configmap.yaml` | update datasource URL |
| `helm/schnappy-observability/templates/_helpers.tpl` | rename prometheus helpers |
| `helm/schnappy-observability/values.yaml` | rename prometheus → victoriametrics |
| `helm/schnappy/templates/gatling-*.yaml` | NEW (3 files) |
| `helm/schnappy/templates/hyperfoil-*.yaml` | DELETE (4 files) |
| `helm/schnappy/templates/network-policies.yaml` | update labels |
| `helm/schnappy/values.yaml` | replace hyperfoil with gatling |
| `infra/clusters/production/schnappy-observability/values.yaml` | rename prometheus → victoriametrics |
| `infra/clusters/production/schnappy/values.yaml` | replace hyperfoil with gatling |
| New repo: `schnappy/gatling-tests` | Gradle + simulations + Dockerfile |
