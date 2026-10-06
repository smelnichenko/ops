# Plan 100 — upgrade the cluster to current releases

Status: **IN PROGRESS** (2026-10-05): step 02 (old 19: Istio charts from blob.istio.io) is in production since
2026-10-03; the steps are reordered (operator's decisions 2026-10-05). The gate before any other production change
(operator 2026-10-05: "full run and full review at the end before live"):
1. the open fixes done - R14 (test environment before production for the data versions), R18 (abort and outage
   notes per step), R27 (the defaults at the targets, a fresh build at them, a green task dr:drill) - ALL DONE
   2026-10-05;
2. full run 7 green: task test:upgrade:full - a fresh Vagrant copy, all steps in order with every check, the
   restore checks at the end, unattended;
3. a full review of the whole upgrade work after that run (not only what changed since the last one); its findings
   fixed and proven, and the full run repeated if a fix touches the steps or the harness - the review of 2026-10-06
   (below) is done and its fixes in; the full run that proves them is next, then another full review;
4. then production, step by step, each with the operator's approval - Wave 0 backup first for every one-way step,
   every stateful step shown before it runs.

## Decisions (operator, 2026-10-01)

- Upgrade every component to its latest release, kagent excepted (left as it is).
- PostgreSQL 18: **option A** — in-place major upgrade by CNPG on the same Debian bullseye image line
  (`18.6-system-bullseye`, pinned by digest). The move to the trixie image line is a later, separate step.
- ScyllaDB: move from 6.2 (last AGPL release) to the source-available 2025.x/2026.x line (free tier: 50 vCPU / 10 TB
  per organisation; the operator sizes each node from its resources - limit 4 CPU).
- Kubernetes stops at **1.36.5**: no Istio release supports 1.37 and Cilium 1.20 is tested only to 1.36. 1.37 waits for
  Cilium 1.21 and Istio 1.32.
- Host changes on `ten` (kubeadm, kubelet, containerd, Cilium) run **through Ansible playbooks**, never by hand.
- **Every step is first proven in a full Vagrant upgrade test**; production changes start only after all tests pass and
  the operator approves, one step at a time.

## Versions

| Component | Now | Target | Path |
|---|---|---|---|
| Kubernetes (kubeadm) | 1.34.6 | 1.36.5 | 1.34.12 → 1.35.9 → 1.36.5 (one minor per run) |
| etcd / CoreDNS | 3.6.5 / 1.12.1 | 3.6.8 / 1.14.2 (kubeadm 1.36.5's) | with kubeadm; etcd ≥ 3.6.11 is etcd 3.7's prerequisite - k8s 1.37, not now |
| containerd | 1.7.24 (Debian; nerdctl-full's 2.0.2 binaries in /usr/local run nothing - defect 4) | 2.3 LTS | one install, from Docker's apt repo |
| Cilium (+ Hubble UI) | 1.19.1 (0.13.3) | 1.20.2 (0.13.6) | 1.19.8 → 1.20.2 |
| Istio | 1.25.2 (EOL, unsupported on k8s 1.34) | 1.31.1 | in place, one minor per step (operator 2026-10-03): 1.26 → … → 1.31, mesh workloads restarted each step; charts from blob.istio.io first (defect 17) |
| Gateway API CRDs | v1.2.1 | v1.5.1 (operator 2026-10-05: not v1.6) | before Istio 1.30 |
| Argo CD | 3.3.8 (chart 9.5.4) | 3.5.3 (chart 10.9.6) | 3.3.14 → 3.4 → 3.5 |
| cert-manager | 1.20.0 | 1.21.2 | 1.20.4 → 1.21.2 |
| External Secrets | 2.2.0 (CRDs never upgraded) | 2.11.0 | CRDs under Argo first, then 2.2 -> 2.11 directly (only the newest minor is supported) |
| CloudNativePG | 1.29.0 | 1.30.1 | direct |
| PostgreSQL | 17.9 (bullseye system image) | 18.6 | CNPG offline in-place upgrade |
| Strimzi / Kafka | 0.51.0 / 4.2.0 | 1.2.0 / 4.3.1 | v1 CRD conversion on 0.51 → 1.2.0 → Kafka 4.3.1 |
| Scylla Operator | 1.20.2 | 1.22.0 | 1.20.3 → 1.21.1 → 1.22.0 (N+1 only) |
| ScyllaDB (prod, test) | 6.2.3 | 2026.1.14 LTS (operator 2026-10-05) | 2025.1.16 → (op 1.21) → 2026.1.14 → (op 1.22); the test environment first each time |
| ScyllaDB (manager backend) | 2026.1.0 | 2026.2.5 (the Manager chart v1.22.0's; Manager 3.12 lists 2026.2, not 2026.3) | with the operator steps |
| Scylla Manager + agent | 3.9.0 | 3.12.1 | 3.10 → 3.12 with the operator (3.12.1 pinned; the chart ships 3.12.0) |
| Valkey | 8.1 | 9.1 | direct (emptyDir: cache wiped) |
| Velero / AWS plugin | 1.18.0 / 1.11.1 (off-matrix) | 1.18.4 / 1.14.4 | direct |
| versitygw (cluster, Pi) | 1.6.0 | 1.8.0 | cluster first, Pi outside 02:00–04:00 |
| local-path-provisioner | 0.0.35 | 0.0.37 | direct (Rancher's manifest, applied by setup-kubeadm.yml - no chart) |
| kube-prometheus-stack | 82.16.0 (Prometheus 3.10, operator 0.89) | 91.8.2 (3.15, 0.94.1) | direct, CRDs by Argo |
| Alertmanager / blackbox / ksm | 0.31.1 / 0.27.0 / 2.18.0 | 0.34.1 / 0.28.0 / 2.20.0 | direct |
| Grafana | 12.4.2 | 13.2.3 | 12.4.12 → 13.2.3 |
| Mimir | 2.17.8 | 3.2.1 | 2.17.11 → 3.0 → 3.1 → 3.2 |
| Tempo | 2.7.2 | 3.1.0 | one-way; config rewrite |
| Fluent Bit | 4.2.3.1 | 5.1.3 | 4.2.8 → 5.1.3 |
| ClickHouse | 24.8 LTS | 26.8 LTS | 24.8 → 25.8 → 26.8 |
| Centrifugo | 6.7.1 | 6.9.7 | direct (expired sub tokens now disconnect: 3006) |
| SonarQube CE | 26.3.0 | 26.9.0 | direct; the setup hook starts the DB migration (`/setup`'s call) |
| Woodpecker | 3.18.1 | — | already latest |

## Defects to fix first (they break the upgrades)

1. Cilium `bpf-lb-sock-hostns-only=true` is set by `kubectl patch` (ops `bootstrap.sh`), not in the Helm values: any
   `helm upgrade` drops it and breaks Istio. Move it to `socketLB.hostNamespaceOnly: true` in `setup-kubeadm.yml`.
2. External Secrets runs `installCRDs: false`: its CRDs are whatever was first installed and are never upgraded.
3. velero-plugin-for-aws 1.11.1 belongs to Velero 1.15; Velero 1.18 pairs with 1.14.x.
4. ~~Two containerd installs on ten~~ — not on ten: ten runs only Debian's containerd 1.7.24 (its unit in
   /usr/lib). The Vagrant VM is the one with two: setup-kubeadm.yml installs nerdctl-full (for test:cicd), whose
   containerd 2.0.2 unit in /usr/local overrides Debian's — so the Vagrant node ran a different containerd than
   production. (History: ten ran Docker's containerd.io 2.2 from 2026-02-15 until the kubeadm migration replaced it
   with Debian's 1.7.24 on 2026-03-30; Docker's apt repo is still configured on ten.)
5. containerd 1.7.24 is below the Kubernetes 1.34 floor (1.7.28).
6. The Postgres image `ghcr.io/cloudnative-pg/postgresql:17` is a deprecated rolling tag: pin a digest.
7. Strimzi v1beta2 templates (`kafka-users.yaml`, `kafkatopic-events.yaml`, ops test-realtime.yml) must move to v1.
8. local-path-provisioner chart is unpinned; its image pre-pull says 0.0.36 while 0.0.35 runs.
9. `git.pmon.dev/schnappy/apt-cacher-ng:1.0` is gone from the registry; ten runs it only from its node cache (a
   rebuilt node or DR restore could not pull it). Built by hand once (2026-03-17), never in CI. Fix (operator
   2026-10-02, options 2+3): platform 7b46aea builds `apt-cache/` in CI, tagged with the commit; the new tag is
   deployed in Wave 1 as a values change, tested in Vagrant first.
10. A fresh CNPG cluster never bootstraps: platform `helm/schnappy-data/templates/cnpg-cluster.yaml` gives initdb
    `secret: <cluster>-app`, which nothing creates (on ten CNPG generated it on 2026-04-10 through a path that named
    no secret). Found by the Vagrant build ("secret schnappy-production-postgres-app not found"); the DR drill misses
    it because it restores through `recovery`. The Vagrant test recreates ten's Secret (tests/ansible/upgrade/
    production-state.yml). Refined 2026-10-02: on ten the -app Secret names user `app`, not the owner `monitor`, so
    CNPG's owner-password sync FAILS every few minutes ("wrong username 'app' in secret, expected 'monitor'", 6-7/h
    in the operator log) - and only that failure keeps monitor's password: a correct-username Secret with another
    password made CNPG reset monitor's role on the next Postgres restart (Vagrant). Fix, proven in Vagrant: the -app
    Secret is an ExternalSecret from Vault's postgres-monitor (basic-auth, username monitor, monitor's own password) -
    a fresh cluster bootstraps, CNPG's sync agrees with init-users, the error loop ends; monitor survived a primary
    restart/failover with it. For production: the ExternalSecret in the data chart (replacing the CNPG-owned Secret).
11. Objects on ten that no git repo creates (made by hand; a rebuild loses them): ServiceAccounts
    schnappy-{alertmanager,grafana,mimir,reports} in schnappy-infra (the observability chart runs its pods as these;
    the mesh chart creates schnappy-infra-*), five KafkaTopics from 2026-04-10; also hand patches now in the playbooks
    (Cilium bpf-lb-sock-hostns-only, the /usr/lib/cni link). (The caddy-cert-reader RBAC is not hand-made:
    setup-caddy.yml applies it.) The Vagrant test recreates the ServiceAccounts (production-state.yml); fix: create
    them in the charts.
12. A production REBUILD under Argo comes up broken (the DR drill restores into a cluster that already has Istio, so it
    never sees this): the root app-of-apps waits for nothing (no argoproj.io/Application health check), so the app
    sets start pods before istiod's injector exists - no sidecars, all traffic reset by STRICT mTLS. Fixed and proven
    in Vagrant (ops 8e95262): the health check in setup-argocd.yml, and sync waves - cert-manager -2; Prometheus -1
    (its CRDs before cluster-config's ServiceMonitors); scylla-manager 0 (after scylla-operator); the app sets 4
    (after Istio); observability 5 (after the infra data set's S3 secret). The waves are Vagrant-only patches in the
    mirror (INFRA_SYNC_WAVES) until approved for infra; applying them on ten is harmless (they order creation only).
13. `setup-caddy.yml` read the wildcard Secret and applied its RBAC with the controller's own kubectl
    (`delegate_to: localhost`): whichever cluster the operator's kubeconfig named, so a run against any other inventory
    read and wrote production. Fixed (2026-10-03): it runs kubectl on the inventory's `target` with its admin
    kubeconfig - on ten the same endpoint, https://192.168.11.2:6443.
14. The `schnappy` realm exists only in production's Keycloak database; git holds just the auth chart's realm-import
    template (platform `helm/schnappy-auth`, from when Keycloak ran in the cluster), so the clients' redirect URIs and
    every later change are nowhere else. The Vagrant copy builds its realm from that template
    (`tests/ansible/upgrade/keycloak-realm.yml`). Fix: keep the realm (without secrets) in git and apply it from there.
15. The Hyperfoil load test runs `git.pmon.dev/schnappy/hyperfoil:latest`: a floating tag, pulled on every run (pull
    policy Always), so what runs at 03:00 is whatever was pushed last and no rebuild or copy can pin it. Off in the
    Vagrant copy (it cannot reach production's registry). Fix: commit tags, like every application image.
16. CNPG backs up with the in-tree Barman Cloud support (`barmanObjectStore`), deprecated in 1.30 and removed in 1.31:
    the move to the Barman Cloud Plugin must come before any CNPG 1.31 (this plan stops at 1.30.1).
17. Istio's charts come from istio-release.storage.googleapis.com, which Istio retires from 1.31 on (planned outages
    2026-10-13 15:00-18:00 UTC and 2026-11-17, off from 2026-12-09): ten's three Istio Argo apps would stop syncing.
    blob.istio.io serves the same charts (1.25.2 through 1.31.1). Step 19 moves them, nothing else - it can go to
    production on its own, before the first outage.
18. ClickHouse has a `default` user the config says it has not: clickhouse-users.xml replaces the users with
    `schnappy` only, but the StatefulSet sets CLICKHOUSE_USER=default with CLICKHOUSE_PASSWORD, so the image's
    entrypoint writes users.d/default-user.xml, merged after it - `default`, with that password, from ::/0 (found by
    the ClickHouse upgrade review, 2026-10-03). Not upgrade-related; fix: CLICKHOUSE_SKIP_USER_SETUP=1, or name the user.
19. `setup-argocd.yml` merge-patched the root Application on every run with a spec unlike infra's apps/root.yaml (no
    RespectIgnoreDifferences - a merge patch replaces the list - and an extra directory.recurse): each run put the
    root OutOfSync, the root re-applied itself mid-sync and could lose its .operation, sitting 'Running' with
    nothing syncing (Vagrant, the Argo CD 3.3.14 step; ten's 10-01 run recovered by luck). Fixed: the root is created
    only when absent, exactly as git has it - the Argo CD steps (12, 29, 30) rely on this.
20. Velero backs up none of production's data volumes. Every PV is a local-path hostPath volume, which Velero's
    file-system backup does not support: ten's velero-schnappy-daily (2026-10-03, 20 min) holds 79 volume backups,
    all emptyDirs (sidecar sockets and certs, tmp, scratch), and no pgdata or data volume; velero-full-weekly backs up
    every namespace the same way (its last run, 2026-09-27, ended PartiallyFailed). What does protect data: CNPG's
    barman backups of Postgres (hourly, completed), etcd hourly. Kafka and ScyllaDB have none (no Scylla Manager backup
    task). Not upgrade-related, not fixed by it; found by the backup check's slowdown, 2026-10-03. Fix options for the
    operator: local-path's `local` volume type (Velero supports it) for new volumes, Scylla Manager backups,
    Kafka mirror or tiered storage.

21. `setup-gluster.yml` disrupted every re-run and never replicated a fresh install in full. Its mount plays stopped
    every service and unmounted every volume on every run ("Unmount if already mounted with different source" had no
    condition): each re-run took Forgejo and Nexus down, and the backup store's gateway - listed as `minio`, gone since
    versitygw - kept serving the local disk under the unmounted store, where writes would vanish behind the remount.
    And a fresh install copies existing data straight into pi1's brick, which Gluster never learns of: pi2 got only
    what something touched (neither heal nor `heal full` copied the rest). Fixed: only a volume not mounted from itself
    is (re)mounted, its service (versitygw for the store) stopped around it and started after; each volume the run
    created gets every entry looked up through pi1's mount, pi2's brick must then hold every path pi1's does, and
    their heals must finish. A re-run on ten stops, unmounts and crawls nothing. Found 2026-10-04 by the Vagrant copy,
    which never ran setup-gluster: each Pi kept its own store and a VIP on pi2 found no velero bucket (full run 4);
    its first build with Gluster had pi1 listing 5 buckets, pi2 2 (run 5).

## The Vagrant upgrade test

The step runner in the ops Taskfile (`task test:upgrade:build`, `task test:upgrade:step STEP=<step>`,
`task test:upgrade:full`) with its playbooks in `tests/ansible/upgrade/`, run detached like the DR drill.

1. **Baseline = production today, proven by diff.** `scripts/version-inventory.sh` lists every versioned component
   (host packages, binaries, Helm releases, Argo chart sources, images, CRD bundles); production's list is
   `tests/ansible/upgrade/prod-inventory.txt` (2026-10-02). The baseline counts only when the VM's list matches it
   (application images aside). VMs on Debian **trixie** (the current box is bookworm: change it), the kubeadm
   stack at today's versions through the same playbooks and charts production uses.
2. **Seed data** that must survive: Postgres rows and a CNPG backup, Kafka topics with messages, Scylla keyspaces with
   rows, Mimir series, Tempo traces, ClickHouse logs, a Grafana dashboard, SonarQube project.
3. **Run every step through the new upgrade playbooks / git value changes, in production order.** After each step:
   all pods ready, Argo-equivalent sync clean, the seeded data read back, the service's own health check.
4. **End:** the k6 smoke, the DR drill suites (Velero + barman restore), and a check that every version is the target.
5. Any failure stops the run with diagnostics (events, describe, logs) — the harness pattern from the DR drill.

Fidelity and isolation of the Vagrant copy (2026-10-02/03):
- **Isolated from production** on every VM: the kubeadm node and its pods by `isolate-cluster.yml` (CoreDNS answers
  `*.pmon.dev` with Vagrant addresses; nftables + a Cilium policy drop the production LAN; a probe proves it), the Pi
  VMs by `tests/ansible/isolate-pis.yml`, first in every Vagrant flow - before it, libvirt's DNS resolved
  git/auth/vault.pmon.dev on them to production's VIP (nothing had used it: no webhooks, connections or log lines).
- **Production's own `*.pmon.dev` certificate** (operator, 2026-10-03): copied from ten into the Vagrant cluster
  (`production-state.yml`) and served by Caddy on the Vagrant Pis as on the real ones, because every in-cluster client
  of https://auth.pmon.dev verifies it against public CAs. A Vagrant-issued certificate failed all of them. The copy
  has no Certificate for it (the mirror drops the mesh chart's): cert-manager replaced the copied Secret at once.
- **Keycloak** gets production's realm from git (defect 14), before Argo: istiod fetches the realm's keys at start.
- **The k6 smoke** runs as in production (the chart's PostSync hook) and on demand after each step
  (`scripts/vagrant-smoke.sh`).
- **Each step** (`task test:upgrade:step STEP=NN-name`): a step is `tests/ansible/upgrade/steps/NN-name.txt` (its
  inventory changes) plus a branch `upgrade/NN-name` in infra and/or platform, stacked on the previous step's branch
  in that repo - merged to main in this order at the rollout. The runner mirrors each repo's latest step branch,
  runs the step's own playbook lines (host-side changes; not an earlier step's - replaying a Helm install would
  downgrade it), re-proves the isolation, waits until every Argo app is synced to exactly those commits with all pods
  ready, checks the seeded Postgres rows
  on every instance (`data-check.yml`), runs the smoke, and diffs the inventory against production's plus every
  step's changes so far (`scripts/upgrade-expected-inventory.py`).
- **Steps proven** one by one: 01-55 by 2026-10-04 06:23 (the step table below). Steps marked so also take a Velero
  backup from production's daily schedule (`backup-check.yml`); every step provisions a new volume (`storage-check.yml`).
- **Argo green is not "the operator has finished"**: after the CNPG operator upgrade Argo settled at once, and CNPG
  restarted both instances a minute later, while the checks ran. The data check now first waits for every instance
  to run under the new operator version. Each operator step (Strimzi, Scylla) needs the same wait for its own
  rollout before its checks count.
- **The isolation's CoreDNS `template` blocks stop `kubeadm upgrade`** when it bumps CoreDNS (step 42, v1.12.1 -> v1.13.1):
  preflight CoreDNSUnsupportedPlugins refuses a Corefile plugin its migration does not know. Ten's Corefile has none,
  so only the Vagrant inventory passes over that one check (`k8s_upgrade_ignore_preflight_errors_override`); kubeadm
  migrates the rest and leaves the blocks as they are.
- **Every upgrade test playbook refuses to run anywhere but the Vagrant VMs** (`tests/ansible/vagrant-only.yml`, the
  first task of each play): the host's own addresses must be in 192.168.56.0/24 and none in production's
  192.168.11.0/24 - no inventory or `-e` decides. Proven both ways 2026-10-04: data-check and restore-check pointed at
  production stopped at that task (only `hostname -I` ran on ten); the Vagrant VMs pass. Before, nothing stopped
  data-check seeding a table into production's database, or isolate-cluster rewriting ten's CoreDNS.
- **The end of the full run proves the backups restore** (`restore-check.yml`, also `task test:upgrade:restore-check`):
  Postgres recovered from its barman object store into a side cluster with every seeded row (after the PostgreSQL 18
  step that is also the fresh base backup it needs), and a Velero file-system backup of a test namespace restored
  with its emptyDir's random token intact. Production's namespace is never replaced; its names are fixed and refuse
  an `-e` override. The plan's end-of-test restore, which the runner lacked until 2026-10-04.
- **Backup checks only where a step touches a backup** (operator, 2026-10-04). The Velero check (production's schedule,
  ~8 min) runs after 10 and 25 only - Velero and its store: it holds no data volume (defect 20), so after any other
  step it guarded the least valuable backup at half a step's time; it ran after every step until full run 2. The
  backup production's data depends on, CNPG's barman backup of Postgres, is checked after 24 (the CNPG operator), 25
  (its store) and 47 (PostgreSQL 18): WAL archiving working and a fresh base backup completed (`barman-check.yml`).
  Step files mark them (`backup-check`, `barman-check`); the restore check closes the run.
- **ClickHouse's compatibility pin applies at the next start**: the users file is a subPath mount, which never sees a
  ConfigMap change, so steps 58 and 60 change nothing in the running server; the image bumps right after them (59,
  61) restart it with the pin in place before the new version writes a part - the order that matters. Checked with
  `getSetting('compatibility')` after each step.
- **A step that goes to production early leaves the stack**: it is cherry-picked onto main, the repo's step branches
  are rebased on that main (`git rebase --update-refs main <last step branch>`; git drops the now-duplicate commit),
  and its own branch is deleted. Step 19, 2026-10-03: every later branch's tree unchanged, 02-16 gained only it.
- **The inventory lists what runs or is set to run**: pods not finished, CronJob templates, Jobs no CronJob owns. It
  listed finished pods too, so a CronJob's kept runs showed the image it had just left for hours (step 16: the etcd
  backup on etcd 3.6.5-0 beside the new 3.6.6-0). Production's baseline is the same under both (re-taken read-only
  2026-10-03) but for the k6 smoke Job's two images, there only for the 24 h after a sync.

New playbooks (ops): `upgrade-kubeadm.yml` (one minor per run, `kubeadm upgrade apply`, kubelet/kubectl, drain-free
single node), `upgrade-containerd.yml`, Cilium/Istio/Gateway-API steps as variables of the existing playbooks.

## Upgrade steps (tests/ansible/upgrade/steps; each a Vagrant run before production)

Branches `upgrade/NN-*` in infra/platform (local until approved), stacked per repo; host-side steps as playbook lines.
S = stateful (shown to the operator with the exact change before it runs in production). Status 2026-10-03.

**Every step green on its own in Vagrant: 2026-10-04 06:23** (01-55; 51 changes nothing in the copy). Full run 1
(06:24): build and steps 01-15 green, step 16 failed - upgrade-kubeadm.yml finished while the new kubelet restarted
the control plane (fixed efb07bb). Full run 2 (11:04): steps 01-23 green, stopped at 24 by the operator to restart
with every fix - the guards, backup checks only on their 17 steps, the restore check at the end. Full run 3 (17:54):
stopped by the operator during its build. Full run 4 (18:03): failed at step 04 - the build had no Gluster, the VIP on
pi2 found no velero bucket (defect 21). Full run 5 (19:24): stopped - new volumes not replicated to pi2 (the lookup
crawl). Full run 6 (20:02): failed in the build - the Gluster mounts did not come back after the snapshot reboot
(defect 22). Full run 7 (2026-10-05 17:50): failed at step 09 (a cold start); then stopped to cut its time.
2026-10-06, after the full review: full run 05:46 failed at step 13 - the kubelet's shutdown grace compared as text
(kubeadm writes "3m0s", the step expects "180s"; compared in seconds since). Full run 08:10: steps 00-12 green, step
13 failed - `kubeadm upgrade apply` restarted etcd, the kubelet brought it back only after 2 min 2 s (its volume
manager sat on PVC reads the API server held for its 60 s request timeout while etcd was down, until the API server's
liveness probe restarted it), kubeadm's etcd client had given up at its default 2 m. Not rolled back: kubeadm had
reported etcd upgraded, and it returns only a component whose own restart fails - the node was half-applied (etcd on
its new manifest, the rest 1.34.6), and the re-run finished it; the abort lines of 13, 42 and 43 say so since. Fixed
in upgrade-kubeadm.yml (f76c27b): an UpgradeConfiguration whose etcdAPICall equals upgradeManifests, kubeadm's 5 m
for any static pod; step 13 green again on that copy (etcd down 26 s that time). Full run 10:44: failed in its build
- setup-patroni's restore of the Keycloak dump connected through HAProxy in the same second HAProxy marked the new
leader up (two checks 3 s apart), and found no server; the restore goes straight to the leader's Postgres since
(test:patroni-keycloak-restore runs it with HAProxy stopped). Full run 11:00: build 48 min, steps 00-34 green in
2 h 56 min (13: the apply 1 min 55 s), stopped in step 35's first settle - after Argo CD 3.5 (step 34) cluster-config's
spec keeps an empty `directory.jsonnet: {}` its status.sync.comparedTo leaves out, and argo-settled.py (production's
settle too, upgrade-production.py) compared the two literally: "compared against an older spec" for ever. It compares
them without empty fields since. Full run 15:01: build 53 min, steps 00-36 green, step 37 failed in its preview (the
full review's --check before every step's playbooks; no run had reached a step after 35 with it): the conversion is
skipped in check mode and the closing message read its proof. The preview now says what it would do (postgres-analyze's
too); step 37's preview green on that copy. Steps 37-61 on that copy (no step after 35 had run with the preview and
the settle as they are): 37-41 green; 42 failed its survival check - the Vagrant Mimir overlay sends queries older
than 1 h to the store-gateway, which skipped blocks with samples from the last 10 h, so once the querier expected the
seed's block every query over it failed the consistency check (the overlay switches that filter off since; production
keeps Mimir's 12 h / 10 h); 43 failed its settle - the controllers holding leader leases (cert-manager, CNPG,
Cilium's and Scylla's operators) restart with the API server in both Kubernetes upgrades, read as a crash loop "in
two steps running" (a restarts-control-plane line on 13, 42 and 43 records them without judging, production's settle
too); 47's undo rehearsal refused by CNPG's webhook - its image a bare digest (now postgresql:17@sha256:..., a
restore-undo image without a tag refused by the parser) - and then its inventory caught the side cluster's pod still
terminating (side clusters deleted in the foreground since); 50 - Grafana 13 updated its bundled Prometheus plugin at
start, the image's copy removed first, which the read-only root filesystem refused with the plugin unregistered: the
Mimir datasource answered "Plugin not registered", and every Mimir dashboard would have broken in production. A
platform branch for 50 now (the chart's pluginsPreinstallAutoUpdate, merged first, rendering nothing alone; infra sets
it with the image), platform 54-61 and infra 51-61 restacked on it; 51 - its Wave 0 gateway backup refused
versitygw 1.8's .vgwlocks as a bucket without an ACL (production's Wave 0 after step 25 the same; dot directories are
no buckets since). Steps 51-61 and the restore check then green on that copy (21:27). Next: the full run again, from
nothing, then the full review.

