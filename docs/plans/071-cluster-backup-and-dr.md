# Plan 071: Cluster-wide backup + disaster recovery

## Status: DRAFT (2026-05-10)

## Context

We just learned the hard way (Plan-of-yesterday MinIO incident) that backups need
attention beyond "Velero is set up and runs daily." This plan audits **everything
the cluster has state for** and decides, per-source, whether the current backup
posture is adequate, what's missing, and what the recovery path looks like.

The conversation that triggered this:
- Velero's BackupStorageLocation went `Unavailable` because MinIO's bucket
  disappeared on a topology change. 24h of `kopia-maintain` jobs failed silently.
  Discovery was reactive — only because we noticed red pods.
- That kicked off "wait, what else are we silently failing to back up?"

This plan is the audit + remediation roadmap.

---

## Current state inventory

| Source | Where state lives | Backup mechanism today | Off-host? | Off-cluster? |
|---|---|---|---|---|
| **k8s control plane (etcd)** | ten:/var/lib/etcd/ | None — only static-pod auto-snap in same dir | ❌ | ❌ |
| **k8s objects (CRDs, deploys, secrets, configmaps)** | etcd | Velero `velero-full-weekly` schedule, all namespaces, 720h TTL | ✅ Pi MinIO | ❌ |
| **PVC contents** (25 PVCs, ~250 GB) | ten:/mnt/storage/local-path | Velero kopia uploader (daily for `schnappy-production`, weekly full) | ✅ Pi MinIO | ❌ |
| **Forgejo Postgres DB** | Patroni cluster on Pis | Patroni streaming replication only (pi1↔pi2) | ✅ replicated | ❌ |
| **Forgejo git repos** | Gluster `forgejo-repos` (3-arbiter: pi1+pi2+ten) | Gluster replication only | ✅ replicated | ❌ |
| **Forgejo packages/attachments/avatars** | Gluster `forgejo-data` (3-arbiter, new yesterday) | Gluster replication only | ✅ replicated | ❌ |
| **Container registry blobs** (the 31 GB packages dir) | inside `forgejo-data` above | Gluster replication only | ✅ replicated | ❌ |
| **Keycloak realm config + users** | same Patroni Postgres | Same: Patroni replication only | ✅ replicated | ❌ |
| **Vault transit/auth state** | pi1's local `/var/lib/vault/data/` | Daily tar of data dir → `/var/backups/vault/` (pi1 LOCAL) | ❌ | ❌ |
| **Consul KV (Vault backend + service registry)** | Consul Raft cluster (pi1+pi2+ten) | Raft replication only — no scheduled snapshots | ✅ replicated | ❌ |
| **MinIO buckets** (velero, pg-dump, postgres-backups, scylla-backups) | Gluster `backup-minio` | Gluster replication only | ✅ replicated | ❌ |
| **Nexus blobs + H2 DB** | Gluster `nexus-data` | Gluster replication only | ✅ replicated | ❌ |
| **ScyllaDB (production)** | StatefulSet PVC on ten | scylla-manager `daily-backup` + `weekly-repair` task | ?  must verify destination | ❌ |
| **ten host config** (`/etc/kubernetes`, `/etc/cni`, manifests) | ten root fs | Bare-metal install scripts in repo (re-runnable) | code in git | ✅ via git |
| **Pi host config** (Patroni, PgBouncer, HAProxy, Caddy, keepalived, fstab, etc.) | Pi root fs | Ansible playbooks in repo (re-runnable) | code in git | ✅ via git |

**Holes that a single-Pi or single-NVMe failure would expose right now:**

| Failure scenario | Recovery story | RPO | RTO | Acceptable? |
|---|---|---|---|---|
| pi1 NVMe dies | Re-image pi1, re-run Ansible playbooks, Gluster + Patroni heal | 0 (replica still on pi2) | ~2 h | ✅ |
| pi2 NVMe dies | Same, mirror image | 0 | ~2 h | ✅ |
| **ten NVMe dies** | Re-image ten, kubeadm init, restore Velero backup | up to 24 h (last daily) | ~6–8 h | ⚠️ |
| **Both Pis die simultaneously** (theft, fire, switch frying both) | No recovery — Vault data, all Pi DBs, Gluster bricks all gone | total loss | total loss | ❌ |
| ten + 1 Pi die | k8s restorable from Velero on Pi MinIO; some PVC data loss for whatever ran on the dead Pi | up to 24 h | ~8 h | ⚠️ |
| Logical corruption (someone wipes Forgejo DB; ransomware-style PVC mass-delete) | Patroni replicates the corruption. Velero backup might be from before — check ttl. | 24h–7d | hours | ⚠️ |
| Whole homelab loss (extended outage, theft, fire) | Nothing off-site → start over from scratch + git | total loss | days | ❌ |

