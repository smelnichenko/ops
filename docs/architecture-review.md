# Architecture Review — The "schnappy" Homelab Platform

*A self-hosted, multi-service Kubernetes platform — independent architectural assessment*

---

## Scope & Method

This review covers the **schnappy** platform: a self-hosted, multi-service system running on a single-node kubeadm cluster ("ten", 192.168.11.2) backed by a two-Raspberry-Pi stateful tier and an edge router. It spans six application microservices (`monitor`, `admin`, `chat`, `chess`, `site`, `game-scp`), their data stores, the GitOps delivery pipeline, the Istio/Cilium service mesh, the observability stack, and the resilience/disaster-recovery posture.

The assessment was conducted by reading the live repositories under `/home/sm/src/` — `monitor`, `admin`, `chat`, `chess`, `site`, `game-scp` (application code), `infra` (Argo CD app-of-apps, per-environment values), `platform` (Helm charts `schnappy-*`), and `ops` (Ansible playbooks, plan docs) — rather than relying on prior summaries. Where domain surveys carried claims forward from earlier work, those claims were **re-verified against current config**, and several were found stale or incorrect. Those corrections are folded into the relevant sections and called out explicitly, because a recommendation built on a phantom risk wastes effort. All non-trivial assertions are cited by repository path, and several by file:line.

The method was deliberately adversarial on risk and generous on credit: I tried to break each load-bearing claim before accepting it, and I separately documented what is genuinely well-engineered so the recommendations don't drown the strengths.

---

## Executive Summary

schnappy is an unusually sophisticated homelab. It runs an enterprise-shaped stack — Istio sidecar mesh with STRICT mTLS, Cilium eBPF CNI, CloudNativePG, Strimzi Kafka, ScyllaDB operator, Vault HA with transit auto-unseal, External Secrets Operator, Mimir/Tempo/ClickHouse observability, Velero, Centrifugo realtime — all orchestrated through a disciplined Argo CD app-of-apps GitOps flow fed by Woodpecker CI and Kaniko image builds. The engineering quality of the GitOps machinery, the Raspberry-Pi data-tier HA, and the observability correlation is genuinely above homelab norm.

The defining tension is **architectural ambition versus physical substrate**: nearly every component is enterprise-grade and HA-capable, but the substrate is a *single Kubernetes node with single-replica everything on a single local disk*. The cluster node `ten` is simultaneously the control plane, the entire in-cluster data plane, the GlusterFS arbiter, and a Consul quorum member. This is a defensible choice for a learning lab, but it means most components carry their operational cost (operators, CRDs, network-policy surface, version tracking) without delivering their headline benefit (horizontal scale, fault tolerance).

The most material risks are **not bad design** — they are a handful of dangerous toggles and missing automations where the *configured* posture contradicts the *intended* posture:

1. **The Argo CD root app has `prune: true` + `selfHeal: true`** (`infra/clusters/production/argocd/apps/root.yaml:27-29`), directly contradicting its own README guardrail ("Never force-sync or prune the root app — it cascade-deletes all child Applications"). One bad ApplicationSet render or operator force-sync can cascade-delete the entire platform definition.

2. **Edge JWT validation is disabled in production** (`schnappy-production-mesh/values.yaml:20`, `jwt.enabled: false`). The gateway neither validates the Keycloak signature nor strips inbound `X-User-*` headers, and the application security filter trusts those headers and parses roles from an **unverified** Base64-decoded JWT payload (`GatewayAuthFilter.java:57-58,102-105`). In production, the documented "edge JWT + app RBAC + mTLS" defense-in-depth is, in practice, *app-header-trust + mTLS*.

3. **Test→prod promotion is a manual hand-edit and is already drifting** — four of six services have production lagging test (`schnappy-production-apps/values.yaml` vs `schnappy-test-apps/values.yaml`), with no approval gate, diff review, or rollback automation.

4. **Disaster recovery is asserted, not continuously proven** — the restore-verification CronJob (Plan 061-C) is scoped but never run; DR was last validated manually in March 2026.

Crucially, several risks previously rated CRITICAL by earlier surveys were **disproven on re-inspection**: Forgejo's DB connection is failover-transparent (not pinned), the stateful data ApplicationSet is `prune: false` (not prune-everything), and the ingress gateway runs two replicas. The remaining top items are all low-to-medium effort. Fixing them converts the platform's *stated* posture into its *actual* posture.

### Maturity at a glance

| Domain | Maturity | One-line assessment |
|---|---|---|
| Topology & Infrastructure | **Moderate** | Excellent automation; single-node substrate is the structural ceiling. |
| Application Services & Communication | **Strong** | Clean event-driven design, per-service security, well-factored realtime path. |
| Data Architecture | **Moderate** | Per-service isolation is good; single-instance CNPG/Kafka/Scylla limit durability. |
| Auth & Security | **Mixed** | Sound model, strong pod hardening — undermined by the prod JWT toggle. |
| Service Mesh & Networking | **Strong** | Thorough mTLS + dual-layer NetworkPolicy; carve-out sprawl is the cost. |
| CI/CD & GitOps | **Strong (with gaps)** | Disciplined GitOps; manual promotion + root-app prune are the soft spots. |
| Observability | **Strong** | Correlated metrics/traces/logs, rich alerting, runbooks — real SRE setup. |
| Resilience / HA / DR | **Moderate** | Pi-tier HA is excellent; in-cluster tier and DR verification are weak. |

