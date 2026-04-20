# Monitor Application

Web page monitoring application that extracts numeric values using regex patterns and tracks them over time. Multi-user with Keycloak SSO authentication.

## CI/CD

Woodpecker CI (`.woodpecker/`), running on the Kubernetes backend in the `woodpecker` namespace. Each pipeline step runs as a real k8s pod — logs captured automatically by Fluent-bit's pod log tail.

**CI** (`ci.yaml`): Push to non-main branches or PRs → parallel test jobs (path-filtered by changed files)
**CD** (`cd.yaml`): Push to main → parallel test jobs → Kaniko image builds → commit image tag to infra repo → Argo CD deploys

Change detection: CI uses Woodpecker's `when.path` webhook filtering. CD uses git-diff against `CI_PREV_COMMIT_SHA` (previous pipeline commit).

Jobs run independently in parallel (only for changed components):
- **backend**: `./gradlew test` + SonarQube analysis (quality gate blocks CI, informational on CD)
- **frontend**: `tsc --noEmit` + `vitest run --coverage` + SonarQube analysis (quality gate blocks CI, informational on CD)
- **infra**: `helm lint` + SonarQube analysis on Dockerfiles/Helm/Ansible YAML
- **update-infra** (CD only): runs after image builds pass, commits image tags to `schnappy/infra` repo on Forgejo

Image builds use Kaniko (unprivileged, no Docker daemon). Deployment via Argo CD GitOps — Woodpecker commits image tags to infra repo, Argo CD detects changes and reconciles Applications. All secrets (app, Forgejo, Woodpecker) managed via Vault + ESO.

### Argo CD (GitOps)

Argo CD manages cluster state from the `schnappy/infra` Git repository on Forgejo. App-of-apps pattern with root Application managing child Applications in `argocd` namespace. UI at `cd.pmon.dev` with Keycloak SSO.

**Infra repo structure:** `clusters/production/` with `argocd/` (Application manifests), `cluster-config/` (raw manifests like ClusterIssuers, NetworkPolicies), and per-component `values.yaml` files.

**Deploy flow:** Push code → Woodpecker builds image → Woodpecker commits new tag to `values.yaml` in infra repo → Argo CD detects change → syncs Application → k8s rolling update.

**Key commands:**
```bash
# Check Argo CD status
ssh ten 'sudo kubectl get applications -n argocd'

# Check sync status
ssh ten 'sudo kubectl get applications -n argocd -o wide'

# Force refresh
ssh ten 'sudo kubectl annotate application schnappy -n argocd argocd.argoproj.io/refresh=hard --overwrite'

# Check Application details
ssh ten 'sudo kubectl describe application schnappy -n argocd'
```

**Installation:** `task deploy:argocd` (Ansible playbook `setup-argocd.yml`)
**UI:** `https://cd.pmon.dev/` (Keycloak SSO, Admins = admin role, Users = readonly)

### Checking CI/CD Status

**Woodpecker UI:** `https://ci.pmon.dev/` (OAuth via Forgejo)

**Woodpecker pipeline pods:**
```bash
# List running pipeline pods
ssh ten 'sudo kubectl get pods -n woodpecker -l pipeline'

# Check server/agent status
ssh ten 'sudo kubectl get pods -n woodpecker'

# Server logs
ssh ten 'sudo kubectl logs woodpecker-server-0 -n woodpecker --tail=50'
```

**Woodpecker API** (via kubectl exec or API token):
```bash
# API token stored as k8s secret in woodpecker namespace
ssh ten 'TOKEN=$(sudo kubectl get secret woodpecker-api-token -n woodpecker -o jsonpath="{.data.token}" | base64 -d) && echo $TOKEN'

# List repos (via kubectl exec into server pod)
ssh ten 'TOKEN=$(sudo kubectl get secret woodpecker-api-token -n woodpecker -o jsonpath="{.data.token}" | base64 -d) && sudo kubectl exec woodpecker-server-0 -n woodpecker -- /bin/woodpecker-cli --server http://localhost:8000 --token "$TOKEN" repo ls'

# List recent pipelines for a repo
ssh ten 'TOKEN=$(sudo kubectl get secret woodpecker-api-token -n woodpecker -o jsonpath="{.data.token}" | base64 -d) && sudo kubectl exec woodpecker-server-0 -n woodpecker -- /bin/woodpecker-cli --server http://localhost:8000 --token "$TOKEN" pipeline ls schnappy/admin'

# View pipeline logs (repo, pipeline number, step name)
ssh ten 'TOKEN=$(sudo kubectl get secret woodpecker-api-token -n woodpecker -o jsonpath="{.data.token}" | base64 -d) && sudo kubectl exec woodpecker-server-0 -n woodpecker -- /bin/woodpecker-cli --server http://localhost:8000 --token "$TOKEN" log show schnappy/admin 4 test'

# Sync repos from Forgejo (after adding new repos)
ssh ten 'TOKEN=$(sudo kubectl get secret woodpecker-api-token -n woodpecker -o jsonpath="{.data.token}" | base64 -d) && sudo kubectl exec woodpecker-server-0 -n woodpecker -- /bin/woodpecker-cli --server http://localhost:8000 --token "$TOKEN" repo sync'

# Activate a repo in Woodpecker
ssh ten 'TOKEN=$(sudo kubectl get secret woodpecker-api-token -n woodpecker -o jsonpath="{.data.token}" | base64 -d) && sudo kubectl exec woodpecker-server-0 -n woodpecker -- /bin/woodpecker-cli --server http://localhost:8000 --token "$TOKEN" repo add schnappy/admin'

# Woodpecker SQLite DB (direct access, server must be scaled down first)
# PVC path on ten: /opt/local-path-provisioner/pvc-a65c80b9-0579-4ae7-a9cd-d3eed872a673_woodpecker_data-woodpecker-server-0/woodpecker.sqlite
ssh ten 'sudo sqlite3 /opt/local-path-provisioner/pvc-a65c80b9-0579-4ae7-a9cd-d3eed872a673_woodpecker_data-woodpecker-server-0/woodpecker.sqlite "SELECT id, full_name, active, forge_remote_id FROM repos;"'
```

**Pipeline logs via ELK** (Woodpecker pipeline steps run as k8s pods — logs captured by Fluent-bit):
```bash
# Search pipeline logs in Elasticsearch (all pipeline pods in woodpecker namespace)
ssh ten 'PW=$(sudo kubectl get secret schnappy-elasticsearch -n schnappy -o jsonpath="{.data.ELASTICSEARCH_PASSWORD}" | base64 -d) && sudo kubectl exec schnappy-elasticsearch-0 -n schnappy -- curl -sf -u "elastic:${PW}" "http://localhost:9200/podlogs-*/_search" -H "Content-Type: application/json" -d "{\"size\":50,\"sort\":[{\"@timestamp\":\"desc\"}],\"query\":{\"bool\":{\"must\":[{\"match\":{\"kubernetes.namespace_name\":\"woodpecker\"}},{\"match_phrase\":{\"log\":\"ERROR\"}}]}}}"' 2>/dev/null | jq '.hits.hits[]._source | {timestamp: .["@timestamp"], pod: .kubernetes.pod_name, log}'

# Search logs for a specific pipeline step (e.g., "push-image" step of admin repo)
ssh ten 'PW=$(sudo kubectl get secret schnappy-elasticsearch -n schnappy -o jsonpath="{.data.ELASTICSEARCH_PASSWORD}" | base64 -d) && sudo kubectl exec schnappy-elasticsearch-0 -n schnappy -- curl -sf -u "elastic:${PW}" "http://localhost:9200/podlogs-*/_search" -H "Content-Type: application/json" -d "{\"size\":100,\"sort\":[{\"@timestamp\":\"desc\"}],\"query\":{\"bool\":{\"must\":[{\"match\":{\"kubernetes.namespace_name\":\"woodpecker\"}},{\"wildcard\":{\"kubernetes.pod_name\":\"*admin*push-image*\"}}]}}}"' 2>/dev/null | jq '.hits.hits[]._source.log'

# Search by time range (last 1 hour) — useful for recent pipeline failures
ssh ten 'PW=$(sudo kubectl get secret schnappy-elasticsearch -n schnappy -o jsonpath="{.data.ELASTICSEARCH_PASSWORD}" | base64 -d) && sudo kubectl exec schnappy-elasticsearch-0 -n schnappy -- curl -sf -u "elastic:${PW}" "http://localhost:9200/podlogs-*/_search" -H "Content-Type: application/json" -d "{\"size\":200,\"sort\":[{\"@timestamp\":\"desc\"}],\"query\":{\"bool\":{\"must\":[{\"match\":{\"kubernetes.namespace_name\":\"woodpecker\"}},{\"range\":{\"@timestamp\":{\"gte\":\"now-1h\"}}}]}}}"' 2>/dev/null | jq '.hits.hits[]._source | {timestamp: .["@timestamp"], pod: .kubernetes.pod_name, log}'

# Kibana UI: https://logs.pmon.dev/ — filter by kubernetes.namespace_name: "woodpecker"
```

