# Plan 126 - Istio's native sidecars mesh-wide, without losing a byte of production data

**Status:** 2026-11-18 - asked (operator: "please recheck if native sidecars will work now", then "make sure we will
not lose prod data"); DECIDED ("switch it!"), its order ("go"): the mesh push (plan 123) first, then this ops branch on
main, then its copy run (copy run 8, before the hooks/Kafka batch's), its full review, the production switch below in
a quiet hour. Reviewed twice before its copy run (architecture, reliability: the restart's real CNPG behaviour, the
Kafka consumers' skipped records, the gates that could pass a loss, the alerts blind to a native proxy - all answered
below).

## Why

Native sidecars (the proxy an init container restarting Always) were on mesh-wide 2026-04-01 and off 2026-04-05 (infra
302ee1d7: "corrupt the Postgres authentication handshake") - no error kept, the evening Istio injection began, in the
same hour as Postgres' SSL turned off (20:04), `sslmode=disable` (20:10), the data ports' `tcp-` names (20:22), the
service-account tokens (20:56); 17 minutes after it the wait-for-postgres init containers went as "incompatible with
Istio mTLS" - what classic sidecars do to an init container. A client's TCP to Postgres takes the same redirect and the
same Envoy listener in either mode: the mode changes the proxy's lifecycle alone. Proven on the copy since: CNPG's
init-users Job, on a native sidecar, logged into Postgres 18 and wrote the roles (copy run 6, 2026-11-18).

| | 2026-04-05 | now |
|---|---|---|
| Istio | 1.25.2 (native off by default) | 1.31.4 - native ON by default since 1.27; ours an explicit `"false"` |
| Kubernetes | k3s | kubeadm 1.36.6 (sidecar containers GA since 1.33) |
| Postgres | a Deployment of postgres:17-alpine, SSL on until 20:04 | CNPG 1.30.1, Postgres 18, sslmode disabled, `tcp-` ports |
| Cilium | 1.19 | 1.20.4 with Istio CNI |

Native, every Job's proxy stops with it (no quitquitquit call whose failure the Job ignores), a pod's init containers
reach the mesh, and the proxy outlives the app at shutdown (no request cut by a proxy that went first). Upstream knows
no Postgres problem with them (Crunchy runs its Postgres operator on Istio's native sidecars). What reads a pod's
containers had to read its init containers too - the restart playbook, the inventory, the mesh audit, the copy's
settle and verify checks (argo-settled.py, upgrade-verify.sh), and the pod alerts (kube-state-metrics reports a native
sidecar as `kube_pod_init_container_*`): all do now.

## What it touches

istiod's `ENABLE_NATIVE_SIDECARS` (infra's istiod values; one istiod for the cluster) and then every meshed pod
restarted onto the new mode - 39 in production (2026-11-18), CNPG's Postgres instances (production's two, test's one)
and Strimzi's Kafka brokers among them; Grafana's and SonarQube's CNPG clusters and ScyllaDB are outside the mesh,
untouched. It restarts stateful pods: a copy run (plan 125's closed list), and the data-safety gates below.

## Data safety - no production data lost (operator, 2026-11-18)

1. **No volume touched.** The change is istiod's environment alone - no PVC, StatefulSet spec, CNPG storage, Kafka
   storage, KafkaTopic or retention: every pod restarts onto its own volume.
2. **Fresh backups first, each checked, the run stopping at any red** (scratchpad prod-backups-now.sh): Postgres - a
   CNPG base backup now (task deploy:postgres:base-backup), the WAL archive current, the Pis' daily restore check green
   within its age; Kafka - a dump now through its guard (task check:production:kafka-backup); ScyllaDB - a Scylla
   Manager backup now (check:production:scylla-backup); ClickHouse (check:production:clickhouse-backup); etcd - a
   snapshot now (deploy:etcd:backup).
3. **The data counted before and after** (prod-data-counts.sh, its comparison counts-compare.py): every Postgres table
   of every database, an exact `count(*)` read on the replica; Kafka's latest offset per partition and every consumer
   group's committed offsets; every ScyllaDB table's rows; ClickHouse's active rows per table. LOSS - the switch's
   gate red: a Kafka partition's latest offset lower or gone; a Postgres database or a Postgres or ScyllaDB table
   gone; a ScyllaDB table that shrank at all (chat's history - written, almost never deleted); Postgres' total rows
   down by more than 5 % and 100 rows. Listed and judged by eye: a Postgres or ClickHouse table that shrank (apps
   delete rows; ClickHouse's logs have a TTL), a group's committed offset lower (a re-read, no loss). Any store not
   read fails the count.
4. **The restart, one stateful workload at a time** (restart-mesh-workloads.yml): CNPG's clusters, then Strimzi's pod
   sets, then the StatefulSets - each back on the new sidecar AND ready before the next, the apps after them all, each
   Deployment rolled out (`rollout status`). CNPG rolls its replicas, then restarts its primary **in place** (its
   `primaryUpdateMethod` is CNPG's default, `restart` - not a switchover): the primary's writes stop until it is up
   again (copy run 6's classic restart: the data tier back in ~100 s); a committed write is safe on the primary's own
   volume (its WAL fsync'd) and on the streaming replica. Native sidecars may lengthen a CNPG instance's stop (the
   proxy outlives Postgres; its smart shutdown waits for clients, up to CNPG's `smartShutdownTimeout`, 180 s by
   default): measured on the copy - the way back's restart stops native pods - before production. A switchover
   (`primaryUpdateMethod: switchover`) is a change of its own, not this one.
5. **Kafka's consumers: a record given up on is found and replayed.** No app sets a Kafka error handler: Spring Kafka's
   default tries a failing record 10 times without a pause, then skips it and commits its offset - a record consumed
   while its store restarts (chat-persistence into ScyllaDB, user-sync into Postgres) would be lost but for Kafka. The
   last 7 days hold no such log line (ClickHouse, 2026-11-18 - the morning's mesh restart among them). The gate: no log
   line of a record given up on ("Backoff ... exhausted", "Failed to persist", "Error handler threw") in production
   or test from the switch's start to its end (prod-native-verify.sh). One found: replayed from Kafka (its 7 days'
   retention) - Argo's auto-sync off for that app, its Deployment at 0, the group's offset reset to the skipped record
   (`kafka-consumer-groups.sh --group <g> --topic <t>:<p> --reset-offsets --to-offset <o> --execute`), the app back
   (auto-sync on); chat-persistence and user-sync write by key (a re-read upserts, no duplicate). The fix of the
   cause - each consumer's handler backing off past a store's restart - is the next plan, not this one.
6. **The way back rehearsed** in the same copy run - after a failed native phase too: `ENABLE_NATIVE_SIDECARS: "false"`
   and the restart playbook (`-e sidecar_mode=classic`) bring every pod back to classic. A pod stuck in its new mode
   (CNPG rolls only ready instances; an OrderedReady StatefulSet waits on its broken pod) is deleted by hand - a CNPG
   replica before its primary, then the playbook again.
7. **The alerts see a native proxy before the switch**: PodRestartingFrequently, ContainerOOMKilled,
   PodCrashLoopBackOff and KubePodCrashLooping read the init containers too (platform, promtool-tested; plan 125's
   closed list, item 3) - live before istiod's flag moves.
8. Nothing in production until the copy run is green, the full review clean and the gates below pass.

## Production, in order

1. The platform alerts (item 7) live; ops main holding the playbook and the checks (this branch); `task
   check:production:data` green.
2. Backups: `scratchpad/prod-backups-now.sh` - green, each store.
3. Before: `prod-data-counts.sh <before>`; the live consumer groups (`bundle.sh prod-native-verify.sh .native-check |
   ssh sm@192.168.11.2 'MODE=groups bash -s'`); the switch's start time (UTC) noted.
4. infra's commit (istiod-values.yaml: `ENABLE_NATIVE_SIDECARS: "true"`) pushed to main; Argo syncs istio; wait until
   istiod's Deployment carries `"true"` and has rolled out (`kubectl -n istio-system rollout status deploy/istiod`).
5. `task deploy:mesh:restart -- -e istio_version=1.31.4 -e sidecar_mode=native` (it refuses while istiod still
   injects classic).
6. `prod-native-verify.sh MODE=native SINCE=<start> GROUPS_WANT=<before>`: RESULT-OK (every meshed pod native, every
   CNPG cluster healthy and streaming, every group live again, 15 min held by uid, no record given up on, every Argo
   app green).
7. After: `prod-data-counts.sh <after>`, then `--compare <before> <after>`: no LOSS.
8. `task check:production:kafka-backup` (the dump through its guard, every partition read through a native sidecar);
   `task check:production:data`.

**The way back, at once, when** step 5, 6, 7 or 8 is red, or an alert of item 7 fires on a proxy: infra's revert
pushed (`"false"`), istiod rolled out, `task deploy:mesh:restart -- -e istio_version=1.31.4 -e sidecar_mode=classic`,
`prod-native-verify.sh MODE=classic`, the counts compared again; a record given up on replayed (item 5).

## Changes

- infra: `clusters/production/istio/istiod-values.yaml` - `ENABLE_NATIVE_SIDECARS: "true"`.
- ops: `restart-mesh-workloads.yml` - a pod of the other mode than istiod injects restarted (its own
  `sidecar.istio.io/nativeSidecar` by Istio's rule: set, native unless exactly `"false"`); the data tier one workload at
  a time; each restarted Deployment and DaemonSet rolled out; `-e sidecar_mode` asserted against istiod's; the Jobs
  left named. Harness restart-mesh-order (the flip both ways, an annotation keeping a pod, a pod back in the wrong mode
  never green, each gateway label alone, one at a time, a stuck rollout, the guard). argo-settled.py and
  upgrade-verify.sh read a pod's native sidecars (their harnesses: one unready, one OOM-killed).
- platform: the pod alerts read `kube_pod_init_container_*` (tests/rules/native-sidecar.test.yaml).
- scratchpad tools (not shipped): native-check.sh, prod-native-verify.sh, prod-data-counts.sh with counts-compare.py,
  mesh-pods.py, hold-compare.py, bundle.sh; argo-sync-hooks.sh; copy-run-1118k.sh.

## Proof (the copy, copy run 8)

1. Built; `native-check snap`: the meshed pods, the live groups, every Postgres table's count, Kafka's offsets.
2. The change (infra's branch) and every check (test:copy:check - data, survival, storage, metrics with every target
   up, the k6 smoke, production's data paths, isolation, the ClickHouse, ScyllaDB, Postgres and Velero restore
   rehearsals); the restart playbook `-e sidecar_mode=native` and every check again.
3. `native-check native`: every meshed pod native; every CNPG cluster healthy, the primary streaming; every group live
   again; 15 minutes held - the same pods by uid, none restarted, each Running and ready (an operator rolling its pods
   for the init container it did not make: caught); no Kafka record given up on; no data lost.
4. The meshed hooks' Jobs on native sidecars: schnappy-observability's and schnappy-sonarqube's syncs - clickhouse-init
   and sonarqube-setup Succeeded (argo-sync-hooks.sh). The Kafka dump and restore through native sidecars
   (test:copy:kafka-restore).
5. The way back - after a red native phase too: `"false"`, the playbook `-e sidecar_mode=classic`, every check,
   `native-check classic`; each data workload's restart time in the log, classic against native (item 4).

Not proven by the copy: a producer's sends during the broker's restart (the copy runs no load then) - production's
switch runs in a quiet hour, and item 5's gate reads every consumer's skips. An app's database login is not proven by
its pod's readiness (no app's readiness group holds a database check): the k6 smoke and the production data-paths check
go through the apps to their stores, and every consumer group live again says each consumer reconnected.
