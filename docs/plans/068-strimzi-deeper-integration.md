# Plan 068: Use Strimzi more deeply — KafkaUser + KafkaConnect for sinks

## TL;DR

Today we use Strimzi only for the Kafka cluster itself (one `Kafka` CR
per env) and a handful of `KafkaTopic` CRs declared inline in the
`schnappy` chart's values. Producers/consumers connect with bootstrap-only
auth. Two changes get us a lot of leverage:

1. **Per-service `KafkaUser` CRs** with SCRAM credentials, ACL'd to only
   the topics they own. ESO syncs the operator-generated Secret into pods.
2. **`KafkaConnect` + `KafkaConnector`** for ClickHouse sink (replaces
   the `Kafka` engine pattern in Plan 065). Offsets live in Kafka, sink
   restarts independently of ClickHouse, and we get a Connect REST API
   for plumbing other sinks later (S3 archival, Tempo trace export).

This plan should land **before** Plan 065 because it rewrites 065's
Kafka→ClickHouse pipeline shape. It is independent of Plan 064, can
ship in parallel.

## Context

### What we get from KafkaUser

Per-service identity. Today, every pod with `KAFKA_BOOTSTRAP_SERVERS`
can read/write any topic — there's no producer/consumer ACL boundary.
A bug or misconfig in the chess service can pollute chat topics. With
`KafkaUser` + `KafkaTopic.spec.acl`, each service gets only the rights
it needs:

- `monitor` user: produce to `monitor.events.*`, consume from `monitor.commands.*`
- `chat` user: produce + consume `chat.*`
- `chess` user: produce + consume `chess.*`
- `centrifugo` user (Plan 066): produce-only on `events.public.*`
- `clickhouse-sink` user (this plan): consume-only on `events.*`, `chat.*`,
  `chess.*` (read-only mirror to analytics)

Strimzi auto-generates SCRAM credentials and stores them in a Secret
named `<KafkaUser-name>` — ESO already knows how to consume secrets;
no Vault round-trip needed for these.

Operationally this is "the same thing we already do for Postgres roles
post-Plan 056" — declarative per-service identity via operator CRs.

### What we get from KafkaConnect for the ClickHouse sink

Plan 065's current shape is:

```
Apps → Kafka → ClickHouse `Kafka` engine (built-in consumer)
                          ↓ MaterializedView
                          MergeTree table
```

