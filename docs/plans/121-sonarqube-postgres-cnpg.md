# Plan 121 - SonarQube's Postgres on CloudNativePG

**Status:** stage 0 (chart) ready; stages 1-3 not started. Operator's choice 2026-11-17: "a" - move it to CNPG.

## Why

SonarQube's database is a plain `postgres:17-alpine` StatefulSet (`schnappy-sonarqube-postgres`, 150 MB, local-path
volume, reclaim Delete): no backup, no upgrade path. The upgrade cycle's one-way table (`scripts/upgrade-stores.json`)
blocks every Postgres major on it. On CNPG it gets its own cluster (`schnappy-sonarqube-pg`, never production's
database), barman backups to the Pi store as `schnappy-sonarqube-pg18`, and CNPG's upgrade and restore paths.

## Before stage 1

- **The Pis' restore check is pinned to production's server** (ops 486beef7, `pi_restore_check_pg_server`), deployed
  with `task deploy:pi-restore-check`. Without it the check restores whichever server backed up last - SonarQube's at
  01:45, after production's 01:30 - and is red every day while production's backups go unchecked.
- **CI idle.** SonarQube is down for stages 1-2 (a few minutes): every pipeline's Sonar step fails closed in that
  window. Re-run whatever failed after.

## Stages (infra `clusters/production/schnappy-sonarqube/values.yaml`, one commit each)

| stage | values | then |
|---|---|---|
| 0 | platform chart: `sonarqube.replicas`, `postgresReplicas`, `cnpg.*` (all off by default - production's render unchanged but comments) | platform CI green |
| 1 | `replicas: 0`; `cnpg: {enabled, import, backup: true, backupEndpoint, backupServerName: schnappy-sonarqube-pg18, storage local-path}`; `database: statefulset` | the Cluster healthy, its first backup completed, the row counts equal |
| 2 | `replicas` back to 1; `database: cnpg` | SonarQube up on CNPG, one CI analysis green on it |
| 3 | `cnpg.import: false`; `postgresReplicas: 0` | the old StatefulSet at 0 pods, its volume kept |

Stage 1 keeps SonarQube stopped while the import reads, so nothing is written between the copy and the switch (with
both in one sync the old pod could still be committing an analysis when pg_dump's snapshot is taken, and the new pod
crash-loops until the import ends). The setup Job is not rendered while `replicas` is 0 (it would wait 40 minutes for
the API and fail the sync).

Stage 3 matters: with `import: true` left on, any re-creation of the Cluster (a fix, a rebuild, a Velero restore of
schnappy-infra) silently re-imports the StatefulSet's stage-1 data - SonarQube healthy on old data, the setup Job finding
its token, nothing red but the archive check.

**Row counts compared at stage 1** (the StatefulSet's, 2026-11-17, and the CNPG cluster's after the import):
`projects` 20, `users` 1, `user_tokens` 2, `ce_activity` 2281, `issues` 791, `project_measures` 42665.

```
kubectl -n schnappy-infra exec schnappy-sonarqube-postgres-0 -c postgres -- psql -U sonarqube -d sonarqube -Atc "<counts>"
kubectl -n schnappy-infra exec schnappy-sonarqube-pg-1 -c postgres -- psql -d sonarqube -Atc "<counts>"
```

## If the import fails (stage 1)

Expected: the import Job done in about a minute (150 MB). CNPG retries a failed import Job 6 times (no backoffLimit
set), then the Cluster goes `Unrecoverable` after about 10 minutes. Each retry renames PGDATA to `pgdata_<ts>` instead
of deleting it - up to 7 partial copies on ten's disk (local-path ignores the 5Gi).

1. **Nothing to roll back for SonarQube's data:** the StatefulSet is only read, and SonarQube still points at it
   (`database: statefulset`). Revert stage 1's commit (SonarQube back at 1 replica on the StatefulSet).
2. **If Argo does not take the revert:** the sync that created the Cluster may still be Running (waiting on its health,
   no sync timeout set) - auto-sync then skips the new commit. Check
   `kubectl -n argocd get application schnappy-sonarqube -o jsonpath='{.status.operationState.phase}'`; if Running,
   `argocd app terminate-op schnappy-sonarqube --core`. A root sync meanwhile stalls at wave 3 (SonarQube) before
   wave 4's apps - terminate it the same way.
3. **Retry:** the revert does NOT remove the Cluster - the app has no prune (never turned on). Delete it by hand,
   with the operator's OK for that command: `kubectl -n schnappy-infra delete clusters.postgresql.cnpg.io
   schnappy-sonarqube-pg` (its PVC goes with it, and with that the `pgdata_*` copies - local-path deletes the
   directory; check ten's disk after). The import ran with archive_mode off, so nothing reached the store - the same
   server name is fine again. Then stage 1 again.

## Back after stage 2

`database: statefulset` is one value but **not lossless** once SonarQube has written to CNPG: every analysis since
stage 2 is dropped, and forward again does not re-import. Its Elasticsearch index (`schnappy-sonarqube-data`, `data/es8`)
then reflects the newer database - delete `data/es8` to force a reindex. Prefer a fix forward, or a recovery from the
cluster's own backups.

## Recovery from its backups

`cnpg.recovery: true` with `recoveryServerName: schnappy-sonarqube-pg18` bootstraps a new cluster from barman; it then
archives under a NEW `backupServerName` (`schnappy-sonarqube-pg18-2`, ...) - CNPG archives into an empty one only, and
the chart refuses the same name. Not yet drilled: the drill is the open item after stage 3.

## Left after stage 3

- The StatefulSet and its PVC removed - a stateful delete, the operator's OK first.
- The restore drill (above); then the one-way table's Postgres entry drops SonarQube's missing part.
