# Plan 049: Migrate from Calico to Cilium CNI

## Context

The cluster uses Calico 3.30.0 (nftables dataplane) with a separate kube-proxy DaemonSet. Cilium provides an eBPF-based CNI with built-in kube-proxy replacement and Hubble network observability. All 60 NetworkPolicies are standard Kubernetes -- no Calico CRDs -- fully portable.

Cilium and Istio CNI coexist. Istio CNI chains onto whatever primary CNI is installed. Cilium needs `cni.exclusive: false` to not delete Istio's chained config.

## What Changes

| Before | After |
|--------|-------|
| Calico 3.30.0 (nftables) | Cilium (eBPF) |
| kube-proxy DaemonSet (nftables) | Cilium kube-proxy replacement (eBPF) |
| VXLANCrossSubnet encapsulation | Native routing (single node) |
| nftables NAT masquerade | eBPF masquerade |
| No network observability | Hubble (L3/L4 visibility) |

Unchanged: Istio sidecar mesh, all NetworkPolicies, Pod/Service CIDRs, Istio CNI.

## Migration Steps

1. Velero backup
2. Remove kube-proxy DaemonSet
3. Remove Calico (operator, CRDs, host state)
4. Install Cilium via Helm (kube-proxy replacement, native routing, Hubble)
5. Restart all pods
6. Verify (networking, mTLS, NPs, services, Hubble)

## Rollback

- `helm uninstall cilium` -> re-install Calico + kube-proxy
- Or: restore from Velero backup

## Estimated Downtime

~35-40 minutes. Test in Vagrant first.
