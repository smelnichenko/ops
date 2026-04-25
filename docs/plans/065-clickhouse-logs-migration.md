# Plan 065: Replace Elasticsearch + Kibana with ClickHouse for log storage

## TL;DR

Yes, ClickHouse can replace the ELK part of the stack cleanly. Fluent-bit
stays (it already has a ClickHouse output plugin), Elasticsearch is gone,
Kibana is gone — log queries move to Grafana (which is already deployed
for Mimir + Tempo). The observability story becomes: **one UI (Grafana),
three backends (Mimir / Tempo / ClickHouse), one shipper (Fluent-bit)**.

## Why replace ELK with ClickHouse

### Resource footprint

| | Current (ES + Kibana) | Proposed (ClickHouse) |
|---|---|---|
| Memory (single-replica, tuned for this stack) | ~3–4 GB (ES 1 GB JVM heap + off-heap + Kibana 512 Mi) | ~512 Mi – 1 GB |
| CPU (idle) | ~500 m (JVM + Kibana Node.js) | ~50 m |
| Disk (30 days at current log volume) | ~50 GB (ES index overhead + replica) | ~3–5 GB (ClickHouse typical 10–20× compression) |
| Pods in the chart | 3 (ES StatefulSet, ES-ILM Job, ES-config init, Kibana Deploy, Kibana-setup Job) | 1 (ClickHouse StatefulSet) |

ClickHouse's LZ4 + column store compress log lines to a fraction of what
an inverted-index in ES uses. That alone is enough to justify the move on
a Pi-adjacent deployment.

### Query performance

Typical workload = "show me app X logs between Y and Z, error level, grouped
by pod". ClickHouse is **10–100× faster** than ES for this kind of
time-range + filter + aggregation pattern because it's a columnar store
built for exactly that. ES is optimized for full-text relevance ranking —
which nobody actually uses for ops logs.

### Operational surface

- **No more Kibana**: Grafana already speaks ClickHouse (`grafana-clickhouse-datasource` plugin, first-party). Log queries + metrics + traces in one UI.
- **No more ILM**: ClickHouse uses TTL on MergeTree partitions. Dropping a day's data is a partition rename — O(1). ES ILM is a policy-per-index dance with rollover and shrink phases.
- **No more ES cluster state**: single-node ClickHouse uses the local filesystem and Parts (immutable sorted files); there's no yellow/red cluster color to babysit.
- **SQL**: log queries are `SELECT … WHERE timestamp > now() - INTERVAL 1 HOUR AND pod = 'foo' AND level = 'ERROR'` — no KQL / Lucene translation.

### What's lost

- **Full-text relevance ranking**: ES's BM25 scoring and Lucene analyzers are truly unique. ClickHouse has `LIKE`, `ILIKE`, `positionCaseInsensitive`, `tokens()` + token-bloom-filter indexes, and the `hasTokenCaseInsensitive` function — enough for 95% of ops log search. The remaining 5% (find similar stack traces by fuzzy match) is gone.
- **Kibana Discover**: the drag-to-timeline + pivot UI. Grafana's Explore view with a ClickHouse datasource is competitive but not identical.
- **APM / security / ES-specific plugins**: not used in this stack anyway.

## Current ELK stack being replaced

From [`platform/helm/schnappy-observability`](../../schnappy-observability/):

- `elasticsearch-statefulset.yaml` + `elasticsearch-service.yaml` + `elasticsearch-secret.yaml` + `elasticsearch-configmap.yaml` + `elasticsearch-ilm-job.yaml`
- `kibana-deployment.yaml` + `kibana-service.yaml` + `kibana-configmap.yaml` + `kibana-ingress.yaml` + `kibana-setup-job.yaml`
- `fluentbit-daemonset.yaml` + `fluentbit-configmap.yaml` + `fluentbit-rbac.yaml` (keep — shipper stays)
- Already-present and untouched: `grafana-*.yaml` (datasource list grows by one), `mimir-*`, `tempo-*`, `alertmanager-*`

## Proposed ClickHouse stack

### Chart additions (`schnappy-observability`)

