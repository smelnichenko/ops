# Plan 058: Custom Hyperfoil image with MinIO client

## Status: COMPLETED (2026-04-11)

## Context

Hyperfoil jobs downloaded mc binary at runtime (~15s, required external HTTPS egress). Pre-installed it in a custom image.

## Implementation

### Repo: `schnappy/hyperfoil` on git.pmon.dev

**Dockerfile:**
```dockerfile
FROM quay.io/hyperfoil/hyperfoil:0.28.0
USER root
RUN microdnf install -y wget && \
    wget -q -O /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x /usr/local/bin/mc && \
    microdnf clean all
USER default
```

Woodpecker CD pipeline builds on push to main → `git.pmon.dev/schnappy/hyperfoil:latest`

### Platform changes

- `helm/schnappy/values.yaml`: image changed to `git.pmon.dev/schnappy/hyperfoil:latest`
- Load + stress configmaps: removed `curl` download of mc, use `mc` directly
- Stress test expanded to 10 stages: 100→200→300→400→500→600→700→800→900→1000 req/s

### Also done in this session

- Reports service moved to `schnappy-observability` chart (infra namespace)
- `hyperfoil-reports` bucket moved to infra MinIO
- Resource requests updated to match stress test consumption
- PriorityClasses for ordered boot after node restart
- DestinationRules with outlier detection for app services
- k6 smoke test converted from PostSync hook to sync-wave Job
- All Jobs use `Delete=true` + `ignoreDifferences` for immutability handling