**SonarQube API** (via kubectl exec into SQ pod):
```bash
# Quality gate status (token auth)
ssh ten 'TOKEN=$(sudo kubectl get secret schnappy-sonarqube -n schnappy -o jsonpath="{.data.SONARQUBE_TOKEN}" | base64 -d) && sudo kubectl exec deploy/schnappy-sonarqube -n schnappy -- curl -sf -u "${TOKEN}:" "http://localhost:9000/api/qualitygates/project_status?projectKey=schnappy-monitor"' 2>/dev/null | jq .

# Open issues (token auth) — componentKeys: schnappy-monitor, schnappy-frontend, schnappy-infra
ssh ten 'TOKEN=$(sudo kubectl get secret schnappy-sonarqube -n schnappy -o jsonpath="{.data.SONARQUBE_TOKEN}" | base64 -d) && sudo kubectl exec deploy/schnappy-sonarqube -n schnappy -- curl -sf -u "${TOKEN}:" "http://localhost:9000/api/issues/search?componentKeys=schnappy-monitor&resolved=false&ps=50"' 2>/dev/null | jq '.issues[] | {severity, component, line, message}'

# Analysis status (admin auth required)
ssh ten 'PW=$(sudo kubectl get secret schnappy-sonarqube -n schnappy -o jsonpath="{.data.SONARQUBE_TOKEN}" | base64 -d) && sudo kubectl exec deploy/schnappy-sonarqube -n schnappy -- curl -sf -u "admin:${PW}" "http://localhost:9000/api/ce/activity?component=schnappy-monitor&ps=5"' 2>/dev/null | jq .
```

## Quick Start

```bash
# Local development
task dev              # Start all infra + backend + frontend
task dev:infra        # Start only infra (for IDE debugging)
task dev:monitoring   # Include Prometheus & Grafana
task dev:stop         # Stop

# Tests
task test             # Backend + E2E
task test:backend     # Gradle tests
task test:e2e         # Playwright E2E
task test:load        # k6 load test
task test:vault       # Vagrant: Vault + ESO integration
task test:elk         # Vagrant: ELK stack integration
task test:grafana     # Vagrant: Grafana + Prometheus integration
task test:kafka-scylla        # Vagrant: Kafka + ScyllaDB integration
task test:dr          # Vagrant: disaster recovery
task test:keycloak    # Vagrant: Keycloak SSO integration
task test:nexus       # Vagrant: Nexus repository manager
task test:argocd      # Vagrant: Argo CD GitOps integration

# Deploy to target
task deploy:argocd       # Install/update Argo CD (GitOps controller)
task deploy:nexus        # Deploy Nexus repository manager on Pi
task deploy:pi-services  # Forgejo, Keycloak, MinIO, HAProxy on Pis
task deploy:woodpecker   # Deploy Woodpecker CI
task deploy:velero       # Deploy Velero + Backup MinIO
task deploy:full         # Fresh kubeadm + pi-services + argocd + app
task deploy:status    # Check pods

# Backups (velero CLI installed on ten)
velero backup get                              # List backups
velero backup create my-backup                 # Manual full backup
velero backup create --from-schedule velero-schnappy-daily my-snap  # From schedule template
velero restore create --from-backup <name>     # Restore
velero schedule get                            # List schedules

# Tier 0 Bootstrap (pre-GitOps, no Forgejo/ArgoCD needed)
./bootstrap.sh all           # Install cert-manager, ESO, Istio, Velero, cluster-config
./bootstrap.sh cert-manager  # Single component
```

## Architecture

```
Frontend (React) → HAProxy (TCP 443) → Istio Gateway (TLS + routing)
                                        ├─ Admin service (monitor_admin DB) ← auth, users, groups, permissions
                                        ├─ Core app (monitor DB)            ← monitors, RSS, inbox, webhooks, game
                                        ├─ Chat service (monitor_chat DB)   ← channels, messages
                                        └─ Chess service (monitor_chess DB)  ← chess games
                           ↓
                     PostgreSQL (shared instance, separate databases)
                           ↓
                     VictoriaMetrics → Grafana

Admin → Kafka (user.events) → Core app UserEventConsumer → syncs users table
                             → Chat service UserEventConsumer → syncs chat_users table

ELK Stack (namespace: schnappy)
  ├─ Elasticsearch (StatefulSet)  ← log storage + search
  ├─ Fluent-bit (DaemonSet)       ← ships pod logs to ES (podlogs-* index)
  └─ Kibana (Deployment)          ← log visualization at logs.pmon.dev

Chat (namespace: schnappy)
  ├─ Kafka (StatefulSet, KRaft)    ← message bus for chat + user events
  ├─ ScyllaDB (StatefulSet)        ← message persistence (day-bucketed)
  └─ WebSocket (STOMP/SockJS)      ← real-time delivery

Forgejo (namespace: forgejo)       ← git hosting (source code + webhooks)

Woodpecker CI (namespace: woodpecker) ← CI/CD pipeline execution
  ├─ Server (StatefulSet)          ← orchestrates pipelines, UI at ci.pmon.dev
  ├─ Agent (StatefulSet, 2 replicas) ← creates pipeline pods via k8s API
  └─ Pipeline pods (transient)     ← build/test/update-infra steps, logs in podlogs-*

Argo CD (namespace: argocd)        ← GitOps controller
  ├─ argocd-server                 ← UI at cd.pmon.dev, API, Keycloak SSO
  ├─ argocd-repo-server            ← Git clone + Helm template rendering
  ├─ argocd-application-controller ← reconciles Applications → deploys apps
  └─ argocd-redis                  ← caching layer

Nexus Repository Manager (Pi, systemd) ← caching proxy for artifacts + Docker
  ├─ :8081 → Maven Central, npmjs, PyPI (proxy)
  ├─ :8082 → Docker Hub, Elastic, Quay (Docker group)
  └─ Web UI at http://192.168.11.4:8081/
apt-cacher-ng (namespace: schnappy)     ← caching proxy for apt in Docker builds
  └─ :3142 → Debian/Ubuntu mirrors (used by Kaniko via http_proxy build-arg)

MinIO-backup (namespace: velero) ← S3 storage at /mnt/backups/minio
Velero (namespace: velero)       ← k8s backup orchestrator → MinIO
  ├─ schnappy-daily (2 AM)        ← schnappy namespace, 7-day retention
  └─ full-weekly (Sun 3 AM)      ← all namespaces, 30-day retention
```

**Stack:** Java 25, Spring Boot 4.0, Istio sidecar mesh 1.25, React 18, TypeScript, Vite 5, PostgreSQL 17, Kafka 4.2 (KRaft), ScyllaDB 6.2, Recharts, Bucket4j, Rome (RSS), Anthropic SDK, Elasticsearch 8, Fluent-bit, Kibana, kubeadm 1.34, Cilium CNI (kube-proxy replacement), Helm, Ansible, Forgejo, Woodpecker CI, Velero, SpringDoc OpenAPI

## Authentication & Authorization

- **Keycloak SSO:** All authentication via Keycloak at `auth.pmon.dev`, realm `schnappy`
- **JWT validation:** Each service validates Keycloak JWTs locally via `GatewayAuthFilter` (extracts claims from JWT payload)
- Frontend uses Keycloak access tokens directly (`Authorization: Bearer` header, PKCE)
- No cookies, no CSRF — Bearer tokens work for web, mobile, and CLI
- Each service provisions users on first authenticated request via `UserProvisioner` interface in `GatewayAuthFilter` (5min per-UUID cache). Admin service calls `UserSyncService.ensureUser()` directly; other services call admin's `POST /auth/ensure-user` if UUID not in local user table
- Istio gateway routes requests to backend services via HTTPRoutes; each service's `GatewayAuthFilter` extracts `sub` (UUID) and permissions from JWT payload directly
- Registration and password reset handled by Keycloak (self-registration enabled)
- Permissions mapped as Keycloak realm roles: `PLAY`, `CHAT`, `EMAIL`, `METRICS`, `MANAGE_USERS`
- No shared library — each service has its own `security/` package with `GatewayAuthFilter`, `GatewayUser`, `Permission`, `RequirePermission`, `PermissionInterceptor`, `UserProvisioner`
- User ID resolved from UUID via local user table (Envoy passes UUID from Keycloak `sub` claim as `X-User-UUID` header)

### Keycloak