---

## System Context

schnappy is a hub-and-spoke topology: a single Kubernetes node hosts all application and observability workloads, a two-Pi tier provides active-passive HA for the stateful "platform of record" services (git, SSO, secrets, durable Postgres for those two services, object storage), and an edge router provides WAN, DNS, and remote access. All three sit on a flat LAN (192.168.11.0/24).

```
                    Internet (PPPoE WAN)  +  WireGuard remote access
                                  |
                       +----------------------+
                       |  Edge Router (CM4)   |
                       |  PPPoE / UFW         |
                       |  unbound (split-horizon DNS: *.pmon.dev -> .2)
                       |  WireGuard endpoint  |
                       +----------+-----------+
                                  | LAN 192.168.11.0/24
        +-------------------------+--------------------------------+
        |                         |                                |
+-------v--------+      +---------v---------+          +-----------v----------+
|  ten (.2)      |      |   pi1 (.4)        |  VRRP    |   pi2 (.6)           |
|  kubeadm 1.34  |      |   keepalived MASTER|<-------->|  keepalived BACKUP  |
|  single node   |      |   (prio 150)      |  unicast |  (prio 100)         |
|                |      +---------+---------+          +-----------+----------+
| Cilium (eBPF)  |                |     Keepalived VIP .5 floats     |
| Istio sidecar  |      +---------v---------------------------------v---------+
|   STRICT mTLS  |      |  Pi stateful tier (active-passive):                |
|                |      |   Forgejo (git.pmon.dev) + container registry      |
| Namespaces:    |      |   Keycloak (auth.pmon.dev) SSO realm "schnappy"     |
|  istio-system  |      |   Vault (transit auto-unseal, Consul storage)       |
|  argocd        |      |   MinIO (Velero + DB backups) [consul-lock fenced]  |
|  woodpecker    |      |   Patroni Postgres (Forgejo/Keycloak DBs)           |
|  cert-manager  |      |   PgBouncer :6432 -> HAProxy :5000 -> Patroni leader|
|  cnpg-system   |      |   Consul (server)         Nexus (cache)             |
|  strimzi /     |      +-----------------------------------------------------+
|  scylla-op     |        Consul 3-node quorum: pi1 + pi2 + ten (arbiter)
|                |        GlusterFS replica-3-arbiter: pi1 + pi2 data, ten arbiter
| schnappy-      |
|  production    |   Apps: monitor admin chat chess site game-scp
| schnappy-test  |   Data: CNPG(1) Strimzi-Kafka(1) ScyllaDB(1) Valkey MinIO(1)
| schnappy-infra |   Obs:  Prometheus Mimir Tempo Grafana ClickHouse Alertmanager
+-------+--------+
        |
   HAProxy (host) :80/:443  ->  Istio ingress gateway (externalIP .2, 2 replicas)
        |
   GitOps: push -> Woodpecker (k8s backend) -> Kaniko -> git.pmon.dev registry
                -> commit tag to infra repo -> Argo CD app-of-apps sync
```

Identity is centralized in Keycloak's `schnappy` realm; TLS is a single `*.pmon.dev` wildcard via cert-manager DNS-01 (Porkbun webhook); secrets flow Vault → External Secrets Operator → Kubernetes Secrets. The edge router's unbound provides split-horizon DNS so LAN clients reach internal IPs while DNS-01 validation uses public resolvers.

---

## Topology & Infrastructure

The cluster is a single kubeadm 1.34 node running Cilium (eBPF, L2 LB IP pool, kube-proxy replacement) for the CNI and Istio 1.25.2 for the sidecar mesh under STRICT mTLS. Workloads are organized into three application namespaces — `schnappy-production`, `schnappy-test`, and `schnappy-infra` (observability + gateway) — plus operator namespaces (`cnpg-system`, `strimzi`, `scylla-operator`, `cert-manager`, `argocd`, `woodpecker`, `velero`). Storage is `local-path` provisioner, so every PVC is pinned to `ten`'s disk.

Provisioning is fully codified in Ansible under `ops/deploy/ansible/playbooks/` (`setup-kubeadm.yml`, `setup-consul.yml`, `setup-pi-services.yml`, `setup-keepalived.yml`, `setup-patroni.yml`, `setup-pgbouncer.yml`, `setup-gluster.yml`, `setup-vault-pi.yml`), invoked through Taskfile targets. This is a strength: the substrate is reproducible from source.

