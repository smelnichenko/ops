# Microservice Decomposition Plan

## Status: ALL PHASES COMPLETE (2026-03-18)

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | API Gateway (`api-gateway` repo) | Complete |
| Phase 2 | Common library (`io.schnappy:common:1.0.0` → Nexus) | Complete |
| Phase 3 | Linkerd Service Mesh (Helm templates + auth policies) | Complete |
| Phase 4 | Admin/User Service (`admin` repo) | Complete |
| Phase 5 | Chat Service (`chat` repo) | Complete |
| Phase 6 | Chess Service (`chess` repo) | Complete |

**Additional fixes applied:**
- Jackson 3.x migration: replaced all `@Jacksonized` with explicit `@JsonDeserialize`/`@JsonPOJOBuilder` (12 files across all codebases)
- Jackson 3.x imports: migrated `com.fasterxml.jackson.{core,databind}` → `tools.jackson.*` in all services
- Helm values consistency: fixed `chat:`→`chatService:`, `chess:`→`chessService:` in test playbooks
- All 5 codebases compile and monolith tests pass

**Next steps (not part of this plan):**
- Push each service repo to Forgejo and trigger first CI builds
- Enable services in production values one at a time (toggle `enabled: true`)
- Install Linkerd on k3s cluster (`linkerd.enabled: true`)
- Run Vagrant integration tests (`test:gateway`, `test:microservices`, `test:linkerd`)

## Context

The monitor backend is a monolith serving auth, monitoring, RSS, inbox, admin, chat, and chess. We're splitting it into 4 services behind an API gateway for independent scaling and deployment. Four empty Forgejo repos exist: `admin`, `chat`, `chess`, `api-gateway`.

## Architecture

```
Client (pmon.dev)
  ↓
Traefik Ingress
  ├─ /api/** → API Gateway (Spring Cloud Gateway, port 8080)
  │    ├─ /api/auth/**, /api/admin/**,    → admin:8080  (user service)
  │    │   /api/captcha/**, /api/user/**
  │    ├─ /api/chat/**, /ws/chat          → chat:8080
  │    ├─ /api/chess/**, /ws/chess        → chess:8080
  │    └─ /api/**                         → monitor-app:8080 (core: monitoring, RSS, inbox, webhooks)
  └─ /** → frontend:8080
```

**Service dependency graph (no synchronous inter-service calls):**
```
Client → User Service (login/register only — critical path for auth, not gameplay)
Client → Chess Service (JWT validated locally — no user service call)
Client → Chat Service (JWT validated locally — no user service call)
Client → Core (JWT validated locally — no user service call)

Chess Service ──game.events──→ Chat Service
  │  GAME_CREATED  → chat creates game conversation channel
  │  GAME_ENDED    → chat archives/keeps channel available
  │  MOVE          → (ignored by chat, consumed by chess-ws group for WebSocket)
User Service  ──user.events──→ Chess / Chat (profile updates, approvals)
```

**Service responsibilities:**
- **admin (user service)** — registration, login, password reset, email verification, JWT issuance, captcha/PoW, user profile, group/permission management, registration approval (AI/admin/skip). Owns the `users`, `groups`, `user_groups`, `password_reset_tokens`, `email_verification_tokens`, `registration_approvals` tables.
- **chat** — channels, messaging, presence, E2E encryption. Owns `channels`, `channel_members`, `user_keys`, `channel_key_bundles` tables + ScyllaDB message store.
- **chess** — game lifecycle, move validation, AI (Stockfish WASM client-side). Owns `chess_games` table.
- **core** — page monitoring, RSS feeds, inbox, webhooks, scheduling. Owns `page_monitors`, `monitor_results`, `rss_*`, `received_emails`, `game_states` tables.