- **Realm:** `schnappy` at `https://auth.pmon.dev`
- **Clients:** `app` (public, PKCE), `forgejo` (confidential), `grafana` (confidential), `k6-smoke` (confidential, service account)
- **Realm roles:** PLAY, CHAT, EMAIL, METRICS, MANAGE_USERS + composites (Users, Admins)
- **Default role:** Users (METRICS + PLAY)
- **Token lifetimes:** access=5min, refresh=30min, SSO session=10h
- **Custom theme:** `schnappy/keycloak-theme` Docker image (PF5, dark gradient)
- **Declarative config:** Realm JSON in ConfigMap, init container templates secrets, `--import-realm` on first deploy
- **Admin console:** `auth.pmon.dev/admin/` (permanent admin user)

### Istio Sidecar Mesh

Istio classic sidecar mode v1.25 provides per-pod mTLS and L7 routing. Only `schnappy` namespace is enrolled in the mesh (`istio.io/rev=default` label).

- **Components:** istiod (control plane), istio-cni (iptables redirection), per-pod sidecar proxies (classic mode, `ENABLE_NATIVE_SIDECARS=false`)
- **CNI:** Cilium with `socketLB.hostNamespaceOnly=true` for Istio compatibility (prevents eBPF DNAT in pod namespaces)
- **Gateway:** Istio Gateway API in schnappy namespace with `externalIPs: [192.168.11.2]`
- **Routing:** HTTPRoutes (Gateway API) for pmon.dev, ci, cd, grafana, logs, reports, sonar (auth + git on Pi Caddy)
- **TLS:** Wildcard cert `*.pmon.dev` via cert-manager DNS-01 (Porkbun webhook), terminated at Istio gateway
- **mTLS:** STRICT PeerAuthentication namespace-wide; per-service AuthorizationPolicies with SPIFFE identity; port-level PERMISSIVE for MinIO (9000) and Mimir (9009)
- **Cross-namespace routing:** ReferenceGrants for argocd and woodpecker namespaces
- **Helm chart:** `schnappy-mesh` — Gateway, HTTPRoutes, ServiceAccounts, PeerAuthentication, AuthorizationPolicies, Certificates, ReferenceGrants
- **Jobs:** All Job templates include `curl -X POST localhost:15020/quitquitquit` to terminate sidecar after completion
- **Init containers:** Removed `wait-for-postgres` init containers (incompatible with STRICT mTLS; Spring Boot retries on its own)

**Public paths** (no JWT required): `/api/auth/approval-mode`, `/api/webhooks/**`, `/api/health`, `/api/permissions/required`, `/api/actuator/**`, `/api/swagger-ui/**`

### Permissions (RBAC)

- **Permissions:** `PLAY`, `CHAT`, `EMAIL`, `METRICS`, `MANAGE_USERS` (Keycloak realm roles)
- **Default role:** Users (METRICS, PLAY) — assigned to new registrations
- **Composite roles:** Admins (all five permissions)
- Permissions extracted from Keycloak `realm_access.roles` claim by each service's `GatewayAuthFilter` (from JWT payload)
- Enforcement via `@RequirePermission` AOP annotation + `PermissionInterceptor` in each service
- All services read from `GatewayUser` (populated from gateway headers + JWT payload)

| Service | Controller | Permission |
|---|---|---|
| Core app | `MonitorController` | METRICS |
| Core app | `RssFeedController` | METRICS |
| Core app | `InboxController` | EMAIL |
| Core app | `GameController` | PLAY |
| Chat | `ChatController` | CHAT |
| Chess | `ChessController` | PLAY |
| Admin | `AdminController` | MANAGE_USERS |

## API Endpoints

```
# Auth (service-initiated, not user-facing)
POST /api/auth/ensure-user               # Called on first authenticated request — provisions user from Keycloak claims

# Page Monitoring (authenticated, user-scoped)
GET  /api/monitor/pages                    # List pages
GET  /api/monitor/results/{page}           # Results (paginated)
GET  /api/monitor/results/{page}/latest    # Latest result
POST /api/monitor/check/{page}             # Manual trigger
GET  /api/monitor/stats/{page}             # 24h statistics

# Page Monitor CRUD (authenticated)
GET    /api/monitor/config                 # List user's page monitors
POST   /api/monitor/config                 # Create page monitor
PUT    /api/monitor/config/{id}            # Update page monitor
DELETE /api/monitor/config/{id}            # Delete page monitor

# RSS Keyword Monitoring (authenticated, user-scoped)
GET  /api/rss/feeds                        # List feeds
GET  /api/rss/results/{feed}               # Results (paginated)
GET  /api/rss/results/{feed}/chart-data    # Multi-line chart data
POST /api/rss/check/{feed}                 # Manual trigger
POST /api/rss/generate-collections         # AI-generate collections from feed + prompt

# RSS Feed CRUD (authenticated)
GET    /api/rss/config                     # List user's RSS monitors
POST   /api/rss/config                     # Create RSS monitor
PUT    /api/rss/config/{id}                # Update RSS monitor
DELETE /api/rss/config/{id}                # Delete RSS monitor

# Inbox (authenticated, EMAIL permission)
GET  /api/inbox/emails                     # List received emails (paginated)
GET  /api/inbox/emails/{id}                # Single email detail

# Auth (public)
GET  /api/auth/approval-mode              # { mode } — for frontend messaging
# Auth (authenticated)
GET  /api/auth/approval-status            # { status, reason } — for PendingApproval polling

# Admin (authenticated, MANAGE_USERS permission)
GET    /api/admin/users                    # List all users with groups/permissions
PUT    /api/admin/users/{id}/enabled       # Block/unblock { enabled: true/false }
GET    /api/admin/users/{id}/groups        # List user's groups
PUT    /api/admin/users/{id}/groups        # Set user's groups { groupIds: [1,2] }
GET    /api/admin/groups                   # List all groups with permissions
POST   /api/admin/groups                   # Create group { name, description, permissions }
PUT    /api/admin/groups/{id}              # Update group
DELETE /api/admin/groups/{id}              # Delete group (cannot delete Admins)
GET    /api/admin/approvals                # List pending registration approvals
POST   /api/admin/approvals/{id}/approve   # Approve registration
POST   /api/admin/approvals/{id}/decline   # Decline registration

# Chat (authenticated, CHAT permission)
GET    /api/chat/channels                    # List user's channels
POST   /api/chat/channels                    # Create channel { name, type }
POST   /api/chat/channels/{id}/join          # Join channel
POST   /api/chat/channels/{id}/leave         # Leave channel
GET    /api/chat/channels/{id}/messages      # Messages (paginated, ?limit=50)
POST   /api/chat/channels/{id}/messages      # Send message { content, parentMessageId }
POST   /api/chat/channels/{id}/read          # Mark as read
# WebSocket: STOMP over SockJS at /api/ws/chat
# Subscribe: /topic/channel.{channelId}
# Send: /app/chat.send { channelId, content, parentMessageId }

# E2E Encryption (authenticated, CHAT permission, requires chat.e2eEnabled)
GET    /api/chat/keys                          # Get user's keys (public + encrypted private)
POST   /api/chat/keys                          # Upload key pair (first time)
PUT    /api/chat/keys                          # Re-encrypt private key (password change)
GET    /api/chat/keys/public?userIds=1,2,3     # Batch fetch public keys
GET    /api/chat/channels/{id}/keys            # Get channel key bundles for current user
POST   /api/chat/channels/{id}/keys            # Set encrypted channel keys for members
POST   /api/chat/channels/{id}/keys/rotate     # Rotate key (new version, wrap for members)

# Webhooks (public, signature-verified)
POST /api/webhooks/resend                  # Resend inbound email webhook

# System (public)
GET  /api/health                           # Health check
GET  /api/permissions/required             # Permission-to-feature mapping
GET  /api/actuator/health                  # Spring actuator health
GET  /api/actuator/prometheus              # Metrics

# Swagger/OpenAPI (all services)
GET  /api/swagger-ui.html                 # Swagger UI (per-service, via Envoy routing)
```

## Configuration

Monitor/feed configuration is stored in the database and managed per-user via the `/monitors` UI page or CRUD API endpoints. The `application.yml` only contains infrastructure settings:

```yaml
# application.yml
monitor:
  auth:
    approval:
      mode: ${REGISTRATION_APPROVAL_MODE:ai}    # ai, admin, or skip
      criteria: ${REGISTRATION_APPROVAL_CRITERIA:}  # AI evaluation prompt
      default-group: ${REGISTRATION_APPROVAL_DEFAULT_GROUP:Users}
  enabled: true
  http:
    connect-timeout: 10s
    read-timeout: 30s
    user-agent: "Mozilla/5.0 ..."
  ai:
    enabled: ${AI_ENABLED:false}
    api-key: ${ANTHROPIC_API_KEY:}
    model: ${AI_MODEL:claude-sonnet-4-5-20250929}
  mail:
    enabled: ${MAIL_ENABLED:false}
    from-address: ${MAIL_FROM:noreply@example.com}
    app-url: ${APP_URL:http://localhost:3000}
  rate-limit:
    enabled: true
    requests-per-minute: 300
  webhook:
    resend:
      enabled: ${RESEND_WEBHOOK_ENABLED:false}
      signing-secret: ${RESEND_WEBHOOK_SECRET:}
      api-key: ${RESEND_API_KEY:}
```

