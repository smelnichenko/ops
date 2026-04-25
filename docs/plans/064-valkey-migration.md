# Plan 064: Migrate from Redis to Valkey (operator-managed, full rename)

## Context

Redis Labs changed Redis's license in 2024 from BSD-3 to RSALv2/SSPLv1. The
Linux Foundation + AWS/Google/Oracle/Snap/Ericsson forked 7.2.4 into
**Valkey** (BSD-3). Valkey 8.x is a drop-in replacement: same wire protocol,
same RDB/AOF formats, same CLI (`valkey-cli` aliases `redis-cli`), same
Spring Data Redis / Lettuce client compatibility.

We're moving from a hand-rolled `Deployment` to the **Valkey Operator** so
HA, replication, backup/restore, and config drift are managed declaratively
by a CRD instead of by us. Even at our current single-replica size, that
buys: auto-failover when we add a second replica, automated TLS cert
rotation if we ever turn TLS on, and config-as-CR that Argo CD reconciles
without us having to template StatefulSet/Deployment internals ourselves.

### Operator choice

Use **`hyperspike/valkey-operator`** (https://github.com/hyperspike/valkey-operator,
Apache 2.0). Reasons:

- Maintained, used in production by Hyperspike, regular releases.
- CRDs: `Valkey` (single + replica + cluster modes), `ValkeyReplication`.
- Manages StatefulSet, Service, ConfigMap, PodDisruptionBudget, Secret rotation.
- Helm chart at `oci://registry-1.docker.io/bitnamicharts/valkey-operator`-style
  install (or `helm install valkey-operator hyperspike/valkey-operator`).
- Lightweight: ~50 MiB operator pod, no extra controller pods per Valkey.

Alternative considered + rejected:
- **Bitnami `valkey` Helm chart** — not an operator, just templates; doesn't
  give us the CRD-driven reconciliation we want for ephemeral envs (Plan 067).
- **`valkey-io/valkey-operator`** — exists but very early; not yet at v1.0.
  Re-evaluate when it stabilizes.

### Why a deep rename (not just image swap)

- Every surface that still says `redis` is a license-risk signal in a
  repo audit and a cognitive hazard in incident triage.
- The Spring Data Redis *library* keeps its name (Spring hasn't shipped a
  `spring-boot-starter-data-valkey`), but everything the schnappy stack
  owns — chart templates, Kubernetes Service/Secret names, labels, env
  vars, dashboards, PVC names — can be renamed consistently.

## What gets renamed vs what stays

### Renamed (everything we own)

| Surface | Before | After |
|---|---|---|
| Chart template files | `schnappy-data/templates/redis-*.yaml` | `valkey-*.yaml` |
| Chart helpers | `schnappy.redis.labels`, `schnappy.redis.serviceName`, `schnappy.redis.secretName` | `schnappy.valkey.*` |
| Helm values key | `redis: { image, password, resources, ... }` | `valkey: { ... }` |
| Container image | `redis:7-alpine` | `valkey/valkey:8.1-alpine` |
| Container name | `redis` | `valkey` |
| Deployment / Service / Secret / PVC metadata.name | `schnappy-redis` | `schnappy-valkey` |
| Label `app.kubernetes.io/component` | `redis` | `valkey` |
| Label `app.kubernetes.io/name` | (follows chart) | unchanged (`schnappy`) |
| Service DNS name apps resolve | `schnappy-redis.schnappy.svc` | `schnappy-valkey.schnappy.svc` |
| Secret name referenced by apps | `schnappy-redis` | `schnappy-valkey` |
| Secret key inside Secret | `REDIS_PASSWORD` | `VALKEY_PASSWORD` |
| ExternalSecret name | `schnappy-redis` | `schnappy-valkey` |
| ExternalSecret remoteRef path | `secret/schnappy/redis` | `secret/schnappy/valkey` |
| Vault KV path (set by seed-vault-secrets) | `secret/schnappy/redis` | `secret/schnappy/valkey` |
| Env vars in app Deployment (`app`, `chat`, `admin`, `chess`, `site`) | `REDIS_HOST`, `REDIS_PASSWORD` | `VALKEY_HOST`, `VALKEY_PASSWORD` |
| Spring property placeholders in `application.yml` (monitor/chat/admin/chess) | `${REDIS_HOST:localhost}`, `${REDIS_PASSWORD:}` | `${VALKEY_HOST:localhost}`, `${VALKEY_PASSWORD:}` |
| Woodpecker CI pipelines service-container + env | `redis:7-alpine` / `SPRING_DATA_REDIS_HOST: redis` | `valkey/valkey:8.1-alpine` / `SPRING_DATA_REDIS_HOST: valkey` (service container name "valkey" attached to same host alias) |
| Health probe command | `redis-cli -a "$REDIS_PASSWORD" ping` | `valkey-cli -a "$VALKEY_PASSWORD" ping` |
| NetworkPolicy selectors | `matchLabels: app.kubernetes.io/component: redis` | `valkey` |
| AuthorizationPolicy selectors | same | `valkey` |
| Grafana dashboard title / filename | `Redis` | `Valkey` |
| Velero backup annotation (if any) | `redis` | `valkey` |

