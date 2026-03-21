# Nexus Repository Manager — Pi Deployment Plan

## Status: Complete

Deployed to production 2026-03-15. All phases done.

## Context

The project needs a general-purpose caching proxy for package managers across the homelab: Gradle/Maven, npm, pip/PyPI, and Docker. Previously:
- Docker images were cached via 3 separate `distribution/distribution` instances on the Pi (ports 5000-5002)
- Gradle, npm, pip all resolved directly from upstream with no caching
- CI pipeline pods are ephemeral — dependencies re-downloaded on every Woodpecker build

## Decision

Deploy **Nexus OSS 3.90.1** (free, open-source edition) on the Pi (192.168.11.4, 8GB RAM) as a systemd service. This replaces the 3 Docker registry mirrors with a single service that also proxies Maven, npm, and PyPI.

**Why the Pi?**
- Avoids cluster resource pressure
- No chicken-and-egg problem (k3s needs to pull images to start pods — if image proxy is itself a pod, k3s can't start it when the proxy is down)
- Pi has 8GB RAM with low utilization (only Vault ~140MB)
- Same deployment pattern as Vault (standalone binary + systemd)

**Why Nexus OSS?**
- Single tool handles Maven, npm, PyPI, and Docker proxy — all needed formats
- apt proxy uses apt-cacher-ng (lightweight, dedicated tool) alongside Nexus on the same Pi

## Repositories

| Repository | Type | Format | Remote URL | Port |
|------------|------|--------|------------|------|
| `docker-hub` | proxy | docker | https://registry-1.docker.io | via 8082 (group) |
| `docker-elastic` | proxy | docker | https://docker.elastic.co | via 8082 (group) |
| `docker-quay` | proxy | docker | https://quay.io | via 8082 (group) |
| `docker-group` | group | docker | (groups above 3) | 8082 |
| `maven-central` | proxy | maven2 | https://repo1.maven.org/maven2/ | via 8081 |
| `maven-public` | group | maven2 | (groups maven-central) | via 8081 |
| `npm-registry` | proxy | npm | https://registry.npmjs.org/ | via 8081 |
| `npm-public` | group | npm | (groups npm-registry) | via 8081 |
| `pypi-proxy` | proxy | pypi | https://pypi.org/ | via 8081 |
| `pypi-public` | group | pypi | (groups pypi-proxy) | via 8081 |

## Implementation

### Phase 1: Ansible Playbook (`setup-nexus.yml`)

- [x] Install OpenJDK 21 JRE on Pi
- [x] Download Nexus OSS 3.90.1 tarball with SHA-256 checksum verification
- [x] Create `nexus` system user, data dir at `/mnt/data/nexus`
- [x] Systemd service with JVM opts (`-Xms512m -Xmx4g`, one flag per line in vmoptions)
- [x] UFW: ports 8081 + 8082 from LAN (IPv4 + IPv6)
- [x] Accept EULA via REST API (required for Nexus CE 3.90.x)
- [x] Provision repositories via REST API (post-start)
- [x] Enable Docker Bearer Token Realm + anonymous read access
- [x] Set cleanup policies (30-day retention for cached artifacts)
- [x] Change default admin password (from `NEXUS_ADMIN_PASSWORD` env var)
- [x] Decommission old registry mirrors (stop + disable systemd services)

### Phase 2: k3s Integration

- [x] Update `registries.yaml` template in `setup-k3s.yml` — all Docker mirrors point to port 8082
- [x] Scope `setup-k3s.yml` to `hosts: target` only (was `all`, accidentally installed k3s on Pi)

### Phase 3: CI Pipeline Integration

- [x] `build.gradle`: conditional Nexus Maven proxy via `NEXUS_URL` env var
- [x] Switch all pipeline secrets from `from_secret` (Woodpecker internal store) to native k8s secrets (`backend_options.kubernetes.secrets` referencing `woodpecker-ci-secrets`)
- [x] Enable `WOODPECKER_BACKEND_K8S_ALLOW_NATIVE_SECRETS=true` on Woodpecker agent
- [x] Add `nexus_url` + `nexus_npm_registry` to `woodpecker-ci-secrets` k8s Secret
- [x] Add Nexus secrets to `setup-woodpecker.yml` for persistence across re-deploys
- [x] Add pipeline network policy egress rule for Pi (192.168.11.4:8081/8082)

### Phase 4: Testing

- [x] Vagrant integration test (`test-nexus.yml`) — 10 checks, all pass
- [x] `task test:nexus` in Taskfile
- [x] Production deploy verified — 615MB cached (998 Maven, 525 npm, 65 Docker assets)

### Phase 5: Cleanup

- [x] Remove Docker/containerd from Pi (not needed, leftover from k3s misinstall)
- [x] Remove dev tooling from ten (~7GB: .gradle, .npm, .nvm, .sdkman, etc.)
- [x] Move `.env` from ten to aqua (deploy machine)

### Phase 6: apt-cacher-ng

- [x] Install apt-cacher-ng on Pi (same host as Nexus)
- [x] Configure cache dir at `/mnt/data/apt-cacher-ng`, port 3142
- [x] UFW: port 3142 from LAN (IPv4 + IPv6)
- [x] Add `apt_proxy` to Woodpecker CI secrets in `setup-woodpecker.yml`
- [x] Pass `http_proxy` build arg in Kaniko backend image build (`cd.yaml`)
- [x] Add apt-cacher-ng tests to `test-nexus.yml`

## Lessons Learned

- **Nexus vmoptions**: must be one flag per line — all flags on one line are silently ignored
- **Nexus CE EULA**: 3.90.x requires EULA acceptance via REST API before proxying works; disclaimer text must match exactly (including Unicode curly quotes)
- **Nexus download URL**: changed from `nexus-{ver}-unix.tar.gz` to `nexus-{ver}-linux-{arch}.tar.gz` with architecture detection
- **k8s NetworkPolicy + ClusterIP**: `ipBlock` alone doesn't match ClusterIP traffic (DNAT); need `namespaceSelector` for the `default` namespace to reach the k8s API
- **Woodpecker `from_secret`**: only reads from Woodpecker's internal store (UI/API), not k8s Secrets; use `backend_options.kubernetes.secrets` for native k8s Secret references
- **Pipeline NP + LAN hosts**: external egress blocks RFC1918; need explicit `ipBlock` rules for LAN hosts like the Pi

## Resources

| Component | CPU | Memory |
|-----------|-----|--------|
| Nexus 3.x | varies | 512Mi-4Gi heap (~1Gi typical) |
| apt-cacher-ng | minimal | ~256Mi (cache-dependent) |
| Vault | minimal | ~140Mi |
| **Pi total** | — | **~1.5Gi of 8Gi** |

## Ports

| Port | Service | Purpose |
|------|---------|---------|
| 8081 | Nexus | Web UI + Maven/npm/PyPI API |
| 8082 | Nexus | Docker registry HTTP connector |
| 3142 | apt-cacher-ng | Debian/Ubuntu apt caching proxy |

## Files

**New:**
- `deploy/ansible/playbooks/setup-nexus.yml`
- `tests/ansible/test-nexus.yml`
- `docs/plans/nexus-repository-plan.md`

**Modified:**
- `backend/build.gradle` — conditional Nexus repository
- `.woodpecker/ci.yaml` — native k8s secrets for NEXUS_URL, NPM_CONFIG_REGISTRY, sonar, registry
- `.woodpecker/cd.yaml` — native k8s secrets for all pipeline secrets + apt proxy build arg for Kaniko
- `backend/Dockerfile.runtime` — `ARG http_proxy` for apt-cacher-ng in CI builds
- `deploy/ansible/playbooks/setup-k3s.yml` — `registries.yaml` port update, scoped to `hosts: target`
- `deploy/ansible/playbooks/setup-woodpecker.yml` — Nexus + apt-cacher-ng secrets, native k8s secrets addon, NP egress rule
- `Taskfile.yml` — `deploy:nexus` + `test:nexus` tasks
- `Vagrantfile` — vault-pi RAM bumped to 4GB
- `CLAUDE.md` — documentation
