# Plan 100 — upgrade the cluster to current releases

Status: **PLANNED** (2026-10-01). No change to the production cluster until every Vagrant upgrade test passes and the
operator approves.

## Decisions (operator, 2026-10-01)

- Upgrade every component to its latest release, kagent excepted (left as it is).
- PostgreSQL 18: **option A** — in-place major upgrade by CNPG on the same Debian bullseye image line
  (`18.6-system-bullseye`, pinned by digest). The move to the trixie image line is a later, separate step.
- ScyllaDB: move from 6.2 (last AGPL release) to the source-available 2025.x/2026.x line (free tier: 50 vCPU / 10 TB
  per organisation; we run `--smp=2`).
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
| containerd | 1.7.24 (Debian) + 2.0.2 (nerdctl-full in /usr/local) | 2.3 LTS | one install, from Docker's apt repo |
| Cilium (+ Hubble UI) | 1.19.1 (0.13.3) | 1.20.2 (0.13.6) | 1.19.8 → 1.20.2 |
| Istio | 1.25.2 (EOL, unsupported on k8s 1.34) | 1.31.1 | in place, one minor per step (operator 2026-10-03): 1.26 → … → 1.31, mesh workloads restarted each step; charts from blob.istio.io first (defect 17) |
| Gateway API CRDs | v1.2.1 | v1.5.x | before Istio 1.30 |
| Argo CD | 3.3.8 (chart 9.5.4) | 3.5.3 (chart 10.9.6) | 3.3.14 → 3.4 → 3.5 |
| cert-manager | 1.20.0 | 1.21.2 | 1.20.4 → 1.21.2 |
| External Secrets | 2.2.0 (CRDs never upgraded) | 2.11.0 | CRDs under Argo first, then one minor at a time |
| CloudNativePG | 1.29.0 | 1.30.1 | direct |
| PostgreSQL | 17.9 (bullseye system image) | 18.6 | CNPG offline in-place upgrade |
| Strimzi / Kafka | 0.51.0 / 4.2.0 | 1.2.0 / 4.3.1 | v1 CRD conversion on 0.51 → 1.2.0 → Kafka 4.3.1 |
| Scylla Operator | 1.20.2 | 1.22.0 | 1.20.3 → 1.21.1 → 1.22.0 (N+1 only) |
| ScyllaDB (prod, test) | 6.2.3 | 2026.3.2 | 2025.1 → (op 1.21) → 2026.1 → (op 1.22) → 2026.3.2 |
| ScyllaDB (manager backend) | 2026.1.0 | 2026.3.2 | with the operator steps |
| Scylla Manager + agent | 3.9.0 | 3.12.1 | 3.10 → 3.12 with the operator |
| Valkey | 8.1 | 9.1 | direct (emptyDir: cache wiped) |
| Velero / AWS plugin | 1.18.0 / 1.11.1 (off-matrix) | 1.18.4 / 1.14.4 | direct |
| versitygw (cluster, Pi) | 1.6.0 | 1.8.0 | cluster first, Pi outside 02:00–04:00 |
| local-path-provisioner | 0.0.35 | 0.0.37 (chart 0.0.38, pinned) | direct |
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

A new `tests/ansible/test-upgrade.yml` with `task test:upgrade`, run detached like the DR drill.

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
- **Steps proven** (2026-10-03): 01 apt-cacher-ng from CI (7b46aea), 02 cert-manager v1.20.4, 03 CNPG 1.30.1,
  04 Velero 1.18.4 + plugin 1.14.4, 05 versitygw 1.8.0 (cluster and Pis), 06 local-path 0.0.37. Each step also takes a
  Velero backup from production's daily schedule (`backup-check.yml`) and provisions a new volume (`storage-check.yml`).
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
with every fix - the guards, backup checks only on their 17 steps, the restore check at the end. Full run 3 next.

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
  serverName in the same change; read ten's timelineID and archive history first; pin the image by digest.
- R2 Re-runs downgrade: setup-kubeadm (Debian containerd over containerd.io, ESO 2.2.0, k8s pins) and setup-argocd
  (chart default) - fail-closed guards against a downgrade, then the new defaults, before any production step.
  DONE 3ac3eb9 (guards; the new defaults move with each production step).