## Directory Structure

```
monitor/
├── .woodpecker/                # CI/CD (Woodpecker CI)
│   ├── ci.yaml                # Test on push to non-main
│   └── cd.yaml                # Test + build + deploy on push to main
├── backend/                    # Spring Boot API
│   └── src/main/java/         # Java source
└── CLAUDE.md
```

Helm chart, deployment automation, frontend, games, tests, and infrastructure config live in the `schnappy/platform` repo.

## Key Classes (Core App — monitor repo)

| File | Purpose |
|------|---------|
| `SecurityConfig.java` | Spring Security config — trusts gateway headers |
| `GatewayAuthFilter.java` | Reads X-User-* headers + JWT payload, populates SecurityContext |
| `GatewayUser.java` | User identity record from gateway headers + JWT |
| `PermissionInterceptor.java` | AOP aspect enforcing `@RequirePermission` |
| `UserEventConsumer.java` | Kafka consumer: syncs users from admin service + creates default monitors |
| `MonitorController.java` | Page monitoring REST API + CRUD |
| `RssFeedController.java` | RSS monitoring REST API + CRUD |
| `PageMonitorService.java` | HTTP fetch & regex matching |
| `RssFeedMonitorService.java` | RSS parsing & keyword counting |
| `MonitorScheduler.java` | Dynamic CRON scheduling from DB |
| `AiCollectionGeneratorService.java` | AI-powered RSS collection generation (Anthropic SDK) |
| `WebhookController.java` | Resend inbound email webhook (public, Svix-verified) |
| `InboxController.java` | Received email listing (authenticated, user-scoped) |
| `GameController.java` | Slot machine game |
| `UserProvisioner.java` | Functional interface for user auto-provisioning |
| `UserProvisionerAdapter.java` | Calls admin `POST /auth/ensure-user` if UUID not in local users table |
| `GlobalExceptionHandler.java` | Catch-all exception handler (prevents stack trace leaks) |

### Key Classes (Admin Service — admin repo)

| File | Purpose |
|------|---------|
| `SecurityConfig.java` | Spring Security config — trusts gateway headers |
| `GatewayAuthFilter.java` | Reads X-User-* headers + JWT payload, populates SecurityContext |
| `GatewayUser.java` | User identity record from gateway headers + JWT |
| `PermissionInterceptor.java` | AOP aspect enforcing `@RequirePermission` |
| `UserProvisioner.java` | Functional interface for user auto-provisioning |
| `UserProvisionerAdapter.java` | Implements UserProvisioner, delegates to UserSyncService |
| `AuthController.java` | User provisioning endpoint (`POST /auth/ensure-user`) |
| `UserSyncService.java` | Ensure-user provisioning (create/update user from Keycloak claims) |
| `AdminController.java` | User management, group CRUD, registration approvals |
| `AdminService.java` | Admin business logic + safety checks |
| `RegistrationApprovalService.java` | Approval orchestration (skip/admin/ai) |
| `UserEventProducer.java` | Publishes USER_CREATED/ENABLED/DISABLED to Kafka |
| `KeycloakSyncService.java` | Syncs user roles & enabled status to Keycloak via Admin REST API |
| `KeycloakAdminConfig.java` | Keycloak Admin Client bean factory (conditional on `monitor.keycloak.enabled`) |

### Key Classes (Chat Service — chat repo)

| File | Purpose |
|------|---------|
| `SecurityConfig.java` | Spring Security config — trusts gateway headers |
| `GatewayAuthFilter.java` | Reads X-User-* headers + JWT payload, populates SecurityContext |
| `GatewayUser.java` | User identity record from gateway headers + JWT |
| `PermissionInterceptor.java` | AOP aspect enforcing `@RequirePermission` |
| `ChatController.java` | Channel and message REST API |
| `ChatService.java` | Chat business logic |
| `ChatMessageConsumer.java` | Kafka consumer: persists messages to ScyllaDB + WebSocket delivery |
| `UserEventConsumer.java` | Kafka consumer: syncs users from admin service to chat_users table |

### Key Classes (Chess Service — chess repo)

| File | Purpose |
|------|---------|
| `SecurityConfig.java` | Spring Security config — trusts gateway headers |
| `GatewayAuthFilter.java` | Reads X-User-* headers + JWT payload, populates SecurityContext |
| `GatewayUser.java` | User identity record from gateway headers + JWT |
| `PermissionInterceptor.java` | AOP aspect enforcing `@RequirePermission` |
| `ChessController.java` | Chess game REST API |

## DB Schema

```
users (id, uuid, email, enabled, last_path, created_at)
groups (id, name, description, created_at)
group_permissions (id, group_id, permission)
user_groups (id, user_id, group_id)
page_monitors (id, user_id, name, url, pattern, cron, enabled, created_at, updated_at)
rss_feed_monitors (id, user_id, name, url, cron, fetch_content, max_articles, enabled, ...)
rss_collections (id, feed_monitor_id, name)
rss_metric_defs (id, collection_id, name, keywords)
monitor_results (id, user_id, page_name, url, pattern, extracted_value, ...)
rss_feed_results (id, user_id, feed_name, url, article_count, ...)
rss_metric_counts (id, result_id, collection_name, metric_name, count)
received_emails (id, user_id, resend_email_id, from_address, to_addresses, subject, body_html, body_text, received_at, created_at)
registration_approvals (id, user_id, status, decided_by, decision_reason, created_at, decided_at)
-- Chat service (monitor_chat DB)
chat_users (id, uuid, email, enabled, created_at, updated_at)
channels (id, uuid, name, type, system, encrypted, current_key_version, created_by, created_at)
channel_members (id, channel_id, user_id, joined_at, last_read_at)
user_keys (id, user_id, public_key, encrypted_private_key, pbkdf2_salt, pbkdf2_iterations, key_version, created_at, updated_at)
channel_key_bundles (id, channel_id, user_id, key_version, encrypted_channel_key, wrapper_public_key, created_at)

-- ScyllaDB (keyspace: chat)
messages_by_channel ((channel_id, bucket), message_id, user_id, username, content, parent_message_id, edited, deleted, message_type, metadata)
messages_by_user (user_id, message_id, channel_id, bucket, content)
reactions_by_message ((channel_id, bucket, message_id), emoji, user_id, username)
attachments_by_message ((channel_id, bucket, message_id), attachment_id, url, filename, content_type, size_bytes)
```

## Frontend Pages

| Route | Component | Permission | Purpose |
|-------|-----------|------------|---------|
| `/` | Dashboard | METRICS | Overview with charts |
| `/page/:name` | PageDetail | METRICS | Stats, history, manual trigger |
| `/rss` | RssDashboard | METRICS | RSS feeds overview |
| `/rss/:feedName` | RssFeedDetail | METRICS | RSS feed details |
| `/monitors` | MonitorConfig | METRICS | CRUD for page & RSS monitors |
| `/chat` | Chat | CHAT | Channel list + messaging |
| `/chat/:channelId` | Chat | CHAT | Specific channel view |
| `/inbox` | Inbox | EMAIL | Received emails (via Resend webhook) |
| `/game` | Game | PLAY | Game |
| `/admin` | Admin | MANAGE_USERS | User & group management |

## Deployment

### Production

```bash
# All secrets managed via Vault KV → ESO → k8s Secrets. Single source of truth.
# .env provides initial values for Vault seeding only.

# Configure in .env (Vault seed + deploy-time)
TARGET_HOST=192.168.11.2
TARGET_USER=sm
TARGET_SSH_KEY=/home/sm/.ssh/id_ed25519
FORGEJO_ADMIN_USER=admin            # Seeded to Vault → ESO → forgejo-admin secret
FORGEJO_ADMIN_PASSWORD=<secure>
FORGEJO_ADMIN_EMAIL=admin@pmon.dev
VELERO_MINIO_ACCESS_KEY=velero-admin  # Backup MinIO
VELERO_MINIO_SECRET_KEY=<secure>
PORKBUN_API_KEY=pk1_...              # DNS-01 cert validation
PORKBUN_SECRET_KEY=sk1_...

# One-time: Seed all secrets into Vault (from .env on ten)
# set -a && source .env && set +a
# ansible-playbook playbooks/setup-vault.yml -e @vars/vault.yml \
#   -e "vault_seed_secrets=true" -e "vault_seed_token=$VAULT_ROOT_TOKEN"

# Deploy
task deploy:argocd       # Install/update Argo CD (GitOps controller)
task deploy:full         # Fresh kubeadm + pi-services + argocd + app
task deploy:pi-services  # Forgejo, Keycloak, MinIO, HAProxy on Pis
task deploy:woodpecker   # Deploy Woodpecker CI
task deploy:velero       # Deploy Velero + backups
task deploy:status       # Check status
task deploy:undeploy  # Remove (keeps data)
```