**The structural risk is concentration on `ten`.** Beyond hosting all app and observability workloads, the node is the GlusterFS arbiter and one of three Consul quorum members. The consequence is a cross-tier failure coupling that the "independent Pi tier" framing obscures: if `ten` is down *and* a Pi flaps, the surviving Pi loses Consul write-quorum (2-of-3 with `ten` absent), so Patroni cannot elect a leader — meaning a control-plane node failure can cascade into the supposedly-independent stateful tier. Disk loss on `ten` additionally destroys all metrics, logs, and traces (all on local-path), recoverable only from Velero. This is an acceptable homelab trade-off, but the enterprise shape of the surrounding stack invites treating the system as more resilient than a single disk actually is.

The Pi tier itself is well-built (covered under Resilience). The edge router (PPPoE/WireGuard/unbound) is not represented in the scanned playbooks, so it is effectively a manually-managed single point of failure for WAN and remote access — worth documenting even if not automating.

---

## Application Services & Inter-Service Communication

Six services divide cleanly by responsibility:

- **monitor** (`io.schnappy.monitor`) — web-page and RSS monitoring with regex extraction over time, dynamic CRON scheduling from the DB (`MonitorScheduler`), an inbound-email webhook + inbox, and a slot-machine game.
- **admin** (`io.schnappy.admin`) — user/role management, the source of truth for the `user.events` Kafka stream (`UserEventProducer`), Keycloak role sync (`KeycloakSyncService`), and the Centrifugo subscription-token minting endpoint (`RealtimeTokenController` + membership checkers).
- **chat** (`io.schnappy.chat`) — channels and messages with client-side E2E encryption, message persistence to ScyllaDB via Kafka, and an `/internal/membership` endpoint for admin's token minting.
- **chess** (`io.schnappy.chess`) — game engine (move validation), PvP coordination, and live updates via Centrifugo; mirrors chat's internal-membership pattern.
- **site** — the React/TypeScript/Vite SPA fronting all features, with `api.ts` (the REST client), `centrifugoClient.ts` (realtime), and `oidcClient.ts` (Keycloak OIDC + PKCE).
- **game-scp** — a Godot HTML5 export embedded by iframe; stateless, no backend coupling.

The communication architecture uses three complementary patterns, and a single walkthrough illustrates all of them.

**Request + event data-flow walkthrough — a chat message:**

1. A browser, authenticated to Keycloak via PKCE, `POST`s to `/api/chat/channels/{id}/messages` carrying the access token.
2. The request enters through HAProxy → the Istio ingress gateway → the `chat` pod's sidecar (mTLS). Inside the pod, `GatewayAuthFilter` reads `X-User-UUID`/`X-User-Email` and resolves permissions, populating the Spring `SecurityContext`; `@RequirePermission(CHAT)` (AOP via `PermissionInterceptor`) authorizes the call.
3. `ChatService.sendMessage()` produces to the `chat.messages` Kafka topic (keyed by channel) **and** publishes an envelope to `events.chat.messages` carrying a Kafka header `x-centrifugo-channels=chat:room:{id}`.
4. `ChatMessageConsumer` (group `chat-persistence`) consumes `chat.messages` and writes to ScyllaDB (`messages_by_channel`, time-bucketed). Independently, an external Centrifugo bridge consumes `events.chat.messages`, reads the channel header, and publishes to subscribers.
5. Subscribing clients receive the message over WebSocket. Subscription was authorized earlier: `centrifugoClient.ts` requested a sub-token from admin's `/realtime/sub-token`, which validated channel membership by calling chat's `/internal/membership` over mTLS before minting a short-lived HMAC token.

The same envelope→header→bridge pattern serves chess (`events.chess.moves`, `chess:game:{uuid}`). The **`user.events`** topic is the third pattern: admin emits `USER_CREATED/ENABLED/DISABLED/PERMISSIONS_CHANGED/REGISTRATION_*`, and monitor/chat/chess each consume independently (groups `user-sync`, `chat-user`, `chess-user`) to provision local user state — eventual consistency by design, redundant-but-safe alongside lazy gateway provisioning.

This is clean, idiomatic event-driven design. The honest caveats are inherent to the pattern: DTOs and events are unversioned (`version: 1` everywhere), so schema changes require coordinated deploys; consumer-lag and bridge-latency are not surfaced as metrics; and several SPOFs follow from single-node Kafka and the single Centrifugo bridge — if either stalls, realtime fanout halts while REST history still works.

---

## Data Architecture

This domain carried the most stale survey material, now reconciled against live config (`schnappy-production-data/values.yaml`):

- **Application databases run on in-cluster CloudNativePG**, not Pi Patroni. `cnpg.enabled: true` (line 144) with an operator-managed `Cluster` at **`instances: 1`** (`cnpg-cluster.yaml:10`) hosting four isolated databases/users — `monitor`, `admin`, `chat`, `chess` — each with Vault-sourced credentials and Liquibase-managed schemas. A `cnpg-init-users` Job bootstraps the per-service roles.
- **The chart's raw `postgres:`/`minio` legacy blocks are dead** (`enabled: false`); Kafka is Strimzi (`strimzi.enabled: true`, KRaft mode), ScyllaDB is operator-managed (`scyllaOperator.enabled: true`), Valkey replaces Redis (wire-compatible cache), and MinIO is a single in-cluster pod.
- **Pi Patroni serves only Forgejo and Keycloak** — a separate system from the app data tier.

