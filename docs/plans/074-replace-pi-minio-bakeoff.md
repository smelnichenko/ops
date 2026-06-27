# Plan 074: Replace Pi MinIO — Vagrant bake-off (versitygw-over-Gluster vs Garage)

## Status: DRAFT (2026-06-27)

> Supersedes the original "two independent Pi MinIOs" framing of this plan.
> The decision narrowed to *replacing MinIO entirely*; this plan decides the
> replacement **empirically in Vagrant** before any production change.

## Context

### What happened (2026-06-27)

A network event cost the Pi side its Consul quorum. MinIO's launch is wrapped
in `consul lock minio/active` (Plan 072 Part A) so two writers can't corrupt the
shared `xl-single` Gluster data dir — but with no quorum, no node could hold the
lock, so **MinIO ran nowhere**. The VIP `192.168.11.5:9000` was *connection
refused* for the whole window; Velero's BSL went `Unavailable`, every
`kopia-maintain` job and the hourly `etcd-backup` failed. It recovered only
after a **manual reboot of both Pis**. Plan 072 documented this exact tradeoff
("MinIO availability now depends on Consul quorum"); the event was that cost
coming due.

### Why MinIO is out (not just its replication)

The decision is to leave **MinIO the project**: the community edition is being
actively de-invested (console UI removed, `mc admin` surface trimmed in the 2025
builds we run), so betting the only off-cluster backup store's future on it is
unwise. The fix is a different object store — chosen on evidence.

### The evaluation (this session)

A parallel evaluation scored three candidates against this environment (the 5 S3
consumers, ARM/Pi fit, partition-tolerant redundancy, project governance):

| Candidate | Overall | Verdict |
|---|---|---|
| **Garage** (Deuxfleurs) | **4.5** | Purpose-built for self-hosted low-power partition-distributed nodes; native rf=3 quorum solves the outage natively. |
| **versitygw over Gluster** | **4.4** | Keep the trusted Gluster; swap MinIO for a *stateless* Apache-2.0 S3 gateway. Smallest blast radius. |
| SeaweedFS | 2.4 | **Rejected.** `W=N` writes fail on any missing replica (no partition survival); open-core single-maintainer + paid Enterprise tier (the same trap as MinIO); a multipart bug that silently writes wrong-size objects. |

Garage and versitygw are a near-tie representing **different philosophies**
(eliminate Gluster vs keep it). Rather than guess, this plan **prototypes both
in Vagrant and lets the failure tests decide.**

## Goal

Pick the Pi backup object store on empirical evidence: stand up **versitygw-over-
Gluster** and **Garage rf=3** in the Vagrant pi1/pi2/ten harness, run an
identical failure + consumer test matrix against each, and choose the winner by
a fixed rubric. Only then write the production migration. **No production change
until the bake-off picks a winner.**

## The two finalists (decisive facts from the evaluation)

### A. versitygw over the existing Gluster volume

- One **stateless** `versitygw` S3 gateway per Pi over the existing
  `backup-minio` Gluster volume (replica-3-arbiter: pi1+pi2+ten). Object = file
  on POSIX, so **two gateways are not a dual-writer hazard** the way MinIO's
  `xl-single` is → **no Consul lock needed** (the thing that caused the outage).
- Redundancy delegated to Gluster, which *did not fail* on 2026-06-27.
- S3 compat **5/5** (POSIX backend is versitygw's most complete: SigV4,
  path-style, ListObjectsV2, full multipart).
- Apache-2.0; single-vendor (Versity) but no feature-stripping history.
- **Blast radius: small** — keep storage, drop MinIO + the Consul fence. No
  data migration to a new storage system, no new quorum.
- **Risk to validate:** versitygw stores etag/object metadata in `user.*`
  **xattrs**, and GlusterFS-over-FUSE has documented xattr quirks — must prove
  etag/multipart integrity holds across both gateways on the Gluster mount.

### B. Garage rf=3 (eliminate Gluster + keepalived + Consul)

- A 3-node Garage cluster (pi1 + pi2 + **ten as a real storage node**, each its
  own zone) at `replication_factor=3`. Native quorum replication **replaces the
  whole VIP + Consul-lock + Gluster contraption**.
- Partition behaviour (consistent mode, rf=3): write/read quorum 2. Survives any
  one node loss for reads **and** writes with no intervention; under a pi↔pi
  partition the 2-node majority stays read+write, the isolated node cleanly
  refuses writes (no split-brain). This is exactly the outage, solved natively.
