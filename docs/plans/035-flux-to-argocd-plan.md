# Migration from Flux CD to Argo CD

## Status: PLANNED

## Motivation

- Argo CD provides a rich Web UI for visualizing application state, sync status, and resource diffs
- Better visibility into deployment rollouts and failures
- Native application-of-applications pattern (simpler than Flux Kustomization hierarchy)
- Argo CD ApplicationSets for templated multi-component deployments
- Wider community adoption and ecosystem (Argo Rollouts, Argo Events, Argo Workflows)
- SSO integration with Keycloak (Argo CD has built-in OIDC support)

## Current Flux Architecture

**3 controllers** in `flux-system`: source-controller, kustomize-controller, helm-controller

**2 GitRepository sources:**
- `infra` (1m poll) — cluster config at `clusters/production/`
- `platform` (5m poll) — Helm chart source

**8 HelmRepository sources:** jetstack, external-secrets, hashicorp, forgejo, woodpecker, vmware-tanzu, sealed-secrets, porkbun-webhook

**7 Kustomizations** (hierarchical): cert-manager, external-secrets, vault, forgejo, woodpecker, velero, schnappy

**8 HelmReleases:** cert-manager, external-secrets, vault, forgejo, woodpecker, velero, schnappy (monolithic app), flux-system (self-managed)

**CD Flow:** Push code → Woodpecker builds image → commits tag to infra repo → Flux polls (1m) → reconciles HelmRelease

## Target Argo CD Architecture

### Argo CD Components

Deploy in `argocd` namespace:
- **argocd-server** — API + Web UI at `cd.pmon.dev` (DNS-01 TLS)
- **argocd-repo-server** — clones repos, renders manifests
- **argocd-application-controller** — reconciles Applications
- **argocd-redis** — caching (built-in)
- **argocd-dex-server** — NOT needed (use Keycloak OIDC directly)

### Application Structure

Use **App of Apps** pattern with one root Application:

```
root-app (Application)
├── cert-manager (Application, Helm)
├── external-secrets (Application, Helm)
├── vault (Application, Helm)
├── forgejo (Application, Helm)
├── woodpecker (Application, Helm)
├── velero (Application, Helm)
└── schnappy (Application, Helm — monolithic app chart)
```

Each child Application defined as a YAML manifest in the infra repo.

### Infra Repo Structure (after migration)

```
clusters/production/
├── argocd/
│   ├── root-app.yaml           # Root Application (points to apps/)
│   └── apps/
│       ├── cert-manager.yaml   # Application for cert-manager
│       ├── external-secrets.yaml
│       ├── vault.yaml
│       ├── forgejo.yaml
│       ├── woodpecker.yaml
│       ├── velero.yaml
│       └── schnappy.yaml       # Application for app stack
├── schnappy/
│   └── values.yaml             # Helm values (extracted from HelmRelease)
├── cert-manager/
│   └── values.yaml
├── vault/
│   └── values.yaml
├── forgejo/
│   └── values.yaml
├── woodpecker/
│   └── values.yaml
└── velero/
    └── values.yaml
```

### SSO via Keycloak

Argo CD supports OIDC natively:
```yaml
oidc.config: |
  name: Keycloak
  issuer: https://auth.pmon.dev/realms/schnappy
  clientID: argocd
  clientSecret: $oidc.keycloak.clientSecret
  requestedScopes: ["openid", "profile", "email"]
```

- Add `argocd` confidential client to Keycloak realm import
- Map Keycloak roles to Argo CD RBAC (Admins → `role:admin`)

## Migration Phases

### Phase 1: Deploy Argo CD (parallel to Flux)

Both can run simultaneously — they manage different resources.

1. Create Ansible playbook `setup-argocd.yml`:
   - Install Argo CD Helm chart in `argocd` namespace
   - Configure Keycloak OIDC
   - Set up ingress at `cd.pmon.dev` (DNS-01 TLS)
   - Seed admin password in Vault
   - Network policies (ingress from Traefik, egress to Forgejo + k8s API)

2. Add `argocd` client to Keycloak realm import JSON

3. Add Taskfile task: `task deploy:argocd`

4. Verify: login at `cd.pmon.dev` via Keycloak SSO

### Phase 2: Create Argo CD Applications (read-only)

Create Application manifests for each component, but set `syncPolicy: {}` (manual sync only). This lets us verify Argo CD sees the correct state without it making changes.

