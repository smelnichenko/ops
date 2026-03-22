# Chat Service Plan

Real-time messaging service integrated into the monitor application. Designed for 1M concurrent users, initially deployed on single node (`ten`), scaling to GCP when needed.

## Architecture

```
Clients (WebSocket/STOMP)
    ↓
Traefik (sticky sessions via cookie)
    ↓
Chat Service (Spring Boot, virtual threads)
  ├── STOMP over WebSocket (SockJS fallback)
  ├── Kafka (message bus — all chat messages flow through topics)
  ├── Redis (presence, typing indicators, connection registry)
  ├── PostgreSQL (channels, members, relational data)
  └── ScyllaDB (message storage — high-throughput, query-first)

Kafka Topics:
  chat.messages    — partitioned by channelId, ordered delivery
  chat.events      — joins, leaves, typing, read receipts
  chat.notifications — push notifications, email digests
```

## Why Kafka

- Ordered message delivery per channel (partition key = channelId)
- Consumer groups for independent processing (persistence, notifications, search indexing)
- Message replay for late joiners and reconnections
- Durable log — survives pod restarts without message loss
- Natural boundary for future microservice decomposition

## Why ScyllaDB

- Purpose-built for chat workloads (Discord uses ScyllaDB for trillions of messages)
- Incredible write throughput — millions of writes/sec per node
- Predictable low latency — no JVM GC pauses (C++ implementation)
- Linear horizontal scaling — add nodes for proportional throughput
- Perfect partition model: `(channel_id, time_bucket)` gives sequential I/O
- Runs as single node on `ten`, scales to cluster on GCP

## Data Store Split

| Data | Store | Reason |
|------|-------|--------|
| Users, groups, permissions | PostgreSQL | Relational, existing schema |
| Channels, channel_members | PostgreSQL | Relational (JOINs, foreign keys) |
| Messages | ScyllaDB | Write-heavy, query-first, horizontal scaling |
| Message attachments metadata | ScyllaDB | Co-located with messages |
| Presence, typing, connections | Redis | Ephemeral, TTL-based |
| Message bus | Kafka | Ordered delivery, consumer groups |

## Components

### Phase 1: Core Messaging
- [ ] Kafka deployment (KRaft mode, single broker on ten)
- [ ] ScyllaDB deployment (single node on ten)
- [ ] PostgreSQL migration: channels, channel_members tables
- [ ] ScyllaDB schema: messages_by_channel, messages_by_user
- [ ] WebSocket endpoint with STOMP protocol
- [ ] Kafka producer: publish messages to `chat.messages`
- [ ] Kafka consumer: persist messages to ScyllaDB
- [ ] Kafka consumer: fan-out to WebSocket sessions via Redis Pub/Sub
- [ ] Connection registry in Redis (userId → podId mapping)
- [ ] REST API: channel CRUD, message history (cursor-paginated)
- [ ] Frontend: chat UI page at `/chat`
- [ ] Permission: `CHAT` (already exists in Permission enum)

### Phase 2: Presence & UX
- [ ] Online/offline presence (Redis sorted sets with TTL heartbeat)
- [ ] Typing indicators (Redis Pub/Sub, short TTL)
- [ ] Read receipts (last_read_at in channel_members)
- [ ] Unread counts (derived from last_read_at vs latest message)
- [ ] Message editing and deletion (tombstone in ScyllaDB)
- [ ] Direct messages (channel type: DM vs GROUP)

### Phase 3: Rich Features
- [ ] File attachments (MinIO/GCS, presigned upload URLs)
- [ ] Message search (Elasticsearch — already deployed)
- [ ] Threads/replies (parent_message_id in ScyllaDB)
- [ ] Emoji reactions (reactions_by_message table in ScyllaDB)
- [ ] Notification consumer: push notifications, email digests
- [ ] Message pinning (pinned_messages table in PostgreSQL)

