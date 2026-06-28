# Plan 076 — Remove legacy "minio" terminology from the Pi versitygw backup store

## 1. Context & goal

On 2026-06-27 the schnappy Pi backup object store was migrated from MinIO to **versitygw** (a stateless S3 gateway serving a POSIX backend over GlusterFS, behind the keepalived VIP `192.168.11.5:9000`). The store is verified healthy: Velero, the hourly etcd-backup CronJob, CNPG barman, and the ScyllaDB Manager agent all back up successfully through the VIP. The **binary, the service unit, the IAM dir, the env file, and the on-disk format are all versitygw now** — but the surrounding identifiers still carry the legacy `minio` name: Vault property/path names, k8s secret names + data-key names, env-var names, ansible vars, the linux user/group, the GlusterFS volume, and the data-dir mount path. This plan removes that terminology.

**Non-negotiable constraint.** ZERO backup-creds-break window. Every one of the four consumers — **velero, etcd-backup, CNPG, scylla** — keeps backing up throughout, and the migration is **fully reversible at every stage**. This is achieved by an **additive-first** discipline: introduce the new identifier *alongside* the old, force the consumer to re-read it, verify a *real* backup against the new identifier, and only then retire the old one. No consumer ever points at a name that does not yet resolve, and no destructive step runs until a fresh successful backup proves the new identifier works.

**Critical disambiguation (carried into every step).** Two distinct "minio" surfaces exist:

- **IN SCOPE** — the Pi backup store now served by versitygw (this plan).
- **OUT OF SCOPE** — the separate in-cluster app-data MinIO StatefulSet `schnappy-production-minio` (buckets `email-attachments` / `postgres-backups`), the `schnappy-infra-minio` Mimir/observability backend, and all `schnappy-test-minio` / `schnappy-shared-minio` / `schnappy/preview-minio` replicas. These keep their MinIO naming and are **never touched**.

The two surfaces share substrings, so collisions are a real hazard:

| in scope (rename) | out of scope (leave) |
|---|---|
| secret `schnappy-production-minio`**`-backup`** | secret `schnappy-production-minio` |
| Vault `secret/data/schnappy/minio`**`-backup`** | Vault `secret/data/schnappy/minio` |
| env `VELERO_MINIO_*` | env `MINIO_ROOT_*` |

**Every rename must anchor on the exact in-scope reference (the table in §2), never a loose `git grep minio | sed`.**

## 2. Complete surface inventory

### 2a. Vault keys (property names inside a secret)

| ref | location | consumers | rename risk |
|---|---|---|---|
| `minio_access_key` / `minio_secret_key` (properties on `secret/data/schnappy/velero`) | written `ops:deploy/ansible/playbooks/seed-vault-secrets.yml:335-336`; read via `remoteRef.property` in `infra:clusters/production/cluster-config/velero-secrets.yaml:26,30` + `etcd-backup.yaml:43,47` | ExternalSecret `velero/velero-credentials-es`, ExternalSecret `kube-system/etcd-backup-minio` | medium — live Vault property rewrite; **NOTE** the seed play overwrites the whole secret (§5 defect handling), so this is sequenced via the seed play, not a bare `kv patch` |

### 2b. Vault paths

| ref | location | consumers | rename risk |
|---|---|---|---|
| `secret/data/schnappy/minio-backup` (props `access_key`/`secret_key`) | written `ops:seed-vault-secrets.yml:263-271`; read via `{{ .Values.vault.secretPathPrefix }}/minio-backup` in `platform:helm/schnappy-data/templates/cnpg-secret.yaml:71,75` + `scylla-agent-secret.yaml:28,32` | ExternalSecret `schnappy-production-minio-backup` (CNPG barman), ExternalSecret `scylla-agent-config-secret` (Scylla Manager) | medium — live Vault path move (seed-play driven) + two chart repoints |
| `secret/data/schnappy/velero` (PATH itself) | as 2a | velero + etcd-backup ExternalSecrets | none — path is clean; only its property names are legacy (2a) |

### 2c. k8s secret names (ExternalSecret + target Secret)

| ref | location | consumers | rename risk |
|---|---|---|---|
| `etcd-backup-minio` | `infra:etcd-backup.yaml:30,38` (ES name + target.name), referenced `:155-156` (secretKeyRef) | CronJob `kube-system/etcd-backup` | medium — live k8s secret recreate via Argo |
| `schnappy-production-minio-backup` | `infra:clusters/production/schnappy-production-data/values.yaml:149` (`cnpg.backupSecret`); rendered `platform:cnpg-secret.yaml:58,67`; consumed `platform:cnpg-cluster.yaml:85,88,137,140`; RBAC `cnpg-rbac.yaml:12` | CNPG Cluster `schnappy-production-postgres` barman s3Credentials | medium — cross-repo recreate; CNPG rolls on ref change |
| `velero-credentials-es` | `infra:velero-secrets.yaml:6` (ES name; target `velero-credentials`) | downstream `velero-credentials` | low — `-es` is generic; **leave as-is** (no `minio` token) |
| `velero-credentials` | `infra:velero-secrets.yaml:14`; `infra:clusters/production/velero/values.yaml:9` | Velero Deployment + node-agent DaemonSet | none — already clean (chain completeness) |
| `scylla-agent-config-secret` | `platform:scylla-agent-secret.yaml:6,15` | ScyllaDB Manager Agent (operator looks it up **by name**) | **do not rename** — Scylla-Operator convention; only its Vault source is in scope |

### 2d. k8s secret keys (data-key names inside a secret)