**Access:** `https://pmon.dev/` | Grafana: `https://grafana.pmon.dev/` | Logs: `https://logs.pmon.dev/` | CI: `https://ci.pmon.dev/`

**Build & deploy flow (CD pipeline + Argo CD GitOps):**
- Push to main triggers Woodpecker CD pipeline
- Incremental: only rebuilds changed components (backend/frontend)
- Docker images built with Kaniko and pushed to Forgejo container registry (`git.pmon.dev`)
- `update-infra` step commits new image tags to `values.yaml` in `schnappy/infra` repo on Forgejo
- Argo CD detects change in infra repo, syncs Application
- Rolling update with new images

**Production settings:**
- Containerd and kubeadm data on NVMe (`/mnt/storage`)
- PVCs via local-path-provisioner at `/opt/local-path-provisioner`
- Network policies enabled (default-deny with explicit allow rules)
- Monitoring stack disabled (enable with `prometheus.enabled: true`)

**Networking:**
- Single interface: `enp1s0f0` (192.168.11.0/24) on unmanaged switch
- kubeadm cluster with Cilium CNI (kube-proxy replacement, eBPF), `--pod-network-cidr=10.42.0.0/16`, `--service-cidr=10.43.0.0/16`
- Istio gateway service with `externalIPs: [192.168.11.2]` — directly reachable on node IP ports 80/443
- Router port-forwards 80/443 from public IP to 192.168.11.2
- **DNS:** `*.pmon.dev` resolved via upstream DNS (public A records → 192.168.11.2). CoreDNS `hosts` plugin only for internal-only entries (vault-pi). No `*.pmon.dev` entries in CoreDNS (breaks SOA resolution for cert-manager DNS-01)
- **TLS:** Wildcard cert `*.pmon.dev` via cert-manager DNS-01 (Porkbun webhook), single `letsencrypt-dns` ClusterIssuer
- **No AAAA records** — server does not serve IPv6 for the app

## Performance Tuning (10-core / 64GB target)

**JVM:**
- Virtual threads enabled (`spring.threads.virtual.enabled: true`)
- Heap: `-Xmx2g -XX:+UseZGC` (monitor), `-Xmx1g` (admin/chat/chess) via `JAVA_OPTS` env var in Helm deployment (configurable via `app.javaOpts`)
- Entrypoint: `sh -c "exec java $JAVA_OPTS -jar app.jar"`

**HikariCP:** `maximum-pool-size: 20`, `minimum-idle: 5` (configurable via `app.hikari.*`)

**PostgreSQL:** custom args in deployment (configurable via `postgres.*`)
- `shared_buffers=512MB`
- `effective_cache_size=2GB`
- `work_mem=32MB`
- `maintenance_work_mem=128MB`
- `max_parallel_workers_per_gather=4`
- `max_parallel_workers=6`
- `max_worker_processes=10`
- `effective_io_concurrency=200` (NVMe)
- `random_page_cost=1.1` (NVMe)

**Resource limits (production):**

| Pod | CPU req/limit | Memory req/limit |
|-----|---------------|------------------|
| Backend (monitor) | 200m / 4000m | 2Gi / 4Gi |
| Admin | 100m / 2000m | 1Gi / 2Gi |
| Chat | 100m / 2000m | 1Gi / 2Gi |
| Chess | 100m / 2000m | 1Gi / 2Gi |
| Frontend (site) | 100m / 2000m | 64Mi / 256Mi |
| PostgreSQL | 250m / 4000m | 1Gi / 2Gi |
| Redis | 100m / 1000m | 64Mi / 512Mi |
| Kafka | 250m / 2000m | 1536Mi / 2Gi |
| ScyllaDB | 200m / 4000m | 2Gi / 4Gi |
| Elasticsearch | 250m / 4000m | 2Gi / 4Gi |
| Kibana | 100m / 1000m | 1Gi / 2Gi |
| Fluent-bit | 100m / 1000m | 128Mi / 512Mi |
| VictoriaMetrics | 100m / 2000m | 256Mi / 2Gi |
| Keycloak | 200m / 2000m | 1Gi / 2Gi |
| SonarQube | 200m / 2000m | 2Gi / 4Gi |
| Forgejo | 100m / 1000m | 256Mi / 1Gi |
| Woodpecker Server | 100m / 500m | 128Mi / 256Mi |
| Woodpecker Agent (x2) | 100m / 500m | 128Mi / 256Mi |
| Backup MinIO | 50m / 500m | 256Mi / 1Gi |
| Velero | 100m / 1000m | 128Mi / 512Mi |
| apt-cacher-ng | 25m / 200m | 32Mi / 128Mi |

**Rate limiting:** Not currently active (Envoy Gateway rate limiter removed during Istio migration; Bucket4j previously removed).

### Local Development

```bash
task dev              # http://localhost:3000 (all infra + backend + frontend)
task dev:infra        # Start only infra (postgres, redis, kafka, scylla, minio) for IDE debugging
task dev:monitoring   # + Prometheus :9090, Grafana :3001
task dev:logs         # Tail logs
task dev:clean        # Stop + remove volumes
```

## Build Info

Header tooltip (hover over title) shows separate FE and BE version info:
- Format: `FE: abc1234 · Feb 1, 14:30` / `BE: def5678 · Feb 7, 09:30`
- FE info baked in at compile time via Vite (`VITE_GIT_HASH`, `VITE_BUILD_TIME`)
- BE info baked in at compile time via Spring Boot build-info plugin (`BuildProperties` bean)
- BE env vars `GIT_HASH` and `BUILD_TIME` passed via Helm `--set` during deploy

## Helm Charts

Located in the `schnappy/platform` repo under `helm/`. Split into 5 charts by lifecycle, all deploying to namespace `schnappy`. Each chart uses `nameOverride: schnappy` so resource names are identical across charts.

| Chart | Path | Argo CD App | Changes when |
|---|---|---|---|
| `schnappy` | `helm/schnappy` | `schnappy` | Code pushes (daily) — app, admin, chat, chess, envoy gateway, site, game |
| `schnappy-data` | `helm/schnappy-data` | `schnappy-data` | Version bumps (monthly) — postgres, redis, kafka, scylla, minio, apt-cache |
| `schnappy-auth` | `helm/schnappy-auth` | `schnappy-auth` | Auth config (rare) — keycloak |
| `schnappy-observability` | `helm/schnappy-observability` | `schnappy-observability` | Dashboard/config (weekly) — ELK, prometheus, grafana, alertmanager, kube-state-metrics |
| `schnappy-sonarqube` | `helm/schnappy-sonarqube` | `schnappy-sonarqube` | QG/rule changes (rare) — sonarqube + sonarqube-postgres |

**Cross-chart design:** All pods have `app.kubernetes.io/part-of: schnappy` label. Network policies use `nameOverride`-derived selector labels for cross-chart pod references. Default-deny NP is a raw manifest in `cluster-config/` (namespace-wide `podSelector: {}`).