### Phase 4: Scale-out (GCP migration)
- [ ] Multi-broker Kafka cluster (3 brokers, replication factor 3)
- [ ] ScyllaDB cluster (3+ nodes, replication factor 3)
- [ ] GKE with HPA for chat backend pods
- [ ] Redis Cluster (3 nodes)
- [ ] CDN for static assets and file attachments
- [ ] Connection-aware load balancing

## Kafka Deployment

### On `ten` (initial, single broker)

```yaml
# Helm values
kafka:
  enabled: false
  image: apache/kafka:4.2.0    # KRaft mode built-in, no ZooKeeper
  replicas: 1
  clusterId: ""                 # Generated once, stored in Vault
  storage:
    size: 10Gi
    storageClass: local-path
  resources:
    requests:
      cpu: 250m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi
  javaOpts: "-Xmx1g -Xms1g"
  retention:
    hours: 168                  # 7 days message retention
    bytes: 10737418240          # 10GB max per topic
  topics:
    - name: chat.messages
      partitions: 12            # Allows up to 12 consumer instances later
      replicationFactor: 1      # Single broker for now
    - name: chat.events
      partitions: 6
      replicationFactor: 1
    - name: chat.notifications
      partitions: 3
      replicationFactor: 1
```

### KRaft mode (no ZooKeeper)
- Apache Kafka 3.9+ runs in KRaft mode by default
- Single process acts as both controller and broker
- Cluster ID generated once, stored in Vault KV (`secret/monitor/kafka`)
- No ZooKeeper pod — saves ~512Mi RAM

## ScyllaDB Deployment

### On `ten` (initial, single node)

```yaml
# Helm values
scylla:
  enabled: false
  image: scylladb/scylla:6.2
  replicas: 1
  storage:
    size: 20Gi
    storageClass: local-path
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 4000m
      memory: 4Gi
  # ScyllaDB tunes itself based on available resources
  # --smp controls CPU cores, --memory controls RAM allocation
  args:
    - "--smp=2"
    - "--memory=2G"
    - "--overprovisioned=1"     # Share CPU with other pods (not dedicated)
    - "--developer-mode=1"      # Single node, relaxed consistency for dev
```

### Production notes
- `--developer-mode=0` and `--overprovisioned=0` on dedicated GCP nodes
- Remove `--smp` and `--memory` flags to let Scylla auto-detect resources
- Replication factor 3 with `NetworkTopologyStrategy` on GCP

### Resource estimates

| Scale | Nodes | CPU req/limit | Memory req/limit | Disk |
|-------|-------|---------------|------------------|------|
| ten (dev/early) | 1 | 500m / 4000m | 2Gi / 4Gi | 20Gi |
| 10K users | 1 | 1000m / 4000m | 4Gi / 8Gi | 50Gi |
| 100K users | 3 | 2000m / 4000m | 8Gi / 16Gi each | 200Gi each |
| 1M users | 5+ | 4000m / 8000m | 16Gi / 32Gi each | 500Gi each |

## DB Schema

### PostgreSQL (relational data)

```sql
-- Channels
CREATE TABLE channels (
    id BIGSERIAL PRIMARY KEY,
    uuid UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    name VARCHAR(100),
    type VARCHAR(20) NOT NULL DEFAULT 'GROUP',  -- GROUP, DM
    created_by BIGINT NOT NULL REFERENCES users(id),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Channel membership
CREATE TABLE channel_members (
    id BIGSERIAL PRIMARY KEY,
    channel_id BIGINT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP NOT NULL DEFAULT NOW(),
    last_read_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (channel_id, user_id)
);
CREATE INDEX idx_channel_members_user ON channel_members(user_id);

-- Pinned messages (references ScyllaDB message by channel_id + message_id)
CREATE TABLE pinned_messages (
    id BIGSERIAL PRIMARY KEY,
    channel_id BIGINT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    message_id TIMEUUID NOT NULL,          -- ScyllaDB message ID
    pinned_by BIGINT NOT NULL REFERENCES users(id),
    pinned_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (channel_id, message_id)
);
```