```
templates/
  clickhouse-statefulset.yaml   # single-replica ClickHouse server
  clickhouse-service.yaml       # ClusterIP 8123 (HTTP) + 9000 (native)
  clickhouse-secret.yaml        # admin password; synced via ExternalSecret
  clickhouse-configmap.yaml     # config.xml + users.xml + init.sql
  clickhouse-init-job.yaml      # creates the `logs.podlogs` table on first deploy
```

### Schema — `logs.podlogs`

```sql
CREATE DATABASE IF NOT EXISTS logs;

CREATE TABLE IF NOT EXISTS logs.podlogs
(
    timestamp     DateTime64(3, 'UTC'),
    level         LowCardinality(String),
    namespace     LowCardinality(String),
    pod           String,
    container     LowCardinality(String),
    node          LowCardinality(String),
    app           LowCardinality(String),       -- app.kubernetes.io/name
    component     LowCardinality(String),       -- app.kubernetes.io/component
    stream        LowCardinality(String),       -- stdout / stderr
    message       String,
    labels        Map(LowCardinality(String), String),   -- full k8s labels
    fields        Map(LowCardinality(String), String),   -- parsed JSON fields
    INDEX idx_message_tokens tokens(message) TYPE bloom_filter GRANULARITY 4,
    INDEX idx_pod_bloom pod TYPE bloom_filter GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (namespace, app, timestamp)
TTL timestamp + INTERVAL 30 DAY DELETE
SETTINGS index_granularity = 8192;
```

- `LowCardinality`: compresses enum-like columns (namespace, level) to a few bytes.
- `tokens() + bloom_filter`: replaces what ES used full-text indexes for — substring / keyword search in `message`.
- `Map(String, String)`: captures the remaining "schemaless" log shape. Queries use `labels['app.kubernetes.io/name']`.
- `PARTITION BY toYYYYMMDD`: one partition per day. Dropping old data is a cheap `ALTER TABLE ... DROP PARTITION`.
- `TTL DELETE`: enforces the 30-day retention.

### Fluent-bit config change (`fluentbit-configmap.yaml`)

Replace the `[OUTPUT] name es` block with:

```ini
[OUTPUT]
    Name            http
    Match           kube.*
    Host            schnappy-clickhouse
    Port            8123
    URI             /?database=logs&table=podlogs&query=INSERT INTO logs.podlogs FORMAT JSONEachRow
    Format          json_lines
    json_date_key   timestamp
    json_date_format iso8601
    http_user       default
    http_passwd     ${CLICKHOUSE_PASSWORD}
    tls             off
    Retry_Limit     5
```

(Fluent-bit also has an explicit `clickhouse` output plugin since 3.1 — either works; the `http` output is more portable and is what SigNoz / Altinity recommend for log volumes at this scale.)

### Grafana datasource addition

Edit `grafana-datasources-configmap.yaml` — add one more entry:

```yaml
- name: ClickHouse-Logs
  type: grafana-clickhouse-datasource
  url: http://schnappy-clickhouse:8123
  access: proxy
  secureJsonData:
    password: ${CLICKHOUSE_PASSWORD}
  jsonData:
    defaultDatabase: logs
    username: default
    protocol: http
```

Grafana auto-loads datasources; no restart needed. Install the plugin via
the grafana `GF_INSTALL_PLUGINS=grafana-clickhouse-datasource` env var.

### Dashboard replacement for "what Kibana did"

- One stock Grafana dashboard bundled with the plugin: "ClickHouse Logs
  Explorer" — columns timestamp / level / pod / message + time-range
  filter. Replaces Kibana Discover for 90% of daily use.
- Add a panel to the existing `reliability.json` dashboard:
  `SELECT toStartOfMinute(timestamp), count() FROM logs.podlogs WHERE level IN ('ERROR', 'WARN') GROUP BY 1 ORDER BY 1` — error rate over time, one line.

## Scope

### Changed

