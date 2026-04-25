# Plan 066: Centralize realtime fanout — Valkey + Centrifugo + Kafka + ClickHouse

## TL;DR

Replace the ad-hoc WebSocket + STOMP setup in each service with one
**Centrifugo** instance as the realtime edge. Apps publish events to
**Kafka** (already running); Centrifugo consumes from Kafka and fans
out to clients over WebSocket/SSE; ClickHouse also reads from the same
Kafka topic via its native `Kafka` engine for analytics and replay.
Valkey (plan 064) becomes Centrifugo's broker for pub/sub + presence
+ history, which is its intended role.

**One diagram:**

```
                    ┌─────────────┐
         move/msg   │             │  WebSocket / SSE
  apps ─────────────▶   Kafka     ├──────────▶ Centrifugo ──▶ browser clients
                    │  (bus)      │            │  │
                    │             │            │  └── Valkey (pub/sub + presence + history)
                    └──────┬──────┘            │
                           │                   └── auth via Keycloak JWT
                           │
                           ▼
                    ClickHouse Kafka engine ──▶ MergeTree (analytics + replay)
```

## Context

Today the stack has three services with separate realtime/WebSocket
setups (Spring Messaging + STOMP over WS):

- [chat.websocket.WebSocketConfig](../../../chat/src/main/java/io/schnappy/chat/websocket/WebSocketConfig.java) + `ChatWebSocketController` + `WebSocketAuthInterceptor`
- `chess.config.WebSocketAuthInterceptor` + (no controller — likely push via Kafka consumer into a WS session broker)
- Kafka producers/consumers per service: `ChatKafkaProducer`, `ChatMessageConsumer`, `ChessEventConsumer`, `UserEventConsumer` in chat + monitor, `UserEventProducer` in admin

Each service:

- Implements JWT auth-handshake logic for WebSocket
- Runs its own STOMP broker (SimpMessaging)
- Scales the realtime state with its own pods
- Defines its own channel naming conventions

Problems this creates:

1. **Duplicated WebSocket plumbing.** Auth interceptor, session registry,
   subscribe-topic wiring — reimplemented in chat and chess.
2. **Scale coupling.** WebSocket state is pinned to pods; horizontal
   scaling requires session stickiness or a shared store (Redis/Valkey).
   Each service ships its own solution.
3. **Cross-service fanout is clumsy.** If admin needs to push a
   notification to the chat UI, it has to go through the chat service's
   STOMP endpoint — or reimplement WebSocket itself.
4. **No event archive.** Moves, messages, lifecycle events exist only
   as ephemeral Kafka messages (7-day retention) and whatever each
   consumer materializes. Replay of a chess game, audit of a chat
   room, or user-session reconstruction requires ad-hoc queries.

## What Centrifugo is

`centrifugo/centrifugo:v6` is a single Go binary + Docker image.
Features relevant here:

- **Transport multiplexing**: WebSocket (RFC 6455) + SSE + HTTP-streaming
  + WebTransport. Clients auto-negotiate.
- **Client SDKs** for Web (centrifuge-js), iOS, Android, Unity, Dart.
  All share a consistent reconnect + subscription API.
- **Channel model**: namespaced channels (e.g. `chess:game:123`,
  `chat:room:general`) with per-namespace permissions.
- **JWT auth**: accepts tokens from our Keycloak realm directly; verifies
  JWKS, checks `exp`, routes by `sub`.
- **Engines**: in-memory (single node) or **Redis/Valkey** (multi-node).
  Valkey engine uses pub/sub for fanout + sorted sets for presence +
  streams for history.
- **Publication sources**: HTTP API, gRPC API, or **Kafka consumer**
  (asynchronous publications introduced in Centrifugo v5; stable in v6).
- **Proxying**: Centrifugo can proxy connect / subscribe / publish /
  refresh events to an HTTP backend — so custom permission logic can
  live in our services without changing clients.

