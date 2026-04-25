# Plan 070: Logs↔traces correlation, plus OpenObserve as a Discover-like UI

## TL;DR

Two independent halves of the same observability gap:

1. **Trace↔logs correlation** end-to-end. Today exemplars
   (metric→trace) work because Plan 065 kept Mimir intact. The
   reverse jump (span→logs and log→trace) doesn't — `tracesToLogsV2`
   isn't configured on the Tempo datasource, and Fluent-bit doesn't
   extract `traceId` out of log lines into a queryable column.
2. **OpenObserve** added **alongside** ClickHouse as a Kibana-Discover-
   replacement UI. ClickHouse remains the canonical log store
   (events DB + analytics + retention) — OpenObserve is a parallel
   sink with its own storage, used **only** for the ad-hoc
   exploration UX that Grafana Explore is mediocre at. Fluent-bit
   dual-writes; both stores see the same envelope.

Half A is small (Helm + Spring + Fluent-bit + Grafana config).
Half B is structural (new chart, new persistence, new UI route,
new auth integration).

## Half A — trace↔logs correlation

### Current gap

```
metric (Prom) ── exemplar trace_id ──▶ Tempo  ✅ works (Plan 065 kept Mimir)
log (CH) ──── ??? ──▶ trace                  ❌ no traceId column on logs.podlogs
trace span ── ??? ──▶ logs                   ❌ tracesToLogsV2 not configured
```

### Target

```
metric ── exemplar ──▶ Tempo                 (unchanged)
log    ── traceId column ──▶ Tempo           (new: filter logs by trace, click to span)
span   ── tracesToLogsV2 ──▶ ClickHouse      (new: click span, see correlated log lines)
```

### App-side change

Spring Boot 4 ships `micrometer-tracing-bridge-otel` which pushes
`traceId` + `spanId` into the SLF4J MDC automatically when an OTel
context is active. Logback's `JsonLayout` (or `LogstashEncoder`)
emits them as fields on each JSON log line.

Per service (`monitor`, `chat`, `chess`, `admin`):

```xml
<!-- src/main/resources/logback-spring.xml -->
<configuration>
  <include resource="org/springframework/boot/logging/logback/defaults.xml"/>
  <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LogstashEncoder">
      <includeMdcKeyName>traceId</includeMdcKeyName>
      <includeMdcKeyName>spanId</includeMdcKeyName>
    </encoder>
  </appender>
  <root level="INFO"><appender-ref ref="JSON"/></root>
</configuration>
```

`build.gradle`:
```gradle
implementation 'net.logstash.logback:logstash-logback-encoder:8.0'
implementation 'io.micrometer:micrometer-tracing-bridge-otel'
```

(Most services already have `micrometer-tracing` from the existing
Tempo bridge — verify each.)

### Fluent-bit change

Parse JSON log lines into structured fields:

```ini
[FILTER]
    Name              parser
    Match             kube.*
    Key_Name          log
    Parser            json_log
    Reserve_Data      On

[PARSER]
    Name        json_log
    Format      json
    Time_Key    timestamp
    Time_Format %Y-%m-%dT%H:%M:%S.%LZ
```

After this, `traceId`/`spanId` from the JSON appear at the top level
of the record before the ClickHouse output stage.

### ClickHouse schema bump

Promote `traceId` from the `fields Map` column to a real top-level
column with a bloom-filter index. Migration is online — `ALTER TABLE
… ADD COLUMN trace_id String` against existing data.

```sql
ALTER TABLE logs.podlogs
    ADD COLUMN IF NOT EXISTS trace_id  LowCardinality(String) DEFAULT '',
    ADD COLUMN IF NOT EXISTS span_id   LowCardinality(String) DEFAULT '',
    ADD INDEX IF NOT EXISTS idx_trace_id trace_id TYPE bloom_filter GRANULARITY 4;
```

Also append a column-extraction step in the chart's
`clickhouse-logs-schema.sql` so future fresh installs include the
column from the start.

### Grafana datasource wiring

`schnappy-observability/templates/grafana-datasources-configmap.yaml`,
under the Tempo datasource:

```yaml
- name: Tempo
  …
  jsonData:
    tracesToLogsV2:
      datasourceUid: clickhouse-logs
      spanStartTimeShift: "-1m"
      spanEndTimeShift:   "1m"
      filterByTraceID: true
      filterBySpanID:  false
      customQuery: true
      query: |
        SELECT timestamp, level, namespace, pod, message
        FROM logs.podlogs
        WHERE trace_id = '${__span.traceID}'
          AND timestamp BETWEEN $__fromTime AND $__toTime
        ORDER BY timestamp ASC
        LIMIT 500
```

The matching reverse — log→trace — works automatically when the
log row has a column named `trace_id` and the ClickHouse-Logs
datasource is configured with `derivedFields` mapping
`trace_id` → tempo datasource UID.

### Vagrant test gate

Extend `tests/ansible/test-logs.yml`:

1. Deploy a tiny test app emitting one structured log line with a
   known `traceId=feedface…`.
