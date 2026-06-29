# Plan 077 — Replace the in-cluster app-data MinIO with versitygw

## 1. Context & goal

The `schnappy-data` Helm chart runs a **hand-rolled, single-replica standalone MinIO** (`minio server /data` on one RWO PVC, ClusterIP `{release}-minio:9000`, S3-only, no console — not the upstream chart, not a StatefulSet, not distributed). It is deployed as **three independent instances**:

| Release | Buckets | Consumers |
|---|---|---|
| `schnappy-production` / `schnappy-test` | `email-attachments` | the **monitor app** (`AttachmentStorageService`, io.minio SDK) — the only first-party S3 client |
| `schnappy-infra` | `mimir-blocks`, `tempo-traces`, `hyperfoil-reports` | **Mimir** + **Tempo** block storage, **Hyperfoil** report upload |

Preview/PR-envs never set `minio.enabled`; they share one MinIO via a Vault endpoint (`schnappy/preview-minio.endpoint`), isolated by a `pr-<N>` bucket prefix.

**Goal:** replace MinIO with **versitygw** (the stateless S3 gateway already serving the Pi backup store and validated in DR tests), retiring MinIO's de-invested community edition and consolidating the stack on one S3 implementation.

**This is a different surface from the Pi backup store** (which is already versitygw — Plan 074/076). The Pi store and this in-cluster store share only the substring "minio"; never conflate them.

## 2. Why this is safe — the evidence

Two prior investigations de-risked this before any change:

1. **Feasibility (8-agent workflow).** The monitor app uses **no presigned URLs** and exactly four vanilla S3 ops (`bucketExists`, `makeBucket`, `putObject` single-PUT ≤50 MB, `getObject`) — all SigV4 / path-style / `us-east-1`, matching versitygw. The app path is an **endpoint swap with zero Java changes**.
2. **Live soak (local docker, prod versions).** versitygw v1.6.0 posix backend was driven by real **Mimir 2.17.8** and **Tempo 2.7.2**:
   - `thanos_objstore_bucket_operation_failures_total = 0` across `exists / get / get_range / iter / upload / delete`.
   - Listing is **complete** (disk == S3 recursive list) and delimited `ListObjectsV2` returns **CommonPrefixes with the trailing slash** — versitygw does **not** have the rclone-`serve s3` bug that would silently hide blocks (the single biggest risk).
   - A **real compaction merge** (level-2 block from 2 sources) and **store-gateway discovery** (`blocks_loaded=6`, 24 range-GETs) both succeeded.
   - Tempo flushed a block, discovered it via listing, and a **TraceQL search read the trace back** end-to-end.

   Not exercised by the soak: multipart (blocks stayed < 5 MiB) — already proven by the live velero/CNPG backups on the Pi versitygw; and the `copy_file_range`/NFS caveat is moot because the in-cluster PVC is local-path.

**Verdict carried into this plan: GO** for all three tiers.

## 3. The one hard constraint: data is not readable in place

MinIO `server /data` stores objects in its **xl-single on-disk format** (`<bucket>/<object>/xl.meta` + part files), which versitygw's `object=file` POSIX backend **cannot read directly**. Therefore the cutover **cannot** reuse the MinIO PVC in place — it must be an **S3-level `mc mirror`** from a running MinIO to a running versitygw (both up simultaneously, on separate storage). This shapes the whole migration: per release, stand up versitygw in parallel, mirror, flip consumers, then decommission MinIO.

Everything is **additive-first and reversible up to the decommission step**: versitygw is introduced alongside MinIO; consumers are flipped only after a verified mirror; MinIO (and its data) is deleted only after a soak proves versitygw serves the workload.

## 4. The chart change

Add a parallel versitygw workload to `schnappy-data`, gated on a new value, reusing the existing MinIO secret + helpers. **Do not touch the MinIO templates until decommission** (clean rollback).

New value block (chart `values.yaml`, default off):
```yaml
s3gw:
  enabled: false            # set true to stand versitygw up alongside MinIO
  image: ghcr.io/versity/versitygw:1.6.0
  mirror: false             # set true to (re-)run the one-shot mc-mirror Job
  resources: { ... }        # mirror of minio.resources
```

New templates (mirrors of the `minio-*` ones, component label `s3gw` so they do **not** collide with the MinIO Service selector):

