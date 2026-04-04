# Plan 049: Dual-Pi HA Infrastructure + Cilium Migration

## Architecture — Symmetric Mirrored Pis

```
Pi-1 (192.168.11.4, pi1):              Pi-2 (192.168.11.6, pi2):
  Vault (transit unseal)                 (Vault standby — TODO)
  Nexus (pull-through cache)             (Nexus — TODO)
  Forgejo 14.0.3                         Forgejo 14.0.3
  MinIO (site replication peer)          MinIO (site replication peer)
  Keycloak 26.5.7                        Keycloak 26.5.7
  Postgres 17 (Patroni Leader)           Postgres 17 (Patroni Replica)
  Consul server                          Consul server

ten (192.168.11.2):
  Consul server (tiebreaker)
  kubeadm (Calico now, Cilium after migration)
```

## Replication — All Real-Time

| Service | Method | Status |
|---------|--------|--------|
| Postgres | Patroni + streaming replication | DONE |
| Consul | 3-node raft (pi1, pi2, ten) | DONE |
| MinIO | Site replication (bi-directional) | DONE |
| Keycloak | Multi-host JDBC (auto-failover to primary) | DONE |
| Forgejo | Post-receive git hook | TODO |
| Vault | Raft replication | TODO |
| Nexus | Independent caches | TODO |

## Postgres Automatic Failover

Patroni manages Postgres on both Pis via Consul DCS:
- If pi1 dies: Consul quorum (pi2 + ten) agrees, Patroni promotes pi2
- If pi2 dies: pi1 stays leader, no action needed
- If ten dies: pi1 + pi2 have quorum, failover still works
- If switch dies: no quorum possible, no promotion (prevents split-brain)
- Both Keycloaks use multi-host JDBC: `jdbc:postgresql://pi1:5432,pi2:5432/keycloak?targetServerType=primary`

## Completed

- [x] Install services on both Pis (Forgejo, MinIO, Keycloak, Postgres)
- [x] Production passwords (no changeme)
- [x] MinIO site replication (bi-directional, verified)
- [x] Consul 3-node cluster (pi1, pi2, ten)
- [x] Patroni automatic Postgres failover (pi1 leader, pi2 replica, lag=0)
- [x] Keycloak multi-host JDBC (auto-connects to primary)
- [x] UFW rules for all services
- [x] Ansible playbooks: setup-pi-services, setup-consul, setup-patroni
- [x] Vagrant tests: dual-Pi replication + failover, Cilium migration

## Remaining

- [ ] Vault on pi2 + raft join to pi1
- [ ] Vault auto-unseal from local file
- [ ] Forgejo mirror (post-receive git hook pi1 -> pi2)
- [ ] Nexus on pi2
- [ ] Migrate Forgejo from in-cluster to Pis
- [ ] Migrate Keycloak from in-cluster to Pis
- [ ] Update ArgoCD repoURLs to Pi Forgejo
- [ ] Update Velero BSL to Pi MinIO
- [ ] Cilium migration (kubeadm reset + rebuild)
- [ ] Update Vagrant tests for Consul + Patroni
- [ ] Base nftables on both Pis