## Architecture — the three consumer paths

**Kafka is the source of truth.** All three consumers read from the
same topic:

```
                                        ┌── Centrifugo (Kafka consumer) ──▶ clients
apps ──publish──▶ Kafka ──┬── logs ─────┼── Chat service (idempotent persistence) ──▶ ScyllaDB
                          │             ├── Chess service (state update) ──▶ Postgres
                          │             └── ClickHouse Kafka engine ──▶ MergeTree (analytics)
                          │
                          └── Kafka retention 7d
```

### Topic design

One topic per event class, partitioned by a logical key to preserve
per-entity ordering:

| Topic | Partition key | Event types |
|---|---|---|
| `events.chat.messages` | `roomId` | `message.sent`, `message.edited`, `message.deleted` |
| `events.chess.moves` | `gameId` | `move.made`, `game.started`, `game.ended`, `game.resigned`, `game.draw-offered` |
| `events.presence` | `userId` | `user.connected`, `user.disconnected`, `user.focus`, `user.typing` |
| `events.notifications` | `userId` | `notification.created`, `notification.read` |

Fields on every event (envelope):

```json
{
  "id": "uuidv7",
  "type": "move.made",
  "version": 1,
  "ts": "2026-04-23T15:30:00.000Z",
  "service": "chess",
  "subject": "game:123",
  "actor": "user-uuid",
  "payload": { ... }
}
```

The envelope is stable even when `payload` shape changes; `version`
marks payload schema. This same envelope gets:

1. Wrapped by Centrifugo into a publication on channel
   `<service>:<subject>` (e.g. `chess:game:123`)
2. Stored in ClickHouse as a row for analytics
3. Consumed by the authoritative service for state persistence (chat
   → ScyllaDB, chess → Postgres game state table)

### Centrifugo configuration

```yaml
# schnappy-realtime/values.yaml
centrifugo:
  image: centrifugo/centrifugo:v6
  replicas: 2                   # stateless; Valkey engine shares state

  engine: redis                 # works against Valkey unchanged
  redis:
    addresses:
      - schnappy-valkey:6379
    password: ${VALKEY_PASSWORD}
    use_lists: true             # history + recovery support
    presence_user_mapping: true

  token_hmac_secret_key: ""     # unset — using RSA/JWKS instead
  token_jwks_public_endpoint: https://auth.pmon.dev/realms/schnappy/protocol/openid-connect/certs
  token_audience: centrifugo

  namespaces:
    - name: chess
      presence: true
      history_size: 200         # last 200 moves per game, replayable
      history_ttl: 7d
      recover: true             # client reconnect → resume from last seen offset
      force_recovery: true
    - name: chat
      presence: true
      history_size: 100
      history_ttl: 30d
      recover: true
      publish_proxy: on         # server-side ACL check before fanout
    - name: notifications
      presence: false
      history_size: 50
      history_ttl: 7d

  # Consume realtime events from Kafka instead of apps publishing via
  # Centrifugo's HTTP API. Apps only publish to Kafka.
  async_consumers:
    - type: kafka
      kafka:
        brokers: [schnappy-kafka:9092]
        topics:
          - events.chat.messages
          - events.chess.moves
          - events.notifications
        consumer_group: centrifugo
      # Centrifugo expects a specific shape in the Kafka value —
      # channel + data. Our envelope has `service` + `subject` which
      # we map via JSON template:
      channel_template: "{{ .service }}:{{ .subject }}"
      data_template: "{{ . }}"  # whole envelope

  proxy:
    connect_endpoint: http://schnappy-gateway:8080/internal/centrifugo/connect
    subscribe_endpoint: http://schnappy-gateway:8080/internal/centrifugo/subscribe
    publish_endpoint: ""        # disabled; clients don't publish directly
    refresh_endpoint: http://schnappy-gateway:8080/internal/centrifugo/refresh
    http:
      timeout: 2s
      retries: 2
```

