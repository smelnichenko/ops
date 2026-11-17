# Plan 121 - SonarQube's Postgres on CloudNativePG

**Status:** stage 0 (chart: platform f7c2180, d1060e5) on main; stages 1a-3 not started. Operator's choice 2026-11-17:
"a" - move it to CNPG. Reviewed twice (2026-11-17); the second review's findings are folded in below.

## Why

SonarQube's database is a plain `postgres:17-alpine` StatefulSet (`schnappy-sonarqube-postgres`, 150 MB, local-path
volume, reclaim Delete): no backup, no upgrade path. The upgrade cycle's one-way table (`scripts/upgrade-stores.json`)
blocks every Postgres major on it. On CNPG it gets its own cluster (`schnappy-sonarqube-pg`, never production's
database), barman backups to the Pi store as `schnappy-sonarqube-pg18`, and CNPG's upgrade and restore paths.

## Before stage 1a

- **The Pis' restore check is pinned to production's server** (ops 486beef7, `pi_restore_check_pg_server`), deployed
  with `task deploy:pi-restore-check`. Without it the check restores whichever server backed up last - SonarQube's at
  01:45, after production's 01:30 - and is red every day while production's backups go unchecked.
- **CI idle.** SonarQube is down from stage 1a to stage 2 (minutes): every pipeline's Sonar step fails closed in that
  window. Re-run whatever failed after.

## Stages (infra `clusters/production/schnappy-sonarqube/values.yaml`, one commit each)

| stage | values | then |
|---|---|---|
| 0 | platform chart: `sonarqube.replicas`, `postgresReplicas`, `cnpg.*` (all off by default - production's render unchanged) | platform CI green |
| 1a | `replicas: 0` | SonarQube's pod gone; its compute-engine queue was empty (no analysis running) |
| 1b | `cnpg: {enabled, import, backup: true, backupEndpoint, backupServerName: schnappy-sonarqube-pg18, storage local-path}`; `database: statefulset` | the Cluster healthy, its first backup completed, the row counts equal |
| 2 | `replicas` back to 1; `database: cnpg` | SonarQube up on CNPG, one CI analysis green on it |
| 3 | `cnpg.import: false`; `postgresReplicas: 0` | the old StatefulSet at 0 pods, its volume kept |

1a before 1b: Argo applies the Deployment and the Cluster in one wave with no wait, and the import's pg_dump could start
inside SonarQube's 30 s shutdown - an analysis committed after the snapshot would be lost (the row counts catch new rows,
not updates). The setup Job is not rendered while `replicas` is 0 (it would wait 40 minutes for the API and fail the
sync).

Stage 3 matters: with `import: true` left on, any re-creation of the Cluster silently re-imports the StatefulSet's
stage-1 data - SonarQube healthy on old data, nothing red but the archive check. After stage 3 a re-creation would be an
empty database (initdb): **the Cluster is re-created only by a recovery** (below), never by deleting it and letting Argo
make it again.

**Row counts compared at stage 1b** (the StatefulSet's, 2026-11-17, and the CNPG cluster's after the import):
`projects` 20, `users` 1, `user_tokens` 2, `ce_activity` 2281, `issues` 791, `project_measures` 42665. The counts are
the only guard against an empty import (CNPG's microservice import returns success when its dump directory cannot be
made).

```
kubectl -n schnappy-infra exec schnappy-sonarqube-postgres-0 -c postgres -- psql -U sonarqube -d sonarqube -Atc "<counts>"
kubectl -n schnappy-infra exec schnappy-sonarqube-pg-1 -c postgres -- psql -d sonarqube -Atc "<counts>"
```

## Argo, at any stage

Argo v3.5.4 reports no health for CNPG's kinds, so stage 1b's operation ends at apply. Two cases stop the way back:

- **Running** (stage 2: the PostSync setup Job waits for SonarQube's health - a SonarQube that never becomes Ready on
  CNPG keeps the operation Running): auto-sync skips a revert commit, and a root sync stalls at wave 3 (SonarQube) before
  wave 4's apps. Check `kubectl -n argocd get application schnappy-sonarqube -o jsonpath='{.status.operationState.phase}'`;
  Running → `argocd app terminate-op schnappy-sonarqube --core` (root the same way if it waits on it).
- **Failed** (a CNPG webhook refusing the Cluster - failurePolicy Fail - while `replicas: 0` landed): auto-sync does not
  retry a failed revision until the next commit. Fix the values, or re-sync by patching the Application's `.operation`
  (memory: manual Argo sync = patch .operation).

