# Plan 061: Observability & resilience remaining work

## Status: PARTIAL (2026-04-20)

Completed:
- **D** Reliability dashboard (Vault/ESO/ArgoCD/Velero/PublicURLs) — `9b8e18f`
- **E** Runbook URLs + 6 stub runbooks — `db0cc85` (ops) + `1327621`, `aff84e7` (platform)

Reverted:
- **B** Forgejo/Keycloak A/P — `da66835` then `0ba2f08`. Reveal during rollout:
  forgejo's pgx driver silently ignored `TARGET_SESSION_ATTRS`, so multi-host
  `HOST = pi1,pi2` connected to the replica and hit SQLSTATE 25006 whenever
  it tried to run migrations after a (re)start. Pre-existing latent bug,
  not visible in dual-active because migrations only run once per lifetime.

  Interim: forgejo `HOST` pinned to the Patroni leader (pi2) only.
  If Patroni fails over, re-run `task deploy:pi-services` with
  `forgejo_db_host` overridden to the new leader.

  **Proper fix (new sub-plan C2)**: put a pgBouncer or pg-auto-failover
  instance in front of Patroni that routes to leader by default. Or run a
  second keepalived VRRP that follows the Patroni leader (separate VIP for
  DB writes) and point forgejo at that VIP. Until that lands, A/P is blocked.

Still TODO:
- **C** Restore verification — needs dedicated session (target cluster choice, DR creds)
- **C2** Patroni-leader-aware DB routing (enables B when done)

Skipped/deferred: A (Vault KMS), F (MinIO consolidation), G (k8s HA)

## Context

Session 2026-04-19/20 restored backups (Velero + fresh distributed MinIO),
closed the monitoring blind spots (Vault, ESO, ArgoCD, Velero probes +
alerts), fixed the silent-alertmanager bug (Prometheus → AM mTLS reset),
and added public-URL/certmanager/Prometheus self-alerts. See commits
`a78974a`, `b3fdf42`, `764a67d`, `bf77e2e`, `b881240`, `2e52d1c`.

Remaining items are structural improvements that require their own
design/testing. Ordered by risk-reduction value × effort.

---

## Sub-plan B: Forgejo/Keycloak active/passive (MEDIUM VALUE)

**Why:** same architectural bug MinIO had — two processes writing to
shared Gluster (forgejo repos) or shared Patroni DB (keycloak cache).
Less catastrophic than MinIO's format.json because:
- Forgejo: git's file-level locking survives concurrent readers on the
  standby; only writes from VIP-holder touch repos
- Keycloak: all state in Patroni (single-writer). Cache incoherence is
  possible but hasn't caused visible issues.

But on a future reboot where both wake up and race, could corrupt
git-refs or cause cache drift.

**Approach:**
Same pattern as the MinIO fix would have been: keepalived notify scripts
start/stop the services based on VIP ownership. Fixed unseal script bug
first (done — commit `a78974a`).

1. Add `notify_master` / `notify_backup` scripts in setup-keepalived.yml
2. Use them to toggle `forgejo.service` and `keycloak.service`
3. Update ansible to set `state: stopped, enabled: true` for these units
4. Keep `check_services.sh` probing localhost forgejo/keycloak so
   failure flips the VIP

**Files:** `deploy/ansible/playbooks/setup-keepalived.yml`,
`deploy/ansible/playbooks/setup-pi-services.yml`.

**Risk:** 10–15s downtime on VIP failover (service startup time). Keycloak
session caches would need to be re-warmed. Users may see re-auth prompts.

**Effort:** 1 day.

---

## Sub-plan C: Scheduled restore verification (MEDIUM VALUE)

**Why:** `task deploy:restore:verify` exists but is never run. We have no
standing evidence backups are restorable. Today's manual backup succeeded
in writing, but we never tested reading.

**Approach:**
1. CronJob in cluster that once per week:
   - Triggers a fresh Velero backup of a test namespace with known
     seeded data
   - Bootstraps a kind/k3d/Vagrant-equivalent ephemeral cluster
   - Restores the backup there
   - Runs k6 smoke to verify app comes up
   - Reports success as a Prometheus metric: `restore_verify_success`
