# Flux CD GitOps Migration Plan

## Context

The monitor project currently deploys via imperative `helm upgrade --install` from Woodpecker CD pipelines and Ansible playbooks. With 5 repos (monitor + 4 microservices) all needing coordinated deployment through a single Helm release, the deploy flow is fragile — webhook token issues, SQLite locking, cross-repo access to the Helm chart.

Moving to Flux CD with a dedicated `infra` repository makes Git the single source of truth for cluster state. Woodpecker pipelines build and push images, then commit the new tag to the infra repo. Flux detects the change and reconciles. No more imperative `helm upgrade` from CI pipelines.

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Infra repo + Flux installation | Complete (Ansible playbook + Vagrant tested) |
| Phase 2 | Monitor HelmRelease (Flux manages the app) | Complete |
| Phase 3 | Woodpecker pipeline: git-push-to-infra | Complete |
| Phase 4 | Extract infrastructure components | Complete |
| Phase 5 | Vagrant integration test | Complete (all checks pass) |
| Phase 6 | Cleanup + cutover | Complete |

## Architecture

```
Developer pushes code
  ↓
Woodpecker CD: test → build → push image → commit tag to infra repo
  ↓
Flux source-controller: polls infra repo (1m interval)
  ↓
Flux helm-controller: reconciles HelmRelease
  ↓
k8s: rolling update with new image tag
```

**Infra repo structure (target):**
```
infra/
├── clusters/
│   └── production/
│       ├── flux-system/              ← Flux's own config (auto-generated)
│       │   ├── gotk-components.yaml
│       │   ├── gotk-sync.yaml
│       │   └── kustomization.yaml
│       ├── sources/                  ← Shared Flux sources
│       │   ├── forgejo-git.yaml      ← GitRepository for infra + monitor repos
│       │   ├── helm-repos.yaml       ← HelmRepository for upstream charts
│       │   └── kustomization.yaml
│       ├── monitor/                  ← Monitor namespace (HelmRelease, shrinks over time)
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       ├── forgejo/                  ← Upstream HelmRelease
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       ├── woodpecker/               ← Upstream HelmRelease
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       ├── vault/                    ← Upstream HelmRelease
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   └── kustomization.yaml
│       ├── velero/                   ← Upstream HelmRelease + MinIO manifests
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   ├── minio-deployment.yaml
│       │   └── kustomization.yaml
│       ├── cert-manager/             ← Upstream HelmRelease + CRDs
│       │   ├── namespace.yaml
│       │   ├── helmrelease.yaml
│       │   ├── cluster-issuers.yaml
│       │   └── kustomization.yaml
│       └── external-secrets/         ← Upstream HelmRelease + ClusterSecretStore
│           ├── namespace.yaml
│           ├── helmrelease.yaml
│           ├── cluster-secret-store.yaml
│           └── kustomization.yaml
```

## Key Decisions

1. **Progressive split** — Start with HelmRelease wrapping the existing monitor chart. Extract independent infra (Forgejo, Vault, Velero, cert-manager, ESO) into their own directories immediately. The monitor chart shrinks as components are extracted.

2. **Pipeline git push for image tags** — Woodpecker builds images, clones infra repo, updates the tag via `sed`, commits, pushes. Simple, explicit, visible in git log. Retry logic for concurrent pushes.

3. **Keep ESO** — ExternalSecret CRDs committed to Git, applied by Flux. ESO continues syncing from Vault. No secret values in Git.

4. **Install via Ansible** — `setup-flux.yml` playbook (consistent with existing setup-* pattern). Not `flux bootstrap` (limited Forgejo support).

5. **Prune: false** — Safety for stateful workloads. Accidental manifest removal won't delete PVCs.

## Phase 1: Infra Repo + Flux Installation

### Step 1.1: Create infra repo on Forgejo

- New repo `schnappy/infra` on git.pmon.dev (SHA-1, private)
- Add to Woodpecker (for future webhooks)

### Step 1.2: Create Ansible playbook `setup-flux.yml`