- **`s3gw-pvc.yaml`** — a fresh RWO PVC `{fullname}-s3gw` (empty; the mirror destination). Size = the MinIO PVC size.
- **`s3gw-deployment.yaml`** — versitygw Deployment `{fullname}-s3gw`:
  - `image: {{ .Values.s3gw.image }}`, **no `command`** — drive via env:
    `ROOT_ACCESS_KEY`←secretKeyRef `{minio secret}` key `MINIO_ROOT_USER`, `ROOT_SECRET_KEY`←key `MINIO_ROOT_PASSWORD` (explicit `env:`, not `envFrom`, so the existing secret-key names are untouched), `VGW_PORT=:9000`, `VGW_BACKEND=posix`, `VGW_BACKEND_ARGS=/data/buckets`, `VGW_IAM_DIR=/data/iam`.
  - **initContainer** (busybox) `mkdir -p /data/buckets /data/iam` — versitygw creates neither, and the IAM dir **must be separate from the backend** or it surfaces as a stray bucket.
  - Probes: `tcpSocket: 9000` (versitygw's `/health` can answer 200 before the S3 API is ready — same lesson as the Pi role).
  - Keep the existing hardened `securityContext` (runAsUser 1000, drop ALL, `readOnlyRootFilesystem: true` — versitygw writes only to `/data` + `/tmp`), `priorityClassName: data-critical`, port name `s3`, PVC `{fullname}-s3gw` at `/data`, `tmp` emptyDir.
- **`s3gw-service.yaml`** — ClusterIP `{fullname}-s3gw:9000`.
- **`s3gw-buckets-job.yaml`** — clone of `minio-buckets-job.yaml` pointed at `{fullname}-s3gw:9000` (plain `mc mb --ignore-existing` already works against versitygw; keep the `quitquitquit` sidecar-exit).
- **`s3gw-mirror-job.yaml`** (gated on `s3gw.mirror`) — one-shot: `mc alias set` both endpoints, `mc mirror --overwrite local-minio/<bucket> s3gw/<bucket>` for each bucket, then `mc ls --recursive` both and **assert equal object counts** (fail the Job otherwise). `sync-options: Delete=true`, sidecar-disabled, `quitquitquit`.

Mesh + NP (chart `schnappy-mesh` + `schnappy-data/templates/network-policies.yaml`): add **parallel** entries for `component: s3gw` mirroring the `component: minio` ones — PeerAuthentication PERMISSIVE on 9000 (sidecar-less Mimir/Tempo speak plaintext), the AuthorizationPolicy allowing the same principals, and the NetworkPolicy ingress. These are additive; the MinIO ones stay until decommission.

**Consumer endpoints** (flipped at cutover, per release, in the infra `values.yaml`):
- App: `app-deployment.yaml` emits `MINIO_ENDPOINT=http://{fullname}-minio:9000` — add a value (e.g. `minio.endpointOverride`) so it can be repointed to `{fullname}-s3gw:9000` without editing the template.
- Mimir/Tempo: set `mimir.minioEndpoint` / `tempo.minioEndpoint` to `{fullname}-s3gw:9000`.
- Hyperfoil: repoint its `*-minio:9000` reference.

## 5. Execution — tier by tier, lowest blast radius first

Order: **test → production (app-data) → infra (Mimir/Tempo/Hyperfoil) → preview**. Each tier is a sequence of PRs (platform chart + infra values), GitOps-applied, with a verify gate before the irreversible decommission.

### Tier A — app-data (`schnappy-test`, then `schnappy-production`)

1. **PR-1 (platform):** add the `s3gw` templates + values (default off). No-op until enabled.
2. **PR-2 (infra, test):** `s3gw.enabled: true`. Argo brings up versitygw + its buckets Job alongside MinIO. Verify the pod is Ready and `mc ls {fullname}-s3gw:9000` shows the buckets.
3. **PR-3 (infra, test):** `s3gw.mirror: true`. The mirror Job copies `email-attachments` MinIO→versitygw and asserts equal counts. Verify the Job succeeded.
4. **PR-4 (infra, test):** flip `minio.endpointOverride` → `{fullname}-s3gw:9000`; roll the monitor app. **Verify:** upload a test inbound email with an attachment (Resend webhook) and fetch it back from the inbox — round-trips through versitygw. Re-run the mirror once more to catch any write between steps 3–4.
5. **Soak** (a day of normal use). Reversible: flip `endpointOverride` back to MinIO (the original data is intact).
6. **PR-5 (infra, test) — decommission (point of no return):** only after §6's gates pass **and a fresh Velero backup of the MinIO PVC is confirmed**, set `minio.enabled: false`. Argo removes the MinIO Deployment + PVC; versitygw is the only store. (Velero can still restore the old MinIO PVC if ever needed.)
7. Repeat 2–6 for `schnappy-production`.

### Tier B — infra observability (`schnappy-infra`)

Same shape, but the buckets are `mimir-blocks` / `tempo-traces` / `hyperfoil-reports`. **Per the "save existing data" directive, all history is preserved** — Mimir blocks and Tempo traces are mirrored, never dropped:
- Mirror all three buckets (`mimir-blocks` can be sizeable → size the s3gw PVC for it; this is the transient second PVC). `hyperfoil-reports` is regenerable but mirrored too, for uniformity.
- **Verify:** after cutover, `cortex_bucket_store_blocks_loaded > 0`, `thanos_objstore_bucket_operation_failures_total == 0`, a Grafana metrics query and a Tempo trace search both return data; `tempodb_blocklist_length > 0`. Soak before decommission.

### Tier C — preview shared store

Decoupled — no chart change. Stand up a shared versitygw (or reuse the production one), repoint the Vault value `schnappy/preview-minio.endpoint`, and confirm: (a) the gateway creds may create buckets on first write (the app's `makeBucket` covers per-PR `pr-<N>` buckets), and (b) `preview-cleanup-job.yaml`'s `mc rb --force` recursive remove works (standard S3 — it does).

## 6. Verification gates (every tier, before decommission)

- versitygw pod Ready; `mc ls` shows all expected buckets.
- Mirror Job is green — `mc mirror` + `mc diff` show **zero** difference for every bucket (a non-empty diff fails the Job and blocks the cutover).
- **A fresh Velero backup of the MinIO PVC is confirmed** before deletion — the `backup.velero.io/backup-volumes: data` annotation already snapshots it to the Pi backup store; trigger an on-demand backup and confirm it completed. This is the safety net for "save existing data".
- A real consumer round-trip: attachment upload+download (app) / metrics+trace read-back (infra).
- For infra: `thanos_objstore_bucket_operation_failures_total == 0` and `cortex_bucket_store_blocks_loaded` matches the bucket block count (the discovery proof from the soak, now in-cluster).
- mesh: the consumer can reach `{fullname}-s3gw:9000` through the PERMISSIVE PeerAuth (no `RBAC: access denied` in the istio-proxy logs).

## 7. Risks & open decisions

| Item | Note |
|---|---|
| **Transient second PVC** | Required because xl-single isn't versitygw-readable. For `mimir-blocks` this may be large; ensure node disk headroom. Freed when MinIO is decommissioned. |
| **History retention (infra)** | **Resolved: preserve everything** (save-existing-data directive). Mimir blocks + Tempo traces are mirrored, never dropped; cost is the larger transient s3gw PVC + a longer `mimir-blocks` mirror. |
| **Write delta during mirror→flip** | New writes to MinIO between the mirror and the endpoint flip aren't on versitygw yet → re-run the incremental `mc mirror` immediately before flipping reads. For email-attachments this matters; for Mimir/Tempo the ingester re-ships recent blocks. |
| **End-state naming** | After decommission the workload is named `{fullname}-s3gw`. Collapsing `s3gw`→`minio` (Service/label/secret-key names) is cosmetic and carries the same zero-gain/breakage-risk as Plan 076's declined Tier-2 — **defer as a separate decision**; the `MINIO_*` env contract is internally consistent and functional as-is. |
| **`readOnlyRootFilesystem`** | versitygw writes only under `/data` (PVC) and needs `/tmp`; the existing `tmp` emptyDir + RO-root carries over. Confirm versitygw has no other write path. |
| **mc image** | The buckets/mirror Jobs use `minio/mc` — that's the MinIO *client*, S3-generic, and stays (it's not the MinIO server). Keep. |

## 8. Out of scope

- The **Pi backup-store** versitygw (already migrated — Plan 074/076).
- Any **cosmetic rename** of the in-cluster `minio` Service/label/secret-key identifiers (deferred, §7).
- Changing the monitor app's Java or the io.minio SDK (the swap is endpoint-only).

## 9. Status

- [ ] Tier A — test
- [ ] Tier A — production
- [ ] Tier B — infra (mirror all history — preserve)
- [ ] Tier C — preview
- [ ] (deferred) cosmetic `s3gw`→`minio` naming collapse
