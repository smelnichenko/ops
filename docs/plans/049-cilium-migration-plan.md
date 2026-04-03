# Plan 049: Cilium Migration + Dual-Pi Infrastructure

## Context

Move critical services to two Pi 5s (8GB, NVMe each) so they survive cluster destruction. Then migrate Calico to Cilium via kubeadm reset + redeploy.

## Two-Pi Architecture

```
Pi-1 (192.168.11.4, better SSD):
  Vault (primary, raft leader)    ~200MB
  Nexus (caching proxy)           ~1GB
  Forgejo 14.0.3 (git forge)     ~300MB
  MinIO (Velero backups)          ~200MB
  Total: ~1.7GB of 8GB

Pi-2 (192.168.11.5):
  Vault (standby, raft replica)   ~200MB
  Keycloak 26.5.7 (SSO)          ~1GB
  Postgres 17 (Keycloak DB)      ~200MB
  Total: ~1.4GB of 8GB

ten (192.168.11.2):
  kubeadm (Cilium CNI, no kube-proxy)
  App workloads + App Postgres
  Observability stack
```

## Vault HA with Local Auto-Unseal

Both Pis run Vault in a raft cluster:
- Unseal keys saved to `/root/.vault-unseal-keys` (mode 0400) on each Pi
- Systemd unit auto-unseals on boot from local file
- Any Pi can boot alone and unseal itself
- Raft replication keeps secrets in sync
- If one Pi dies, the other has full Vault

## Cross-Replication

- Pi-1 -> Pi-2: MinIO mirror (mc mirror, cron)
- Pi-2 -> Pi-1: pg_dump Keycloak DB (cron)
- Vault: raft replication (built-in)

## Data Strategy

- App Postgres: pg_dump to Pi-1 MinIO
- Keycloak DB: on Pi-2, cross-backed to Pi-1
- Forgejo repos: on Pi-1, mirrored to Pi-2 MinIO
- Vault secrets: raft-replicated across both Pis
- Observability PVCs: expendable

## Migration Steps

No downtime (pre-work): setup Pi-2, Vault raft, migrate Keycloak,
mirror repos, update DNS + ArgoCD + OAuth configs.

Maintenance window (~30 min): pg_dump, kubeadm reset, Cilium,
bootstrap, redeploy, pg_restore, ArgoCD setup.

## Vagrant Test Status

- [x] Core migration (pg_dump + Cilium): PASSED
- [x] Forgejo + MinIO + Keycloak on vault-pi VM
- [ ] Full test with Keycloak auth + ArgoCD sync (running)
- [ ] Production migration
