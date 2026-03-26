# k6 Smoke Tests with Prometheus Metrics and Grafana Dashboard

## Status: PLANNED

## Motivation

- **Post-deploy validation:** After Argo CD syncs a new version, automatically verify all critical endpoints respond correctly
- **Daily health check:** Catch regressions or infrastructure drift between deploys
- **Metrics continuity:** Existing Playwright E2E tests validate browser flows; k6 smoke tests validate API-level health with response time metrics in Prometheus/Grafana
- **Alerting foundation:** Smoke test failures feed into Prometheus → Alertmanager → email notifications

## Current State

- k6 load tests exist in `ops/tests/k6/` (load, stress, spike) — run locally via `task test:load`
- Prometheus scrapes app/admin/chat/chess/gateway actuator endpoints
- Grafana has application, monitors, and infrastructure dashboards
- Prometheus does NOT have remote write API enabled (needed for k6 → Prometheus)
- Playwright E2E tests run locally or in CI — not in-cluster

## Target Architecture

```
Argo CD sync → PostSync Hook Job (k6 smoke) → Prometheus remote write → Grafana dashboard
                                                                       → Alertmanager (on failure)
Daily CronJob → same k6 smoke test → same metrics flow
```

### Components

1. **k6 smoke test script** (`ops/tests/k6/smoke-test.js`) — lightweight, hits all critical public + authenticated endpoints
2. **k6 Docker image** — `grafana/k6:latest` with Prometheus remote write output (`--out experimental-prometheus-rw`)
3. **Argo CD PostSync Job** — Helm template in `schnappy` chart, runs after every sync
4. **CronJob** — Helm template in `schnappy-observability` chart, runs daily at 6 AM
5. **Prometheus remote write receiver** — enable `--web.enable-remote-write-receiver` flag
6. **Grafana dashboard** — k6 metrics (response times, error rates, check pass/fail)
7. **Alertmanager rule** — fire alert if smoke test checks fail

## k6 Smoke Test Script

```javascript
// smoke-test.js — Quick validation of all critical endpoints
import http from 'k6/http';
import { check, group } from 'k6';

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ['rate==1.0'],           // All checks must pass
    http_req_duration: ['p(95)<2000'], // 95th percentile under 2s
  },
};

const BASE_URL = __ENV.BASE_URL || 'https://pmon.dev';

export default function () {
  // Public endpoints (no auth)
  group('health', () => {
    const r = http.get(`${BASE_URL}/api/health`);
    check(r, {
      'health 200': (r) => r.status === 200,
      'status UP': (r) => r.json('status') === 'UP',
    });
  });

  group('build-info', () => {
    const r = http.get(`${BASE_URL}/api/build-info`);
    check(r, {
      'build-info 200': (r) => r.status === 200,
      'has gitHash': (r) => r.json('gitHash') !== undefined,
    });
  });

  group('auth', () => {
    const r = http.get(`${BASE_URL}/api/auth/approval-mode`);
    check(r, { 'approval-mode 200': (r) => r.status === 200 });
  });

  group('permissions', () => {
    const r = http.get(`${BASE_URL}/api/permissions/required`);
    check(r, { 'permissions 200': (r) => r.status === 200 });
  });

  // Keycloak
  group('keycloak', () => {
    const r = http.get(`https://auth.pmon.dev/realms/schnappy/.well-known/openid-configuration`);
    check(r, {
      'keycloak 200': (r) => r.status === 200,
      'has issuer': (r) => r.json('issuer') !== undefined,
    });
  });

  // Frontend
  group('frontend', () => {
    const r = http.get(`${BASE_URL}/`);
    check(r, { 'frontend 200': (r) => r.status === 200 });
  });

  // Actuator (Spring Boot health)
  group('actuator', () => {
    const r = http.get(`${BASE_URL}/api/actuator/health`);
    check(r, { 'actuator 200': (r) => r.status === 200 });
  });
}
```

Endpoints tested: health, build-info, approval-mode, permissions, keycloak OIDC discovery, frontend, actuator. All public — no auth token needed. Authenticated endpoint tests can be added later with a Keycloak service account token.

## Implementation

### Phase 1: Enable Prometheus remote write receiver

Add `--web.enable-remote-write-receiver` to Prometheus args in the observability chart.

**File:** `schnappy-observability/templates/prometheus-deployment.yaml`

```yaml
args:
  - --config.file=/etc/prometheus/prometheus.yml
  - --storage.tsdb.path=/prometheus
  - --storage.tsdb.retention.time={{ .Values.prometheus.retention }}
  - --web.enable-remote-write-receiver   # <-- add this
```

**Network policy:** Allow ingress to Prometheus port 9090 from k6 pods (both Job and CronJob).

### Phase 2: k6 smoke test ConfigMap + Job

Add to `schnappy` chart (PostSync hook runs after app deploys):

**`schnappy/templates/k6-smoke-configmap.yaml`** — contains the smoke test script

**`schnappy/templates/k6-smoke-job.yaml`** — Argo CD PostSync hook:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "schnappy.fullname" . }}-k6-smoke-{{ .Release.Revision }}
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 0
  template:
    spec:
      containers:
        - name: k6
          image: grafana/k6:latest
          command: ['k6', 'run', '--out', 'experimental-prometheus-rw', '/scripts/smoke-test.js']
          env:
            - name: BASE_URL
              value: "https://{{ .Values.app.ingress.host }}"
            - name: K6_PROMETHEUS_RW_SERVER_URL
              value: "http://{{ include "schnappy.prometheus.serviceName" . }}:9090/api/v1/write"
            - name: K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM
              value: "true"
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: {{ include "schnappy.fullname" . }}-k6-smoke
      restartPolicy: Never
```