### ScyllaDB (message storage)

```cql
-- Keyspace
CREATE KEYSPACE chat WITH replication = {
    'class': 'SimpleStrategy',        -- Switch to NetworkTopologyStrategy on GCP
    'replication_factor': 1           -- Switch to 3 on GCP
};

-- Messages by channel (primary read path: "show messages in channel")
-- Bucketed by day to prevent unbounded partition growth
CREATE TABLE chat.messages_by_channel (
    channel_id BIGINT,
    bucket TEXT,                       -- '2026-03-07' (date string)
    message_id TIMEUUID,              -- time-ordered, globally unique
    user_id BIGINT,
    username TEXT,                     -- denormalized for display (avoid JOIN)
    content TEXT,
    parent_message_id TIMEUUID,       -- null for top-level, set for replies
    edited BOOLEAN,
    deleted BOOLEAN,
    PRIMARY KEY ((channel_id, bucket), message_id)
) WITH CLUSTERING ORDER BY (message_id DESC)
  AND default_time_to_live = 0
  AND gc_grace_seconds = 864000;      -- 10 days (for tombstone cleanup)

-- Messages by user (for "my messages" / search-by-author)
CREATE TABLE chat.messages_by_user (
    user_id BIGINT,
    message_id TIMEUUID,
    channel_id BIGINT,
    bucket TEXT,
    content TEXT,
    PRIMARY KEY (user_id, message_id)
) WITH CLUSTERING ORDER BY (message_id DESC);

-- Reactions per message
CREATE TABLE chat.reactions_by_message (
    channel_id BIGINT,
    bucket TEXT,
    message_id TIMEUUID,
    emoji TEXT,
    user_id BIGINT,
    username TEXT,
    PRIMARY KEY ((channel_id, bucket, message_id), emoji, user_id)
);

-- Attachments per message
CREATE TABLE chat.attachments_by_message (
    channel_id BIGINT,
    bucket TEXT,
    message_id TIMEUUID,
    attachment_id TIMEUUID,
    url TEXT,
    filename TEXT,
    content_type TEXT,
    size_bytes BIGINT,
    PRIMARY KEY ((channel_id, bucket, message_id), attachment_id)
);
```

### ScyllaDB Query Patterns

| Query | Table | Partition key |
|-------|-------|---------------|
| Messages in channel (paginated) | messages_by_channel | (channel_id, bucket) |
| User's message history | messages_by_user | user_id |
| Reactions on a message | reactions_by_message | (channel_id, bucket, message_id) |
| Attachments on a message | attachments_by_message | (channel_id, bucket, message_id) |

**Pagination:** Use `message_id` as cursor. Client sends last seen `message_id`, query uses `WHERE message_id < ?`. Cross-bucket: query current bucket first, if fewer than page size, query previous bucket.

### Dual-write from Kafka

Messages are written to both ScyllaDB tables from the Kafka persistence consumer:
```
Kafka chat.messages → ChatMessageConsumer
  ├── INSERT INTO messages_by_channel (...)
  └── INSERT INTO messages_by_user (...)
```
Both writes are idempotent (same `message_id`). If one fails, Kafka retries the batch.

## API Endpoints

```
# Channels (PostgreSQL)
GET    /api/chat/channels                    # List user's channels
POST   /api/chat/channels                    # Create channel
GET    /api/chat/channels/{id}               # Channel details
PUT    /api/chat/channels/{id}               # Update channel
DELETE /api/chat/channels/{id}               # Delete channel (owner only)
POST   /api/chat/channels/{id}/join          # Join channel
POST   /api/chat/channels/{id}/leave         # Leave channel
GET    /api/chat/channels/{id}/members       # List members

# Messages (ScyllaDB via REST for history, WebSocket for real-time)
GET    /api/chat/channels/{id}/messages      # Message history (cursor-paginated)
POST   /api/chat/channels/{id}/messages      # Send message (also via WS)
PUT    /api/chat/messages/{id}               # Edit message
DELETE /api/chat/messages/{id}               # Delete message (tombstone)

# Presence (Redis)
GET    /api/chat/presence                    # Online users in user's channels

# WebSocket
WS     /ws/chat                              # STOMP endpoint
  SUBSCRIBE /topic/channel.{id}              # Receive messages for channel
  SUBSCRIBE /user/queue/notifications        # User-specific events
  SEND      /app/chat.send                   # Send message
  SEND      /app/chat.typing                 # Typing indicator
  SEND      /app/chat.read                   # Mark as read
```

