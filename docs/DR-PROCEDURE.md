# Disaster Recovery Procedure

## Prerequisites

- Access to the host machine (192.168.11.2)
- Vault Pi (192.168.11.4) running with transit engine
- `/home/sm/src/` has clones of: ops, infra, platform repos
- Velero MinIO backup at `/mnt/backups/minio` (if restoring data)

## Full Cluster Rebuild

### 1. Install Kubernetes

```bash
cd /home/sm/src/ops
task deploy:kubeadm
```

### 2. Bootstrap Tier 0 (Pre-GitOps)

```bash
./bootstrap.sh all
```

This installs: cert-manager, porkbun-webhook, external-secrets, Istio, Velero, cluster-config.

### 3. Setup Vault

```bash
task deploy:vault-pi   # If Pi needs setup
task deploy:vault       # Vault HA in cluster
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

### 6. Verify

```bash
kubectl get apps -n argocd
# Wait for all 20 apps to show Synced + Healthy
```

## Restore from Velero Backup

If you have a Velero backup and want to restore data (PVCs, secrets):

### After Step 2 (Tier 0 installed), before Step 4:

```bash
# Restore Velero MinIO backup pod first
kubectl apply -f /home/sm/src/infra/clusters/production/cluster-config/velero-minio-deployment.yaml

# Wait for MinIO to be ready
kubectl wait --for=condition=Ready pods -l app=minio-backup -n velero --timeout=120s

# List available backups
velero backup get

# Restore full cluster
velero restore create --from-backup full-weekly-latest

# Or restore specific namespace
velero restore create --from-backup velero-schnappy-daily-YYYYMMDD --include-namespaces schnappy
```

Then continue with Steps 3-5.

## Component-Only Recovery

If only specific components are down:

```bash
# Single Tier 0 component
./bootstrap.sh cert-manager
./bootstrap.sh istio
./bootstrap.sh velero

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
| 0 | cert-manager, ESO, Istio, Velero, cluster-config | bootstrap.sh |
| 0 | Vault, Forgejo, ArgoCD | Ansible (task deploy:*) |
| 1 | schnappy-production-{apps,data,mesh}, schnappy-test-{apps,data,mesh} | ArgoCD |
| 1 | schnappy-observability, schnappy-sonarqube | ArgoCD |
| 1 | Woodpecker, Prometheus | ArgoCD |