2. Wait for Fluent-bit to ship.
3. `SELECT count() FROM logs.podlogs WHERE trace_id = 'feedface…'`
   == 1.
4. Hit Grafana's `/api/datasources/proxy/{tempo-id}/api/traces/lookup`
   with the `feedface…` ID, follow the `tracesToLogsV2` link
   programmatically, assert the returned row has `message` matching
   the test app's payload.

## Half B — OpenObserve as the Discover-like UI

### Why two stores

ClickHouse + Grafana Explore is fine for "I know what I'm looking
for". Kibana Discover (drag-to-time, click-to-add-filter, top-N
field stats sidebar, schema sniffing on first sight) is genuinely
better for "what was happening around T". Grafana's CH datasource
isn't catching up to that UX in the foreseeable.

OpenObserve ships that exact UX, single Rust binary, ~50–100 Mi
RAM. It's its own store — there's no "OpenObserve as front-end for
external CH" mode. So this plan is **explicit dual-write**:

- ClickHouse: canonical log store, owns analytics, retention,
  `events.all`, all the things we built in Plans 065/066.
- OpenObserve: fast UX for ad-hoc log exploration. Shorter
  retention (e.g. 14 days vs CH's 30) since it's not the source of
  truth.

Yes this means double the ingest traffic + ~7 days of duplicated
hot data. RAM cost is small; disk cost is bounded by the shorter
OO retention.

### Pod topology

```
                       ┌─ ClickHouse (logs.podlogs, 30d, source-of-truth)
fluent-bit DS ──fan-out┤
                       └─ OpenObserve (logs/default, 14d, Discover UI)
```

### Chart additions

`platform/helm/schnappy-observability/templates/`:

- `openobserve-statefulset.yaml` — single-replica, single binary.
  Self-init, embedded sled DB for metadata + local storage tier.
- `openobserve-service.yaml` — ClusterIP 5080.
- `openobserve-secret.yaml` — `OPENOBSERVE_ROOT_USER` (email-style),
  `OPENOBSERVE_ROOT_PASSWORD`, `OPENOBSERVE_OIDC_*` for Keycloak.
- `openobserve-externalsecret.yaml` — ESO from
  `secret/schnappy/openobserve` (generatable).
- `openobserve-httproute.yaml` — `logs.pmon.dev` (steal the host
  back from the Plan 065 Grafana redirect; OpenObserve IS the new
  logs UI).
- `openobserve-networkpolicy.yaml` — ingress from Istio gateway
  source ns, Fluent-bit; egress for OIDC discovery + DNS.

### Fluent-bit fan-out

Append a second `[OUTPUT]` block:

```ini
[OUTPUT]
    Name             http
    Match            kube.*
    Host             schnappy-openobserve
    Port             5080
    URI              /api/default/podlogs/_json
    Format           json_lines
    json_date_key    _timestamp
    json_date_format iso8601
    http_user        ${OPENOBSERVE_ROOT_USER}
    http_passwd      ${OPENOBSERVE_ROOT_PASSWORD}
    Retry_Limit      5
    Workers          2
```

Fluent-bit independently retries each output; ClickHouse and
OpenObserve drift independently if one is slow/down.

### Auth integration

OpenObserve supports OIDC out of the box. Add a Keycloak client
`openobserve` (mirror of `grafana`'s setup) with
`logs.pmon.dev/auth/login/keycloak` redirect. ESO surfaces the
client secret.

### Cost-of-running

| Component | Mem req | Mem limit | Disk |
|---|---|---|---|
| OpenObserve (current) | 128 Mi | 512 Mi | 5 Gi (14d × ~350 Mi/day) |
| Disk overlap with CH | — | — | ~2.5 Gi (overlap window 7 days) |

Net add: ~512 Mi limit, ~5 Gi disk on `ten`.

## Scope

### Files (Half A)

| Path | Change |
|---|---|
| `monitor/src/main/resources/logback-spring.xml` (×4 services) | new — JSON encoder + MDC keys |
| `monitor/build.gradle` (×4) | add `logstash-logback-encoder` |
| `platform/helm/schnappy-observability/files/clickhouse-logs-schema.sql` | add `trace_id`, `span_id` columns + index |
| Migration step in `clickhouse-init-job.yaml` | run the `ALTER TABLE … ADD COLUMN IF NOT EXISTS …` against existing tables |
| `platform/helm/schnappy-observability/templates/fluentbit-configmap.yaml` | add JSON parser filter step |
| `platform/helm/schnappy-observability/templates/grafana-datasources-configmap.yaml` | add `tracesToLogsV2` to Tempo datasource; add `derivedFields` to ClickHouse-Logs datasource |
| `ops/tests/ansible/test-logs.yml` | trace_id round-trip assertion |

### Files (Half B)

| Path | Change |
|---|---|
| `platform/helm/schnappy-observability/files/openobserve-config.yaml` | new — OO config (OIDC, retention) |
| `platform/helm/schnappy-observability/templates/openobserve-{statefulset,service,secret,externalsecret,httproute,networkpolicy,configmap}.yaml` | new (7 files) |
| `platform/helm/schnappy-observability/values.yaml` | new `openobserve:` block |
| `platform/helm/schnappy-observability/templates/_helpers.tpl` | `schnappy.openobserve.*` helpers |
| `platform/helm/schnappy-observability/templates/fluentbit-configmap.yaml` | second `[OUTPUT]` http-fan-out to OO |
| `platform/helm/schnappy-observability/templates/fluentbit-daemonset.yaml` | mount OO secret |
| `platform/helm/schnappy-observability/templates/httproutes.yaml` | drop the Plan 065 logs.pmon.dev → grafana redirect; OO takes the host |
| `platform/helm/schnappy-observability/templates/network-policies.yaml` | OO NP + Fluent-bit egress to OO port 5080 |
| `platform/helm/schnappy-mesh/templates/{service-accounts,authorization-policies}.yaml` | new `openobserve` SA + AP |
| `infra/clusters/production/schnappy-observability/values.yaml` | enable OO |
| `ops/deploy/ansible/playbooks/seed-vault-secrets.yml` | add `openobserve` to `generatable_secrets` (admin password); set `oidc_client_secret` from Keycloak |
| `ops/deploy/ansible/playbooks/setup-keycloak-clients.yml` | new client `openobserve` |
| `ops/tests/ansible/test-logs.yml` | extend: assert OO ingest also working |

## Vagrant gate

Required, in order:

1. `task test:logs` — ClickHouse ingest works (existing) + OO
   `/api/default/podlogs/_search` returns the same line within 60s
   (new) + `trace_id` column query on CH returns the test trace
   (new).
2. `task test:grafana` — `tracesToLogsV2` link from a Tempo trace
   resolves to a ClickHouse row in the Explore split-view.
3. `task test:microservices` — apps still emit JSON logs that
   Fluent-bit can parse; ClickHouse `level` column populates
   correctly (i.e. JSON parsing didn't break the pre-Plan-072
   record shape).

## Migration order

Phase 1 (Half A only — small, safe):
1. Per-service: add `logback-spring.xml` + Logstash encoder dep,
   merge.
2. CH schema migration: `ALTER TABLE … ADD COLUMN`.
3. Fluent-bit JSON parser + datasource `tracesToLogsV2` /
   `derivedFields` — one PR, gated by `task test:logs` extended
   gate.
4. After 24h soak: `trace_id` column populated for new logs;
   click-to-trace works in Grafana Explore + Tempo.

Phase 2 (Half B, separate PR):
1. Ship `schnappy-observability` chart with OO disabled by default.
2. Provision Keycloak client `openobserve`.
3. Enable in production values, deploy → Fluent-bit dual-writes.
4. Drop the logs.pmon.dev → Grafana redirect; OO takes the host.
5. After 7d soak: OO is the day-to-day Discover UI; Grafana Explore
   is the SQL/analytics path.

## Risks

| Risk | Mitigation |
|---|---|
| JSON parser breaks on non-JSON log lines (older services, third-party container logs) | `Reserve_Data On` + `Parser_N` fallback. Unparsed rows still land with `message=raw line`, just without `trace_id`. |
| Schema migration on 30 GiB CH locks reads | `ALTER TABLE … ADD COLUMN` is mutation-free metadata change in ClickHouse — no rewrite, no lock. |
| Tempo's `tracesToLogsV2` query hits CH without auth context | The query runs server-side via Grafana's datasource proxy; CH datasource has `password` from Secret. Same auth path as Explore. |
| OO own-store eats disk | Bounded retention (14d) + small avg log volume. Set storage limit + alert at 80% PVC use. |
| Two log UIs cause "where do I look" confusion | Doc: OO for Discover/exploration, Grafana Explore for SQL/analytics. logs.pmon.dev → OO (the natural bookmark). Grafana Explore is reachable via the existing nav. |
| Dual-write doubles Fluent-bit out-traffic | Fluent-bit is local to each node; both outputs talk to in-cluster Services — no external bandwidth. CPU bump on fluent-bit is ~2× of one output, well under the existing 200m limit. |

## Out of scope

- **Dropping ClickHouse for logs in favor of OO**: the events DB
  (Plan 066) lives in CH, and CH is the analytics path. Don't
  consolidate.
- **OO for metrics or traces**: OO supports both, but Mimir +
  Tempo are working and exemplar-aware. No reason to swap.
- **Two-way drift detection between CH and OO**: short retention
  on OO + canonical-store-is-CH means drift only matters during
  incidents, where you'd query both anyway.
- **App SDK migration to OTel-direct logging** (skipping Fluent-bit
  for OTel logs): OTel logs SDK is maturing; revisit when it's GA
  in Spring Boot.

## Effort

- Half A: ~1 day. App-side is mechanical (one file per service +
  one dep). Schema ALTER is a one-liner. Datasource config is two
  blocks. Vagrant test extension is ~30 LOC.
- Half B: ~2 days. New chart subtree, OIDC client provisioning,
  Fluent-bit fan-out, Keycloak wiring, dashboard polish.

Total: ~3 person-days end-to-end.