**File:** `deploy/ansible/playbooks/setup-flux.yml`

Installs Flux on k3s via the official Helm chart with only needed controllers:
- `source-controller` — watches Git repos + Helm repos (polls every 1m)
- `kustomize-controller` — applies Kustomizations
- `helm-controller` — manages HelmReleases
- Skip `notification-controller`, `image-reflector-controller`, and `image-automation-controller` (not needed — polling is sufficient)

Creates:
1. `flux-system` namespace
2. Flux Helm release (chart: `oci://ghcr.io/fluxcd-community/flux2`)
3. k8s Secret with Forgejo PAT for Git access
4. `GitRepository` source pointing to `https://git.pmon.dev/schnappy/infra.git`
5. Root `Kustomization` pointing to `clusters/production/`
6. NetworkPolicy for flux-system (egress to Forgejo, k8s API, Helm OCI registries, DNS)

**Resource budget:**

| Controller | CPU req/limit | Memory req/limit |
|---|---|---|
| source-controller | 50m / 500m | 64Mi / 256Mi |
| kustomize-controller | 50m / 500m | 64Mi / 256Mi |
| helm-controller | 50m / 500m | 64Mi / 256Mi |
| **Total** | **150m / 1500m** | **192Mi / 768Mi** |

### Step 1.3: Bootstrap infra repo content

Seed the repo with:
```
clusters/production/
  flux-system/kustomization.yaml
  sources/
    forgejo-git.yaml       ← GitRepository for infra repo (self-referencing)
    monitor-source.yaml    ← GitRepository for monitor repo (chart source)
    helm-repos.yaml        ← HelmRepository for upstream charts (forgejo, vault, velero, cert-manager, ESO)
    kustomization.yaml
```

**`sources/forgejo-git.yaml`:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: infra
  namespace: flux-system
spec:
  interval: 1m
  url: https://git.pmon.dev/schnappy/infra.git
  ref:
    branch: main
  secretRef:
    name: forgejo-credentials
```

**`sources/monitor-source.yaml`:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: monitor
  namespace: flux-system
spec:
  interval: 5m
  url: https://git.pmon.dev/schnappy/monitor.git
  ref:
    branch: master
  secretRef:
    name: forgejo-credentials
```

### Step 1.4: Forgejo TLS

`git.pmon.dev` uses Let's Encrypt (DNS-01 via Porkbun) — public CA, standard trust works. Verify from inside the cluster. If issues, use `spec.insecure: true` on GitRepository as fallback.

### Step 1.5: Taskfile entries

```yaml
deploy:flux:
  desc: Install/update Flux CD
  cmds:
    - cd deploy/ansible && venv/bin/ansible-playbook -i inventory/production.yml playbooks/setup-flux.yml -e @vars/vault.yml
```

## Phase 2: Monitor HelmRelease

### Step 2.1: Create monitor Kustomization in infra repo

**`clusters/production/monitor/namespace.yaml`:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitor
  labels:
    pod-security.kubernetes.io/enforce: privileged
```

**`clusters/production/monitor/helmrelease.yaml`:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: monitor
  namespace: monitor
spec:
  interval: 5m
  timeout: 10m
  chart:
    spec:
      chart: infra/helm
      sourceRef:
        kind: GitRepository
        name: monitor
        namespace: flux-system
      reconcileStrategy: Revision
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
  driftDetection:
    mode: warn
  values:
    # Full production values (currently in values-production.yaml)
    # Image tags — these lines are updated by Woodpecker pipeline commits:
    app:
      image:
        tag: "INITIAL_HASH"  # monitor-backend
    frontend:
      image:
        tag: "INITIAL_HASH"  # monitor-frontend
    gateway:
      image:
        tag: "INITIAL_HASH"  # api-gateway
    admin:
      image:
        tag: "INITIAL_HASH"  # admin-service
    chatService:
      image:
        tag: "INITIAL_HASH"  # chat-service
    chessService:
      image:
        tag: "INITIAL_HASH"  # chess-service
    # ... rest of values-production.yaml inlined
```