| File / config | Action |
|---|---|
| `platform/helm/schnappy-observability/templates/elasticsearch-*.yaml` | delete (5 files) |
| `platform/helm/schnappy-observability/templates/kibana-*.yaml` | delete (5 files) |
| `platform/helm/schnappy-observability/templates/clickhouse-*.yaml` | create (5 files) |
| `platform/helm/schnappy-observability/templates/fluentbit-configmap.yaml` | change `[OUTPUT]` section from `es` to `http` (ClickHouse) |
| `platform/helm/schnappy-observability/values.yaml` | remove `elk:` block, add `clickhouse:` |
| `platform/helm/schnappy-observability/templates/grafana-datasources-configmap.yaml` | add ClickHouse datasource entry |
| `platform/helm/schnappy-observability/templates/grafana-deployment.yaml` | add `GF_INSTALL_PLUGINS=grafana-clickhouse-datasource` env |
| `platform/helm/schnappy-observability/templates/external-secrets.yaml` | swap `elasticsearch` → `clickhouse` secret path |
| `deploy/ansible/playbooks/seed-vault-secrets.yml` | rename `secret/schnappy/elasticsearch` → `secret/schnappy/clickhouse` |
| `tests/ansible/test-elk.yml` | rename to `test-logs.yml`; pod-side assertions switch from ES REST API to ClickHouse SQL over HTTP |
| `Taskfile.yml` | rename `test:elk` → `test:logs` |
| `docs/plans/061-observability-resilience-plan.md` (and any that reference ES) | note that ES is retired in favor of ClickHouse |
| `infra/clusters/production/schnappy-observability/values.yaml` | same chart-value rename |

### Stays

- **Fluent-bit** (the shipper). Only its output config changes.
- **Grafana**. Already deployed; gains a datasource + a plugin.
- **Mimir** (metrics), **Tempo** (traces), **Alertmanager**. Untouched.
- All app code — nobody talks to ES/Kibana directly, only Fluent-bit does.

## Deployment sizing

Single-replica ClickHouse for this workload (100–500 pods emitting ~10–50 log lines/s total):

```yaml
clickhouse:
  image: clickhouse/clickhouse-server:24.8-alpine
  replicas: 1
  resources:
    requests: { cpu: 100m, memory: 512Mi }
    limits:   { cpu: 2,    memory: 2Gi }
  storage:
    size: 20Gi
    storageClass: "local-path"   # or wherever the other StatefulSets live
  retention:
    days: 30
```

Typical `du` after 30 days in this stack's volume: ~3–5 GB. 20 GB PVC is
comfortable headroom.

**HA later**: if we want a replica pair, add `ReplicatedMergeTree` +
`clickhouse-keeper` (3 pods, lightweight — 64 Mi each). Out of scope for
v1.

## Migration

Logs are transient; no ES→ClickHouse data migration needed.

**Original plan was a 24-hour staged cutover with both backends live.
Final decision (during implementation): one-shot replacement.** Logs are
ephemeral, dashboards are read-only, and the cluster is small enough
that a brief gap (~minutes between `helm upgrade` removing ELK pods and
ClickHouse coming up) is cheaper than maintaining a transition gate.

The chart was cut to ClickHouse-only in a single PR:

- Deleted: `elasticsearch-*.yaml`, `kibana-*.yaml`, `elk:` values block,
  `schnappy.elasticsearch.*` and `schnappy.kibana.*` helpers, the ES
  ILM job + helper, ES + Kibana NetworkPolicies, the Kibana HTTPRoute,
  `elasticsearch`/`kibana` mesh ServiceAccounts and AuthorizationPolicy.
- Repurposed: top-level `fluentbit:` block (was `elk.fluentbit`).
  Fluent-bit DaemonSet, ConfigMap, RBAC, NetworkPolicy now gate on
  `fluentbit.enabled` and Fluent-bit talks only to ClickHouse.
- Vault: `secret/schnappy/elasticsearch` retired in
  `seed-vault-secrets.yml`; replaced by `secret/schnappy/clickhouse`.

Operationally:

1. Argo CD picks up the chart change → ELK pods are deleted, ClickHouse
   StatefulSet comes up + the post-install init Job creates the
   `logs.podlogs` table.
2. Fluent-bit DaemonSet rolls; new log lines go to ClickHouse.
3. PVC reclaim post-merge (one-time):
   `kubectl delete pvc -n schnappy -l app.kubernetes.io/component=elasticsearch`

