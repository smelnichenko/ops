# Plan 049: Cilium Migration + Pi Services (Forgejo + MinIO)

## Context

Three changes combined into one maintenance window:

1. **Move Forgejo to Pi** -- breaks circular dependency. ArgoCD connects to external git.
2. **Move Velero MinIO to Pi** -- backups survive cluster destruction. Restore works after kubeadm reset.
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

## Execution Order

**No downtime (steps 1-7):**
1. Install Forgejo on Pi
2. Install MinIO on Pi (backup target)
3. Mirror repos from in-cluster Forgejo to Pi
4. Update DNS `git.pmon.dev` -> 192.168.11.4
5. Update ArgoCD apps repoURL to Pi
6. Update Velero backupStorageLocation to Pi MinIO
7. Verify ArgoCD syncs + Velero backup to Pi works

**Maintenance window ~40 min (steps 8-13):**
8. Final Velero backup (to Pi MinIO)
9. kubeadm reset
10. kubeadm init + Cilium install
11. bootstrap.sh (Tier 0) -- Velero points to Pi MinIO
12. Velero restore from Pi MinIO
13. Setup ArgoCD (points to Pi Forgejo)

## Key advantage

After step 7, the cluster can be fully destroyed and rebuilt from:
- Forgejo on Pi (all git repos, ArgoCD source of truth)
- MinIO on Pi (all Velero backups, PVC data)
- Vault on Pi (all secrets)

No data lives exclusively inside the cluster.

## Vagrant Test

vault-pi VM runs: Vault + Forgejo + MinIO
kubeadm VM runs: k8s cluster

Test flow:
1. vagrant up (both VMs)
2. Deploy workloads with PVC data
3. Velero backup to Pi MinIO
4. kubeadm reset + Cilium install
5. Velero restore from Pi MinIO
6. Verify data survived

## Status

- [x] Base nftables rules on production
- [x] Cilium migration test playbook
- [ ] Forgejo on Pi (Vagrantfile + Ansible)
- [ ] MinIO on Pi (Vagrantfile + Ansible)
- [ ] Vagrant end-to-end test
- [ ] Production migration