### Stays (library-level, outside our control)

- `org.springframework.boot:spring-boot-starter-data-redis` — gradle dep name; Spring hasn't shipped a Valkey-rebranded starter.
- Java classes: `RedisTemplate`, `StringRedisTemplate`, `RedisSerializationContext`, `RedisCacheManager`, `RedisCacheConfiguration` — these come from `spring-data-redis`; renaming would require a shim/wrapper that buys nothing.
- Spring config keys: `spring.data.redis.host`, `spring.data.redis.password`, `spring.data.redis.port`. Spring Data Redis autoconfig binds to these. Our `application.yml` uses them to set Lettuce's connection params. Renaming them would silently break autoconfig (Spring wouldn't bind to `spring.data.valkey.*` — no such binding exists).
- Comments in app code that say `// Redis` — leave for a separate pass (mechanical; low value to bundle here).
- Woodpecker env var name `SPRING_DATA_REDIS_HOST` — this is the Spring property name written as an env var and is mandated by the lib; only the *value* changes.

This is the hard boundary: we rename everything on the Kubernetes side +
every chart/config surface we control; the Spring library's internal
names stay because `spring-data-redis` is the client, not the server we
run.

## Files touched (by repo)

### `schnappy/ops`

- `tests/ansible/*.yml` — any values blocks that reference `redis:` now say `valkey:` (using new operator CR shape)
- `tests/ansible/tasks/setup-test-redis.yml` → rename `setup-test-valkey.yml`; replaces the raw Deployment with a `Valkey` CR + waits for `.status.ready=true`
- `deploy/ansible/playbooks/seed-vault-secrets.yml` — rewrite the `redis` secret path to `valkey`
- `deploy/ansible/playbooks/setup-kubeadm.yml` — install valkey-operator alongside CNPG / Strimzi / ScyllaDB operators (one new `kubernetes.core.helm` task in Phase 11)

### `schnappy/platform`