## Vagrant tests are the merge gate (non-negotiable)

Before any production MR merges, the full Vagrant matrix must pass from a
clean `vagrant destroy -f && vagrant up` on a branch that bundles both the
chart work and the test harness rename together (ES and ClickHouse can't
coexist at the same ports, so partial staging breaks).

Required, in order:

1. **`task test:logs`** (renamed from `test:elk`) — seeds the ClickHouse
   password in Vault, deploys the chart, asserts Fluent-bit is `Running`
   with filesystem buffer attached, `SELECT count() FROM logs.podlogs` > 0
   within 60 s, and the TTL clause on the table matches `retentionDays`.
2. **`task test:grafana`** — datasource `ClickHouse-Logs` comes up `healthy`,
   an Explore query via Grafana's API returns rows (proves datasource plugin
   + cert-manager + auth are all wired end-to-end).
3. **`task test:dr`** — a pod crash/restart survives, logs during the
   window are captured (tests Fluent-bit's local buffer spilling to disk
   while ClickHouse is briefly unreachable).
4. **Ingest-loss check inside `test:logs`** — kill `schnappy-clickhouse-0`
   for 30 s, generate log lines, restart; assert the new lines are present
   (proves the filesystem-backed buffer in fluent-bit works as designed).

If any of these fail the branch does not merge. The ELK → ClickHouse
switchover is irreversible from the dashboard-muscle-memory side (ops
team re-learns query shapes), so a dirty cutover is especially expensive.

## Verification

1. **Unit / integration**: `task test:logs` (renamed from `test:elk`) — seeds the ClickHouse password in Vault, deploys the chart, confirms Fluent-bit is `Running`, runs `SELECT count() FROM logs.podlogs` and asserts > 0 rows after 60 s of pod activity.
2. **Schema check**: `test:logs` also asserts the table exists with expected columns + `TTL` clause.
3. **Dashboard smoke**: Grafana API query returns the ClickHouse-Logs datasource as `healthy`.
4. **Resource reduction**: `kubectl top pod -n schnappy | grep -E 'elasticsearch|kibana|clickhouse'` after cutover — the total should drop ~3 GB memory.
5. **Query parity check**: run the 5 most common Kibana searches from ops runbooks as ClickHouse SQL, verify equivalent output.

## Risks

| Risk | Mitigation |
|---|---|
| Fluent-bit HTTP output buffering stalls when ClickHouse is down | `Retry_Limit 5` + `storage.type filesystem` in fluent-bit config → spills to local disk during outages. |
| Schema change after cutover (want to add a column) | `ALTER TABLE logs.podlogs ADD COLUMN … DEFAULT …` — ClickHouse supports this online without a rewrite. |
| No full-text fuzzy ranking for incident debugging | Add `INDEX idx_message_ngram ngrambf_v1(message, 3, 8192, 3, 0)` for trigram search — close enough for "grep-like" fuzzy matches. |
| Team familiar with KQL / Kibana | ClickHouse SQL is closer to familiar ground (SQL) than KQL was; Grafana Explore hides most of it behind point-and-click. |
| Single replica = single point of failure | Fluent-bit's filesystem buffer bridges ~hours of outage; for longer HA, upgrade to ReplicatedMergeTree + ClickHouse-keeper in a follow-up. |

## Post-migration cleanup (T+24h follow-up PR)

After 24 h of healthy ClickHouse ingest, the ELK stack has no runtime
responsibility left. Clean it up — leaving dead charts around makes the
repo confusing and wastes node capacity.

One dedicated PR, `feat(observability): remove ELK after ClickHouse cutover`:

1. **Chart templates — delete** (`platform/helm/schnappy-observability/templates/`):
   - `elasticsearch-statefulset.yaml`, `elasticsearch-service.yaml`,
     `elasticsearch-configmap.yaml`, `elasticsearch-ilm-job.yaml`,
     `elasticsearch-network-policy.yaml`
   - `kibana-deployment.yaml`, `kibana-service.yaml`, `kibana-configmap.yaml`,
     `kibana-setup-job.yaml`, `kibana-ingress.yaml`