### Step 2.2: Import existing deployment

Before Flux takes over, capture the currently deployed image tags:
```bash
helm get values monitor -n monitor -o json | jq '.app.image.tag, .frontend.image.tag'
```
Set these as the initial tags in helmrelease.yaml so Flux's first reconciliation is a no-op.

### Step 2.3: Adopt existing Helm release

Flux can adopt an existing Helm release. The HelmRelease name (`monitor`) and namespace (`monitor`) must match. Flux detects the existing release and manages it going forward. No redeploy needed.

### Implementation Notes (Phase 2)

- HelmRelease pushed to `schnappy/infra` repo on Forgejo (commit `e2a1a62`)
- Full production values inlined from `values-production.yaml` + `helm get values`
- Current image tags captured: `app.image.tag: 51202cd`, `frontend.image.tag: a8cdcb5`
- Disabled microservices (gateway, admin, chatService, chessService) use `tag: "unchanged"` placeholder
- Each image tag has a trailing comment (e.g. `# monitor-backend`) — Woodpecker `sed` targets these
- `app.gitHash` and `app.buildTime` also inlined (previously set via `--set` in CD pipeline)
- Root kustomization at `clusters/production/kustomization.yaml` references `monitor/` subdirectory
- **NOT yet deployed** — Flux needs `setup-flux.yml` run on production first (Phase 1 playbook)

## Phase 3: Woodpecker Pipeline — Git Push to Infra

### Step 3.1: Create Forgejo PAT for Woodpecker

- New PAT on Forgejo with `write:repository` scope for the `infra` repo
- Store as Woodpecker k8s-level secret: `infra_repo_token` in `woodpecker-ci-secrets`

### Step 3.2: Update monitor CD pipeline

Replace the deploy step in `.woodpecker/cd.yaml` with:

```yaml
- name: update-infra
  image: alpine:latest
  commands:
    - '[ "$SHOULD_DEPLOY" = "false" ] && echo "No deployable changes" && exit 0'
    - apk add --no-cache git
    - GIT_HASH=$(echo "$CI_COMMIT_SHA" | cut -c1-7)
    - BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    - |
      for attempt in 1 2 3 4 5; do
        git clone https://woodpecker:${INFRA_TOKEN}@git.pmon.dev/schnappy/infra.git /tmp/infra
        cd /tmp/infra
        git config user.name "Woodpecker CD"
        git config user.email "woodpecker@pmon.dev"
        # Update image tags (only changed components)
        [ "$BACKEND_TAG" != "unchanged" ] && \
          sed -i "s|tag: \".*\"  # monitor-backend|tag: \"$BACKEND_TAG\"  # monitor-backend|" \
            clusters/production/monitor/helmrelease.yaml
        [ "$FRONTEND_TAG" != "unchanged" ] && \
          sed -i "s|tag: \".*\"  # monitor-frontend|tag: \"$FRONTEND_TAG\"  # monitor-frontend|" \
            clusters/production/monitor/helmrelease.yaml
        git add -A
        git diff --cached --quiet && { echo "No changes"; exit 0; }
        git commit -m "deploy: monitor backend=$BACKEND_TAG frontend=$FRONTEND_TAG"
        git push && break
        echo "Push conflict (attempt $attempt), retrying..."
        rm -rf /tmp/infra
        sleep $((attempt * 2))
      done
  depends_on: [push-backend-image, push-frontend-image, helm-lint]
  backend_options:
    kubernetes:
      secrets:
        - name: woodpecker-ci-secrets
          key: infra_repo_token
          target:
            env: INFRA_TOKEN
```

### Step 3.3: Add update-infra step to microservice pipelines

Each microservice (admin, chat, chess, api-gateway) gets a final `update-infra` step in `.woodpecker/cd.yaml`:

```yaml
- name: update-infra
  image: alpine:latest
  commands:
    - apk add --no-cache git
    - GIT_HASH=$(echo "$CI_COMMIT_SHA" | cut -c1-7)
    - |
      for attempt in 1 2 3 4 5; do
        git clone https://woodpecker:${INFRA_TOKEN}@git.pmon.dev/schnappy/infra.git /tmp/infra
        cd /tmp/infra
        git config user.name "Woodpecker CD"
        git config user.email "woodpecker@pmon.dev"
        sed -i "s|tag: \".*\"  # <SERVICE_COMMENT>|tag: \"$GIT_HASH\"  # <SERVICE_COMMENT>|" \
          clusters/production/monitor/helmrelease.yaml
        git add -A
        git diff --cached --quiet && { echo "No changes"; exit 0; }
        git commit -m "deploy: <service>=$GIT_HASH"
        git push && break
        echo "Push conflict (attempt $attempt), retrying..."
        rm -rf /tmp/infra
        sleep $((attempt * 2))
      done
  depends_on: [push-image]
  backend_options:
    kubernetes:
      secrets:
        - name: woodpecker-ci-secrets
          key: infra_repo_token
          target:
            env: INFRA_TOKEN
```

Where `<SERVICE_COMMENT>` is: `admin-service`, `chat-service`, `chess-service`, `api-gateway`.

### Step 3.4: Network policy for Woodpecker → Forgejo git push

The existing NP already allows woodpecker → forgejo:3000. The update-infra step uses HTTPS to `git.pmon.dev` which routes through Traefik ingress (port 443). Verify this path works from woodpecker pods, add egress rule if needed.

### Implementation Notes (Phase 3)

- Monitor CD: replaced `deploy` step (helm upgrade) with `update-infra` step (git clone/sed/push)
- Monitor CD: no longer needs `woodpecker-deployer` ServiceAccount (Flux does the deploying)
- Monitor CD: updates `buildTime` and `gitHash` in helmrelease.yaml alongside image tags
- Monitor CD: unchanged components use tag `unchanged` (sed only runs for changed components)
- Microservices (admin, chat, chess, api-gateway): added `update-infra` step after `push-image`
- Each microservice targets its comment marker: `# admin-service`, `# chat-service`, `# chess-service`, `# api-gateway`
- Forgejo PAT: `woodpecker-infra` PAT created by `setup-woodpecker.yml` (read+write:repository scope)
- PAT stored in `woodpecker-ci-secrets` as `infra_repo_token` key
- Network policies: already sufficient — pipeline pods have egress to Traefik (8443) for HTTPS git push
- Retry logic: 5 attempts with exponential backoff for concurrent push conflicts
- **Activation**: run `task deploy:woodpecker` to create the PAT and update secrets, then push pipeline changes to each repo

## Phase 4: Extract Infrastructure Components

Extract independent components from the monitor Helm chart into their own Flux-managed directories. Each gets a `Kustomization` in the infra repo.

### Dependency ordering (Flux `dependsOn`):

```
cert-manager          ← no dependencies
  └─ external-secrets ← needs cert-manager CRDs
       └─ vault       ← needs ESO for secret sync
            └─ monitor ← needs Vault secrets via ESO
forgejo               ← independent
  └─ woodpecker       ← needs forgejo for OAuth + webhooks
velero                ← independent
```

### Step 4.1: Forgejo

Extract from `setup-forgejo.yml` → Flux HelmRelease:
- Source: `oci://code.forgejo.org/forgejo-helm/forgejo` v16.2.0
- Values: extracted from Ansible playbook vars
- File: `clusters/production/forgejo/helmrelease.yaml`

### Step 4.2: Woodpecker

Extract from `setup-woodpecker.yml` → Flux HelmRelease:
- Source: Woodpecker Helm chart
- Values: server config, agent config, k8s backend settings
- File: `clusters/production/woodpecker/helmrelease.yaml`
- Note: `woodpecker-deployer` ServiceAccount RBAC no longer needed after Flux cutover

### Step 4.3: Vault