| ref | location | consumers | rename risk |
|---|---|---|---|
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` (keys on `schnappy-production-minio-backup`) | producer `platform:cnpg-secret.yaml:69,73`; consumer `platform:cnpg-cluster.yaml:86,89` (recovery `externalClusters`) **and** `:138,141` (`backup:` block) | CNPG barman `s3Credentials` in BOTH blocks | medium — producer + both consumer blocks must change in one atomic Helm release |
| `ACCESS_KEY` / `SECRET_KEY` (keys on `etcd-backup-minio`) | `infra:etcd-backup.yaml:155-156` | CronJob env | none — already clean |

### 2e. env vars (names only — values never read)

| ref | location | consumers | rename risk |
|---|---|---|---|
| `VELERO_MINIO_ACCESS_KEY` / `VELERO_MINIO_SECRET_KEY` | `ops:inventory/production.yml:31-32`; validation loop `seed-vault-secrets.yml:161-162` (loop spans `:155-186`, also contains out-of-scope `MINIO_ROOT_*` at `:159-160`); seeds `:270-271,:335-336`; `Taskfile.yml:324-325` (seed-test) + `:670-671` (seed-secrets); `setup-velero.yml:8` (doc); operator `.env` on localhost `/home/sm/src/ops/.env`; `CLAUDE.md` | feed inventory `minio_root_*` → versitygw root key + both Vault paths + the live `setup-velero.yml` derivation | medium — rename across inventory + seed play + both Taskfile blocks + localhost `.env` + `setup-velero.yml` together; value-identity is load-bearing (see §5 Stage 6) |

### 2f. ansible vars

| ref | location | consumers | rename risk |
|---|---|---|---|
| `minio_root_user` / `minio_root_password` | `ops:inventory/production.yml:31-32`; `ops:inventory/vagrant.yml:38-39`; `ops:tasks/versitygw.yml:17-18,76-77`; derived `ops:setup-velero.yml:24-25` (`velero_minio_access_key`/`secret_key`) | versitygw `/etc/versitygw/env` `ROOT_ACCESS_KEY`/`ROOT_SECRET_KEY`; live `setup-velero.yml` | low — pure var rename, no live state; all files in one commit |
| `backup_volumes` row `{ name: backup-minio, mount: /var/lib/minio/data, stop_service: minio, autostart: false }` | `ops:setup-gluster.yml:554` | Stop/Start service tasks `:560-566,612-617`; mount task | medium — **STALE BUG**; behavioral, not cosmetic (see §5 Stage 7 / defect note). Volume name + mount path embedded here are high-risk anchors (Tier 2) |
| `minio_data: true/false` (per-volume flag) | `ops:setup-gluster.yml:366,371,376,388` | **NONE** — never read in any `when:` across `deploy/` | low — dead key; drop, don't rename |
| `velero_backup_path: /mnt/backups/minio` + in-cluster `minio-backup` Deployment + `minio_image` | `ops:setup-velero.yml:22,24-26,67-249,395-408` | **LIVE** — `Taskfile.yml:724-729` `deploy:velero` runs this playbook | low (rename) — **NOT dead**; see §5 Stage 6. Rename its `VELERO_MINIO_*`/`velero_minio_*` refs in lockstep; do **not** delete the section as part of this rename |
| `minio_root_user`/`password` (vagrant) | `ops:inventory/vagrant.yml:38-39` | feeds versitygw root key in vagrant deploy (mirrors prod) | low — rename in lockstep with `production.yml` |

### 2g. linux user / group

| ref | location | consumers | rename risk |
|---|---|---|---|
| `minio` (uid 9000 / gid 9000, home `/var/lib/minio`, shell nologin) | created `ops:setup-pi-services.yml:435-451`; referenced `ops:tasks/versitygw.yml:53-54,65-66,72-73,95-96`; chown `ops:setup-gluster.yml:593-594`; live on pi1 `.4` + pi2 `.6` (`/etc/passwd`,`/etc/group`) | `versitygw.service` `User=`/`Group=`; owns `/var/lib/minio/data` (Gluster mount), `/etc/versitygw`, `/etc/versitygw/env`, `/var/lib/versitygw/iam` | **high** — uid/gid 9000 is load-bearing (no Gluster `storage.owner` enforcement on this volume; ownership rides on the `9000` numbers). Rename of the **name** keeping uid/gid 9000 avoids a recursive chown but still touches `/etc/passwd`+`/etc/group`+systemd+ansible+restart. A uid **change** orphans every file = very high (Tier 2) |

### 2h. GlusterFS volume

| ref | location | consumers | rename risk |
|---|---|---|---|
| `backup-minio` (replica-2 **+ arbiter**) | def `ops:setup-gluster.yml:362,553-554,628`; live volume — brick on pi1 `.4`, brick on pi2 `.6`, **arbiter on ten `.2`**; mount src `node_ip:/backup-minio`; `/etc/fstab` both Pis | versitygw posix backend; FUSE mount `/var/lib/minio/data`; glusterd peers on **all 3 hosts incl. the k8s node** | **high** — Gluster has **no in-place volume rename**; requires create-new-volume + data migration (or stop/recreate) + remount + fstab edits across 3 hosts, with backup-store downtime (Tier 2) |

### 2i. data paths

| ref | location | consumers | rename risk |
|---|---|---|---|
| `/var/lib/minio/data` (FUSE mountpoint) | `ops:tasks/versitygw.yml:28-30` (`vgw_gluster_mount`/`vgw_backend_dir`/`vgw_sidecar_dir` defaults), `:92` `RequiresMountsFor`; `ops:setup-gluster.yml:365,554,581-595`; live both Pis | versitygw `RequiresMountsFor` + `ExecStart` (`…/buckets`, `…/.sidecar`); fstab mount target; Gluster mountpoint; **holds every live backup object** | **high** — live mountpoint; rename = unmount/remount + fstab + unit + `vgw_*_dir` + gluster mount task atomically + restart. A path/mount mismatch serves an empty pre-mount dir, "data disappears" (Tier 2) |
| `/var/lib/gluster/backup-minio/{brick,arbiter-brick}` | on-disk bricks: pi1+pi2 `brick`, ten `arbiter-brick` | bricks of the `backup-minio` volume | **high** — actual on-disk data dirs; brick-path string embedded in glusterd metadata (Tier 2) |
| `/var/lib/minio` (minio user home, mode 700) | `ops:setup-pi-services.yml:449` | parent of the mount; user home | high — encodes user home; moves with the user/mount rename (Tier 2) |
| `/var/lib/versitygw/iam` | `ops:tasks/versitygw.yml` `--iam-dir`; live both Pis | versitygw IAM | none — already clean (listed to exclude from sweep) |
| `cnpg.backupEndpoint` / scylla endpoint `http://192.168.11.5:9000` | `infra:schnappy-production-data/values.yaml:99,148`; `platform:scylla-agent-secret.yaml:23` | CNPG barman `endpointURL`, scylla `s3.endpoint` | none — IP:port, no `minio` token |
| `quay.io/minio/mc:latest`, `quay.io/minio/minio:*` | `infra:etcd-backup.yaml:112,143`; out-of-scope StatefulSets; `ops:setup-velero.yml:26` `minio_image` | etcd-backup uses `mc` S3 client | none — upstream tool/image, not a store-identity ref. **Do not rename** |