2. **Chart values** (`platform/helm/schnappy-observability/values.yaml`):
   remove the entire `elk:` block (elasticsearch + kibana subkeys).
3. **Helpers** (`platform/helm/schnappy-observability/templates/_helpers.tpl`):
   remove `schnappy.elasticsearch.*` and `schnappy.kibana.*` template defines.
4. **ServiceAccounts** (`platform/helm/schnappy-mesh/templates/service-accounts.yaml`):
   remove `"elasticsearch"`, `"kibana"` from the SA list range.
5. **Network policies** (`platform/helm/schnappy-observability/templates/cross-ns-scrape-policies.yaml`):
   remove the ES + Kibana allow rules (no sources left referencing them).
6. **Grafana datasource** (`platform/helm/schnappy-observability/templates/grafana-configmap.yaml`):
   remove the `Elasticsearch` datasource block; keep `ClickHouse-Logs`.
7. **Vault secrets** (`ops/deploy/ansible/playbooks/seed-vault-secrets.yml`):
   remove the `schnappy/elasticsearch` and `schnappy/kibana` KV entries — and
   delete the live KV paths in prod Vault (`vault kv delete
   secret/schnappy/elasticsearch`).
8. **Ansible inventory** (`ops/deploy/ansible/inventory/*.yml`): remove any
   `elasticsearch_password` / `kibana_password` vars.
9. **Tests** (`ops/tests/ansible/test-elk.yml`): delete the file;
   `test:logs` replaces it.
10. **Taskfile** (`ops/Taskfile.yml`): remove `test:elk` target, keep
    `test:logs`.
11. **Runbooks** (`ops/docs/runbooks/`): rewrite any runbook that
    references Kibana URLs, KQL queries, or ES API calls to use the
    ClickHouse-Logs Grafana Explore view. Grep `kibana.pmon.dev` and
    `elasticsearch` across `docs/` — all hits must be rewritten or deleted.
12. **PVC reclaim**: after the chart prune, `kubectl delete pvc -n schnappy
    -l app.kubernetes.io/component=elasticsearch` — the old ES storage is
    gone for good (this is the irreversible step, do it last).
13. **Argo CD**: the `schnappy-observability` Application picks up the
    chart changes; no separate Argo manifest change needed.

Verification after this PR merges:
- `helm get values schnappy -n schnappy -o yaml | grep -iE 'elastic|kibana'`
  → no matches.
- `kubectl get all,pvc,secret,cm -n schnappy | grep -iE 'elastic|kibana'`
  → no matches.
- ClickHouse ingest still healthy (`SELECT count() FROM logs.podlogs WHERE
  timestamp > now() - INTERVAL 5 MINUTE` > 0).
- Grafana Explore "Logs" panel still resolves — nothing was referencing ES
  that we missed.

## Effort estimate

- Chart work: ~1 day (5 new templates + 1 config change + 1 datasource + values.yaml).
- Test suite: ~4 h (rename test-elk.yml to test-logs.yml, swap assertions from ES REST to ClickHouse HTTP).
- Dashboard/panel tuning: ~2 h.
- Cutover + 24 h observation: passive.
- Post-migration cleanup PR: ~2 h (see "Post-migration cleanup" above — well-scoped because the files to delete are enumerated).

## Out of scope (explicitly considered, deferred to separate plans)

The following were weighed on the observability architecture axis and
kept out of this plan — with reasons that make the boundaries explicit
rather than handwave-y.

### A. ClickHouse-keeper + ReplicatedMergeTree (HA ClickHouse)

**What it looks like:**

```
clickhouse-keeper-0  ┐
clickhouse-keeper-1  ├── Raft consensus (like Zookeeper, smaller)
clickhouse-keeper-2  ┘
clickhouse-server-0  ┐
clickhouse-server-1  ├── ReplicatedMergeTree on `logs.podlogs`
```

- `clickhouse-keeper`: self-hosted Raft cluster embedded in the ClickHouse
  codebase; replaces ZooKeeper. 3 pods, ~64 Mi each, StatefulSet, 500 Mi
  PVC each.
- ClickHouse servers use `ReplicatedMergeTree` engine, which coordinates
  inserts/merges through Keeper. Both replicas can be written to (any one
  accepts the insert; Keeper coordinates replication).
