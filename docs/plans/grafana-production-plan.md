# Enable Grafana for Production

## Goal

Enable Grafana in production with Traefik ingress at `grafana.pmon.dev`, Vault-managed credentials, and Vagrant integration test.

## Current State

- **Helm templates**: All exist — deployment, service, PVC, secret, datasources, dashboards, dashboard-provider, network policies
- **ExternalSecret**: Already configured for `secret/monitor/grafana` (keys: `admin_user`, `admin_password`)
- **Dashboard**: Pre-built "Web Page Monitor" dashboard with 7 panels (extracted values, checks, response times, success rate, percentiles)
- **Datasource**: Prometheus pre-configured
- **Network policies**: Grafana → Prometheus (9090), Traefik → Grafana (3000) already exist
- **Production**: `grafana.enabled: false`, `grafana.image: grafana/grafana:12.4.0`
- **Missing**: Ingress template (only NodePort), ingress values, Vault secret seeding

## Implementation Steps

### Step 1: Add Grafana ingress template

New file `templates/grafana-ingress.yaml` — follows the same pattern as `kibana-ingress.yaml`:
- Traefik IngressRoute at `grafana.pmon.dev`
- TLS via cert-manager (Let's Encrypt)
- Gated behind `grafana.enabled` and `grafana.ingress.enabled`

Add `grafana.ingress` values to `values.yaml`:
```yaml
grafana:
  ingress:
    enabled: false
    className: ""
    host: ""
    tls:
      enabled: false
      secretName: ""
      clusterIssuer: ""
```

Files: `templates/grafana-ingress.yaml` (NEW), `values.yaml`

### Step 2: Update Grafana service type

Change default service type from `NodePort` to `ClusterIP` (ingress handles external access).
Keep `service.type` configurable for backwards compatibility.

Files: `templates/grafana-service.yaml`, `values.yaml`

### Step 3: Update production.yml

Enable Grafana with production-appropriate resources:
```yaml
grafana:
  enabled: true
  image: grafana/grafana:12.4.0
  existingSecret: "monitor-grafana"
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
  storage:
    size: 5Gi
    storageClass: "local-path"
  service:
    type: ClusterIP
  ingress:
    enabled: true
    className: traefik
    host: "grafana.pmon.dev"
    tls:
      enabled: true
      secretName: "grafana-pmon-dev-tls"
      clusterIssuer: "letsencrypt-prod"
```

Files: `deploy/ansible/vars/production.yml`

### Step 4: Seed Grafana credentials into Vault

Add `secret/monitor/grafana` to Vault KV:
- `admin_user`: admin username
- `admin_password`: secure password

Add to `setup-vault.yml` secret seeding section.

Files: `deploy/ansible/playbooks/setup-vault.yml`

### Step 5: Vagrant integration test

New playbook `test-grafana.yml`:
- Seed Grafana credentials into Vault
- Deploy chart with `grafana.enabled: true`, `prometheus.enabled: true` (Grafana needs it as datasource)
- Verify Grafana pod running
- Verify HTTP 200 on `/api/health`
- Verify ExternalSecret synced
- Verify datasource configured (query `/api/datasources`)

Taskfile entry: `task test:grafana`

Files: `tests/ansible/test-grafana.yml` (NEW), `Taskfile.yml`

### Step 6: DNS + docs

- Add `grafana.pmon.dev` A record to DNS provider
- Update CLAUDE.md with Grafana section
- Update resource allocation table

## Files to Create/Modify

| File | Change | Status |
|------|--------|--------|
| `infra/helm/templates/grafana-ingress.yaml` | NEW — Traefik ingress | Done |
| `infra/helm/values.yaml` | Add `grafana.ingress`, default ClusterIP | Done |
| `infra/helm/templates/grafana-service.yaml` | Service type already configurable | N/A |
| `deploy/ansible/vars/production.yml` | Enable Grafana, add ingress config | Done |
| `deploy/ansible/playbooks/setup-vault.yml` | Grafana secret seeding already exists | N/A |
| `tests/ansible/test-grafana.yml` | NEW — Vagrant test | Done |
| `Taskfile.yml` | Add `test:grafana` task | Done |
| `CLAUDE.md` | Update docs | Done |

## Verification

1. `helm lint` passes
2. `kubectl get pods -n monitor` — Grafana running
3. `https://grafana.pmon.dev` — Grafana loads, login works
4. Prometheus datasource auto-configured
5. "Web Page Monitor" dashboard visible with live data
6. Vagrant test passes (`task test:grafana`)

## Rollback

Set `grafana.enabled: false` and redeploy. PVC data persists.
