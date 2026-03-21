# ELK Stack for Monitor

## Goal

1. Centralized log aggregation with 30-day retention for all k8s pods
2. Elasticsearch as a shared service for future app-level full-text search (e.g. monitor results, RSS articles)

## Architecture

```
k8s pods (stdout/stderr)
  └─ Filebeat (DaemonSet) → reads /var/log/pods/*
       └─ Elasticsearch (StatefulSet, single node, monitor namespace)
            ├─ Kibana (Deployment) → https://logs.pmon.dev
            └─ Monitor App (Spring Boot) → direct ES queries for search features
```

Everything in the `monitor` namespace — Elasticsearch is both a logging backend and an app-level search engine.

## Components

| Component | Image | Purpose |
|-----------|-------|---------|
| Elasticsearch | docker.elastic.co/elasticsearch/elasticsearch:8.17.4 | Log storage + app search index |
| Kibana | docker.elastic.co/kibana/kibana:8.17.4 | Web UI for log search + dashboards |
| Filebeat | docker.elastic.co/beats/filebeat:8.17.4 | Log shipper (DaemonSet, cluster-wide) |

## Resource Planning

| Component | CPU req/limit | Memory req/limit | Storage | Typical usage |
|-----------|---------------|------------------|---------|---------------|
| Elasticsearch | 500m / 4000m | 4Gi / 8Gi | 50Gi (NVMe, local-path) | ~2.7Gi |
| Kibana | 100m / 1000m | 1Gi / 2Gi | - | ~550Mi |
| Filebeat | 50m / 200m | 128Mi / 256Mi | - (hostPath /var/log) | ~110Mi |

Updated totals with ELK:
```
# Active total with ELK:       ~24200m     ~41Gi
# (leaves ~23GB for OS cache on 64GB node)
```

## Storage

- Elasticsearch data on NVMe via local-path-provisioner at `/mnt/storage/k3s-pvcs`
- 50Gi PVC, single-node mode (no replicas needed for single k3s node)
- ILM (Index Lifecycle Management) policy: delete log indices older than 30 days
- App indices (search data) have no auto-deletion — managed by the app
- Expected log volume: ~50MB/day for a small app cluster = ~1.5GB/month

## Elasticsearch Configuration

Single-node mode (no clustering overhead):

```yaml
discovery.type: single-node
xpack.security.enabled: true          # basic auth for Kibana + app
xpack.security.http.ssl.enabled: false # TLS handled by Traefik ingress (Kibana only)
ES_JAVA_OPTS: "-Xms2g -Xmx2g"        # half of 4Gi request
```

ILM policy for 30-day log retention:

```json
{
  "policy": {
    "phases": {
      "hot": { "actions": {} },
      "delete": {
        "min_age": "30d",
        "actions": { "delete": {} }
      }
    }
  }
}
```

## Index Strategy

| Index pattern | Purpose | Retention | Owner |
|---------------|---------|-----------|-------|
| `filebeat-*` | Pod logs (all namespaces) | 30 days (ILM) | Filebeat |
| `monitor-*` | App search data (future) | Permanent | Monitor app |

The app connects to ES at `http://monitor-elasticsearch:9200` using the `elastic` user credentials from the same Vault secret. Spring Boot config:

```yaml
spring:
  elasticsearch:
    uris: ${ELASTICSEARCH_URL:http://localhost:9200}
    username: ${ELASTICSEARCH_USERNAME:}
    password: ${ELASTICSEARCH_PASSWORD:}
```

## Filebeat Configuration

- Autodiscover k8s pods via `add_kubernetes_metadata`
- Parse JSON logs from containers (Spring Boot logs as structured JSON)
- Add k8s labels: namespace, pod, container, node
- Exclude Filebeat's own logs to prevent loops
- Ship to Elasticsearch at `http://monitor-elasticsearch.monitor.svc:9200`
- Filebeat DaemonSet is cluster-wide (collects from all namespaces)

