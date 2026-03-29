# Plan 043: Hyperfoil Report Persistence & Web Access

## Context

Hyperfoil generates HTML reports to `/tmp/report/` inside job pods. When the pod completes, the report is lost. We want to persist reports in MinIO and serve them via a web UI at `reports.pmon.dev`.

## Architecture

```
Hyperfoil Job → mc upload → MinIO (hyperfoil-reports bucket)
                                    ↑
reports.pmon.dev → Traefik → Nginx reverse proxy → MinIO:9000
```

## Design Decisions

**Storage:** MinIO — already deployed in schnappy namespace, S3-compatible, has existing secrets via Vault+ESO.

**Upload mechanism:** Download `mc` (MinIO client) binary to `/tmp` during run.sh, upload report directory. Hyperfoil image has `curl` (used for Keycloak token) and `/tmp` is a writable emptyDir.

**Web serving:** Nginx reverse proxy deployment — small Nginx proxying to MinIO. Full control over listing page, clean separation. Alternatives considered: direct MinIO ingress with Traefik addPrefix middleware (couples to Traefik CRDs), presigned URLs only (expire, no browsable interface).

**Index page:** After each upload, run.sh generates an `index.html` listing all reports (using `mc ls`) and uploads it to the bucket root. The listing page shows report type (load/stress), timestamp, and direct links.

**Retention:** 30-day expiry via MinIO lifecycle rule (can add later).

**Bucket policy:** Anonymous read (download) — bucket contains only HTML/CSS/JS reports, no sensitive data.

## Report Structure in MinIO

```
hyperfoil-reports/
├── index.html                          ← auto-generated listing page
├── load/
│   ├── 2026-03-29_030000/
│   │   ├── index.html                  ← Hyperfoil HTML report
│   │   └── ... (CSS, JS, data files)
│   └── 2026-03-28_030000/
│       └── ...
└── stress/
    ├── 2026-03-29_120000/
    │   └── ...
    └── ...
```

URLs: `https://reports.pmon.dev/load/2026-03-29_030000/index.html`

## Changes

### Phase 1: Report Upload (run.sh modifications)

Modify both `hyperfoil-load-configmap.yaml` and `hyperfoil-stress-configmap.yaml` run.sh scripts:

1. Download `mc` binary to `/tmp/mc` (from MinIO's CDN, ~25MB)
2. Configure alias: `mc alias set minio http://schnappy-minio:9000 $MINIO_USER $MINIO_PASSWORD`
3. Create bucket if not exists: `mc mb --ignore-existing minio/hyperfoil-reports`
4. Set anonymous read policy: `mc anonymous set download minio/hyperfoil-reports`
5. Upload report directory after benchmark completes
6. Generate and upload `index.html` listing all reports

### Phase 2: Cronjob/Job Template Changes

Modify `hyperfoil-load-cronjob.yaml` and `hyperfoil-stress-job.yaml`:
- Add MinIO credentials as env vars from `schnappy-minio` secret (cross-chart, same namespace):
  ```yaml
  - name: MINIO_USER
    valueFrom:
      secretKeyRef:
        name: schnappy-minio
        key: MINIO_ROOT_USER
  - name: MINIO_PASSWORD
    valueFrom:
      secretKeyRef:
        name: schnappy-minio
        key: MINIO_ROOT_PASSWORD
  ```

### Phase 3: Nginx Report Server

**Chart:** `schnappy-observability` (alongside Grafana/Kibana — observability tooling)

**New files:**
| File | Purpose |
|------|---------|
| `reports-deployment.yaml` | Nginx container proxying to MinIO |
| `reports-service.yaml` | ClusterIP on port 8080 |
| `reports-configmap.yaml` | Nginx config with `proxy_pass` to MinIO |
| `reports-ingress.yaml` | `reports.pmon.dev` with DNS-01 TLS |

**Nginx config:**
```nginx
server {
    listen 8080;
    location / {
        proxy_pass http://schnappy-minio:9000/hyperfoil-reports/;
        proxy_set_header Host schnappy-minio;
    }
}
```

**Resources:** Minimal — `requests: {cpu: 10m, memory: 16Mi}`, `limits: {cpu: 100m, memory: 32Mi}`
**Security:** Non-root, readOnlyRootFilesystem, drop ALL caps.

### Phase 4: Network Policies

**schnappy chart (network-policies.yaml):**
- Add: Hyperfoil load/stress → MinIO egress (TCP 9000)

**schnappy-data chart (network-policies.yaml):**
- Add: MinIO ingress from Hyperfoil pods (component: hyperfoil-load, hyperfoil-stress)
- Add: MinIO ingress from reports-server pods (component: reports)

**schnappy-observability chart (network-policies.yaml):**
- Add: Reports server NP — ingress from Traefik (kube-system), egress to MinIO (TCP 9000) + DNS

### Phase 5: Values & Production Config

**schnappy-observability/values.yaml:**
```yaml
reports:
  enabled: false
  image: nginx:1.28-alpine
  ingress:
    host: reports.local
    tls:
      enabled: false
      clusterIssuer: letsencrypt-dns
      secretName: ""
```

**Production values** (`clusters/production/schnappy-observability/values.yaml`):
```yaml
reports:
  enabled: true
  ingress:
    host: reports.pmon.dev
    tls:
      enabled: true
      clusterIssuer: letsencrypt-dns
      secretName: reports-pmon-dev-tls
```

### Phase 6: DNS

Add `reports.pmon.dev` → 192.168.11.2 in Unbound config on router (same as grafana.pmon.dev, logs.pmon.dev).

### Phase 7: Vagrant Test

**New file:** `tests/ansible/test-hyperfoil-reports.yml`
**Taskfile entry:** `test:hyperfoil-reports`

Test verifies end-to-end: Hyperfoil job runs → report uploaded to MinIO → Nginx serves report via HTTP.

**Test phases:**

1. **Seed secrets** — postgres, redis, minio, keycloak (k6-smoke client) into Vault KV
2. **Deploy charts:**
   - `schnappy-data` with postgres, redis, minio enabled (kafka/scylla/aptCache disabled)
   - `schnappy-auth` with Keycloak (for Hyperfoil token acquisition)
   - `schnappy-observability` with reports enabled (grafana/elk/alertmanager/victoriametrics disabled)
   - `schnappy` core app with monitor + hyperfoil enabled (site/admin/chat/chess/gateway disabled)
3. **Wait for rollouts** — postgres, redis, minio, keycloak, monitor, reports server
4. **Keycloak setup** — create realm, `k6-smoke` client, service account user with roles (via REST API, same pattern as test-keycloak.yml)
5. **Run Hyperfoil load test** — `kubectl create job hf-test --from=cronjob/schnappy-hyperfoil-load`
6. **Wait for job completion** — `kubectl wait --for=condition=complete job/hf-test --timeout=300s`
7. **Verify MinIO upload:**
   - Exec into MinIO pod or use `mc` to check `hyperfoil-reports/load/` exists
   - Verify report `index.html` exists in report subdirectory
   - Verify root `index.html` (listing page) exists
8. **Verify Nginx serving:**
   - curl reports service: `kubectl exec ... -- curl http://schnappy-reports:8080/`
   - Verify HTTP 200 and HTML content returned
   - curl a report path: verify actual report content is served
9. **Verify network policies** (NPs enabled):
   - `kubectl get networkpolicy schnappy-reports -n schnappy -o name` — reports NP exists
   - Verify MinIO NP updated with Hyperfoil ingress rules
10. **Summary** — aggregate pass/fail, same format as other tests

**Test values (minimal resources for Vagrant):**
```yaml
# schnappy-data
postgres: { enabled: true, existingSecret: schnappy-postgres }
redis: { enabled: true, existingSecret: schnappy-redis }
minio: { enabled: true, existingSecret: schnappy-minio, storage: { size: 1Gi, storageClass: local-path } }
kafka: { enabled: false }
scylla: { enabled: false }
aptCache: { enabled: false }
networkPolicies: { enabled: true }

# schnappy-observability
reports: { enabled: true }
victoriametrics: { enabled: false }
grafana: { enabled: false }
elk: { enabled: false }
alertmanager: { enabled: false }
kubeStateMetrics: { enabled: false }
networkPolicies: { enabled: true }

# schnappy (core)
app: { replicas: 1 }
hyperfoil: { enabled: true }
smokeTest: { clientSecretName: schnappy-k6-smoke }
site: { enabled: false }
admin: { enabled: false }
chatService: { enabled: false }
chessService: { enabled: false }
gateway: { enabled: false }
networkPolicies: { enabled: true }
```

**Taskfile entry** (same pattern as other tests):
```yaml
test:hyperfoil-reports:
  desc: Test Hyperfoil report persistence + Nginx serving in Vagrant
  deps: [deploy:install]
  cmds:
    - cmd: vagrant destroy -f 2>/dev/null; true
    - cmd: vagrant up
    - defer: vagrant halt
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault-pi.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml
    - cmd: cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml ../../tests/ansible/test-hyperfoil-reports.yml -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml
```

## Verification

1. `task test:hyperfoil-reports` passes in Vagrant
2. Run load test in production: `kubectl create job hf-load --from=cronjob/schnappy-hyperfoil-load -n schnappy`
3. Check MinIO: report uploaded
4. Browse `https://reports.pmon.dev/` → listing page with links
5. Click report → full Hyperfoil HTML report