**Key decisions:**
- **Local JWT validation** — each service validates the JWT signature independently using the shared HS256 secret. No synchronous call to a user service or DB on every request. User claims (id, uuid, email, permissions) are embedded in the token. If the user service is down, existing sessions keep working.
- **Gateway is a thin router** — routes by path prefix, handles CORS and rate limiting, forwards the JWT as-is. Does NOT validate tokens or call the DB.
- **Shared code** via `common` JAR published to Nexus (192.168.11.4:8081). Contains JWT decoder config, Permission enum, @RequirePermission, etc.
- **Database per service** — each service owns its own PostgreSQL database (or schema). No cross-service table access. Services only share user IDs and game IDs as correlation identifiers.
  - `admin` (user service): owns `monitor_admin` DB — users, groups, permissions, approvals, password resets, verification tokens
  - `chat`: owns `monitor_chat` DB — channels, members, user_keys, key_bundles (+ ScyllaDB for messages)
  - `chess`: owns `monitor_chess` DB — chess_games
  - `core`: owns `monitor` DB — page_monitors, monitor_results, rss_*, received_emails, game_states
- **Spring Cloud Gateway** — same Java 25 / Spring Boot 4.0 stack, native WebSocket support.
- **Kafka as event backbone** — chess moves, game lifecycle events, and user events are Kafka topics. Services communicate exclusively through Kafka — no synchronous inter-service calls. Each move is an immutable event; any consumer can replay the full game log independently.

## Kafka Event Topology

Single broker, minimal partitions. Three topics, each service has its own consumer group.

```
Topics (3 partitions each unless noted):
  game.events          ← chess produces (moves + lifecycle: created, joined, checkmate, resign, draw)
                         → chess consumes [group: chess-ws] (WebSocket fan-out to players)
                         → chat consumes [group: chat-game]:
                             GAME_CREATED → create game conversation channel for players
                             GAME_ENDED   → post result, keep channel available for post-game chat
                             MOVE         → ignored

  user.events          ← core produces (registered, email-verified, password-changed, enabled/disabled)
                         → admin consumes [group: admin-user] (triggers approval workflow)
                         → chat consumes [group: chat-user] (admin channel notifications)

  chat.messages        ← chat produces (existing, 12 partitions — higher throughput for messaging)
                         → chat consumes [group: chat-persist] (ScyllaDB persistence)
                         → chat consumes [group: chat-deliver] (WebSocket delivery)
```

Every chess move is an immutable event — player A moves e2→e4 at timestamp T. The `game.events` topic is a complete, replayable game log. Each consumer group processes independently: chess delivers via WebSocket, chat posts game-end notifications to channels.

Spring Kafka with `@KafkaListener` annotations — consistent with the existing chat Kafka pattern in the codebase.

## Shared Library: `common`

New Forgejo repo: **not needed** — publish from monitor repo's new `backend/common/` Gradle subproject.

**Contents** (extracted from current monolith):
- `security/`: `RequirePermission` annotation, `PermissionInterceptor` (AOP — reads permissions from JWT claims, no DB call), `Permission` enum
- `config/`: `JwtConfig` (shared `JwtDecoder` bean — HS256 signature validation only, no user-exists DB check), `AuthProperties` (jwt-secret, token-expiration)
- `controller/`: `GlobalExceptionHandler`
- `dto/`: shared DTOs (e.g., `AuthenticatedUser` extracted from JWT claims)

**Not in common** (stays in core/user service):
- `User`, `AppGroup`, `UserGroup` entities — only core needs these
- `UserRepository`, `AppGroupRepository` — only core does DB user lookups
- `SecurityConfig.securityFilterChain()` — each service defines its own (different public endpoints)
- `PermissionVersionService` — only core needs this (it issues tokens)

The current `SecurityConfig.jwtDecoder()` has a `userExistsValidator` that calls `userRepository.findByUuid()` on every request. In `common`, the `JwtConfig.jwtDecoder()` only validates the signature + expiry — no DB call. The user-exists check happens at token issuance time in core. If a user is disabled, their token expires naturally (1h TTL) or the admin service publishes a `user.events` event that other services can optionally act on.

## User Data Strategy

Services need user info (display name, etc.) without calling the user service synchronously.

**JWT claims** carry essential fields — available on every authenticated request, zero lookups:
```json
{
  "sub": "uuid",
  "uid": 42,
  "email": "alice@example.com",
  "permissions": ["PLAY", "CHAT", "METRICS"],
  "pv": 3
}
```

