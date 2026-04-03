# Plan 049: Cilium Migration + Pi Services (Forgejo + MinIO)

## Context

Three changes combined:

1. **Move Forgejo to Pi** -- breaks circular dependency
2. **Move backup MinIO to Pi** -- backups survive cluster destruction
3. **Migrate Calico to Cilium** -- via kubeadm reset + redeploy

## Architecture

```
Pi (192.168.11.4): Vault + Nexus + Forgejo + MinIO (backup)
ten (192.168.11.2): kubeadm (Cilium, no kube-proxy)
```

## Data Strategy

- **Postgres:** pg_dump to Pi MinIO, import after redeploy (NOT Velero FSBackup)
- **Keycloak:** uses Postgres, covered by pg_dump
- **Forgejo:** on Pi, survives cluster death
- **Vault:** on Pi, survives cluster death
- **Other PVCs:** expendable (Elasticsearch, Mimir, Grafana, Tempo rebuild from scratch)

## Migration Steps

**No downtime (pre-work):**
1. Install Forgejo + MinIO on Pi
2. Mirror repos to Pi Forgejo
3. Update DNS + ArgoCD repoURLs to Pi
4. Verify ArgoCD syncs from Pi

**Maintenance window (~30 min):**
5. pg_dump all databases to Pi MinIO
6. kubeadm reset
7. kubeadm init + Cilium install + local-path-provisioner
8. bootstrap.sh (cert-manager, ESO, Istio)
9. Redeploy apps via Helm (or ArgoCD from Pi Forgejo)
10. pg_restore from Pi MinIO
11. Setup ArgoCD pointing to Pi Forgejo
12. Verify: data, auth, ArgoCD sync

## Vagrant Test

Simplified flow (no Velero):
1. Deploy Postgres, insert test data
2. pg_dump to Pi MinIO
3. kubeadm reset
4. Cilium install
5. Helm redeploy
6. pg_restore
7. Verify data survived
8. Verify Cilium + Hubble + Forgejo + MinIO

## Status

- [x] Base nftables rules
- [x] Forgejo + MinIO on vault-pi VM
- [x] pg_dump backup/restore approach
- [ ] Clean Vagrant test pass
- [ ] Keycloak auth test
- [ ] ArgoCD sync test
- [ ] Production migration