- S3 compat **5/5** (Scylla agent must switch `provider: Minio` → rclone
  `Other`; etcd CronJob off the `mc` client).
- AGPLv3; **non-profit collective** (Deuxfleurs), NLnet-funded, no open-core →
  the opposite of the MinIO governance worry.
- **Blast radius: large** — new store, **commit `ten` to the backup quorum**,
  migrate ~250 GB, retire Gluster's `backup-minio` volume.
- **Risks to validate:** (1) LMDB metadata **corrupts on unclean power loss** —
  mandatory `metadata_auto_snapshot_interval` + rely on rf=3 to rebuild a bad
  node; (2) `ten` joining the backup quorum couples a backup replica to the k8s
  node (rf=3 still leaves 2 copies on the Pis if `ten` dies).

## The 5 S3 consumers (the hard gate — both must pass all)

| Consumer | Needs | versitygw | Garage |
|---|---|---|---|
| Velero (kopia, fs-backup) — bucket `velero` | SigV4, path-style, ListObjectsV2, multipart, ~250 GB | yes | yes |
| CNPG barman-cloud — bucket `postgres-backups` (also a **restore** source) | SigV4, multipart, many small WAL PUTs + large basebackups | yes | yes |
| ScyllaDB Manager — bucket `scylla-backups` | S3 via rclone fork; `provider` matters | yes | **partial** — set `provider: Other`, restore-test |
| etcd-backup CronJob — bucket `etcd-backups` | currently the `mc` client; basic PUT/LIST/rm | yes | **partial** — move off `mc` to rclone/aws-cli |
| All | SigV4, **path-style**, plain HTTP `:9000`, fixed keypair | yes | yes |

Files to repoint (both paths): `infra .../velero/values.yaml` (s3Url),
`platform .../cnpg-cluster.yaml` + `infra .../schnappy-production-data/values.yaml`
(barman endpoint), `platform .../scylla-agent-secret.yaml` (provider + endpoint),
`infra .../cluster-config/etcd-backup.yaml` (mc → rclone).

## Bake-off — the test matrix (this is the decision)

Harness: `ops/Vagrantfile` (pi1 .56.20, pi2 .56.21, kubeadm .56.10, VIP
.56.50). **Known harness blocker** (Plan 072): Forgejo crashes on a queues LOCK
perm and HAProxy:5000 is down — the stashed fix needs DB passwords in vagrant
vars; resolve or work around first, since the consumer-smoke test needs a
working cluster. For Garage, add `ten`/kubeadm as a 3rd storage node in the
inventory.

Each finalist runs the **same** experiments; every one has an explicit pass bar:

| # | Experiment | What it proves | Pass criteria |
|---|---|---|---|
| T1 | **Consumer smoke** — velero backup→restore; CNPG barman archive→PITR restore; Scylla snapshot→restore; etcd snapshot PUT→GET | the 5 consumers actually work end-to-end (not just "S3 responds") | all 4 round-trips succeed; restored data verified |
| T2 | **Single-node loss** — kill one Pi (Garage: also kill `ten`) | survives a node death unattended | store stays **read+write**; a velero backup succeeds during the outage; **no manual step** |
| T3 | **pi↔pi partition** — `iptables`-isolate the Pis | the 2026-06-27 failure mode | majority side read+write; minority refuses cleanly; on heal, reconciles with **no data loss/divergence** |
| T4 | **Unclean power loss** — hard-reset a node mid-write | the per-candidate corruption risk | node rejoins and self-heals; **no corruption** (Garage: LMDB snapshot+rebuild; versitygw: Gluster-FUSE consistency) |
| T5 | **Candidate-specific probe** | the named risk | versitygw: etag/multipart integrity via `user.*` xattrs across both gateways. Garage: wipe a node's data dir, confirm rf=3 rebuild |
| T6 | **Resource + ops** | fits Pi-class, operable | RAM/CPU on Pi-sized VMs acceptable; document the ops steps + monitoring hook |

Record RPO/RTO per failure and the manual-step count (target: zero for T2/T3).

## Decision rubric

**Hard gates (must pass to qualify):** T1 (all consumers), T2, T3, T4. A finalist
that fails any gate is out regardless of score. **Tiebreak among qualifiers**, in
order: (1) fewest manual steps under failure, (2) smallest production blast
radius / migration risk, (3) operational simplicity + monitoring, (4) project
governance. Document the result as a short decision record appended here.