- Fluent-bit writes to a Service fronting both ClickHouse pods (`Host:
  schnappy-clickhouse` balances across replica IPs).

**Why defer for this stack:**

- **Workload is asymmetric**. Logs in this stack are write-heavy, read-light.
  Single-replica ClickHouse + Fluent-bit's filesystem buffer handles a
  multi-hour ClickHouse outage without data loss. Adding Keeper is 3 more
  pods + a consensus tier on the critical-path write — complexity we
  don't yet need.
- **The k8s layer already gives us crash-restart**. StatefulSet + PVC
  recover from pod/node loss within minutes. The remaining failure
  domain is "the PVC's disk is corrupt", which is a rare class that
  backup (not replication) addresses better — cheaper to add a nightly
  ClickHouse `BACKUP TO Disk('backups')` job than a Keeper cluster.
- **Chart/operational cost**. +3 pods, +3 PVCs, +1 Service, +Keeper
  TLS certs, +Keeper root password in Vault, +monitoring. The delta is
  non-trivial; don't pay it without a concrete reliability ask.

**When to revisit:**

Replicate ClickHouse when either (a) the logs volume or query load
requires write/read amplification across pods, or (b) we start storing
traces + metrics + logs in the same ClickHouse and losing it would
rebuild the whole observability stack from Fluent-bit + OTel buffers.

**Implementation sketch if we do:**

```yaml
# values.yaml
clickhouse:
  keeper:
    enabled: true
    replicas: 3
    resources:
      requests: { cpu: 50m, memory: 64Mi }
    storage: { size: 1Gi, storageClass: local-path }
  replicas: 2
  # existing fields unchanged
```

Schema switches from `ENGINE = MergeTree` to
`ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/logs/podlogs', '{replica}')`.
No app-side changes; Fluent-bit just round-robins across the ClickHouse
Service endpoints.

---

### B. Tempo → ClickHouse for traces

**What it would look like:**

- Replace Tempo's S3-backed WAL/blocks with ClickHouse table
  `traces.spans` (SigNoz/Uber pattern).
- OpenTelemetry Collector receives OTLP traces, writes to ClickHouse via
  the `clickhouse-exporter`.
- Grafana datasource switches from Tempo to ClickHouse (ClickHouse
  datasource supports trace-view with the same span/service/timeline UI).

**Trade matrix:**

