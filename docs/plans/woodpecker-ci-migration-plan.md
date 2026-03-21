# Migrate CI/CD from Forgejo Actions to Woodpecker CI

## Context

Forgejo Actions runner uses `docker exec` inside a single container per job, so Docker `--log-driver=fluentd` only captures the entrypoint's stdout — not the actual CI step output. This is a fundamental limitation with no fix.

**Solution:** Replace Forgejo Actions with Woodpecker CI using the Kubernetes backend. Each pipeline step runs as a real k8s Pod, so Fluent-bit's existing pod log tail automatically captures CI logs in the `podlogs-*` Elasticsearch index. Service containers replace Testcontainers for integration tests (Postgres, Redis; later Kafka, ScyllaDB).

**Branch:** `feature/woodpecker-ci` (new, based on `master`)

## Architecture

```
Forgejo (git forge, stays)
  │ webhook (push/PR events)
  ▼
Woodpecker Server (woodpecker namespace)
  │ gRPC
  ▼
Woodpecker Agent (woodpecker namespace)
  │ creates pods via k8s API
  ▼
Pipeline Pods (woodpecker namespace)
  ├─ Step pods (build, test, deploy)
  ├─ Service containers (postgres, redis)
  └─ stdout → /var/log/containers/ → Fluent-bit → podlogs-* ES index
```

## Design Decisions

1. **Namespace:** `woodpecker` (dedicated, separate from `monitor`)
2. **Deployment:** Ansible playbook (`setup-woodpecker.yml`) using official Woodpecker Helm chart — same pattern as `setup-forgejo.yml`
3. **Image builds:** Kaniko (unprivileged, no Docker daemon needed)
4. **CD deploy step:** ServiceAccount `woodpecker-deployer` with scoped RBAC in `monitor` namespace — runs `helm upgrade` directly from a pod. No Ansible in the deploy step.
5. **Change detection:** CI uses Woodpecker's native `when.path` filtering (webhook payload). CD uses git-diff with fallback (deploy-state ConfigMap → CI_PREV_COMMIT_SHA → full deploy).
6. **CD state tracking:** ConfigMap `woodpecker-deploy-state` stores last-deployed commit hash (replaces `/var/lib/monitor-deploy-commit`)
7. **Secrets:** k8s Secrets in `woodpecker` namespace, injected into pipeline pods
8. **Parallel transition:** Both Forgejo Actions and Woodpecker run side-by-side during verification period

## Status

| Phase | Status |
|-------|--------|
| Phase 1: Ansible Playbook | DONE |
| Phase 2: Pipeline Files | DONE |
| Phase 3: Backend Test CI Profile | DONE |
| Phase 4: Vagrant Integration Test | DONE |
| Phase 5: Production Deployment | DONE |
| Phase 6: Cleanup | TODO |

## Lessons Learned

### From Vagrant testing
1. **k3s hairpin routing**: Pods cannot reach the node IP on ingress ports. Use CoreDNS NodeHosts to resolve ingress hostnames to the Traefik ClusterIP instead.
2. **Forgejo `webhook.ALLOWED_HOST_LIST`**: Forgejo blocks webhook delivery to internal/private IP addresses by default. Must set `ALLOWED_HOST_LIST=private` to allow delivery to k8s service addresses.
3. **Woodpecker v3 auth**: Session JWTs (type "sess") only work for GET. POST endpoints require either an API token (type "user") via `POST /api/user/token` with CSRF header, or Bearer token. The `POST /api/repos` takes `forge_remote_id` as a query parameter.
4. **Forgejo `must_change_password`**: `gitea admin user change-password` sets `must_change_password=true` by default. Must use `--must-change-password=false` flag.
5. **Webhook URL patching**: Woodpecker sets `WOODPECKER_HOST` as the webhook callback URL. Due to hairpin routing, webhooks must be patched post-activation to use internal k8s service DNS.
6. **Woodpecker pipeline API**: `POST /api/repos/{id}/pipelines` with `{"branch":"main"}` creates a "manual" event — `when: event: push` filters reject it. Don't use this as a fallback for webhook-triggered pipelines.
7. **Bash JSON parsing**: Piping curl JSON through bash variables (`echo "$VAR" | python3 -c ...`) can silently corrupt data. Use Python `urllib.request` directly for reliable API polling.
8. **Woodpecker namespace PodSecurity**: Use `baseline` enforce (pipeline pods need capabilities that `restricted` blocks). Pipeline step pods trigger `restricted` audit warnings but run fine under `baseline`.
9. **Unified Helm chart**: Woodpecker 3.x uses a single `woodpecker` chart (not separate `woodpecker-server`/`woodpecker-agent` charts). Set `server.enabled=true` and `agent.enabled=true`.

