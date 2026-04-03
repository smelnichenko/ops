# Plan 049: Cilium Migration + Forgejo on Pi

## Context

Two changes combined:

1. **Move Forgejo to Vault Pi (192.168.11.4)** -- breaks circular dependency (ArgoCD needs Forgejo, Forgejo was ArgoCD-managed). Forgejo on Pi survives cluster destruction. Pi has 8GB RAM, 2TB NVMe.
2. **Migrate Calico to Cilium** -- via kubeadm reset + Velero restore (not in-place swap). First attempt at in-place swap failed catastrophically.

## Architecture Change

```
Before:
  Pi (192.168.11.4): Vault + Nexus
  ten (192.168.11.2): kubeadm (Calico, kube-proxy, Forgejo in-cluster)
  ArgoCD -> forgejo-http.forgejo.svc:3000

After:
  Pi (192.168.11.4): Vault + Nexus + Forgejo
  ten (192.168.11.2): kubeadm (Cilium, no kube-proxy, no Forgejo)
  ArgoCD -> 192.168.11.4:3000 (survives cluster death)
```

## Execution Order

**No downtime (steps 1-6):**
1. Install Forgejo on Pi
2. Mirror all repos from in-cluster Forgejo to Pi
3. Update DNS `git.pmon.dev` -> 192.168.11.4
4. Update ArgoCD apps to use Pi URL
5. Verify ArgoCD syncs from Pi Forgejo
6. Remove in-cluster Forgejo

**Maintenance window ~40 min (steps 7-12):**
7. Velero backup
8. kubeadm reset (PVC data survives on disk)
9. kubeadm init --skip-phases=addon/kube-proxy + Cilium install
10. bootstrap.sh (Tier 0) + Velero restore
11. Setup ArgoCD (points to Pi Forgejo)
12. Verify everything

## Safeguards

- Base nftables rules in /etc/nftables.conf (SSH survives CNI removal)
- Never `nft flush ruleset` -- only delete specific CNI tables
- Full Vagrant test before production (Forgejo on vault-pi VM + Cilium migration)
- Forgejo on Pi = ArgoCD works even during cluster rebuild

## Status

- [x] Base nftables rules on production
- [x] Cilium migration test playbook created
- [ ] Forgejo on Pi (Ansible playbook)
- [ ] Vagrant end-to-end test
- [ ] Production migration
