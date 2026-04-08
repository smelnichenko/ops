# Plan: Test + Prod Environment Split (Same Cluster)

## Context

Single kubeadm node `ten` (192.168.11.2). Everything in `schnappy` namespace. Goal: add a `schnappy-test` environment on the same cluster for deploy-to-test-first, then promote to prod.

## Architecture

- **Separate namespaces**: `schnappy` (prod, unchanged) + `schnappy-test` (test)
- **Same Helm charts** from `platform.git`, different values from `infra.git`
- **Shared gateway**: single Istio ingress, `test.pmon.dev` alongside `pmon.dev`
- **Shared observability**: Prometheus, Grafana, ELK, Tempo, Mimir — filter by namespace label
- **Shared operators**: CNPG, Strimzi, Scylla, cert-manager, ESO — cluster-scoped
- **Dedicated data stores per env**: PostgreSQL, Kafka, Redis (test gets lightweight instances)
- **All data stores enabled in test** with minimal resources
- **ScyllaDB**: operator-managed in both envs, test uses minimal resources (`--smp=1 --memory=512M`)

## Phase 0: Safety + Vagrant Validation

### Backup ops .env

Before any changes, create a timestamped backup:
```
cp /home/sm/src/ops/.env /home/sm/src/ops/.env.backup-$(date +%Y%m%d)
```

### Vagrant stack matches production

`setup-kubeadm.yml` deploys the full production stack:
- Cilium 1.19.1 (kubeProxyReplacement, VXLAN tunnel)
- Istio 1.25.2 (base + istiod + CNI, sidecar injection)
- cert-manager, ESO, Gateway API CRDs
- CNPG 0.28.0, Strimzi 0.51.0, ScyllaDB Operator 1.20.2 + Manager
- local-path-provisioner, metrics-server, HAProxy

### Vagrant-first development

All changes are developed and validated in Vagrant **before** touching production:
1. Make chart changes locally (parameterize names, vault prefix)
2. Run `helm template` diff to verify identical output for prod values
3. Run `test:multi-env` in Vagrant to validate both envs work on the full stack
4. Only after Vagrant passes: push to platform.git, let ArgoCD sync prod

### Production backups (before Phase 2 deployment)

1. CNPG on-demand backup → verify on Pi MinIO
2. Velero full namespace backup
3. Stress test baseline
4. Record node resource allocation (`kubectl describe node ten`)

## Phase 1: Parameterize Hardcoded Names in Platform Charts

**Why**: Several resource names are hardcoded instead of using `{{ include "schnappy.fullname" . }}`. With `releaseName: schnappy-test`, these would collide or break.

### CNPG cluster name (6 files)

Replace all `schnappy-postgres` with `{{ include "schnappy.postgres.serviceName" . }}` (helper already exists):

- `schnappy-data/templates/cnpg-cluster.yaml` — cluster name, secret refs
- `schnappy-data/templates/cnpg-secret.yaml` — ExternalSecret names/targets
- `schnappy-data/templates/cnpg-backup.yaml` — backup name, cluster ref
- `schnappy-data/templates/cnpg-rbac.yaml` — cluster ref
- `schnappy-mesh/templates/peer-authentication.yaml` line 123 — `cnpg.io/cluster` label
- `schnappy/templates/_helpers.tpl` line 234 — postgres selector label

### Strimzi cluster name (6 files)

Replace all hardcoded `schnappy` in Strimzi labels with `{{ include "schnappy.fullname" . }}`:

- `schnappy-data/templates/strimzi-kafka.yaml` — `name` + `strimzi.io/cluster` label
- `schnappy-data/templates/strimzi-topics.yaml` — `strimzi.io/cluster` label
- `schnappy-data/templates/strimzi-service-compat.yaml` — externalName
- `schnappy-data/templates/network-policies.yaml` — 6 references to `strimzi.io/cluster: schnappy`
- `schnappy/templates/_helpers.tpl` line 248 — kafka selector label
- `schnappy-data/templates/_helpers.tpl` line 103 — kafka selector label

### Vault secret path prefix (8+ files)

Add `vault.secretPathPrefix` value (default: `secret/data/schnappy`). Replace all `key: secret/data/schnappy/...` with `key: {{ .Values.vault.secretPathPrefix }}/...`:

- `schnappy/templates/external-secrets.yaml` — mail, ai, webhook
- `schnappy/templates/k6-smoke-external-secret.yaml`
- `schnappy/templates/hyperfoil-external-secret.yaml`
- `schnappy-data/templates/external-secrets.yaml` — postgres, redis, minio
- `schnappy-data/templates/cnpg-secret.yaml` — postgres superuser/app, minio-backup
- `schnappy-data/templates/scylla-agent-secret.yaml` — minio-backup
- `schnappy-observability/templates/external-secrets.yaml` — grafana, elasticsearch
- `schnappy-auth/templates/external-secrets.yaml` — keycloak