### ClickHouse Kafka engine

```sql
CREATE DATABASE IF NOT EXISTS events;

-- Kafka engine table = consumer; doesn't store data, just reads.
CREATE TABLE events.kafka_stream (
    id            UUID,
    type          LowCardinality(String),
    version       UInt8,
    ts            DateTime64(3, 'UTC'),
    service       LowCardinality(String),
    subject       String,
    actor         String,
    payload       String       -- raw JSON; access via JSONExtract* at query time
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'schnappy-kafka:9092',
    kafka_topic_list  = 'events.chat.messages,events.chess.moves,events.presence,events.notifications',
    kafka_group_name  = 'clickhouse-events',
    kafka_format      = 'JSONEachRow',
    kafka_num_consumers = 2;

-- Persistent analytics table
CREATE TABLE events.all (
    id            UUID,
    type          LowCardinality(String),
    version       UInt8,
    ts            DateTime64(3, 'UTC'),
    service       LowCardinality(String),
    subject       String,
    actor         String,
    payload       String,
    INDEX idx_actor   actor   TYPE bloom_filter GRANULARITY 4,
    INDEX idx_subject subject TYPE bloom_filter GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(ts)
ORDER BY (service, type, ts)
TTL ts + INTERVAL 180 DAY DELETE;

-- Materialized view pipes Kafka → MergeTree continuously.
CREATE MATERIALIZED VIEW events.ingest TO events.all AS
SELECT * FROM events.kafka_stream;
```

Query examples this unlocks:

```sql
-- Replay a chess game (last hour)
SELECT ts, JSONExtractString(payload, 'from') AS mv_from,
           JSONExtractString(payload, 'to')   AS mv_to,
           JSONExtractString(payload, 'fen')  AS fen
FROM events.all
WHERE service = 'chess' AND subject = 'game:123' AND type = 'move.made'
ORDER BY ts;

-- User activity timeline
SELECT ts, type, service, subject
FROM events.all
WHERE actor = '<uuid>'
ORDER BY ts DESC
LIMIT 50;

-- Peak concurrent chats per hour
SELECT toStartOfHour(ts) AS hour, uniq(subject) AS rooms_active
FROM events.all
WHERE service = 'chat' AND type = 'message.sent'
GROUP BY hour
ORDER BY hour;
```

## Client-side changes

