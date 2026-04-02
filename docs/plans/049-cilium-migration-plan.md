# Plan 049: Cilium Migration (Retry with Full Vagrant Test)

## Context

First attempt at in-place Calico->Cilium migration on production failed:
- `nft flush ruleset` killed SSH (should have only deleted Calico table)
- Cilium operator couldn't schedule due to `network-unavailable` taint
- Required physical console access to recover

The safe approach: `kubeadm reset` + fresh init with Cilium + Velero restore.
Must be fully tested in Vagrant before touching production.

## Approach

NOT in-place swap. Full cluster rebuild:
1. Velero backup
2. `kubeadm reset` (wipes etcd, PVC data survives on disk)
3. `kubeadm init --skip-phases=addon/kube-proxy`
4. Install Cilium via Helm
5. Run `bootstrap.sh` (Tier 0)
6. Velero restore (all workloads + data come back)
7. Reconnect Vault + Forgejo + ArgoCD

## Vagrant Test Flow

Full end-to-end test in Vagrant:
1. Build full stack with Calico (vagrant up + Ansible)
2. Create test data + Velero backup
3. kubeadm reset (destroy cluster, keep PVC data)
4. Rebuild with Cilium
5. Restore from Velero
6. Verify everything (data, apps, tracing, smoke test)

## Safeguards Added

- Base nftables rules in `/etc/nftables.conf` (survives CNI removal)
- Never `nft flush ruleset` — only delete specific CNI tables
- All commands on production require explicit approval
- Full Vagrant test before production

## Status

- [x] Base nftables rules applied to production
- [x] setup-kubeadm.yml + Vagrantfile include base nftables
- [ ] Vagrant end-to-end test
- [ ] Production migration
