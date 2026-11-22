# CNPG Postgres: from the bullseye image line to trixie (18.6 -> 18.7)

Status: DONE 2026-11-22 (operator 2026-11-21: "switchover, by hand, separate plan later"): every step, below.

## Why

Every database runs `ghcr.io/cloudnative-pg/postgresql:18.6-system-bullseye`. CloudNativePG stopped that Debian 11 line at
18.6: 18.7 exists only as `-bookworm` and `-trixie` (read from ghcr.io, 12 040 tags, 2026-11-21). Renovate keeps an image's
suffix, so it offers nothing - the databases would never get another patch release, and nothing would say so
(`task upgrade:check` lists the image as current). Found checking `upgrade:check` against production.

## Production now (read live, 2026-11-21)

| cluster | namespace | instances | backups | extensions beyond plpgsql |
|---|---|---|---|---|
| schnappy-production-postgres | schnappy-production | 2 | barman, `s3://postgres-backups/` | pg_stat_statements 1.12 (all), pg_trgm 1.6 + vector 0.8.6 (masi) |
| schnappy-test-postgres | schnappy-test | 1 | archiving on | pg_trgm 1.6 + vector 0.8.6 (masi) |
| woodpecker-postgres | woodpecker | 1 | barman | - |
| schnappy-sonarqube-pg | schnappy-infra | 1 | barman | - |
| schnappy-grafana-pg | schnappy-infra | 1 | barman | - |

All: `primaryUpdateStrategy: unsupervised`, `primaryUpdateMethod: restart`, continuous archiving True; operator
`cloudnative-pg` 1.30.1.

| image | PostgreSQL | OS / glibc | barman-cloud | pgvector |
|---|---|---|---|---|
| now `18.6-system-bullseye@sha256:899d3ed5…` | 18.6 | Debian 11, 2.31 | 3.19.1 | 0.8.6 |
| target `18.7-system-trixie@sha256:b4bbd2e6…` | 18.7 | Debian 13 (as ten), 2.41 | 3.20.1 | 0.8.7 (+ `vector--0.8.6--0.8.7.sql`) |

**Why `system-`:** the clusters back up with the in-tree `barmanObjectStore`, which needs barman-cloud inside the image;
the `minimal`/`standard` lines leave it to CNPG's barman-cloud plugin. Moving to the plugin is a change of its own, not
part of this one.

## The glibc change and the indexes

A new glibc can sort text differently, and an index built under the old order is then silently wrong until rebuilt.
**It does not apply here:** every database is `datlocprovider = c`, `datcollate = C`, `datctype = C`, and no column
names another collation (counted in every database of all five clusters, 2026-11-21). `C` compares bytes, whatever the
glibc - no `REINDEX`. Read again right before the change (below); if anything but C turns up, the plan stops.

```sql
select datname, datlocprovider, datcollate, datctype from pg_database where datallowconn;
-- per database: columns with an explicit collation other than default/C
select count(*) from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
 where a.attcollation not in (0, 100, 950) and n.nspname not in ('pg_catalog', 'information_schema') and a.attnum > 0;
```

## Where the image is named (all move to the same digest)

