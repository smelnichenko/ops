# Plan 074: Replace Pi MinIO — Vagrant bake-off (versitygw-over-Gluster vs Garage)

## Status: CUTOVER DONE (2026-06-27) — versitygw live on the Pis, MinIO retired; playbook cleanup (step 5) remains

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
- Deployment shape (verified from docs): `versitygw --port :9000 posix
  --sidecar <metadir> <backend-path>`, root creds via `ROOT_ACCESS_KEY` /
  `ROOT_SECRET_KEY`, a bucket = a top-level subdir under the backend path,
  ARM64 binaries published. One stateless instance per Pi, **no consul lock**.
- **Risk — and its mitigation:** versitygw *defaults* to storing etag/object
  metadata in `user.*` **xattrs**, which GlusterFS-over-FUSE handles poorly.
  But versitygw has a **`--sidecar <dir>`** mode that stores metadata as
  **regular files** instead. Put the sidecar **on the Gluster volume** →
  metadata is shared across both gateways as plain files with no xattr
  dependency. This likely removes the gating risk; T5 must confirm (comparing
  xattr-default vs sidecar). There is also `--nometa` for read-only datasets.

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
.56.50). **Use a minimal subset** — the object-store bake-off needs only the
object store on pi1/pi2 (+ `ten`/kubeadm for Garage) and the kubeadm cluster VM
for T1; it does **not** need the Forgejo/Keycloak/Patroni/Nexus stack. That
sidesteps the Plan-072 Forgejo-queues-LOCK / HAProxy:5000 harness blocker
entirely (recon 2026-06-27: no stash remains and `inventory/vagrant.yml`
already carries all the DB passwords, so that blocker looks resolved anyway).
For Garage, add `ten`/kubeadm as a 3rd storage node in the inventory.

Each finalist runs the **same** experiments; every one has an explicit pass bar:

| # | Experiment | What it proves | Pass criteria |
|---|---|---|---|
| T1 | **Consumer smoke** — velero backup→restore; CNPG barman archive→PITR restore; Scylla snapshot→restore; etcd snapshot PUT→GET | the 5 consumers actually work end-to-end (not just "S3 responds") | all 4 round-trips succeed; restored data verified |
| T2 | **Single-node loss** — kill one Pi (Garage: also kill `ten`) | survives a node death unattended | store stays **read+write**; a velero backup succeeds during the outage; **no manual step** |
| T3 | **pi↔pi partition** — `iptables`-isolate the Pis | the 2026-06-27 failure mode | majority side read+write; minority refuses cleanly; on heal, reconciles with **no data loss/divergence** |
| T4 | **Unclean power loss** — hard-reset a node mid-write | the per-candidate corruption risk | node rejoins and self-heals; **no corruption** (Garage: LMDB snapshot+rebuild; versitygw: Gluster-FUSE consistency) |
| T5 | **Candidate-specific probe** | the named risk | versitygw: etag/multipart integrity across both gateways with **`--sidecar` on Gluster** (regular-file metadata), and a control run with default xattrs to confirm sidecar is the safer mode. Garage: wipe a node's data dir, confirm rf=3 rebuild |
| T6 | **Resource + ops** | fits Pi-class, operable | RAM/CPU on Pi-sized VMs acceptable; document the ops steps + monitoring hook |

Record RPO/RTO per failure and the manual-step count (target: zero for T2/T3).

## Decision rubric

**Hard gates (must pass to qualify):** T1 (all consumers), T2, T3, T4. A finalist
that fails any gate is out regardless of score. **Tiebreak among qualifiers**, in
order: (1) fewest manual steps under failure, (2) smallest production blast
radius / migration risk, (3) operational simplicity + monitoring, (4) project
governance. Document the result as a short decision record appended here.

### Decision record — versitygw track (live Vagrant run, 2026-06-27)

versitygw v1.6.0 on a throwaway 3-VM libvirt rig (n1+n2 data, arb arbiter)
running a stateless gateway per data node over a GlusterFS replica-3-arbiter
volume, **`--sidecar` metadata on Gluster**, **no consul lock**. Measured:

| Gate | Result | Evidence |
|---|---|---|
| T1 S3 multipart | **PASS** | 64 MB multipart PUT via gw1, GET via gw2, sha256 identical |
| T5 sidecar/etag | **PASS** | identical multipart ETag `…-4` on both gateways (shared sidecar) |
| T3 partition | **PASS** | iptables-isolated n1: majority (gw2) stayed read+write; minority refused (`Transport endpoint is not connected`, no split-brain); self-healed on reconnect, same ETag, no data loss |
| T2 node loss | **PASS** | hard-halt n1: gw2 read the 64 MB object (sha match) + wrote a new object; survivor read+write, zero intervention |
| T4 rejoin/no-corruption | **PASS** | n1 rebooted+remounted: Gluster heal drained to 0 entries; gw1 then served the written-while-down object + 64 MB object intact |