- `helm/schnappy-data/values.yaml` — `redis:` → `valkey:` with new shape (operator CR fields, not raw image/replica counts)
- `helm/schnappy-data/templates/redis-*.yaml` → **delete** (Deployment/Service/Secret no longer hand-rolled)
- `helm/schnappy-data/templates/valkey-cr.yaml` — **new** — single `Valkey` CR (operator-owned StatefulSet/Service emerge from this)
- `helm/schnappy-data/templates/_helpers.tpl` — replace `redis` helpers with `valkey` helpers (no compat shim; we're doing a clean cut). Service-name helper now returns the operator's auto-generated Service name pattern (`<name>` from the Valkey CR).
- `helm/schnappy-data/templates/external-secrets.yaml` — ExternalSecret for `schnappy-valkey` Secret consumed by the Valkey CR's `auth.existingSecret`.
- `helm/schnappy-data/templates/network-policies.yaml` — update selector labels (operator labels pods with `app.kubernetes.io/managed-by: valkey-operator` + `valkey.hyperspike.io/instance: <name>`)
- `helm/schnappy/templates/app-deployment.yaml`, `chat-deployment.yaml`, `admin-deployment.yaml`, `chess-deployment.yaml`, `site-deployment.yaml`, `app-configmap.yaml` — rename env vars `REDIS_HOST` → `VALKEY_HOST`, `REDIS_PASSWORD` → `VALKEY_PASSWORD`, secret `schnappy-redis` → `schnappy-valkey`
- `helm/schnappy/templates/network-policies.yaml` — selector update
- `helm/schnappy-mesh/templates/authorization-policies.yaml` — selector update
- `helm/schnappy-observability/dashboards/redis.json` (if present) → `valkey.json`

### `schnappy/monitor`, `schnappy/chat`, `schnappy/admin`, `schnappy/chess`

- `src/main/resources/application.yml` — change property placeholders: `${REDIS_HOST}` → `${VALKEY_HOST}`, `${REDIS_PASSWORD}` → `${VALKEY_PASSWORD}`. Keep `spring.data.redis.*` as the config-key root (Spring lib contract).
- `.woodpecker/ci.yaml`, `.woodpecker/cd.yaml` — service container image → `valkey/valkey:8.1-alpine`, env var rename `SPRING_DATA_REDIS_HOST: redis` → `SPRING_DATA_REDIS_HOST: valkey` (the service container name), local dev env no longer exports `REDIS_HOST`; the service alias is `valkey`.
- `src/test/resources/application-ci.yml` — `${REDIS_HOST:redis}` → `${VALKEY_HOST:valkey}`.
- Testcontainers (any) — if they hardcode the `redis:7-alpine` tag, update to `valkey/valkey:8.1-alpine`. (Lettuce connects to either.)

### `schnappy/infra`

- Argo CD Application / PriorityClass entries that reference `schnappy-redis` → `schnappy-valkey`
- Any Velero-managed Backup CR that pinned `schnappy-redis` label selectors
- `priority-classes.yaml` entry name

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Existing k8s Secret `schnappy-redis` holds the password; rename deletes it → cache pods can't auth on rollout. | Vault has the source of truth. Seed the new `secret/schnappy/valkey` path before deploying; ESO will create `schnappy-valkey` Secret; rolling pod restart picks up the new env vars that reference the new Secret. Old `schnappy-redis` Secret is garbage-collected when the old ExternalSecret goes away. |
| PVC name changes (`data-schnappy-redis-0` → `data-schnappy-valkey-0`) orphan the old PV. | Cache is ephemeral — no state preserved. Delete old PVC after cutover. |
| App pods restarted with missing `VALKEY_HOST` env var while rolling. | Do chart rollout as one `helm upgrade`: both `schnappy-data` (new Secret + Deployment) and `schnappy` (app env vars reference new names) push simultaneously via Argo CD. Old-name pods stopped before new-name Secret lookups happen. |
| CI pipelines still pull `redis:7-alpine`; test job race with image update. | Bump all `.woodpecker/*.yaml` service containers in the same MR as the chart + app changes; Woodpecker will pick the new pipeline on next push. |
| Someone greps `redis` later expecting to find config. | `README.md` note under "Cache layer" explaining "Redis was replaced by Valkey (Plan 064); Spring Data Redis library remains because it's the client lib." |

## Verification

1. **Unit tests** — `./gradlew test` in each of monitor/chat/admin/chess with Testcontainers pointed at `valkey/valkey:8.1-alpine`. Exercises `StringRedisTemplate` against real Valkey.
2. **`task test:microservices`** — all 4 services reach Ready, chat presence over pub/sub works.
3. **`task test:dr`** — Velero backup + restore cycle on the renamed StatefulSet/PVC round-trips.
4. **Production smoke** — `kubectl exec` into `schnappy-valkey-0`, run `valkey-cli ping` → `PONG`. Check any monitor-service cache reads return data.
5. **`grep -r redis` in `platform/helm/` and the 4 services** — the only hits should be the Spring Data Redis library imports + `spring.data.redis.*` config keys + comments noting the library heritage.

## Vagrant tests are the merge gate (non-negotiable)

Before any of the 4 MRs merge to main, the full Vagrant matrix must pass on a
clean `vagrant destroy -f && vagrant up` from a branch that bundles all 4
changes together. The rename is atomic — staging it per-repo to main first
breaks the world between merges. So the Vagrant pass is what proves the whole
set is consistent.

Required to pass, in order:

1. `task test:microservices` — all 4 services Ready, `/api/chat/presence/online`
   returns 200, chat presence fanout over Valkey pub/sub works end-to-end.
2. `task test:dr` — Velero backup + restore cycle on the renamed StatefulSet/PVC
   round-trips cleanly; app data survives the kill/restore.
3. Per-service Gradle: `./gradlew test` inside `monitor`, `chat`, `admin`,
   `chess` with Testcontainers pinned to `valkey/valkey:8.1-alpine`. Exercises
   `StringRedisTemplate` against real Valkey (library stays Spring Data Redis;
   this proves the on-wire protocol compat holds).

If any of these fail the branch does not merge — don't chase "it'll work in
prod" fixes forward. Root-cause on vagrant, fix, re-run clean.

## Rollout

1. Merge the 4 repo MRs in this order (Woodpecker will chain):
   1. `schnappy/platform` (chart rename)
   2. `schnappy/monitor`, `schnappy/chat`, `schnappy/admin`, `schnappy/chess` (env var + `application.yml` + CI pipelines)
   3. `schnappy/ops` (vault seed-secrets path + Vagrant test values)
   4. `schnappy/infra` (Argo CD Application manifests)
2. Argo CD sync applies everything atomically in the `schnappy` namespace. Old pods drain → new pods start with `VALKEY_*` env vars → new Valkey Deployment takes over.
3. Verify in Grafana (metrics scraping still works — labels kept consistent).

## Out of scope

- Switching from Lettuce to a native Valkey client — no functionally different client exists.
- Renaming the `spring-boot-starter-data-redis` Gradle dep or internal Spring Data Redis classes.
- Converting to Valkey Cluster mode / HA cache — current single-replica is fine for the workload.
- Renaming `// Redis` / `/* Redis */` comments in app code — left for a chore PR.

## Execution order (for the agent running this plan)

1. Save this plan (done).
2. `platform`: rename chart files, templates, helpers, labels, Secret keys, Service/Deployment/PVC names. Bump `schnappy-data/Chart.yaml` version.
3. `platform`: update all `helm/schnappy/templates/*-deployment.yaml` + `app-configmap.yaml` to reference the new env var names + new Secret.
4. `ops`: update `seed-vault-secrets.yml` to write `secret/schnappy/valkey`. Update every Vagrant test that writes values files with `redis:` to use `valkey:` + new image tag.
5. `monitor`, `chat`, `admin`, `chess`: update `application.yml` placeholder names + `.woodpecker/*.yaml` service-container image + env var aliasing.
6. Run `./gradlew test` in each service with the new Testcontainers image.
7. `task test:microservices` end-to-end in Vagrant. Expect all 4 pods Ready, `/api/chat/presence/online` returns 200.
8. `task test:dr` — backup/restore cycle passes.
9. PRs merged in dependency order (platform → services → ops → infra). Argo CD picks up and rolls.
