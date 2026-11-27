# Disaster Recovery Procedure

## Prerequisites

- Access to the host machine (192.168.11.2)
- Vault Pi (192.168.11.4) running with transit engine
- `/home/sm/src/` has clones of: ops, infra, platform repos
- The Pi backup store (versitygw on the Pi VIP, 192.168.11.5:9000): Velero's backups (bucket `velero`), CNPG's barman
  archive and base backups (`postgres-backups`), Kafka's nightly dumps (`kafka-backups`), ClickHouse's logs backups
  (`clickhouse-backups`), Scylla Manager's (`scylla-backups`); nothing writes the retired upgrade tooling's Wave 0
  bucket (`upgrade-backups`) any more

## Full Cluster Rebuild

### 1. Install Kubernetes

```bash
cd /home/sm/src/ops
task deploy:kubeadm
```

### 2. Tier 0

Nothing to run here: production's inventory sets `platform_by_argo`, so `setup-kubeadm.yml` leaves cert-manager, the
porkbun webhook, External Secrets, Istio and Velero to Argo CD (step 5), which installs them in its sync waves.

### 3. Setup Vault

Pi Vault runs on both Pis with a Consul backend (no in-cluster Vault).

```bash
task deploy:vault-pi    # Pi Vault — Consul backend, Shamir + vault-unseal.service
task deploy:seed-vault  # Populate secrets from .env
```

### 4. Setup Forgejo (Git Forge)

```bash
task deploy:pi-services
```

Then Woodpecker CI's Forgejo account (non-admin `woodpecker-ci`) and its tokens in Vault - re-run it after any Vault
restore too: a restored `woodpecker-ci` may hold tokens a later run deleted in Forgejo. Then hand CI the new tokens at
once (External Secrets refreshes hourly otherwise):

```bash
task deploy:ci-bot
ssh ten 'sudo kubectl annotate externalsecret woodpecker-ci-secrets-es -n woodpecker force-sync=$(date +%s) --overwrite'
ssh ten 'sudo kubectl annotate externalsecret forgejo-registry-es -n woodpecker force-sync=$(date +%s) --overwrite'
```

Wait for Forgejo to be ready, then push repos if needed:
```bash
for repo in infra platform ops; do
  cd /home/sm/src/$repo
  git push origin main
done
```

### 5. Setup ArgoCD

Argo CD's Forgejo account first - after the push (it derives what Argo CD reads from infra's main on Forgejo) and before
setup-argocd (which gives the repo-creds Secret the reader's token from Vault: Argo CD clones the private infra before
it installs External Secrets). Nothing to force-sync: Argo CD and External Secrets do not exist yet - their
ExternalSecrets take Vault's token when Argo CD makes them.

```bash
task deploy:argocd-reader   # Argo CD's Forgejo account (argocd-reader) and its token in Vault
task deploy:argocd
```

ArgoCD connects to Forgejo and syncs all Tier 1 apps automatically via the root app-of-apps.

Then External Secrets' login to the Pi Vault - the one thing Argo cannot make: Vault's Kubernetes auth written for this
cluster (its API server and CA - a rebuilt cluster has a new CA) and Vault's CA in `external-secrets/vault-pi-ca`, once
Argo has installed External Secrets (its namespace exists). It refuses a kube context on another cluster than
`https://192.168.11.2:6443` and proves the login by refreshing one ExternalSecret:

```bash
task deploy:vault-eso
```

### 6. Verify

```bash
kubectl get apps -n argocd
# Wait for all 20 apps to show Synced + Healthy
```

## Restore from Velero Backup

If you have a Velero backup and want to restore Kubernetes objects (secrets, config): Velero holds manifests only -
no volume data (production's PVs are local-path hostPath, which its file-system backup never copies). The data comes
back from its own backups: CNPG's object store, Scylla Manager, Kafka's dumps (below), ClickHouse's backups (restored as
`tests/ansible/copy/clickhouse-restore-check.yml` does), the Pis' tier-0 backup.

### After Step 5 (Argo CD has installed Velero):

Velero's backup location is the Pi store (bucket `velero` at 192.168.11.5:9000) - there is no store to bring up first.

```bash
# List available backups
velero backup get

# Restore full cluster
velero restore create --from-backup full-weekly-latest

# Or restore specific namespace
velero restore create --from-backup velero-schnappy-daily-YYYYMMDD --include-namespaces schnappy
```

Postgres is not restored this way - CNPG recovers it from its own barman backup (below).