## Message Flow

```
1. User sends message via WebSocket (SEND /app/chat.send)
2. Chat controller validates, generates TIMEUUID, computes bucket
3. Publish to Kafka topic `chat.messages` (key = channelId)
4. Three independent consumers:
   a. Persistence consumer → INSERT into ScyllaDB (both tables)
   b. Delivery consumer → Redis PUBLISH channel:{id} → all pods
      → each pod pushes to local WebSocket sessions subscribed to that channel
   c. Notification consumer → push/email for offline users
5. Consumer offsets tracked by Kafka — at-least-once with idempotent writes
```

## Spring Boot Integration

### Dependencies
```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-websocket")
implementation("org.springframework.kafka:spring-kafka")
implementation("com.datastax.oss:java-driver-core:4.19.0")         // ScyllaDB driver (CQL)
implementation("com.datastax.oss:java-driver-query-builder:4.19.0")
```

### Key Classes

| File | Purpose |
|------|---------|
| `ChatController.java` | REST API for channels and message history |
| `ChatWebSocketController.java` | STOMP message handling (@MessageMapping) |
| `ChatService.java` | Channel CRUD, message send/edit/delete |
| `ChatKafkaProducer.java` | Publish messages to Kafka topics |
| `ChatMessageConsumer.java` | Kafka consumer: persist to ScyllaDB |
| `ChatDeliveryConsumer.java` | Kafka consumer: fan-out via Redis Pub/Sub to WS |
| `ChatNotificationConsumer.java` | Kafka consumer: offline notifications |
| `PresenceService.java` | Redis-based online/offline tracking |
| `ScyllaConfig.java` | CqlSession bean, contact points, keyspace |
| `ScyllaMessageRepository.java` | ScyllaDB queries (messages_by_channel, messages_by_user) |
| `WebSocketConfig.java` | STOMP/SockJS configuration |
| `WebSocketSecurityConfig.java` | JWT auth for WebSocket handshake |
| `Channel.java` | JPA entity (PostgreSQL) |
| `ChannelMember.java` | JPA entity (PostgreSQL) |
| `ChatMessage.java` | POJO for ScyllaDB (not JPA — uses DataStax driver) |

### ScyllaDB Access Pattern
- No JPA/Hibernate for ScyllaDB — use DataStax Java driver directly
- `CqlSession` bean configured in `ScyllaConfig.java`
- Prepared statements for all queries (compiled once, reused)
- Async queries via `CqlSession.executeAsync()` + virtual threads

### WebSocket Auth
- JWT extracted from cookie during WebSocket handshake (HTTP upgrade)
- `HandshakeInterceptor` validates token, sets user principal
- STOMP subscriptions authorized per-channel (must be member)

## Helm Templates

```
infra/helm/templates/
  # Kafka
  kafka-statefulset.yaml        # KRaft single-node StatefulSet
  kafka-configmap.yaml          # server.properties
  kafka-service.yaml            # ClusterIP :9092
  kafka-secret.yaml             # Cluster ID (or existingSecret)
  kafka-topics-job.yaml         # Init job to create topics

  # ScyllaDB
  scylla-statefulset.yaml       # Single-node StatefulSet
  scylla-service.yaml           # ClusterIP :9042
  scylla-schema-job.yaml        # Init job to create keyspace + tables
```