Problems:
- ClickHouse restart loses Kafka consumer position (it stores offsets
  in metadata that's not durable across pod restarts in some configs).
- ClickHouse `Kafka` engine doesn't support SASL/SCRAM cleanly without
  config gymnastics (we'd be turning off auth for the sink).
- One sink per topic; adding a second sink (e.g. S3 archive) requires a
  separate `Kafka` engine table.

`KafkaConnect` + `KafkaConnector` shape:

```
Apps → Kafka → KafkaConnect cluster (Strimzi-managed, 2 replicas)
                  ├── ClickHouseSinkConnector → ClickHouse HTTP /insert
                  ├── (future) S3SinkConnector → s3://schnappy-archive/
                  └── (future) JdbcSinkConnector → postgres analytics warehouse
```

- Offsets live in Kafka (`__connect-offsets`) — survives any sink restart.
- SASL/SCRAM works natively (Connect understands KafkaUser).
- One `KafkaConnect` cluster, N `KafkaConnector` CRs. Adding a sink is a
  small CR, not a cluster change.
- Hot-reload: change a connector config via `kubectl edit kafkaconnector`,
  Strimzi rolls it without restarting Connect itself.

Cost: one extra Helm release (KafkaConnect cluster), ~256 MiB RAM per
replica, two replicas for HA = ~512 MiB. ClickHouse drops the `Kafka`
engine + MV (saves ~100 MiB on its side). Net ~400 MiB. Fair trade.

## Scope

### 1. KafkaUser per service

`schnappy/platform/helm/schnappy-data/templates/`:
- `kafka-users.yaml` — emits one `KafkaUser` CR per service. Each
  references the cluster (`spec.cluster: schnappy-kafka`) and lists ACLs
  (`spec.authorization.acls`) for the topics that service owns.
- `kafka-user-secrets.yaml` removed (operator owns Secret now; we just
  reference its name).

`schnappy/platform/helm/schnappy/templates/`:
- `app-deployment.yaml`, `chat-deployment.yaml`, `chess-deployment.yaml`,
  `admin-deployment.yaml`, `game-scp-deployment.yaml` — add SASL env vars:
  ```yaml
  - name: KAFKA_SASL_USERNAME
    valueFrom: { secretKeyRef: { name: schnappy-monitor, key: username } }
  - name: KAFKA_SASL_PASSWORD
    valueFrom: { secretKeyRef: { name: schnappy-monitor, key: password } }
  - name: KAFKA_SECURITY_PROTOCOL
    value: SASL_PLAINTEXT
  - name: KAFKA_SASL_MECHANISM
    value: SCRAM-SHA-512
  ```
  (TLS to Kafka stays Istio mTLS — SASL adds app-layer auth on top.)

App-side: `application.yml` adds:
```yaml
spring.kafka:
  security.protocol: ${KAFKA_SECURITY_PROTOCOL:PLAINTEXT}
  sasl.mechanism: ${KAFKA_SASL_MECHANISM:}
  sasl.jaas.config: >-
    org.apache.kafka.common.security.scram.ScramLoginModule required
    username="${KAFKA_SASL_USERNAME:}"
    password="${KAFKA_SASL_PASSWORD:}";
```

`schnappy/monitor/chat/chess/admin/game-scp` repos: each ships the
`application.yml` change above (5 small PRs).

### 2. KafkaConnect cluster + ClickHouse sink

`schnappy/platform/helm/schnappy-data/templates/`:
- `kafka-connect.yaml` — `KafkaConnect` CR, 2 replicas, image
  `quay.io/strimzi/kafka:0.46.0-kafka-4.0.0` plus Strimzi's
  `KAFKA_CONNECT_BUILD` plugin spec for the ClickHouse sink:
  ```yaml
  build:
    output:
      type: docker
      image: git.pmon.dev/schnappy/kafka-connect:0.1.0
      pushSecret: forgejo-registry
    plugins:
      - name: clickhouse-kafka-connect
        artifacts:
          - type: jar
            url: https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v1.3.4/clickhouse-kafka-connect-v1.3.4.jar
  ```
- `kafka-connector-clickhouse.yaml` — `KafkaConnector` CR per topic the
  sink should consume:
  ```yaml
  apiVersion: kafka.strimzi.io/v1beta2
  kind: KafkaConnector
  metadata:
    name: clickhouse-sink-events
    labels:
      strimzi.io/cluster: schnappy-kafka-connect
  spec:
    class: com.clickhouse.kafka.connect.ClickHouseSinkConnector
    tasksMax: 2
    config:
      topics: events.public,events.private,events.system
      hostname: schnappy-clickhouse
      port: 8123
      database: events
      username: clickhouse-sink   # KafkaUser
      password.source.secret: schnappy-clickhouse-sink   # ESO-synced
      ssl: false
      exactlyOnce: true
  ```
- Plan 065's `clickhouse-kafka-engine.yaml` template **dropped**
  (replace with this Connector).

### 3. Vagrant test integration

`tests/ansible/test-kafka-scylla.yml`:
- Add assertions for the KafkaUser CRs being Ready.
- Verify the operator-generated Secret exists for each user.

`tests/ansible/test-microservices.yml`:
- After the schnappy chart deploys, kubectl-test that a chat message
  publish (using SCRAM creds) round-trips to a chat consumer also
  using SCRAM. Proves the per-service ACL works end-to-end.

`tests/ansible/test-elk.yml` → renamed to `test-logs.yml` per Plan 065:
- Asserts the KafkaConnector status is `Ready` and the ClickHouse
  `events.podlogs` table has rows after 60 seconds. Same end-state as
  Plan 065's spec, different pipeline.

## Vagrant tests are the merge gate (non-negotiable)

1. **`task test:kafka-scylla`** — KafkaUser CRs Ready, secrets generated,
   sample produce/consume with SCRAM round-trips.
2. **`task test:microservices`** — All four Spring services connect to
   Kafka with their per-service SCRAM creds. ACL violation test: spin up
   a one-shot pod with chat's creds trying to produce on a chess topic
   → produce fails with `TopicAuthorizationException`. Proves ACL
   isolation.
3. **`task test:logs`** (post-065 rename) — KafkaConnect cluster Ready,
   ClickHouseSinkConnector Ready, log lines flow into `events.podlogs`
   within 60s.

If any fail, no merge.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| All five services and three repos change at once → big bang merge | Land KafkaUser changes first behind a `KAFKA_SECURITY_PROTOCOL=PLAINTEXT` default that disables SASL. Once everything's in prod, flip the default to `SASL_PLAINTEXT`. Two-phase rollout. |
| KafkaConnect adds 2 pods (~512 MiB RAM) | Acceptable; we're getting back ~100 MiB from removing ClickHouse Kafka engine, so net ~400 MiB. |
| SCRAM secret rotation on KafkaUser regenerates the Secret → pods see stale creds | Spring Kafka library refreshes JAAS credentials on the next produce/consume retry; 1-2 second blip on rotation. Document the rotation playbook. |
| ClickHouse sink connector lags Kafka topic | `KafkaConnector.spec.config.consumer.max.poll.records=500` + monitor `kafka_consumergroup_lag{group=connect-clickhouse-sink-events}` in Mimir. Alert on lag > 60s. |
| Strimzi Connect chart build pulls clickhouse-kafka-connect.jar from GitHub on every restart | Strimzi caches the build; only rebuilds when the spec changes. Image lives in `git.pmon.dev/schnappy/kafka-connect:0.1.0`. |

## Verification

1. `kubectl get kafkauser -n schnappy` → 6 users (monitor, chat, chess,
   admin, game-scp, centrifugo, clickhouse-sink), all `Ready`.
2. `kubectl get secret schnappy-monitor -n schnappy` → has `username`
   and `password` keys.
3. `kubectl exec -it deploy/schnappy-monitor -- kafka-topics.sh
   --bootstrap-server schnappy-kafka-bootstrap:9092
   --command-config /tmp/sasl.properties --list`
   → succeeds (auth works).
4. Same command from a `schnappy-chess` pod with `chess` topics in the
   command → fails with `TopicAuthorizationException` (ACL works).
5. `kubectl get kafkaconnect schnappy-kafka-connect -n schnappy
   -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` → True.
6. `kubectl get kafkaconnector clickhouse-sink-events -n schnappy
   -o jsonpath='{.status.connectorStatus.connector.state}'` → RUNNING.
7. Push a message to `events.public` → see it appear in
   `clickhouse-client --query "SELECT count() FROM events.all"` within 30s.
8. Take ClickHouse down for 30s → restart → connector resumes from
   committed offsets, no duplicate rows in `events.all`.

## Out of scope

- **Cruise Control / KafkaRebalance** — only useful when we have multiple
  brokers; we have 1. Add when we add a 2nd broker.
- **MirrorMaker2** — single-cluster, single-region; not needed.
- **OAuth/OIDC for Kafka clients** — SCRAM is sufficient for our
  service-to-Kafka path. OAuth might come if we ever expose Kafka
  externally, which we won't.
- **Schema Registry** — out of scope for now; Spring services use
  JSON-with-trusted-packages classpath approach. Revisit if we want
  cross-language clients (frontend WebSocket via Centrifugo doesn't
  need Schema Registry — Centrifugo handles JSON envelopes).

## Execution order

1. Save this plan.
2. **`platform`**: add `KafkaUser` CRs + ACL spec + chart values for SASL.
3. **`monitor`, `chat`, `chess`, `admin`, `game-scp`**: 5 small PRs adding
   SASL JAAS to `application.yml`. Default `KAFKA_SECURITY_PROTOCOL=PLAINTEXT`
   so the change is a no-op until charts flip the env value.
4. **`platform`** chart: flip default `kafka.securityProtocol=SASL_PLAINTEXT`.
   Vagrant test full stack.
5. **`platform`**: `KafkaConnect` cluster + `KafkaConnector` for ClickHouse.
6. **Plan 065 ClickHouse logs migration** picks up the new Connector
   pattern instead of the `Kafka` engine. (Plan 065 will reference this
   plan once both are landed.)