Replace Spring STOMP.js usage with [centrifuge-js](https://github.com/centrifugal/centrifuge-js):

**Before** (STOMP client in site):
```js
const client = new StompJs.Client({
  brokerURL: 'wss://pmon.dev/api/chat/ws',
  connectHeaders: { Authorization: `Bearer ${token}` },
});
client.onConnect = () => {
  client.subscribe(`/topic/chat/${roomId}`, msg => render(JSON.parse(msg.body)));
};
```

**After** (Centrifugo):
```js
import { Centrifuge } from 'centrifuge';

const centrifuge = new Centrifuge('wss://rt.pmon.dev/connection/websocket', {
  token: () => fetchCurrentJWT(),
});
const sub = centrifuge.newSubscription(`chat:room:${roomId}`);
sub.on('publication', ctx => render(ctx.data));
sub.on('join', ctx => showPresence(ctx.info.user, true));
sub.on('leave', ctx => showPresence(ctx.info.user, false));
sub.subscribe();
centrifuge.connect();
```

Benefits:
- Single connection multiplexing all channels (chat + chess + notifications)
- Built-in exponential-backoff reconnect + history recovery (fills the
  publication gap after reconnect from Valkey streams)
- Presence out of the box — no custom `PresenceService`

## Changes by repo

### Operator usage in this plan

Centrifugo itself is a stateless Go binary — no operator needed; runs as
a regular `Deployment` with 2 replicas. Everything it depends on is
operator-managed:

| Backend | Operator | Plan |
|---|---|---|
| **Valkey** (engine: pub/sub, presence, history streams) | hyperspike valkey-operator | 064 |
| **Kafka** (envelope transport) | Strimzi (`Kafka`, `KafkaTopic`) | already in cluster |
| **ClickHouse** (analytics + replay) | ClickHouse-keeper-operator (deferred per 065) — for now a `StatefulSet` rendered by the chart, swappable later | 065 |
| **Keycloak** (JWKS for client auth) | bare-metal on Pi (no operator); shared | existing |

Centrifugo's chart references the operator-managed CRs by Service name
(`schnappy-valkey`, `schnappy-kafka-bootstrap`, `schnappy-clickhouse`) —
no direct dependency on operator versions.

### `schnappy/platform` — new chart

- `helm/schnappy-realtime/Chart.yaml` — new subchart
- `helm/schnappy-realtime/values.yaml` — Centrifugo config above
- `helm/schnappy-realtime/templates/`:
  - `centrifugo-deployment.yaml` (2 replicas, stateless)
  - `centrifugo-service.yaml` (ClusterIP, ports 8000 HTTP + 8001 gRPC admin)
  - `centrifugo-httproute.yaml` (exposes `rt.pmon.dev` via Istio gateway)
  - `centrifugo-externalsecret.yaml` (reads `secret/schnappy/centrifugo` for `token_hmac_secret_key`, admin password, Kafka auth)
  - `centrifugo-configmap.yaml` (`config.yaml` rendered from values)
  - `centrifugo-networkpolicy.yaml` (egress to Valkey + Kafka + Keycloak JWKS)
  - `centrifugo-servicemonitor.yaml` (scrape `/metrics`)
  - `kafkatopic-events.yaml` — Strimzi `KafkaTopic` CR (managed lifecycle, partition/retention via spec, not by hand)

Depends on: `schnappy-data` (Kafka via Strimzi, Valkey CR via valkey-operator),
`schnappy-auth` (Keycloak for JWKS), `schnappy-mesh` (SA + NetworkPolicy base).

### `schnappy/platform` — `schnappy-observability`

Add ClickHouse `events.kafka_stream` + `events.all` tables + MV to
the `schnappy-observability` chart (same chart that Plan 065
introduces for logs). Or put them in `schnappy-realtime` if we'd
rather keep event analytics alongside the realtime layer — this is a
style call, default to observability.

Grafana: new dashboard `Realtime Events` — panels for event rate per
service/type, top-N active subjects per hour, retention-to-disk chart.

### `schnappy/chat`, `schnappy/chess`, `schnappy/admin`, `schnappy/monitor`

- **Remove**: `WebSocketConfig`, `WebSocketAuthInterceptor`,
  `ChatWebSocketController`, STOMP broker config, session registry code.
- **Keep**: `ChatKafkaProducer`, `ChatMessageConsumer` (the
  ScyllaDB-persistence side — still needed).
- **Add**: `/internal/centrifugo/connect`, `/subscribe`, `/refresh`
  endpoints in the gateway service — these are HTTP webhooks Centrifugo
  calls to authorize connections / subscriptions. They validate the JWT
  and map `user → allowed channels`.

The net effect on each service is a code reduction: WebSocket is no
longer its problem.

### `schnappy/site` (frontend)

- Drop `@stomp/stompjs`; add `centrifuge` (~30 kB gzipped).
- Replace all STOMP subscription code with Centrifugo subscriptions
  (~4 files in chat UI + game UI).

### `schnappy/ops`

- `deploy/ansible/playbooks/seed-vault-secrets.yml` — add
  `secret/schnappy/centrifugo` with `token_hmac_secret_key` (HS256
  fallback for admin API) and `admin_password` for the Centrifugo
  admin web UI.
- `tests/ansible/test-realtime.yml` — new integration test:
  1. Publish envelope to `events.chat.messages`.
  2. Verify `ClickHouse.events.all` row appears within 5 s.
  3. Verify Centrifugo delivers the publication over WS (curl `/ws` with
     JWT, subscribe to `chat:room:test`, assert the message arrives).
  4. Verify `valkey-cli llen centrifugo.history.chat:room:test` > 0 (history persisted).
- `Taskfile.yml` — `test:realtime` task.

### `schnappy/infra`

- `clusters/production/schnappy/` — new subdir for `schnappy-realtime`
  Application + SyncWave (after schnappy-data, before schnappy-app).

## How this relates to plans 064 and 065

- Plan 064 (Valkey). This plan **needs** it — Centrifugo's Valkey engine
  is its horizontal-scale mode. Order: 064 → 066.
- Plan 065 (ClickHouse logs). This plan **adds** to the ClickHouse
  deployment — `events` database alongside `logs` database in the same
  ClickHouse instance. No new DB; same chart. Order: 065 → 066, because
  the ClickHouse `Kafka` engine table type isn't enabled without a
  running ClickHouse.

## Migration path

Phase 1 (chart bring-up): deploy Centrifugo + configure Kafka async
consumers. No client changes yet — dual-publish: apps continue to
push STOMP-style, AND publish envelope to Kafka. ClickHouse starts
consuming and persisting.

Phase 2 (frontend cut-over, per surface): switch one UI surface at
a time (chess board → chat room → notifications) from STOMP to
Centrifugo. The gateway endpoints for connect/subscribe webhooks come
online in this phase.

Phase 3 (cleanup): delete STOMP code + `@EnableWebSocket` config +
`ChatWebSocketController` + `SimpMessagingTemplate` usage. Remove
`@stomp/stompjs` from site.

Each phase is a separate PR and can live in prod for a week between
steps. Rollback is per-phase: revert the frontend PR if the client
SDK misbehaves; revert the Centrifugo chart if fanout drops messages.

## Risks

| Risk | Mitigation |
|---|---|
| Centrifugo's Kafka async consumer at-least-once → duplicates fan out. | Include `id` (uuidv7) in envelope; frontend deduplicates by last-seen id per channel (centrifuge-js recovery works this way natively). |
| Valkey pub/sub is fire-and-forget; a disconnected Centrifugo pod misses publications. | Centrifugo engine uses Valkey **streams** (with `use_lists: true`), not pub/sub, for delivery guarantees. Streams replay missed messages on reconnect. |
| ClickHouse Kafka engine consumer group drift → missed events. | Monitor `kafka_consumer_lag` in the existing Mimir pipeline; alert on lag > 60 s. |
| Kafka retention (7d) < ClickHouse retention (180d) intended. | ClickHouse materializes to MergeTree immediately on consume; Kafka only needs to survive a ClickHouse outage of < 7d. |
| Adds a chart + operational surface (Centrifugo is a new component). | The total LOC removed from chat/chess/admin (WebSocket configs, interceptors, session registries) probably exceeds the LOC added in the chart. Net simplification. |
| Client SDK lock-in to centrifuge-js. | The client library is BSD-3, in use by thousands of projects. Reversible by re-implementing STOMP (the code we're deleting now). |

## Vagrant tests are the merge gate (non-negotiable)

Because this migration touches three independent planes at once (publisher
apps, Centrifugo fanout, ClickHouse analytics) and has *three consumers per
event*, partial merges are worse than no merge — a broken branch with two of
the three wired up starts persisting half-events to ClickHouse and can't
roll back cleanly. The migration is phased, but **each phase PR's Vagrant
gate is the same**:

Required, in order:

1. **`task test:realtime`** (new) — deploys Valkey + Centrifugo +
   ClickHouse + Kafka in one vagrant cluster; a Java test publisher writes
   10 envelopes/s to Kafka; a headless test client (centrifuge-js via node)
   subscribes to `game:test` and asserts *every* envelope received in
   order, then runs `SELECT count() FROM events.all WHERE type='test'` and
   asserts it equals the publisher's counter within ±1 (at-least-once).
2. **`task test:microservices`** — with Centrifugo enabled, chess moves
   and chat messages both fan out correctly to two connected browsers
   (headless). This catches integration bugs in the webhook auth path
   (connect/subscribe → gateway → Keycloak token check).
3. **`task test:kafka-scylla`** (existing) — still passes, proving we
   haven't broken the Kafka setup the ClickHouse MV depends on.
4. **Chaos scenario inside `test:realtime`** — kill
   `schnappy-centrifugo-0` mid-publish; the two surviving pods serve the
   subscribed client with `recovery: true`; assert zero message loss
   after reconnect (Valkey streams replay).
5. **Ingest-drift check inside `test:realtime`** — stop Kafka for 30 s,
   publish 50 envelopes, restart Kafka; ClickHouse row count must reach
   50 within 60 s (Kafka engine consumer catches up).

Gate is hard: no phase merges without a clean run from
`vagrant destroy -f && vagrant up`. A half-migrated prod is the worst
failure mode for this plan — analytics queries start lying.

## Verification (post-merge smoke)

1. **Unit tests**: chat/chess service tests that validated STOMP wiring
   are deleted or rewritten against the Centrifugo webhook endpoints.
2. **Load smoke**: `hyperfoil` scenario opens 500 concurrent WebSocket
   connections, publishes 10 msg/s per channel across 50 channels;
   measure Centrifugo memory + Valkey stream size + ClickHouse ingest
   rate.
3. **Chaos prod-replay**: kill a Centrifugo pod mid-stream in prod staging;
   verify the two remaining clients see no publication loss (streams +
   recovery flag). Same mechanism as the Vagrant chaos test, one more
   level up the stack.

## Resource sizing

Single Kubernetes namespace `schnappy`:

| Component | Pods | CPU req/limit | Mem req/limit | Storage |
|---|---|---|---|---|
| Centrifugo | 2 | 100 m / 1 | 128 Mi / 512 Mi | — |
| Valkey | 1 (plan 064) | existing | existing | existing |
| Kafka | 1 (already) | existing | existing | existing |
| ClickHouse | 1 (plan 065) | existing | existing | existing |

Net added: ~2 small pods. No persistent storage.

## Out of scope

- **Centrifugo in HA Valkey mode.** Sufficient for plan 066 with single
  Valkey; revisit as part of plan 065's A (Replicated ClickHouse)
  discussion if we decide to HA-ify the data tier.
- **Game-engine state reconstruction from event stream.** Current chess
  game state lives in Postgres; the event log is a secondary analytics
  view. Rebuilding game state from events is a separate plan.
- **Centrifugo proxy for publish authorization.** v1 disables
  client-initiated publishes (server-only publication via Kafka). When
  we want browser→Centrifugo→channel direct publishes (e.g. typing
  indicators), enable `proxy.publish_endpoint` and implement ACL in the
  gateway.
- **Multi-region / geo-replicated realtime.** Out of scope until the
  stack has more than one region.
- **OpenTelemetry trace propagation through Centrifugo.** Centrifugo
  has OTLP trace support in v6; wiring it up belongs with plan 065-B
  (ClickHouse traces) if we go that route.

## Execution order

1. Save this plan (done).
2. Finish Plan 064 (Valkey rename) — prerequisite for Centrifugo engine.
3. Finish Plan 065 phase 1 (ClickHouse logs + events database).
4. Build `schnappy-realtime` chart (this plan, Phase 1).
5. Gateway service: implement `/internal/centrifugo/{connect,subscribe,refresh}` webhook endpoints.
6. Dual-publish in apps (STOMP + Kafka envelope).
7. Frontend migration (per-surface — chess, chat, notifications).
8. Delete STOMP code + tests.
9. Prod cutover per surface with a 1-week soak between phases.
