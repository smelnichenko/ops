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
| etcd / CoreDNS | 3.6.5 / 1.12.1 | with kubeadm; etcd pinned ≥ 3.6.11 at 1.36 | |
| containerd | 1.7.24 (Debian) + 2.0.2 (nerdctl-full in /usr/local) | 2.3 LTS | one install, from Docker's apt repo |
| Cilium (+ Hubble UI) | 1.19.1 (0.13.3) | 1.20.2 (0.13.6) | 1.19.8 → 1.20.2 |
| Istio | 1.25.2 (EOL, unsupported on k8s 1.34) | 1.31.1 | canary 1.25 → 1.27 → 1.29 → 1.31 |
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

New playbooks (ops): `upgrade-kubeadm.yml` (one minor per run, `kubeadm upgrade apply`, kubelet/kubectl, drain-free
single node), `upgrade-containerd.yml`, Cilium/Istio/Gateway-API steps as variables of the existing playbooks.

## Production rollout (after all tests pass and approval)

Waves in this order, one step at a time, each verified before the next:

0. Backups (Velero all namespaces, CNPG backup + `pg_dumpall` to the Pi, Scylla Manager backup, etcd snapshot) and the
   defects above.
1. Patches: apt-cacher-ng from CI (defect 9), cert-manager 1.20.4, CNPG 1.30.1, Velero 1.18.4 + plugin 1.14.4, versitygw 1.8.0, local-path 0.0.37,
   kube-prometheus-stack 91.8.2, Alertmanager, blackbox, Grafana 12.4.12, Mimir 2.17.11, Fluent Bit 4.2.8,
   Argo CD 3.3.14.
2. Platform: Cilium 1.19.8 → k8s 1.34.12 → containerd 2.3 → k8s 1.35 → Cilium 1.20.2 → Gateway API v1.5 → Istio
   1.27 / 1.29 / 1.31 → k8s 1.36.5.
3. Operators and data: External Secrets 2.11, Argo CD 3.5, cert-manager 1.21, Strimzi 1.2 + Kafka 4.3.1, Scylla
   operator + ScyllaDB + Manager, PostgreSQL 18, Valkey 9.1.
4. Observability majors: Grafana 13, Mimir 3.x, Tempo 3, Fluent Bit 5, ClickHouse 25.8 → 26.8, SonarQube 26.9,
   Centrifugo 6.9.7.

Rules: one component per change; check its history and live effect first; stateful steps shown to the operator with
the exact change before they run.
