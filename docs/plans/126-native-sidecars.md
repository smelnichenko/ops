# Plan 126 - Istio's native sidecars mesh-wide, without losing a byte of production data

**Status:** 2026-11-18 - asked (operator: "please recheck if native sidecars will work now", then "make sure we will
not lose prod data"); drafted; its copy run after plan 123's push.

## Why

Native sidecars (the proxy an init container restarting Always) were on mesh-wide 2026-04-01 and off 2026-04-05 (infra
302ee1d7: "corrupt the Postgres authentication handshake") - no error kept, the evening Istio injection began, in the
same hour as Postgres' SSL turned off (20:04), `sslmode=disable` (20:10), the data ports' `tcp-` names (20:22), the
service-account tokens (20:56); 17 minutes after it the wait-for-postgres init containers went as "incompatible with
Istio mTLS" - what classic sidecars do to an init container. A client's TCP to Postgres takes the same redirect and the
same Envoy listener in either mode: the mode changes the proxy's lifecycle alone. Since then:

| | 2026-04-05 | now |
|---|---|---|
| Istio | 1.25.2 (native off by default) | 1.31.4 - native ON by default since 1.27; ours an explicit `"false"` |
| Kubernetes | k3s | kubeadm 1.36.6 (sidecar containers GA since 1.33) |
| Postgres | a Deployment of postgres:17-alpine, SSL on until 20:04 | CNPG 1.30.1, Postgres 18, sslmode disabled, `tcp-` ports |
| Cilium | 1.19 | 1.20.4 with Istio CNI |

Native, every Job's proxy stops with it (no quitquitquit call whose failure the Job ignores), a pod's init containers
reach the mesh, and the proxy outlives the app at shutdown (no request cut by a proxy that went first). Upstream knows
no Postgres problem with them (Crunchy runs its Postgres operator on Istio's native sidecars); Istio's one caveat is a
tool expecting `istio-proxy` among a pod's containers - ours read both lists (the restart playbook, the inventory, the
mesh audit: made so for the Kafka backup's native sidecar). Per-pod native sidecars run in production already (the
Kafka backup since 2026-11-18 04:34; init-users proven on the copy, copy run 6).

## What it touches

istiod's `ENABLE_NATIVE_SIDECARS` (infra's istiod values) and then every meshed pod restarted onto the new mode - 41
in production (18 production, 13 test, 9 infra, kagent's 1), CNPG's Postgres instances and Strimzi's Kafka brokers among
them. It restarts stateful pods: a copy run (plan 125's closed list), and the data-safety gates below.

## Data safety - no production data lost (operator, 2026-11-18)

1. **No volume touched.** The change is istiod's environment alone - no PVC, StatefulSet, CNPG storage, Kafka
   storage, KafkaTopic or retention: every pod restarts onto its own volume. The pull request shows it: the production
   render diff of every app is istiod's Deployment env and nothing else.
2. **Fresh backups first, each checked, the run stopping at any red:** Postgres - a CNPG base backup now
   (postgres-base-backup.yml), the WAL archive current, the Pis' daily restore check green within its age; Kafka - a
   dump now through the guard (task check:production:kafka-backup); ScyllaDB - a Scylla Manager backup now
   (check:production:scylla-backup); ClickHouse - a backup now (check:production:clickhouse-backup); etcd - a snapshot
   now (deploy:etcd:backup).
3. **The data's own counts before and after:** every Postgres database's row counts per table (`pg_stat_user_tables`
   n_live_tup and a `count(*)` of the largest), Kafka's latest offsets per partition and its consumer groups' offsets,
   ScyllaDB's and ClickHouse's row counts - the after never lower (Kafka's guard on the dump after the restart says the
   same for every topic).
4. **One stateful pod at a time, each healthy before the next:** the restart playbook's data tier first - CNPG rolls
   its replica, then the primary by switchover; the Kafka broker by Strimzi (producers retry through its restart:
   their delivery timeout above it - checked on the copy, every producer's messages counted); then the
   apps. A data workload not healthy again stops the run before the apps. (CNPG's switchover is planned: the primary
   shuts down cleanly - Postgres sends every WAL record to the streaming replica before its walsender exits - and
   then the replica is promoted, so no committed write is lost. A single-instance cluster - the test environment's -
   restarts in place on its own volume.)
5. **The way back rehearsed** in the same copy run: `ENABLE_NATIVE_SIDECARS: "false"` and the restart playbook bring
   every pod back to classic - green before production ever moves.
6. Nothing in production until the copy run is green, the full review clean and the operator says so.

## Changes

- infra: `clusters/production/istio/istiod-values.yaml` - `ENABLE_NATIVE_SIDECARS: "true"` (Istio's default; the
  comment says why it was false and why it is not now).
- ops: `restart-mesh-workloads.yml` restarts a pod whose proxy is of the other mode than istiod injects (its own
  `sidecar.istio.io/nativeSidecar` annotation first; unset: native since 1.27) - else a flipped flag restarts nothing;
  harness restart-mesh-order (the flip both ways, an annotation keeping a pod, a pod back in the wrong mode never green).

## Proof (the copy)

1. Built; the data counts read; the change (infra's branch) applied; the restart playbook (test:copy:playbook): every
   meshed pod native - none classic.
2. Every check (test:copy:check - data, survival, storage, metrics with every target up, the k6 smoke, production's
   data paths, isolation, Kafka's dump through the guard), every app's database login, Kafka's consumer groups with
   members, the restore rehearsals (Kafka, ClickHouse, ScyllaDB), the hooks' Jobs completing.
3. 15 minutes held: no pod's restart count moving (no operator rolling its pods for the init container it did not
   make), CNPG healthy with its replica streaming, the data counts not lower.
4. The way back: `"false"`, the restart playbook - every pod classic, the checks green again, the counts not lower.