**CD pipelines:** All 8 repos still target `clusters/production/schnappy/values.yaml` (the core app chart's values file). Only image tags live there; data/auth/observability/sonarqube values files are updated manually.

**Infra repo values:** `clusters/production/schnappy/values.yaml`, `schnappy-data/values.yaml`, `schnappy-auth/values.yaml`, `schnappy-observability/values.yaml`, `schnappy-sonarqube/values.yaml`

## Load Testing

**Smoke tests** (k6): Go through Envoy Gateway, validate full request path.
**Load/stress tests** (Hyperfoil): Bypass Envoy, hit backend services directly (monitor, chat, chess). Vert.x/Netty async engine avoids coordinated omission.

```bash
# k6 smoke test (via Envoy Gateway — validates full path)
kubectl create job k6-smoke-manual --from=cronjob/schnappy-k6-smoke -n schnappy

# Hyperfoil load test (direct to backends, daily at 3 AM)
kubectl create job hf-load --from=cronjob/schnappy-hyperfoil-load -n schnappy

# Hyperfoil stress test (direct to backends, manual trigger)
kubectl create job hf-stress --from=cronjob/schnappy-hyperfoil-stress -n schnappy
```

- **Hyperfoil image:** `quay.io/hyperfoil/hyperfoil:0.28.0` (standalone mode, `/deployment/bin/run.sh`)
- **Multi-host:** monitor:8080, chat:8080, chess:8080 — `authority` header selects target per request
- **Load profile:** open-model, ramp 5→50 users/s (1m) + sustained 50 users/s (3m) = 5min
- **Stress profile:** closed-model (`always` phase), 200→500→1000→2000 concurrent users, 90s each = 6min
- **Auth:** Service account `k6-smoke` (client_credentials grant), JWT decoded in shell for X-User-UUID/X-User-Email headers (Hyperfoil sends these to bypass Envoy's claimToHeaders)
- **JVM:** `-Xmx256m -XX:+UseZGC` (load), `-Xmx512m -XX:+UseZGC` (stress) via JAVA_OPTS env var
- **Reports:** HTML report generated to `/tmp/report/` inside the pod
- **Network policies:** Hyperfoil pods have egress to backend services + Keycloak; backend NPs (app, admin, chat, chess) + Keycloak NP allow ingress from hyperfoil-load/stress pods
- **Prometheus integration:** Not yet — Hyperfoil lacks native remote write. Future: pushgateway or custom exporter

## Troubleshooting

**Helm stuck:** `helm rollback schnappy <revision> -n schnappy`

**Pod not updating:** Images use `pullPolicy: Never`, so Ansible does `rollout restart` after deploy.

**Empty dashboard:** Fresh deploy = empty DB. Register a user, then add monitors via `/monitors` page.

**kubectl:** kubeadm cluster, `KUBECONFIG=/etc/kubernetes/admin.conf` or `~/.kube/config`

## AI Collection Generation

When configuring RSS feed monitors, users can click "Generate with AI" to auto-generate collections, metrics, and keywords from a natural language prompt. The system fetches sample articles from the feed, sends titles+descriptions to Claude, and returns structured collections that are appended to the form for review before saving.

- **Feature-flagged:** `monitor.ai.enabled` (disabled by default, no API key required unless enabled)
- **Anthropic SDK:** `com.anthropic:anthropic-java:2.15.0` with structured output (`outputConfig`)
- **Model:** Configurable, defaults to Sonnet; production uses Haiku (`claude-haiku-4-5-20251001`) for cost
- **Cost:** ~$0.01/generation (Sonnet), ~$0.0005/generation (Haiku)
- **No recurring cost:** AI is only used at config time, cron checks use local keyword matching
- **Endpoint:** `POST /api/rss/generate-collections` with `{ url, prompt }` body
- **Key files:** `AiProperties.java`, `AiCollectionGeneratorService.java`, `ai-secret.yaml`

## Inbound Email (Resend Webhook)

Receive inbound emails via Resend webhook, store them in the database, and display in the `/inbox` page. Emails are matched to users by comparing the `to` address against registered user emails.

- **Feature-flagged:** `monitor.webhook.resend.enabled` (disabled by default)
- **Webhook URL:** `POST /api/webhooks/resend` (public, Svix signature-verified)
- **Svix verification:** HMAC-SHA256 via `com.svix:svix:1.56.0`; signing secret from Resend dashboard (`whsec_...`)
- **Body fetch:** Webhook payload only includes metadata; full body fetched from `GET https://api.resend.com/emails/receiving/{id}` using full-access API key
- **User matching:** `to` address matched against `users.email`; supports `Name <email>` format; unmatched emails stored with `userId=null`
- **Idempotent:** Deduplicates by `resend_email_id` (unique constraint)
- **Rate limit exempt:** Webhook path skips rate limiting (signature verification is sufficient)
- **Key files:** `WebhookController.java`, `InboxController.java`, `ResendWebhookService.java`, `WebhookProperties.java`, `ReceivedEmail.java`, `webhook-secret.yaml`
- **Two API keys:** Sending key for SMTP (`MAIL_PASSWORD`), full-access key for receiving API (`RESEND_API_KEY`)

## Forgejo (Self-Hosted Git Forge)

Self-hosted Git forge at `https://git.pmon.dev/` for source hosting. CI/CD handled by Woodpecker CI.

- **Namespace:** `forgejo`
- **Chart:** `oci://code.forgejo.org/forgejo-helm/forgejo` (v16.2.0)
- **Database:** SQLite (single-node, no extra pod)
- **Image:** Rootless, SSH disabled (HTTPS only)
- **Ingress:** `git.pmon.dev` via Istio Gateway + cert-manager TLS
- **Secrets:** forgejo admin seeded by `seed-vault-secrets.yml`, consumed at install time
- **DB:** Patroni-backed Postgres via HAProxy on localhost:5000 on each Pi
- **Key files:** `deploy/ansible/playbooks/setup-pi-services.yml` — Forgejo bare-metal on Pis

## Woodpecker CI

CI/CD pipeline execution via Woodpecker CI with Kubernetes backend. Pipelines triggered by Forgejo webhooks.

- **Namespace:** `woodpecker`
- **Server:** StatefulSet, UI at `https://ci.pmon.dev/` (OAuth via Forgejo)
- **Agent:** StatefulSet (2 replicas), creates pipeline pods via k8s API
- **Backend:** Kubernetes — each step runs as a real pod in `woodpecker` namespace
- **Image builds:** Kaniko (unprivileged, no Docker daemon needed)
- **Deploy step:** `update-infra` commits image tags to `values.yaml` in `schnappy/infra` repo; Argo CD handles actual deployment
- **Secrets:** All via Vault + ESO (single source of truth):
  - `woodpecker-ci-secrets` — ESO from `secret/schnappy/forgejo` (registry_user, registry_token) + `secret/schnappy/woodpecker-ci` (infra_repo_token, sonar, nexus, nvd)
  - `woodpecker-forgejo-secret` — ESO from `secret/schnappy/woodpecker-forgejo` (client_id, client_secret)
  - `woodpecker-default-agent-secret` — ESO from `secret/schnappy/woodpecker` (agent-secret)
  - ExternalSecret manifests in `clusters/production/cluster-config/` (Argo CD cluster-config Application)
- **Pipeline cancellation:** Disabled (`WOODPECKER_PIPELINE_CANCEL_RUNNING=false`) — new pushes queue instead of cancelling
- **Agent config:** `CONNECT_RETRY_COUNT=30`, `MAX_WORKFLOWS=1` per agent
- **Key files:** `.woodpecker/ci.yaml`, `.woodpecker/cd.yaml`, `deploy/ansible/playbooks/setup-woodpecker.yml` (platform repo)
- **API token:** Stored as k8s secret `woodpecker-api-token` in `woodpecker` namespace
- **CLI:** `/bin/woodpecker-cli` inside the `woodpecker-server-0` pod (exec into it)
- **SQLite DB:** PVC at `/opt/local-path-provisioner/pvc-a65c80b9-0579-4ae7-a9cd-d3eed872a673_woodpecker_data-woodpecker-server-0/woodpecker.sqlite` on ten
- **Repo management caveats:**
  - `repo rm` does soft-delete only (sets `active=0`, keeps DB row). UNIQUE constraint on `full_name` blocks re-adding
  - To fully remove: scale down server → delete row from SQLite → scale back up
  - To re-activate with new Forgejo repo ID: update `forge_remote_id` + `active=1` in SQLite
  - Always use `repo sync` + `repo add` (not DB manipulation) for proper webhook token generation
- **Pipeline logs:** Captured by Fluent-bit into `podlogs-*` ES index (pods run in `woodpecker` namespace). Query via ELK or Kibana at `logs.pmon.dev`
- **Registered repos:** schnappy/monitor (id=1), schnappy/admin (id=2), schnappy/chat (id=3), schnappy/chess (id=4), schnappy/site (id=6), schnappy/game-scp (id=7), schnappy/keycloak-theme (id=10). api-gateway (id=5) archived/deactivated

## Nexus Repository Manager (Pi)

Caching proxy for Maven, npm, PyPI, and Docker on the Pi (192.168.11.4). Replaces the 3 separate `distribution/distribution` registry mirrors.

- **Host:** Pi (192.168.11.4), systemd service, Nexus OSS 3.90.1
- **JVM:** OpenJDK 21, `-Xms512m -Xmx2g`, data at `/mnt/data/nexus`
- **Port 8081:** Web UI + Maven/npm/PyPI proxy APIs
- **Port 8082:** Docker registry HTTP connector (Docker group)
- **Repositories:** `docker-hub`, `docker-elastic`, `docker-quay` (proxies) → `docker-group` (group on 8082); `maven-central` → `maven-public`; `npm-registry` → `npm-public`; `pypi-proxy` → `pypi-public`; `gradle-distributions` (raw proxy → `https://services.gradle.org/distributions/`)
- **CI integration:** `NEXUS_URL` and `NPM_CONFIG_REGISTRY` from Woodpecker secrets; `build.gradle` uses Nexus when `NEXUS_URL` env var is set, falls back to Maven Central otherwise
- **Gradle wrapper:** All repos' `gradle-wrapper.properties` point to `http://nexus.pmon.dev:8081/repository/gradle-distributions/` for cached Gradle distribution downloads
- **EULA:** Community Edition requires EULA acceptance via REST API (GET disclaimer, POST back with `accepted: true`)
- **Cleanup:** 30-day retention policy for cached artifacts
- **Decommissions:** Old registry mirrors (ports 5000-5002) stopped and disabled
- **Key files:** `deploy/ansible/playbooks/setup-nexus.yml` (platform repo)
- **Test:** `task test:nexus` (Vagrant integration test)

## apt-cacher-ng (k8s)

Caching proxy for Debian/Ubuntu apt packages, used by Kaniko during Docker image builds. Runs in the schnappy namespace.

- **Image:** `git.pmon.dev/schnappy/apt-cacher-ng:1.0` (own build from `infra/apt-cache/Dockerfile`, Debian trixie-slim)
- **Port 3142:** apt caching proxy
- **CI integration:** Kaniko passes `--build-arg http_proxy=http://schnappy-infra-apt-cache.schnappy-infra.svc.cluster.local:3142` for backend image builds
- **Network policy:** Ingress from woodpecker namespace (pipeline pods), egress to external HTTP/HTTPS (upstream apt mirrors)
- **Storage:** 10Gi PVC (production), 5Gi (default)
- **Helm:** `aptCache.enabled: true` (default)

## Backups (Velero + MinIO)

Automated k8s cluster backups using Velero with a dedicated backup MinIO instance.

- **Namespace:** `velero`
- **Backup storage:** `/mnt/backups/minio` (HostPath PV, not local-path-provisioner)
- **MinIO image:** `quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z` (pinned)
- **Velero chart:** `vmware-tanzu/velero` (v11.4.0) with `velero-plugin-for-aws`
- **Node agent:** Enabled for PVC filesystem backups (`defaultVolumesToFsBackup: true`)
- **Snapshots:** Disabled (no snapshot support on local-path-provisioner)
- **pg_dump CronJob:** Runs at 1:30 AM UTC, dumps to postgres PVC `/backup/` dir, keeps last 3 dumps
- **Scheduled backups:**
  - `schnappy-daily`: 2 AM UTC, `schnappy` namespace, 7-day retention
  - `full-weekly`: Sunday 3 AM UTC, all namespaces, 30-day retention
- **Offsite replication:** rsync `/mnt/backups/minio/` → Pi `192.168.11.4:/mnt/backups/offsite/`, systemd timer at 4 AM daily
- **Git mirror:** bare repo on Pi at `/mnt/backups/git-mirror/monitor.git`, pushed daily with offsite backup; local mirror at `/var/lib/git-mirror/monitor.git` on ten
- **Vault Raft snapshots:** CronJob every 6h, uploaded to MinIO `vault-backups` bucket, 30 retained
- **Key files:** `deploy/ansible/playbooks/setup-velero.yml` (platform repo), Helm templates in platform repo

**Backup storage layout:**
```
SATA SSD (/mnt/backups/minio)          ← primary backup storage (Velero + Vault snapshots)
Pi NVMe (/mnt/backups/offsite)         ← 3rd copy, rsync'd daily at 4 AM from SATA SSD
Pi NVMe (/mnt/backups/git-mirror/)     ← bare git mirror, pushed daily at 4 AM from ten
```

**Backup commands:**
```bash
task deploy:backup          # Manual backup of schnappy namespace
task deploy:backup:status   # Check backup status
```

### Restore Procedures

**Monitor app (from Velero backup):**
```bash
# List available backups
ssh ten 'sudo kubectl exec deploy/velero -n velero -- velero backup get --kubeconfig /etc/kubernetes/admin.conf'

# Restore from backup (recreates namespace + PVCs + data)
ssh ten 'sudo kubectl exec deploy/velero -n velero -- velero restore create --from-backup <backup-name> --kubeconfig /etc/kubernetes/admin.conf'
```

**Monitor app (from offsite copy, primary SATA SSD lost):**
```bash
# 1. Rsync offsite data back to ten
ssh ten 'sudo rsync -az sm@192.168.11.4:/mnt/backups/offsite/ /mnt/backups/minio/'

# 2. Restart MinIO to pick up restored data
ssh ten 'sudo kubectl delete pod -l app=minio-backup -n velero'

# 3. Wait for BSL available, then restore
ssh ten 'sudo kubectl exec deploy/velero -n velero -- velero restore create --from-backup <backup-name> --kubeconfig /etc/kubernetes/admin.conf'
```

**Vault (from Raft snapshot):**
```bash
# 1. List snapshots in MinIO
ssh ten 'sudo kubectl exec deploy/minio-backup -n velero -- mc ls minio/vault-backups/ --insecure'

# 2. Copy snapshot to vault pod
ssh ten 'sudo kubectl cp velero/<minio-pod>:/data/vault-backups/<snapshot>.snap /tmp/vault.snap'
ssh ten 'sudo kubectl cp /tmp/vault.snap vault/vault-0:/tmp/vault.snap'

# 3. Restore (requires root token)
ssh ten 'sudo kubectl exec -n vault vault-0 -- env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt VAULT_TOKEN="<root-token>" vault operator raft snapshot restore /tmp/vault.snap'
```

**Vault Pi (transit unseal server lost):**
```bash
# Re-run Ansible with offline init keys to rebuild from scratch
task deploy:vault-pi
# Then re-run vault setup to update autounseal token
task deploy:vault
```

**DR test:** `task test:dr` — automated Vagrant test covering pod recovery, Velero backup/restore, and offsite restore.

## ELK Stack (Centralized Logging)

Elasticsearch + Fluent-bit + Kibana for centralized log aggregation and search across all pods (including Woodpecker CI pipeline pods).

- **Namespace:** `schnappy` (shared with the app)
- **Elasticsearch:** Single-node StatefulSet, 8.19.8, xpack security enabled (password auth)
- **Fluent-bit:** DaemonSet, ships pod logs from `/var/log/containers` (tail input) to Elasticsearch
- **Kibana:** Deployment at `https://logs.pmon.dev/`, uses `kibana_system` user (password set via init container)
- **Secrets:** `schnappy-elasticsearch` in Vault KV (`secret/schnappy/elasticsearch`) with `password` + `kibana_password` keys
- **ILM:** Managed by `elasticsearch-ilm-job.yaml` — creates retention policies and index templates on deploy
- **Pod logs:** `podlogs-*` index, 30-day retention (`logs-30d-retention` ILM policy)
- **CI logs:** Woodpecker pipeline pods run in k8s, so their logs are captured automatically in `podlogs-*` by the tail input
- **PodSecurity:** Schnappy namespace uses `privileged` enforce (required for Fluent-bit's hostPath + DAC_READ_SEARCH)
- **vm.max_map_count:** Already ≥262144 on host (no sysctl init container needed)

**Resource usage (production):**

| Pod | CPU req/limit | Memory req/limit | Typical usage |
|-----|---------------|------------------|---------------|
| Elasticsearch | 250m / 4000m | 2Gi / 4Gi | ~2.7Gi (2GB JVM heap + Lucene) |
| Kibana | 100m / 1000m | 1Gi / 2Gi | ~550Mi (Node.js) |
| Fluent-bit | 100m / 1000m | 128Mi / 512Mi | ~80Mi idle, ~800m CPU under stress |

**Key files** (in platform repo):
- Templates: `helm/templates/elasticsearch-*.yaml`, `kibana-*.yaml`, `fluentbit-*.yaml`
- Config: `elasticsearch-configmap.yaml`, `kibana-configmap.yaml`, `fluentbit-configmap.yaml`
- Secrets: `elasticsearch-secret.yaml` (skipped when `existingSecret` set)
- ILM: `elasticsearch-ilm-job.yaml` (Helm hook Job that creates ILM policies + index templates)
- Test: `tests/ansible/test-elk.yml` — Vagrant integration test (`task test:elk`)

**Vagrant test:** `task test:elk` — deploys ELK in Vagrant, verifies ES auth, Fluent-bit log shipping, Kibana health, ExternalSecret sync.

## Security Notes

- **JWT:** RS256 asymmetric signing via Keycloak JWKS; Envoy Gateway validates JWTs natively via C++ `jwt_authn` filter (microseconds per decode, no JVM overhead); `realm_access.roles` carries permissions; `sub` claim is UUID
- **RBAC:** Group-based permissions enforced via AOP `@RequirePermission` annotation; permissions mapped as Keycloak realm roles; admin safety checks prevent self-lockout (can't remove own MANAGE_USERS, can't disable self, can't delete Admins group); disabled users rejected at service level
- **Auth:** Bearer tokens only (no cookies, no CSRF needed); frontend uses Keycloak PKCE flow with memory-only token storage; registration and password reset handled entirely by Keycloak
- **Data isolation:** All queries scoped by `userId` from JWT; `@JsonIgnore` on `userId` in all entities to prevent info leaks in JSON responses
- **Webhooks:** Svix HMAC-SHA256 signature verification; replay protection via timestamp check; idempotent (deduplicates by `resendEmailId`); rate limiting skipped (signature is sufficient)
- **Rate limiting:** Per-service Bucket4j rate limiting (300 req/min per user)
- **Error handling:** Global `@ControllerAdvice` exception handler prevents stack trace leaks; returns generic "Internal server error"
- **Actuator:** Only `health` and `prometheus` endpoints exposed; `show-details: never` on public health endpoint
- **SSRF protection:** URL validator blocks internal IPs, validates DNS at request time (prevents rebinding), checks every redirect hop
- **ReDoS protection:** Nested quantifier detection, 500-char pattern limit, 5-second regex timeout, 512KB body limit
- **Containers:** Run as non-root, drop all capabilities, `readOnlyRootFilesystem` on all containers (app/frontend/redis/postgres/minio/elasticsearch/kibana/grafana/prometheus); ES and Kibana use init containers to copy default config files to writable emptyDir volumes
- **Secrets:** All secrets in Vault KV v2 (`secret/schnappy/*`), synced to k8s Secrets via ESO ExternalSecrets; Helm `existingSecret` pattern skips inline secret creation; Forgejo + Woodpecker secrets also via Vault + ESO (ExternalSecrets in `clusters/production/cluster-config/`); containerd registry config populated via Ansible (`setup-kubeadm.yml`); `.env` only for initial Vault seeding; `.env` in `.gitignore`
- **Network policies:** Default-deny ingress+egress for all pods; DNS (port 53) allowed for all; explicit ingress+egress rules per pod (app→postgres/redis/minio/ES/external HTTPS, frontend→app, grafana→prometheus, etc.); app external egress blocks RFC1918 ranges; also applied to forgejo and velero namespaces
- **Docker images:** `postgres:17-alpine` and `redis:7-alpine` pinned (no mutable `:latest` tags)
- **Frontend:** No `dangerouslySetInnerHTML`; postMessage origin validation on Game iframe; open redirect protection on login redirects
- **Nginx:** Security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy) on all locations including `/game/`

## Chat Service

Real-time messaging with Kafka message bus and ScyllaDB persistence.

- **Always-on:** Kafka + ScyllaDB are mandatory infrastructure (like PostgreSQL). No feature flag.
- **Kafka:** Apache Kafka 4.2.0, KRaft mode (no ZooKeeper), single broker, 3 topics: `chat.messages` (12 partitions), `chat.events` (6), `chat.notifications` (3)
- **ScyllaDB:** 6.2, single node, CQL protocol on port 9042; `--developer-mode=1` only in Vagrant tests (production uses `--overprovisioned=1` without developer mode)
- **Message flow:** REST/WebSocket → ChatService → KafkaProducer → Kafka → ChatMessageConsumer (persistence group → ScyllaDB, delivery group → WebSocket fan-out)
- **Data model:** PostgreSQL for channels + members + user cache (relational), ScyllaDB for messages (day-bucketed partitions: `PRIMARY KEY ((channel_id, bucket), message_id)`)
- **User cache:** `chat_users` table in monitor_chat DB, populated from Kafka user events and gateway headers; Redis is read-through cache
- **WebSocket:** STOMP over SockJS at `/ws/chat`, JWT auth via HandshakeInterceptor (cookie or header)
- **Presence:** Redis sorted set (`chat:presence`) with 60s heartbeat TTL
- **Permission:** `CHAT` permission required (group-based RBAC)
- **Key files:** `backend/src/main/java/io/schnappy/monitor/chat/` (all chat Java code), Helm templates `kafka-*.yaml`, `scylla-*.yaml` in platform repo
- **Test:** `task test:kafka-scylla` (Vagrant integration test — Kafka + ScyllaDB + schema/topics jobs + network policies)
- **Plan:** `chat-service-plan.md` (platform repo)

**Resource usage (production):**

| Pod | CPU req/limit | Memory req/limit |
|-----|---------------|------------------|
| Kafka | 250m / 2000m | 1Gi / 2Gi |
| ScyllaDB | 500m / 4000m | 2Gi / 4Gi |

### E2E Encryption

Optional end-to-end encryption for chat channels. When enabled, messages are encrypted client-side before being sent; the server only stores ciphertext.

- **Feature-flagged:** `monitor.chat.e2e-enabled` (disabled by default); Helm value `chat.e2eEnabled`
- **Identity keys:** ECDH P-256 key pair per user (Web Crypto API native, no npm packages)
- **Private key protection:** PBKDF2(password, 16-byte salt, 600k iterations) → AES-256-GCM wrapping key; encrypted PKCS8 private key stored server-side
- **Channel key:** Random AES-256-GCM symmetric key per encrypted channel
- **Channel key distribution:** Ephemeral ECDH per wrap; wrapped key + ephemeral public key stored in `channel_key_bundles` table
- **Message encryption:** AES-256-GCM, random 12-byte IV, stored as `base64(iv || ciphertext || tag)`
- **Key rotation:** New channel key on member removal (forward secrecy for kicked members); old key versions retained for historical message decryption
- **Password reset:** Regenerates key pair; old encrypted chat history becomes unreadable (warning shown on reset pages)
- **Key endpoints:** `GET/POST/PUT /chat/keys`, `GET /chat/keys/public`, `GET/POST /chat/channels/{id}/keys`, `POST /chat/channels/{id}/keys/rotate` — all return 404 when E2E disabled
- **Frontend:** `crypto.ts` (Web Crypto wrapper), `keyStore.ts` (in-memory key cache, cleared on logout)
- **DB tables:** `user_keys` (identity key pairs), `channel_key_bundles` (per-member encrypted channel keys)
- **Plan:** `e2e-encryption-plan.md` (platform repo)

## SonarQube (Code Quality)

Self-hosted SonarQube CE 26.3.0 at `https://sonar.pmon.dev/` for static analysis and code coverage.

- **Namespace:** `schnappy` (shared with the app)
- **Feature-flagged:** `sonarqube.enabled` in Helm (disabled by default)
- **Seven projects:** `schnappy-monitor`, `schnappy-admin`, `schnappy-chat`, `schnappy-chess`, `schnappy-gateway`, `schnappy-site`, `schnappy-infrastructure`
- **Coverage:**
  - Backend services: JaCoCo → XML report, excludes jOOQ generated code and config/dto/entity from coverage
  - Frontend: `@vitest/coverage-v8` → LCOV report
- **Quality gates:**
  - `Service` (default) — 80% new code coverage, no new bugs/vulnerabilities
  - `Frontend` — 70% new code coverage (assigned to `schnappy-site`)
- **Fresh deploy setup** (SQ has no persistent config — must be configured after each fresh deploy):
  ```bash
  # 1. Change default admin password
  curl -X POST -u admin:admin "http://localhost:9000/api/users/change_password" \
    -d "login=admin&previousPassword=admin&password=<from-vault>"
  # 2. Generate analysis token
  curl -X POST -u admin:<pw> "http://localhost:9000/api/user_tokens/generate" \
    -d "name=ci&type=GLOBAL_ANALYSIS_TOKEN"
  # 3. Create projects
  for key in schnappy-monitor schnappy-admin schnappy-chat schnappy-chess schnappy-gateway schnappy-site schnappy-infrastructure; do
    curl -X POST -u admin:<pw> "http://localhost:9000/api/projects/create" -d "project=$key&name=$key"
  done
  # 4. Create quality gates (copy from Sonar way, rename, set coverage thresholds)
  # 5. Update token in woodpecker-ci-secrets + Vault
  ```
- **CI integration:** Quality gate blocks CI (`sonar.qualitygate.wait=true`); CD runs analysis informational-only (`wait=false`)
- **Secrets:** `SONAR_TOKEN` and `SONAR_HOST_URL` in Forgejo repository secrets
- **Dedicated PostgreSQL:** Separate from app database
- **Key files:** `backend/build.gradle` (sonar config), Helm templates `sonarqube-*.yaml` in platform repo
- **Test:** `task test:sonarqube` (Vagrant integration test)
- **Plans:** `sonarqube-ci-plan.md`, `sonarqube-config-plan.md` (platform repo)

## Future TODOs

- [ ] Alerting (Slack/email)
- [ ] Hyperfoil → Prometheus metrics (pushgateway or custom exporter)
