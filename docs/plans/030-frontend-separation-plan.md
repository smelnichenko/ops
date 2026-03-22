# Separate Frontend into Dedicated Git Repository

## Context

The frontend (React/TypeScript/Vite) lives inside the monitor monorepo at `frontend/`. All other services (admin, chat, chess, api-gateway) are already separate repos with their own Woodpecker pipelines. The frontend has zero code dependencies on the backend — it communicates exclusively via HTTP to `/api/` endpoints. Separating it completes the microservice split and simplifies CI/CD (no more change detection for frontend in the monorepo pipeline).

The Godot game (`games/scp/`) stays in the monitor repo for now — will be separated later. The frontend CD pipeline will skip the game export step; game builds will be addressed separately.

## Steps

### 1. Create Forgejo repo `schnappy/frontend`
```bash
# Via Forgejo API or UI
```

### 2. Migrate files with git history
Use `git filter-repo` to extract `frontend/` subdirectory with full commit history into the new repo.

Files to include:
- `frontend/` → repo root (src/, tests/, public/, package.json, tsconfig.json, vite.config.ts, vitest.config.ts, playwright.config.ts, Dockerfile, Dockerfile.runtime, nginx.conf, nginx.conf.template, security-headers.conf, security-headers-base.conf, docker-entrypoint.sh, sonar-project.properties, .dockerignore)

Files NOT migrated:
- `games/scp/` — stays in monitor repo
- `backend/`, `infra/`, `deploy/` — not frontend

### 3. Create `.woodpecker/ci.yaml` in new repo
Adapt from existing monitor CI frontend steps:
- `frontend-test`: `tsc --noEmit` + `vitest run --coverage`
- `frontend-sonar`: SonarQube analysis with `sonar.qualitygate.wait=true`

Clone config: `depth: 100`, `partial: false`

### 4. Create `.woodpecker/cd.yaml` in new repo
Adapt from existing monitor CD frontend steps:
- `build-frontend-dist`: npm build with `VITE_GIT_HASH` + `VITE_BUILD_TIME`
- `push-frontend-image`: Kaniko push to `git.pmon.dev/schnappy/frontend:$GIT_HASH`
- `update-infra`: Commit image tag to `schnappy/infra` repo

No game export step — skip for now.

Image name changes: `git.pmon.dev/schnappy/monitor-frontend` → `git.pmon.dev/schnappy/frontend`

### 5. Activate in Woodpecker
```bash
# Sync repos, activate, add secrets
woodpecker-cli repo sync
woodpecker-cli repo add schnappy/frontend
```

Secrets needed (from `woodpecker-ci-secrets`):
- `nexus_npm_registry` → `NPM_CONFIG_REGISTRY`
- `sonar_token` → `SONAR_TOKEN`
- `sonar_host_url` → `SONAR_HOST_URL`
- `registry_user` → `REGISTRY_USER`
- `registry_token` → `REGISTRY_TOKEN`
- `infra_repo_token` → `INFRA_TOKEN`

### 6. Update Helm chart + helmrelease
Update `frontend.image.repository` from `git.pmon.dev/schnappy/monitor-frontend` to `git.pmon.dev/schnappy/frontend` in:
- `/home/sm/src/monitor/infra/helm/values.yaml`
- `/home/sm/src/infra/clusters/production/monitor/helmrelease.yaml`

### 7. Remove frontend from monitor repo
- Delete `frontend/` directory
- Remove frontend steps from `.woodpecker/ci.yaml` and `.woodpecker/cd.yaml`
- Remove frontend change detection from `detect-changes` step
- Remove frontend sonar step
- Remove `build-frontend-dist`, `push-frontend-image`, `export-game` steps from CD
- Remove frontend image tag update from `update-infra` step
- Update `CLAUDE.md` directory structure

### 8. Update SonarQube
- Rename project key from `monitor-frontend` to `frontend` (or keep as-is for history continuity)

### 9. Configure pitest nightly cron
- Add `pitest-nightly` cron for new repo (5:30 AM, after gateway at 5:00 AM)

### 10. Update CLAUDE.md and memory
- Update directory structure section
- Update CI/CD section (registered repos list)
- Update Woodpecker repo list

## Key Files
- `/home/sm/src/monitor/frontend/` — source to migrate
- `/home/sm/src/monitor/.woodpecker/cd.yaml` — remove frontend steps
- `/home/sm/src/monitor/.woodpecker/ci.yaml` — remove frontend steps
- `/home/sm/src/monitor/infra/helm/values.yaml` — update image repo
- `/home/sm/src/infra/clusters/production/monitor/helmrelease.yaml` — update image repo
- `/home/sm/src/admin/.woodpecker/cd.yaml` — reference pattern for new repo pipeline

## Verification
1. Push to new frontend repo → Woodpecker CD pipeline succeeds
2. Image pushed to `git.pmon.dev/schnappy/frontend:$HASH`
3. `update-infra` commits tag to infra repo
4. Flux deploys new frontend pod with correct image
5. Site loads at `pmon.dev` — all pages render correctly
6. SonarQube analysis runs and passes quality gate
7. Monitor repo pipeline no longer has frontend steps