The two ❌ rows are this plan's reason to exist.

---

## Goals

Frame in terms of three independent failure scenarios, each with its own RPO/RTO budget:

### Scenario A: Single-host failure (ten OR one Pi)

- **RPO target:** 0 (current Pi state) / 24 h (current ten state)
- **RTO target:** 4 h end-to-end
- **Status today:** ✅ Pi side. ⚠️ ten side because etcd is local only.
- **Action:** add etcd snapshot pipeline shipping to Pi MinIO.

### Scenario B: Whole-cluster failure (homelab fire/theft/extended power)

- **RPO target:** 7 d (acceptable for homelab — full restore = catastrophe-level, can lose a week)
- **RTO target:** 48 h (re-acquire hardware + reinstall + restore)
- **Status today:** ❌. No off-site replication of anything.
- **Action:** weekly off-site export of the critical-state subset. Define what's
  critical vs. what's regenerable.

### Scenario C: Logical corruption (bad migration, ransomware, fat-finger)

- **RPO target:** 24 h
- **RTO target:** 4 h
- **Status today:** ⚠️ for Postgres (Patroni replicates corruption; only a Velero-snapshot of the PVC saves us). Acceptable for k8s objects (Velero TTLs are 168h–720h). ❌ for Vault data (the daily tarball captures only the unseal data, not the actual KV).
- **Action:** logical Postgres dumps (separate from Patroni replication), Vault `vault operator raft snapshot save`.

---

## Critical-state subset (the things we MUST keep)

If everything else is gone but we have these, we can rebuild. Total expected
size: ~50 GB compressed.

| Asset | Size | Why critical |
|---|---|---|
| **Vault Raft snapshot** | ~50 MB | Without it: re-issue every secret, every cert. KMS keys gone. |
| **Forgejo + Keycloak Postgres dumps** | ~500 MB | Without it: lose user accounts, repo metadata, OAuth tokens. Repos themselves are pushed to from dev machines (recoverable), but the issue tracker / OAuth / user state isn't. |
| **Forgejo container registry blobs** | ~31 GB | Without it: rebuild every container image from source. Days of CI. |
| **Keycloak realm export (JSON)** | ~2 MB | Easier than restoring from PG. Same data, different format. |
| **etcd snapshot (k8s)** | ~50 MB | Faster k8s recovery than re-applying every CRD via Argo. |
| **Repo manifests** (ops, infra, monitor, chat, …) | ~200 MB git | Already off-site in dev machine clones, but a homelab-managed mirror is belt-and-suspenders. |
| **Mimir TSDB** (1 month metrics) | ~5 GB | Nice to have for incident review; not critical. |

Excluded deliberately (regenerable):
- Container *cache* layers in Forgejo (`*/cache` repos) — re-pulled
- ScyllaDB data — schnappy-production rebuilds the cache from upstream
- Prometheus scrape data — short-term, can be lost
- Nexus cache — proxy cache, re-pulled

---

## Proposed architecture

### Tier 1: Pi-MinIO-resident backups (already partly there)

Hot tier. Things every other backup tier depends on.

| Backup | Source | Schedule | Destination | Retention |
|---|---|---|---|---|
| Velero full | k8s objects + all PVCs | weekly Sun 03:00 | Pi MinIO `velero/` | 720 h (30 d) |
| Velero schnappy-prod | schnappy-production ns | daily 02:00 | Pi MinIO `velero/` | 168 h (7 d) |
| **etcd snapshot** *(NEW)* | ten `/var/lib/etcd/` | hourly | Pi MinIO `etcd-snapshots/` | 168 h (7 d) |
| **Vault Raft snapshot** *(NEW: replace tar)* | pi1 vault data | daily 02:00 | Pi MinIO `vault-snapshots/` | 30 d |
| **Postgres logical dumps** *(NEW)* | Patroni leader, all DBs | daily 02:30 | Pi MinIO `pg-dump/` (already exists) | 30 d |
| **Keycloak realm exports** *(NEW)* | KC API → JSON | daily 02:30 | Pi MinIO `pg-dump/keycloak-realms/` | 30 d |
| **Consul Raft snapshot** *(NEW)* | Pi consul leader | daily 02:00 | Pi MinIO `consul-snapshots/` | 30 d |

