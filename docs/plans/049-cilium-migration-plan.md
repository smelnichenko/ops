# Plan 049: Dual-Pi HA Infrastructure + Cilium Migration

## Architecture — Symmetric Mirrored Pis

```
Pi-1 (192.168.11.4, better SSD):          Pi-2 (192.168.11.5):
  Vault (raft member)                       Vault (raft member)
  Nexus (pull-through cache)                Nexus (pull-through cache)
  Forgejo (primary)                         Forgejo (mirror)
  MinIO (site replication peer)             MinIO (site replication peer)
  Keycloak (cluster node)                   Keycloak (cluster node)
  Postgres (primary)                        Postgres (streaming replica)

ten (192.168.11.2):
  kubeadm (Cilium CNI, no kube-proxy)
  App workloads, App Postgres, Observability
```

## Replication — All Real-Time

| Service | Method |
|---------|--------|
| Vault | Raft consensus (built-in) |
| Postgres | Streaming replication |
| Keycloak | Infinispan cache (clustered) |
| MinIO | Site replication (built-in) |
| Forgejo | Post-receive git hook |
| Nexus | Independent caches |

## Vault Auto-Unseal

Unseal keys stored locally on each Pi. Systemd auto-unseals on boot.
Either Pi boots alone without dependency on the other.

## Vagrant Tests

Three VMs (pi1, pi2, kubeadm):
1. Setup + verify all replication works
2. Kill pi1, write data to pi2, restart pi1, verify catch-up
3. Kill pi2, write data to pi1, restart pi2, verify catch-up
4. Cilium migration with dual-Pi backend

## Status

- [x] Core Cilium migration test: PASSED
- [x] Single-Pi services (Forgejo + MinIO + Keycloak): working
- [ ] Dual-Pi Vagrantfile (3 VMs)
- [ ] Replication setup playbook
- [ ] Failover + catch-up test
- [ ] Full integration test
- [ ] Production deployment