2. Alert rule: `RestoreVerificationFailing` — no success in 8 days.

**Complications:**
- In-cluster CronJob can't easily spin up another cluster. Options:
  - Use a Hetzner/DO instance provisioned on demand (Terraform)
  - Run against Vagrant on a self-hosted Woodpecker runner (simplest)
- Need to store Vault creds somewhere the restore can reach (ESO can't
  help if restoring to a separate cluster)

**Files:** new `ops/tests/restore-verify/` harness,
`.woodpecker/weekly-restore-verify.yaml`,
`platform/helm/schnappy-observability/templates/prometheus-rules.yaml`.

**Effort:** 2-3 days.

---

## Sub-plan D: Grafana dashboards for new metrics (LOW VALUE / QoL)

**Why:** `vault_core_unsealed`, `externalsecret_status_condition`,
`argocd_app_info`, `velero_backup_*`, `probe_*` are all collected but
unvisualized. During an incident, the metrics are only accessible via
raw PromQL.

**Approach:** dashboards-as-code JSON in the observability chart,
auto-provisioned by grafana-dashboard-provider.

Dashboards to build:
1. **Vault & ESO** — seal state, unseal probes, per-ClusterSecretStore
   readiness, per-ExternalSecret sync errors
2. **ArgoCD** — app health matrix, sync status, degraded-duration
3. **Velero** — BSL availability, backup age per schedule, kopia job
   success rate
4. **Public URLs** — probe success % per URL, latency, SSL days-left

**Files:** `platform/helm/schnappy-observability/templates/grafana-dashboards-configmap.yaml`
(already exists, extend).

**Effort:** 1-2 days.

---

## Sub-plan E: Runbook URLs per alert (LOW VALUE / QoL)

**Why:** during 2am page, operator reads the email, has no idea what to
do. Runbook links shorten MTTR.

**Approach:** add `annotations.runbook_url` to every alert rule pointing
at a wiki page per alertname. Pages can live in Forgejo markdown or
a static Grafana notes panel.

**Files:** all `prometheus-rules.yaml` templates (schnappy,
schnappy-data, schnappy-observability).

**Effort:** ½ day (mechanical), + content writing ongoing.

---

## Sub-plan F: Mimir/Tempo MinIO consolidation (OPTIONAL)

**Why:** three MinIOs (Pi-distributed for Velero, `schnappy-infra-minio`
for Mimir/Tempo, per-env for apps). Moving Mimir/Tempo onto Pi MinIO
removes one failure domain. Saves ~1Gi RAM + ~5Gi disk on the cluster node.

**Counter:** creates a circular dependency — observability backend
depends on Pi being up; today Pi outage leaves apps intact but loses
Vault. Adding Mimir/Tempo to Pi means Pi outage ALSO blinds us.

**Recommendation:** DO NOT DO. The current split is intentional.

---

## Sub-plan G: Single-node k8s HA (OPTIONAL, LONG-TERM)

**Why:** `ten` is a single control-plane. If it dies, every cluster
workload is gone. Plan 045 migration notes reserved this for future.

**Approach:** add 2 more control plane nodes (3-node kubeadm HA). Needs:
- 2 more similarly-specced machines (cost/hardware)
- Load balancer VIP for k8s API (keepalived + HAProxy)
- stacked etcd across 3 nodes
- Moving PVCs to a distributed backend (Longhorn, Ceph, or NFS) —
  currently `local-path` is node-pinned

**Effort:** 1 week minimum. Hardware cost.

**Recommendation:** defer until hardware investment justified.

---

## Proposed execution order

1. **C (restore verify)** — real confidence in DR posture
2. **B (Forgejo/Keycloak A/P)** — structural fragility
3. **D (dashboards)** — quality-of-life
4. **E (runbooks)** — quality-of-life

Skip F, G unless constraints change.

## Verification (across all sub-plans)

- `kubectl -n schnappy-infra get probe,podmonitor,prometheusrule` — expected resources present
- `amtool alert query` after a simulated outage returns expected alerts
- `VeleroRestoreVerificationFailing` absent for a week after C ships
- Grafana dashboards visible at `grafana.pmon.dev/d/*` after D