Extract Helm portion of `setup-vault.yml` → Flux HelmRelease:
- Source: `hashicorp/vault` Helm chart
- Values: HA config, Raft storage, auto-unseal, TLS
- File: `clusters/production/vault/helmrelease.yaml`
- Note: `vault operator init` and transit setup remain in Ansible (one-time bootstrap)

### Step 4.4: Velero

Extract from `setup-velero.yml` → Flux HelmRelease + plain manifests:
- HelmRelease for Velero chart (`vmware-tanzu/velero`)
- Plain manifests for backup MinIO deployment (not a Helm chart)
- Schedule CRDs for backup schedules
- File: `clusters/production/velero/`

### Step 4.5: cert-manager and ESO

- cert-manager: upstream Helm chart + ClusterIssuer manifests (letsencrypt-prod, letsencrypt-dns, Porkbun webhook)
- ESO: upstream Helm chart + ClusterSecretStore manifest
- These are prerequisites — Flux applies them first via `dependsOn` ordering

### Step 4.6: Remove extracted components from monitor Helm chart

As each component moves to its own Flux directory, remove its templates from `infra/helm/templates/` and its values from `values.yaml` / `values-production.yaml`. The monitor chart shrinks to just the application components (app, frontend, postgres, redis, kafka, scylla, microservices).

### Implementation Notes (Phase 4)

- All infrastructure components pushed to `schnappy/infra` repo (commit `c1fc340`)
- **HelmRepository sources** in `clusters/production/sources/helm-repos.yaml`:
  - jetstack (cert-manager), external-secrets, hashicorp, forgejo (OCI), woodpecker (OCI), vmware-tanzu, sealed-secrets, porkbun-webhook
- **cert-manager**: `suspend: true` — currently installed via kubectl apply, needs migration to Helm
  - Includes porkbun-webhook HelmRelease (also suspended, depends on cert-manager)
  - Includes ClusterIssuer manifests (letsencrypt-prod HTTP-01, letsencrypt-dns DNS-01 Porkbun)
- **external-secrets**: ESO v2.0.1 + ClusterSecretStore `vault-backend`
- **vault**: Helm chart v0.29.1 with full HA Raft config, transit auto-unseal, TLS
  - Bootstrap (init, policies, auth, ESO roles) still managed by Ansible
- **forgejo**: OCI chart v16.2.0, SQLite, rootless, letsencrypt-dns TLS
  - Admin credentials in Helm values (Forgejo hashes on first boot)
  - Post-install (repo creation, webhooks) still Ansible
- **woodpecker**: OCI chart v3.5.1, k8s backend, letsencrypt-dns TLS
  - OAuth secret + CI secrets still managed by Ansible
- **velero**: Chart v11.4.0 + MinIO plain manifests (Deployment + PV/PVC + Service)
  - Credentials secret still managed by Ansible
- **Adoption strategy**: Flux can adopt existing Helm releases when name + namespace match
- **Step 4.6 deferred**: Monitor Helm chart is NOT being shrunk in this phase — infra components were never in it. They were always separate Ansible playbooks. This step is N/A.

## Phase 5: Vagrant Integration Test

**File:** `tests/ansible/test-flux.yml`

1. Deploy k3s in Vagrant
2. Deploy Forgejo (for Git hosting)
3. Create infra repo on Forgejo, push seed content
4. Install Flux via `setup-flux.yml`
5. Verify Flux controllers are running
6. Push a monitor HelmRelease to infra repo
7. Verify Flux reconciles — HelmRelease status shows `Ready`
8. Verify pods are created in monitor namespace
9. Update an image tag in helmrelease.yaml, push
10. Verify Flux rolls out the change (new pod with new image)
11. Summary: PASS/FAIL per check

**Taskfile:** `task test:flux`

## Phase 6: Cleanup + Cutover

1. Remove deploy step from monitor `.woodpecker/cd.yaml` (replaced by update-infra)
2. Remove `woodpecker-deployer` ServiceAccount + RBAC (Flux manages deployments, not Woodpecker)
3. Remove `woodpecker-deploy-state` ConfigMap (Flux tracks revision via GitRepository status)
4. Remove Ansible `roles/monitor` deploy role (`task deploy:prod` no longer needed)
5. Update CLAUDE.md with new deployment model
6. Update memory files