### Validation

After all changes, run `helm template schnappy helm/schnappy-data -f ../infra/clusters/production/schnappy-data/values.yaml` and diff against pre-change output. Must be identical.

## Phase 2: Create Test Infrastructure (infra repo)

### Namespace + policies

Create in `clusters/production/cluster-config/`:
- `schnappy-test-namespace.yaml` — namespace with `istio.io/rev: default` label
- `schnappy-test-default-deny.yaml` — default-deny NetworkPolicy
- `schnappy-test-resource-quota.yaml` — `requests.cpu: 2, requests.memory: 4Gi, limits.cpu: 8, limits.memory: 8Gi`

### Test values files

Create in `clusters/production/`:

**`schnappy-test/values.yaml`** (apps):
- Same image tags as prod initially (copied, then CI updates test only)
- `replicas: 1` everywhere
- `javaOpts: -Xmx512m` (monitor gets `-Xmx1g` — it idles at 1.6Gi)
- Resources based on prod idle consumption:
  - monitor: 50m/512Mi → 2Gi
  - admin: 50m/256Mi → 1Gi
  - chat: 50m/256Mi → 1Gi
  - chess: 50m/256Mi → 1Gi
  - site: 10m/32Mi → 128Mi
  - game-scp: 10m/32Mi → 128Mi
- `scyllaOperator.enabled: true`
- `vault.secretPathPrefix: "secret/data/schnappy-test"`
- `networkPolicies.enabled: true`

**`schnappy-test-data/values.yaml`** (data):
- `postgres.enabled: false` (CNPG handles it)
- `cnpg.enabled: true`, `cnpg.backup: false`, 5Gi storage, minimal tuning
- `kafka` via Strimzi: 1 partition per topic, `-Xmx256m`, 2Gi storage, 24h retention
- `redis.enabled: true`: 10m/32Mi → 128Mi
- `scylla.enabled: false`
- `scyllaOperator.enabled: true`, version `6.2.3`, `developerMode: true`, no backups
  - Resources: 50m/256Mi → 512Mi, storage: 5Gi
- `minio.enabled: true`: 25m/128Mi → 512Mi, storage: 5Gi
- `vault.secretPathPrefix: "secret/data/schnappy-test"`

**`schnappy-test-mesh/values.yaml`** (networking):
- `gateway.enabled: false` (use prod gateway cross-namespace)
- `peerAuthentication.enabled: true`, `mode: STRICT`
- `jwt.enabled: true`, same Keycloak issuer
- HTTPRoutes for `test.pmon.dev` referencing prod gateway

### ArgoCD: ApplicationSet instead of static apps

Use `ApplicationSet` with a `git` generator scanning directories. This handles test+prod now and supports future ephemeral per-PR environments without changes.

Create `clusters/production/argocd/apps/schnappy-envs.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: schnappy-envs
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: http://192.168.11.5:3000/schnappy/infra.git
        revision: main
        directories:
          - path: "clusters/production/schnappy-*/values"
            # Convention: clusters/production/schnappy-<env>/values/<chart>/
            # e.g. clusters/production/schnappy-test/values/schnappy-data/
  template:
    metadata:
      name: "{{.path.basename}}"
    spec:
      project: default
      sources:
        - repoURL: http://192.168.11.5:3000/schnappy/platform.git
          targetRevision: main
          path: "helm/{{.path[2]}}"   # chart name from directory
          helm:
            releaseName: "{{.path[1]}}"  # env name (schnappy-test, schnappy-pr-123)
            valueFiles:
              - "$values/{{.path}}/values.yaml"
        - repoURL: http://192.168.11.5:3000/schnappy/infra.git
          targetRevision: main
          ref: values
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{.path[1]}}"
      syncPolicy:
        automated:
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

Actually, the git directory generator is awkward for multi-chart environments. Simpler approach — use a `list` generator with explicit environments, which also supports adding ephemeral envs programmatically via the ApplicationSet API:

**Better: one ApplicationSet per chart, parameterized by environment list**

Create `clusters/production/argocd/appsets/`:

**`schnappy-data-envs.yaml`**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: schnappy-data-envs
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: production
            namespace: schnappy
            releaseName: schnappy
            valuesPath: clusters/production/schnappy-data/values.yaml
            prune: "false"
            syncWave: "0"
          - env: test
            namespace: schnappy-test
            releaseName: schnappy-test
            valuesPath: clusters/production/schnappy-test-data/values.yaml
            prune: "false"
            syncWave: "0"
  template:
    metadata:
      name: "schnappy-{{env}}-data"
      annotations:
        argocd.argoproj.io/sync-wave: "{{syncWave}}"
      namespace: argocd
    spec:
      project: default
      sources:
        - repoURL: http://192.168.11.5:3000/schnappy/platform.git
          targetRevision: main
          path: helm/schnappy-data
          helm:
            releaseName: "{{releaseName}}"
            valueFiles:
              - "$values/{{valuesPath}}"
        - repoURL: http://192.168.11.5:3000/schnappy/infra.git
          targetRevision: main
          ref: values
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          selfHeal: true
          prune: "{{prune}}"
        syncOptions:
          - CreateNamespace=true
          - RespectIgnoreDifferences=true
```