1. Create Application YAMLs in `clusters/production/argocd/apps/`
2. Each Application points to:
   - **Source**: Helm chart repo or `platform` Git repo
   - **Destination**: target namespace
   - **Values**: from `clusters/production/<component>/values.yaml`
3. Apply via `kubectl apply` (not yet managed by Argo CD itself)
4. Verify: Argo CD UI shows all applications synced (green)

### Phase 3: Extract Helm Values

Move Helm values from Flux HelmRelease YAML into standalone `values.yaml` files:
- `clusters/production/schnappy/helmrelease.yaml` → `clusters/production/schnappy/values.yaml`
- Same for each component
- The Argo CD Application references these values files

### Phase 4: Enable Auto-Sync on Non-Critical Apps

Enable `automated: { prune: true, selfHeal: true }` on:
- cert-manager
- external-secrets
- velero

Verify they stay in sync without issues.

### Phase 5: Migrate Woodpecker CD Pipeline

Update the `update-infra` step in each repo's `.woodpecker/cd.yaml`:
- Currently: commits image tag to `helmrelease.yaml` (Flux HelmRelease format)
- After: commits image tag to `values.yaml` (plain Helm values format)
- Argo CD detects the values change and syncs

The CD flow stays the same: Woodpecker → infra repo commit → Argo CD syncs.

### Phase 6: Enable Auto-Sync on All Apps

Enable auto-sync on remaining applications:
- vault, forgejo, woodpecker, schnappy
- Monitor for any sync issues

### Phase 7: Remove Flux CD

1. Remove Flux controllers: `task deploy:flux:uninstall` or `flux uninstall`
2. Remove Flux-specific files from infra repo:
   - `kustomization.yaml` files
   - `helmrelease.yaml` files
   - `sources/` directory (GitRepository, HelmRepository)
3. Remove Flux CRDs
4. Remove `setup-flux.yml` playbook
5. Update CLAUDE.md documentation

### Phase 8: Create Root Application (App of Apps)

Make Argo CD self-managing:
- Root Application watches `clusters/production/argocd/apps/` in infra repo
- Adding a new Application YAML to that directory auto-creates it in Argo CD
- The root Application itself is bootstrapped via Ansible

## Argo CD vs Flux Comparison

| Feature | Flux CD (current) | Argo CD (target) |
|---|---|---|
| UI | None (CLI only) | Rich Web UI with diff viewer |
| Sync visualization | `kubectl` commands | Real-time resource tree |
| SSO | N/A | Built-in OIDC (Keycloak) |
| Multi-tenancy | Limited | RBAC with projects |
| Rollback | Manual `helm rollback` | One-click in UI |
| Notifications | Requires notification-controller | Built-in (Slack, webhook) |
| Diff preview | None | Shows pending changes before sync |
| Health checks | Basic | Custom health checks per resource |
| Resource hooks | Helm hooks only | PreSync/Sync/PostSync hooks |

## Resource Requirements

| Pod | CPU req/limit | Memory req/limit |
|---|---|---|
| argocd-server | 100m / 500m | 128Mi / 512Mi |
| argocd-repo-server | 100m / 1000m | 256Mi / 1Gi |
| argocd-application-controller | 100m / 1000m | 256Mi / 1Gi |
| argocd-redis | 50m / 200m | 64Mi / 256Mi |

Total: ~350m CPU, ~704Mi memory (comparable to Flux's 3 controllers)

## Risks

| Risk | Mitigation |
|---|---|
| Dual GitOps during migration | Run both in parallel; Flux manages, Argo CD observes (manual sync) |
| CD pipeline changes | Update one repo at a time; test with manual Argo CD sync first |
| Secret management | Continue using ESO + Vault (Argo CD doesn't manage secrets differently) |
| Network policies | New NPs for argocd namespace (Forgejo access, k8s API) |
| CRD conflicts | Flux and Argo CD CRDs don't overlap |

## Key Files

| File | Purpose |
|---|---|
| `ops/deploy/ansible/playbooks/setup-argocd.yml` | Ansible playbook for Argo CD install |
| `infra/clusters/production/argocd/root-app.yaml` | Root Application (app of apps) |
| `infra/clusters/production/argocd/apps/*.yaml` | Per-component Application manifests |
| `infra/clusters/production/*/values.yaml` | Extracted Helm values |
| `platform/helm/templates/keycloak-realm-configmap.yaml` | Add argocd client |
| `ops/tests/ansible/test-argocd.yml` | Vagrant integration test |
