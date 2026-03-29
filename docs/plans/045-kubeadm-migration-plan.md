# Plan 045: k3s → kubeadm Migration

## Context

k3s has fundamental conflicts between its embedded components (ServiceLB iptables-legacy, kube-router NetworkPolicy) and nftables used by modern kube-proxy. These conflicts prevent Istio ambient mesh from working correctly with LoadBalancer services. Migration to vanilla kubeadm k8s eliminates all embedded component conflicts.

## Current State

- k3s v1.34.4 on `ten` (192.168.11.2)
- Istio ambient installed but external access broken (Traefik/ServiceLB/ztunnel conflicts)
- All data on NVMe at `/mnt/storage`
- PVCs via local-path-provisioner at `/mnt/storage/k3s-pvcs`
- Secrets in Vault (external to k3s)
- Container images in Forgejo registry (git.pmon.dev)
- 91 pods across schnappy, woodpecker, forgejo, argocd, vault, velero namespaces

## Strategy

**Approach: In-place rebuild** — stop k3s, install kubeadm on same node, restore from Velero backup + Vault secrets.

1. Take Velero backup
2. Stop k3s
3. Install kubeadm + containerd + Calico CNI + MetalLB
4. Install Argo CD
5. Restore Vault (raft snapshot)
6. Seed ESO + secrets
7. Let Argo CD sync all Applications from Forgejo
8. Restore PVC data from Velero backup

**Downtime:** ~1-2 hours

## Phase 1: Pre-migration Backup

```bash
# Velero backup
task deploy:backup

# Vault raft snapshot
ssh ten 'sudo k3s kubectl exec -n vault vault-0 -- env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt VAULT_TOKEN="$TOKEN" vault operator raft snapshot save /tmp/vault.snap'

# Copy PVC data
ssh ten 'sudo tar czf /mnt/backups/pvcs-backup.tar.gz /mnt/storage/k3s-pvcs/'

# Export all k8s resources
ssh ten 'sudo k3s kubectl get all,pv,pvc,secret,configmap,ingress,certificate -A -o yaml > /mnt/backups/k8s-resources.yaml'
```

## Phase 2: Install kubeadm

```bash
# Stop k3s
ssh ten 'sudo systemctl stop k3s && sudo systemctl disable k3s'

# Install containerd
apt install containerd
# Configure crictl, containerd config

# Install kubeadm, kubelet, kubectl
apt install kubeadm kubelet kubectl
kubeadm init --pod-network-cidr=10.42.0.0/16 --service-cidr=10.43.0.0/16 --apiserver-advertise-address=192.168.11.2

# Install Calico CNI (nftables native, no iptables-legacy conflicts)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.3/config/manifests/metallb-native.yaml
# Configure L2 pool with 192.168.11.2-192.168.11.10 range
```

## Phase 3: Install Core Infrastructure

```bash
# cert-manager
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set installCRDs=true

# external-secrets operator
helm install external-secrets external-secrets/external-secrets --namespace external-secrets --create-namespace

# Argo CD
helm install argocd argo/argo-cd --namespace argocd --create-namespace

# Local-path-provisioner (for PVCs)
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-provisioner.yaml
```

## Phase 4: Restore Vault

```bash
# Deploy Vault from Argo CD
# Restore raft snapshot
# Unseal via Pi transit
```

## Phase 5: Argo CD Sync

Point Argo CD root app to infra repo → all Applications auto-deploy.

## Phase 6: Restore Data

PVC data (postgres, elasticsearch, etc.) restored from backup.

## Phase 7: Install Istio Ambient

Same as Plan 044 but now with proper nftables support:
- MetalLB assigns 192.168.11.2 directly to Istio gateway
- No Traefik, no ServiceLB, no kube-router conflicts
- STRICT mTLS works end-to-end

## Key Differences from k3s

| Feature | k3s | kubeadm |
|---------|-----|---------|
| CNI | Flannel (embedded) | Calico (separate) |
| NetworkPolicy | kube-router (iptables-legacy) | Calico (nftables native) |
| LoadBalancer | ServiceLB (iptables-legacy) | MetalLB (nftables native) |
| Ingress | Traefik (embedded) | None (Istio gateway) |
| kube-proxy | nftables | nftables |
| containerd | Embedded | Standalone |
| Data path | /mnt/storage/k3s | /var/lib/kubelet, /etc/kubernetes |