- R3 Backups gate (Wave 0 as code): every store a one-way step changes - Postgres (pg_dumpall + CNPG base backup),
  Kafka, ScyllaDB (prove a restore of the existing backup), Grafana, ClickHouse, Mimir/Tempo (in-cluster versitygw
  PV), SonarQube's Postgres; each restore rehearsed in Vagrant.
- R4 upgrade-containerd rebuilds config from defaults: read ten's live config.toml; migrate it (containerd config
  migrate) and fail on unknown settings; a guard that requires the new config + CRI + version; a rescue to the kept
  config. DONE fed85ea (Vagrant: pre-check, swap with 16 containers kept, re-run, rescue).
- R5 kubeadm upgrade resets the kubelet's graceful shutdown (config.yaml rewritten from the kubelet-config ConfigMap):
  the settings into the ConfigMap, re-asserted after each upgrade. DONE 3eb9a2d (the ConfigMap step for production
  comes with R14's restructure).
- R6 Tempo 3: backend_scheduler.local_work_path defaults to /var/tempo on a read-only root - no compaction or
  retention; set it under /data; prove retention deletes in Vagrant.
- R7 Step 27: ESO CRDs under Argo prune - a revert deletes every ExternalSecret and its Secrets: CRD annotations
  Prune=false,Delete=false in the same change.
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
- R10 Defect 18: ClickHouse default user from ::/0 - fix; the metrics check reads as schnappy.

Rollout behaviour
- R11 Root sync waits on child health wave by wave from step 12: every production app Healthy before 12 and before
  20-25; the infra sync waves committed (scylla manager after operator, ...) instead of the Vagrant-only overrides.
- R12 restart-mesh-workloads: `|| true` passes a failed read; restart the data tier first, then apps; kagent included
  (operator); steps 20-25 marked stateful with their outages. DONE e4c87da (the stateful marks with R18).
- R13 Step 24: Istio 1.30 images from registry.istio.io (scream tests 10-13, 11-17, 12-08/09): global.hub docker.io.
- R14 Step order inside every support matrix (operator); test env before production for Postgres, Kafka, ScyllaDB
  (versions as values per environment).
- R15 Step 05: the Pis' versitygw upgrade never restarts the service; restart on version change, one Pi at a time;
  assert the running version.
- R16 Cilium on ten: helm repo index never refreshed (steps 13/17 would fail); compare rendered cilium-config with the
  live, hand-patched one; upgradeCompatibility for 1.19->1.20. DONE: the repo refreshed (force_update); one
  cilium_values for install and check; before an upgrade the running chart is rendered from them on the node's Helm and
  must equal the live cilium-config key for key, or the run refuses (ten read-only 2026-10-04: Helm 3.20 renders 154
  keys, all equal to live; Vagrant: a key added by hand refused, a clean run passed without restarting Cilium);
  upgradeCompatibility "1.19" - no change at 1.19, at 1.20.2 it keeps envoy-xds-mode as 1.19 had it, the only change
  1.20 makes to ten's config besides its new features' keys at their defaults.
- R17 Grafana: RollingUpdate on one SQLite volume - Grafana 12 and 13 at once during the one-way migration: Recreate.
- R18 Step files' playbook lines are Vagrant command lines: a production command per step; task deploy:upgrade:*
  wrappers; read-only production checks after each step; per-step abort/revert and outage notes.
- R19 apt-cacher-ng image pull on ten (no imagePullSecrets); local-path-config on ten (path); ScyllaCluster/Kafka
  managedFieldsManagers ignore rules; Docker apt source on ten; argocd image-tag override across 12/29/30; strimzi
  guard fail-open; restart-mesh and settle checks on empty data; apt keyring emptied by a failed curl. DONE: strimzi
  guard + its RBAC always removed, settle check, apt keyring (b5b9f40), restart-mesh (e4c87da); the rest open.

Test harness
- R20 argo-settled: a failed sync passes; restarts ignored; a failed pod query counts as all ready; one green poll
  ends the wait; comparedTo not checked.
- R21 Data survival not checked for one-way steps: seed and verify ClickHouse, Grafana, Tempo, Mimir; the
  compatibility pin via system.merge_tree_settings; versions per step.
- R22 data-check never writes after a step (replication, Kafka produce, Scylla write); metrics-check misses vanished
  targets; barman check missing at 05; restore-check never replays WAL nor restores the Postgres 17 backup.
- R23 Smaller: step 01 invisible to the inventory diff; a missing step branch unnoticed; step-file arguments
  unvalidated; empty step list green; no pipefail in task; CoreDNS rewrite unchecked; vms-ready must bring Gluster
  mounts up after the harness's own reboots (until R9).

Plan and claims
- R24 Every false or stale claim the reviews listed, corrected in this file, the step files and playbook comments.

## Stateful steps - for the operator's approval

Production runs one Kafka broker, one ScyllaDB node, one ClickHouse and two Postgres instances: a roll of the first
three is an outage of that service for the restart. Each row was proven in Vagrant on a copy of production with
seeded data (Postgres 10,000 rows on both instances, 1,000 Kafka messages, 1,000 ScyllaDB rows, md5 each).

| # | Change | Outage | Undo | Vagrant proof |
|---|---|---|---|---|
| 33 | Argo stops auto-syncing Strimzi; Strimzi's own tool rewrites every Strimzi resource (ten's 13 unmanaged KafkaTopics too) and the CRDs' stored version to v1 | none | 0.51 serves v1 too: staying on 0.51 works; v1beta2 storage does not come back | 10 CRDs store only v1, Kafka Ready, messages intact |
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