### 2j. systemd units

| ref | location | consumers | rename risk |
|---|---|---|---|
| `versitygw.service` (internal `minio` tokens) | `ops:tasks/versitygw.yml:92,95-96`; live both Pis | the running backup-store gateway; keepalived `:9000/health` gate | low edit, but **lockstep** — `User/Group=minio`, `RequiresMountsFor=/var/lib/minio/data`, `ExecStart … --sidecar /var/lib/minio/data/.sidecar /var/lib/minio/data/buckets` are downstream of the high-risk user + mountpoint renames (Tier 2). Unit name, `EnvironmentFile=/etc/versitygw/env`, `--iam-dir=/var/lib/versitygw/iam` already clean |
| `Retire MinIO leftovers` block (`/etc/systemd/system/minio.service`, `/usr/local/bin/minio`, `/etc/minio`) | `ops:setup-pi-services.yml:453-478` | one-time cleanup of retired MinIO artifacts | low — **do NOT rename**; these intentionally name the dead artifacts being deleted |

### 2k. comments / docs / literals

| ref | location | consumers | rename risk |
|---|---|---|---|
| `provider: Minio` (rclone S3 provider enum) | `platform:scylla-agent-secret.yaml:22` | Scylla Manager agent rclone S3 backend | **do NOT change** — functional enum confirmed working against versitygw (path-style + v4 signing) |
| `# CNPG backup S3 credentials (Pi MinIO)` etc. | `platform:cnpg-secret.yaml:54`; `network-policies.yaml:87,405` | humans only (NP rules are IP-based) | low — comment edit |
| Runbook prose `Pi MinIO` / `systemctl status minio` / `/var/lib/minio/data` | `platform:helm/schnappy-observability/runbooks/{VeleroBSLUnavailable,VeleroBackupFailing,KubeJobFailed,ClusterSecretStoreNotReady,PVCUsageHigh,VersitygwGatewayDown}.md` | on-call operators | low — STALE; `systemctl status minio` → `versitygw`. **Keep the `/var/lib/minio/data` literal** until Tier 2 |
| `keepalived check_services.sh` comments | pi1+pi2 `/etc/keepalived/check_services.sh:3,6` | keepalived (live gate already curls versitygw `:9000/health`) | low — cosmetic; deploy via ansible if templated |
| `Taskfile.yml` `dev`/Hyperfoil MinIO mentions | `ops:Taskfile.yml` | dev compose + Hyperfoil reporting | **out of scope** — in-cluster/app-data MinIO + Hyperfoil reporting |
| `salt_minion` in `/etc/cloud/cloud.cfg:55` | pi1+pi2 | cloud-init | none — **FALSE POSITIVE** (substring) |
| `priority-classes.yaml:15`, `kagent agent-grounding-configmap.yaml:22` | infra | descriptive text | out of scope — reference in-cluster MinIO |

### 2l. unverified gap (closed during Stage 0)

| ref | location | note |
|---|---|---|
| `/etc/versitygw/env` credential KEY names | pi1+pi2, mode 0400 root/minio | The ansible template (`ops:tasks/versitygw.yml:76-77`) shows the keys are `ROOT_ACCESS_KEY`/`ROOT_SECRET_KEY` (already clean); values come from `minio_root_user`/`password`. Confirm with one `sudo cat` in Stage 0 |

## 3. Target naming scheme (decided 2026-06-28)

**Chosen: the role-based `backup-store` / `backup` scheme** — implementation-neutral (naming after the gateway is exactly what left `minio` stranded when MinIO→versitygw), one token throughout, eliminating the `minio`/`minio-backup` collision. Applied uniformly:

| surface | from | to |
|---|---|---|
| Vault property names (velero path) | `minio_access_key` / `minio_secret_key` | `access_key` / `secret_key` *(matches the existing minio-backup-path scheme — one convention everywhere)* |
| Vault path leaf | `secret/data/schnappy/minio-backup` | `secret/data/schnappy/backup-store` |
| k8s secret name (etcd) | `etcd-backup-minio` | `etcd-backup-store` |
| k8s secret name (CNPG) | `schnappy-production-minio-backup` | `schnappy-production-backup-store` |
| k8s secret name (velero ES) | `velero-credentials-es` | `velero-credentials-es` *(unchanged — no `minio` token; target `velero-credentials` already clean)* |
| k8s secret keys (CNPG) | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | `ACCESS_KEY` / `SECRET_KEY` |
| env vars | `VELERO_MINIO_ACCESS_KEY` / `VELERO_MINIO_SECRET_KEY` | `BACKUP_ACCESS_KEY` / `BACKUP_SECRET_KEY` |
| ansible vars | `minio_root_user` / `minio_root_password` | `backup_root_user` / `backup_root_password` |
| linux user/group (Tier 2) | `minio` (keep **uid/gid 9000**) | `backup-store` (uid/gid **stay 9000**) — **not** bare `backup`, which collides with Debian's default `backup` user (uid 34) |
| GlusterFS volume (Tier 2) | `backup-minio` | `backup-store` |
| data dir / mount (Tier 2) | `/var/lib/minio`, `/var/lib/minio/data` | `/var/lib/backup-store`, `/var/lib/backup-store/data` |
| gluster bricks (Tier 2) | `/var/lib/gluster/backup-minio/{brick,arbiter-brick}` | `/var/lib/gluster/backup-store/{brick,arbiter-brick}` |
| **preserved as-is** | `provider: Minio`, `quay.io/minio/{mc,minio}`, `velero-credentials`, `scylla-agent-config-secret`, `/etc/versitygw/*`, `/var/lib/versitygw/iam`, the `Retire MinIO leftovers` cleanup strings, the OUT-OF-SCOPE app-store `minio`/`MINIO_ROOT_*`/`schnappy-production-minio` | — |

Rationale: `backup-store` describes the thing's **role** (the off-node backup object store), so it stays correct across any future gateway swap — unlike naming it after the implementation (`versitygw`), which is the mistake that stranded `minio` here. The short `backup`/`BACKUP_` form is used for env/ansible identifiers, and `ACCESS_KEY`/`SECRET_KEY` reuses the convention the etcd secret already carries; the full `backup-store` token names every resource, the linux user, the volume, and the mount. It shares no substring with the out-of-scope `minio` app store, removing the collision risk entirely. The linux user is `backup-store` rather than bare `backup` because Debian already ships a `backup` user (uid 34).

## 4. Risk tiers & scope recommendation

### Tier 1 — Credential / config layer (RECOMMENDED — DO IT)

Vault property rename (velero path), Vault path move (`minio-backup`→`backup-store`), k8s secret names + keys, env vars, ansible vars, the live `setup-velero.yml` env refs, stale comments/runbooks, plus the two hygiene fixes (`backup_volumes` stale bug, dead `minio_data`).

- **Risk:** low (GitOps/chart/comment edits) to medium (live Vault rewrites + k8s secret recreate), all mitigated to **zero-break** by the additive-first procedure in §5.
- **Value:** high — removes ~90% of the legacy terminology, including every confusing `minio-backup`/`MINIO_ROOT_*` token that misleads operators into thinking the backup store is the app-data MinIO.
- **Reversible:** yes, at every stage (old identifier retained until the new one is verified serving a real backup).
- **Recommendation: DO Tier 1.** High value, low blast radius, no downtime.

### Tier 2 — Data layer (RECOMMENDED: DEFER / DECLINE)