### Tier 2: Off-site replication (NEW)

Cold tier. Weekly export to *something not in the homelab.*

Three sub-options, ranked by effort:

**Option 2a (lowest effort, recommended start):** rclone weekly mirror of selected
buckets to a personal cloud bucket (Backblaze B2 ~$1/mo for 100 GB, or AWS S3
Glacier for the same price tier).

```
Weekly cron on pi1:
  rclone sync minio:velero b2:homelab-velero --max-age 7d
  rclone sync minio:vault-snapshots b2:homelab-vault
  rclone sync minio:pg-dump b2:homelab-pg
  rclone sync minio:etcd-snapshots b2:homelab-etcd
  rclone sync forgejo-data:packages b2:homelab-forgejo-packages  # 31 GB
```

Estimated egress: ~40 GB/week initially, then deltas (~5 GB/week steady state).

**Option 2b:** USB drive rotation. Plug an encrypted USB drive into pi1 weekly,
`rsync` the same buckets, eject. Two drives in rotation. One stays off-site
(at the office / parents' place / fireproof box). Zero monthly cost, requires
manual swap.

**Option 2c:** Friend's homelab via Tailscale + reverse rclone. Higher setup
cost, free recurring, depends on relationship reliability.

### Tier 3: Application-level snapshots (NEW)

These are sources truth-of-record at the *application* level, NOT just file dumps.
They're robust against logical corruption that file-level backups would also capture.

| Source | Tool | Output | Why beyond Velero |
|---|---|---|---|
| Forgejo | `forgejo dump` | tar with DB SQL + repo bundle + LFS | Has its own internal-consistency guarantee that a PVC snapshot doesn't (transaction in flight at snap time = corrupted DB) |
| Postgres | `pg_dump --format=custom` per DB | binary dumps | Same reason; `pg_dump` is logically consistent per-DB at one point in time |
| Keycloak | KC export realm | JSON realm file | Format readable by any KC version; survives major-version upgrades that PG dumps might not |
| ScyllaDB | scylla-manager (already running) | snapshots in S3-style backend | Verify destination is Pi MinIO (currently unclear — see below) |

### Tier 4: Repository / GitOps state (already in place)

Everything declarative is already in git: `ops`, `infra`, helm charts, k8s
manifests, ansible playbooks. This is the *source* the cluster gets rebuilt
from. Off-site automatically because dev machines have clones + Forgejo
mirrors to upstream.

---

## What needs to be built

### 071-A: etcd snapshots → MinIO (~2 h work)

```yaml
# /etc/cron.hourly/etcd-snapshot on ten
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-$(date +%Y%m%d-%H%M).db

# upload via mc or aws-cli to minio:etcd-snapshots/
mc cp /tmp/etcd-*.db prod-minio/etcd-snapshots/
```

Or as a CronJob in `kube-system` ns, with mounted etcd certs and an mc image.

### 071-B: Replace tar-of-vault-data with vault-native snapshot (~1 h)

Current `vault-backup.sh` tarballs `/var/lib/vault/data/`. That's the
filesystem state of the *unseal* Vault, which is small. But for the *cluster*
Vault (in k8s), the right approach is `vault operator raft snapshot save`.

Actually — wait, do we have a separate cluster Vault, or is the pi-side Vault
the only one? Need to verify before writing this. Either way:

```bash
# pi1 daily at 02:00 (replaces existing /etc/cron.d/vault-backup):
VAULT_TOKEN=... vault operator raft snapshot save /tmp/vault-snap.db
mc cp /tmp/vault-snap.db local/vault-snapshots/vault-$(date +%Y%m%d).db
```

The current tar IS technically a "backup" (24 KB compressed!) but not what
you'd actually restore from in an emergency. Vault's official snapshot path
is mandatory for proper restore.

### 071-C: Postgres logical dumps (~2 h)

```bash
# pi1 (or whichever holds Patroni leader, query via /primary REST) daily 02:30:
for db in forgejo keycloak; do
  PGPASSWORD=$PG_ADMIN_PW pg_dump -h 127.0.0.1 -p 6432 -U postgres \
    --format=custom --no-owner --no-privileges \
    --file /tmp/${db}-$(date +%Y%m%d).pgdump $db
done
mc cp /tmp/*.pgdump local/pg-dump/
```

Should run as a systemd timer with retry; embed in a new playbook
`setup-pg-dump.yml` or fold into `setup-pgbouncer.yml` (it's where the DB
state lives).

### 071-D: Keycloak realm export (~1 h)

```bash
# Daily 02:30, on pi1:
curl -X GET https://keycloak.pmon.dev/admin/realms/schnappy/export \
  -H "Authorization: Bearer $KC_ADMIN_TOKEN" \
  > /tmp/kc-realm-$(date +%Y%m%d).json
mc cp /tmp/kc-realm-*.json local/pg-dump/keycloak-realms/
```

(Keycloak also has a `kc.sh export` CLI mode that can run inside a job pod.)

### 071-E: Consul Raft snapshot (~30 min)

```bash
# pi1 daily 02:00:
consul snapshot save /tmp/consul-$(date +%Y%m%d).snap
mc cp /tmp/consul-*.snap local/consul-snapshots/
```

### 071-F: Off-site replication (Option 2a/2b decision needed)

Choose between rclone-to-cloud, USB rotation, or Tailscale-to-friend.

If 2a: provision Backblaze B2 bucket, app key, store key in Vault, write
weekly cron on pi1.

### 071-G: ScyllaDB backup destination verification

Right now `scylla-manager` has tasks defined but I haven't verified the
destination. Likely it backs up to a local PVC, which doesn't help DR.
Should target Pi MinIO `scylla-backups/` bucket (which already exists).

### 071-H: Restore-test runbook

A documented, *executed* end-to-end test. Otherwise these backups are
Schrödinger's: simultaneously alive and dead until observed.

Two scenarios to walk through and document:
1. **Wipe ten and rebuild.** Reinstall Debian, run kubeadm bootstrap, `velero
   restore` from latest backup, verify all apps come up. Time-box: 1 day.
   Run this annually, or after any major change to the cluster topology.
2. **Drop forgejo DB and restore from pg_dump.** Verify all repos browse,
   webhook deliveries resume, OAuth still works. Time-box: 2 hours.
   Run this quarterly.

Each test gets a new sub-plan documenting outcome + lessons + diff
between expected and actual restore. The fact that we don't have one is
an active risk.

---

## Sequencing

Suggested order, easiest → hardest:

1. **071-E** Consul snapshot (30 min, low risk, immediately useful)
2. **071-C** Postgres logical dumps (2 h, addresses the highest-value gap)
3. **071-D** Keycloak realm export (1 h, complementary to C)
4. **071-A** etcd snapshots (2 h, addresses the ten-only-NVMe gap)
5. **071-B** Vault Raft snapshot (1 h, replaces an existing-but-wrong backup)
6. **071-G** ScyllaDB destination check (30 min audit, fix if wrong)
7. **071-F** Off-site replication (full day; requires choosing 2a/2b/2c)
8. **071-H** Restore-test exercise (full day, only after 1–7)

Total estimated: ~3 days of focused work, spread over a couple of weeks.

---

## What this plan does NOT cover

- **Application-level Mimir long-term TSDB backup.** Mimir already targets
  S3-compatible storage. If we move Mimir's bucket to Pi MinIO (it might
  already be there — check), it ride-alongs into 071-F off-site.
- **Backup *encryption* at rest.** Pi MinIO is unencrypted. For homelab
  that's mostly fine; for off-site (071-F) it's mandatory — rclone can do
  client-side encryption (`crypt` remote).
- **Backup *integrity verification* (anti-bitrot).** Kopia does this for
  Velero; pg_dump checksums itself. Vault snapshots are SHA-validated on
  restore. Acceptable.
- **Multi-region failover** of the homelab. Out of scope; not a SaaS.

---

## Decisions needed before starting

1. **Off-site choice (2a/2b/2c)** — affects whether 071-F is 2 h or a full day.
2. **Encryption strategy for off-site** — rclone crypt? age-encrypted tarballs? Both?
3. **Restore-test cadence** — annually for ten rebuild, quarterly for DB? Or all annual?
4. **Where to put runbook** — in this repo (`ops/docs/runbooks/`) or in the existing
   runbook ConfigMap served at `runbooks.pmon.dev`?
