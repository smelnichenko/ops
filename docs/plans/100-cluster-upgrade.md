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
   fixed and proven, and the full run repeated if a fix touches the steps or the harness;
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
| Kubernetes (kubeadm) | 1.34.6 | 1.36.5 | 1.34.12 → 1.35.x → 1.36.5 (one minor per run) |
| etcd / CoreDNS | 3.6.5 / 1.12.1 | 3.6.8 / 1.14.2 (kubeadm 1.36.5's) | with kubeadm; etcd ≥ 3.6.11 is etcd 3.7's prerequisite - k8s 1.37, not now |
| containerd | 1.7.24 (Debian; nerdctl-full's 2.0.2 binaries in /usr/local run nothing - defect 4) | 2.3 LTS | one install, from Docker's apt repo |
| Cilium (+ Hubble UI) | 1.19.1 (0.13.3) | 1.20.2 (0.13.6) | 1.19.8 → 1.20.2 |
| Istio | 1.25.2 (EOL, unsupported on k8s 1.34) | 1.31.1 | in place, one minor per step (operator 2026-10-03): 1.26 → … → 1.31, mesh workloads restarted each step; charts from blob.istio.io first (defect 17) |
| Gateway API CRDs | v1.2.1 | v1.5.x | before Istio 1.30 |
| Argo CD | 3.3.8 (chart 9.5.4) | 3.5.3 (chart 10.9.6) | 3.3.14 → 3.4 → 3.5 |
| cert-manager | 1.20.0 | 1.21.2 | 1.20.4 → 1.21.2 |
| External Secrets | 2.2.0 (CRDs never upgraded) | 2.11.0 | CRDs under Argo first, then 2.2 -> 2.11 directly (only the newest minor is supported) |
| CloudNativePG | 1.29.0 | 1.30.1 | direct |
| PostgreSQL | 17.9 (bullseye system image) | 18.6 | CNPG offline in-place upgrade |
| Strimzi / Kafka | 0.51.0 / 4.2.0 | 1.2.0 / 4.3.1 | v1 CRD conversion on 0.51 → 1.2.0 → Kafka 4.3.1 |
| Scylla Operator | 1.20.2 | 1.22.0 | 1.20.3 → 1.21.1 → 1.22.0 (N+1 only) |
| ScyllaDB (prod, test) | 6.2.3 | 2026.3.2 | 2025.1 → (op 1.21) → 2026.1 → (op 1.22) → 2026.3.2 |
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
| SonarQube CE | 26.3.0 | 26.9.0 | direct; DB migration via `/setup` |
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
- **The isolation's CoreDNS `template` blocks stop `kubeadm upgrade`** when it bumps CoreDNS (step 16, v1.12.1 -> v1.13.1):
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
  ~8 min) runs after 04 and 05 only - Velero and its store: it holds no data volume (defect 20), so after any other
  step it guarded the least valuable backup at half a step's time; it ran after every step until full run 2. The
  backup production's data depends on, CNPG's barman backup of Postgres, is checked after 03 (the CNPG operator) and
  42 (PostgreSQL 18): WAL archiving working and a fresh base backup completed (`barman-check.yml`). Step files mark
  them (`backup-check`, `barman-check`); the restore check closes the run.
- **ClickHouse's compatibility pin applies at the next start**: the users file is a subPath mount, which never sees a
  ConfigMap change, so steps 52 and 54 change nothing in the running server; the image bumps right after them (53,
  55) restart it with the pin in place before the new version writes a part - the order that matters. Checked with
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
(defect 22). Next: full run 7, after the review's fixes and the reordering.

**Gate before the production rollout** (operator, 2026-10-03): every step green on its own, then one full run green -
`task test:upgrade:full`: the Vagrant copy built from nothing, then steps 01-55 in order, unattended, every check
after each. Fixes made while steps run one at a time prove the step, not the chain.

| # | Step | Where | Vagrant |
|---|---|---|---|
| 01 | apt-cacher-ng from CI (defect 9) | platform | green |
| 02 | cert-manager v1.20.4 | infra | green |
| 03 | CNPG 1.30.1 | infra | green |
| 04 | Velero 1.18.4 + AWS plugin 1.14.4 (defect 3) | infra | green |
| 05 | versitygw 1.8.0 (cluster, Pis) | platform + playbook | green |
| 06 | local-path 0.0.37 | playbook | green |
| 07 | kube-prometheus-stack 91.8.2 (operator 0.94.1) | infra | green |
| 08 | Alertmanager 0.34.1, blackbox 0.28.0, ksm 2.20.0 | platform | green |
| 09 | Grafana 12.4.12 | infra | green |
| 10 | Mimir 2.17.11 | infra | green |
| 11 | Fluent Bit 4.2.8 | infra | green |
| 12 | Argo CD 3.3.14 | playbook | green |
| 13 | Cilium 1.19.8 | playbook | green |
| 14 | Kubernetes 1.34.12 | playbook | green |
| 15 | containerd.io 2.3.6 (replaces Debian's 1.7) | playbook | green |
| 16 | Kubernetes 1.35.9 (+ etcd backup image) | infra + playbook | green |
| 17 | Cilium 1.20.2 | playbook | green |
| 18 | Gateway API v1.5.1 | playbook | green |
| 19 | Istio charts from blob.istio.io (defect 17; can go early) | infra | green; IN PRODUCTION 2026-10-03 19:47 (infra e89bbbb, operator OK) |
| 20-25 | Istio 1.26.8 ... 1.31.1 in place, mesh restarted each | infra + playbook | 20-25 green (mesh restarted each; 1.30 pulls from registry.istio.io) |
| 26 | Kubernetes 1.36.5 (+ etcd backup image) | infra + playbook | green |
| 27 | External Secrets CRDs under Argo (defect 2) | infra | green (argocd-controller applies the CRDs server-side) |
| 28 | External Secrets 2.11.0 | infra | green (all 25 CRDs = chart 2.11.0, 2 new) |
| 29-30 | Argo CD 3.4.6, 3.5.3 | playbook | green (root stayed Synced through both) |
| 31 | cert-manager v1.21.2 | infra | green |
| 32 | Strimzi templates on v1 (defect 7) | platform | green |
| 33 | Strimzi v1 conversion (Argo automation off) | infra + playbook | S; green (10 CRDs store only v1, Kafka Ready, messages intact) |
| 34 | Strimzi 1.2.0 (automation back) | infra | S; green (Kafka rolled onto 1.2.0, messages intact; ignoreDifferences for the CRD's dropped empty map) |
| 35 | Kafka 4.3.1 | platform | S; green (metadata version moved with it, messages intact) |
| 36-41 | Scylla Operator 1.20.3/1.21.1/1.22.0 with ScyllaDB 2025.1.16/2026.1.14/2026.3.2 | infra | S; green (ScyllaDB 2026.3.2 with the operator's node-exporter sidecar, rows intact) |
| 42 | PostgreSQL 18.6 in place (defect 6) | platform | S; green (both instances 18.6, data major 18, rows intact) |
| 43 | Valkey 9.1.2 | infra + platform | green |
| 44 | Grafana 13.2.3 (one-way storage migration) | infra | S; green (database ok, 6 dashboards as on ten, 3 datasources) |
| 45-47 | Mimir 3.0.8, 3.1.6, 3.2.1 | infra | green |
| 48 | Tempo 3.1.0 (monolithic, one-way) | infra + platform | S; green (v3.1.0 receiving OTLP and Zipkin spans, search answers) |
| 49 | Fluent Bit 5.1.3 | infra | green (logs still reach ClickHouse) |
| 50 | Centrifugo 6.9.7 | infra + platform | green |
| 51 | SonarQube 26.9.0 - not in the Vagrant copy: production-only | infra + platform | n/a (the step ran green: nothing else moved) |
| 52 | ClickHouse compatibility 24.8 (keeps formats readable for a rollback) | platform | green (in effect from 53's restart) |
| 53 | ClickHouse 25.8.33.6 | infra + platform | S; green (25.8.33.6 up with compatibility 24.8, logs flowing) |
| 54 | ClickHouse compatibility 25.8 | platform | green (in effect from 55's restart) |
| 55 | ClickHouse 26.8.15.10 (the pin's removal later: operator's call, no return) | infra + platform | S; green (26.8.15.10 with compatibility 25.8, logs flowing) |

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
- R4 upgrade-containerd rebuilds config from defaults: read ten's live config.toml; migrate it (containerd config
  migrate) and fail on unknown settings; a guard that requires the new config + CRI + version; a rescue to the kept
  config. DONE fed85ea (Vagrant: pre-check, swap with 16 containers kept, re-run, rescue).
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
  setting against the step files' clickhouse-compat lines (24.8 from the 25.8 step, 25.8 from the 26.8 one), every
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
  window, Scylla repair Sunday 04:00 - each step's time chosen around them; the Istio steps restart kagent, SonarQube
  and its Postgres, the test environment and PR environments too (a read-only list before the first).
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
- F24 The ClickHouse pin's rollback is unproven (getSetting reads a session setting): rehearsed in Vagrant - 25.8
  under the pin writes and merges parts, the image back to 24.8 reads them.
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
- wave0 lines on the one-way steps (17, 20 scylla; 38, 40 kafka; 46, 47, 57 postgres; 50 grafana; 51, 54 gateway;
  59, 61 clickhouse): production's backup phase; the full run's side is F8.

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
1.31 v1.6.0. Gateway API v1.5 refuses a downgrade (step 18 is one-way). Strimzi 0.51 -> 1.2 directly: not yet
checked against Strimzi's upgrade notes.

The current order runs Argo CD 3.3, cert-manager 1.20, ESO 2.2, Strimzi 0.51 and Scylla Operator 1.20 on Kubernetes
1.36 (steps 26-37), Istio 1.25-1.28 on 1.35 (16-22). Proposed order (each step's content unchanged):
A (at 1.34): 19, 20, 21, 22, 23 (Istio 1.29 before 1.35 - 1.28 ends at 1.34), 18, 24, 25, 04, 13, 14, 15, 36, 37,
38, 39, 40; B: 01, 02, 03, 05, 06, 07, 09, 10, 11, 12; C (move to 1.36-capable versions, still on 1.34): 17, 29, 30,
31, 32, 33, 34, 35, 27; D: 16, 26, 28 (right after 26: ESO 2.11 lists 1.36 only), 08 (ksm 2.20 pairs with 1.36);
E: 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, then 41. Every moved step is re-proven by the full run.
Unavoidable windows: Istio 1.26-1.27 on 1.34 (one minor at a time); containerd 2.3 is listed for 1.36 only (a direct
1.7 -> 2.3 LTS hop is supported by containerd); ESO 2.2 on 1.36 between 26 and 28; ksm 2.18 on 1.35.
Mine to fix: the kubectl images to 1.35.x before 26; step 25's comment (Istio 1.31: 1.32-1.36, not 1.37) - DONE;
step 40 pins Scylla Manager and its agents to the target 3.12.1 (the chart's default is 3.12.0) - with the restructure.
Operator's decisions (2026-10-05): ScyllaDB 2026.1 LTS - step 41 (2026.3) dropped, its branch kept as
upgrade-old/41-scylladb-2026.3 only, the schema Job's cqlsh image pinned to 2026.1.14 with step 39 instead;
containerd in one hop; ESO's window accepted (no 2.8 step); Gateway API stops at v1.5.1.

Applied 2026-10-05 (scripts/upgrade-restack.py; the old branches kept as upgrade-old/*): every branch re-created in the
new order, each step's own commits cherry-picked without a conflict; platform's final tree identical to before,
infra's differs exactly by the dropped 2026.3 (back to 2026.1.14). Every step's refs and inventory checks pass in
the new order. The new numbers - the text of this plan written before 2026-10-05 uses the old ones:

| New | Old | Step |
|---|---|---|
| 01 | 00 | argocd-root-retry |
| 02 | 19 | istio-chart-repo |
| 03 | 20 | istio-1.26 |
| 04 | 21 | istio-1.27 |
| 05 | 22 | istio-1.28 |
| 06 | 23 | istio-1.29 |
| 07 | 18 | gateway-api |
| 08 | 24 | istio-1.30 |
| 09 | 25 | istio-1.31 |
| 10 | 04 | velero |
| 11 | 13 | cilium |
| 12 | 13 | kubelet-shutdown-grace |
| 13 | 14 | kubernetes-1.34.12 |
| 14 | 15 | containerd |
| 15 | 36 | scylla-operator-1.20.3 |
| 16 | 37 | scylladb-2025.1 |
| 17 | 38 | scylla-operator-1.21 |
| 18 | 39 | scylladb-2026.1 |
| 19 | 40 | scylla-operator-1.22 |
| 20 | 01 | apt-cacher-ng |
| 21 | 02 | cert-manager |
| 22 | 03 | cnpg |
| 23 | 05 | versitygw |
| 24 | 06 | local-path |
| 25 | 07 | kube-prometheus-stack |
| 26 | 09 | grafana |
| 27 | 10 | mimir |
| 28 | 11 | fluent-bit |
| 29 | 12 | argocd |
| 30 | 17 | cilium-1.20 |
| 31 | 29 | argocd-3.4 |
| 32 | 30 | argocd-3.5 |
| 33 | 31 | cert-manager-1.21 |
| 34 | 32 | strimzi-v1-templates |
| 35 | 33 | strimzi-conversion |
| 36 | 34 | strimzi-1.2 |
| 37 | 35 | kafka-4.3 |
| 38 | 27 | eso-crds |
| 39 | 16 | kubernetes-1.35 |
| 40 | 26 | kubernetes-1.36 |
| 41 | 28 | eso-2.11 |
| 42 | 08 | alertmanager-blackbox-ksm |
| 43 | 42 | postgres-18 |
| 44 | 43 | valkey-9.1 |
| 45 | 44 | grafana-13 |
| 46 | 45 | mimir-3.0 |
| 47 | 46 | mimir-3.1 |
| 48 | 47 | mimir-3.2 |
| 49 | 48 | tempo-3 |
| 50 | 49 | fluent-bit-5 |
| 51 | 50 | centrifugo-6.9 |
| 52 | 51 | sonarqube-26.9 |
| 53 | 52 | clickhouse-compat-24.8 |
| 54 | 53 | clickhouse-25.8 |
| 55 | 54 | clickhouse-compat-25.8 |
| 56 | 55 | clickhouse-26.8 |

## Stateful steps - for the operator's approval

Production runs one Kafka broker, one ScyllaDB node, one ClickHouse and two Postgres instances: a roll of the first
three is an outage of that service for the restart. Each row was proven in Vagrant on a copy of production with
seeded data (Postgres 10,000 rows on both instances, 1,000 Kafka messages, 1,000 ScyllaDB rows, md5 each).

| # | Change | Outage | Undo | Vagrant proof |
|---|---|---|---|---|
| 18 | Gateway API CRDs v1.2.1 -> v1.5.1 (with their safe-upgrades ValidatingAdmissionPolicy) | none | one-way: the policy refuses v1.0-v1.4 CRDs - delete it first to go back; setup-kubeadm's default moves to v1.5.1 with the step | v1.5.1 serves every version v1.2.1 did; Istio 1.25 reads on |
| 33 | Argo stops auto-syncing Strimzi; Strimzi's own tool rewrites every Strimzi resource (ten's 13 KafkaTopics too, 5 of them made by hand) and the CRDs' stored version to v1 | none | 0.51 serves v1 too: staying on 0.51 works; v1beta2 storage does not come back | 10 CRDs store only v1, Kafka Ready, messages intact |
| 34 | Strimzi 0.51.0 -> 1.2.0, auto-sync back; the broker rolls onto the 1.2.0 image (Kafka 4.2.0) | Kafka, one roll | chart back to 0.51 (reads v1) | operator 1.2.0 reconciles, messages intact |
| 35 | Kafka 4.2.0 -> 4.3.1; Strimzi then moves the metadata version to 4.3-IV0 | Kafka, a rolling update | none once the metadata version moved | 4.3.1, 4.3-IV0, Ready, messages intact |
| 37 | ScyllaDB 6.2.3 -> 2025.1.16 (source-available line) | ScyllaDB, one roll | none (new SSTables) | rows intact |
| 39 | ScyllaDB 2025.1.16 -> 2026.1.14 (LTS to LTS) | ScyllaDB, one roll | none | rows intact |
| 41 | ScyllaDB 2026.1.14 -> 2026.3.2; node-exporter becomes the operator's sidecar | ScyllaDB, one roll | none | rows intact, every scrape target up |
| 42 | PostgreSQL 17 -> 18.6, CNPG offline in-place (pg_upgrade on the primary, replica re-cloned) | Postgres, minutes | none: restore from the pre-upgrade backup; take a fresh base backup after (17's WAL cannot restore 18) | both instances 18.6, data major 18, rows on both |
| 44 | Grafana 12.4.12 -> 13.2.3, its storage migrated on start | Grafana, one restart | restore the volume backed up first | database ok, 6 dashboards as on ten, 3 datasources |
| 48 | Tempo 2.7.2 -> 3.1.0 monolithic | Tempo, one restart | 2.x cannot read blocks 3.x wrote | v3.1.0 ingests OTLP and Zipkin, search answers |
| 53 | ClickHouse 24.8 -> 25.8.33.6 with compatibility 24.8 (step 52) | ClickHouse, one restart (logs buffer in Fluent Bit) | image back to 24.8 while the pin stays | 25.8.33.6 under 24.8, logs flowing |
| 55 | ClickHouse 25.8 -> 26.8.15.10 with compatibility 25.8 (step 54) | ClickHouse, one restart | image back to 25.8 while the pin stays; removing the pin is the point of no return (operator's call) | 26.8.15.10 under 25.8, logs flowing |

Before 33-41 (Kafka, ScyllaDB): Velero holds no copy of their data (defect 20) - a backup first, or the operator
accepts the risk. Before 42: CNPG base backup + `pg_dumpall` to the Pi. Before 44: Grafana's volume.

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
3. `deploy:upgrade:preview STEP=N` - a step with playbook lines: check mode with diffs, read by the operator.
4. `deploy:upgrade:merge STEP=N REPO=r` - each branch line in the file's order. The branch restacked on origin/main
   first when main moved (the apps' CD pushes image tags to infra main): `scripts/upgrade-restack-in-place.sh ../infra`.
   Refused unless its own change (changed lines and files) is the one the full run proved, deploy/ and the step file
   are as that run had them, and the state between the step's two merges is one the run proved
   (scripts/upgrade-merge-order.py: the first merge alone renders every platform-chart application as before, or the
   second renders nothing new). Pushed; Argo settled on the pushed commits within 30 minutes, nothing out of sync.
5. `deploy:upgrade:playbooks STEP=N` - after every merge settled and the preview.
6. `deploy:upgrade:done STEP=N` - ten as the step leaves it (its argo-out-of-sync apps allowed). The first green call
   starts the soak: 60 minutes after a wave0 step, 15 otherwise (a step's `soak` line overrides). Called again after it
   - green, with no container restarted since the first green call - the step is done. A red call during the soak
   restarts it.
Each phase that changes production asks first (the task's prompt) - the operator approves each.

Stop criteria: the rollout stops at the first of these - a phase refused or failed, Argo not settled after a merge,
an inventory difference, a restart during the soak - and the step's abort line, with the operator, decides what
follows. Nothing of the next step can start: its begin wants this one done.