| | Tempo (current) | ClickHouse for traces |
|---|---|---|
| Storage | Object-store native (MinIO S3). WAL on local PVC. | Columnar on local PVC. |
| Write path | Push traces → Tempo distributor → ingester → compactor → S3 blocks. | OTel Collector → ClickHouse insert. |
| Query | TraceQL (Tempo's own query language) | SQL. Grafana generates it from the trace-view UI. |
| Retention | 14 days (current); S3 lifecycle handles eviction. | TTL on partitions. |
| Correlation with logs | Tempo + Loki linked via trace-to-logs panel; **does not exist** for Tempo + ClickHouse-logs today without manual setup. | Single DB — trace_id JOIN against `logs.podlogs` is trivial SQL. |
| Resource cost | 3 pods (compactor, ingester, distributor via monolithic deploy). Tempo is Go, light. | Reuses ClickHouse. |
| Trace-id lookup latency | Sub-second on indexed tempo blocks. | Sub-second via the ClickHouse `TraceID` column. |
| Rarely-used features we'd lose | Tempo's metric-generator (span metrics exported to Prom) — we'd lose this or rebuild on ClickHouse. | — |

**Why defer for now:**

- **Tempo is working and cheap to run** (~200 Mi RAM total). No
  operational pain.
- **Main benefit is logs↔traces correlation**, which is genuinely
  valuable but requires OTel Collector already in place (see section D).
  Do the logs migration (Plan 065) first, then evaluate correlation
  value, then switch traces if the pain is real.
- **Metric-generator feature**: Tempo's span-to-Prom metric pipeline is
  a nice-to-have that SigNoz reimplements differently. Losing it = extra
  migration work.

**When to revisit:**

After Plan 065 (ClickHouse logs) has been in prod for a month and we
have a concrete "I need trace-id linked to logs in a single query" use
case. Estimated plan scope: small (Tempo is already stateless; point
Grafana at the new datasource, delete Tempo).

**Implementation sketch if we do:**

```sql
CREATE TABLE traces.spans (
  timestamp        DateTime64(9, 'UTC'),
  trace_id         FixedString(16),          -- 128 bits
  span_id          FixedString(8),
  parent_span_id   FixedString(8),
  service          LowCardinality(String),
  operation        LowCardinality(String),
  duration_ns      UInt64,
  status_code      LowCardinality(String),
  attributes       Map(LowCardinality(String), String),
  events           Array(Tuple(ts DateTime64(9), name String, attrs Map(String, String))),
  INDEX idx_trace trace_id TYPE bloom_filter GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(timestamp)
ORDER BY (service, timestamp, trace_id)
TTL timestamp + INTERVAL 14 DAY DELETE;
```

---

### C. Mimir → ClickHouse for metrics

**Short answer: no, don't do it.**

Mimir is a purpose-built Prometheus long-term store. It's architecturally
correct for metrics in a way ClickHouse is not:

- **Ingesters + WAL + compactor + store-gateway tiers** each solve a
  distinct metrics-specific problem (hot-set, block compaction, out-of-order
  samples, series cardinality pressure, range-query fan-out). ClickHouse's
  MergeTree doesn't have native PromQL; you'd bolt on an adapter like
  `chprometheus` or SigNoz's metrics-ingest pipeline.
- **PromQL is the query language the whole ecosystem speaks**. Alerting
  rules, recording rules, every dashboard, `promtool` — all of it is
  PromQL. Re-homing to ClickHouse SQL for the 300+ alert rules we have
  in `prometheus-rules.yaml` is a week of work with no functional gain.
- **Storage efficiency for time-series**: Prometheus's float64 + delta-of-
  delta + XOR compression beats ClickHouse's LZ4 on high-cardinality
  metrics data by ~2–3×.
- **Mimir is already running fine** with MinIO S3 backend, 90d retention,
  <300 Mi memory for this stack's volume. Zero operational pain.

**Verdict:** keep Mimir. This is not a defer-and-revisit, this is a
"don't consolidate for consolidation's sake."

**Exemplars seal the argument.** Exemplars are the whole point of
running Mimir + Tempo side-by-side — click a metric spike in Grafana,
jump to the trace. Implementing ClickHouse as a Prometheus remote_write
target preserves samples fine (via adapters like `chproxy-remotewrite`
or Altinity's `chp`) but **drops exemplars end-to-end** because:

- remote_write v1 has no exemplar wire format at all.
- remote_write v2 (2024) added exemplars, but no mainstream OSS
  ClickHouse remote_write adapter preserves them today — `chproxy-
  remotewrite` silently discards, SigNoz only picks up exemplars from
  its OTLP path.
- To get exemplar-equivalent correlation into ClickHouse, every service
  would need to switch from Prom-scrape to OTLP-metrics emission so
  the OTel Collector can attach `trace_id` as a metric attribute on
  ingest. That's a re-instrumentation of the whole fleet, not a
  storage swap.

The one narrow scenario where we'd reconsider: if we want to join metric
values with log contexts or span attributes at query time in a single
statement ("show me requests > 500 ms with their error logs"). Even
there, Grafana's new-ish cross-datasource joins handle it without
consolidating the storage.

---

### D. OpenTelemetry Collector in front of Fluent-bit (or replacing it)

**Three concrete architectures** to distinguish between:

| Option | Pod topology | Logs source | Traces source | Metrics source |
|---|---|---|---|---|
| **D0** (status quo after plan 065) | Fluent-bit DaemonSet → ClickHouse. Tempo for traces. Mimir for metrics. | Fluent-bit tails kubelet container log files. | App OTLP → Tempo distributor. | App `/metrics` scraped by Prometheus Operator → Mimir. |
| **D1** (OTel Collector **alongside** Fluent-bit) | Fluent-bit DaemonSet (logs only) + OTel Collector Deployment (traces + metrics passthrough, with sampling/filtering/attribute rewriting). | Fluent-bit (unchanged). | App OTLP → OTel Collector → Tempo (or ClickHouse later). | Prom scrape → OTel Collector's prometheus receiver → Mimir. |
| **D2** (OTel Collector **replaces** Fluent-bit) | OTel Collector DaemonSet (`filelog` receiver tailing container logs) for logs + OTel Collector Deployment for aggregation. | OTel DaemonSet `filelog` receiver. | OTel OTLP receiver. | OTel prometheus receiver. |

**Recommendation: D1, eventually. Not in this plan.**

Reasoning:

- **Fluent-bit's `tail` input on k8s container logs is battle-tested**.
  The OTel Collector `filelog` receiver is a rewrite of similar logic,
  about 2 years behind Fluent-bit in edge cases (multi-line stack trace
  handling, container runtime variance, log rotation races). Switching
  to D2 just to use one binary is a regression on stability.
- **OTel Collector shines for the gateway role** — centralized
  sampling, attribute enrichment, redaction, routing to multiple sinks.
  That's valuable when we have more than one trace/metrics backend
  (e.g. send traces to both Tempo and ClickHouse during migration).
  Today (single-backend everywhere) it buys nothing.
- **The collector is how we'd do logs↔traces correlation** if we ever
  go with option B above. OTel Collector can enrich logs with active
  trace_id at emit time when apps are instrumented with OTel SDK; that's
  a 5× improvement on the correlation quality vs. Fluent-bit's
  parse-at-shipper-time approach.

**When to adopt D1:**

- Right before (or as part of) the Tempo → ClickHouse migration. D1's
  real value is as a routing layer during that migration (dual-write
  traces to Tempo + ClickHouse for cutover safety).
- If we start doing mixed sampling (e.g. trace head-sampling at 100%
  for errors, 1% for success). Fluent-bit can't do this; OTel Collector
  can.

**Implementation sketch if/when we adopt D1:**

```yaml
# New chart: opentelemetry-collector (official Helm chart, not a custom one)
mode: deployment         # not daemonset — traces + metrics go through here, logs do not
config:
  receivers:
    otlp:
      protocols:
        grpc: { endpoint: 0.0.0.0:4317 }
        http: { endpoint: 0.0.0.0:4318 }
    prometheus:
      config:
        scrape_configs: []   # populated via ServiceMonitor-style discovery, or skip; keep Prom Operator
  processors:
    batch: { timeout: 5s, send_batch_size: 10000 }
    memory_limiter: { limit_percentage: 80 }
    k8sattributes: {}         # auto-tag with pod/namespace/labels
    tail_sampling:            # probabilistic head-sampling could also go here
      decision_wait: 10s
      policies:
        - name: errors-always
          type: status_code
          status_code: { status_codes: [ERROR] }
        - name: probabilistic
          type: probabilistic
          probabilistic: { sampling_percentage: 10 }
  exporters:
    otlp/tempo:
      endpoint: schnappy-tempo:4317
      tls: { insecure: true }
    clickhouse:               # only active after plan 065+B lands
      endpoint: tcp://schnappy-clickhouse:9000
      database: traces
      ttl: 336h
  service:
    pipelines:
      traces:  { receivers: [otlp], processors: [memory_limiter, k8sattributes, tail_sampling, batch], exporters: [otlp/tempo] }
      metrics: { receivers: [otlp], processors: [memory_limiter, batch], exporters: [prometheusremotewrite/mimir] }
```

---

### Summary of these deferrals

| Deferral | Do in this plan? | Separate plan needed? | When to revisit |
|---|---|---|---|
| (A) Replicated ClickHouse + Keeper | No | Yes (small) | After a real ClickHouse availability incident, OR when we move traces/metrics in too. |
| (B) Tempo → ClickHouse for traces | No | Yes (medium) | When we have a concrete logs↔traces correlation need in an incident. |
| (C) Mimir → ClickHouse for metrics | No | **Don't** | Never, unless ecosystem shifts (PromQL-on-ClickHouse becomes standard). |
| (D) OTel Collector alongside Fluent-bit | No | Yes (medium, tied to B) | Together with plan B, or when we need multi-sink routing / tail sampling. |