- infra `clusters/production/schnappy-production-data/values.yaml` (`imageName`)
- infra `clusters/production/schnappy-test-data/values.yaml` (`imageName`)
- infra `clusters/production/woodpecker/manifests/postgres.yaml` (`imageName`)
- platform `helm/schnappy-data/values.yaml` (`imageName` default and `ephemeralImage`)
- platform `helm/schnappy-observability/values.yaml` (Grafana's, `imageName`)
- platform `helm/schnappy-sonarqube/values.yaml` (SonarQube's, `imageName`)
- ops `deploy/ansible/playbooks/setup-pi-restore-check.yml` (the Pi restore check restores production's base backups with
  it - moved with production in step 5 and applied by its playbook (setup-pi-restore-check.yml), the operator
  approving the Pi run; a restore of an 18.7 backup by the 18.6 image would still work - same major - but drifts)

## Steps

1. **The copy first.** A full Vagrant copy run with the target image: every cluster up on 18.7, the apps healthy, a
   base backup taken and restored. Then **the way back rehearsed on the copy**: the image back to 18.6-bullseye, the
   clusters up and healthy again - before production moves, the return path is proven, not assumed.
2. **The test environment** (one instance - down for its restart, ~1 min): infra test values. Checked as below.
   **Done 2026-11-22.** Step 1 on the copy, both ways rc 0: production's and Grafana's clusters (the copy has no
   Woodpecker, SonarQube or test cluster) on 18.7, every database libc C/C with no non-C column collation, a base
   backup restored into a side cluster on the 18.7 image (10 000 rows, md5 equal, WAL replayed), the inventory
   differing by the image only; back on 18.6 with every check green. The copy's GitOps mirror refuses a change to
   what its overlay drops - the test environment's values - as untested, so that line moved on its own in step 2.
   Step 2 at 13:03 (infra eef8431, the image pre-pulled on ten): the instance restarted on 18.7 in about a minute,
   no container restart, the collations unchanged, ContinuousArchiving True and two segments archived after it
   (no new failure), pgvector still 0.8.6 in masi and answering, the test apps Synced/Healthy with no database
   error; ArgoCDAppDegraded went pending for the restart and cleared. The test environment takes no scheduled
   backup, so that check waits for production.
3. **Woodpecker's database** (CI down for ~1 min): with the CI queue empty.
   **Done 2026-11-22 13:23** (infra 04014ce, `[CI SKIP]`: an infra pipeline would have run on the Woodpecker whose
   database restarted - infra's checks and a kubeconform of the manifest ran locally; the queue was empty): 18.7,
   collations unchanged, a segment archived after the restart, an on-demand base backup on 18.7, Woodpecker's API
   answering from its database.
4. **SonarQube's and Grafana's** (one instance each, ~1 min each): platform values.
   **Done 2026-11-22 14:02** (platform 679ce50, `[CI SKIP]`: its Sonar step would have run against the restarting
   SonarQube - the charts' lint and render checks ran locally, the production values rendering 18.7 for both):
   18.7, collations unchanged, archiving on after the restarts, an on-demand base backup of each on 18.7, SonarQube
   UP and Grafana's database ok; ArgoCDAppDegraded pending for the restarts, then clear.
5. **Production**, last. First, production's primary set to update by **switchover** (decided): `primaryUpdateMethod:
   switchover` named in platform's `helm/schnappy-data/templates/cnpg-cluster.yaml`, and `.spec.primaryUpdateMethod` taken
   out of the `schnappy-data-envs` Argo application's ignoreDifferences in infra (it is ignored there because CNPG's
   webhook fills the default, `restart` - left ignored, git's value would never reach the cluster); the live spec read back
   as `switchover` before anything else. It changes nothing by itself and stays for every later minor. Then a base backup,
   verified
   (`task deploy:postgres:base-backup -- -e pg_namespace=schnappy-production -e cluster=schnappy-production-postgres`);
   then the image. CNPG restarts the replica on the new image, promotes it (writes pause for a few seconds, connections
   reset once), then restarts the old primary as the new replica.
   **Done 2026-11-22.** platform ea43669 (the template's `primaryUpdateMethod: switchover`, the chart's own defaults
   on 18.7) then infra e470f1b (the ignoreDifferences entry gone; the live spec read back `switchover`, nothing
   restarted); a verified base backup; infra f98c524, the image: CloudNativePG upgraded the replica (12:27:53 UTC),
   switched over to it (12:28:09 - writes paused for seconds, each app's connections reset once, their errors all in
   that minute) and upgraded the old primary as the new replica (12:28:28). Both 18.7, replication streaming, the
   collations unchanged, archiving on the new timeline (one failure at the promotion instant, none after), a base
   backup on 18.7, the alerts clear. The Pi restore check followed production (ops 07649a93 - its harness wants the
   playbook's image equal to production's recorded one), deployed on both Pis, and pi1 restored the 18.7 base backup
   in the 18.7 image by hand (every part restored).
6. **After a day's soak:** `ALTER EXTENSION vector UPDATE` in masi's database (test, then production) - not before:
   pgvector has no downgrade script, so it is the step that closes the way back.
   **Done 2026-11-22 16:0x, without the soak** (operator: "finish with CNPG now without soaking"): masi's database is
   the only one with pgvector (test, production); `ALTER EXTENSION vector UPDATE` took both from 0.8.6 to 0.8.7. On
   production, after it: 5206 face embeddings (vector(512), no HNSW/IVFFlat index), each norm 1, a nearest-neighbour
   search answering (itself at 0, then 0.710, 0.732, ...), masi without a vector or SQL error. The way back to 18.6 is
   closed from here.

Each step is checked before the next: `select version()` says 18.7; the collation query above unchanged; the cluster's
`ContinuousArchiving` condition True and a WAL segment archived after the restart; the next scheduled backup succeeds;
the apps' error rates and alerts as before.

## The way back

`imageName` back to `18.6-system-bullseye@sha256:899d3ed5…`: a minor downgrade within PostgreSQL 18 reads the same data
files, and `C` makes the glibc irrelevant. Open until step 6 (pgvector's catalog update), rehearsed in step 1.

## After

Renovate keeps the new suffix, so 18.8-system-trixie and on arrive as ordinary upgrade-cycle units (minors); a major
stays one-way (the store table's Postgres store, the CNPG image).

## Decisions (operator 2026-11-21)

1. Production's primary updates by **switchover** - set permanently (step 5), so this and every later minor costs
   seconds of writes, not a minute. The other four clusters have one instance: they restart.
2. **By hand**, step by step as above - not as a hand-made upgrade-cycle unit (the cycle applies a unit in one merge
   and is built around Renovate's version units; this is a one-off switch of image line, staged cluster by cluster).
   Later 18.x-system-trixie minors come through the cycle as ordinary units.
3. CNPG's barman-cloud plugin and the `standard` image line: **a plan of its own, later** - before a CloudNativePG
   upgrade removes the in-tree barman support.