## Network Policies

```yaml
# Kafka: ingress from app only, egress DNS only
# ScyllaDB: ingress from app only, egress DNS only
# App: add egress to Kafka :9092 and ScyllaDB :9042
```

## Frontend

| Route | Component | Permission |
|-------|-----------|------------|
| `/chat` | Chat | CHAT |
| `/chat/:channelId` | ChatChannel | CHAT |

### UI Components
- `ChatSidebar` — channel list, unread badges, presence dots
- `ChatMessages` — message list with virtual scrolling (react-virtuoso)
- `ChatInput` — message compose, file upload, emoji picker
- `ChatHeader` — channel name, member count, search

## Security Considerations

- WebSocket handshake validates JWT from cookie (same as REST)
- STOMP subscription checks channel membership
- Message content sanitized (no XSS via stored messages)
- File uploads: validate content-type, size limit (10MB), virus scan optional
- Rate limit: 60 messages/min per user (separate from API rate limit)
- Kafka ACLs not needed initially (single tenant, internal network)
- ScyllaDB auth disabled initially (internal network); enable when on GCP

## Monitoring

### Prometheus Metrics
- `chat_messages_total` — counter by channel type
- `chat_websocket_connections` — gauge of active connections
- `chat_kafka_consumer_lag` — consumer group lag
- `chat_presence_online_users` — gauge
- `chat_scylla_query_latency` — histogram by query type

### Grafana Dashboard
- Add "Chat" dashboard alongside existing "Web Page Monitor"
- Panels: messages/sec, active connections, consumer lag, ScyllaDB latency, presence count

## Implementation Order

1. Kafka StatefulSet + Helm templates (infra first)
2. ScyllaDB StatefulSet + Helm templates + schema init job
3. PostgreSQL migration (channels, channel_members)
4. ScyllaDB repository layer (DataStax driver, prepared statements)
5. REST API (channel CRUD via JPA, message history via ScyllaDB)
6. WebSocket + STOMP setup with JWT auth
7. Kafka producer/consumer for message flow (persist to ScyllaDB + WS delivery)
8. Redis presence tracking
9. Frontend chat UI
10. Typing indicators, read receipts, reactions
11. File attachments
12. Message search (Elasticsearch)

## Vault Secrets

```
secret/monitor/kafka:
  cluster_id: <generated-uuid>

secret/monitor/scylla:
  # No auth initially (internal network, single tenant)
  # Add when moving to GCP:
  # username: scylla_admin
  # password: <secure>
```

## Resource Summary on `ten`

| Component | CPU req/limit | Memory req/limit | Disk | New? |
|-----------|---------------|------------------|------|------|
| Kafka | 250m / 2000m | 1Gi / 2Gi | 10Gi | Yes |
| ScyllaDB | 500m / 4000m | 2Gi / 4Gi | 20Gi | Yes |
| Chat in backend | ~0 (shared) | ~256Mi additional | — | No (same pod) |
| **Total new** | **750m / 6000m** | **3Gi / 6Gi** | **30Gi** | |

Current `ten` usage leaves ~30Gi RAM free and plenty of CPU headroom. This fits comfortably.

## Migration Path to GCP

When ready to scale beyond `ten`:

1. **GKE cluster** — 3+ nodes, e2-standard-8
2. **Kafka** — 3 brokers, replication factor 3
3. **ScyllaDB** — 3+ nodes via ScyllaDB Operator for Kubernetes
4. **PostgreSQL** — Cloud SQL (channels/members don't need sharding)
5. **Redis** — Memorystore (managed)
6. **Storage** — GCS for file attachments
7. **Load balancer** — GCP LB with WebSocket support + sticky sessions
8. **Terraform** — infrastructure as code for GCP resources

Application code changes for GCP migration:
- ScyllaDB: change replication strategy + factor, add auth credentials
- Kafka: update broker count, replication factor
- Everything else: zero changes
