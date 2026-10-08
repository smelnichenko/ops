# Disaster Recovery Procedure

## Prerequisites

- Access to the host machine (192.168.11.2)
- Vault Pi (192.168.11.4) running with transit engine
- `/home/sm/src/` has clones of: ops, infra, platform repos
- The Pi backup store (versitygw on the Pi VIP, 192.168.11.5:9000): Velero's backups (bucket `velero`), CNPG's barman
  archive and base backups (`postgres-backups`), the upgrade's Wave 0 backups (`upgrade-backups`)

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

Wait for Forgejo to be ready, then push repos if needed:
```bash
for repo in infra platform ops; do
  cd /home/sm/src/$repo
  git push origin main
done
```

### 5. Setup ArgoCD

```bash
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

If you have a Velero backup and want to restore data (PVCs, secrets):

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