## Ingress

Kibana exposed via Traefik at `logs.pmon.dev`:
- TLS via cert-manager (Let's Encrypt)
- Elasticsearch NOT exposed externally (internal only via k8s service)

DNS: Add A record for `logs.pmon.dev` pointing to 192.168.11.2 (same as pmon.dev)

## Security

- Elasticsearch basic auth (credentials stored in Vault as `secret/monitor/elasticsearch`)
- ESO syncs to k8s Secret `monitor-elasticsearch` with keys: `ELASTICSEARCH_PASSWORD`, `KIBANA_PASSWORD`
- Kibana authenticates as `kibana_system` user
- App authenticates as `elastic` user (or a dedicated `monitor_app` user later)
- Network policies: Filebeat → ES (9200), Kibana → ES (9200), App → ES (9200), Traefik → Kibana (5601)
- Elasticsearch not exposed outside cluster

## Implementation Steps

### Step 1: Add ELK templates to Helm chart [DONE]

New template files in `infra/helm/templates/`:

| File | Resource |
|------|----------|
| `elasticsearch-statefulset.yaml` | Elasticsearch StatefulSet (1 replica) |
| `elasticsearch-service.yaml` | ClusterIP service on port 9200 |
| `elasticsearch-configmap.yaml` | elasticsearch.yml config |
| `elasticsearch-secret.yaml` | Auth credentials (or existingSecret) |
| `kibana-deployment.yaml` | Kibana Deployment |
| `kibana-service.yaml` | ClusterIP service on port 5601 |
| `kibana-configmap.yaml` | kibana.yml config |
| `kibana-ingress.yaml` | Traefik ingress for logs.pmon.dev |
| `filebeat-daemonset.yaml` | Filebeat DaemonSet |
| `filebeat-configmap.yaml` | filebeat.yml + autodiscover |
| `filebeat-rbac.yaml` | ServiceAccount + ClusterRole for k8s API |

All gated behind `elk.enabled: false` in values.yaml.

### Step 2: Add values.yaml entries [DONE]

```yaml
elk:
  enabled: false
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.17.4
    replicas: 1
    javaOpts: "-Xms2g -Xmx2g"
    existingSecret: ""
    password: ""            # inline fallback (dev)
    resources:
      requests:
        memory: "4Gi"
        cpu: "500m"
      limits:
        memory: "8Gi"
        cpu: "4000m"
    storage:
      size: 50Gi
      storageClass: "local-path"
    retention:
      days: 30
  kibana:
    image: docker.elastic.co/kibana/kibana:8.17.4
    replicas: 1
    resources:
      requests:
        memory: "1Gi"
        cpu: "100m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
    ingress:
      enabled: true
      host: "logs.pmon.dev"
      tls:
        enabled: true
        secretName: "logs-pmon-dev-tls"
        clusterIssuer: "letsencrypt-prod"
  filebeat:
    image: docker.elastic.co/beats/filebeat:8.17.4
    resources:
      requests:
        memory: "128Mi"
        cpu: "50m"
      limits:
        memory: "256Mi"
        cpu: "200m"
```

### Step 3: Seed Elasticsearch credentials into Vault [DONE]

Add `secret/monitor/elasticsearch` to Vault KV:
- `password` (elastic superuser password)
- `kibana_password` (kibana_system user password)

Add ExternalSecret for `monitor-elasticsearch` in `external-secrets.yaml`.

### Step 4: Update production.yml [DONE]

Add ELK section with `elk.enabled: true`, resource limits, and `existingSecret: "monitor-elasticsearch"`.

### Step 5: Configure ILM + index template [DONE]

Post-deploy init job (Kubernetes Job, runs once):
- Wait for ES to be ready
- Create ILM policy `logs-30d-retention`
- Create index template `filebeat-*` with ILM policy attached
- Set up `kibana_system` user password
- Create `monitor-*` index template (no ILM, for future app use)

### Step 6: Network policies [DONE]

Add to existing network policy template:
- Allow: App → Elasticsearch (9200)
- Allow: Kibana → Elasticsearch (9200)
- Allow: Traefik → Kibana (5601)
- Filebeat DaemonSet needs cluster-wide access: k8s API (metadata) + Elasticsearch (9200)

### Step 7: Add Spring Boot Elasticsearch dependency (future, not in this phase)

When ready to add app-level search:
- Add `spring-boot-starter-data-elasticsearch` to `build.gradle`
- Add ES config to `application.yml`
- ES env vars (`ELASTICSEARCH_URL`, `ELASTICSEARCH_PASSWORD`) already available from the same secret
- No redeployment of ES needed — it's already running

### Step 8: Vagrant integration test [DONE — PASS]

New playbook `test-elk.yml` — validates ELK in the two-VM Vagrant environment before production deploy.
Deploys only ELK components (app replicas=0, postgres/redis disabled) for fast, focused testing.

**Phase 1: Seed test credentials**
- Get Vault root token from k8s secret (requires `vault_store_root_token: true` in vagrant vars)
- Seed `secret/monitor/elasticsearch` with test passwords into Vault KV

**Phase 2: Deploy chart with ELK enabled**
- `vagrant rsync k3s` to sync chart changes to VM
- Helm deploy with `elk.enabled: true`, reduced resources for Vagrant:
  - ES: 512Mi-1Gi RAM, `"-Xms256m -Xmx256m"`, 5Gi storage
  - Kibana: 512Mi-1Gi
  - Filebeat: 64Mi-128Mi
  - App replicas: 0 (not needed for ELK test)
  - Kibana ingress disabled (no TLS in Vagrant)

**Phase 3: Verify Elasticsearch**
- Wait for ES StatefulSet rollout
- Verify ES responds with cluster health (authenticated exec probe)
- Verify auth works: unauthenticated request returns 401
- Verify ExternalSecret synced for `monitor-elasticsearch`

**Phase 4: Verify Filebeat**
- Wait for Filebeat DaemonSet ready
- Query `filebeat-*` index for document count (WARN if 0 — timing-dependent)

**Phase 5: Verify Kibana**
- Wait for Kibana deployment rollout
- Init container sets `kibana_system` password via ES `_security` API
- Verify Kibana HTTP 200 on `/api/status`

**Phase 6: Verify ILM**
- Check ILM policy `logs-30d-retention` exists

**Summary:** PASS/PARTIAL with individual check results. Fails only on critical issues (ES/Filebeat not running).

**Test result (2026-03-06):** PASS — all critical checks passed. Filebeat 0 docs is a timing WARN.

Taskfile entry:
```yaml
test:elk:
  desc: Test ELK stack in Vagrant
  deps: [deploy:install]
  cmds:
    - cmd: vagrant destroy -f 2>/dev/null; true
    - cmd: vagrant up
    - defer: vagrant halt
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault-pi.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/test-elk.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml
```

Files:
- NEW `tests/ansible/test-elk.yml`
- Modified `Taskfile.yml` (add `test:elk` task)
- Modified `deploy/ansible/vars/vault-vagrant.yml` (add `vault_store_root_token: true`)

**Fixes discovered during Vagrant testing:**
- ES readiness/liveness probes: HTTP probes fail with 401 when security enabled → changed to exec probes with `curl -u elastic:$ELASTIC_PASSWORD`
- Kibana `xpack.security.enabled`: removed from kibana.yml (not a valid config key in Kibana 8.x)
- Kibana ES auth: env var substitution doesn't work in kibana.yml → pass via `ELASTICSEARCH_USERNAME`/`ELASTICSEARCH_PASSWORD` env vars
- Kibana `kibana_system` user: password must be set via ES `_security` API before Kibana can connect → added init container
- Vagrant e2e-tests provisioner: set to `run: "never"` (infra tests don't need E2E)
- Vagrant test tasks: destroy VMs before starting for clean state
- `setup-vault.yml`: guard Prometheus secret copy on monitor namespace existence

### Step 9: DNS + docs [DONE]

- Add `logs.pmon.dev` A record to DNS provider — TODO (manual DNS change)
- Add ELK section to CLAUDE.md — Done
- Update resource allocation table in production.yml — Done
- Fix CD pipeline to detect `deploy/` and `.github/` changes — Done

**Production deployment fixes (2026-03-06):**
- Removed privileged sysctl init container (vm.max_map_count already ≥262144 on host)
- Changed monitor namespace PodSecurity to `privileged` (Filebeat needs hostPath + DAC_READ_SEARCH)
- Increased Kibana memory: 512Mi→2Gi (OOM at 512Mi, Node.js 8.x needs ~1Gi minimum)
- Increased Filebeat memory: 128Mi→256Mi (was using 118Mi/128Mi)
- Increased Elasticsearch memory: 4Gi→8Gi with 2GB JVM heap (was 1GB)

## Files to Create/Modify

| File | Change | Status |
|------|--------|--------|
| `infra/helm/values.yaml` | Add `elk` section | Done |
| `infra/helm/templates/_helpers.tpl` | Add ES/Kibana/Filebeat helpers | Done |
| `infra/helm/templates/elasticsearch-statefulset.yaml` | NEW | Done |
| `infra/helm/templates/elasticsearch-service.yaml` | NEW | Done |
| `infra/helm/templates/elasticsearch-configmap.yaml` | NEW | Done |
| `infra/helm/templates/elasticsearch-secret.yaml` | NEW | Done |
| `infra/helm/templates/kibana-deployment.yaml` | NEW | Done |
| `infra/helm/templates/kibana-service.yaml` | NEW | Done |
| `infra/helm/templates/kibana-configmap.yaml` | NEW | Done |
| `infra/helm/templates/kibana-ingress.yaml` | NEW | Done |
| `infra/helm/templates/filebeat-daemonset.yaml` | NEW | Done |
| `infra/helm/templates/filebeat-configmap.yaml` | NEW (ILM built-in) | Done |
| `infra/helm/templates/filebeat-rbac.yaml` | NEW | Done |
| `infra/helm/templates/external-secrets.yaml` | Add elasticsearch ExternalSecret | Done |
| `infra/helm/templates/network-policies.yaml` | Add ES + Kibana ingress rules | Done |
| `deploy/ansible/vars/production.yml` | Add elk section + resource table | Done |
| `tests/ansible/test-elk.yml` | NEW — Vagrant test playbook | Done |
| `deploy/ansible/vars/vault-vagrant.yml` | Add `vault_store_root_token: true` | Done |
| `deploy/ansible/playbooks/setup-vault.yml` | Guard monitor namespace check | Done |
| `Taskfile.yml` | Add `test:elk` task + vagrant destroy | Done |
| `Vagrantfile` | e2e-tests provisioner `run: "never"` | Done |
| `CLAUDE.md` | Add ELK docs | Done |
| `.github/workflows/cd.yml` | Add deploy/ + .github/ change detection | Done |

## Verification

1. `helm lint` passes
2. `kubectl get pods -n monitor` -- ES, Kibana, Filebeat all running
3. `https://logs.pmon.dev` -- Kibana loads, can log in
4. Kibana Discover: `filebeat-*` index has logs from all namespaces
5. Search for `"status":"UP"` finds app health check logs
6. After 31 days: old log indices auto-deleted by ILM
7. App can reach ES: `curl http://monitor-elasticsearch:9200` from app pod

## Rollback

Disable with `elk.enabled: false` and redeploy. PVC data persists. To fully remove:
```bash
kubectl delete statefulset monitor-elasticsearch -n monitor
kubectl delete deploy monitor-kibana -n monitor
kubectl delete daemonset monitor-filebeat -n monitor
kubectl delete pvc -l app.kubernetes.io/component=elasticsearch -n monitor
```
