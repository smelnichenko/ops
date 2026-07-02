---
name: platform-reliability
description: Failure-mode discipline for the schnappy platform — GitOps/Argo CD semantics (CSA vs SSA, ignoreDifferences traps, prune dangers, operation-vs-rollup status), Cilium/NetworkPolicy gotchas (environment labels, node-IP entities), and distributed failure modes (cached failures, quorum dependencies, dual-active flips, shared-storage file locks, health-check semantics). Read BEFORE designing or reviewing infra/platform/ops changes, service topology, retries, health checks, HA/failover, or storage layout — and whenever debugging an Argo sync, a NetworkPolicy drop, or a cascade outage.
---

# Platform reliability discipline

Failure-mode review lenses for the platform. Every rule was paid for with a real outage or a lost
debugging day here; the specific incidents stay attached so the rule has teeth. The question that
finds the bugs: *what happens on timeout, partial failure, retry storm, failover with cached
state, or double-active?*

## 1. GitOps / Argo CD semantics

- **Read the right status field**: the rollup `sync.status`/`health.status` can be green while
  `operationState.phase = Failed` (a failed PostSync hook — the k6 smoke — hid exactly there).
  Check the *operation* and Error pods, not just the app color. `Unknown` ≠ `OutOfSync`: read
  `status.conditions[].type=ComparisonError` before building diff theories.
- **CSA vs SSA is a semantic choice, not a knob**: SSA flags apiserver-defaulted fields as drift;
  CSA ignores them via last-applied. Never add `ServerSideApply=true` reactively to "fix" a diff.
- **`RespectIgnoreDifferences` + list-typed fields = edits that never apply**: an in-place edit
  of an ignored list (ExternalSecret `spec.data[]`) shows OutOfSync forever but is never written.
  Delete+recreate (with Retain) or make additive changes.
- **Prune is a cascade delete**: never prune the root app (deletes every child Application) or
  stateful apps (deletes StatefulSets/PVCs = data loss). Wedged hook? `argocd app terminate-op`
  via the controller pod's bundled CLI (`--core`) — not a force-sync.
- Argo excludes Endpoints/EndpointSlice: host-scrape targets need a ScrapeConfig CR (with the
  `release=schnappy` label), not raw Endpoints manifests.

## 2. Network policy and CNI

- **A new namespace needs `environment=production`** — the schnappy-infra egress rules select on
  it, and traffic to an unlabeled namespace is *silently dropped* at the source. First check for
  "service can't reach new thing".
- **Pod → node-IP is not `ipBlock`**: standard NetworkPolicy can't match the host; use
  CiliumNetworkPolicy `toEntities: host`. Never put a node IP in an LB pool (it kills SSH — L2
  announcements hijack the address).
- **Change safety is physical**: never `nft flush` on a live node, never swap CNI in place
  (drain-and-rebuild), and cert/ACME storage changes need restart-not-reload (a Caddy reload
  after ACME→file caused an outage). Belt-and-suspenders the k8s API NetworkPolicy.

## 3. Distributed failure modes

- **A cached FAILURE is an outage generator**: PgBouncer cached an auth failure from a brief
  switch flap and kept Forgejo down for hours after the network healed. For every cache ask:
  does it cache negative results, and what evicts them? Retry-after-failure paths must re-resolve,
  not replay the cached error.
- **Map quorum dependencies before trusting a service**: MinIO died when Consul lost quorum —
  the object store's availability was secretly the KV store's. For each dependency: what happens
  to THIS service when THAT one loses quorum/leader? (Consul still underpins Vault + Patroni
  here.)
- **Dual-active is the default failure of active-passive**: keepalived flip protocols must prove
  the old master stopped before the new one starts (single-host flip is defended here;
  cross-host dual-active is a KNOWN open hazard). Review any notify/failover script for the
  both-running window.
- **File locks don't cross shared storage**: LevelDB/Bleve on Gluster deadlocked active-active
  Forgejo in kernel D-state. Queues/indexers/sessions stay on local disk; only lock-free data
  shares.
- **Health checks must test the real dependency**: Patroni's `/primary` REST check is what makes
  the HAProxy failover correct — a TCP-port check would happily route to a replica. For every
  health check: what exactly does a pass prove?

## 4. Change and recovery discipline

- Playbooks re-runnable (init guards, checksum-restarts) — a provisioning step that can't run
  twice fails exactly during recovery, when it runs twice.
- Fix playbooks properly, never one-off hacks on hosts; prod `.env` lives on localhost, never on
  the cluster host.
- Backup/restore is only real when drilled: restore paths (CNPG barman + bootstrap.recovery, etcd
  snapshots) get exercised (`task dr:drill`) and verified by metric+alert, not by the existence
  of backup files.

## 5. Review workflow

For any diff touching topology, retries, health, HA, storage, or manifests: (1) walk each new
dependency edge and ask the quorum/failover question; (2) find every cache and ask the negative-
result question; (3) find every check-then-act across the network (leader checks, lock files,
VIP claims) and ask the dual-active question; (4) for Argo-managed resources, decide CSA/SSA and
ignoreDifferences semantics *up front*; (5) confirm labels/NetworkPolicy reachability for
anything in a new namespace; (6) confirm the rollback/re-run story for the change itself.