The per-service isolation is good practice: separate databases, users, and credentials prevent one service's compromise or schema migration from affecting another, and Liquibase gives idempotent, version-tracked DDL. ScyllaDB's chat schema (`messages_by_channel`, `messages_by_user_v2`, `message_edits`, `reactions_by_message`, `chain_heads`) is thoughtfully partitioned for the access patterns, with an E2E hash chain (`hash`/`prev_hash`) and key-version columns.

**The durability gaps are all "instances: 1."** All four app databases share a single CNPG pod with no replica — the much-discussed Patroni/PgBouncer/HAProxy HA machinery on the Pis protects *only* Forgejo/Keycloak. App-DB durability rests on one pod plus daily Barman base backups to Pi MinIO; pod eviction takes all apps down until reschedule, and PVC loss means restore-from-backup at whatever RPO the last base backup gives. Strimzi Kafka (RF=1, single broker) and ScyllaDB (RF=1, single node) are similarly single-points. Secrets flow correctly through ESO with a 15-minute refresh, which is a rotation-lag floor but acceptable. The realistic posture: app data is **recoverable** (per-service backups, S3 offsite) but **not highly available**, and that gap should be a conscious, documented decision rather than an implicit one.

---

## Auth & Security

The identity model is sound and modern: Keycloak-only SSO (`schnappy` realm), UUID-everywhere, a public `app` client with PKCE (S256), confidential clients for Forgejo/Argo CD/Grafana/admin-service/k6, composite roles (`Users` → `[METRICS, PLAY]`, `Admins` → full set) mapping to a five-value `Permission` enum (`PLAY, CHAT, EMAIL, METRICS, MANAGE_USERS`), short 5-minute access tokens, and admin→Keycloak role sync via `KeycloakSyncService`. Each service carries its own `security/` package with an identical `GatewayAuthFilter` → `@RequirePermission` AOP pattern, and `SecurityConfig` applies strong response headers (HSTS, CSP `default-src 'none'`, frame-ancestors none), stateless sessions, and CSRF-off (appropriate for a token-fronted API).

