# Plan 049: Cilium Migration + Pi Services (Forgejo + MinIO)

## Context

Three changes combined into one maintenance window:

1. **Move Forgejo to Pi** -- breaks circular dependency. ArgoCD connects to external git.
2. **Move Velero MinIO to Pi** -- backups survive cluster destruction.
3. **Migrate Calico to Cilium** -- via kubeadm reset + Velero restore.

## Architecture Change

```
Before:
  Pi (192.168.11.4): Vault + Nexus
  ten (192.168.11.2): kubeadm (Calico, kube-proxy, Forgejo, MinIO backup)

After:
  Pi (192.168.11.4): Vault + Nexus + Forgejo + MinIO (backup)
  ten (192.168.11.2): kubeadm (Cilium, no kube-proxy)

Pi resource budget (8GB RAM):
  Vault ~200MB + Nexus ~1GB + Forgejo ~300MB + MinIO ~200MB = ~1.7GB
```

## Data Backup Strategy

**Postgres:** pg_dump to Pi MinIO (application-consistent, not FSBackup)
- Dump all databases before migration
- After restore, import dump into fresh Postgres
- Velero FSBackup of raw Postgres data files is unreliable (init container reinitializes)

**Keycloak:** uses Postgres -- covered by pg_dump

**Other PVCs (Elasticsearch, Mimir, Grafana, Tempo):** Velero FSBackup
- These don't have init containers that reinitialize data
- `backup.velero.io/backup-volumes: data` annotation on all stateful pods

**Forgejo:** on Pi -- survives cluster destruction, no backup needed

**Vault:** on Pi -- survives cluster destruction

## Execution Order

**No downtime (steps 1-7):**
1. Install Forgejo on Pi
2. Install MinIO on Pi (backup target)
3. Mirror repos from in-cluster Forgejo to Pi
4. Update DNS `git.pmon.dev` -> 192.168.11.4
5. Update ArgoCD apps repoURL to Pi
6. Update Velero backupStorageLocation to Pi MinIO
7. Verify ArgoCD syncs + Velero backup to Pi works

**Maintenance window ~40 min (steps 8-14):**
8. pg_dump all databases to Pi MinIO
9. Final Velero backup (to Pi MinIO)
10. kubeadm reset
11. kubeadm init + Cilium install
12. bootstrap.sh (Tier 0) + Velero restore (excludes infra namespaces)
13. Import pg_dump into fresh Postgres
14. Setup ArgoCD (points to Pi Forgejo)

## Postgres Dump/Restore

**Before migration:**
```bash
# Dump all databases to Pi MinIO
kubectl exec deploy/schnappy-postgres -- pg_dumpall -U postgres | \
  mc pipe pi/velero/pg-dump/pre-migration.sql
```

**After migration:**
```bash
# Postgres starts fresh (empty), import dump
mc cat pi/velero/pg-dump/pre-migration.sql | \
  kubectl exec -i deploy/schnappy-postgres -- psql -U postgres
```

## Vagrant Test

vault-pi VM: Vault + Forgejo + MinIO
kubeadm VM: k8s cluster

Test flow:
1. vagrant up (both VMs)
2. Deploy Postgres, insert test data
3. pg_dump to Pi MinIO
4. Velero backup (non-Postgres PVCs)
5. kubeadm reset + Cilium install
6. bootstrap.sh + Velero restore
7. Import pg_dump
8. Verify test data survived
9. Authenticate with Keycloak (if deployed)
10. Verify ArgoCD syncs from Pi Forgejo

## Safeguards

- Base nftables rules (SSH survives CNI removal)
- Never `nft flush ruleset`
- pg_dump for Postgres (not FSBackup)
- Full Vagrant test before production
- Forgejo + MinIO + Vault on Pi = everything recoverable

## Status

- [x] Base nftables rules on production
- [x] Vagrantfile: Forgejo + MinIO on vault-pi
- [x] Velero backup annotations on all stateful pods
- [ ] pg_dump based backup/restore in test
- [ ] Keycloak auth verification in test
- [ ] ArgoCD sync verification in test
- [ ] Full clean Vagrant test pass
- [ ] Production migration
