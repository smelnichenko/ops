# Plan 069: Use the ScyllaDB operator more — managed backup/repair + NodeConfig

## TL;DR

Today we ship a minimal `ScyllaCluster` CR — single DC, single rack,
operator handles only the cluster lifecycle. We don't drive backup,
repair, or node tuning through the operator. Three changes get us
declarative ops parity with what Postgres-via-CNPG already gives us:

1. **`ScyllaDBManagerTask`** for daily snapshots → S3 (Pi MinIO)
2. **`ScyllaDBManagerTask`** for weekly anti-entropy repair
3. **`NodeConfig`** to pin Scylla cores + set hugepages on `ten`

All three are operator-native CRs. Argo CD reconciles them. No cron
jobs in the wild, no `nodetool` shell scripts to maintain.

This plan is independent of the others (Valkey/ClickHouse/Centrifugo) —
ship whenever.

## Context

### Current state

`platform/helm/schnappy-data/templates/scylla-cluster.yaml`:

```yaml
apiVersion: scylla.scylladb.com/v1
kind: ScyllaCluster
metadata:
  name: schnappy-scylla
spec:
  agentVersion: 3.6.1
  version: 6.2.0
  developerMode: false
  datacenter:
    name: datacenter1
    racks:
      - name: rack1
        members: 1
        storage: { capacity: 50Gi, storageClassName: local-path }
        resources: { requests: { cpu: 1, memory: 2Gi } }
```

What's missing:
- No backup destination configured.
- No repair schedule (we manually run `nodetool repair` ~once when we
  remember).
- No CPU pinning / NUMA tuning. Scylla's "shared-nothing" arch leaves
  ~25% perf on the table when the kernel is free to schedule its
  shards across cores.

### What's available in the operator

ScyllaDB Operator (`scylla-operator/v1`) ships these CRDs we don't use:

| CRD | Purpose |
|---|---|
| `NodeConfig` (cluster-scoped) | Sets host-level kernel/CPU tuning needed by Scylla shards. Operator runs a privileged Job that writes `cpuset`, `hugepages`, `irqbalance`, `THP=never`. |
| `ScyllaDBManagerClusterRegistration` | Hooks the cluster into ScyllaDB Manager (a separate component we already install — `install_scylla_manager: true` in prod inventory). |
| `ScyllaDBManagerTask` | Schedules backup or repair tasks. Operator drives ScyllaDB Manager via its REST API based on these CRs. |

Manager itself runs as a single pod managed by the operator's Helm
chart (`scylla-manager` namespace). It coordinates with Scylla shards
via its sidecar agent.

## Scope

### 1. NodeConfig for `ten`

`infra/clusters/production/scylla-operator/nodeconfig.yaml`:

```yaml
apiVersion: scylla.scylladb.com/v1alpha1
kind: NodeConfig
metadata:
  name: ten-tuning
spec:
  placement:
    nodeSelector:
      kubernetes.io/hostname: ten
  localDiskSetup:
    raids: []          # we use local-path on a single disk; no RAID
    filesystems: []    # already mounted
    mounts: []
  cpuPinning: true
  hugepages2Mi: 1024   # 2GB hugepages — Scylla shard memory
  disableIrqBalance: true
```

Effect:
- `cpuset` carved out for Scylla pods (operator coordinates with kubelet).
- 1024 × 2 MiB = 2 GiB hugepages reserved at boot.
- IRQ balancing off so Scylla shards aren't disrupted by NIC/timer IRQs.

Risk: requires reboot of `ten` for hugepages to take effect. Schedule
a maintenance window. After this lands, expect ~15-30% lower P99
latencies on Scylla queries.

### 2. ScyllaDBManagerClusterRegistration

`platform/helm/schnappy-data/templates/scylla-manager-registration.yaml`:

```yaml
apiVersion: scylla.scylladb.com/v1alpha1
kind: ScyllaDBManagerClusterRegistration
metadata:
  name: schnappy-scylla
spec:
  scyllaDBClusterRef:
    name: schnappy-scylla
```

This tells ScyllaDB Manager about our cluster. Without this CR, manager
doesn't see the cluster and tasks can't target it.

### 3. ScyllaDBManagerTask: daily backup

`platform/helm/schnappy-data/templates/scylla-backup-task.yaml`:

```yaml
apiVersion: scylla.scylladb.com/v1alpha1
kind: ScyllaDBManagerTask
metadata:
  name: schnappy-scylla-daily-backup
spec:
  scyllaDBClusterRef:
    name: schnappy-scylla
  type: Backup
  backup:
    location:
      - s3:schnappy-backups/scylla
    retention: 7      # keep 7 days
    snapshotParallel:
      - "<rack>:1"   # one node at a time, no race
    interval: 24h
    cron: "0 3 * * *"   # 03:00 UTC daily
```

Backup destination: existing Pi MinIO bucket `schnappy-backups`. Operator
manages the cred sync (Manager has the S3 creds in its config; CR just
references the location).

### 4. ScyllaDBManagerTask: weekly repair

`platform/helm/schnappy-data/templates/scylla-repair-task.yaml`:

```yaml
apiVersion: scylla.scylladb.com/v1alpha1
kind: ScyllaDBManagerTask
metadata:
  name: schnappy-scylla-weekly-repair
spec:
  scyllaDBClusterRef:
    name: schnappy-scylla
  type: Repair
  repair:
    intensity: 1.0     # max — single-node, no consumer impact concerns
    parallel: 1
    cron: "0 4 * * 0"  # Sunday 04:00 UTC
    smallTableThreshold: 1GiB
```

### 5. Vagrant test integration

`tests/ansible/test-kafka-scylla.yml`:
- After ScyllaCluster is Ready, assert
  `ScyllaDBManagerClusterRegistration` is `Synchronized`.
- Skip the actual backup/repair tasks in vagrant (vagrant doesn't have
  the s3 endpoint that prod uses; they'd just sit Pending).
- `vagrant_install_scylla_manager: false` already in vagrant inventory;
  preserve that. The CR templates gate on a value
  (`scylla.manager.enabled`) which defaults true; vagrant overrides it
  to false.

## Vagrant tests are the merge gate

1. **`task test:kafka-scylla`** — ScyllaCluster Ready, the
   `ScyllaDBManagerClusterRegistration` exists but its status is
   `NotApplicable` in vagrant (manager off); the schedule-task CRs
   exist but skipped. Chart renders cleanly.
2. **Production smoke after merge** (manual checklist, not a vagrant
   test):
   - Within 24 h, see one Backup task entry under
     `kubectl get scylladbmanagertask -n schnappy` with status `Done`.
   - Within 7 days, one Repair task entry with status `Done`.
   - First Sunday after `NodeConfig` applied: confirm hugepages reserved
     (`cat /proc/meminfo | grep HugePages`) and Scylla pod's
     `nodetool status` shows it pinned to allocated cores.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| `NodeConfig.spec.cpuPinning` requires kubelet's `cpuManager: static`. Default is `none`. | Need to update `setup-kubeadm.yml` with `cpuManagerPolicy: static` in `kubelet-config.yaml`. Touches kubelet config — requires kubelet restart. Can be done one node at a time in our single-node cluster. |
| Hugepages reservation requires kernel boot param OR sysctl on running kernel. Operator handles via sysctl. | Reboot still recommended for clean state. Schedule. |
| Backup goes to Pi MinIO over the private network. If Pi is down at backup time, task fails. | Acceptable — Manager retries; alert on consecutive failures. |
| Weekly repair on single-node Scylla is mostly a no-op (no anti-entropy needed without replicas) | Still useful: it triggers tombstone cleanup. Cost is ~5 min/week of CPU. Worth the consistency guarantee. |
| ScyllaDB Manager itself fails | Falls back to no scheduled ops; data still available. Task CRs sit `Pending`. Recoverable. |

## Verification

1. `kubectl get nodeconfig ten-tuning -o jsonpath='{.status.conditions}'`
   → all `Synchronized: True`.
2. SSH to `ten`: `cat /proc/meminfo | grep HugePages_Total` → `1024`.
3. `kubectl exec -it schnappy-scylla-... -- nodetool info` →
   `Heap Memory (MB)` matches the operator-allocated cores × shard
   memory.
4. `kubectl get scylladbmanagerclusterregistration schnappy-scylla
   -o jsonpath='{.status.conditions[?(@.type=="Synchronized")].status}'`
   → `True`.
5. After 24 h: at least one entry in
   `kubectl get scylladbmanagertask -A` with `status: Done` and
   `lastRun: <timestamp>`.
6. After backup: `mc ls schnappy-backups/scylla/` shows snapshot data.
7. After 7 days: one Repair task ran (status Done).

## Out of scope

- **`ScyllaDBMonitoring`** — operator ships its own Prom + Grafana. We
  already have Mimir + ServiceMonitor + a Grafana dashboard. Skip.
- **Multi-DC topology** (`ScyllaCluster.spec.datacenter` with multiple
  entries) — we're single-node, single-DC; not needed until we add a
  second site.
- **Operator-managed restore** — the `ScyllaDBManagerTask.spec.restore`
  exists but we'd want to test restore separately (Plan 002 DR test
  covers this).
- **Auto-tuning sysctls beyond hugepages** — `vm.swappiness=0`,
  `vm.dirty_ratio=80`, `kernel.numa_balancing=0` are default-good on
  Bookworm; we'd only tune if we hit specific issues.

## Execution order

1. Save this plan.
2. **`infra`**: commit the `NodeConfig` resource for `ten`.
3. **`ops`**: update `setup-kubeadm.yml` to set `cpuManagerPolicy: static`
   in the kubelet config.
4. Schedule a `ten` reboot. Verify hugepages and CPU pinning post-reboot.
5. **`platform`**: add `ScyllaDBManagerClusterRegistration` +
   `ScyllaDBManagerTask` CRs to `schnappy-data`.
6. Vagrant test (gates on rendering correctly with manager disabled).
7. Argo CD sync; first daily backup runs at 03:00 UTC.
8. Add Mimir alerts for failed backup/repair tasks (1 day of consecutive
   failures triggers a page).