### From production deployment
10. **WOODPECKER_FORGEJO_URL dual purpose**: Used for BOTH browser OAuth redirects AND server-side token exchange. Cannot use internal ClusterIP (browser can't reach it). Must use external HTTPS URL + ensure server pod can reach it.
11. **CoreDNS NodeHosts for in-cluster ingress resolution**: Add Traefik ClusterIP for ingress hostnames (`git.pmon.dev`, `ci.pmon.dev`) to CoreDNS NodeHosts. This avoids hairpin routing while keeping the external HTTPS URL for browser compatibility. Mark entries with `# woodpecker-managed` for idempotent updates.
12. **kube-proxy DNAT changes target port in FORWARD chain**: Service port 443 maps to Traefik's container `targetPort: websecure` (8443). Network policies in the FORWARD chain see the post-DNAT port (8443), not the original service port (443). Must allow BOTH ports in NP egress rules.
13. **Woodpecker `from_secret` validated at parse time**: If a secret referenced by `from_secret` doesn't exist in Woodpecker's secret store, the entire pipeline fails to parse — even if the step would skip the secret at runtime. Secrets must be created in Woodpecker UI/API before the pipeline can run.
14. **Woodpecker v3 requires event filter in `when` blocks**: Pipeline-level `when` must include `event: push` (or other event type). Branch-only filters cause `[bad_habit]` errors and the pipeline is rejected.

### From CI pipeline testing
15. **Woodpecker shallow clone + no auth in steps**: The clone plugin does a shallow clone and subsequent steps cannot `git fetch` (no credentials). `depth: 0` in clone settings doesn't help — the clone is still depth 1. Use Woodpecker's native `when.path` filtering (uses webhook payload) instead of git-diff-based change detection for CI.
16. **Git safe.directory required**: Clone runs as one user, step containers run as another. Git blocks all operations with "dubious ownership" error. Must add `git config --global --add safe.directory '*'` at the start of any step that uses git commands.
17. **Woodpecker commands share shell session**: All `-` commands in a step run in the same shell. `cd frontend` persists, so subsequent `cd frontend` tries `frontend/frontend/`. Use a single `cd` followed by bare commands.
18. **CiTestConfiguration needs TestHttpServer**: When `@Profile("ci")` skips TestcontainersConfiguration, its static initializer (TestHttpServer.start(), allowLoopback) is also skipped. CiTestConfiguration must duplicate this initialization.
19. **SecurityConfigTest FK cleanup**: With shared CI database (not Testcontainers per-test), `userRepository.deleteAll()` fails on FK constraints from registration_approvals, channels, user_groups. Must clean dependent tables first.
20. **SonarQube internal URL**: Pipeline pods can't reach `sonar.pmon.dev` via node IP (hairpin). Use internal service URL `http://monitor-sonarqube.monitor.svc:9000` as `sonar_host_url` secret in Woodpecker.

## Phase 1: Ansible Playbook — Woodpecker Deployment

### New: `deploy/ansible/playbooks/setup-woodpecker.yml`

1. Create `woodpecker` namespace (PodSecurity: baseline enforce, restricted audit/warn)
2. Register OAuth2 app in Forgejo via API (`POST /api/v1/user/applications/oauth2`)
   - Redirect URI: `https://ci.pmon.dev/authorize` (prod) or `http://ci.vagrant.test/authorize` (Vagrant)
   - Captures `client_id` and `client_secret`
3. Create k8s Secrets:
   - `woodpecker-server-secret`: `WOODPECKER_AGENT_SECRET` (shared server↔agent token)
   - `woodpecker-forgejo-secret`: OAuth `client_id` + `client_secret`
   - `woodpecker-ci-secrets`: `SONAR_TOKEN`, `SONAR_HOST_URL`, registry credentials
4. Deploy Woodpecker server: `helm upgrade --install woodpecker-server oci://ghcr.io/woodpecker-ci/helm/woodpecker-server`
   - Env: `WOODPECKER_HOST`, `WOODPECKER_FORGEJO=true`, `WOODPECKER_FORGEJO_URL`, `WOODPECKER_ADMIN`
   - Ingress: `ci.pmon.dev` (DNS-01 TLS via `letsencrypt-dns`)
5. Deploy Woodpecker agent: `helm upgrade --install woodpecker-agent oci://ghcr.io/woodpecker-ci/helm/woodpecker-agent`
   - Env: `WOODPECKER_BACKEND=kubernetes`, `WOODPECKER_BACKEND_K8S_NAMESPACE=woodpecker`, `WOODPECKER_BACKEND_K8S_STORAGE_CLASS=local-path`, `WOODPECKER_BACKEND_K8S_VOLUME_SIZE=2Gi`, `WOODPECKER_MAX_WORKFLOWS=4`
6. Create RBAC for deploy step:
   - `ServiceAccount: woodpecker-deployer` in `woodpecker` namespace
   - `ClusterRole: woodpecker-deployer` with helm-level permissions (deployments, services, configmaps, secrets, statefulsets, ingresses, jobs, cronjobs, pvcs, networkpolicies, serviceaccounts, roles, rolebindings, clusterroles, clusterrolebindings, namespaces read)
   - `ClusterRoleBinding` binding SA to ClusterRole
   - Also needs read on namespaces/nodes for helm operations
7. Create ConfigMap `woodpecker-deploy-state` with `last-deployed-commit: ""`
8. Apply network policies:
   - Default deny ingress+egress in `woodpecker` namespace
   - Server: ingress from kube-system (Traefik :8000), from agent (:9000); egress to Forgejo (forgejo ns :3000), DNS
   - Agent: egress to server (:9000), k8s API (:443/:6443), DNS
   - Pipeline pods: egress to k8s API (:443/:6443), SonarQube (monitor ns :9000), Forgejo registry (forgejo ns :3000), external HTTPS (:443), DNS; ingress for service containers (inter-pod on workspace)
9. Wait for server + agent ready

### New: `deploy/ansible/vars/woodpecker.yml`

```yaml
woodpecker_namespace: woodpecker
woodpecker_host: "ci.pmon.dev"
woodpecker_server_chart_version: "0.4.2"  # pin to latest stable
woodpecker_agent_chart_version: "0.4.2"
```

### Modify: `Taskfile.yml`

Add `deploy:woodpecker` task.

### Files
| File | Action |
|------|--------|
| `deploy/ansible/playbooks/setup-woodpecker.yml` | NEW |
| `deploy/ansible/vars/woodpecker.yml` | NEW |
| `Taskfile.yml` | MODIFY — add deploy:woodpecker task |

## Phase 2: Pipeline Files

### New: `.woodpecker/ci.yaml`

CI pipeline (non-master branches):

```yaml
when:
  - branch:
      exclude: master

steps:
  - name: detect-changes
    image: alpine/git:latest
    commands:
      - git fetch origin master:refs/remotes/origin/master 2>/dev/null || true
      - BASE=$(git merge-base origin/master HEAD 2>/dev/null || echo "")
      - '[ -z "$BASE" ] && BASE="4b825dc642cb6eb9a060e54bf899d15f71747600"'
      - backend=false; frontend=false; helm=false; infra=false
      - git diff --name-only "$BASE" HEAD | grep -q '^backend/' && backend=true || true
      - git diff --name-only "$BASE" HEAD | grep -q '^frontend/' && frontend=true || true
      - git diff --name-only "$BASE" HEAD | grep -q '^infra/helm/' && helm=true || true
      - git diff --name-only "$BASE" HEAD | grep -qE '^deploy/|^\.woodpecker/' && infra=true || true
      - echo "$backend" > .changes-backend
      - echo "$frontend" > .changes-frontend
      - echo "$helm" > .changes-helm
      - echo "$infra" > .changes-infra
      - echo "Changes — backend:$backend frontend:$frontend helm:$helm infra:$infra"

  - name: backend-test
    image: eclipse-temurin:25-jdk
    environment:
      SPRING_PROFILES_ACTIVE: test,ci
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/monitor
      SPRING_DATASOURCE_USERNAME: postgres
      SPRING_DATASOURCE_PASSWORD: test
      SPRING_DATA_REDIS_HOST: redis
    commands:
      - '[ "$(cat .changes-backend)" = "true" ] || exit 0'
      - cd backend && ./gradlew test --no-daemon
    depends_on: [detect-changes]
    backend_options:
      kubernetes:
        resources:
          requests: { cpu: 500m, memory: 2Gi }
          limits: { cpu: 4000m, memory: 4Gi }

  - name: backend-sonar
    image: eclipse-temurin:25-jdk
    environment:
      SONAR_TOKEN:
        from_secret: sonar_token
      SONAR_HOST_URL:
        from_secret: sonar_host_url
    commands:
      - '[ "$(cat .changes-backend)" = "true" ] || exit 0'
      - cd backend && ./gradlew sonar --no-daemon
    depends_on: [backend-test]

  - name: frontend-test
    image: node:22-bookworm-slim
    commands:
      - '[ "$(cat .changes-frontend)" = "true" ] || exit 0'
      - cd frontend && npm ci --silent
      - cd frontend && npx tsc --noEmit
      - cd frontend && npm run test:coverage
    depends_on: [detect-changes]

  - name: frontend-sonar
    image: node:22-bookworm-slim
    environment:
      SONAR_TOKEN:
        from_secret: sonar_token
      SONAR_HOST_URL:
        from_secret: sonar_host_url
    commands:
      - '[ "$(cat .changes-frontend)" = "true" ] || exit 0'
      - cd frontend && npx sonarqube-scanner
    depends_on: [frontend-test]

  - name: helm-lint
    image: alpine/helm:latest
    commands:
      - '[ "$(cat .changes-helm)" = "true" ] || exit 0'
      - cd infra/helm && helm lint .
    depends_on: [detect-changes]

services:
  - name: postgres
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: monitor
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: test
  - name: redis
    image: redis:7-alpine
```

### New: `.woodpecker/cd.yaml`

CD pipeline (master branch):

```yaml
when:
  - branch: master
    event: push

steps:
  - name: detect-changes
    image: bitnami/kubectl:latest
    commands:
      - |
        LAST=$(kubectl get configmap woodpecker-deploy-state -n woodpecker \
          -o jsonpath='{.data.last-deployed-commit}' 2>/dev/null || echo "")
        if [ -n "$LAST" ] && git rev-parse "$LAST" >/dev/null 2>&1; then
          BASE="$LAST"
        elif git rev-parse HEAD~1 >/dev/null 2>&1; then
          BASE="HEAD~1"
        else
          BASE="4b825dc642cb6eb9a060e54bf899d15f71747600"
        fi
      - backend=false; frontend=false; helm=false; deploy=false; game=false
      - git diff --name-only "$BASE" HEAD | grep -q '^backend/' && backend=true || true
      - git diff --name-only "$BASE" HEAD | grep -q '^frontend/' && frontend=true || true
      - git diff --name-only "$BASE" HEAD | grep -q '^infra/helm/' && helm=true || true
      - git diff --name-only "$BASE" HEAD | grep -q '^games/' && game=true || true
      - git diff --name-only "$BASE" HEAD | grep -qE '^deploy/|^\.woodpecker/' && deploy=true || true
      - '[ "$game" = "true" ] && frontend=true || true'
      - echo "$backend" > .changes-backend
      - echo "$frontend" > .changes-frontend
      - echo "$helm" > .changes-helm
      - echo "$deploy" > .changes-deploy
    backend_options:
      kubernetes:
        serviceAccountName: woodpecker-deployer

  # ---- Test Gates (parallel, informational) ----
  - name: backend-test
    image: eclipse-temurin:25-jdk
    environment:
      SPRING_PROFILES_ACTIVE: test,ci
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/monitor
      SPRING_DATASOURCE_USERNAME: postgres
      SPRING_DATASOURCE_PASSWORD: test
      SPRING_DATA_REDIS_HOST: redis
    commands:
      - '[ "$(cat .changes-backend)" = "true" ] || exit 0'
      - cd backend && ./gradlew test --no-daemon
    depends_on: [detect-changes]

  - name: backend-sonar
    image: eclipse-temurin:25-jdk
    environment:
      SONAR_TOKEN:
        from_secret: sonar_token
      SONAR_HOST_URL:
        from_secret: sonar_host_url
    commands:
      - '[ "$(cat .changes-backend)" = "true" ] || exit 0'
      - cd backend && ./gradlew sonar --no-daemon -Dsonar.qualitygate.wait=false
    depends_on: [backend-test]

  - name: frontend-test
    image: node:22-bookworm-slim
    commands:
      - '[ "$(cat .changes-frontend)" = "true" ] || exit 0'
      - cd frontend && npm ci --silent && npx tsc --noEmit && npm run test:coverage
    depends_on: [detect-changes]

  - name: frontend-sonar
    image: node:22-bookworm-slim
    environment:
      SONAR_TOKEN:
        from_secret: sonar_token
      SONAR_HOST_URL:
        from_secret: sonar_host_url
    commands:
      - '[ "$(cat .changes-frontend)" = "true" ] || exit 0'
      - cd frontend && npx sonarqube-scanner -Dsonar.qualitygate.wait=false
    depends_on: [frontend-test]

  - name: helm-lint
    image: alpine/helm:latest
    commands:
      - '[ "$(cat .changes-helm)" = "true" ] || exit 0'
      - cd infra/helm && helm lint .
    depends_on: [detect-changes]

  # ---- Build Backend Image (Kaniko) ----
  - name: build-backend-jar
    image: eclipse-temurin:25-jdk
    commands:
      - '[ "$(cat .changes-backend)" = "true" ] || exit 0'
      - cd backend && ./gradlew bootJar --no-daemon -x test
      - mkdir -p .docker-context
      - jar=$(ls build/libs/*.jar | grep -v plain | head -1)
      - cp "$jar" .docker-context/app.jar
      - cp Dockerfile.runtime .docker-context/Dockerfile
    depends_on: [backend-test, backend-sonar]

  - name: push-backend-image
    image: gcr.io/kaniko-project/executor:debug
    environment:
      REGISTRY_USER:
        from_secret: registry_user
      REGISTRY_TOKEN:
        from_secret: registry_token
    commands:
      - '[ "$(cat .changes-backend)" = "true" ] || exit 0'
      - mkdir -p /kaniko/.docker
      - |
        echo "{\"auths\":{\"git.pmon.dev\":{\"username\":\"$REGISTRY_USER\",\"password\":\"$REGISTRY_TOKEN\"}}}" > /kaniko/.docker/config.json
      - GIT_HASH=$(echo $CI_COMMIT_SHA | cut -c1-7)
      - |
        /kaniko/executor \
          --context=backend/.docker-context \
          --destination=git.pmon.dev/schnappy/monitor:$GIT_HASH \
          --cache=true \
          --cache-repo=git.pmon.dev/schnappy/monitor/cache
    depends_on: [build-backend-jar]

  # ---- Build Frontend Image (Kaniko) ----
  - name: build-frontend-dist
    image: node:22-bookworm-slim
    commands:
      - '[ "$(cat .changes-frontend)" = "true" ] || exit 0'
      - cd frontend && npm ci --silent
      - GIT_HASH=$(echo $CI_COMMIT_SHA | cut -c1-7)
      - BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      - VITE_GIT_HASH=$GIT_HASH VITE_BUILD_TIME=$BUILD_TIME npm run build
      - mkdir -p .docker-context
      - cp -r dist .docker-context/
      - cp Dockerfile.runtime .docker-context/Dockerfile
      - cp nginx.conf nginx.conf.template security-headers.conf security-headers-base.conf docker-entrypoint.sh .docker-context/
    depends_on: [frontend-test, frontend-sonar]

  - name: push-frontend-image
    image: gcr.io/kaniko-project/executor:debug
    environment:
      REGISTRY_USER:
        from_secret: registry_user
      REGISTRY_TOKEN:
        from_secret: registry_token
    commands:
      - '[ "$(cat .changes-frontend)" = "true" ] || exit 0'
      - mkdir -p /kaniko/.docker
      - |
        echo "{\"auths\":{\"git.pmon.dev\":{\"username\":\"$REGISTRY_USER\",\"password\":\"$REGISTRY_TOKEN\"}}}" > /kaniko/.docker/config.json
      - GIT_HASH=$(echo $CI_COMMIT_SHA | cut -c1-7)
      - |
        /kaniko/executor \
          --context=frontend/.docker-context \
          --destination=git.pmon.dev/schnappy/monitor-frontend:$GIT_HASH \
          --cache=true \
          --cache-repo=git.pmon.dev/schnappy/monitor-frontend/cache
    depends_on: [build-frontend-dist]

  # ---- Deploy via Helm ----
  - name: deploy
    image: alpine/helm:latest
    commands:
      - |
        SHOULD_DEPLOY=false
        [ "$(cat .changes-backend)" = "true" ] && SHOULD_DEPLOY=true
        [ "$(cat .changes-frontend)" = "true" ] && SHOULD_DEPLOY=true
        [ "$(cat .changes-helm)" = "true" ] && SHOULD_DEPLOY=true
        [ "$(cat .changes-deploy)" = "true" ] && SHOULD_DEPLOY=true
        [ "$SHOULD_DEPLOY" = "false" ] && echo "No deployable changes" && exit 0
      - GIT_HASH=$(echo $CI_COMMIT_SHA | cut -c1-7)
      - BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      - |
        helm upgrade --install monitor ./infra/helm \
          --namespace monitor \
          --values ./infra/helm/production-values.yaml \
          --set "app.gitHash=$GIT_HASH" \
          --set "app.buildTime=$BUILD_TIME" \
          --set "app.image.tag=$GIT_HASH" \
          --set "frontend.image.tag=$GIT_HASH" \
          --wait --timeout 600s
      - |
        wget -qO /usr/local/bin/kubectl "https://dl.k8s.io/release/$(wget -qO- https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x /usr/local/bin/kubectl
        kubectl patch configmap woodpecker-deploy-state -n woodpecker \
          --type merge -p "{\"data\":{\"last-deployed-commit\":\"$GIT_HASH\"}}"
    depends_on: [push-backend-image, push-frontend-image, helm-lint]
    backend_options:
      kubernetes:
        serviceAccountName: woodpecker-deployer

services:
  - name: postgres
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: monitor
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: test
  - name: redis
    image: redis:7-alpine
```

**Note on deploy step:** The deploy step needs production Helm values. Two options:
- (a) Commit a `production-values.yaml` (non-secret values only, secrets via `existingSecret`) to the repo
- (b) Store production values in a ConfigMap, mount in the deploy pod
- Recommendation: (a) — production values are already non-secret (secrets come from Vault/ESO `existingSecret` refs)

**Note on game export:** The CD currently runs `task game:export` for Godot game asset export. This requires Godot CLI which won't be in the Node container. Either: pre-export and commit game assets, or add a separate step with a Godot image. Address in Phase 2 implementation.

### Files
| File | Action |
|------|--------|
| `.woodpecker/ci.yaml` | NEW |
| `.woodpecker/cd.yaml` | NEW |
| `infra/helm/production-values.yaml` | NEW — extracted from Ansible `monitor_values` dict (non-secret values only) |

## Phase 3: Backend Test CI Profile

### New: `backend/src/test/resources/application-ci.yml`

```yaml
spring:
  datasource:
    url: jdbc:postgresql://${POSTGRES_HOST:postgres}:${POSTGRES_PORT:5432}/${POSTGRES_DB:monitor}
    username: ${POSTGRES_USER:postgres}
    password: ${POSTGRES_PASSWORD:test}
  data:
    redis:
      host: ${REDIS_HOST:redis}
      port: ${REDIS_PORT:6379}
```

### Modify: `backend/src/test/java/io/schnappy/TestcontainersConfiguration.java`

Add `@Profile("!ci")`:

```java
@TestConfiguration(proxyBeanMethods = false)
@Profile("!ci")
public class TestcontainersConfiguration {
    // ... unchanged — PostgreSQL + Redis Testcontainers + Kafka/ScyllaDB mocks
}
```

### New: `backend/src/test/java/io/schnappy/CiTestConfiguration.java`

Provides Kafka/ScyllaDB mocks when CI profile is active (since TestcontainersConfiguration is skipped):

```java
@TestConfiguration(proxyBeanMethods = false)
@Profile("ci")
public class CiTestConfiguration {
    @Bean KafkaTemplate kafkaTemplate() { return mock(KafkaTemplate.class); }
    @Bean CqlSession cqlSession() { /* same mock setup */ }
}
```

### Modify: All 18 test classes that `@Import(TestcontainersConfiguration.class)`

Add `@Import(CiTestConfiguration.class)` alongside existing import:

```java
@Import({TestcontainersConfiguration.class, CiTestConfiguration.class})
```

Only one will activate based on the active profile.

### Files
| File | Action |
|------|--------|
| `backend/src/test/resources/application-ci.yml` | NEW |
| `backend/src/test/java/io/schnappy/TestcontainersConfiguration.java` | MODIFY — add `@Profile("!ci")` |
| `backend/src/test/java/io/schnappy/CiTestConfiguration.java` | NEW |
| 18 test classes | MODIFY — add `CiTestConfiguration.class` to `@Import` |

## Phase 4: Vagrant Integration Test

### New: `tests/ansible/test-woodpecker.yml`

Following existing test patterns (`test-cicd.yml`, `test-elk.yml`):

1. **Phase 1:** Deploy Forgejo (reuse from test-cicd pattern)
   - Helm chart, admin user, DNS in CoreDNS, ingress
2. **Phase 2:** Deploy Woodpecker
   - Create namespace, register OAuth app via Forgejo API
   - Deploy server + agent via Helm
   - Create RBAC, network policies, secrets
3. **Phase 3:** Verify Woodpecker infrastructure
   - Server pod running, API responds (health check)
   - Agent pod running, connected to server
4. **Phase 4:** Create test repo + trigger pipeline
   - Create repo in Forgejo via API
   - Activate repo in Woodpecker via API
   - Push a minimal `.woodpecker/ci.yaml` that runs `echo "hello"`
   - Poll Woodpecker API for pipeline completion (retry loop)
   - Verify pipeline succeeded
5. **Phase 5:** Verify CI logs in Elasticsearch (if ELK enabled in test)
   - Query `podlogs-*` for logs from `woodpecker` namespace
   - Verify "hello" string appears in logs
6. **Phase 6:** Verify RBAC
   - `kubectl auth can-i` checks for `woodpecker-deployer` SA
7. **Phase 7:** Summary with PASS/FAIL tally

### Modify: `Taskfile.yml`

Add `test:woodpecker` task:
```yaml
test:woodpecker:
  desc: Test Woodpecker CI deployment (Vagrant)
  deps: [deploy:install]
  cmds:
    - cmd: vagrant destroy -f 2>/dev/null; true
    - cmd: vagrant up k3s
    - defer: vagrant halt
    - cmd: >-
        cd deploy/ansible && venv/bin/ansible-playbook
        -i inventory/vagrant.yml
        ../../tests/ansible/test-woodpecker.yml
        -e @vars/vault.yml -e @vars/vault-vagrant.yml
```

### Files
| File | Action |
|------|--------|
| `tests/ansible/test-woodpecker.yml` | NEW |
| `Taskfile.yml` | MODIFY — add test:woodpecker task |

## Phase 5: Production Deployment

1. Add Woodpecker vars to `deploy/ansible/vars/production.yml`
2. Add DNS for `ci.pmon.dev` in Unbound config on router (internal, DNS-01)
3. Add `deploy:woodpecker` to `deploy:full` in Taskfile (after setup-forgejo)
4. Run `task deploy:woodpecker`
5. Log into Woodpecker UI at `ci.pmon.dev`, activate `schnappy/monitor` repo
6. Push `.woodpecker/` to a feature branch → verify CI pipeline
7. Run both systems in parallel for verification
8. Disable Forgejo Actions runner after verification

### Files
| File | Action |
|------|--------|
| `deploy/ansible/vars/production.yml` | MODIFY — add woodpecker vars |
| `Taskfile.yml` | MODIFY — add deploy:woodpecker to deploy:full |

## Phase 6: Cleanup

### Delete
- `.github/workflows/ci.yml`
- `.github/workflows/cd.yml`
- `infra/ci-images/java/Dockerfile`
- `infra/ci-images/node/Dockerfile`
- `deploy/ansible/vars/ci-runner.yml`

### Modify
- `deploy/ansible/playbooks/setup-forgejo.yml` — Remove Phase 2 (runner install, config, systemd, CI images, sudoers). Keep Phase 1 (Forgejo Helm deploy)
- `infra/helm/templates/fluentbit-configmap.yaml` — Remove forward input for CI logs (port 24224) since pipeline pod logs are captured by tail input. Optionally add namespace-based rewrite tag to route `woodpecker` namespace logs to `ci-logs-*` index
- `infra/helm/templates/fluentbit-daemonset.yaml` — Remove hostPort 24224
- `infra/helm/templates/network-policies.yaml` — Remove Fluent-bit ingress rule for port 24224
- `CLAUDE.md` — Update CI/CD section, architecture diagram, resource table, key files

### Files
| File | Action |
|------|--------|
| `.github/workflows/ci.yml` | DELETE |
| `.github/workflows/cd.yml` | DELETE |
| `infra/ci-images/java/Dockerfile` | DELETE |
| `infra/ci-images/node/Dockerfile` | DELETE |
| `deploy/ansible/vars/ci-runner.yml` | DELETE |
| `deploy/ansible/playbooks/setup-forgejo.yml` | MODIFY — remove runner section |
| `infra/helm/templates/fluentbit-configmap.yaml` | MODIFY — remove forward input |
| `infra/helm/templates/fluentbit-daemonset.yaml` | MODIFY — remove hostPort 24224 |
| `infra/helm/templates/network-policies.yaml` | MODIFY — remove 24224 ingress |
| `CLAUDE.md` | MODIFY — update CI/CD docs |

## Resource Impact

| Pod | CPU req/limit | Memory req/limit | Notes |
|-----|---------------|------------------|-------|
| Woodpecker Server | 100m / 500m | 128Mi / 256Mi | Permanent |
| Woodpecker Agent | 100m / 500m | 128Mi / 256Mi | Permanent |
| Pipeline pods | varies | varies | Transient (during builds only) |
| **Net change** | **+200m idle** | **+256Mi idle** | Lighter than host runner |

Removes: forgejo-runner systemd process (host resources), ci-java/ci-node Docker images, Fluent-bit forward input overhead.

## Verification

1. `task test:woodpecker` — Vagrant: Woodpecker deploys, pipeline runs, logs captured
2. Push to feature branch → Woodpecker CI runs tests → passes
3. Merge to master → Woodpecker CD builds images (Kaniko) → deploys via Helm
4. Check Kibana `podlogs-*` for pipeline pod logs from `woodpecker` namespace
5. `kubectl get pods -n woodpecker` — server + agent running, no pipeline pods lingering
6. Forgejo Actions disabled, runner stopped — no regressions

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Woodpecker Forgejo integration is "experimental" | Codeberg uses it in production; Vagrant test verifies |
| Kaniko slower than native Docker builds | `--cache=true` with registry-based layer caching |
| RWO PVC limits parallel steps on multi-node | Single-node: no issue. Sequential steps as fallback |
| Service container DNS resolution | Woodpecker k8s backend creates headless Services; verified in Vagrant |
| Kaniko registry auth | Docker config.json written from secrets in step |
| Game export needs Godot CLI | Pre-export and commit assets, or add Godot container step |

## Open Questions

1. **Production values file:** Extract `monitor_values` from `production.yml` to a committed `infra/helm/production-values.yaml` (non-secret values only)? Or mount from ConfigMap?
2. **Game export:** Current CD uses `task game:export` (Godot CLI). Options: (a) commit exported assets, (b) Godot Docker image step, (c) skip game rebuild in Woodpecker initially
3. **Vault secrets for Woodpecker:** Store Woodpecker secrets (OAuth, agent token) in Vault + ESO like other secrets? Or keep as direct k8s Secrets since they're infra-level?