**Local read models** for data that changes rarely — when a user updates their profile, the admin/user service publishes to `user.events` and interested services update a local cache:
- **Chat:** caches `{userId → displayName}` in Redis. Updated via `user.events` consumer. Falls back to email from JWT if cache miss.
- **Chess:** caches `{userId → displayName}` in Redis. Same pattern. ELO ratings are owned by the chess service itself (stored in `chess_games` or a `chess_ratings` table), not the user service — ratings are a game domain concept.

**Event flow:**
```
User updates profile → admin publishes to user.events {type: PROFILE_UPDATED, userId, displayName}
                      → chat consumer updates Redis cache
                      → chess consumer updates Redis cache
```

This keeps services fully decoupled. No synchronous user lookups. JWT covers the hot path, events handle the rare profile-change path.

**Published to:** Nexus Maven hosted repo at `http://192.168.11.4:8081/repository/maven-releases/` as `io.schnappy:common:1.0.0`

**Each downstream service's `build.gradle`:**
```groovy
repositories {
    maven { url 'http://192.168.11.4:8081/repository/maven-public/' }
    mavenCentral()
}
dependencies {
    implementation 'io.schnappy:common:1.0.0'
}
```

## Phase 1: API Gateway (`/home/sm/src/api-gateway`)

**Goal:** Route all `/api/**` traffic through the gateway. Core monolith continues serving everything initially — gateway just proxies. Then services are extracted one at a time behind it.

### Files to Create

```
api-gateway/
├── build.gradle                          # Spring Cloud Gateway + common
├── settings.gradle
├── src/main/java/io/schnappy/gateway/
│   ├── GatewayApplication.java           # @SpringBootApplication
│   └── config/
│       ├── RouteConfig.java              # Route definitions (or application.yml)
│       └── GatewaySecurityConfig.java    # JWT validation, extract user info, set headers
├── src/main/resources/
│   └── application.yml                   # Routes, JWT config, CORS
├── Dockerfile                            # Multi-stage: gradle build + JRE runtime
└── .woodpecker/
    └── cd.yaml                           # CI/CD pipeline
```

### Routing Rules (`application.yml`)

```yaml
spring:
  cloud:
    gateway:
      routes:
        # Phase 1: everything to core (monolith passthrough)
        - id: core
          uri: http://${CORE_URL:monitor-app:8080}
          predicates:
            - Path=/api/**
```

Later phases add routes for admin, chat, chess that take priority over the catch-all.

### Gateway is a Thin Router

The gateway does NOT validate JWTs or touch the database. It forwards the JWT cookie/header as-is. Each downstream service validates the token locally using `common`'s `JwtConfig`.

