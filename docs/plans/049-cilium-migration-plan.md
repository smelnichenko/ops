# Plan 049: Dual-Pi HA Infrastructure + Cilium Migration

## Architecture

```
Pi-1 (192.168.11.4, pi1):              Pi-2 (192.168.11.6, pi2):
  Vault (raft member, auto-unseal)      Vault (raft member, auto-unseal)
  Consul server                         Consul server
  Nexus (pull-through cache)            (Nexus — TODO)
  Forgejo (active/passive via DRBD)     Forgejo (active/passive via DRBD)
  MinIO (site replication peer)         MinIO (site replication peer)
  Keycloak (multi-host JDBC)            Keycloak (multi-host JDBC)
  Postgres (Patroni managed)            Postgres (Patroni managed)
  DRBD primary (Forgejo data)           DRBD secondary (Forgejo data)

ten (192.168.11.2):
  Consul server (tiebreaker)
  kubeadm cluster
```

## Replication Summary

| Service | Method | Status |
|---------|--------|--------|
| Vault | Raft consensus | DONE |
| Postgres | Patroni + Consul DCS | DONE |
| MinIO | Site replication | DONE |
| Keycloak | Multi-host JDBC to Patroni PG | DONE |
| Consul | 3-node raft | DONE |
| Forgejo DB | Shared Patroni Postgres | DONE |
| Forgejo repos | DRBD block replication | TODO |
| Nexus | Independent caches | TODO |

## DRBD for Forgejo Repos

DRBD replicates a block device between pi1 and pi2 in real-time.
One Pi mounts it read-write (active Forgejo), the other has the
data replicated but unmounted. On Patroni failover, DRBD promotes
the secondary and mounts the volume.

- Volume: /dev/drbd0 mounted at /var/lib/forgejo/repos
- Primary follows Patroni leader (same Pi runs both)
- Automatic promotion via Patroni callback script
- No rsync, no SSH keys, no hooks, no file permission hacks

## Completed

- [x] Services on both Pis (Forgejo, MinIO, Keycloak, Postgres)
- [x] Production passwords
- [x] MinIO site replication
- [x] Consul 3-node cluster
- [x] Patroni automatic Postgres failover
- [x] Keycloak multi-host JDBC
- [x] Vault HA (raft, both Pis, CA-signed TLS, auto-unseal)
- [x] Forgejo on shared Postgres

## Remaining

- [ ] DRBD setup for Forgejo repos
- [ ] Patroni callback to manage DRBD primary/secondary
- [ ] Nexus on pi2
- [ ] Migrate Forgejo from in-cluster to Pis
- [ ] Migrate Keycloak from in-cluster to Pis
- [ ] Update ArgoCD repoURLs
- [ ] Cilium migration