### Implementation Notes (Phase 6)

- Deploy step already replaced with `update-infra` in Phase 3
- `woodpecker-deployer` ServiceAccount + RBAC removed from `setup-woodpecker.yml`
- `woodpecker-deploy-state` ConfigMap creation removed from `setup-woodpecker.yml`
- `detect-changes` step simplified: uses `CI_PREV_COMMIT_SHA` only (no ConfigMap lookup), no longer needs `woodpecker-deployer` SA, switched from `bitnami/kubectl` to `alpine:latest`
- CLAUDE.md updated: new Flux CD section, updated CI/CD flow, architecture diagram, deploy commands
- Step 4 (remove `roles/monitor` deploy role) — N/A, there is no such role; `task deploy:prod` kept as legacy fallback
- **Production cleanup**: After verifying Flux works, manually delete stale resources on ten:
  ```bash
  k3s kubectl delete sa woodpecker-deployer -n woodpecker
  k3s kubectl delete clusterrole woodpecker-deployer
  k3s kubectl delete clusterrolebinding woodpecker-deployer
  k3s kubectl delete configmap woodpecker-deploy-state -n woodpecker
  ```

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Flux deletes stateful resources on prune | `prune: false` on all Kustomizations with PVCs |
| Concurrent git pushes from multiple pipelines | Retry loop with `git pull --rebase` (5 attempts, exponential backoff) |
| Forgejo downtime breaks reconciliation | Flux caches last known state, retries on interval |
| NP blocks Flux controllers | Add NP for flux-system before enabling (egress: Forgejo HTTPS, k8s API, DNS) |
| HelmRelease drift from manual kubectl edits | `driftDetection.mode: warn` initially, `enabled` after stabilization |
| Adopting existing Helm release fails | Verify release name + namespace match before Flux takes over |

## Implementation Notes (from Vagrant testing)

- **Flux Helm chart:** `oci://ghcr.io/fluxcd-community/charts/flux2` v2.14.1
- **Controller deployment names:** `source-controller`, `kustomize-controller`, `helm-controller` (no `flux-` prefix)
- **Disable controllers via Helm values:** `notificationController.create: false`, `imageReflectionController.create: false`, `imageAutomationController.create: false`
- **GitRepository for internal Forgejo:** Use ClusterIP URL (`http://<clusterip>:3000/...`) in Vagrant; use HTTPS in production
- **Kustomization path:** `./clusters/production` (relative to repo root)
- **Reconciliation timing:** ~1 minute from git push to applied in cluster (1m poll interval)
- **Idempotent git push:** Guard with `git diff --cached --quiet` to skip when no changes

## Critical Files

| File | Action |
|---|---|
| `deploy/ansible/playbooks/setup-flux.yml` | Created — Flux installation playbook |
| `tests/ansible/test-flux.yml` | Created — Vagrant integration test |
| `Taskfile.yml` | Modified — added `deploy:flux`, `test:flux` tasks |
| `infra/` (new repo on Forgejo) | Create — all cluster manifests |
| `.woodpecker/cd.yaml` (monitor) | Modify — replace deploy step with update-infra |
| `.woodpecker/cd.yaml` (admin, chat, chess, api-gateway) | Modify — add update-infra step |
| `infra/helm/templates/network-policies.yaml` | Modify — add flux-system NP rules |
| `deploy/ansible/playbooks/setup-woodpecker.yml` | Modify — add `infra_repo_token` secret |

## Verification

1. `flux get sources git` — shows infra repo as `Ready`
2. `flux get helmreleases -n monitor` — shows monitor as `Ready`
3. Push a code change to any microservice → Woodpecker builds → commits tag to infra → Flux deploys → pod updates
4. `kubectl get pods -n monitor` — new pod running with expected image tag
5. `task test:flux` — Vagrant integration test passes
6. Existing functionality at pmon.dev unchanged