## Production rollout (after all tests pass and approval)

Gate: every step green in Vagrant on its own, then `task test:upgrade:full` green (built from nothing, steps 01-55 in
one unattended run), then the operator's approval. Step 19 is already in production (2026-10-03, infra e89bbbb).

How a step goes to production: its `upgrade/NN-*` branches merge to main in step order (infra and platform are pushed
straight to main; Argo syncs them), and its `playbook` lines run against `inventory/production.yml` - after which that
playbook's default takes the step's `-e` value in the same change (setup-kubeadm.yml: k8s_version/k8s_package_version,
containerd.io instead of Debian's containerd, cilium_version, gateway_api_version, local_path_provisioner_version, and
the External Secrets Helm install `when: not platform_by_argo`; setup-argocd.yml: argocd_version). One step at a time,
each verified as in Vagrant (Argo synced and healthy, data, backup, metrics, the k6 smoke) before the next.

Waves in this order:

0. Backups: CNPG base backup + `pg_dumpall` to the Pi, etcd snapshot, Grafana's volume (13 migrates it one way). Velero
   holds no data volume (defect 20): Kafka and ScyllaDB need their own copy before steps 33-41 - a Scylla Manager
   backup task (none exists) and a Kafka topic export - or the operator accepts their loss risk.
1. Patches (01-12): apt-cacher-ng from CI (defect 9), cert-manager 1.20.4, CNPG 1.30.1, Velero 1.18.4 + plugin 1.14.4,
   versitygw 1.8.0, local-path 0.0.37, kube-prometheus-stack 91.8.2, Alertmanager, blackbox, ksm, Grafana 12.4.12,
   Mimir 2.17.11, Fluent Bit 4.2.8, Argo CD 3.3.14.
2. Platform (13-26): Cilium 1.19.8 -> k8s 1.34.12 -> containerd.io 2.3.6 -> k8s 1.35.9 -> Cilium 1.20.2 -> Gateway API
   v1.5.1 -> Istio 1.26 ... 1.31 in place, one minor each with every mesh workload restarted
   (restart-mesh-workloads.yml) -> k8s 1.36.5.
3. Operators and data (27-43): External Secrets CRDs under Argo, then 2.11; Argo CD 3.4, 3.5; cert-manager 1.21;
   Strimzi v1 conversion, 1.2.0, Kafka 4.3.1; Scylla operator 1.20.3 -> 1.21 -> 1.22 with ScyllaDB 2025.1 -> 2026.1 ->
   2026.3; PostgreSQL 18 in place (downtime; a fresh base backup after it - the old major's WAL cannot restore 18);
   Valkey 9.1.
4. Observability (44-55): Grafana 13, Mimir 3.0 -> 3.1 -> 3.2, Tempo 3, Fluent Bit 5, Centrifugo 6.9, SonarQube 26.9,
   ClickHouse 25.8 -> 26.8 (the compatibility pin's removal is the operator's decision).

Rules: one component per change; check its history and live effect first; stateful steps (S in the table) shown to
the operator with the exact change before they run.