### Phase 3: Daily CronJob

Add to `schnappy-observability` chart:

**`schnappy-observability/templates/k6-smoke-cronjob.yaml`**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "schnappy.fullname" . }}-k6-smoke
spec:
  schedule: "0 6 * * *"   # Daily at 6 AM UTC
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        spec:
          containers:
            - name: k6
              image: grafana/k6:latest
              command: ['k6', 'run', '--out', 'experimental-prometheus-rw', '/scripts/smoke-test.js']
              env:
                - name: BASE_URL
                  value: "https://pmon.dev"
                - name: K6_PROMETHEUS_RW_SERVER_URL
                  value: "http://{{ include "schnappy.prometheus.serviceName" . }}:9090/api/v1/write"
                - name: K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM
                  value: "true"
              volumeMounts:
                - name: scripts
                  mountPath: /scripts
          volumes:
            - name: scripts
              configMap:
                name: {{ include "schnappy.fullname" . }}-k6-smoke
          restartPolicy: Never
```

The CronJob needs the same smoke test ConfigMap. Two options:
- Duplicate the ConfigMap in observability chart
- Put both the ConfigMap and CronJob in the same chart

**Decision:** Put everything in the `schnappy` chart. The PostSync Job and CronJob share the same ConfigMap. The CronJob runs daily regardless of deploys. Having both in one chart avoids duplication.

### Phase 4: Network policies

Add NP rules for k6 pods:

**Egress:** k6 → Prometheus (port 9090, remote write), k6 → app (port 8080, HTTPS via external), k6 → keycloak
**Ingress:** Prometheus ← k6 (port 9090)

k6 pods need external HTTPS egress to reach `pmon.dev` and `auth.pmon.dev` through Traefik.

### Phase 5: Grafana dashboard

Create `dashboards/k6-smoke-dashboard.json` with panels:
- **Check pass rate** — `k6_checks_rate` (gauge, should be 1.0)
- **HTTP request duration** — `k6_http_req_duration` (histogram, p50/p95/p99)
- **HTTP requests per group** — `k6_http_reqs_total` by `group`
- **Error rate** — `k6_http_req_failed_rate`
- **Last run status** — annotation from job completion
- **Test history** — time series of pass/fail over days

### Phase 6: Prometheus alert rule

Add to `schnappy-observability/templates/prometheus-rules-configmap.yaml`:
```yaml
- alert: K6SmokeTestFailing
  expr: k6_checks_rate < 1
  for: 0m
  labels:
    severity: critical
  annotations:
    summary: "k6 smoke test failing"
    description: "One or more smoke test checks failed (pass rate: {{ $value }})"
```

## Values

```yaml
# In schnappy chart values.yaml
smokeTest:
  enabled: true
  image: grafana/k6:latest
  schedule: "0 6 * * *"
  baseUrl: ""              # Defaults to app.ingress.host
```

## Security

- k6 pods run as non-root, drop all capabilities, read-only root filesystem
- k6 only accesses public endpoints — no secrets or auth tokens needed
- Network policy restricts k6 egress to Prometheus (remote write) + external HTTPS (app endpoints)
- Job pods are ephemeral (cleaned up by Argo CD hook-delete-policy and CronJob history limits)

## File Changes

| File | Chart | Change |
|---|---|---|
| `schnappy/templates/k6-smoke-configmap.yaml` | schnappy | New — smoke test script |
| `schnappy/templates/k6-smoke-job.yaml` | schnappy | New — PostSync hook Job |
| `schnappy/templates/k6-smoke-cronjob.yaml` | schnappy | New — daily CronJob |
| `schnappy/templates/network-policies.yaml` | schnappy | Add k6 NP rules |
| `schnappy/values.yaml` | schnappy | Add `smokeTest` config |
| `schnappy-observability/templates/prometheus-deployment.yaml` | observability | Add `--web.enable-remote-write-receiver` |
| `schnappy-observability/templates/prometheus-rules-configmap.yaml` | observability | Add K6SmokeTestFailing alert |
| `schnappy-observability/templates/network-policies.yaml` | observability | Allow k6 → Prometheus ingress |
| `helm/dashboards/k6-smoke-dashboard.json` | observability | New — Grafana dashboard |
| `schnappy-observability/templates/grafana-dashboards-configmap.yaml` | observability | Include new dashboard |
| `infra/clusters/production/schnappy/values.yaml` | infra | Enable smokeTest |

## Implementation Order

1. Enable Prometheus remote write receiver (~10min)
2. Write smoke test script + ConfigMap (~15min)
3. Create PostSync Job template (~10min)
4. Create CronJob template (~10min)
5. Add network policies (~10min)
6. Create Grafana dashboard (~30min)
7. Add alert rule (~5min)
8. Update values + deploy (~10min)
