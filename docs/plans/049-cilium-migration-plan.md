# Plan 049: Cilium Migration + Pi Services

## Context

Move critical services to Pi (192.168.11.4) so they survive cluster destruction, then migrate Calico to Cilium via kubeadm reset + redeploy.

## What moves to Pi

| Service | RAM | Purpose |
|---------|-----|---------|
| Vault | ~200MB | Already there (transit unseal) |
| Nexus | ~1GB | Already there (caching proxy) |
| Forgejo 14.0.3 | ~300MB | Git forge (ArgoCD source) |
| MinIO | ~200MB | Velero backup target |
| Keycloak 26.5.7 | ~1GB | SSO (Forgejo, Woodpecker, Grafana, ArgoCD) |
| Postgres 17 | ~200MB | Keycloak database |
| **Total** | **~2.9GB** | of 8GB available |

## Why Keycloak on Pi

Dependency chain: Woodpecker -> Forgejo OAuth -> Keycloak. If Keycloak is in-cluster and the cluster dies, Forgejo on Pi can't authenticate users. Moving Keycloak to Pi makes the entire auth chain independent of the cluster.

## Architecture

```
Pi (192.168.11.4):
  Vault, Nexus (existing)
  Forgejo -> Keycloak OAuth -> Postgres (KC DB)
  MinIO (Velero backups)

ten (192.168.11.2):
  kubeadm (Cilium CNI, no kube-proxy)
  App workloads + App Postgres
  Observability stack
```

## Data Strategy

- App Postgres (monitor, admin, chat, chess DBs): pg_dump to Pi MinIO
- Keycloak DB: on Pi, survives cluster death
- Forgejo: on Pi, survives cluster death
- Vault: on Pi, survives cluster death
- Other PVCs: expendable, rebuild from scratch

## Migration Steps

**Pre-work (no downtime):**
1. Install Postgres + Keycloak + Forgejo + MinIO on Pi
2. Migrate Keycloak realm data (export/import)
3. Mirror repos to Pi Forgejo
4. Update DNS: git.pmon.dev + auth.pmon.dev -> Pi
5. Update ArgoCD repoURLs + OAuth configs to Pi
6. Verify: auth, ArgoCD sync, Woodpecker webhooks

**Maintenance window (~30 min):**
7. pg_dump app databases to Pi MinIO
8. kubeadm reset
9. kubeadm init + Cilium + bootstrap.sh
10. Helm redeploy apps + pg_restore
11. Setup ArgoCD -> Pi Forgejo
12. Verify everything

## Vagrant Test (passed for core migration)

- Postgres data survives via pg_dump/restore: PASSED
- Cilium 1.19.2 + Hubble: PASSED
- Forgejo + MinIO on Pi: PASSED
- Keycloak on Pi + auth verification: testing
- ArgoCD sync from Pi Forgejo: testing

## Status

- [x] Base nftables rules on production
- [x] Core migration test (pg_dump + Cilium): PASSED
- [x] Forgejo + MinIO on vault-pi VM
- [ ] Keycloak + Postgres on vault-pi VM
- [ ] Full test with Keycloak auth + ArgoCD sync
- [ ] Production migration
