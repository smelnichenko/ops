# Node Reboot — `ten` (192.168.11.2)

The cluster is a **single** kubeadm control-plane node. A reboot is a **full outage**
for its duration — nothing fails over. This is the procedure for a clean, planned
reboot (for an unplanned/forced reboot, it is still crash-safe — skip to §3).

The off-cluster Pi services (Vault, MinIO, Patroni Postgres, Forgejo, Keycloak,
Nexus, keepalived VIP) are **not** affected by rebooting `ten`.

## 1. TL;DR

A plain `systemctl reboot` is safe:
- Kubelet **graceful node shutdown** is configured (`setup-kubeadm.yml`): pods get a
  clean SIGTERM in two waves before SIGKILL.
- etcd and all PVs are **node-local and crash-consistent** (single `local-path`
  StorageClass — data is on `ten`'s disk and survives the reboot).
- etcd is snapshotted **hourly to Pi MinIO** (`etcd-backup` CronJob → bucket
  `etcd-backups`), so an off-node copy always exists.
- The stack **self-recovers** with no manual steps; app pods are back ~9–10 min later.

Do **not** drain (single node — nowhere to evict to; it only blocks scheduling).

## 2. Pre-reboot (planned)

All optional — the reboot is crash-safe without them. They tighten the
most-recent-writes window on the single-replica stores.

**2.1 etcd snapshot** — already automated hourly, but a fresh one before a planned
reboot is cheap insurance:
```bash
kubectl -n kube-system create job etcd-backup-manual --from=cronjob/etcd-backup
kubectl -n kube-system wait --for=condition=complete job/etcd-backup-manual --timeout=120s
kubectl -n kube-system delete job etcd-backup-manual
```

**2.2 Fresh CNPG backup** (prod Postgres is already hourly-backed-up to Pi MinIO):
```bash
kubectl cnpg backup schnappy-production-postgres -n schnappy-production
```

**2.3 Highest-risk single-replica stores.** Per-pod `terminationGracePeriodSeconds`
is now 60–120s (raised from 30s), but a *node* shutdown is still capped by the
kubelet `shutdownGracePeriod` (see §6). If that cap is below the store's needs,
flush first:

| Store | Pre-reboot action |
|---|---|
| `schnappy-production-scylla` | `kubectl exec -n schnappy-production schnappy-production-scylla-datacenter1-rack1-0 -- nodetool drain` |
| `schnappy-production-minio` (email-attachments, only copy) | `mc mirror <alias>/email-attachments <pi>/email-attachments-backup` |
| `schnappy-infra-minio` (Mimir+Tempo S3 backend) | mirror buckets, or accept loss of the most-recent un-shipped Mimir head block |
| `schnappy-sonarqube-postgres` (no backup) | optional `pg_dump` if SQ history matters |

**2.4 Pre-flight:**
```bash
swapon --show     # must be EMPTY — failSwapOn=true; kubelet won't restart if swap is on
sync              # flush dirty fs buffers (etcd db + local-path PVs) to disk
```

## 3. Reboot

```bash
systemctl reboot
```
Full outage for the window. `base-filter` nftables keeps SSH (22) and the apiserver
(6443) reachable even if Cilium is slow, so you won't get locked out. Bring-up order:
kubelet → etcd → apiserver → Cilium → CoreDNS → istio-cni/istiod → ESO → Argo → apps.

## 4. Post-reboot verification (read-only)

```bash
ssh sm@192.168.11.2 true                          # host back
kubectl get --raw='/readyz?verbose'               # apiserver serving (gates ESO TokenReview)
kubectl get nodes -o wide                          # ten Ready
kubectl -n kube-system get pods | grep -E 'etcd-ten|apiserver|controller-manager|scheduler'
kubectl -n kube-system get pods -l k8s-app=cilium -o wide   # Cilium up (gates ALL pod networking)
kubectl -n istio-system get pods                   # istiod + cni-node (gates sidecars)
kubectl get clustersecretstore vault-backend -o jsonpath='{.status.conditions[0].type}={.status.conditions[0].status}{"\n"}'  # Ready=True
kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
kubectl get pvc -A --no-headers | awk '$2!="Bound"{print}'   # expect NO output
```
Argo `selfHeal=true` reconciles any drift automatically — no manual sync needed (and
any pre-reboot live hotfix will get reverted, by design).

## 5. If something is stuck (usually self-resolving in <10 min)

- **Pods stuck `1/2`** → istiod not serving XDS yet; `holdApplicationUntilProxyStarts`
  holds the app. Waits out. A pod labelled `cni.istio.io/uninitialized` is fixed in
  place by istio-cni repair — **don't delete**.
- **`schnappy-production-realtime`/centrifugo restarting** → expected Kafka
  `REBALANCE_IN_PROGRESS` churn after the single broker restarts; settles on its own.
- **ESO `Ready=False`** → almost always apiserver not yet serving (the Pi Vault calls
  *back* into ten's apiserver for TokenReview). Self-heals once apiserver is up. If
  `vault status` shows `sealed:true`, the Pis rebooted too — see `VaultSealed.md`.
- **Pod stuck `Terminating`/`ContainerCreating`** → RWO local-path mount held by an
  old pod. `kubectl describe` to confirm; a targeted pod delete is the fix.

## 6. Notes

- **Restore from a snapshot:** snapshots are in Pi MinIO `etcd-backups` (and via the
  on-host path during a planned snapshot). Restore is a host op: copy the `.db` to
  `ten`, `etcdutl snapshot restore`, repoint the etcd static-pod data-dir, restart
  kubelet. See `DR-PROCEDURE.md`.
- **Kubelet shutdown grace:** set to `shutdownGracePeriod=180s` /
  `shutdownGracePeriodCriticalPods=30s` (→ 150s for normal pods, enough for the
  120s-grace stores). Apply to a live node with **`task deploy:node-config`**
  (idempotent; touches only the kubelet config and restarts kubelet — pods keep
  running). NOT via `task deploy:kubeadm`: that one-shot bootstrap is not re-runnable
  (it fails at `kubeadm init` preflight). Until applied, the live cap is 60s/15s →
  45s for normal pods, so do the §2.3 flushes for a fully clean reboot.
- **No node-reboot automation** (no kured, no reboot timer): reboots are deliberate
  and manual.