A restore brings back objects git no longer renders but the backup held (the mesh apps and data apps do not prune):
they return with their Argo tracking id, and the app shows OutOfSync with them marked requiresPruning. List them and
delete each by kind and name - never by label or a name pattern: names repeat across kinds (`schnappy-production-kafka`
is the broker's StrimziPodSet, Service, Secret and ServiceAccount too). Hooks (a completed Sync Job) are listed too and
are Argo's own - leave them.

```bash
kubectl -n argocd get applications -o json | jq -r '.items[] | .metadata.name as $a | .status.resources[]?
  | select(.requiresPruning and (.hook | not)) | "\($a) \(.kind) \(.namespace)/\(.name)"'
```

## Postgres from its barman backup (CNPG)

A recovery bootstraps a new Cluster from the barman archive in the Pi store; it never changes a running one. The
Cluster and its PVCs must be gone first (local-path, reclaim Delete: the live data with them - the operator's decision).
In infra's `clusters/production/schnappy-production-data/values.yaml`, under `cnpg:`:

- `recovery: true` - the Cluster bootstraps from the archive (`bootstrap.recovery`) instead of `initdb`.
- `recoveryServerName` - the archive it reads. Before the PostgreSQL 18 upgrade (upgrade step 47) it is the cluster's
  own name, `schnappy-production-postgres`; from that step on the values set `schnappy-production-postgres-pg18`
  (pg_upgrade starts the new major at timeline 1 under the new name; 17's history stays under the old one).
- `backupServerName` - where the recovered cluster archives. CNPG archives only into an empty server name: set a new
  one (for example `schnappy-production-postgres-pg18-r1`) before the recovered cluster starts.

Rehearsed in Vagrant: `task test:dr` recovers Postgres on the image production's Cluster runs
(`scripts/production-cnpg-image.py`; `TEST_PG_IMAGE=` for another).

The other CNPG clusters back up to the same bucket under names of their own, and recover the same way:

- **SonarQube** (`schnappy-sonarqube-pg`, infra's `clusters/production/schnappy-sonarqube/values.yaml`, `sonarqube.cnpg`):
  `recovery`, `recoveryServerName: schnappy-sonarqube-pg18`, a new `backupServerName`; SonarQube at 0 replicas first,
  and its `ci` token revoked after (the setup Job writes a new one to Vault) - plan 121's "Recovery from its backups".
  Never re-created by deleting the Cluster: with `import` off that is an empty database.
- **Grafana** (`schnappy-grafana-pg`, archive `schnappy-grafana-pg18`, Grafana's database since 2026-11-18): re-created
  empty is acceptable (every dashboard and datasource is provisioned); users come back through OAuth.
- **Woodpecker** (`woodpecker-postgres`, infra's `clusters/production/woodpecker/manifests/postgres.yaml`, archive
  `woodpecker-postgres-pg18`): a `bootstrap.recovery` from that server name, archiving under a new one.

## Kafka from its dumps

Kafka's topics are dumped to the Pi store each night at 02:30 UTC (platform's `kafka-backup.yaml`, bucket
`kafka-backups`, the newest 7 complete dumps kept): every partition's messages, the topics' descriptions, the consumer
groups' offsets. The Strimzi Kafka comes back from git (Argo CD) with its KafkaTopics, empty; the messages from a dump:

1. The services that consume the topics stopped (a live consumer group refuses the restore - they would read a week of
   history again), Kafka at the version that ran, its topics there and empty.
2. `task deploy:kafka:restore -- -e kafka_dump=newest` (or a dump's UTC timestamp; `-e "kafka_topics='<t> <t>'"` for some
   topics alone; a dump older than one holding messages needs `-e kafka_allow_older=true`). It holds the nightly dump off
   for its span, pins its source dump and every complete dump newer than it, produces the messages back (a keyed message
   on its partition again), moves the dump's groups to the topics' end, writes the store's BASELINE for the topics it
   restored, then dumps the restored Kafka.
3. The services started again. Once Kafka is whole and its services run on it, each dump it pinned (its last line names
   them): `task deploy:kafka-backup-unpin -- -e kafka_dump=<it>` - the prune keeps the newest complete dumps again.

A restore that failed keeps its lock (`<namespace>-kafka-backup-restoring`): every nightly dump refuses while it is there
(KafkaBackupRestoreLockStale says so - its runbook). Rehearsed on the copy: `task test:copy:kafka-restore`.

## Component-Only Recovery

If only specific components are down:

```bash
# A Tier 0 component (cert-manager, Istio, External Secrets, Velero): Argo CD's - a hard refresh of root (below)

# Forgejo only
task deploy:pi-services

# ArgoCD only
task deploy:argocd

# Let ArgoCD heal Tier 1
kubectl annotate app root -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## Backup Schedule

| Schedule | Time | Scope | Retention |
|----------|------|-------|-----------|
| schnappy-daily | 02:00 UTC | schnappy namespace | 7 days |
| full-weekly | Sunday 03:00 UTC | all namespaces | 30 days |

## Manual Backup

```bash
kubectl create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: full-manual-$(date +%Y%m%d)
  namespace: velero
spec:
  includedNamespaces: ["*"]
  defaultVolumesToFsBackup: true
  ttl: 720h
EOF
```

## Tier Architecture

| Tier | Components | Deployed By |
|------|-----------|-------------|
| 0 | cert-manager, ESO, Istio, Velero, cluster-config | ArgoCD (its early sync waves) |
| 0 | Vault, Forgejo, ArgoCD | Ansible (task deploy:*) |
| 1 | schnappy-production-{apps,data,mesh}, schnappy-test-{apps,data,mesh} | ArgoCD |
| 1 | schnappy-observability, schnappy-sonarqube | ArgoCD |
| 1 | Woodpecker, Prometheus | ArgoCD |
