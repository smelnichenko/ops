# Rename k8s Namespace: monitor → schnappy

## Context

All services (monitor, admin, chat, chess, gateway, site, game-scp) run in the `monitor` namespace with pod prefix `monitor-*`. The namespace predates the microservice split — now that each service has its own repo, the namespace should reflect the organization name `schnappy`. Pod names change from `monitor-game` → `schnappy-game-scp`, `monitor-app` → `schnappy-app`, etc.

This is a coordinated change across **all repos**: platform (Helm chart), infra (Flux state), ops (Ansible + Vagrant tests), and documentation.

## Approach

**Strategy: Blue-green namespace migration**
1. Create new `schnappy` namespace
2. Deploy everything to `schnappy` via Helm release rename
3. Verify all services healthy
4. Delete old `monitor` namespace
5. Update all references

This avoids downtime — the old namespace stays alive until the new one is verified.

## Steps

### Phase 1: Helm Chart (platform repo)

The Helm `_helpers.tpl` already uses `.Release.Name` for all names — changing the release name from `monitor` to `schnappy` auto-changes ALL pod/service/secret names. Only hardcoded `namespace="monitor"` references need manual fixes.

**Files to update in `/home/sm/src/platform/`:**

1. `helm/templates/prometheus-rules-configmap.yaml` — Replace all `namespace="monitor"` with `namespace="{{ .Release.Namespace }}"` (templated)
2. `helm/templates/prometheus-configmap.yaml` — Check for hardcoded namespace
3. `helm/templates/network-policies.yaml` — Any hardcoded namespace refs
4. `helm/templates/_helpers.tpl` — Rename template names from `monitor.*` to `app.*` (cosmetic but cleaner)

### Phase 2: Infra Repo (Flux state)

**Files to update in `/home/sm/src/infra/clusters/production/`:**

1. Rename directory `monitor/` → `schnappy/`
2. `schnappy/namespace.yaml` — `name: schnappy`
3. `schnappy/helmrelease.yaml`:
   - `namespace: schnappy`
   - `releaseName: schnappy` (changes pod prefix)
   - ALL `existingSecret: monitor-*` → `schnappy-*`
4. `schnappy/kustomization.yaml` — Update resource paths
5. `schnappy/platform-source.yaml` — Update if exists
6. Root kustomization — Update path from `monitor/` to `schnappy/`
7. `velero/helmrelease.yaml` — `includedNamespaces: schnappy`

### Phase 3: Vault Secrets

Vault KV paths `secret/monitor/*` → `secret/schnappy/*`. This requires:
1. Copy all secrets: `vault kv get secret/monitor/X | vault kv put secret/schnappy/X`
2. Update Vault policy: `monitor` → `schnappy`
3. Update K8s auth role: namespace `monitor` → `schnappy`
4. Update ESO ClusterSecretStore or SecretStore if namespace-scoped

**Vault paths to migrate (14):**
- `secret/monitor/auth`, `postgres`, `redis`, `mail`, `ai`, `webhook`, `minio`, `kafka`, `grafana`, `sonarqube`, `registry`, `elasticsearch`, `alertmanager`

### Phase 4: Ansible Playbooks (ops repo)

**Files to update in `/home/sm/src/ops/`:**

1. `deploy/ansible/vars/production.yml` — `monitor_namespace: schnappy`, `monitor_release_name: schnappy`, all `existingSecret` refs
2. `deploy/ansible/vars/development.yml` — Same
3. `deploy/ansible/playbooks/setup-vault.yml` — Vault policy names, K8s auth role, `secret/monitor/*` paths
4. `deploy/ansible/playbooks/setup-velero.yml` — Backup namespace, git mirror paths
5. `deploy/ansible/playbooks/setup-woodpecker.yml` — Secret namespace refs
6. `deploy/ansible/playbooks/setup-flux.yml` — GitRepository namespace
7. `deploy/ansible/uninstall.yml` — Namespace and PVC names
8. `docker-compose.yml` — Container name prefixes (local dev)

### Phase 5: Vagrant Tests (ops repo)

All test files in `/home/sm/src/ops/tests/ansible/`:
- `test-elk.yml`, `test-grafana.yml`, `test-kafka-scylla.yml`, `test-dr.yml`, `test-eso.yml`, `test-gateway.yml`, `test-hashcash.yml`, `test-linkerd.yml`, `test-microservices.yml`, `test-cicd.yml`, `test-sonarqube.yml`

Each needs: `ns: monitor` → `ns: schnappy`, pod name patterns, secret names.

### Phase 6: SonarQube Project Keys

Current keys: `monitor-backend`, `monitor-frontend`, `monitor-infra`, `monitor-chess`, `monitor-admin`, `monitor-chat`, `monitor-gateway`

These are SQ internal identifiers — renaming is optional. The project keys don't need to match the namespace. **Skip this** to avoid breaking analysis history.

### Phase 7: Documentation

1. `/home/sm/src/monitor/CLAUDE.md` — All namespace refs, secret paths, pod names
2. Memory files in `/home/sm/.claude/projects/`

### Phase 8: Woodpecker Secrets

The `woodpecker-ci-secrets` k8s secret is in the `woodpecker` namespace (not affected). But pipeline steps that reference `monitor` namespace for kubectl commands need updating:
- `setup-woodpecker.yml` references `monitor-sonarqube` secret in `monitor` namespace

## Key Files (Critical Path)

| File | Repo | Changes |
|------|------|---------|
| `helm/templates/prometheus-rules-configmap.yaml` | platform | ~30 namespace refs |
| `clusters/production/monitor/helmrelease.yaml` | infra | namespace + 14 secret refs |
| `clusters/production/monitor/namespace.yaml` | infra | namespace name |
| `deploy/ansible/vars/production.yml` | ops | namespace + release name + secrets |
| `deploy/ansible/playbooks/setup-vault.yml` | ops | Vault paths + policies |
| `deploy/ansible/playbooks/setup-velero.yml` | ops | backup namespace |
| `tests/ansible/test-*.yml` (11 files) | ops | namespace + pod names |
| `CLAUDE.md` | monitor | 70+ refs |

## Risks

1. **Vault secret migration** — Must copy secrets BEFORE deploying to new namespace, or pods can't start
2. **Velero backups** — Old backups reference `monitor` namespace; can't restore to `schnappy` without manual intervention
3. **ELK logs** — Historical logs have `kubernetes.namespace_name: monitor`; queries need updating
4. **DNS/Ingress** — No change needed (Traefik routes by host, not namespace)
5. **Flux timing** — Must deploy namespace + secrets before HelmRelease tries to install

## Verification

1. All pods in `schnappy` namespace Running 1/1
2. `pmon.dev` loads correctly
3. Login works end-to-end
4. Chat WebSocket connects
5. Grafana dashboards show data
6. Prometheus alerts fire correctly
7. Velero backup of `schnappy` namespace succeeds
8. `task test:vault` passes in Vagrant
9. `task test:elk` passes in Vagrant
10. Old `monitor` namespace is empty and deleted