### Gateway Handles
- **Path-based routing** — config-driven, routes to correct service
- **CORS** — centralized, removed from individual services
- **Rate limiting** — per-IP (Spring Cloud Gateway's built-in `RequestRateLimiter` filter with Redis)
- **WebSocket upgrade** — forwards `/ws/chat` and `/ws/chess` upgrade requests to correct service
- **Health aggregation** — `/api/gateway/health` checks all downstream services
- **Circuit breaking** — handled by Linkerd sidecar (not gateway code). Gateway stays pure routing

### Gateway Does NOT Handle
- **JWT validation** — each service does this locally (no synchronous dependency)
- **CSRF** — each service handles its own (cookie path scoping differs per service)
- **Permission checking** — `@RequirePermission` runs in each service via `PermissionInterceptor` from common

### Helm Chart (monitor repo owns the chart for all services)

Each service is a separate Deployment + Service in k3s, all in the `monitor` namespace:

```
Deployments (new):                    Services (new):
  monitor-gateway                       monitor-gateway:8080
  monitor-admin                         monitor-admin:8080
  monitor-chat                          monitor-chat:8080
  monitor-chess                         monitor-chess:8080

Existing (unchanged):
  monitor-app (core)                    monitor-app:8080
  monitor-frontend                      monitor-frontend:8080
  monitor-postgres                      monitor-postgres:5432
  monitor-redis                         monitor-redis:6379
  monitor-kafka                         monitor-kafka:9092
  monitor-scylla                        monitor-scylla:9042
```

New Helm templates per service:
- `gateway-deployment.yaml`, `gateway-service.yaml`, `gateway-configmap.yaml`
- `admin-deployment.yaml`, `admin-service.yaml`
- `chat-deployment.yaml`, `chat-service.yaml`
- `chess-deployment.yaml`, `chess-service.yaml`

Modified templates:
- `app-ingress.yaml` — `/api` routes to gateway service instead of app service
- `network-policies.yaml` — per-service ingress/egress rules:
  - gateway: ingress from Traefik, egress to all services + redis
  - admin: ingress from gateway, egress to own postgres DB + redis + kafka
  - chat: ingress from gateway, egress to own postgres DB + redis + kafka + scylla
  - chess: ingress from gateway, egress to own postgres DB + redis + kafka
  - core: ingress from gateway, egress to own postgres DB + redis + kafka + minio + external HTTPS

### CI/CD — Each Repo Has Its Own Pipeline

Every service repo (`api-gateway`, `admin`, `chat`, `chess`) gets its own `.woodpecker/ci.yaml` + `cd.yaml`, same pattern as the monitor repo:

- **CI** (non-master push): `./gradlew test`, lint
- **CD** (master push): test → Kaniko build → `git.pmon.dev/schnappy/<service>:$GIT_HASH` → deploy

Deploy step: each service's CD pipeline runs `helm upgrade --install monitor ./infra/helm ...` with its own image tag `--set`. All services share the **same Helm release** (`monitor` in namespace `monitor`) — the chart in the monitor repo defines all deployments. Each service pipeline only sets its own image tag, leaving others unchanged.

```
api-gateway CD:  helm upgrade --install monitor ... --set-string gateway.image.tag=$GIT_HASH
admin CD:        helm upgrade --install monitor ... --set-string admin.image.tag=$GIT_HASH
chat CD:         helm upgrade --install monitor ... --set-string chat.image.tag=$GIT_HASH
chess CD:        helm upgrade --install monitor ... --set-string chess.image.tag=$GIT_HASH
monitor CD:      helm upgrade --install monitor ... --set-string app.image.tag=$GIT_HASH --set-string frontend.image.tag=$GIT_HASH
```

Each pipeline needs access to the Helm chart. Options:
1. **Chart in Forgejo registry** — publish the Helm chart as an OCI artifact, each pipeline pulls it
2. **Git clone** — each pipeline clones the monitor repo to get `infra/helm/` (simpler, current pattern)

Recommend option 2 (git clone) to start — matches existing workflow. The deploy step clones the monitor repo's `infra/helm/` chart before running `helm upgrade`.

Woodpecker config: each repo is registered in Woodpecker via Forgejo webhook (same as monitor). `woodpecker-deployer` ServiceAccount RBAC already scoped to the monitor namespace.

### Local Dev

- `docker-compose.yml` adds `gateway` service on port 8082
- Frontend `API_BACKEND_HOST` changes from `backend` to `gateway`
- `task dev` starts gateway alongside other services

## Phase 2: Extract `common` Library

Before extracting any service, publish the shared library.

### Steps
1. Create `backend/common/` Gradle subproject in monitor repo
2. Move shared entities, repositories, security, config classes
3. Update `backend/build.gradle` (now `backend/core/build.gradle`) to depend on `:common`
4. Verify all tests pass
5. Add `maven-publish` plugin to `common/build.gradle`
6. Publish to Nexus: `./gradlew :common:publish`
7. CD pipeline publishes on changes to `backend/common/`

### Downstream SecurityConfig

Each service validates JWT locally using the shared HS256 secret from `common`. No network call, no DB lookup — just signature + expiry check. User claims (id, uuid, email, permissions) are read directly from the token.

```java
@Configuration
@EnableWebSecurity
public class ChessSecurityConfig {
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, JwtDecoder jwtDecoder) {
        http
            .csrf(csrf -> csrf.disable())  // API-only service, no browser cookies
            .sessionManagement(s -> s.sessionCreationPolicy(STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> jwt.decoder(jwtDecoder)));
        return http.build();
    }
}
```

The `JwtDecoder` bean comes from `common`'s `JwtConfig` — validates HS256 signature + expiry only. `PermissionInterceptor` (also from common) reads the `permissions` claim from the JWT to enforce `@RequirePermission`.

## Phase 3: Linkerd Service Mesh

Install Linkerd on the k3s cluster. Every pod gets a sidecar proxy injected automatically.

**What Linkerd provides (no code changes):**
- **mTLS** between all pods — automatic, transparent. Replaces network policy as the auth layer between services (keep NPs for defense-in-depth)
- **Retries + timeouts** — declared per route in `ServiceProfile` CRDs, not application config. Different services can have different timeout policies for the same upstream endpoint (e.g., chess and chat can have different timeouts calling the user service)
- **Circuit breaking** — Linkerd detects failing endpoints and stops sending traffic
- **Observability** — golden metrics (request rate, success rate, latency percentiles) per service, per route. Linkerd Viz for real-time service topology. Metrics exported to existing Prometheus → Grafana dashboards. Complements ELK: Linkerd tells you "chess service has elevated latency to admin service", ELK logs tell you why
- **Traffic splitting** — canary deployments for service rollouts
- **Authorization policies** — `Server` + `ServerAuthorization` CRDs enforce which services can talk to which, using mTLS identity (ServiceAccounts), not just network IPs:

```yaml
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata:
  name: chess-service
spec:
  podSelector:
    matchLabels:
      app: chess-service
  port: 8080
---
apiVersion: policy.linkerd.io/v1beta3
kind: ServerAuthorization
metadata:
  name: allow-gateway-only
spec:
  server:
    name: chess-service
  client:
    meshTLS:
      serviceAccounts:
        - name: api-gateway    # only gateway can call chess HTTP
```

Allowed communication matrix:
| Target | Allowed callers (ServiceAccount identity) |
|--------|------------------------------------------|
| admin | gateway |
| chat | gateway |
| chess | gateway |
| core | gateway |
| gateway | traefik (external), all services (health) |
| kafka | admin, chat, chess, core |
| postgres-* | owning service only |

**Installation:**
```bash
# Linkerd CLI
curl -sL run.linkerd.io/install | sh

# Install CRDs + control plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Inject sidecars into monitor namespace
kubectl annotate namespace monitor linkerd.io/inject=enabled
kubectl rollout restart deploy -n monitor  # triggers sidecar injection
```

**Helm integration:** Add Linkerd annotations to all deployments in the Helm chart:
```yaml
metadata:
  annotations:
    linkerd.io/inject: enabled
```

**Ansible playbook:** `deploy/ansible/playbooks/setup-linkerd.yml` — installs Linkerd, injects namespace, creates ServiceProfiles for gateway routes.

**WebSocket caveat:** Linkerd supports WebSocket connections — they get mTLS — but treats them as long-lived TCP. Per-message L7 metrics and routing don't apply like request/response HTTP. STOMP-over-SockJS connections for chat and chess will be encrypted and authenticated, but golden metrics (latency, success rate) only cover the initial upgrade handshake, not individual STOMP frames. Application-level metrics (message count, delivery latency) should still be emitted via Prometheus from the chat/chess services directly.

**Gateway simplification:** With Linkerd handling mTLS, retries, and circuit breaking, the gateway becomes pure path-based routing + CORS + rate limiting. No Resilience4j dependency needed.

## Phase 4: Extract Admin / User Service (`/home/sm/src/admin`)

The admin repo is really the **user service** — it owns identity, authentication, and authorization. Extracted before chat and chess because auth, authorization, profiles, and registration are cross-cutting concerns that both depend on.

### Files to Move
- **Auth:** `AuthController`, `AuthService`, `AuthProperties`
- **Admin:** `AdminController`, `AdminService`
- **Approval:** `RegistrationApprovalService`, `AiApprovalService`, `ApprovalProperties`
- **Password reset:** `PasswordResetService`, `PasswordResetToken` entity
- **Email verification:** `EmailVerificationService`, `EmailVerificationToken` entity
- **Captcha:** `CaptchaController`, `CaptchaConfigController`, `HashcashService`, `CaptchaProperties`
- **User profile:** `UserController`
- **Permissions:** `PermissionsController`, `PermissionVersionService`
- **Entities:** `User`, `AppGroup`, `UserGroup`, `GroupPermission`, `RegistrationApproval`
- **Repositories:** `UserRepository`, `AppGroupRepository`, `UserGroupRepository`, `RegistrationApprovalRepository`
- **Mail:** `MailConfig`, `MailProperties`
- **Events:** `EmailVerifiedEvent`, `PermissionsChangedException`

### What Changes
- Owns its own database `monitor_admin` with `users`, `groups`, `user_groups`, `password_reset_tokens`, `email_verification_tokens`, `registration_approvals` tables
- Other services only store `userId` as a correlation identifier — they never access the users database
- JWT issuance stays here; other services validate tokens locally via `common`
- Publishes to `user.events` topic: registered, email-verified, approved, disabled, permissions-changed
- Chat consumes `user.events` for admin channel notifications
- Core no longer needs `User` entity or `UserRepository` — it only stores `userId` from JWT claims

### Helm Templates
- `admin-deployment.yaml`, `admin-service.yaml`
- Network policies: ingress from gateway, egress to postgres/redis/kafka

### Gateway Routes
```yaml
- id: admin-auth
  uri: http://${ADMIN_URL:monitor-admin:8080}
  predicates:
    - Path=/api/auth/**,/api/admin/**,/api/captcha/**,/api/user/**,/api/permissions/**
```

## Phase 5: Extract Chat Service (`/home/sm/src/chat`)

Chat is the cleanest extraction — 28 files already isolated in `chat/` package.

### Files to Move
All from `backend/src/main/java/io/schnappy/monitor/chat/`:
- Controllers: `ChatController`, `ChatWebSocketController`
- Services: `ChatService`, `PresenceService`, `SystemChannelService`
- Entities: `Channel`, `ChannelMember`, `UserKeys`, `ChannelKeyBundle`
- Repositories: `ChannelRepository`, `ChannelMemberRepository`, `ScyllaMessageRepository`, `UserKeysRepository`, `ChannelKeyBundleRepository`
- Kafka: `ChatKafkaProducer`, `ChatMessageConsumer`
- WebSocket: `WebSocketConfig`, `WebSocketAuthInterceptor`, `SubscriptionGuard`
- Config: `ChatProperties`, `ScyllaConfig`
- DTOs

### Cross-Service Dependencies to Resolve

| Dependency | Resolution |
|-----------|-----------|
| `UserRepository` (chat looks up users for display names) | Local Redis cache populated from `user.events` + JWT claims. No direct DB access to users table |
| `SystemChannelService` (core calls it for admin notifications) | Core publishes to `user.events`, chat consumes |
| `EmailVerifiedEvent` (triggers approval notification in admin channel) | Core publishes to `user.events`, admin consumes |
| `WebSocketConfig` (shared STOMP broker for chat + chess) | Each service gets its own WebSocket endpoint. Chat: `/ws/chat`, Chess: `/ws/chess` |
| `SubscriptionGuard` (validates chess + chat subscriptions) | Split: chat guard stays in chat, chess guard moves to chess service |
| Game-end notifications in chat channels | Chat consumes `game.events` topic, filters for terminal events (checkmate, resign, draw) |

### Helm Templates
- `chat-deployment.yaml`, `chat-service.yaml`
- Network policies: ingress from gateway, egress to postgres/redis/kafka/scylla

### Gateway Route Addition
```yaml
- id: chat-ws
  uri: ws://${CHAT_URL:monitor-chat:8080}
  predicates:
    - Path=/ws/chat/**
- id: chat-api
  uri: http://${CHAT_URL:monitor-chat:8080}
  predicates:
    - Path=/api/chat/**
```

## Phase 6: Extract Chess Service (`/home/sm/src/chess`)

15 files, already isolated in `chess/` package.

### Files to Move
All from `backend/src/main/java/io/schnappy/monitor/chess/`:
- `ChessController`, `ChessService`, `ChessGameCacheService`
- `ChessGame` entity, `ChessGameRepository`
- Kafka: `ChessKafkaProducer`, `ChessEventConsumer`
- DTOs, enums, properties

### Dependencies
- `Permission.PLAY` + `@RequirePermission` — from `common`
- Own PostgreSQL database `monitor_chess` — `chess_games` table (+ future `chess_ratings`)
- Redis — game state cache
- Kafka `game.events` topic — immutable move + lifecycle event log (producer). Each event: `{gameUuid, type, moveUci, fen, pgn, status, result, userId, timestamp}`. Consumers: chess [group: chess-ws] (WebSocket delivery), chat [group: chat-game] (game-end notifications)
- WebSocket — own `WebSocketConfig` with `/ws/chess` endpoint
- User IDs stored as correlation identifiers only — no `User` entity, no access to users DB

### Helm Templates
- `chess-deployment.yaml`, `chess-service.yaml`
- Network policies: ingress from gateway, egress to postgres/redis/kafka

### Gateway Route Addition
```yaml
- id: chess-ws
  uri: ws://${CHESS_URL:monitor-chess:8080}
  predicates:
    - Path=/ws/chess/**
- id: chess-api
  uri: http://${CHESS_URL:monitor-chess:8080}
  predicates:
    - Path=/api/chess/**
```

## Implementation Order

Start with **Phase 1 (API Gateway)** — the foundation. Then extract the user service first because auth, authorization, profiles, and registration are cross-cutting concerns that both chess and chat depend on.

1. **Phase 1: API Gateway** — thin router, CORS, rate limiting
2. **Phase 2: common library** — extract shared code (JWT decoder, Permission, @RequirePermission), publish to Nexus
3. **Phase 3: Linkerd** — install service mesh. mTLS between all pods, retries, circuit breaking, golden metrics (latency/throughput/success rate per service) — all without code changes. Replaces Resilience4j need in gateway.
4. **Phase 4: Admin (user service)** — extract first because it's foundational. Auth, registration, profiles, permissions, captcha. Produces `user.events` that chess and chat will consume.
5. **Phase 5: Chat** — cleanest boundary, distinct scaling profile. Consumes `user.events` + `game.events`.
6. **Phase 6: Chess** — small, well-isolated. Produces `game.events`, consumes `user.events`.

Each phase is independently deployable and testable. The monolith shrinks with each extraction.

## Vagrant Integration Tests

Three Ansible test playbooks validate the decomposition end-to-end:

| Test | File | Checks | When |
|------|------|--------|------|
| `task test:gateway` | `tests/ansible/test-gateway.yml` | Gateway deployment, route passthrough, CORS, NPs, auth flow | After Phase 1 |
| `task test:microservices` | `tests/ansible/test-microservices.yml` | All 4 services, routing, JWT validation, DB isolation, Kafka events, DNS | After Phases 4-6 |
| `task test:linkerd` | `tests/ansible/test-linkerd.yml` | Linkerd install, sidecar injection, mTLS, ServerAuthorization, Viz | After Phase 3 |

**SonarQube:** `test-sonarqube.yml` updated with 7 projects (core, admin, chat, chess, gateway, frontend, infra) + shared "Monitor" quality gate.

**Vagrantfile:** Synced folders added for `../api-gateway`, `../admin`, `../chat`, `../chess` repos.

## Verification

**Phase 1 (Gateway):**
- `task test:gateway` passes in Vagrant
- All existing frontend functionality works through gateway (passthrough to monolith)
- WebSocket `/ws/chat` and chess polling work through gateway
- Rate limiting works at gateway level
- CI pipeline builds and deploys gateway image

**Phase 3 (Linkerd):**
- `task test:linkerd` passes in Vagrant
- `linkerd check` passes
- `linkerd viz dashboard` shows golden metrics for all services
- mTLS active between all pods (`linkerd viz edges`)
- Existing functionality unaffected (sidecars are transparent)

**Per-service extraction:**
- `task test:microservices` passes in Vagrant
- Extracted service starts independently with `./gradlew bootRun`
- Gateway routes to new service correctly
- Tests pass in both the extracted service and the remaining core
- WebSocket connections route correctly (chat to chat service, chess to chess service)
- Linkerd shows traffic flowing between gateway → service
- Network policies still in place as defense-in-depth
- Each service has its own SonarQube project with quality gate passing