**versitygw-over-Gluster clears every hard gate, including T3 — the exact
2026-06-27 failure — staying up on the majority side with no manual step.**

### Decision record — Garage track (live Vagrant run, 2026-06-27)

Garage v2.3.0, same 3 VMs as 3 EQUAL nodes (z1/z2/z3), `replication_factor=3`,
**`db_engine=lmdb`** + `metadata_auto_snapshot_interval`, consistent mode.

| Gate | Result | Evidence |
|---|---|---|
| T1 S3 multipart | **PASS** | 64 MB multipart PUT g1→GET g2, sha match; identical ETag `…-4` across all 3 nodes |
| T3 partition | **PASS** | isolated n1: majority (g2) read+write; minority refused (no quorum); re-synced on heal |
| T2 node loss | **PASS** | hard power-off n1: cluster read+write via g3 (quorum n2+arb) |
| T4 LMDB power-loss | **PASS (beat expectations)** | abrupt power-cut mid-write → n1 rebooted with **zero LMDB corruption/panic in logs**, rejoined HEALTHY, re-synced big.bin + 80 burst objects intact |
| T5 wipe-and-rebuild | **method snag, not a defect** | wiping the data dir removed Garage's `garage-marker`; Garage then **refuses to start** (deliberate mount-safety guard, validated against a UUID in metadata). rf=3 data stayed safe on peers; an in-place rebuild needs the documented marker-restore / node-replace procedure, more involved than Gluster's transparent self-heal |

### Final verdict (both tracks measured live)

Both pass the hard reliability gates (T1–T4). **Garage's T4 cleanly survived the
power cut**, de-risking the evaluation's main worry about it; and its
marker-guard is a genuine safety plus (the prod MinIO setup hand-codes around
exactly that "ran on an unmounted dir" failure). The split is operational, not
reliability: **versitygw-over-Gluster** = smallest change, no 250 GB migration,
**transparent self-heal** of a lost node (proven, drained to 0); **Garage** =
cleaner architecture but a bigger migration, `ten` in the backup quorum, and a
**more hands-on node-replacement** flow. **Recommendation stands: versitygw-over-
Gluster** — equal reliability, lower blast radius, simpler recovery.

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

### Productionization status (versitygw — the winner)

- **DONE** — `playbooks/tasks/versitygw.yml`: stateless gateway, no consul lock,
  `--sidecar` on Gluster, runs on both Pis, bucket bootstrap. ansible-lint clean
  (production profile). Wired into `setup-pi-services.yml` as a **gated** include
  (`vgw_enabled`, default false — current MinIO deploy untouched).
- **DONE** — Vagrant-tested the real `tasks/versitygw.yml` via ansible-playbook
  against a fresh VM (bind-mount standing in for Gluster): caught + fixed a
  missing `/etc/versitygw` dir bug, then applied clean (ok=17, failed=0) —
  versitygw active, 5 buckets, S3 put/get verified.
- **DONE** — keepalived cutover gating (`setup-keepalived.yml`, `vgw_cutover`):
  removes `minio` from the `SERVICES` table and adds a versitygw health check so
  the VIP follows a live gateway (both gateways always run). Default renders the
  current config byte-for-byte; verified via the `bool` filter.
- **DONE — operational cutover executed on prod (2026-06-27):**
  1. ✅ Coexist deploy (`task deploy:versitygw -- -e vgw_port=9001`) — versitygw
     on `:9001` both Pis. Actual data was **17 G** (kopia-deduped), not 250 GB;
     1.6 T free, so capacity was a non-issue.
  2. ✅ Migrate — `mc mirror` MinIO→versitygw, all buckets MATCH on size+count
     (velero 14606, postgres 7765, etcd 28, scylla 1406, pg-dump 0).
  3. ✅ Restore-verify — sample objects byte-identical (SHA-MATCH) across velero/
     postgres/etcd; velero BSL `Available`; a real etcd-backup write succeeded
     through the VIP.
  4. ✅ Cutover — `deploy:keepalived -e vgw_cutover=true` (no flap, VIP stayed
     pi1), stop+disable MinIO, `deploy:versitygw -e vgw_port=9000 -e
     vgw_cutover=true`. VIP `.5:9000`→versitygw, health 200 both Pis. Durable:
     `vgw_enabled`/`vgw_cutover=true` pinned in the pis group vars, Enable-MinIO
     task gated. Commits ops `b74ecee`→`c1df274`.
  5. **Cleanup (remaining follow-up)** — remove the MinIO Phase 4 tasks + the
     consul lock from the playbooks; retire `MinioDualActive`, add a "gateway
     down" alert; clear the stale consul-lock comments in keepalived. (Consul
     itself stays — it's still Vault's storage backend + Patroni's DCS.)
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