## If stage 1b fails

Expected: the import Job done in about a minute (150 MB). CNPG retries a failed import Job 6 times, then the Cluster
goes `Unrecoverable` after about 10 minutes; each retry renames PGDATA to `pgdata_<ts>` instead of deleting it (up to 7
partial copies on ten's disk - local-path ignores the 5Gi).

1. **Nothing to roll back for SonarQube's data:** the StatefulSet is only read and SonarQube still points at it.
   Revert 1b and 1a (SonarQube back at 1 replica on the StatefulSet). See "Argo, at any stage" if the revert does not
   apply.
2. **Retry, in this order - never while stage 1b is still in git** (selfHeal re-creates the Cluster at once, racing the
   deletion of the old PVC of the same name):
   1. the revert synced;
   2. with the operator's OK for these commands: `kubectl -n schnappy-infra delete clusters.postgresql.cnpg.io
      schnappy-sonarqube-pg` (its PVC and the `pgdata_*` copies go with it - check ten's disk after) and
      `kubectl -n schnappy-infra delete scheduledbackups.postgresql.cnpg.io schnappy-sonarqube-pg-daily` (no
      ownerReference: it would survive, and keeping its last check time it never fires `immediate` again - the first
      backup would slip to 01:45);
   3. the ExternalSecrets `schnappy-sonarqube-pg-owner`, `schnappy-sonarqube-pg-backup-store` and the NetworkPolicy
      `schnappy-sonarqube-pg` (the app has no prune: left, it stays OutOfSync and ArgoCDAppOutOfSync fires).
3. **The server name:** fine again only if the instance never archived (a failed import runs with archive_mode off). If
   the Cluster was ever healthy, its WAL is in `schnappy-sonarqube-pg18/`: the next cluster's empty-archive check fails
   (no backups, PostgresArchivingFailed). Use a new `backupServerName` (`schnappy-sonarqube-pg18-2`), or empty that
   prefix through a reviewed playbook (never by hand on the store).
4. Stage 1a and 1b again.

## Back after stage 2

`database: statefulset` is one value but **not lossless** once SonarQube has written to CNPG: every analysis since
stage 2 is dropped, and forward again does not re-import. Its Elasticsearch index (`schnappy-sonarqube-data`, `data/es8`)
then reflects the newer database - delete `data/es8` to force a reindex. Prefer a fix forward, or a recovery from the
cluster's own backups. A Running operation: "Argo, at any stage".

## Recovery from its backups

CNPG reads `bootstrap` only when it creates a Cluster - flipping the values on a live one restores nothing, and its new
`backupServerName` would start archiving mid-timeline with no base backup. The steps:

1. SonarQube to 0 (`replicas: 0`), synced.
2. With the operator's OK: delete the ScheduledBackup and the Cluster (its PVC with it - the live data goes).
3. `cnpg.recovery: true`, `recoveryServerName: schnappy-sonarqube-pg18` (the generation's archive), a NEW
   `backupServerName` (`schnappy-sonarqube-pg18-2`, ...: CNPG archives into an empty one only - the chart refuses the
   same name); `import: false`.
4. The Cluster healthy; the row counts; its first backup under the new name.
5. SonarQube back to 1. The recovered database holds the `ci` token as it was at the backup: revoke it and let the setup
   Job make a new one into Vault's woodpecker-ci (`sonar_token`), or CI's Sonar steps fail on a token Vault no longer
   matches.

Not yet drilled: the drill is the open item after stage 3 (the chart's recovery render is checked in platform CI -
database, owner, the -owner secret, the store's egress with backups off).

## Notes

- **Password rotation now reaches the database.** CNPG reconciles `sonarqube`'s password from the `-owner` secret
  (Vault's `postgres_password`) within ~15 minutes, but SonarQube reads it only at its start: after a rotation in Vault,
  restart SonarQube once the secret has refreshed, or its new connections fail. (The StatefulSet never changed its
  password after initdb.)
- An Application deleted never takes the database: the Cluster carries `Prune=false,Delete=false`.

## Left after stage 3

- The StatefulSet and its PVC removed - a stateful delete, the operator's OK first.
- The restore drill (above); DR-PROCEDURE's CNPG section names SonarQube's cluster; then the one-way table's Postgres
  entry drops SonarQube's missing part.
