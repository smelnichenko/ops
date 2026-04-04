# Plan 049: Dual-Pi HA Infrastructure + Cilium Migration

## Architecture

```
         VIP: 192.168.11.5 (Keepalived, floats between Pis)
              git.pmon.dev / keycloak.pmon.dev → VIP
              ┌───────────┴───────────┐
              │                       │
Pi-1 (192.168.11.4, pi1):              Pi-2 (192.168.11.6, pi2):
  Keepalived MASTER (priority 150)      Keepalived BACKUP (priority 100)
  Vault (raft member, auto-unseal)      Vault (raft member, auto-unseal)
  Consul server                         Consul server
  Nexus (pull-through cache)            Nexus (pull-through cache)
  Forgejo (active-active via GlusterFS) Forgejo (active-active via GlusterFS)
  MinIO (site replication peer)         MinIO (site replication peer)
  Keycloak (multi-host JDBC)            Keycloak (multi-host JDBC)
  Postgres (Patroni managed)            Postgres (Patroni managed)
  GlusterFS (forgejo-repos replica)     GlusterFS (forgejo-repos replica)

ten (192.168.11.2):
  Consul server (tiebreaker)
  kubeadm cluster
```

## Keepalived VIP

A floating virtual IP (192.168.11.5) provides a single stable endpoint for all
Pi-hosted services. Keepalived runs VRRP between pi1 and pi2 — if the active
Pi dies, the other grabs the VIP in ~3 seconds.

- VIP: `192.168.11.5/24` on the LAN interface
- pi1 is MASTER (priority 150), pi2 is BACKUP (priority 100)
- `nopreempt` — once pi2 takes over, it keeps VIP until it fails (avoids flapping)
- Health check script monitors Forgejo, Keycloak, and Patroni every 5 seconds
- If health check fails 3 times, priority drops by 50 → triggers failover
- All external references (DNS, ArgoCD, Woodpecker, git remotes) use VIP

## Replication Summary

| Service | Method | Status |
|---------|--------|--------|
| Vault | Consul storage + HA | DONE |
| Postgres | Patroni + Consul DCS | DONE |
| MinIO | Site replication | DONE |
| Keycloak | Multi-host JDBC to Patroni PG | DONE |
| Consul | 3-node raft | DONE |
| Forgejo DB | Shared Patroni Postgres | DONE |
| Forgejo repos | GlusterFS replicated volume | DONE |
| Nexus | Independent caches | DONE |
| VIP failover | Keepalived VRRP | DONE |

## GlusterFS for Forgejo Repos

GlusterFS provides a FUSE-based replicated filesystem between pi1 and pi2.
Both nodes mount the same volume read-write — no primary/secondary promotion needed.
Pure userland, no kernel module dependency, survives kernel updates.

- Volume: `forgejo-repos` (replica 2) mounted at `/var/lib/forgejo/repos`
- Both Pis active simultaneously — GlusterFS handles replication + self-heal
- `backup-volfile-servers` option provides failover if local glusterd is down
- Forgejo UID/GID aligned to 900:900 on both Pis for consistent ownership
- No rsync, no SSH keys, no hooks, no kernel module compilation

## Failover Behavior

**Pi-1 dies:**
- Keepalived: pi2 grabs VIP 192.168.11.5 (~3 seconds)
- Vault: pi2 becomes raft leader (automatic)
- Postgres: Patroni promotes pi2 replica (automatic via Consul)
- Keycloak: pi2 serves all requests (multi-host JDBC reconnects)
- MinIO: pi2 serves all data (site replication catches up on return)
- Forgejo: pi2 serves repos (GlusterFS has full copy, same Patroni PG)
- ArgoCD/Woodpecker/git: VIP unchanged, no config changes needed

**Both die (power outage):**
- Both boot, Keepalived elects MASTER, Vault auto-unseals, Patroni picks leader

## Completed

- [x] Services on both Pis (Forgejo, MinIO, Keycloak, Postgres)
- [x] Production passwords
- [x] MinIO site replication
- [x] Consul 3-node cluster
- [x] Patroni automatic Postgres failover
- [x] Keycloak multi-host JDBC
- [x] Vault HA (raft, both Pis, CA-signed TLS, auto-unseal)
- [x] Forgejo on shared Postgres
- [x] GlusterFS for Forgejo repos
- [x] Nexus on pi2
- [x] Forgejo repos migrated to Pi (13 repos, private, main branch)

## Remaining

- [x] Keepalived VIP (192.168.11.5) between pi1 and pi2
- [x] Update DNS: git.pmon.dev + nexus.pmon.dev → VIP (Unbound on router)
- [x] Update ArgoCD repoURLs → VIP Forgejo (all apps synced)
- [x] ArgoCD NetworkPolicy: allow egress to VIP 192.168.11.5:3000
- [x] ArgoCD repo credentials for Pi Forgejo (private repos)
- [x] Caddy reverse proxy with auto-TLS (Let's Encrypt + Porkbun DNS-01)
- [x] Forgejo ROOT_URL + Keycloak OAuth configured
- [x] Woodpecker CI + local git remotes via git.pmon.dev (DNS → VIP → Caddy TLS)
- [x] Vault migrated from raft to Consul storage (3-node quorum)
- [x] Vault auto-unseal systemd service on both Pis
- [x] All Vault secrets re-seeded, ESO pointing to Pi Vault via VIP
- [x] In-cluster Forgejo + Vault removed (apps + namespaces deleted)
- [x] Migrate Keycloak: realm exported from in-cluster, imported to Pi, auth.pmon.dev → VIP
- [ ] Cilium migration