**Gate before the production rollout** (operator, 2026-10-03; 2026-10-05): full run 7 green - `task test:upgrade:full`: the Vagrant copy built from nothing, then every step below in order, unattended, every check after each - then a full review of the whole work, then production step by step ("Production, step by step" at the end).

The steps (generated from tests/ansible/upgrade/steps - the step files are the source; Wave 0 = the stores backed up before the step, in production and in the full run):

| # | Step | Changes | Where | Wave 0 |
|---|---|---|---|---|
| 00 | gluster-boot | The Pis' and ten's Gluster setup as ops main has it (setup-gluster.yml), before any upgrade | playbook | - |
| 01 | argocd-root-retry | What a fresh install of the cluster needs from Argo CD, in git (infra) | infra | - |
| 02 | istio-chart-repo | Istio's charts from blob.istio.io, same 1.25.2 | - | - |
| 03 | istio-1.26 | Istio 1.25.2 -> 1.26.8, in place (one minor: Istio's in-place rule) | infra + playbook | - |
| 04 | istio-1.27 | Istio 1.26.8 -> 1.27.9, in place (one minor: Istio's in-place rule) | infra + playbook | - |
| 05 | istio-1.28 | Istio 1.27.9 -> 1.28.10, in place (one minor: Istio's in-place rule) | infra + playbook | - |
| 06 | istio-1.29 | Istio 1.28.10 -> 1.29.8, in place (one minor: Istio's in-place rule) | infra + playbook | - |
| 07 | gateway-api | Gateway API CRDs v1.2.1 -> v1.5.1 (before Istio 1.30) | playbook | - |
| 08 | istio-1.30 | Istio 1.29.8 -> 1.30.5, in place (one minor: Istio's in-place rule) | infra + playbook | - |
| 09 | istio-1.31 | Istio 1.30.5 -> 1.31.1, in place (one minor: Istio's in-place rule) | infra + playbook | - |
| 10 | velero | Velero 1.18.0 -> 1.18.4 (chart 12.0.0 -> 12.2.0, image pinned to the newest patch) and the AWS plugin 1.11.1 -... | infra | - |
| 11 | cilium | Cilium 1.19.1 -> 1.19.8 (Hubble UI 0.13.3 -> 0.13.6), the first platform step | playbook | - |
| 12 | kubelet-shutdown-grace | The kubelet's graceful node shutdown (180 s, 30 s for critical pods) into the kubelet-config ConfigMap, before... | playbook | - |
| 13 | kubernetes-1.34.12 | Kubernetes 1.34.6 -> 1.34.12 (patch) | playbook | etcd |
| 14 | containerd | containerd: Debian's 1.7.24 (below Kubernetes 1.34's 1.7.28 floor, end of life 2026-09-30) -> containerd.io 2.... | playbook | - |
| 15 | scylla-operator-1.20.3 | Scylla Operator + Manager charts v1.20.2 -> v1.20.3 | infra | - |
| 16 | scylladb-2025.1-test | ScyllaDB 6.2.3 -> 2025.1.16 in the test environment, before production's (operator 2026-10-05: the test enviro... | infra | - |
| 17 | scylladb-2025.1 | ScyllaDB 6.2.3 -> 2025.1.16 in production, after the test environment (step 16) | infra | scylla |
| 18 | scylla-operator-1.21 | Scylla Operator + Manager charts v1.20.3 -> v1.21.1 | infra | - |
| 19 | scylladb-2026.1-test | ScyllaDB 2025.1.16 -> 2026.1.14 in the test environment, before production's (operator 2026-10-05) | infra | - |
| 20 | scylladb-2026.1 | ScyllaDB 2025.1.16 -> 2026.1.14 in production, after the test environment (step 19) | infra | scylla |
| 21 | scylla-operator-1.22 | Scylla Operator + Manager charts v1.21.1 -> v1.22.0 | infra | - |
| 22 | apt-cacher-ng | apt-cacher-ng from its CI build | platform | - |
| 23 | cert-manager | cert-manager v1.20.0 -> v1.20.4 (patch releases) | infra | - |
| 24 | cnpg | CloudNativePG operator 1.29.0 -> 1.30.1 (chart 0.28.0 -> 0.29.1); restarts every Postgres instance in place | infra | - |
| 25 | versitygw | versitygw v1.6.0 -> v1.8.0 | platform + playbook | - |
| 26 | local-path | local-path-provisioner v0.0.35 -> v0.0.37 | playbook | - |
| 27 | kube-prometheus-stack | kube-prometheus-stack 82.16.0 -> 91.8.2 | infra | - |
| 28 | grafana | Grafana 12.4.2 -> 12.4.12 (patch releases; 13.x is a later step) | infra | - |
| 29 | mimir | Mimir 2.17.8 -> 2.17.11 (patch releases; 3.x is a later step) | infra | - |
| 30 | fluent-bit | Fluent Bit 4.2.3.1 -> 4.2.8 (patch releases; 5.x is a later step) | infra | - |
| 31 | argocd | Argo CD v3.3.8 -> v3.3.14 | playbook | - |
| 32 | cilium-1.20 | Cilium 1.19.8 -> 1.20.2 (the next minor, from the latest patch of the previous one, as Cilium requires) | playbook | - |
| 33 | argocd-3.4 | Argo CD v3.3.14 -> v3.4.6 | playbook | - |
| 34 | argocd-3.5 | Argo CD v3.4.6 -> v3.5.3 | playbook | - |
| 35 | cert-manager-1.21 | cert-manager v1.20.4 -> v1.21.2 | infra | - |
| 36 | strimzi-v1-templates | The Strimzi templates still on v1beta2 - KafkaUsers (schnappy-data) and the realtime KafkaTopics - on the v1 API | platform | - |
| 37 | strimzi-conversion | Every Strimzi resource and the CRDs' stored version to v1, before Strimzi 1.x (which serves v1 only) | infra + playbook | etcd |
| 38 | strimzi-1.2 | Strimzi 0.51.0 -> 1.2.0 (v1 API only), Argo's automated sync back (infra upgrade/38-strimzi-1.2) | infra | kafka |
| 39 | kafka-4.3-test | Kafka 4.2.0 -> 4.3.1 in the test environment, before production's (operator 2026-10-05) | infra + platform | - |
| 40 | kafka-4.3 | Kafka 4.2.0 -> 4.3.1 under Strimzi 1.2.0 in production, after the test environment (step 39) | infra + platform | kafka |
| 41 | eso-crds | External Secrets' CRDs under Argo, same 2.2.0 | infra | - |
| 42 | kubernetes-1.35 | Kubernetes 1.34.12 -> 1.35.9 (the next minor; after containerd 2) | infra + playbook | etcd |
| 43 | kubernetes-1.36 | Kubernetes 1.35.9 -> 1.36.5, the last platform step (Istio 1.31 and Cilium 1.20 support 1.36; nothing here sup... | infra + playbook | etcd |
| 44 | eso-2.11 | External Secrets 2.2.0 -> 2.11.0, CRDs with it through Argo (step 41) | infra | - |
| 45 | alertmanager-blackbox-ksm | Alertmanager 0.31.1 -> 0.34.1, blackbox exporter 0.27.0 -> 0.28.0 (its config reloader to the operator's v0.94... | platform | - |
| 46 | postgres-18-test | PostgreSQL 17 -> 18.6 in the test environment, before production's (operator 2026-10-05) | infra + platform + playbook | postgres |
| 47 | postgres-18 | PostgreSQL 17 -> 18.6, CNPG's offline in-place major upgrade (operator 2026-10-01, option A) | infra + platform + playbook | postgres |
| 48 | valkey-9.1-test | Valkey 8.1 -> 9.1.2, pinned, in the test environment (infra) and the chart default PR environments use (platfo... | infra + platform | - |
| 49 | valkey-9.1 | Valkey 8.1 -> 9.1.2, pinned (was the floating 8.1-alpine), in production after the test environment and the ch... | infra | - |
| 50 | grafana-13 | Grafana 12.4.12 -> 13.2.3, its preinstalled plugins not auto-updated (platform, then infra upgrade/50-grafana-13) | platform + infra | grafana |
| 51 | mimir-3.0 | Mimir 2.17.11 -> 3.0.8, one minor at a time (infra upgrade/51-mimir-3.0) | infra | gateway |
| 52 | mimir-3.1 | Mimir 3.0.8 -> 3.1.6, one minor at a time (infra upgrade/52-mimir-3.1) | infra | - |
| 53 | mimir-3.2 | Mimir 3.1.6 -> 3.2.1, one minor at a time (infra upgrade/53-mimir-3.2) | infra | - |
| 54 | tempo-3 | Tempo 2.7.2 -> 3.1.0 in monolithic mode (no Kafka) | platform + infra | gateway |
| 55 | fluent-bit-5 | Fluent Bit 4.2.8 -> 5.1.3 (infra upgrade/55-fluent-bit-5) | infra | - |
| 56 | centrifugo-6.9 | Centrifugo v6.7.1 -> v6.9.7 (infra values and platform's default, both upgrade/56-centrifugo-6.9) | infra + platform | - |
| 57 | sonarqube-26.9 | SonarQube Community 26.3.0 -> 26.9.0 (infra values and platform's default, both upgrade/57-sonarqube-26.9) | infra + platform | postgres |
| 58 | clickhouse-compat-24.8 | ClickHouse: compatibility 24.8 in the default profile (platform upgrade/58-clickhouse-compat-24.8), before the... | platform | - |
| 59 | clickhouse-25.8 | ClickHouse 24.8 -> 25.8.33.6, pinned (was the floating 24.8-alpine) | infra + platform | clickhouse |
| 60 | clickhouse-compat-25.8 | ClickHouse: compatibility 24.8 -> 25.8 (platform upgrade/60-clickhouse-compat-25.8), before the 26.8 image | platform | - |
| 61 | clickhouse-26.8 | ClickHouse 25.8.33.6 -> 26.8.15.10 (infra values and platform's default, both upgrade/61-clickhouse-26.8) | infra + platform | clickhouse |

## Review 2026-10-04 - findings, decisions, fix list

Four independent read-only reviews (production playbooks; infra/platform step branches; the test harness; the plan and
its claims) of everything since a90384a. Verdict: not ready for production. Operator decisions the same day: kagent's
pods restart with the mesh at each Istio step (the skew rule); a scripted, Vagrant-rehearsed backup + restore of every
store is a hard gate before its one-way step; the steps are reordered to stay inside every support matrix, test env
before production; defect 22 (Gluster cold boot) is fixed in production. Checked since: production's Scylla backup
works (Scylla Manager task schnappy-production-daily-backup, 158 runs, last 2026-10-04 03:00 DONE) - defect 20 was
wrong about Scylla; Kafka has none.

Read-only pre-checks on ten and the Pis, 2026-10-04 (results feed the fixes):
- containerd: ten's config.toml is containerd 1.7's default plus SystemdCgroup=true, nothing else; root
  /var/lib/containerd on the NVMe root. The Docker apt source is exactly what upgrade-containerd.yml writes.
- kubelet: config.yaml has shutdownGracePeriod 180s / 30s, the kubelet-config ConfigMap 0s / 0s - each kubeadm
  upgrade would reset them (R5 confirmed). kubeadm-config keeps terminated-pod-gc-threshold 100.
- local-path: upstream's config, /opt/local-path-provisioner on the NVMe root (plan 071's /mnt/storage is wrong).
- Helm on ten: argocd chart 9.5.4 (v3.3.8), cilium 1.19.1, external-secrets 2.2.0; root's cilium repo index (April)
  has neither 1.19.8 nor 1.20.2 (R16 confirmed).
- Argo: all 31 apps Synced + Healthy.
- CNPG: production on timeline 3 (00000003.history in the archive) - PostgreSQL 18 restarting at timeline 1 on the
  same path is R1 confirmed. Test cluster on timeline 1.
- ScyllaCluster version/agentVersion and Kafka spec.kafka.version are owned by argocd-controller: the inherited
  managedFieldsManagers ignore rules do not hide those bumps.
- kagent's pods (its Postgres too) carry istio-proxy: they restart with the mesh (operator's decision).
- apt-cacher-ng:7b46aea from git.pmon.dev: anonymous pull refused (401) - step 01 needs imagePullSecrets.
- Pis: every Gluster mount's source is <own address>:/<volume> - setup-gluster's remount condition holds; versitygw
  1.6.0 on both.

Fix list (status: open unless marked):

Production / data
- R1 Step 42: PostgreSQL 18 archives to the 17 path (pg_upgrade resets the timeline to 1; ten is past 1): a new
  serverName in the same change; read ten's timelineID and archive history first; pin the image by digest. DONE on
  the step branches: infra upgrade/42 backupServerName schnappy-production-postgres-pg18 (only production backs up;
  ten on timeline 3, read 2026-10-04), platform upgrade/42 the image @sha256:899d3ed5 (what the tag pointed at
  2026-10-04); the step's restore-undo line recovers PostgreSQL 17's backup with ten's image (@sha256:b1885e2c).
- R2 Re-runs downgrade: setup-kubeadm (Debian containerd over containerd.io, ESO 2.2.0, k8s pins) and setup-argocd
  (chart default) - fail-closed guards against a downgrade, then the new defaults, before any production step.
  DONE 3ac3eb9 (guards; the new defaults move with each production step).
- R3 Backups gate (Wave 0 as code): every store a one-way step changes - Postgres (pg_dumpall + CNPG base backup),
  Kafka, ScyllaDB (prove a restore of the existing backup), Grafana, ClickHouse, Mimir/Tempo (in-cluster versitygw
  PV), SonarQube's Postgres; each restore rehearsed in Vagrant.
  Built (deploy/ansible/playbooks/upgrade-backup.yml, task deploy:upgrade:backup STORE=, one store per run, right
  before its one-way step): into the Pi store (bucket upgrade-backups, keys <store>/<UTC time>/<file>, a sha256
  beside each, every object read back and compared), a copy on the node under /var/backups/upgrade:
  postgres - pg_dumpall of every CNPG primary and of SonarQube's Postgres (production only), and a CNPG on-demand
  base backup of each cluster (online);
  clickhouse - every MergeTree table frozen (ALTER TABLE ... FREEZE: hard links, online, consistent per part), the
  snapshot, metadata/ and each database's store/<uuid> directory tarred (metadata/<db> is a symlink by the
  in-container path), the snapshot removed;
  grafana - SQLite's online backup API on the node (Grafana running);
  kafka - the broker volume tarred with the broker stopped (operator paused, pod deleted): an outage of Kafka;
  scylla - a Scylla Manager backup task now, waited for (online);
  gateway - the in-cluster object store's, Mimir's and Tempo's volumes tarred with their user.* extended attributes
  (versitygw's posix backend keeps every object's ETag and every bucket's ACL there), online.
  Rehearsal (task test:upgrade:wave0, tests/ansible/upgrade/wave0-rehearsal.yml, Vagrant only), each restore reading
  the backup back from the Pi store: postgres into a side CNPG cluster (data-check's rows, count and md5); clickhouse
  into a new table built from the backup's own schema (survival-check's rows); grafana's copy (integrity, the canary
  dashboard, every recorded UID); kafka in place (a message added after the backup is gone, exactly the seeded ones
  back); scylla in place (truncated, sctool restore, the seeded rows); gateway in place (pods held Pending on the
  cordoned node, volumes replaced: ETags and ACLs back, the seeded trace back and one pushed after the backup gone,
  Mimir's `up` at the seed time).
  Status: all six rehearsed green on Vagrant 2026-10-04 (gateway: 3 buckets, 80 objects with their ETags, the seeded
  trace back and the later one gone, 51 `up` series). The rehearsals found the backup's defects - ClickHouse's
  metadata links, the gateway's extended attributes (a restore without them proven to fail the check) - fixed.
  Since the full review (2026-10-05): each step file names its stores (wave0 lines); production's backup phase
  (deploy:upgrade:backup STEP= STORE=) takes only those, before the step's merge, and the full run takes and rehearses
  them at the step itself, at the versions the step starts from. Files go up in parts (4 GiB; 4 MiB in Vagrant), each
  read back, with a list of the parts and the whole file's sha256, and come back through one task file that checks
  both (tasks/upgrade-backup-download.yml). The node must have room for the copy first; older local copies of the
  store go after the upload. A seventh store, etcd: a snapshot by the static pod's own etcdctl, before each Kubernetes
  step (production's hourly etcd copies keep 7 days), its rehearsal a restore into a scratch data directory. The test
  environment's ScyllaDB is skipped by name (no backup task, its agent no store credentials).
- R4 upgrade-containerd rebuilds config from defaults: read ten's live config.toml; migrate it (containerd config
  migrate) and fail on unknown settings; a guard that requires the new config + CRI + version; a rescue to the kept
  config. DONE fed85ea (Vagrant: pre-check, swap with 16 containers kept, re-run, rescue). Corrected 2026-10-05: no
  `containerd config migrate` runs - the playbook fails unless ten's live config is containerd 1.7's default plus only
  SystemdCgroup and the registry config_path, then writes containerd 2's default with those two (checked with
  `config dump` before it replaces the file).
- R5 kubeadm upgrade resets the kubelet's graceful shutdown (config.yaml rewritten from the kubelet-config ConfigMap):
  the settings into the ConfigMap, re-asserted after each upgrade. DONE 3eb9a2d (the ConfigMap step for production
  comes with R14's restructure).
- R6 Tempo 3: backend_scheduler.local_work_path defaults to /var/tempo on a read-only root - no compaction or
  retention; set it under /data; prove retention deletes in Vagrant. DONE on platform upgrade/48:
  backend_scheduler.local_work_path /data/backend-scheduler (its default /var/tempo, from tempo 3.1.0 -help).
- R7 Step 27: ESO CRDs under Argo prune - a revert deletes every ExternalSecret and its Secrets: CRD annotations
  Prune=false,Delete=false in the same change. DONE on infra upgrade/27 (crds.annotations: 23 of 23 CRDs at 2.2.0,
  25 of 25 at 2.11.0, rendered with the values file).
- R8 setup-gluster: a gluster CLI error reads as "no volume" and copies over the live forgejo-repos brick; recursive
  chown of all Forgejo data every run; error swallowing (cp || true, failed_when false); "Number of entries: -" counted
  as 0; the fresh-install path not resumable. Found while fixing: every run set each brick root to root:root behind
  Gluster's back (the volume roots then root's until a chown through the mount - since 771dc71 none ran for the repos);
  the old-volume cleanup matched the live git-mirror mount and deleted its fstab line, put back by a later play
  (production pi1 matches). DONE (Vagrant: remount after the cold boot, a re-run changed=0, a marked volume resumed;
  the count and heal logic against a stub gluster).
- R9 Defect 22 (Gluster cold boot): mounts that retry until bricks are up, services after them; Vagrant cold boot
  proof, then the Pis. Cause (Vagrant journal + client log): systemd mounted each volume at 3 s, before glusterd
  (ready 5.4 s) and any brick - "first lookup on root failed", no retry, Forgejo/versitygw "Dependency failed".
  Fix: gluster-volumes-ready.service waits until every fstab volume mounts (a trial mount every 5 s), the mount units
  are ordered after it (x-systemd.after), the services after their mounts (RequiresMountsFor); fstab entries of
  mounted volumes are rewritten without a remount. DONE in Vagrant (all three VMs halted and started together: pi2
  waited one retry, all 10 mounts up, Forgejo and versitygw 200 on both; the apply run kept all 10 FUSE clients).
  Production: with the operator's OK (setup-gluster on the Pis).
- R10 Defect 18: ClickHouse default user from ::/0 - fix; the metrics check reads as schnappy. Production read-only
  2026-10-04: users.d/default-user.xml present, a bare clickhouse-client logs in as default; in a day every query
  came from schnappy (609,784). The metrics check reads as schnappy - DONE. The chart: CLICKHOUSE_USER=schnappy +
  CLICKHOUSE_SKIP_USER_SETUP=1 (the image's entrypoint then writes no default-user.xml; clickhouse-client honours
  CLICKHOUSE_USER, so the runbooks' bare client works as schnappy) - DONE in the 25.8 step's platform branch, where
  ClickHouse restarts anyway (fbe7052); its clickhouse-users line makes survival-check want exactly schnappy from then.
  Moved 2026-10-05 to step 58's branch (24.8's entrypoint honours CLICKHOUSE_SKIP_USER_SETUP): merged before the
  25.8 image it would have been an unproven in-between state; 58 now restarts ClickHouse.

Rollout behaviour
- R25 Root app-of-apps on a cold start (Vagrant 2026-10-04, the Argo stage after a base-ready restore): a first-wave
  operator (cnpg) Degraded while starting failed the wave's health wait; Argo CD's default 5 retries ran out and auto-sync
  will not retry that revision - the later waves were never created (14 of the copy's apps). A fresh install - a DR
  rebuild of ten - hits the same. Fix: root.yaml syncPolicy.retry with a capped backoff (infra, its own early step).
  DONE on infra upgrade/00-argocd-root-retry (with R11's sync waves), step 00.
- R11 Root sync waits on child health wave by wave from step 12: every production app Healthy before 12 and before
  20-25; the infra sync waves committed (scylla manager after operator, ...) instead of the Vagrant-only overrides.
  DONE: the waves in infra (step 00, with R25; the mirror skips a wave git has); every app Healthy before a step:
  task deploy:upgrade:check, before and after each production step.
- R12 restart-mesh-workloads: `|| true` passes a failed read; restart the data tier first, then apps; kagent included
  (operator); steps 20-25 marked stateful with their outages. DONE e4c87da (the stateful marks with R18).
- R13 Step 24: Istio 1.30 images from registry.istio.io (scream tests 10-13, 11-17, 12-08/09): global.hub docker.io.
  DONE on infra upgrade/24 (istiod and cni values; docker.io/istio has 1.30.5; steps 24/25 expect docker.io images).
- R14 Step order inside every support matrix (operator); test env before production for Postgres, Kafka, ScyllaDB
  (versions as values per environment).
  DONE 2026-10-05: the order applied (renumbered, see the table under Support matrices); the test environment first -
  each of ScyllaDB 2025.1 and 2026.1, Kafka 4.3, PostgreSQL 18 and Valkey 9.1 split into a test step and the
  production step right after it (61 steps). Kafka's version (strimzi.kafkaVersion) and the cluster's image
  (cnpg.imageName) became chart values, each environment moved by its own values; rendered as Argo does, every test
  step changes only the test environment's manifests and every production step only production's, and the final
  renders equal the ones before the split. The Vagrant copy has no test environment: there the test steps change
  nothing (postgres-analyze -e pg_namespaces=schnappy-test finds no cluster and says so); in production each is shown
  and watched before its production step. The old branches: upgrade-old2/*.
- R15 Step 05: the Pis' versitygw upgrade never restarts the service; restart on version change, one Pi at a time;
  assert the running version. DONE: a restart wherever the running process is not the installed binary (a package
  upgrade leaves it on "(deleted)"; a run failing between install and restart is caught by the next), one Pi at a
  time, each healthy before the next; the run ends only with every Pi serving the installed binary at vgw_version; a
  lower vgw_version than installed is refused. Vagrant: 1.6.0 re-run no change; 1.8.0 - both "(deleted)" after the
  install, restarted pi1 then pi2, both 1.8.0; re-run no change; 1.6.0 refused. Step 05's earlier green left the Pis
  running 1.6.0 (nothing checked the process).
- R16 Cilium on ten: helm repo index never refreshed (steps 13/17 would fail); compare rendered cilium-config with the
  live, hand-patched one; upgradeCompatibility for 1.19->1.20. DONE: the repo refreshed (force_update); one
  cilium_values for install and check; before an upgrade the running chart is rendered from them on the node's Helm and
  must equal the live cilium-config key for key, or the run refuses (ten read-only 2026-10-04: Helm 3.20 renders 154
  keys, all equal to live; Vagrant: a key added by hand refused, a clean run passed without restarting Cilium);
  upgradeCompatibility "1.19" - no change at 1.19, at 1.20.2 it keeps envoy-xds-mode as 1.19 had it, the only change
  1.20 makes to ten's config besides its new features' keys at their defaults.
- R17 Grafana: RollingUpdate on one SQLite volume - Grafana 12 and 13 at once during the one-way migration: Recreate.
  DONE on a new platform upgrade/44 (rendered: strategy Recreate).
- R18 Step files' playbook lines are Vagrant command lines: a production command per step; task deploy:upgrade:*
  wrappers; read-only production checks after each step; per-step abort/revert and outage notes. Tasks: 
  deploy:upgrade:check (read-only: ten's and the Pis' inventory against the step's expected one, the k6 job's
  transient images allowed; Argo apps/pods judged as in Vagrant - ten 2026-10-04: matches the baseline, green),
  deploy:upgrade:preview (read-only: the step's playbooks in check mode with diffs - step 05 on ten's Pis: rclone
  would be installed, the retired mc removed, versitygw 1.6.0 -> 1.8.0, unit and env unchanged; nothing changed,
  checked after), deploy:upgrade:playbooks and deploy:upgrade:merge (PRODUCTION, behind a prompt: the step's playbook
  lines with ten's inventory and secrets, the argument fence kept; a step branch fast-forwarded onto main only when the
  repo's previous step branch is in main). setup-argocd keeps a working Forgejo token and makes a new one before
  deleting the old (it revoked Argo CD's access in between); "works" = it reads the root app's repository (its
  read:repository scope gets 403 from /api/v1/user, so the first version replaced it on every run) - kept and
  replaced both proven on Vagrant 2026-10-04, Argo CD settled after. Abort/outage notes: DONE 2026-10-05 - every
  step file has an "outage:" line (what stops, for how long) and an "abort:" line (the way back: a revert, a
  playbook with the old version, or for a one-way step the Wave 0 restore / the etcd backup and a rebuild); each way
  back says whether it was rehearsed in Vagrant (the Wave 0 restores and PostgreSQL 17's restore-undo were).
  Corrected 2026-10-05 (full review): the restores were rehearsed, the ways back on them were not - each abort line
  now says which; four named a playbook run its own no-downgrade check refuses (now: by hand, not rehearsed).
- R19 (apt-cacher-ng's forgejo-registry pull secret on platform upgrade/01; local-path's node paths checked before
  and after the manifest - ten's are upstream's default; ScyllaCluster/Kafka and the Docker apt source: the
  pre-checks showed nothing to change; argocd's image pinned per chart version - DONE)
  apt-cacher-ng image pull on ten (no imagePullSecrets); local-path-config on ten (path); ScyllaCluster/Kafka
  managedFieldsManagers ignore rules; Docker apt source on ten; argocd image-tag override across 12/29/30; strimzi
  guard fail-open; restart-mesh and settle checks on empty data; apt keyring emptied by a failed curl. DONE: strimzi
  guard + its RBAC always removed, settle check, apt keyring (b5b9f40), restart-mesh (e4c87da); the local-path guard
  proven on Vagrant 2026-10-04 (passes on upstream's paths; with a hand-set path it stops before the apply, nothing
  applied); the rest open.

Test harness
- R20 argo-settled: a failed sync passes; restarts ignored; a failed pod query counts as all ready; one green poll
  ends the wait; comparedTo not checked. DONE: tests/ansible/upgrade/files/argo-settled.py - per app Synced, Healthy,
  nothing running, the last sync not Failed/Error, comparedTo = spec, on the pushed commit; per pod ready (a
  node-shutdown leftover excepted: ten has 13); a failed kubectl call is not green; green held for stable_polls polls
  with no container restarting in between (4 = 30 s; the runner's first wait, before the playbooks, 1), and no
  container restarted in the last 5 min (CrashLoopBackOff's longest back-off: a crash loop never settles, one restart
  costs at most 5 min - fixture: restarted 60 s ago not ready, 400 s ago ready). Proven: ten's
  state read-only GREEN (31 apps); one-fault fixtures each NOT GREEN on their fault; a simulated loop - a restart
  resets the count, a crash loop and a pod restarting every 30 s while "ready" never settle, a failed poll resets;
  Vagrant without Argo: every poll failed, NOT SETTLED, the task failed.
- R21 Data survival not checked for one-way steps: seed and verify ClickHouse, Grafana, Tempo, Mimir; the
  compatibility pin via system.merge_tree_settings; versions per step. DONE: tests/ansible/upgrade/survival-check.yml,
  seeded at the build, verified after every step - a ClickHouse MergeTree table (count, md5) and its compatibility
  setting against the step files' clickhouse-compat lines (24.8 from the 25.8 step, 25.8 from the 26.8 one), the
  MergeTree format settings that pin holds (system.merge_tree_settings, since 2026-10-06 - before, only the session's
  setting was read), every
  Grafana dashboard UID of the seed and a canary dashboard's content, a Tempo trace by ID, Mimir's `up` series at the
  seed's time. Vagrant 2026-10-04: seed and verify green (1000 rows, compat empty, 7 dashboards, the trace, 51 series);
  a wrong pin and a missing dashboard each failed.
- R22 data-check never writes after a step (replication, Kafka produce, Scylla write); metrics-check misses vanished
  targets; barman check missing at 05; restore-check never replays WAL nor restores the Postgres 17 backup. Barman
  check at 05 - DONE (CNPG archives to the Pi store, 192.168.11.5:9000, whose gateways step 05 restarts). Writes -
  DONE, live on Vagrant: every verify commits a heartbeat row that must reach every replica (and the primary streams
  to instances-1), switches its WAL segment out and wants it archived with no new archiver failure, produces and
  reads a message through Kafka's bootstrap Service, writes and reads a row through ScyllaDB's client Service; the
  Scylla wait wants every pod's operator containers at the running operator's image. Scrape pools - DONE: recorded at
  the build, no pool gone or smaller after a step (a shrunk record named both faults). Restore - the marker after the
  base backup must come back (WAL replayed), run after the CNPG, store and Postgres 18 steps (restore-check line); the
  Postgres 17 undo with R1's serverName (-e restore_server/restore_image).
- R23 Smaller: step 01 invisible to the inventory diff; a missing step branch unnoticed; step-file arguments
  unvalidated; empty step list green; no pipefail in task; CoreDNS rewrite unchecked; vms-ready must bring Gluster
  mounts up after the harness's own reboots (until R9). DONE: the diff filters only the app images CD moves (step 01's
  expected vs apt-cacher-ng 1.0 now DIFFERS); step files declare their branches (branch infra|platform) and --refs
  refuses a declared branch missing or an existing one undeclared; step arguments naming an inventory, a limit, a
  host address or an extra-vars file are refused, the guard play (tests/ansible/vagrant-only-play.yml) runs first in
  the same call (production inventory: all 4 hosts refused, the next playbook reached none), stdin closed; an empty
  step list fails; pipefail in the step vars and inventory pipes (an unknown step stopped at its refs); the CoreDNS
  rewrite refuses a Corefile without its anchor and a DNS probe proves Vagrant answers; vms-ready checks every Gluster
  mount and Forgejo/versitygw (never mounts them); data-check: a Pending pod is not ready; the mirror refuses a
  Forgejo outside 192.168.56.0/24.

Plan and claims
- R24 Every false or stale claim the reviews listed, corrected in this file, the step files and playbook comments.
- R26 The Vagrant copy installs the proposed fix of defect 10 (an ExternalSecret naming `monitor` for CNPG's -app
  Secret); ten's Secret names `app` - the CNPG steps never ran against production's Secret state: reproduce ten's.
  After the PostgreSQL 18 step, vacuumdb --analyze-in-stages (CNPG's major-upgrade notes).
- R27 Rebuild at the target versions is never tested; the playbook defaults the rollout moves are incomplete
  (istio_version, cert_manager_version, external_secrets_chart_version, metrics_server_chart_version, vgw_version,
  gateway_api_version - v1.2.1 fails against v1.5's safe-upgrades policy): the default edits as one reviewed change, then
  a fresh build at the targets and a green task dr:drill before the production rollout.
  DONE 2026-10-05: the defaults at the targets on the local ops branch upgrade/defaults-at-targets (merged at the
  rollout's end); setup-kubeadm.yml installs containerd.io when containerd_io_version is set. task
  test:upgrade:build-targets - a fresh build with those defaults, Argo at the last step's branches - green from
  scratch: Argo settled (23 apps), the data, survival and metrics checks, and the inventory equal to the one the 61
  steps lead to (the one allowed difference: External Secrets' stale Helm record, which only an upgraded ten keeps).
  Its first runs found what the full run would have hit or a rebuild after the rollout would break on: the Scylla
  operator's cleanup Job held Running by an Istio proxy (istiod neverInjectSelector, step 21); the Manager's backend
  agent unpinned (step 21); the containerd step's inventory line without the hold; kubernetes-cni and cri-tools never
  moved by upgrade-kubeadm.yml (now with each minor, steps 42/43); setup-argocd waiting for External Secrets' CRDs
  before the root that installs them (the wait gone, the root bootstraps with retries); isolate-cluster needing
  External Secrets' account before Argo makes it. task test:dr at the targets (platform at the last step's branch):
  ALL DR TESTS PASSED, 259 tasks, every k6 check (the drill's skip list had lost masi - fixed).
  The playbook variables the steps set (their last value, from the step files 2026-10-05): argocd_version 10.9.6,
  cilium_version 1.20.2, containerd_upgrade_to 2.3.6 (setup-kubeadm then installs containerd.io 2.3.6, not Debian's),
  gateway_api_version v1.5.1, istio_version 1.31.1, local_path_provisioner_version v0.0.37, vgw_version 1.8.0,
  kubelet_grace_in_kubelet_config_map true; and the ones only Argo moves in production but setup-kubeadm installs
  on a build without it: cert_manager_version, external_secrets_chart_version, metrics_server_chart_version,
  k8s_package_version (1.36.5).
- R28 Scope and pins: the Pis' own services (Keycloak, Forgejo, Consul, Nexus, Caddy, Vault, Patroni, PgBouncer,
  HAProxy, Gluster) are not in this plan - stated; metrics-server and porkbun-webhook float at targetRevision "*" and can
  move mid-rollout - pinned to what ten runs.
- R29 Change freeze for the rollout: Woodpecker CD's infra commits, Hyperfoil at 03:00, the 02:00-04:00 backup
  window, Scylla repair Sunday 04:00 - each step's time chosen around them; the Istio steps restart kagent's Postgres,
  the test environment and PR environments too (a read-only list before the first). SonarQube and its Postgres run no
  proxy (read on ten 2026-10-05: only SonarQube's setup Job has one) - the Istio steps do not restart them.
  Read on ten 2026-10-04 23:55 - the workloads with an istio-proxy, 30 (listed again right before the first Istio
  step): kagent - kagent-postgresql only (kagent itself runs none); schnappy-infra - fluentbit (DaemonSet),
  alertmanager, grafana, the gateway (schnappy-infra-gateway-istio), s3gw, reports, runbooks, clickhouse;
  schnappy-production - Postgres (CNPG), admin, centrifugo, chat, chess, game-scp, monitor, site, valkey, Kafka;
  schnappy-test - Postgres, admin, chat, chess, game-scp, masi, masi-browser, monitor, site, valkey, Kafka. No PR
  environment then; SonarQube, ScyllaDB, Mimir, Tempo, Velero and the operators carry no sidecar.
- R30 Gateway API v1.5.1 is one-way (its safe-upgrades ValidatingAdmissionPolicy refuses v1.0-v1.4 CRDs): flagged
  in the step and the stateful table.

Second review (2026-10-05, the new work: Wave 0, the checks, the production commands) - every finding fixed:
- Production: Kafka's pause/stop/copy/unpause is one detached script on the node (async) whose EXIT trap lifts the
  pause - an interrupted run or a lost connection left both clusters paused with their brokers deleted. Proven live
  (Vagrant 2026-10-05): the StrimziPodSet controller recreates a deleted broker even while its Kafka is paused, so
  every earlier Kafka backup copied a running broker; now the node is cordoned for the copy (the recreated pod waits
  Pending; ten has one node - no new pod is scheduled anywhere for the copy, seconds at 103M per broker, shown to the
  operator at that step), each broker checked not running before and after its copy, the trap uncordons first. ClickHouse's snapshot is removed in an always (a failed tar left its hard links
  on the root disk). CNPG base backups only for clusters with an object store (the test cluster's has none - every
  production run would have failed). The gateway tar accepts exit 1 only for files changing while read (the WAL, the
  indexes) and is checked against the objects listed before and after it (files/objectstore-manifest.py: ETag and
  md5 per object, ACL per bucket; the list stored beside it); unit test tests/ansible/unit/objectstore-manifest.
  SonarQube's dump is required where it runs. The store's credentials in a 0600 curl config, never on a command line
  or in the environment. postgres-analyze covers every CNPG cluster. local-path: the manifest's own node paths are
  checked before that same downloaded file is applied (after the apply the provisioner already had the new paths).
- Checks that did not bite: Mimir - a stored block covering the seed time must be in the store-gateway's list from
  4 h after the seed (before 12 h the ingester answers the query alone); the Kafka rehearsal proves its extra
  message arrived (end offset 1001) and the restored log ends at 1000; the gateway restore is compared with the
  backup's object list before the pods start; Scylla restores the snapshot the Wave 0 run recorded (snapshots.txt),
  not the newest; data-check's Kafka read is exact by the end offset; scrape targets must have stayed up for 3
  minutes; an empty step branch fails the refs check; a node-shutdown leftover counts only when its workload runs a
  ready pod again; restore-check recovers its base backup by barman ID (recoveryTarget.backupID), and -e
  restore_backup=wave0 recovers the Wave 0 base backup; the Postgres rehearsal replays every dump, allows only the
  roles and databases the side cluster had, and compares every table's row count with the dump.
- Found by that last rehearsal (Vagrant 2026-10-05): a CNPG base backup taken from the standby (CNPG's default
  target) completes before the primary archives the WAL its end needs - recovered a minute later it failed ("WAL
  ends before end of online backup"), restorable only after archive_timeout. upgrade-backup.yml now switches WAL on
  the primary and waits until each base backup's end WAL is archived; production's Wave 0 base backup is
  restorable the moment the playbook ends.

Full review (2026-10-05, three read-only reviewers over the whole work, during the stopped full run 7) - the
verdict "not ready"; every item below to be fixed and proven before full run 7:
- F1 (critical) The Argo CD steps pass the Vagrant copy's own arguments (Forgejo at 192.168.56.20:3000, plain http,
  no certificate check, no Keycloak, no ingress) to production through deploy:upgrade:playbooks - ten's repo
  credentials would point at the Vagrant Forgejo. They belong in inventory/vagrant.yml; --production allows only
  each playbook's step variables.
- F2 (critical) Nothing in production refuses step N before N-1 (Istio 1.30 before Gateway API v1.5, Strimzi 1.2
  before the conversion, Kubernetes 1.36 before containerd 2): a production step ledger every deploy:upgrade:* task
  checks and writes; upgrade-kubeadm.yml refuses a runtime below the target minor's floor.
- F3 deploy:upgrade:check: the inventory has no namespace, so the test environment's and SonarQube's own changes
  read as differences (steps 16, 19, 39, 46, 48, 57; the test schema Job's scylla:6.2); its settle runs --once
  against whatever ~/.kube/config points at and without the pushed SHAs (green on the old commit). Production's
  scope as Vagrant's (the test environment and SonarQube out, listed apart), the settle on ten with the merged SHAs
  and stable polls.
- F4 Step 50: Grafana's Recreate (platform) and its 13.2.3 image (infra) merge separately, in any order - infra
  first runs Grafana 12 and 13 on one SQLite file. The step file's branch lines are the merge order and the merge
  refuses another; Recreate first.
- F5 Defaults: kept until the rollout's end, a rebuild between steps installs the old versions under a newer etcd -
  each step moves its playbook defaults (machine-readable "default" lines; the defaults branch is generated from
  them); an etcd snapshot store in Wave 0 before each kubeadm step.
- F6 Step 47: recovery reads the PostgreSQL 17 archive by name (recoveryServerName follows the cluster name) - set
  it with backupServerName; the DR drill hardcodes postgresql:17 and never recovered an 18 backup - driven by the
  chart's values.
- F7 Wave 0 of the test environment's ScyllaDB cannot work (no agent credentials there): the test environment's
  ScyllaDB has no backup - said so in the test steps' abort lines, Wave 0 skips it by name.
- F8 Wave 0 never runs inside the full run - the backups are proven only at the baseline versions: wave0 lines in
  the step files before each one-way step run the backup and its rehearsal there. The abort lines' "rehearsed in
  Vagrant" claimed a rollback to the previous version that never ran - restated (operator decision on real rollback
  rehearsals pending).
- F9 Wave 0 uploads are single PUTs of tars up to ~50 GB (ClickHouse 53G, the object store 45G on ten): split into
  parts, each with its sha256; a free-space check before tarring; old local copies pruned.
- F10 The object-store check passed on zero objects and on ETags under another name - fixed (unit test).
- F11 argo-settled: no floor on the app set (a dropped child app goes green), a crash loop slower than 5 minutes
  settles - the app names recorded at the build and required; a pod restarting in consecutive steps fails.
- F12 Mimir's seed-time query is answered by the ingesters for 12 h - the Vagrant copy's query_store_after and
  query_ingesters_within lowered so it is the store-gateway's.
- F13 CRDs: only gateway-api and the Prometheus operator's are in the inventory - every CRD group's count and
  version, the External Secrets CRDs' Prune/Delete annotations checked.
- F14 Nothing ties what the full run proved to what gets merged: the full run records each step's infra/platform
  SHAs and ops' commit (a dirty ops tree refuses), the merge refuses another SHA.
- F15 Floating tags (postgresql:17, ...) checked against ten only at the build: their digests checked before each
  step.
- F16 Smaller: Kafka's metadataVersion unread (step 40's claim and abort); build-targets smoke-tests main's Job;
  postgres-analyze with pg_namespaces matching nothing ends green (fail unless the inventory allows none);
  strimzi-v1-conversion's "|| true" and its always without set -e; versitygw.yml compares versions by substring;
  upgrade-kubeadm.yml installs the repo's newest kubernetes-cni/cri-tools (pinned per minor instead); the non-Argo
  scylla-manager install is not pinned; lines over 120 in scripts.
- F17 Claims: the plan's versions table (ScyllaDB 2026.3.2), old step numbers throughout, the wrong renumber table
  (from row 12; the five test steps missing), the stateful table, the Wave 0 description, R4's "config migrate",
  R29's SonarQube sidecar, the windows; steps 58/60 (ClickHouse does not restart there - the pin acts at 59/61),
  46 (the test cluster's dump is in Wave 0), 41 (the when: is on main already), 57 (SonarQube waits for /setup -
  a migrate playbook line), 21 (istiod rolls); R9's production Gluster fix in no step - step 00.
- F18 The operator's procedure per step - Wave 0, preview, merge in order, the settle on the pushed SHAs,
  playbooks, check, soak, stop criteria - written down and enforced by the tasks.
- F19 (third reviewer) The state between a two-repo step's merges was never proven, and three steps' orders were
  wrong: 47 platform first upgrades production to 18 by the chart default without the new archive name; 50 and 54
  infra first run Grafana 13 beside 12 on one SQLite file / Tempo 3 on the 2.x config; 59 infra first runs 25.8 with
  the image-made default user (found by the new check). Step 28 already runs two Grafanas (RollingUpdate).
- F20 Four abort lines (11 and 32 Cilium, 26 local-path, 07's policy removal) are refused by the playbooks' own
  no-downgrade guard (tasks/no-downgrade.yml): restated as one-way, or an explicit per-component override (refusing
  by default) with one downgrade rehearsed.
- F21 Step 21 is one-way for Scylla Manager's backend ScyllaDB (2026.1.3 -> 2026.2.5), no Wave 0 store covers it:
  marked one-way, its backend snapshotted first or Manager's state rebuilt by a written procedure.
- F22 Step 47's production undo has no procedure: restore-check recovers into a side cluster only. Going back means
  replacing the live Cluster (its PVCs deleted - local-path, reclaim Delete) by a recovery under the old server name,
  losing writes after the upgrade: written down and rehearsed in Vagrant against the production names.
- F23 ACME issuance through the porkbun webhook is never exercised (steps 23, 35): after each in production a
  throwaway staging Certificate through the porkbun solver, Ready, deleted.
- F24 The ClickHouse pin's rollback is unproven (getSetting reads a session setting). DONE 2026-10-06 with the real
  images in docker (task test:clickhouse-pin): 25.8 pinned to 24.8 and 26.8 pinned to 25.8 write and merge parts of
  the logs table, the older image reads every row back; unpinned, 24.8 does not start and 25.8 detaches half the
  parts. The pin reaches MergeTree (system.merge_tree_settings: substream marks off, 'basic' serialization info,
  single-stream strings, v2 object/dynamic) - the survival check now asserts those values at each pin. Not rehearsed:
  the revert through Argo CD on the copy.
- F25 Step 31 is ten's first setup-argocd run since 10-01: it installs the Application health check, after which
  the root waits for each wave Healthy (about 50 minutes of retries) - said in step 31, every app Healthy before it.
- F26 deploy:upgrade:check allowed no argo-out-of-sync app: red after step 37 by design.
- F27 The Vagrant runner's barman-check, restore-check and cert-renew lines have no production counterpart - after
  step 47 production needs a fresh base backup (its step file says so) that nothing takes.

Fixed so far (2026-10-05, uncommitted where not said):
- F1: the production runner allows only --tags and the step variables (`--lint` in CI: tests/ansible/unit/step-fence);
  the Vagrant Argo CD settings in inventory/vagrant.yml; production runs carry -e @vars/vault.yml.
- F10: the object-store check fails on zero objects, objects without an ETag, or under 90% unchanged (unit test).
- F2, F4, F14, F18, F26: scripts/upgrade-production.py and the deploy:upgrade:* tasks - the ledger on ten, the
  phases in order, the merge in the step file's order with the in-between state proven (F19's check), the full run's
  proof (own change per repo, the ops commit; a dirty ops tree refuses the run), the soak with no restart, the
  procedure written ("Production, step by step"); tests/ansible/unit/upgrade-ledger (seven mechanisms reverted, each
  red). The upgrade-kubeadm containerd floor (F2's second half) still open.
- F3: production's inventory leaves schnappy-test out and lists it apart (the baseline matches ten exactly: 98 lines,
  2026-10-05); browserless (test-only) out of the baseline; step 57 carries SonarQube's line; Argo judged on ten
  with ten's kubeconfig, on main's commits (green on ten 2026-10-05: 31 apps, every pod ready).
- F19: scripts/upgrade-merge-order.py renders every platform-chart Argo application (helm template from the refs)
  before, between and after the two merges and refuses unless the between state equals one of the others - run at the
  full run's start and by the production merge. Orders now: 47 infra then platform; 54 platform then infra; Grafana's
  Recreate moved to platform step 25 (no restart), so 28 and 50 run one Grafana and 50 is infra only; the ClickHouse
  users fix moved to step 58 (24.8's entrypoint honours CLICKHOUSE_SKIP_USER_SETUP, read on ten): ClickHouse restarts
  there, so its compatibility pin and one user start at 58. All 11 two-repo steps proven safe in their order.
- wave0 lines on the one-way steps (13, 42, 43 etcd; 17, 20 scylla; 38, 40 kafka; 46, 47, 57 postgres; 50 grafana;
  51, 54 gateway; 59, 61 clickhouse): production's backup phase, and the full run's (F8).
- F2: upgrade-kubeadm.yml refuses a minor on a runtime below its floor (tests/ansible/unit/runtime-supported).
- F5: per-step default lines (36 over 27 steps; scripts/upgrade-defaults.py), production's defaults phase commits each
  step's; the defaults branch is generated from them (equal to the hand-made one but for the Manager's values form);
  the etcd Wave 0 store before 13, 42, 43.
- F6: infra's step 47 sets recoveryServerName (a DR recovery reads 18's archive); the DR drill's Postgres takes the
  image production's Cluster renders to (scripts/production-cnpg-image.py) - its 18 run still to come (the final
  proofs, task test:dr TEST_PG_IMAGE=).
- F7: the test environment's ScyllaDB skipped by name (ten: its agent mounts no store credentials). Found with it:
  `sctool info | awk exit` died of SIGPIPE on ten's larger output - production's Scylla backup would have failed;
  fixed, and three test pipes with grep -q.
- F8: the step runner runs each step's wave0 stores (backup and rehearsal) before the step; the abort lines say what
  was rehearsed (the restore) and what not (the old version on it). Real rollback rehearsals: the operator's decision.
- F9: uploads in parts with read-back, the download task, the space check, the pruning (tests/ansible/unit/backup-parts).
- F11: argo-settled.py's app floor and two-steps restart rule (tests/ansible/unit/argo-settled).
- F12: Vagrant's Mimir querier windows (4 h / 1 h) through platform step 22's mimir.extraArgs.
- F13: every CRD in the inventory (none may go; new ones allowed), External Secrets' protection count
  (tests/ansible/unit/inventory-diff); every target chart keeps production's 124 CRDs (rendered).
- F15: floating-tag digests recorded by the preload and checked before each production phase.
- F16: Kafka's metadata version in the inventory, the targets build's smoke refs, postgres-analyze fails on no
  cluster, strimzi-v1-conversion's waits and cleanup, versitygw's whole-version compares, kubernetes-cni/cri-tools
  pinned per minor, the non-Argo Scylla Manager pinned (defaults branch), scripts within 120 columns.
- F17: the plan's step and stateful tables generated from the step files, the renumber table dropped, the versions
  table, R3, R4, R10, R29, the windows; steps 21 (istiod does NOT restart - rendered), 41, 45/57 (SonarQube's hook
  now starts its migration), 60 (no restart there); step 00 takes the Gluster fixes to the Pis.
- F20, F21, F25: abort and comment lines as they are (no-downgrade refusals, the Manager backend, step 31's first
  setup-argocd run since 10-01).
- F23: acme-check.yml after the cert-manager steps (production; objects validated by a server dry run on ten).
- F27: postgres-base-backup.yml after 24, 25, 47 in production (the Vagrant barman-check runs the same playbook).
Open, the operator's: F22 and an etcd restore - the rollback rehearsals in the full run.

## Full review 2026-10-06 - what it fixed, what is the operator's

Ten passes (code, security, architecture, steps 00-21, steps 22-61, Pi playbooks twice, harness speed, concurrency,
test quality) over everything of plans 100 and 101. Fixed, each with a test that fails when its mechanism is reverted
(ops 75e5451..; the commits name them):
- The procedure: the preview after the step's merges, read-only probes running in check mode, previewed by the full
  run at every step; merged steps tagged (a restack and the proof skip them); the whole proven tree frozen against
  the proof, not only deploy/; production's app tags must be the ones the full run ran; a done phase that changes
  production (ACME, base backup) asks first; the committed default lines recorded (CI lint through the rollout) and
  the defaults phase resumed after a cut-short run; a step's own-registry images checked before its merge; `settle`
  per step (57: 50 minutes); Argo CD 3.5's Helm 4.2.1 renders all 33 applications as 3.4's 3.19.4 did
  (argo-helm-diff.py, before the full run boots).
- The steps: ClickHouse's rollback pin rehearsed with the real images (F24 - test:clickhouse-pin) and asserted on the
  MergeTree format settings; Strimzi 0.51 -> 1.2 checked against its own notes; an etcd Wave 0 before 37; abort lines
  that hold (00, 27, 39, 40, 44, 59, 61) and outage lines that tell (18, 21, 22, 54 - Tempo 2 flushed first); the
  copy on production's runc; containerd's swap without the kubelet; the Gluster boot wait bounded; Grafana's
  datasources and Tempo's span metrics checked after every step.
- The Pis (plan 101): no service restarted on both Pis at once (Patroni reloaded or restarted paused one node at a
  time, Vault, Forgejo, Keycloak, HAProxy); restarts pending from a cut-short run done by the next; pauses resumed
  only by their own run; the Consul key read from every server; backups that survive Keycloak failing and a wrong
  clock; Forgejo taken forward after a cut-short upgrade; Vault's certificate checked by the unseal; secrets off
  command lines and the controller; app.ini and keepalived.conf root/owner only; the DR procedure's Postgres
  recovery.

The operator's - decisions this review does not make:
1. The candidate app images (monitor, admin, chat, chess: Keycloak keys warmed and kept through an outage) promoted
   to production before the rollout - every production phase refuses until production's tags are the full run's;
   their review PRs (fix/warm-up-review) pushed and merged first (a merge deploys to schnappy-test).
2. platform fix/runbooks-prometheus-distroless pushed (seven runbooks exec'd wget in Prometheus, which step 27's
   distroless image lacks; the events schema's TTL 24.8 refuses) - it changes production's runbooks ConfigMap, and
   the platform step branches are restacked and proven again.
3. Kafka's metadataVersion pinned in a step of its own (step 40's revert window does not exist without it).
4. The next full run's Pis at plan 101's targets (one full run) or at production's versions (another full run once
   plan 101's steps are in production).
5. Prune protection of the CRD-owning apps (Strimzi, CNPG, Prometheus, cert-manager - deleting a CRD deletes every
   resource of it: KafkaTopics with their topics, Clusters with their volumes) - per chart, or no resources finalizer.
6. A backup of Forgejo's repositories (none exists - the Gluster volume is replicated, not backed up).
7. Security (pre-existing): Consul and Patroni APIs without authentication on the LAN; Forgejo and Keycloak as the
   Postgres superuser; one store key for every backup consumer, unencrypted; Keycloak in dev mode on the LAN; UFW
   opening 8200 to all; the Vault root token in .env and on both Pis; production secrets in local Claude Code
   permission rules (remove and rotate); production's wildcard key in the Vagrant copy.
8. F22 and an etcd restore rehearsed in the full run (longer run).

## Support matrices and the new step order (R14; official pages read 2026-10-04)

Kubernetes ranges per version (sources: istio.io supported-releases, docs.cilium.io compatibility, containerd.io
releases, Argo CD tested-kubernetes-versions, cert-manager releases, cloudnative-pg supported_releases,
external-secrets stability-support, Scylla Operator releases + metadata.yaml, Strimzi downloads, Velero README):

| Component | Versions in the plan | Kubernetes |
|---|---|---|
| Istio | 1.25 / 1.26 / 1.27 / 1.28 / 1.29 / 1.30 / 1.31 | 1.29-1.32 / 1.29-1.33 / 1.29-1.33 / 1.30-1.34 / 1.31-1.35 / 1.32-1.36 / 1.32-1.36 |
| Cilium | 1.19 / 1.20 | 1.32-1.35 / 1.33-1.36 |
| containerd | 1.7.24 (below 1.34's floor 1.7.28; EOL 2026-09-30) / 2.3.6 | 2.3 listed for 1.36+ only; 1.35 accepts 1.7.28+, 2.1.5+, 2.2+; 1.36 needs 2.2+ |
| Argo CD | 3.3 / 3.4 / 3.5 | 1.32-1.35 / 1.32-1.35 / 1.33-1.36 |
| cert-manager | 1.20 / 1.21 | 1.32-1.35 / 1.33-1.36 |
| CNPG | 1.29 (EOL 2026-09-29) / 1.30 | 1.33-1.35 / 1.34-1.36 |
| External Secrets | 2.2 / 2.11 | 1.34-1.35 / 1.36 only |
| Scylla Operator | 1.20 / 1.21 / 1.22 | 1.32-1.35 / 1.33-1.36 / 1.33-1.36 |
| Strimzi | 0.51 / 1.2 | 1.30-1.35 / 1.30-1.36 |
| kube-state-metrics | 2.18 / 2.20 | pairs with 1.34 / 1.36 |
| kubectl images (alpine/k8s 1.34.0) | no step moves it | +-1 minor of the API server: out at 1.36 |

Pairings: ScyllaDB 6.2.3 is outside operator 1.20's and Manager 3.9's lists today; operator 1.22 lists ScyllaDB 2025.1,
2026.1-2026.3, but Manager 3.12 lists 2025.1, 2025.4, 2026.1, 2026.2 - not 2026.3. Istio pins Gateway API per
release: 1.25 v1.2.1, 1.26-1.27 v1.3.0, 1.28-1.29 v1.4.0, 1.30 v1.5.1 (install v1.5 before 1.30 - a hard minimum),
1.31 v1.6.0. Gateway API v1.5 refuses a downgrade (step 18 is one-way). Strimzi 0.51 -> 1.2 directly: checked
2026-10-06 against Strimzi's own upgrade documentation and changelog (0.51-1.2) - a multi-version upgrade is supported;
its required sequence holds (Kubernetes 1.30+, KRaft, the v1 conversion before the operator - step 37, then the
operator, then Kafka's version - step 40); 1.2.0 supports Kafka 4.2.0-4.3.1 (production's 4.2.0 is set in the CR);
the removals and renames do not touch production's render (node pools carry resources and storage, KafkaUsers use
`operations`, simple authorization and SCRAM - no OAuth, Keycloak or OPA - no rack, nothing names the Entity
Operator's renamed health ports, no HTTP Bridge).

The order then (old numbers below, to "Unavoidable windows") ran Argo CD 3.3, cert-manager 1.20, ESO 2.2, Strimzi
0.51 and Scylla Operator 1.20 on Kubernetes 1.36 (steps 26-37), Istio 1.25-1.28 on 1.35 (16-22). Proposed order (each
step's content unchanged):
A (at 1.34): 19, 20, 21, 22, 23 (Istio 1.29 before 1.35 - 1.28 ends at 1.34), 18, 24, 25, 04, 13, 14, 15, 36, 37,
38, 39, 40; B: 01, 02, 03, 05, 06, 07, 09, 10, 11, 12; C (move to 1.36-capable versions, still on 1.34): 17, 29, 30,
31, 32, 33, 34, 35, 27; D: 16, 26, 28 (right after 26: ESO 2.11 lists 1.36 only), 08 (ksm 2.20 pairs with 1.36);
E: 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, then 41. Every moved step is re-proven by the full run.
Unavoidable windows (current numbers): Istio 1.26-1.27 on 1.34 (steps 03-04, one minor at a time); containerd 2.3
under Kubernetes 1.34 and 1.35 (steps 14-42: 2.3 is listed for 1.36 only; the 1.7 -> 2.3 LTS hop is containerd's
supported path); External Secrets 2.2 on 1.36 between steps 43 and 44 (operator 2026-10-05: accepted); kube-state-metrics
2.18 on 1.35 (steps 42-45).
Mine to fix: the kubectl images to 1.35.x before 26; step 25's comment (Istio 1.31: 1.32-1.36, not 1.37) - DONE;
step 40 pins Scylla Manager and its agents to the target 3.12.1 (the chart's default is 3.12.0) - with the restructure.
Operator's decisions (2026-10-05): ScyllaDB 2026.1 LTS - step 41 (2026.3) dropped, its branch kept as
upgrade-old/41-scylladb-2026.3 only, the schema Job's cqlsh image pinned to 2026.1.14 with step 39 instead;
containerd in one hop; ESO's window accepted (no 2.8 step); Gateway API stops at v1.5.1.

Applied 2026-10-05 (scripts/upgrade-restack.py; the old branches kept as upgrade-old/*): every branch re-created in the
new order, each step's own commits cherry-picked without a conflict; platform's final tree identical to before,
infra's differs exactly by the dropped 2026.3 (back to 2026.1.14). Every step's refs and inventory checks pass in
the new order. The text of this plan written before 2026-10-05 uses the old numbers (01-55); the same day the five test-environment steps were split from their production ones and step 00 added - the step table under "Upgrade steps" is the current list.

## Stateful steps - for the operator's approval

Production runs one Kafka broker, one ScyllaDB node, one ClickHouse and two Postgres instances: a roll of the first three is an outage of that service for the restart. The one-way steps - each with a wave0 line takes its Wave 0 backup first, in production and in the full run, where the backup's restore is rehearsed at the step's versions - and 14 and 21, whose way back is by hand. The rows are the step files' outage and abort lines (the step files are the source):

| # | Step | Outage | Abort |
|---|---|---|---|
| 13 | kubernetes-1.34.12 (Wave 0: etcd) | the control-plane pods restart one at a time (the API server away for seconds; workloads keep running), the kubelet restarts | one-way - kubeadm does not downgrade; back only by a rebuild at the old version (DR-PROCEDURE.md's full rebuild: GitOps and each store's own backup), or the Wave 0 etcd snapshot restored into the node's etcd - for that no procedure is written and it is not rehearsed (only the snapshot's restore into a scratch data directory is, at this step in the full run). A failed apply is not rolled back: kubeadm returns a component only when that component's own restart fails, so the ones it upgraded stay upgraded and the node is half-applied (full run 2026-10-06 08:10: etcd's new manifest running, the rest still the old version) - deploy:upgrade:playbooks run again finishes it |
| 14 | containerd (no Wave 0) | containerd swapped under the running containers (they keep running: KillMode=process) with the kubelet stopped for the install (the package downloaded before): past some 50 s without the kubelet the node goes NotReady and every Service loses its endpoints (CoreDNS, the gateway, the webhooks) until it is back | by hand, as upgrade-containerd.yml's header says: Debian's containerd and the kept config back (not rehearsed) |
| 17 | scylladb-2025.1 (Wave 0: scylla) | ScyllaDB restarts on the new version - one node, unavailable for the restart (a minute or two) | one-way once it runs (ScyllaDB does not downgrade across releases): the Wave 0 Scylla backup restored with sctool (its restore rehearsed at this step in the full run; the old version on it is not) |
| 20 | scylladb-2026.1 (Wave 0: scylla) | ScyllaDB restarts on the new version - one node, unavailable for the restart (a minute or two) | one-way once it runs (ScyllaDB does not downgrade across releases): the Wave 0 Scylla backup restored with sctool (its restore rehearsed at this step in the full run; the old version on it is not) |
| 21 | scylla-operator-1.22 (no Wave 0) | the operator restarts; the ScyllaDB pod rolls for its agent version (the data app) and for the operator's sidecar image (the operator app) - two apps that sync apart, so possibly twice: ScyllaDB (one node) unavailable for each restart; Scylla Manager restarts (no backup or repair meanwhile); istiod reloads its injector's config for the new selector (its pod template is unchanged - rendered 2026-10-05: no restart) | the operator - revert the step's merge on main (Argo syncs back), its downgrade not rehearsed. Scylla Manager's own backend ScyllaDB moves 2026.1.3 -> 2026.2.5 and does not go back (a revert would start the old release on the newer files): back by a fresh backend at the old version instead - its volume deleted (Manager's state only; with the operator's approval) - after which the operator registers the clusters and their backup and repair tasks again from their ScyllaDBManagerClusterRegistration and ScyllaDBManagerTask resources; the snapshots stay in the store, where sctool lists them; the tasks' history is lost. Not rehearsed |
| 37 | strimzi-conversion (Wave 0: etcd) | none - Kafka runs on; Strimzi's Argo sync is off and its tool converts the resources | one-way: the CRDs' stored version is v1 afterwards (not rehearsed back); the resources as they were are in the Wave 0 etcd snapshot (5 of the KafkaTopics exist nowhere else) |
| 38 | strimzi-1.2 (Wave 0: kafka) | the operator rolls Kafka - one broker, unavailable for its restart | one-way: Strimzi 1.x serves v1 only; back by the Wave 0 Kafka backup with 0.51 (not rehearsed) |
| 40 | kafka-4.3 (Wave 0: kafka) | the broker restarts on 4.3 - Kafka unavailable for the restart (a minute) | the Wave 0 Kafka backup (taken at step 38 and here; its restore rehearsed at this step in the full run; the old version on it is not). A revert of the merge does not help: Strimzi moves the metadata version seconds after the one broker has rolled, and 4.2 cannot start on 4.3's - a window kept open only by a metadataVersion pinned in the chart (none is rendered; pinning it is the operator's decision) |
| 42 | kubernetes-1.35 (Wave 0: etcd) | the control-plane pods restart one at a time (the API server away for seconds; workloads keep running), the kubelet restarts | one-way - kubeadm does not downgrade; back only by a rebuild at the old version (DR-PROCEDURE.md's full rebuild: GitOps and each store's own backup), or the Wave 0 etcd snapshot restored into the node's etcd - for that no procedure is written and it is not rehearsed (only the snapshot's restore into a scratch data directory is, at this step in the full run). A failed apply is not rolled back: kubeadm returns a component only when that component's own restart fails, so the ones it upgraded stay upgraded and the node is half-applied (full run 2026-10-06 08:10: etcd's new manifest running, the rest still the old version) - deploy:upgrade:playbooks run again finishes it |
| 43 | kubernetes-1.36 (Wave 0: etcd) | the control-plane pods restart one at a time (the API server away for seconds; workloads keep running), the kubelet restarts | one-way - kubeadm does not downgrade; back only by a rebuild at the old version (DR-PROCEDURE.md's full rebuild: GitOps and each store's own backup), or the Wave 0 etcd snapshot restored into the node's etcd - for that no procedure is written and it is not rehearsed (only the snapshot's restore into a scratch data directory is, at this step in the full run). A failed apply is not rolled back: kubeadm returns a component only when that component's own restart fails, so the ones it upgraded stay upgraded and the node is half-applied (full run 2026-10-06 08:10: etcd's new manifest running, the rest still the old version) - deploy:upgrade:playbooks run again finishes it |
| 46 | postgres-18-test (Wave 0: postgres) | the test environment only: its Postgres down for pg_upgrade (minutes) | the test cluster's Wave 0 dump (the postgres store dumps every CNPG primary, this step's wave0 line) restored into a PostgreSQL 17 cluster - the test cluster has no base backups |
| 47 | postgres-18 (Wave 0: postgres) | Postgres down for pg_upgrade (minutes) - every app's writes fail; the replica re-cloned after | the step's restore-undo: PostgreSQL 17's latest backup recovered under the old server name (recovered into a side cluster in the full run; replacing production's cluster with it - its volumes deleted, writes since lost - is neither written down nor rehearsed), or the Wave 0 dump |
| 50 | grafana-13 (Wave 0: grafana) | Grafana down while it migrates its database | one-way: the Wave 0 Grafana backup (grafana.db) with Grafana 12 (its restore rehearsed at this step in the full run; the old version on it is not) |
| 51 | mimir-3.0 (Wave 0: gateway) | Mimir restarts - Prometheus retries its remote write, queries fail briefly | one-way (3.x may write what 2.x cannot read): the Wave 0 gateway backup - the object store's and Mimir's volumes (its restore rehearsed at this step in the full run; the old version on it is not) |
| 54 | tempo-3 (Wave 0: gateway) | Tempo restarts - spans sent meanwhile are lost; the ones Tempo 2 still holds in its WAL (Tempo 3 does not replay it) are flushed to the store first: the tempo-flush line below - production's merge calls Tempo's /flush right before the infra merge, the full run before the step's push, and wants a trace pushed before the flush back after it | one-way (Tempo 3 blocks): the Wave 0 gateway backup (its restore rehearsed at this step in the full run; the old version on it is not) |
| 57 | sonarqube-26.9 (Wave 0: postgres) | SonarQube down while it migrates its database (production only); production waits up to 50 minutes for Argo after each merge (the migration hook's own deadline is 45) | one-way: SonarQube's Postgres dump from Wave 0 (the postgres store) with 26.3 |
| 59 | clickhouse-25.8 (Wave 0: clickhouse) | ClickHouse restarts on 25.8 - log ingestion waits | back to 24.8 while the pin keeps 24.8's formats (revert the step's merge on main (Argo syncs back)) - 24.8 reads what 25.8 wrote and merged under the pin (rehearsed with the real images: task test:clickhouse-pin; the revert through Argo is not); otherwise the Wave 0 ClickHouse backup (its restore rehearsed at this step in the full run) |
| 61 | clickhouse-26.8 (Wave 0: clickhouse) | ClickHouse restarts on 26.8 - log ingestion waits | back to 25.8 while the pin keeps 25.8's formats (drop or unlock the renamed system.*_log_N tables first) - 25.8 starts on the data and reads what 26.8 wrote and merged under the pin (rehearsed with the real images: task test:clickhouse-pin - the system log tables not looked at, the revert through Argo not rehearsed); otherwise the Wave 0 ClickHouse backup |

## Production, step by step (after the gate and the operator's approval)

Gate: full run 7 green (`task test:upgrade:full`: built from nothing, every step in one unattended run, each green
step's proof recorded), then the full review of the whole upgrade work with its fixes proven (the full run repeated
when a fix touches the steps or the harness), then the operator's approval.

One step at a time, in the step files' order, only through the deploy:upgrade:* tasks: scripts/upgrade-production.py
keeps a ledger on ten (ConfigMap kube-system/upgrade-ledger) and refuses a phase whose predecessors are missing.
`task deploy:upgrade:ledger-init` once (step 02 recorded done: in production since 2026-10-03, infra e89bbbb); `task
deploy:upgrade:status` names the next phase and what stands before it. Per step N:

1. `deploy:upgrade:begin STEP=N` - every earlier step done; N and every step before it proven by one full run; ten's
   and the Pis' inventory as the done steps leave it (the test environment, schnappy-test, listed apart - the Vagrant
   copy has none); Argo settled on main's commits, judged on ten (4 polls, no container restarted in 5 minutes; the step
   before's argo-out-of-sync apps allowed).
2. `deploy:upgrade:backup STEP=N STORE=s` - each wave0 line, before anything changes.
3. `deploy:upgrade:merge STEP=N REPO=r` - each branch line in the file's order. The branch restacked on origin/main
   first when main moved (the apps' CD pushes image tags to infra main): `scripts/upgrade-restack-in-place.sh ../infra`
   (merged steps, tagged upgrade-merged/<step>, are skipped).
   Refused unless its own change (changed lines, files, modes and binaries) is the one the full run proved, the
   step's new images from production's own registry are there, and the state between the step's two merges is one the
   run proved (scripts/upgrade-merge-order.py: the first merge alone renders every platform-chart application as
   before, or the second renders nothing new). Then the change is shown (log, stat, diff) and the operator answers;
   a step with a tempo-flush line (54) flushes Tempo's WAL to the store right before that repo's merge. Pushed and
   tagged upgrade-merged/<step> (a run cut short between the two is taken up); Argo settled on the pushed commits
   within 30 minutes (a step's `settle` line overrides: 57, SonarQube's migration), nothing out of sync.
4. `deploy:upgrade:preview STEP=N` - a step with playbook lines, after its merges settled: check mode with diffs
   (read-only probes run, waits on changes the preview does not make are skipped), read by the operator. The full run
   runs the same preview on the Vagrant copy at every such step, so it is proven to pass.
5. `deploy:upgrade:playbooks STEP=N` - after every merge settled and the preview.
6. `deploy:upgrade:defaults STEP=N` - a step with default lines: they and the step's name in
   tests/ansible/upgrade/defaults-committed.txt, one commit to ops main, pushed (only the next step's; CI's
   `upgrade-defaults.py --lint` and the targets branch start after the recorded ones). A run cut short after its commit
   or its push is taken up where it stopped. The proof check then allows exactly those lines and that record.
7. `deploy:upgrade:done STEP=N` - ten as the step leaves it (its argo-out-of-sync apps allowed). The first green call
   starts the soak: 60 minutes after a wave0 step, 15 otherwise (a step's `soak` line overrides). Called again after it
   - green, with no container restarted since the first green call - the step is done. A red call during the soak
   restarts it. A cert-renew step's first call issues a throwaway certificate through production's ACME solver, a
   barman-check step's takes a Postgres base backup: that call asks first.
Each phase that changes production asks first (the phase's own question, after showing what it will change) - the
operator approves each. Every phase first checks the full run's proof: the step and every step before it proven by
that one run; the ops paths it ran (deploy/, scripts/, tests/, Taskfile.yml, Vagrantfile) as it had them, but for the
committed steps' default lines; production's app tags (infra main) those it ran (the Vagrant overlay's: the candidate
images are promoted before the rollout's first step); the floating-tag images at the digests it ran. A phase claims
the step in the ledger (a start event, then its end): another phase of the step is refused while one runs, and a run
killed before its end is closed by `task deploy:upgrade:release STEP=N` (it asks first).

Stop criteria: the rollout stops at the first of these - a phase refused or failed, Argo not settled after a merge,
an inventory difference, a restart during the soak - and the step's abort line, with the operator, decides what
follows. Nothing of the next step can start: its begin wants this one done.

