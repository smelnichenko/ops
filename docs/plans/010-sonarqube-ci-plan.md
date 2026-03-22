# SonarQube CI Integration Plan

## Goal

Deploy SonarQube Community Edition to k3s and integrate with Forgejo Actions CI for Java (backend) and TypeScript (frontend) code analysis with quality gates.

## Architecture

```
Forgejo Actions CI
  ├─ Backend: ./gradlew sonar (after test)
  └─ Frontend: npx sonar-scanner (after tsc)
        ↓
SonarQube (namespace: monitor)
  ├─ SonarQube CE (Deployment)  ← analysis engine + web UI
  └─ PostgreSQL (StatefulSet)   ← dedicated, not shared with app DB
        ↓
Ingress: sonar.pmon.dev (DNS-01, internal only like grafana/logs)
```

## Resource Budget

| Pod | CPU req/limit | Memory req/limit | Notes |
|-----|---------------|------------------|-------|
| SonarQube | 500m / 4000m | 2Gi / 4Gi | JVM heap 512m x3 (web/ce/search) + ES embedded |
| PostgreSQL | 100m / 1000m | 256Mi / 512Mi | Light usage, just metadata |

## Steps

### Phase 1: Helm Templates — DONE

- [x] 1.1 Add `sonarqube.enabled` toggle to `values.yaml` (default false)
- [x] 1.2 Add helper templates to `_helpers.tpl` (sonarqube + sonarqube-postgres labels, selectors, service names, secret name)
- [x] 1.3 Create `sonarqube-postgres-statefulset.yaml` (PostgreSQL 17-alpine, dedicated, readOnlyRootFilesystem)
- [x] 1.4 Create `sonarqube-postgres-service.yaml` (ClusterIP, port 5432)
- [x] 1.5 Create `sonarqube-secret.yaml` (DB password with fail-fast validation, existingSecret support)
- [x] 1.6 Create `sonarqube-deployment.yaml` (26.3.0.120487-community, Recreate strategy, init-sysctl for vm.max_map_count, emptyDir for data/extensions/logs/tmp)
- [x] 1.7 Create `sonarqube-pvc.yaml` (data PVC for SonarQube)
- [x] 1.8 Create `sonarqube-service.yaml` (ClusterIP, port 9000)
- [x] 1.9 Create `sonarqube-ingress.yaml` (sonar.pmon.dev, DNS-01 TLS via cert-manager)
- [x] 1.10 Create `sonarqube-networkpolicy.yaml` (SQ↔SQ-postgres, Traefik ingress, DNS egress)
- [x] 1.11 Add ExternalSecret to `external-secrets.yaml` (Vault KV `secret/monitor/sonarqube`)
- [x] 1.12 Helm lint passes (both enabled and disabled)

### Phase 2: Vagrant Testing — DONE

- [x] 2.1 Create `test-sonarqube.yml` Ansible playbook (seeds Vault, deploys chart, verifies pods/status/NP)
- [x] 2.2 Add `task test:sonarqube` to Taskfile.yml
- [x] 2.3 Run Vagrant test — all checks pass

### Phase 3: Vault Secrets (production) — DONE

- [x] 3.1 Add `secret/monitor/sonarqube` seed task to `setup-vault.yml` (`postgres_password` from `SONARQUBE_DB_PASSWORD` env var)
- [x] 3.2 Vault policy already covers `secret/data/*` via ESO policy — no changes needed

### Phase 4: DNS (production) — DONE

- [x] 4.1 Add `sonar.pmon.dev` to Unbound config on router (→ 192.168.11.2)
- [x] 4.2 Verify DNS-01 cert issuance (after production deployment)

### Phase 5: Backend Integration (Gradle) — DONE

- [x] 5.1 Add SonarQube Gradle plugin `org.sonarqube` v7.2.3.7755 to `build.gradle` (v6.x incompatible with Gradle 9 — `getConvention()` removed)
- [x] 5.2 Add JaCoCo plugin for XML coverage reports, finalized by test task
- [x] 5.3 Configure sonar properties (projectKey, host.url, token from env, java.source 25, JaCoCo XML path)

### Phase 6: Frontend Integration — DONE

- [x] 6.1 Add `sonar-project.properties` to `frontend/`
- [x] 6.2 Add `sonarqube-scanner` v4.3.4 npm dev dependency (not `sonar-scanner` which is unmaintained v3.1.0)

### Phase 7: CI Pipeline — DONE

- [x] 7.1 Add `SONAR_TOKEN` and `SONAR_HOST_URL` as Forgejo secrets (after SonarQube is deployed and token is generated)
- [x] 7.2 Update `ci.yml` — add sonar analysis steps after tests (backend: `./gradlew sonar`, frontend: `npx sonarqube-scanner`)
- [ ] 7.3 Configure quality gate in SonarQube UI (after production deployment)
- [ ] 7.4 Optionally add quality gate check step (poll SonarQube API, fail CI if gate fails)

### Phase 8: Production Deployment — DONE

- [x] 8.1 Add sonarqube vars to `vars/production.yml` (enabled, image, existingSecret, resources, ingress, storage)
- [x] 8.2 Seed Vault secret `secret/monitor/sonarqube` with `postgres_password`
- [x] 8.3 Deploy to production via CD push to master
- [x] 8.4 Verify sonar.pmon.dev accessible, DNS-01 cert issued
- [x] 8.5 Generate SonarQube token, add `SONAR_TOKEN` + `SONAR_HOST_URL` as Forgejo secrets
- [x] 8.6 Run CI pipeline, verify analysis results appear in dashboard
- [x] 8.7 Quality gate — using default gate (passed on first analysis)

## Decisions

1. **Same namespace** (`monitor`) — deployed as part of the monitor Helm chart, simplifies secrets and network policies
2. **Dedicated PostgreSQL** — no risk to app DB, independent lifecycle
3. **DNS-01 TLS** — internal only (like grafana, logs), no public A record needed
4. **CI-only scanning** — SonarQube runs persistently for dashboard/trends, scanner runs in CI
5. **No container-based CI needed** — sonar scanner runs as Gradle plugin (backend) and npm package (frontend), works fine on host runner
6. **Recreate strategy** — SonarQube uses embedded ES with file locks; only one instance can run at a time
7. **SonarQube 2026 LTA** — latest long-term active release (replaces LTS naming)

## Key Files

| File | Purpose |
|------|---------|
| `sonarqube-deployment.yaml` | SonarQube CE with init-sysctl, emptyDir volumes |
| `sonarqube-pvc.yaml` | Data PVC for SonarQube |
| `sonarqube-service.yaml` | ClusterIP on port 9000 |
| `sonarqube-ingress.yaml` | sonar.pmon.dev with DNS-01 TLS |
| `sonarqube-postgres-statefulset.yaml` | Dedicated PostgreSQL 17 |
| `sonarqube-postgres-service.yaml` | ClusterIP on port 5432 |
| `sonarqube-secret.yaml` | Inline secret with fail-fast validation |
| `sonarqube-networkpolicy.yaml` | SQ↔SQ-postgres, Traefik ingress |
| `test-sonarqube.yml` | Vagrant integration test |

## Notes

- SonarQube Community Edition is free, supports Java + TypeScript + JS + 30+ languages
- Embedded Elasticsearch in SonarQube CE (no external ES needed)
- `vm.max_map_count >= 524288` required (init-sysctl container handles this)
- SonarQube 2026 LTA requires PostgreSQL 13-17 (we use 17)
- Quality gate webhook to Forgejo PR status is possible but requires Forgejo-specific plugin or API scripting
- SonarQube 2026.1 requires writable `/tmp` for Java Attach API socket files
