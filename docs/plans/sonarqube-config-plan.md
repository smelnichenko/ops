# SonarQube Configuration Plan

Configure SonarQube for maximum project coverage using best practices (Clean as You Code).

## Current State

- SonarQube CE 26.3.0 deployed at `sonar.pmon.dev`
- Three projects: `monitor-backend` (Gradle), `monitor-frontend` (sonarqube-scanner), `monitor-infra` (Dockerfiles/Helm)
- CI + CD run analysis on every push
- Backend: JaCoCo XML reports, 64.2% coverage, jOOQ generated code excluded
- Frontend: vitest + @vitest/coverage-v8, LCOV reports generated
- Infrastructure: Dockerfiles + Helm templates + Ansible YAML scanned

## Phases

### Phase 1: Frontend Coverage (vitest + LCOV) — DONE

- Installed `@vitest/coverage-v8`, configured v8 provider with LCOV reporter in `vitest.config.ts`
- Added `test:coverage` script to `package.json`
- CI/CD run `npm run test:coverage` (typecheck + unit tests + coverage)
- `sonar-project.properties` points to `coverage/lcov.info`

### Phase 2: Backend Source Exclusions — DONE

- `sonar.exclusions`: `**/io/schnappy/jooq/generated/**`
- `sonar.coverage.exclusions`: `**/config/**,**/dto/**,**/entity/**`

### Phase 3: Quality Gate (Clean as You Code) — MANUAL

Verify in SonarQube UI:
- Both projects use "Sonar way" quality gate (default)
- New Code definition set to "Previous version" (reference branch = master)

### Phase 4: Quality Profiles — MANUAL

Verify in SonarQube UI:
- "Sonar way" Java and TypeScript profiles are active (defaults)

### Phase 5: CI Quality Gate Check — DONE

- Backend: `sonar.qualitygate.wait=true`, timeout 300 in `build.gradle`
- Frontend: `sonar.qualitygate.wait=true`, timeout 300 in `sonar-project.properties`
- CI blocks on quality gate failure; CD uses `wait=false` (informational)

### Phase 6: Infrastructure Scanning — DONE

- Root `sonar-project.properties` for `monitor-infra` project
- Sources: `helm`, `deploy`, `.github`, Dockerfiles
- CI runs infra sonar step when helm/deploy/.github changes detected

### Phase 7: CD Pipeline Integration — DONE

- Sonar analysis steps added to `cd.yml` after test gates
- `qualitygate.wait=false` — does not block deploy

### Phase 8: Secrets Management — DONE

- Added `adminPassword` and `token` fields to Helm values and sonarqube-secret.yaml
- Added Vault ESO mappings in external-secrets.yaml for admin_password and token
- Updated setup-vault.yml seed to include admin_password and token from env vars
- Added auto-configure logic in test-sonarqube.yml: change default admin password, generate API token, seed to Vault
- Production `.env` on ten updated with SONARQUBE_ADMIN_PASSWORD and SONARQUBE_TOKEN

### Phase 9: Verify and Document — DONE

- CLAUDE.md updated with SonarQube section
- Frontend coverage: 17.6% (LCOV reports generated)
- Backend coverage: 58.8% (JaCoCo XML reports)
- SonarQube dashboard confirmed working at sonar.pmon.dev
- Quality gate blocks CI on feature branches; informational on master
