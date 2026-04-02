# Plan 048: Tiered Bootstrap for Cluster DR

## Context

ArgoCD needs Forgejo to deploy apps, but Forgejo itself is an ArgoCD-managed app. If the cluster dies or Forgejo goes down, there's a circular dependency. Today's `task deploy:full` runs Ansible playbooks sequentially, but ArgoCD's root app points to `http://forgejo-http.forgejo.svc:3000/schnappy/infra.git` — if Forgejo is down, ArgoCD can't sync anything.

Goal: Break the bootstrap cycle with a tiered approach so Tier 0 (pre-GitOps) components can be deployed without ArgoCD or Forgejo.

## Current Bootstrap Order

```
Nexus (Pi) -> Vault Pi -> kubeadm + Calico -> cert-manager -> Forgejo -> Woodpecker -> Velero -> Vault HA -> ArgoCD -> root app -> 20 apps via sync waves
```

## Proposed Tiers

### Tier 0 -- Pre-GitOps (bootstrap.sh + Ansible)

Deployable without ArgoCD, without Forgejo, from local host.

- kubeadm + Calico CNI (Ansible)
- cert-manager + ClusterIssuers (bootstrap.sh)
- Porkbun webhook (bootstrap.sh)
- External Secrets Operator (bootstrap.sh)
- local-path-provisioner (kubeadm playbook)
- Vault Pi + cluster (Ansible)
- Istio base + istiod + CNI (bootstrap.sh)
- Velero + MinIO backup (bootstrap.sh)
- Forgejo (Ansible)
- ArgoCD (Ansible)

### Tier 1 -- GitOps-Managed (ArgoCD from Forgejo)

- schnappy-data, schnappy-auth, schnappy-mesh, schnappy
- schnappy-observability, schnappy-test, schnappy-sonarqube
- Woodpecker

## Implementation

1. Create `bootstrap.sh` — Helm installs Tier 0 from external chart repos using values from local infra repo
2. Keep Tier 0 apps in ArgoCD for drift detection (ArgoCD adopts pre-existing resources via ServerSideApply)
3. Add `deploy:bootstrap` task to Taskfile.yml
4. Git mirror on host — `/home/sm/src/` already has bare clones
5. Document DR procedure

## DR Procedure

1. `kubeadm init` + Calico (Ansible)
2. `bootstrap.sh` (Tier 0 — cert-manager, ESO, Istio, Velero)
3. Restore Velero backup: `velero restore create --from-backup full-weekly-latest`
4. Wait for Forgejo PVC to restore
5. Setup Forgejo + ArgoCD (Ansible)
6. ArgoCD syncs Tier 1 from restored Forgejo

## Verification

1. Fresh cluster: kubeadm -> bootstrap.sh -> Forgejo -> ArgoCD -> all apps sync
2. Simulated Forgejo outage: Tier 0 continues running, restore Forgejo, ArgoCD resumes
3. Full DR: destroy cluster -> rebuild -> Velero restore -> verify all services