Same pattern for `schnappy-apps-envs.yaml` and `schnappy-mesh-envs.yaml`.

**For ephemeral PR envs later**: add an element to the list generator (or switch to a `pullRequest` generator) — no chart or values structure changes needed.

**Migration**: replace existing static `schnappy-data.yaml`, `schnappy.yaml`, `schnappy-mesh.yaml` ArgoCD apps with these ApplicationSets. The prod element produces identical apps.

### DNS + TLS

- Add `test.pmon.dev` A record → `192.168.11.2` (Porkbun)
- Wildcard cert `*.pmon.dev` already covers it

### Vault secrets seeding

Add test environment seeding to `seed-vault-secrets.yml`. Test needs these secrets at `secret/schnappy-test/*`:

| Secret | Same as prod? | Notes |
|--------|--------------|-------|
| `postgres` | No | different password, same schema |
| `redis` | No | different password |
| `kafka` | No | different cluster ID (`uuidgen`) |
| `minio` | No | different credentials |
| `mail` | Yes | can share Resend API key |
| `ai` | Yes | can share Anthropic key |
| `webhook` | Yes | can share Resend webhook secret |
| `k6-smoke` | No | different client_secret, `app_url: https://test.pmon.dev` |
| `keycloak` | No | different client secrets for test realm/clients |

The ops `.env` file holds all prod secret values (51 variables). For test:

**Option A** (cleanest): Create `.env.test` with test-specific overrides. Shared secrets (API keys) default to prod values. Parameterize `seed-vault-secrets.yml` with a `vault_prefix` variable:
```yaml
# Usage:
#   task deploy:seed-secrets                          # seeds secret/schnappy/*
#   task deploy:seed-secrets -- -e vault_prefix=schnappy-test -e @.env.test  # seeds secret/schnappy-test/*
```

The playbook changes `secret/schnappy/` → `secret/{{ vault_prefix | default('schnappy') }}/` in all tasks.

**`.env.test`** contains only the values that differ from prod:
```
MONITOR_DB_PASSWORD=<generated>
REDIS_PASSWORD=<generated>
KAFKA_CLUSTER_ID=<generated via uuidgen>
MINIO_ROOT_USER=test-admin
MINIO_ROOT_PASSWORD=<generated>
KEYCLOAK_K6_SMOKE_CLIENT_SECRET=<from test KC client>
K6_SMOKE_CLIENT_SECRET=<from test KC client>
```

Variables not in `.env.test` fall through to `.env` (mail, AI, webhook keys are shared).

Also update:
- ESO Vault role policy: allow reads from `secret/data/schnappy-test/*`
- Vault Kubernetes auth: add `schnappy-test` to bound service account namespaces

### Gateway cross-namespace routing

- Add `ReferenceGrant` in `schnappy` namespace allowing HTTPRoutes from `schnappy-test`
- Test mesh chart deploys HTTPRoutes with `parentRef` to prod gateway

## Phase 3: CI/CD Changes

### Deploy to test by default

Each service's `.woodpecker/cd.yaml` — change:
```
HELMRELEASE=clusters/production/schnappy/values.yaml
→
HELMRELEASE=clusters/production/schnappy-test/values.yaml
```

Push to main → Woodpecker tests + builds → updates test values → ArgoCD syncs test env.

### Promotion to prod via Taskfile

Add `promote:prod` task to `/home/sm/src/ops/Taskfile.yml`:

```yaml
promote:prod:
  desc: Promote all test image tags to production
  cmds:
    - |
      cd {{.INFRA_DIR}}
      TEST=clusters/production/schnappy-test/values.yaml
      PROD=clusters/production/schnappy/values.yaml
      for svc in monitor admin chat chess site game-scp; do
        TAG=$(grep "# schnappy-${svc}" "$TEST" | grep -oP 'tag: "\K[^"]+')
        [ -n "$TAG" ] && sed -i "s|tag: \".*\"  # schnappy-${svc}|tag: \"${TAG}\"  # schnappy-${svc}|" "$PROD"
      done
      git add "$PROD"
      git diff --cached --quiet && { echo "No changes"; exit 0; }
      git commit -m "promote: test → prod"
      git push
```

Flow: verify test at `test.pmon.dev` → `task promote:prod` → ArgoCD syncs prod.

## Phase 4: Vagrant Tests