## What to build for the bake-off (throwaway-OK Ansible spikes)

- **versitygw spike:** a role that installs versitygw on each Pi, points its
  POSIX backend at the existing `/var/lib/minio/data` Gluster mount (or a fresh
  bucket root on it), systemd unit, same `/etc/minio/env` keypair, **no consul
  lock**. Decide VIP vs per-Pi endpoint (stateless gateways → both run; VIP just
  routes — D1 below).
- **Garage spike:** a role that installs Garage on pi1/pi2/ten, writes the TOML
  (rf=3, zones, `metadata_auto_snapshot_interval`), runs `garage layout`
  assign+apply, creates buckets + an access key matching the consumers' keypair.
  No Gluster/keepalived/Consul for it.

Keep both behind a Vagrant-only inventory toggle so prod is untouched.

## After the bake-off → production migration (winner-dependent)

Common: migrate ~250 GB bucket-by-bucket with `rclone`/`mc mirror` from the live
MinIO endpoint to the winner (no on-disk format lock-in — kopia/barman/scylla
keep their bytes); cut the 5 consumers (Scylla `provider: Other`, etcd off
`mc`); **restore-verify CNPG + Velero before retiring MinIO**; retire the
`MinioDualActive` alert (dual-active is no longer a hazard) and add "replica
down" / (Garage) "layout/replication unhealthy" alerts.

- **If versitygw wins:** revert the Plan 072 `consul lock` from the MinIO unit,
  pull MinIO from the keepalived `SERVICES` table, run two gateways, keep
  Gluster. D1: keep `.5` as a health-checked router to a live gateway.
- **If Garage wins:** stand up the 3-node cluster, migrate, decommission the
  `backup-minio` Gluster volume + brick + arbiter, and retire the MinIO/keepalived
  /Consul-lock machinery for backups entirely.

## Interaction with Plans 071 and 072

- **072 (Pi failover fencing) — superseded for MinIO** when this ships (the
  Consul-lock fence's premise, a shared data dir, goes away under either
  finalist). Part B (re-converge timer) and the Consul-lock pattern **stay for
  Nexus** (still active-passive on Gluster + H2 lock). Update 072's status on
  cutover, not before.
- **071 (cluster backup + DR) — complementary.** This hardens Tier 1 (Pi-resident
  backups) against a node/partition event; it does **not** replace 071-F off-site
  replication — two Pis in one rack still don't survive whole-site loss. Off-site
  remains the next DR layer.

## Risks & tradeoffs

- **Bake-off cost:** building two object-store spikes + the harness fix is real
  effort, but it's throwaway Vagrant work that de-risks a hard-to-reverse prod
  change to the *backup* store. Worth it.
- **Garage:** `ten` in the backup quorum; LMDB power-loss hazard (mitigated by
  snapshot config + rf=3 rebuild); small maintainer team.
- **versitygw:** Gluster-FUSE xattr correctness is the gating unknown (T5); keeps
  Gluster's existing operational surface; single-vendor (but permissive license).
- **Either:** no Object Lock/WORM on either finalist — backups stay mutable (no
  ransomware-immutable tier; out of scope, note for 071-F off-site).

## Rollback

The bake-off is Vagrant-only — zero prod risk. The production migration keeps
MinIO + the Gluster data intact until restore-verify passes on the winner, so
cutover is reversible (repoint endpoints back) until MinIO is decommissioned.

## Out of scope

- Off-site replication (Plan 071-F) — the other half of DR; do next.
- Backup encryption at rest / Object Lock immutability.
- Nexus's active-passive arrangement (stays on Gluster + H2 lock + 072 Part B).
- In-cluster MinIO deployments (`schnappy-*-minio`) — unrelated to the Pi store.

## Open decisions (resolve during the spike)

1. **D1 — endpoint:** keep VIP `.5` as a health-checked router (zero consumer
   change) vs a dedicated service IP. Both finalists keep clients on `.5:9000`
   to avoid churning the 5 consumers.
2. **D2 — Garage zones / `ten` role:** confirm `ten` can carry a full backup
   replica (disk + the coupling tradeoff) before committing track B to prod.
3. **D3 — etcd & Scylla client swaps** (mc→rclone, provider→Other) — fold into T1
   so they're proven in the bake-off, not discovered in prod.