**Pod hardening is exemplary and uniform** across services: `runAsNonRoot`, `runAsUser: 1000`, `readOnlyRootFilesystem: true`, `capabilities: drop ALL`, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`, named per-service ServiceAccounts, and belt-and-suspenders NetworkPolicy plus Istio AuthorizationPolicy. This is above the bar for most production shops, let alone homelabs.

**The one serious gap is the production edge-auth toggle, and it is the single most important finding in this review.** Verified chain of evidence:

- `schnappy-production-mesh/values.yaml:20` sets `jwt.enabled: false`.
- The entire `RequestAuthentication` block — the only thing that validates the Keycloak signature and *sets* `x-user-uuid`/`x-user-email` from claims — is wrapped in `{{- if .Values.jwt.enabled }}` (`request-authentication.yaml:1`). So in production the gateway neither validates the JWT **nor strips/overwrites** inbound `X-User-*` headers.
- `GatewayAuthFilter` trusts `X-User-UUID`/`X-User-Email` from request headers for identity (`GatewayAuthFilter.java:57-58`) and derives roles by Base64-decoding the JWT payload **with no signature check** (`GatewayAuthFilter.java:102-105`), behind a code comment asserting "Istio already validated" — which is untrue in production.

Net: in production, identity *and* roles are forgeable by anything that can reach a backend pod on `:8080` with attacker-chosen headers and a self-minted unsigned token. The sole compensating controls are NetworkPolicy (8080 ingress restricted to gateway/site/prometheus/alertmanager pods, `schnappy/templates/network-policies.yaml`) and mesh mTLS. So this is **not internet-trivially exploitable**, but it is a real privilege-escalation seam: a compromise of the in-mesh `site` nginx (which is in the ingress allowlist) yields full impersonation of any user or admin. The documented three-layer defense-in-depth is, in production, two layers.

Two secondary gaps reinforce the theme. The chat/chess `/internal/**` endpoints are `permitAll()` in Spring (`chat/.../SecurityConfig.java:39`), guarded solely by the Istio DENY-except-`schnappy-admin` policy — a single sidecar mis-injection or policy regression exposes the membership lookups that gate sub-token minting, with no app-layer backstop. And `KeycloakSyncService` swallows sync failures by design with no reconciliation job, so admin-DB roles and Keycloak realm roles can silently diverge — which, combined with 5-minute tokens and no server-side revocation, widens the offboarding window. The Centrifugo sub-token HMAC is a single shared symmetric secret across the realtime auth path (Vault-stored, short-TTL — acceptable but worth noting).

---

## Service Mesh & Networking

The mesh is comprehensive defense-in-depth: Istio 1.25.2 sidecars with STRICT `PeerAuthentication`, per-pod `AuthorizationPolicy` keyed on SPIFFE ServiceAccount principals (e.g., Postgres:5432 reachable only by the four app SAs; ScyllaDB:9042 by monitor/chat/scylla; chat & chess `/api/internal/**` DENY-except-admin), Gateway API v1 `HTTPRoute`s with `ReferenceGrant`s for cross-namespace routing, and `DestinationRule`s adding outlier detection (eject on 3 consecutive 5xx) and connection pooling. Ingress uses the Gateway API with `externalIPs` patched onto a ClusterIP Service (a post-sync Job, since there is no LoadBalancer controller), and TLS terminates with the single `*.pmon.dev` wildcard via cert-manager DNS-01.

Two survey claims were corrected here. The ingress gateway is **not** a single-pod SPOF — `schnappy-infra-mesh/values.yaml:14` sets `replicas: 2`; the real SPOF is that both replicas bind one node's IP (`.2`), so node loss (not pod loss) is the exposure. And edge JWT validation is enabled in `schnappy-infra` (`jwt.enabled: true` with a per-vhost passthrough allowlist for git/sonar/ci/auth/cd/grafana/logs/etc.) but disabled in `schnappy-production` — the security consequence detailed above.

The cost of STRICT mTLS on a heterogeneous stack is **carve-out sprawl**: roughly seven-plus port-level PERMISSIVE exceptions and sidecar-disable annotations are needed so non-mesh scrape targets, S3 Signature-V4 clients (MinIO/Tempo break under Envoy header rewriting), Fluent-bit (DaemonSet, no sidecar control plane), and setup Jobs can coexist. The decision to run **Prometheus without a sidecar** is a deliberate, documented trade-off (one PeerAuth exception vs. 7+ DestinationRules and ~50% overhead) — but it directly caused the 2026-04-20 "silent alerts for weeks" incident (fixed in commit `bf77e2e`), a useful reminder that each carve-out is latent risk. The Cilium eBPF DNAT interaction with NetworkPolicy `ipBlock` is a known sharp edge: Woodpecker egress rules are deliberately over-broad ("allow 443 broadly, restrict 3000 to Pi VIP") because eBPF DNAT mangles externalIP `ipBlock` matching. Both layers (K8s NetworkPolicy + CiliumNetworkPolicy for host-level egress like the smartctl probe) are used appropriately.

---

## CI/CD & GitOps

The delivery model is push-based GitOps with clean separation of concerns: code push → Woodpecker CI (Kubernetes backend, `MAX_WORKFLOWS: 1`, RWO storage — both deliberate single-node safety values) → tests + SonarQube → Kaniko image build to the Forgejo registry (`git.pmon.dev/schnappy/<service>:<7-char-hash>`, cached/mirrored through Nexus) → an `update-infra` step that commits the new tag to the infra repo with retry/backoff → Argo CD app-of-apps sync. Secrets reach the pipeline via ESO from Vault (`woodpecker-ci-secrets`). The CI/CD design is disciplined: per-repo `.woodpecker/{ci,cd,pitest,depcheck}.yaml`, branch-vs-PR trigger separation, and quality gates that block on CI but are informational on CD.

Argo CD uses ApplicationSet directory generators (`schnappy-apps-envs`, `schnappy-data-envs`, `schnappy-mesh-envs`, `schnappy-realtime-envs`) plus a `schnappy-pr-envs` set for ephemeral per-PR preview environments (gitea generator, `preview/` branch filter, sandboxed `pr-envs` project, `pr-{number}.preview.pmon.dev`). The `ignoreDifferences` tuning to silence controller-managed `.status`/`.operation` fields, and the deliberate choice of client-side apply over server-side apply (to avoid apiserver-defaulted-field drift), reflect real GitOps sophistication.

Two corrections and two real gaps. **Correction:** the stateful `schnappy-data-envs` ApplicationSet is `prune: false` (`schnappy-data-envs.yaml:40`) — only the stateless `schnappy-apps-envs` is `prune: true` (`:40`), which is exactly right. **Real gap #1 — the root app.** `root.yaml:27-29` sets `automated: { selfHeal: true, prune: true }` on the app-of-apps, contradicting the infra README's explicit "never prune the root app — it cascade-deletes all child Applications." The `ignoreDifferences` reduces false OutOfSync, but a generator drift, a bad ApplicationSet template render, or an operator force-sync can cascade-delete every child (including stateful ones, whose finalizers then run). This is the highest-leverage, lowest-effort fix in the report.

**Real gap #2 — manual, ungated test→prod promotion, already drifting.** Every service CD pipeline writes only to `schnappy-test-apps/values.yaml` (`monitor/.woodpecker/cd.yaml`); the CD step is even named `deploy(test)`. Production promotion is a manual hand-edit of `schnappy-production-apps/values.yaml`, and the repo shows live divergence on four of six services:

| service | prod tag | test tag |
|---|---|---|
| monitor | `8ff6517` | `f9025e1` |
| site | `b87db63` | `fea19e4` |
| chat | `77e64b1` | `8e78877` |
| chess | `00d0412` | `a46e1bc` |

(admin and game-scp match.) There is no approval record, no diff gate, no rollback automation — the single biggest *operational* gap.

---

## Observability

Observability is the platform's standout strength and resembles a deliberate SRE setup rather than "Grafana and call it done." The three pillars are correlated, not siloed:

- **Metrics:** Prometheus Operator (kube-prometheus-stack) with CRD-based discovery, no sidecar (scraping merged app+Envoy metrics on `:15020`), `remote_write` to **Mimir** (single-replica all-in-one, MinIO S3 backend, 90-day retention), with **exemplar storage enabled** for trace-to-metric linking.
- **Tracing:** **Tempo** (OTLP gRPC/HTTP + Zipkin, MinIO S3, 14-day retention) with a metrics-generator producing service-graph and span-metrics that remote-write back to Mimir with exemplars. Spring Boot 4 apps export via OpenTelemetry HTTP/4318 at 10% sampling (tracing off by default, enabled per environment).
- **Logging:** **Fluent-bit** DaemonSet → **ClickHouse** (`logs.podlogs`, MergeTree, date-partitioned, bloom indexes on message/pod/trace_id, configurable TTL), with a Lua heuristic level extractor. Grafana ties it together: ClickHouse-Logs derived fields jump from a `trace_id` to the Tempo trace, and Tempo's `tracesToLogsV2` reverses the flow.

Alerting is mature: 26 alert groups across infra/CI categories (Vault sealed, MinIO dual-active, ESO/Argo CD/Velero health, PVC usage, cert expiry, public-URL probes, and notably **smartctl disk-failure alerts**), a Watchdog dead-man's-switch, inhibition rules, and **43+ `runbook_url` annotations** pointing to an auth-free runbooks site (`runbooks.pmon.dev`). Blackbox probes cover Pi Vault, per-Pi MinIO (dual-active detection), and public endpoints.

The honest caveats are the same single-node theme: Mimir, Tempo, ClickHouse, Grafana, and Alertmanager are all single-replica on local-path PVCs — a node or disk loss is an observability blackout recoverable only from backup. The Alertmanager SMTP endpoint (Resend) is a single hardcoded path with no fallback channel, so an SMTP outage equals total alert silence. ClickHouse schema upgrades have been manual (no migration tooling for the log store), and 10% trace sampling will miss rare-error traces. None of these undercut the fundamentally strong design.

---

## Resilience, HA & Disaster Recovery

The Pi-tier HA is genuinely good distributed-systems engineering, and the survey corrections here matter because two were previously rated CRITICAL.

**Correction — Forgejo DB is failover-transparent, not pinned.** Verified in `setup-pi-services.yml:79-107,292`: Forgejo and Keycloak connect to `127.0.0.1:6432` (local **PgBouncer**) → HAProxy `:5000` → the Patroni leader, with the port falling back to `:5000` (HAProxy direct) if PgBouncer is down. The `forgejo_db_host` override exists only as a fallback when Patroni is *not active on that Pi*; normal Patroni failover requires no manual re-deploy. The earlier "manual re-deploy on every failover" CRITICAL was wrong.

The HA design is layered and battle-tested. Keepalived runs unicast VRRP (both nodes start BACKUP with `nopreempt`; pi1 prio 150 wins), with health probes on Forgejo/Keycloak/Patroni dropping priority 50 on failure (~3s failover). The notify handlers re-read kernel VIP ownership under per-service flock to converge on the latest VRRP state (avoiding stale-state races), with a 3-minute converge timer to re-arm crashed services. **MinIO dual-active prevention is defense-in-depth**: keepalived VRRP + a Consul quorum-enforced `consul lock` fence on the systemd unit + `.active-on-<host>` sentinel files + a GlusterFS replica-3-arbiter (ten as arbiter) that gives the minority partition EROFS — and the `MinioDualActive` blackbox alert closes the loop. Patroni uses Consul DCS, `use_pg_rewind`, and streaming replication; PgBouncer runs in session mode (required by Keycloak's session-scoped temp tables) with `auth_query` so credentials aren't copied to `userlist.txt`. The operational maturity shows in postmortem-driven fixes: `server_login_retry` cut 15s→5s after a 2026-05-08 cached-auth-failure cascade, and the live-VIP re-read after a 2026-06-12 stale-handler incident.

**The weaknesses are the in-cluster tier and DR verification.** In-cluster CNPG is `instances: 1` — app databases have *zero* HA (the Pi HA protects only Forgejo/Keycloak). Velero backs up to Pi MinIO (single location on shared Gluster) with a tertiary offsite rsync to vault-pi; but **Plan 061-C restore verification is never run** — `task deploy:restore:verify` exists, DR was last validated manually 2026-03-05, and with single-replica state on local-path disks an untested backup is the most expensive kind of false confidence. Vault unseal keys live on the Pi filesystem (`/etc/vault-unseal/`); both-Pi loss loses them, though Consul-backed storage survives if `ten` is up.

---

## Cross-Cutting Concerns

Several themes recur across domains and are best addressed once rather than per-section.

**The substrate-vs-stack mismatch is the root cause of most brittleness.** Running Istio + Cilium + CNPG + Strimzi + ScyllaDB-operator + Mimir + Tempo + ClickHouse + Vault-HA + ESO + Velero + Centrifugo on one node with single-replica everything means each component pays its operational tax (an operator, CRDs, version pinning, network-policy surface, a carve-out or two) while delivering little of its headline HA/scale benefit. The concrete costs are visible throughout: the mesh carve-out sprawl, the Cilium DNAT workarounds, the "silent alerts" incident, and the long list of single-replica SPOFs. This is defensible as a *learning lab* — and should be named as such — but it is genuine carrying cost.

**Configured posture vs. intended posture.** The most dangerous risks are not design flaws but config that contradicts documented intent: the root app prunes despite the README forbidding it; production disables edge JWT validation despite the documented defense-in-depth; promotion is manual despite a CD pipeline that stops at "test." The institutional memory (plan docs, feedback memory) *knows* these risks — they simply aren't enforced in config yet.

**Version-pinning debt.** Helm charts and operators are hard-pinned across infra (Woodpecker 3.6.4, CNPG 0.28.0, Strimzi 0.51.0, kube-prometheus-stack 82.x, cert-manager 1.20.0, Istio 1.25.2) with no Renovate/Dependabot equivalent; security patches require manual Application edits.

**Out-of-band setup steps** undermine reproducibility: the MinIO `scylla-backups`/`schnappy-backups` buckets are created by hand via `mc exec` (mesh AuthZ blocks the bootstrap Job), the gateway externalIPs come from a post-sync patch Job, and ClickHouse schema migrations have been manual. A from-scratch rebuild silently loses these unless someone remembers.

**Eventual consistency and revocation windows.** Lazy gateway provisioning (5-min cache), Kafka-driven user sync, 15-min ESO refresh, 5-min tokens with no server-side revocation, and non-blocking Keycloak role sync are each individually reasonable but compound into multi-minute windows where state can diverge — acceptable at this scale, but worth tracking.

---

## Architectural Risks & Recommendations

Prioritized by blast-radius × likelihood ÷ effort. Effort: **S** ≤ ½ day, **M** 1–3 days, **L** 1+ week.

### HIGH

**H1 — Set `prune: false` on the root app. (Effort: S)** `root.yaml:29` currently contradicts its own README guardrail; one bad ApplicationSet render or force-sync cascade-deletes the platform. Keep prune only on the leaf stateless `schnappy-apps-envs` (already `prune: true` there). Highest leverage, lowest effort in the entire review. — **✅ DONE** (`root.yaml` `prune: false` live, with a guardrail comment).

**H2 — Close the production identity-trust seam. (Effort: S to flip the flag; M for in-app verification)** Either set `jwt.enabled: true` in `schnappy-production-mesh/values.yaml` so the gateway validates the Keycloak signature and *strips/overwrites* inbound `X-User-*` headers (validating the per-vhost passthrough allowlist), **or** make `GatewayAuthFilter` verify the forwarded token against Keycloak JWKS before trusting headers and parsing roles. Today production trusts unvalidated headers plus an unsigned-token role parse; this fix restores the documented three-layer defense and removes the in-mesh-pod → admin-impersonation path.

**H3 — Automate test→prod promotion behind a gate. (Effort: M)** Add a `promote` pipeline (or an Argo image-updater scoped to prod with manual sync) that copies test tags into `schnappy-production-apps/values.yaml` behind an approval, replacing the silent hand-edit that has already drifted on four of six services. Gives an audit trail and rollback path; removes the largest operational footgun. — **✅ DONE 2026-06-22** — the `promote:prod` task already existed but had **silently no-op'd** on a nonexistent path (`clusters/production/schnappy/values.yaml`) and a comment anchor the values never use (`# schnappy-<svc>` vs `# <svc>`) — that no-op *was* the drift cause. Repaired + gated: `task promote:prod` dry-runs the test→prod tag diff, `CONFIRM=1` commits+pushes (audit = the commit, rollback = `git revert`), `SERVICES="…"` scopes it. Verified it now flags the live `site` drift (`b87db63 → fea19e4`) and edits only that line.

**H4 — Implement scheduled restore verification (Plan 061-C). (Effort: M)** A weekly CronJob that restores a backup to an ephemeral target, runs a k6 smoke test, and emits a `restore_verify_success` metric with a `RestoreVerificationFailing` alert. With single-replica state on local-path disks, backups are the only DR; "untested since March" is unacceptable confidence. The plan is already scoped.

### MEDIUM

**M1 — Give in-cluster CNPG a second instance + PDB, or formally document app-DB RPO. (Effort: M)** App databases have zero HA today (`cnpg-cluster.yaml:10`, `instances: 1`); the Pi HA protects only Forgejo/Keycloak. If node resources allow, `instances: 2` + a PodDisruptionBudget; otherwise make the gap an explicit, documented decision. — **✅ DONE** — production cluster now runs `instances: 2` (platform `fcdfd52`, infra `eecbe93`); headroom verified on ten. This also surfaced and fixed a latent BLOCKER: the `-cnpg-postgres` NetworkPolicy had no intra-cluster self-allow, so the replica could not stream on 5432 — fixed (mirrors the Strimzi/Scylla self-allow). Replica verified streaming (async); CNPG manages the primary PDB. L2 is effectively covered for the DB.

**M2 — Add defense-in-depth on `/api/internal/**`. (Effort: S–M)** Verify the mTLS SPIFFE principal or a shared internal secret at the app layer so a single Istio policy regression doesn't expose chat/chess membership lookups that gate sub-token minting (currently `permitAll()` with Istio as the only guard).

**M3 — Add a Keycloak↔admin-DB role reconciliation CronJob + drift alert. (Effort: M)** `KeycloakSyncService` failures are silent; reconcile periodically and emit a sync-failure metric to close the offboarding/role-drift window.

**M4 — Codify the out-of-band setup steps. (Effort: M)** Move MinIO bucket creation (`scylla-backups`/`schnappy-backups`) and any ClickHouse schema migration into idempotent, mesh-aware Jobs or documented `task` targets so a rebuild is fully reproducible.

**M5 — Introduce automated dependency/version PRs. (Effort: M)** Renovate against the infra repo's Helm `targetRevision` pins, to surface security updates without manual patching of 8+ pinned charts/operators.

### LOW

**L1 — Right-size the stack: name one or two operators to retire. (Effort: L, optional) — DECIDED: KEEP (won't fix).** Strimzi (single broker, RF=1) and the ScyllaDB operator (members=1) are *deliberately* retained: operating a real distributed-systems stack is a primary goal of this platform (system development / learning), so the operator overhead is accepted tuition, not waste. Verified config confirms the single-instance footprint; this is an explicit choice, not an oversight. Revisit only if node resource pressure forces it.

**L2 — Add PDBs once apps reach ≥2 replicas (pairs with M1). (Effort: S)** Enables graceful drains; document the current single-node rollout blip.

**L3 — Add an alerting fallback channel (webhook/Telegram) alongside Resend SMTP. (Effort: S)** Today a Resend outage equals total alert silence — the alerting SPOF. — **⏸ ON HOLD** (deferred by decision; needs a chosen webhook/Telegram target).

**L4 — Store a copy of the Vault unseal keys offsite with the backups. (Effort: S)** They live only on the Pi filesystems; both-Pi loss loses them. — **✅ DONE** — `task deploy:vault-keys-backup` (ops `d049fc7`) pulls the Shamir unseal keys + root token off the Pis to the controller (0600, gitignored). Moving that copy to true-offsite custody (password manager / encrypted USB) is the remaining manual step.

---

## Maturity Assessment & Verdict

schnappy is best characterized as **over-engineered for its substrate and under-enforced on its own guardrails** — an unusual but internally coherent profile for a serious learning lab. The engineering quality where it counts is real and above homelab norm:

- **GitOps discipline** that most production teams never reach: app-of-apps with directory-generator ApplicationSets, `ignoreDifferences` tuned to controller-managed fields, a deliberate CSA-over-SSA choice, and `prune: false` correctly applied to the stateful tier.
- **Pi-tier HA** that is textbook defense-in-depth: Patroni+Consul leader election, failover-transparent PgBouncer→HAProxy DB routing, a four-layer MinIO dual-active fence, and postmortem-driven tuning that demonstrates genuine operational maturity.
- **Correlated observability** — metrics↔traces↔logs via exemplars and derived fields, 26 alert groups, 43+ runbooks, a watchdog, and even disk-SMART alerting.
- **Consistent pod hardening** and a **sound auth model** wherever the JWT is actually validated.

The risk is concentrated in a small number of *toggles and missing automations*, not architecture: a root app that can self-destruct (H1), a production auth flag that quietly disables edge validation and turns three-layer defense into two (H2), a promotion path that is a manual hand-edit already drifting in the repo (H3), and a DR posture that has never been continuously proven (H4). All four are S/M effort.

**Verdict:** a high-quality, ambitious platform whose *stated* security and resilience posture currently exceeds its *configured* posture. The single-node substrate is an honest and acceptable constraint for its purpose; the only thing to insist on there is that the single-replica reality be named, not implied. Address the four HIGH items — none of which require new infrastructure — and the architecture's actual posture will match the one it already documents and aspires to. The foundations are strong enough that this is a matter of finishing, not rebuilding.