Add `test:multi-env` to `ops/Taskfile.yml` and create `tests/ansible/test-multi-env.yml`.

### What the test does

**Setup (automated by Taskfile):**
1. `vagrant destroy && vagrant up` — fresh 3-VM environment (kubeadm + pi1 + pi2)
2. `setup-kubeadm.yml` — installs kubeadm, initializes cluster, Calico CNI
3. `setup-vault-pi.yml` — installs Vault on pi1
4. `setup-vault.yml` — deploys Vault + ESO into k8s

**Test playbook verifies multi-env isolation:**
1. Seeds Vault with two separate paths (`secret/schnappy/*` and `secret/schnappy-test/*`) using different credentials
2. Updates Vault policy to allow ESO reads from both paths
3. Creates both namespaces, applies ResourceQuota on test
4. Syncs platform charts to VM, deploys schnappy-data chart twice:
   - `helm upgrade --install schnappy` in `schnappy` namespace (prod)
   - `helm upgrade --install schnappy-test` in `schnappy-test` namespace (test)
5. Asserts:
   - Pods running in both namespaces (≥2 each)
   - ExternalSecrets synced in both namespaces
   - **Secret isolation**: prod postgres password differs from test (from different Vault paths)
   - **Service name isolation**: `schnappy-postgres` in prod, `schnappy-test-postgres` in test
   - **ResourceQuota enforced**: test namespace has 4Gi memory limit

**What it proves:** Same Helm chart, different release name, different Vault path, different namespace — no cross-contamination.

```yaml
# Taskfile entry:
test:multi-env:
  desc: Test multi-environment (test + prod) isolation in Vagrant
  deps: [deploy:install]
  cmds:
    - cmd: vagrant destroy -f 2>/dev/null; true
    - cmd: vagrant up
    - defer: vagrant halt
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault-pi.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml ../../tests/ansible/test-multi-env.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml
```

## Phase 5: Cleanup

- Keep existing `schnappy-test.yaml` ArgoCD app and `helm/schnappy-test` chart — k6 smoke tests stay in `schnappy-test` namespace (they test the test env)
- Update Velero backup schedule to exclude `schnappy-test`

## Resource Budget (Test)

Based on prod idle consumption (`kubectl top pods`):

| Component | Prod idle CPU | Prod idle Mem | Test requests CPU | Test requests Mem | Test limits Mem |
|-----------|--------------|---------------|-------------------|-------------------|-----------------|
| monitor | 7m | 1640Mi | 50m | 512Mi | 2Gi |
| admin | 5m | 721Mi | 50m | 256Mi | 1Gi |
| chat | 28m | 803Mi | 50m | 256Mi | 1Gi |
| chess | 19m | 778Mi | 50m | 256Mi | 1Gi |
| site | 2m | 82Mi | 10m | 32Mi | 128Mi |
| game-scp | 2m | 76Mi | 10m | 32Mi | 128Mi |
| PostgreSQL | 6m | 196Mi | 25m | 128Mi | 512Mi |
| Kafka | 14m | 1349Mi | 50m | 512Mi | 1536Mi |
| Redis | 11m | 81Mi | 10m | 32Mi | 128Mi |
| ScyllaDB | 8m | 310Mi | 50m | 256Mi | 512Mi |
| MinIO | 8m | 367Mi | 25m | 128Mi | 512Mi |
| **Total** | **110m** | **~6.4Gi** | **380m** | **~2.4Gi** | **~8.5Gi** |

## Verification

### After Phase 0 (safety)

1. `.env` backup exists
2. Vagrant `test:multi-env` passes with parameterized charts
3. `helm template` output identical before/after for prod values

### Before Phase 2 (production deployment)

4. CNPG + Velero backups verified on Pi MinIO
5. Stress test baseline saved
6. Node resource allocation recorded

### After Phase 2 (test env deployed)

7. Test namespace comes up: `kubectl get pods -n schnappy-test`
8. All ExternalSecrets sync: `kubectl get externalsecret -n schnappy-test`
9. HTTPRoute for `test.pmon.dev` resolves and serves the test app
10. Prod unaffected: all pods Running, no restarts

### After Phase 3 (CI/CD changes)

11. Push code change → Woodpecker deploys to test → verify at `test.pmon.dev`
12. `task promote:prod` → verify at `pmon.dev`

### Final validation

13. **Compare cluster resource allocation before/after**:
    ```
    kubectl describe node ten | grep -A5 "Allocated resources"
    ```
    Record before Phase 2 and after. Expected delta: ~380m CPU requests, ~2.4Gi memory requests from test env.

14. **Run stress test again**: `task test:hyperfoil:stress` — compare req/s and latency with baseline from step 4. Must be within 5% (test env adds requests but prod limits are unchanged)
15. **Verify prod data intact**: spot-check PG tables, ScyllaDB chat data, MinIO objects
