# SonarQube Setup Automation

## Status: COMPLETE (2026-03-22)

## What was implemented

### Helm Hook Job (`sonarqube-setup-job.yaml`)
- Post-install/post-upgrade hook (weight 15, after SQ starts)
- Image: `curlimages/curl:8.12.1`
- Timeout: 600s, backoff: 5 retries
- Idempotent — safe on re-deploy

### Steps (all idempotent):
1. Wait for SQ to be UP (poll `/api/system/status`, max 120 retries × 5s)
2. Change admin password if still default (`admin:admin`)
3. Generate analysis token (name=`ci`, skip if exists)
4. Create quality gates: `Service` (80% coverage, default) and `Frontend` (70%)
5. Create projects from `sonarqube.setup.projects` values list
6. Assign `Frontend` gate to projects with `gate: Frontend`

### Network Policy
- Setup job egress → SQ port 9000 + DNS
- SQ ingress ← setup job (added to `sonarqube-networkpolicy.yaml`)

### Helm Values
```yaml
sonarqube:
  setup:
    enabled: true
    projects:
      - key: schnappy-monitor
        name: Schnappy Monitor
      - key: schnappy-site
        name: Schnappy Site
        gate: Frontend
      # ... etc
```

### Files
- `platform/helm/templates/sonarqube-setup-job.yaml` — Job + ServiceAccount
- `platform/helm/templates/sonarqube-networkpolicy.yaml` — Ingress from setup job
- `platform/helm/templates/network-policies.yaml` — Setup job egress NP
- `platform/helm/values.yaml` — `sonarqube.setup` section
- `infra/clusters/production/schnappy/helmrelease.yaml` — Project list

## What was NOT implemented (deferred)

### SSO via Keycloak
- SQ Community Edition supports HTTP header SSO only
- Keycloak integration planned as dedicated project (provides SSO for SQ + Grafana + Kibana + all services)
- Forward-auth stopgap considered but deferred in favor of proper Keycloak solution

## Verification
- Fresh deploy: setup job runs, creates all config in 10s
- Re-deploy: setup job detects existing config, skips gracefully
- SQ analysis works with auto-generated token