Linux user rename, GlusterFS volume rename (= create-new + ~17 GB data move across pi1/pi2/**ten**), data-dir remount, brick-path move.

- **Risk:** high. Gluster has no in-place rename; this is create-new-volume + mirror + repoint + retire across three hosts with **backup-store downtime** and a recursive-chown hazard if uid/gid 9000 is disturbed.
- **Value:** **zero functional value.** The service, binary, format, VIP, port, env file, and IAM dir are already versitygw-named. The remaining `minio` tokens here (`backup-minio` volume, `/var/lib/minio/data`, `minio` user) are purely cosmetic on-disk strings behind `RequiresMountsFor` and `User=` lines.
- **Recommendation: DECLINE for now.** Tier 2 risks a **verified-healthy** store to delete strings nobody routinely reads, for no behavioral gain. If a future Gluster maintenance window or Pi rebuild happens anyway, fold the rename in then (procedure pre-written in §6). Until then, document in `CLAUDE.md` that `/var/lib/minio` + volume `backup-minio` are versitygw's storage despite the name.

**Net scope of this plan: execute Tier 1; pre-stage but defer Tier 2.**

Bundle the non-naming hygiene fixes into Tier 1 since they touch the same files, **but treat the `backup_volumes` change as behavioral, not cosmetic** (see §5 Stage 7).

## 5. Staged Tier-1 migration procedure (additive-first, per consumer)

**Golden rule, every stage:** *write-new → force re-read → verify a real backup → retire-old.* Never delete an old identifier until the consumer that used it has produced a **fresh successful backup** against the new one. Each stage is independently revertible by re-pointing back to the still-present old identifier.

> **Two systemic hazards the whole procedure must respect (do not skip):**
>
> **(H1) The seed play overwrites, it is not additive.** `seed-vault-secrets.yml` writes each Vault path with `community.hashi_vault.vault_kv2_write`, which **replaces the entire KV2 data map** — it does not merge. So a bare live `vault kv put`/`patch` to add keys is silently undone the next time anyone runs `task deploy:seed-secrets`. **Therefore the Vault key/path changes are driven THROUGH the seed play** (edit it to emit the transitional set, then run the seed task), never by a one-off live write that the seed play will clobber. Stage 6 (seed-play + env edits) is consequently a **hard prerequisite**, sequenced into Stages 1 and 3 below — not a "land anytime" afterthought.
>
> **(H2) ESO has a refresh interval (1h for velero/etcd, 15m for cnpg/scylla) and no fallback.** After repointing a `property:`/`key:` you must **force a refresh and assert freshness** before any retire-old. A manifest edit bumps the ES generation and triggers a reconcile, but the **retire-old** step must independently prove the target Secret decodes non-empty from the new source. Forced-refresh + non-empty assertion is built into every stage.

> House rule: none of the file content we write may contain plan/ticket refs. The PR description carries that context, not the YAML.

### Stage 0 — Prep & baseline (no changes)

1. Confirm all four consumers green now:
   ```bash
   kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}'; echo            # Available
   kubectl -n kube-system get jobs -l app=etcd-backup --sort-by=.metadata.creationTimestamp | tail -1 # last Complete
   kubectl -n schnappy-production get cluster schnappy-production-postgres \
     -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'; echo               # True
   kubectl -n schnappy-production exec svc/schnappy-production-scylla-manager -- sctool task list      # last DONE
   ```
2. ESO health: `kubectl get externalsecrets -A | grep -Ei 'velero|etcd-backup|minio-backup|scylla-agent'` → all `SecretSynced`.
3. Close the §2l gap: `ssh sm@192.168.11.4 sudo cat /etc/versitygw/env` — confirm keys are `ROOT_ACCESS_KEY`/`ROOT_SECRET_KEY` and **record the current root access/secret values** (Stage 6 must prove they do not change).
4. Branch each repo: `git checkout -b chore/backup-store-rename` in `ops`, `infra`, `platform`.

Helper used by later stages (force-refresh + non-empty assert):
```bash
# usage: refresh_assert <ns> <es-name> <secret-name> <data-key>
refresh_assert() {
  kubectl -n "$1" annotate externalsecret "$2" \
    force-sync="$(date +%s)" --overwrite
  for i in $(seq 1 30); do
    r=$(kubectl -n "$1" get es "$2" -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}')
    [ "$r" = "SecretSynced" ] && break; sleep 5
  done
  v=$(kubectl -n "$1" get secret "$3" -o jsonpath="{.data.$4}" | base64 -d)
  [ -n "$v" ] || { echo "FAIL: $1/$3 key $4 is EMPTY"; return 1; }
  echo "OK: $1/$3 $4 non-empty, ES $2 = $r"
}
```

### Stage 1 — velero-path Vault properties (additive, seed-play driven) → velero + etcd-backup

Both consumers read `secret/data/schnappy/velero` properties `minio_access_key`/`minio_secret_key`.

1. **Transitional seed (emit BOTH old+new keys).** Edit `ops:seed-vault-secrets.yml:333-336` so the velero secret's `data:` map contains all four:
   ```yaml
   data:
     minio_access_key: "{{ lookup('env', 'VELERO_MINIO_ACCESS_KEY') }}"
     minio_secret_key: "{{ lookup('env', 'VELERO_MINIO_SECRET_KEY') }}"
     access_key:        "{{ lookup('env', 'VELERO_MINIO_ACCESS_KEY') }}"
     secret_key:        "{{ lookup('env', 'VELERO_MINIO_SECRET_KEY') }}"
   ```
   Apply: `task deploy:seed-secrets`. Verify: `vault kv get secret/schnappy/velero` shows **all four** keys (overwrite-safe because the seed play now emits all four).
2. **Repoint ESO** (`infra`): `velero-secrets.yaml:26,30` and `etcd-backup.yaml:43,47` — `property: minio_access_key`→`access_key`, `minio_secret_key`→`secret_key`. Commit; let Argo sync `cluster-config` (never force-sync/prune the root app).
3. **Force-refresh + assert non-empty:**
   ```bash
   refresh_assert velero      velero-credentials-es velero-credentials cloud
   refresh_assert kube-system etcd-backup-minio     etcd-backup-minio  ACCESS_KEY
   ```
4. **Verify a real backup per consumer:**
   - velero: `velero backup create rename-verify-velero-$(date +%s) --wait` → `Completed`.
   - etcd-backup: `J=rename-verify-etcd-$(date +%s); kubectl -n kube-system create job --from=cronjob/etcd-backup "$J" && kubectl -n kube-system wait --for=condition=complete job/"$J" --timeout=300s && kubectl -n kube-system delete job "$J"`.
5. **Retire old (seed-play driven).** Drop the two `minio_*` lines from `seed-vault-secrets.yml:333-336` (leaving only `access_key`/`secret_key`), `task deploy:seed-secrets`, then confirm `vault kv get secret/schnappy/velero` shows only the new keys and re-run step 4's velero backup once to confirm still green.
6. **Rollback (any sub-step before step 5):** revert the ESO `property:` edit — old keys still present in Vault until step 5; Argo re-syncs.

### Stage 2 — etcd-backup k8s secret name rename

1. **Add a second ExternalSecret** in `infra:etcd-backup.yaml` named `etcd-backup-store` (target `etcd-backup-store`), identical spec to `etcd-backup-minio` (now reading `access_key`/`secret_key`). Argo sync → both secrets exist.
2. `refresh_assert kube-system etcd-backup-store etcd-backup-store ACCESS_KEY`.
3. **Repoint CronJob:** `etcd-backup.yaml:155-156` `secretKeyRef.name: etcd-backup-minio`→`etcd-backup-store`. Sync.
4. **Verify:** trigger a CronJob run as in Stage 1.4 (unique job name); confirm `Complete`.
5. **Retire old:** delete the `etcd-backup-minio` ExternalSecret block from the manifest; Argo prunes it (cluster-config app only — never prune root/stateful apps).
6. **Rollback:** repoint `secretKeyRef.name` back; old secret still present until step 5.

### Stage 3 — Vault path `minio-backup` → `backup-store` (additive, seed-play driven) → CNPG + scylla

1. **Transitional seed (write BOTH paths).** Add a new seed task in `ops:seed-vault-secrets.yml` writing `{{ vault_prefix }}/backup-store` with the same `access_key`/`secret_key` from `VELERO_MINIO_*`, **keeping** the existing `:263-271` `minio-backup` task for now. `task deploy:seed-secrets`; verify `vault kv get secret/schnappy/backup-store` shows `access_key`/`secret_key`.
2. **Repoint platform chart** to the new path leaf:
   - `cnpg-secret.yaml:71,75`: `{{ .Values.vault.secretPathPrefix }}/minio-backup` → `/backup-store`.
   - `scylla-agent-secret.yaml:28,32`: same.
   Bump chart; Argo sync `schnappy-production-data`.
3. **Force-refresh + assert non-empty (independent of the slow scylla cron):**
   ```bash
   refresh_assert schnappy-production schnappy-production-minio-backup schnappy-production-minio-backup MINIO_ROOT_USER
   refresh_assert schnappy-production scylla-agent-config-secret       scylla-agent-config-secret       scylla-manager-agent.yaml
   ```
4. **Verify backups** (CNPG in Stage 4, scylla in Stage 5 — both still reading the same physical creds, now via the new path).
5. **Retire old:** remove the `minio-backup` seed task, `task deploy:seed-secrets`, then `vault kv metadata delete secret/schnappy/minio-backup` — **only after Stages 4 and 5 confirm fresh backups AND step 3 asserted both target Secrets decode non-empty from the new path.** Do not gate the delete on the slow daily scylla cron alone.
6. **Rollback:** revert the two chart `key:` edits; old path still present until step 5.

### Stage 4 — CNPG secret name + data-key rename (ONE atomic Helm release)

The secret name (`schnappy-production-minio-backup`) and keys (`MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD`) live in the `schnappy-data` chart + the infra value. The keys are referenced in **both** the `backup:` block (`cnpg-cluster.yaml:138,141`) and the recovery `externalClusters` block (`:86,89`).

1. **Additive secret render.** In `platform:cnpg-secret.yaml`, render a **second** ExternalSecret named `schnappy-production-backup-store` whose target Secret carries keys `ACCESS_KEY`/`SECRET_KEY` (sourced from `…/backup-store`), alongside the existing one for one release. Update `cnpg-rbac.yaml:12` to grant `get` on **both** names.
2. `refresh_assert schnappy-production schnappy-production-backup-store schnappy-production-backup-store ACCESS_KEY`.
3. **Atomic flip (single release).** In ONE Helm change, simultaneously:
   - `infra:schnappy-production-data/values.yaml:149` → `cnpg.backupSecret: schnappy-production-backup-store`;
   - `platform:cnpg-cluster.yaml:85,88` and `:137,140` → secret name `schnappy-production-backup-store`;
   - `platform:cnpg-cluster.yaml:86,89` and `:138,141` → keys `ACCESS_KEY`/`SECRET_KEY`.
   Never render a state where the referenced `backupSecret` name and the `key:` values disagree about which key scheme exists on that secret. Argo sync; CNPG rolls on the secret-ref change (HA failover, `instances: 2`).
4. **Verify — no backup gap.** Continuity must hold on the new primary, and BOTH the backup destination and the recovery path must authenticate:
   ```bash
   kubectl -n schnappy-production get cluster schnappy-production-postgres \
     -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'; echo   # stays True
   # forward (backup) destination:
   kubectl -n schnappy-production exec schnappy-production-postgres-1 -c postgres -- \
     barman-cloud-backup-list --cloud-provider aws-s3 \
     --endpoint-url http://192.168.11.5:9000 s3://postgres-backups/ | tail
   ```
   Then force a fresh base backup and confirm it completes:
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: postgresql.cnpg.io/v1
   kind: Backup
   metadata: { name: rename-verify-cnpg, namespace: schnappy-production }
   spec: { cluster: { name: schnappy-production-postgres }, method: barmanObjectStore }
   EOF
   kubectl -n schnappy-production wait backup/rename-verify-cnpg --for=jsonpath='{.status.phase}'=completed --timeout=600s
   kubectl -n schnappy-production delete backup rename-verify-cnpg
   ```
   Also assert the recovery `externalClusters` path lists without auth error (re-run `barman-cloud-backup-list` against the recovery `serverName`/`destinationPath` from `cnpg-cluster.yaml:78-89`).
5. **Retire old:** remove the old ExternalSecret + the old RBAC entry from the chart; next release prunes the old secret.
6. **Rollback:** point `cnpg.backupSecret` + both `cnpg-cluster.yaml` blocks back to the old secret/keys (still present until step 5).

### Stage 5 — scylla (path already repointed in Stage 3)

`scylla-agent-config-secret` keeps its name (operator convention) and `provider: Minio` (functional rclone enum). Only its Vault source moved (Stage 3).

1. **Verify the agent re-read** (Stage 3 already force-refreshed the secret; the agent re-reads on config change / next task):
   ```bash
   kubectl -n schnappy-production exec svc/schnappy-production-scylla-manager -- sctool task list   # last DONE
   ```
   If the daily hasn't run, trigger an ad-hoc backup and confirm `DONE`:
   ```bash
   kubectl -n schnappy-production exec svc/schnappy-production-scylla-manager -- \
     sctool backup -c schnappy-production-scylla
   # then poll: sctool task list  → status DONE
   ```
2. Only after this passes may Stage 3.5 delete the old `minio-backup` Vault path.

### Stage 6 — env vars + ansible vars (ops repo) — **value-identity is load-bearing**

This stage re-templates `/etc/versitygw/env` (the versitygw **root** S3 credential). If the new env var resolves empty or to a different value, the root key silently changes and **every** consumer breaks. The procedure proves byte-identity before deploying.

1. **`.env` on localhost, additive + value-identical.** Add `BACKUP_ACCESS_KEY`/`BACKUP_SECRET_KEY` to `/home/sm/src/ops/.env` set to the **same values** as the existing `VELERO_MINIO_*` (prod `.env` lives on localhost, never on ten). Assert identity:
   ```bash
   set -a; . /home/sm/src/ops/.env; set +a
   [ "$BACKUP_ACCESS_KEY" = "$VELERO_MINIO_ACCESS_KEY" ] && \
   [ "$BACKUP_SECRET_KEY" = "$VELERO_MINIO_SECRET_KEY" ] || { echo "VALUE MISMATCH — abort"; exit 1; }
   ```
2. **Inventory:** `production.yml:31-32` + `vagrant.yml:38-39` → `backup_root_user`/`backup_root_password`, sourcing the new env names. `tasks/versitygw.yml:17-18,76-77` → new var names.
3. **`setup-velero.yml` (LIVE — do this here, not Stage 7):** `:24-25` `velero_minio_access_key`/`secret_key` → derive from the renamed `backup-store_root_*` vars. Leave `velero_backup_path`/`minio_image`/the in-cluster `minio-backup` Deployment **as-is** (that is a separate decommissioning decision, not part of this rename).
4. **Seed play:** in the validation loop (`seed-vault-secrets.yml:155-186`) rename ONLY the two `VELERO_MINIO_*` lines (`:161-162`); **leave `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` at `:159-160`** (out-of-scope app store). Update the velero + backup-store seed tasks' `lookup('env', …)` to the new names.
5. **Taskfile:** rename `VELERO_MINIO_*` in BOTH env-passing blocks — `:324-325` (seed-test) and `:670-671` (seed-secrets). **Leave the adjacent `MINIO_ROOT_*` lines** (app store) and the `:39,41,49,119,121` dev/Hyperfoil lines (out of scope).
6. **Deploy + verify auth (not just health):**
   ```bash
   task deploy:pi-services        # re-templates /etc/versitygw/env (use task deploy:*, never raw ansible-playbook)
   ssh sm@192.168.11.4 sudo cat /etc/versitygw/env   # ROOT_* values byte-match the Stage-0 record
   # real authenticated S3 op against the VIP (health alone does NOT exercise auth):
   mc alias set bkverify http://192.168.11.5:9000 "$BACKUP_ACCESS_KEY" "$BACKUP_SECRET_KEY" && mc ls bkverify
   ```
   Then confirm a velero + etcd backup still complete (they authenticate with the ESO-synced creds, which must equal the unchanged root key).
7. **Retire old:** remove `VELERO_MINIO_*` from `.env`. The seed-play `assert` (non-empty loop) is a loud tripwire if any reference to the old name survives.
8. **Rollback:** old env names remain in `.env` until step 7; revert inventory/seed/Taskfile and re-deploy to fall back.

### Stage 7 — comments, runbooks, dead-key cleanup (ops + platform)

Low-risk, no live-cred verification beyond render/lint:

- `platform:cnpg-secret.yaml:54`, `network-policies.yaml:87,405` comments → "Pi backup store (versitygw)".
- Runbooks: `systemctl status minio` → `versitygw`; "Pi MinIO" → "Pi backup store (versitygw)". **Keep the `/var/lib/minio/data` literal** in `VersitygwGatewayDown.md:31` (still the real mount until Tier 2).
- `keepalived check_services.sh:3,6` comments (deploy via ansible if templated; else cosmetic on-Pi).
- **Dead key:** remove `minio_data` (`ops:setup-gluster.yml:366,371,376,388`) — never read.

**NOT in this stage (behavioral, handle separately):** the `backup_volumes` stale-bug row at `ops:setup-gluster.yml:554`. Flipping `stop_service: minio, autostart: false` → `stop_service: versitygw, autostart: true` would, on the next `task deploy:gluster`, `systemctl stop versitygw` on BOTH active-active Pis during the remount — a brief **full backup-store outage** the keepalived design avoids. **Preferred fix:** set `stop_service: ''` (versitygw owns its mount dependency via `RequiresMountsFor`, so the play need not stop it at all), leaving `autostart` irrelevant. If an explicit start is wanted, make it a separate, flagged change with its own rollback and a single-Pi-at-a-time validation — never a simultaneous dual-Pi stop. The embedded volume name + mount path stay until Tier 2.

## 6. Tier-2 data-layer procedure — **DEFERRED (declined for this plan)**

Buys zero functional value and risks a verified-healthy store; execute only inside an unrelated Gluster/Pi maintenance window. Pre-written for that window:

1. **Backup freeze.** Stop all four writers from initiating: scale CNPG backup off, `kubectl -n kube-system patch cronjob etcd-backup -p '{"spec":{"suspend":true}}'`, pause velero schedules, pause scylla tasks.
2. **Create the new Gluster volume** `backup-store` with fresh bricks `/var/lib/gluster/backup-store/{brick,arbiter-brick}` on pi1/pi2/ten (arbiter on ten). Do **not** reuse the old brick dirs.
3. **Stop versitygw on both Pis** (`systemctl stop versitygw`) so the source mount is quiescent.
4. **Mirror data** preserving ownership: mount both volumes transiently; `rsync -aHAX --numeric-ids` (preserves uid/gid **9000**) from `/var/lib/minio/data` → `/var/lib/backup-store/data`. Verify object counts/sizes match (~17 GB).
5. **Rename the linux user/group** keeping **uid/gid 9000** (no chown needed): `groupmod -n backup-store minio` then `usermod -l backup-store -d /var/lib/backup-store minio`.
6. **Repoint the unit (via ansible):** `User/Group=backup-store`, `RequiresMountsFor=/var/lib/backup-store/data`, `ExecStart … --sidecar /var/lib/backup-store/data/.sidecar /var/lib/backup-store/data/buckets`. Update `tasks/versitygw.yml` `vgw_gluster_mount`/`vgw_backend_dir`/`vgw_sidecar_dir` defaults and the `setup-gluster.yml` mount task + fstab (src `node_ip:/backup-store`) + the `backup_volumes` `name`/`mount` fields.
7. **`daemon-reload` + start versitygw**; keepalived `:9000/health` must pass on the master Pi before the VIP returns.
8. **Unfreeze + verify** all four consumers complete a fresh backup against the unchanged VIP `:9000`.
9. **Retire** the old `backup-minio` volume + `/var/lib/minio` brick/mount only after a full backup cycle is green.
10. **Rollback:** old volume + user (uid 9000) + mount stay intact until step 9; revert the unit + fstab and restart to fall back instantly.

## 7. End-state verification checklist

**Two-pass grep per repo** — first inclusive (eyeball the full remaining set), then assert each survivor is expected (Tier-2 deferred data paths, `provider: Minio`, `quay.io/minio/*`, the OUT-OF-SCOPE app store, the `Retire MinIO leftovers` cleanup):

```bash
# Pass 1 (inclusive — read every hit):
cd /home/sm/src/ops      && git grep -in minio -- deploy/ Taskfile.yml
cd /home/sm/src/infra    && git grep -in minio -- clusters/production/
cd /home/sm/src/platform && git grep -in minio -- helm/

# Pass 2 (assertion — only expected survivors remain):
cd /home/sm/src/ops && git grep -in minio -- deploy/ Taskfile.yml \
  | grep -vE 'Retire|/usr/local/bin/minio|/etc/minio|minio\.service|/var/lib/minio|backup-minio|salt_minion|dev|[Hh]yperfoil|MINIO_ROOT'
# expect: empty
cd /home/sm/src/infra && git grep -in minio -- clusters/production/cluster-config/ clusters/production/velero/ \
  | grep -vE 'quay.io/minio'
# expect: empty (etcd-backup-minio name + velero/etcd minio_* properties gone)
cd /home/sm/src/platform && git grep -in minio -- \
  helm/schnappy-data/templates/cnpg-secret.yaml helm/schnappy-data/templates/cnpg-cluster.yaml \
  helm/schnappy-data/templates/scylla-agent-secret.yaml helm/schnappy-observability/runbooks/ \
  helm/schnappy-data/templates/network-policies.yaml \
  | grep -vE 'provider: Minio'
# expect: empty
```
Document each Pass-1 survivor explicitly rather than trusting the Pass-2 regex (the broad `dev`/`Hyperfoil`/`MINIO_ROOT` excludes can mask a real miss).

**All four consumers green:**
```bash
kubectl -n velero get bsl default -o jsonpath='{.status.phase}'; echo                                  # Available
kubectl -n kube-system get jobs -l app=etcd-backup --sort-by=.metadata.creationTimestamp | tail -1     # Complete
kubectl -n schnappy-production get cluster schnappy-production-postgres \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'; echo                    # True
kubectl -n schnappy-production exec svc/schnappy-production-scylla-manager -- sctool task list          # DONE
```

**No orphaned Vault keys/paths/secrets:**
```bash
vault kv get secret/schnappy/velero        # only access_key/secret_key (no minio_*)
vault kv list secret/schnappy/             # backup-store present; minio-backup ABSENT; minio (app store) STILL present (correct)
kubectl -n kube-system        get es,secret | grep etcd-backup-minio                 # empty
kubectl -n schnappy-production get es,secret | grep schnappy-production-minio-backup # empty
```
ESO all `SecretSynced`; `provider: Minio`, `quay.io/minio/*`, `secret/schnappy/minio`, and `schnappy-production-minio` (no `-backup`) **all intentionally still present**.

## 8. Effort & sequencing estimate

| Stage | Repos touched | Risk | Effort |
|---|---|---|---|
| 0 Baseline + gap-close + record root creds | — | none | 20 min |
| 1 velero-path Vault props (seed-play) + velero/etcd verify | ops + infra + Vault | medium | 50 min (incl. backup waits) |
| 2 etcd secret name | infra | medium | 25 min |
| 3 Vault path move (seed-play) + chart repoint | ops + platform + Vault | medium | 40 min |
| 4 CNPG name+keys (atomic release) | infra + platform | medium | 50 min (CNPG roll + base backup) |
| 5 scylla verify | — | low | 20 min |
| 6 env + ansible vars + setup-velero + deploy + auth verify | ops (+ localhost .env) | medium | 50 min (incl. `task deploy` + `mc ls`) |
| 7 comments/runbooks/dead-key | ops + platform | low | 25 min |
| **Tier 1 total** | 3 repos + Vault | low–medium, **zero downtime** | **~4.5 h active**, spread so each consumer's backup cycle confirms before retire-old |
| Tier 2 (deferred) | ops + Pis + Gluster | high, **downtime** | ~3–4 h in a maintenance window — **not scheduled** |

**Sequencing & dependencies:**

- **Stage 6's env/seed edits are a hard prerequisite for the additive Vault writes** in Stages 1 and 3 *as soon as they are applied* (hazard H1: the seed play overwrites). Practical ordering: Stages 1 and 3 each carry their own *transitional* seed-play edit (emit old+new) so the seed play is never the thing that wipes the additive keys; Stage 6 then finalizes the env/var rename and drops the old env names. Do **not** treat Stage 6 as "land anytime" — its seed-play and Taskfile edits are coupled to the Vault key/path lifecycle.
- The velero/etcd chain (Stages 1→2) and the CNPG/scylla chain (Stages 3→4→5) are otherwise independent and may run in either order.
- Keep each **retire-old** step (final seed-play drop, ES deletion, `vault kv metadata delete`) in a follow-up commit a backup-cycle later, so a verified-green window separates additive from destructive.
- One PR per repo (`ops`, `infra`, `platform`), cross-linked; additive ordering lets PRs merge without a creds-break window.

**Per house rules:** update `CLAUDE.md` / this plan doc after it lands (note that `/var/lib/minio` + volume `backup-minio` remain as versitygw storage by deliberate Tier-2 deferral); use `task deploy:*` for the ansible step; drive all Vault rewrites through the seed play (never a bare live `kv put` the seed play will clobber); never force-sync or prune the root or stateful Argo apps during any sync.
