# SonarQube Setup Automation + SSO

## Context

SonarQube loses all configuration on fresh deploy (new PVC = empty DB). Currently requires manual API calls to: change admin password, generate tokens, create projects, set up quality gates. This has bitten us twice during the namespace migration. Automate it via a Helm hook Job, following the existing pattern (ES ILM job, Kafka topics job, ScyllaDB schema job).

Additionally, SQ Community Edition supports HTTP header SSO — we can use Traefik forward-auth with Forgejo OAuth to provide SSO without upgrading to Developer Edition.

## Part 1: Setup Automation Job

### Helm Hook Job (`sonarqube-setup-job.yaml`)

**Pattern:** Same as `elasticsearch-ilm-job.yaml`
- Helm hook: `post-install`, `post-upgrade`
- Hook weight: 15 (after SQ deployment at default weight)
- Hook delete policy: `before-hook-creation`
- Image: `curlimages/curl:8.12.1`
- `backoffLimit: 5`, `activeDeadlineSeconds: 600` (SQ takes ~2min to start)
- `readOnlyRootFilesystem: true`, drop all caps

**Steps (idempotent):**

1. **Wait for SQ** — poll `GET /api/system/status` until `"status":"UP"` (max 120 retries × 5s)

2. **Change admin password** — try login with Vault password first. If 401, try `admin:admin` (fresh DB). If default works, change via `POST /api/users/change_password`. If Vault password works, skip.

3. **Generate analysis token** — `POST /api/user_tokens/generate` with `name=ci&type=GLOBAL_ANALYSIS_TOKEN`. If token name exists (409), skip. Store token in k8s secret `schnappy-sonarqube-token` for Woodpecker to read.

4. **Create quality gates:**
   - `Service` gate (80% coverage) — copy from "Sonar way", rename, set as default
   - `Frontend` gate (70% coverage) — copy from "Sonar way", rename, update coverage threshold
   - Skip if gates already exist

5. **Create projects** — iterate over `sonarqube.projects` values list. `POST /api/projects/create` with `project=<key>&name=<name>`. Skip if exists (400 already exists).

6. **Assign quality gates** — `POST /api/qualitygates/select` for each project. Frontend projects get `Frontend` gate, others get `Service`.

**New Helm values:**
```yaml
sonarqube:
  setup:
    enabled: true  # auto-setup on deploy
    projects:
      - key: schnappy-monitor
        name: Schnappy Monitor
      - key: schnappy-admin
        name: Schnappy Admin
      - key: schnappy-chat
        name: Schnappy Chat
      - key: schnappy-chess
        name: Schnappy Chess
      - key: schnappy-gateway
        name: Schnappy Gateway
      - key: schnappy-site
        name: Schnappy Site
        gate: Frontend
      - key: schnappy-infrastructure
        name: Schnappy Infrastructure
```

### Token Distribution

The job creates a k8s secret `schnappy-sonarqube-token` with key `SONAR_TOKEN`. Woodpecker pipelines read this via `backend_options.kubernetes.secrets` instead of the manually managed `woodpecker-ci-secrets`. This makes the token self-healing — every Helm upgrade regenerates it if missing.

Actually — token generation is NOT idempotent (SQ returns 400 if token name exists). Better approach: check if token exists first via `GET /api/user_tokens/search`, only generate if missing. Store in the existing `schnappy-sonarqube` secret by patching it with kubectl.

### Network Policy

The setup job needs to reach SQ (port 9000) and the k8s API (for secret patching). Add NP rules similar to the ES ILM job pattern.

## Part 2: SSO via Traefik Forward-Auth

### How it works

1. User visits `sonar.pmon.dev`
2. Traefik checks forward-auth middleware → redirects to Forgejo OAuth
3. User authenticates with Forgejo
4. Traefik sets `X-Forwarded-Login` and `X-Forwarded-Email` headers
5. SQ reads headers via HTTP header SSO (`sonar.web.sso.enable=true`)
6. SQ auto-creates user account from headers

### Implementation

**Forward-auth service:** Deploy `thomseddon/traefik-forward-auth` (or `mesosphere/traefik-forward-auth`) as a sidecar or separate deployment. Configure with Forgejo OAuth app credentials.

**Forgejo OAuth app:** Create via API — `POST /api/v1/user/applications/oauth2` with redirect URI `https://sonar.pmon.dev/_oauth`.

**SQ properties:**
```properties
sonar.web.sso.enable=true
sonar.web.sso.loginHeader=X-Forwarded-Login
sonar.web.sso.nameHeader=X-Forwarded-Name
sonar.web.sso.emailHeader=X-Forwarded-Email
```

**Traefik middleware:**
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: schnappy-sonarqube-auth
spec:
  forwardAuth:
    address: http://schnappy-forward-auth:4181
    trustForwardHeader: true
    authResponseHeaders:
      - X-Forwarded-Login
      - X-Forwarded-Email
      - X-Forwarded-Name
```

**SQ ingress annotation:**
```yaml
traefik.ingress.kubernetes.io/router.middlewares: schnappy-schnappy-sonarqube-auth@kubernetescrd
```

### Helm values:
```yaml
sonarqube:
  sso:
    enabled: false  # opt-in
    forgejoClientId: ""
    forgejoClientSecret: ""  # or existingSecret
```

### Files to create/modify

**Platform repo (`/home/sm/src/platform/helm/templates/`):**
- `sonarqube-setup-job.yaml` — NEW: Helm hook Job
- `sonarqube-forward-auth-deployment.yaml` — NEW: forward-auth sidecar (when SSO enabled)
- `sonarqube-forward-auth-service.yaml` — NEW
- `sonarqube-sso-middleware.yaml` — NEW: Traefik middleware
- `sonarqube-deployment.yaml` — MODIFY: add SSO env vars when enabled
- `sonarqube-ingress.yaml` — MODIFY: add middleware annotation when SSO enabled
- `network-policies.yaml` — MODIFY: add setup job + forward-auth NP rules
- `values.yaml` — MODIFY: add `sonarqube.setup` and `sonarqube.sso` sections

**Ops repo:**
- `tests/ansible/test-sonarqube.yml` — MODIFY: verify setup job ran, projects created, quality gates configured, SSO headers work

**Infra repo:**
- `clusters/production/schnappy/helmrelease.yaml` — MODIFY: add `sonarqube.setup.projects` list

## Part 3: Vagrant Test

Update `test-sonarqube.yml` to verify:

1. **Setup job completed** — `kubectl get jobs | grep sonarqube-setup | grep Complete`
2. **Admin password changed** — can't login with `admin:admin`
3. **Projects exist** — `GET /api/projects/search` returns all 7
4. **Quality gates exist** — `Service` (default, 80%) and `Frontend` (70%)
5. **Token works** — `GET /api/authentication/validate` with generated token
6. **SSO headers** — curl with `X-Forwarded-Login: testuser` returns 200 (when SSO enabled)
7. **Idempotent** — re-run `helm upgrade`, verify setup job succeeds without errors

## Verification

1. `helm lint` passes
2. `task test:sonarqube` passes in Vagrant
3. Fresh deploy: SQ auto-configures (projects, gates, token)
4. Re-deploy: setup job is idempotent (no errors on existing config)
5. SSO: login via Forgejo OAuth redirects correctly
6. Pipeline: SQ analysis succeeds with auto-generated token

## Implementation Order

1. Setup Job (Helm template + values)
2. Update helmrelease with project list
3. Test in Vagrant
4. SSO (forward-auth + middleware)
5. Update plan doc in ops/docs/plans/
