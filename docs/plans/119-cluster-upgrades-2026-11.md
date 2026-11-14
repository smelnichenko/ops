# Plan 119 — cluster and Pi upgrades, November 2026

Status: **PLANNED** (operator 2026-11-13: "check if we can upgrade our cluster parts like we did recently" → report →
"yes, please"). Plan 117's Vagrant proof and its Velero change are green and live (2026-11-14): wave 1 next.

## Context

Production's versions read 2026-11-13 18:15 (`task test:copy:inventory` → `tests/ansible/copy/prod-inventory.txt`),
upstream's the same evening (Helm repos, GitHub/Codeberg releases, dl.k8s.io, Docker Hub tags). Plan 100 brought the
cluster current in October; since then patches and minors piled up, the Pis' plan 101 upgrades never ran (they run
Forgejo 15.0.3, Patroni 4.1.0, Vault 1.21.3 while the playbooks pin 15.0.9, 4.1.5, 1.21.4), and the Pis carry Debian
security updates (pi1 46 packages, pi2 20: OpenSSL, curl, expat, liblzma, HAProxy).

How each change is proven (plan 117): built from main = production, then the change applied to the copy as production
gets it - an infra/platform branch with `task test:copy:change INFRA_REF= PLATFORM_REF=`, a node or Pi playbook with
`task test:copy:playbook PLAYBOOK= ARGS=` - every check green, then production. Each item's release notes read before
its branch: breaking changes, order between components, the one-way ones named.

## Delivery (operator 2026-11-13: "upgrade with argocd, tested in vagrant, hopefully in less than 62 branches")

- **One wave = one infra branch + one platform branch** carrying every Argo-managed bump of the wave, proven together by
  one `task test:copy:change INFRA_REF=upgrade/wave-N PLATFORM_REF=upgrade/wave-N` (every check green), merged - Argo
  upgrades production. A wave is split only when its copy run fails and the cause is not plain. Waves 1-2: ~4 branches.
- **What Argo cannot carry** - what exists before Argo or outside the cluster: Kubernetes and containerd on the node,
  Cilium (the network Argo runs on), Argo CD itself (`setup-argocd.yml`), the Gateway API CRDs (`setup-kubeadm.yml`),
  the Pis' services. Their bumps are ops version vars, proven with `task test:copy:playbook` in the same copy run as
  the wave's branches, then their PRODUCTION `deploy:*` tasks. The ops defaults that restate Argo's charts
  (`defaults-follow-production`) move in the same ops commit as the wave's merge.
- Renovate (proposed, not decided) could open each wave's grouped PRs by itself; the proof and the merge stay ours.

## Wave 1 — patches, the Pis' security updates, plan 101's pending upgrades

**1a. Cluster (one infra + one platform branch, one `test:copy:change`)**

| Component | From → to | Where |
|---|---|---|
| cert-manager | v1.21.2 → v1.21.3 | infra `argocd/apps/cert-manager.yaml`; ops `setup-kubeadm.yml` `cert_manager_version` (defaults-follow-production) |
| Velero chart | 12.2.0 → 12.2.5 (Velero 1.18.4, pinned in values) | infra `argocd/apps/velero.yaml` |
| ClickHouse (LTS line) | 26.8.15 → 26.8.34 | infra + platform `schnappy-observability/values.yaml` |
| ScyllaDB (2026.1 line) | 2026.1.14 → 2026.1.15 | infra `schnappy-production-data/values.yaml` (image and `version`) |
| Mimir / Tempo | 3.2.1 → 3.2.5 / 3.1.0 → 3.1.1 | infra `schnappy-observability/values.yaml` |
| Valkey | 9.1.2 → 9.1.3 | infra `schnappy-production-data`, platform `schnappy-data` values |
| pushgateway / blackbox exporter | 1.11.3 → 1.11.4 / 0.29.0 → 0.29.1 | platform `schnappy-observability/values.yaml` (blackbox: located with the branch) |

**1b. Node (ops playbooks, `test:copy:playbook`, then production's tasks)**

| Component | From → to | How |
|---|---|---|
| Kubernetes | 1.36.5 → 1.36.6 | `upgrade-kubeadm.yml` (`RESTARTS_EXPECTED=true`), then `deploy:kubeadm:upgrade`; `k8s_package_version` follows |
| Cilium | 1.20.2 → 1.20.4 | `setup-kubeadm.yml` `cilium_version` (Helm on ten, not Argo) - its upgrade path read first |

**1c. Pis (playbooks on the copy's Pis, then production's tasks, one Pi service at a time)**

| Component | From → to | How |
|---|---|---|
| Debian security updates | pi1 46, pi2 20 packages | an apt upgrade playbook (one Pi at a time, the VIP's last) - made with this wave if none exists. The copy's Pis start at production's versions only for the five inventoried packages (plan 117): the proof exercises those and the playbook, not every package's restart |
| Forgejo | 15.0.3 → 15.0.11 (the 15 line) | `upgrade-forgejo.yml` / `deploy:forgejo:upgrade` (vars pin moved to 15.0.11) |
| Patroni | 4.1.0 → 4.1.5 | `upgrade-patroni.yml` / `deploy:patroni:upgrade` |
| Vault | 1.21.3 → 1.21.4 (the last free 1.21: 1.21.5+ are Enterprise only) | `upgrade-vault.yml` / `deploy:vault:upgrade` |

Then `task test:copy:inventory` (production read again) - the copy is built to the new versions from then on.

**Wave 1 release notes (read 2026-11-13; the full notes with sources in this plan's research record):**
- Order: pushgateway/blackbox → Tempo → cert-manager → Valkey → Velero chart (its 12.2.3 adds an env var: the Velero
  pod restarts - outside the backup windows) → Mimir → ClickHouse → ScyllaDB; node: Kubernetes 1.36.6, then Cilium
  1.20.4 (straight past 1.20.3: its BackendTLSPolicy regression; the pre-flight image pull first); Pis one at a time,
  the one without the VIP first: Debian updates + reboot → Patroni → Vault → Forgejo.
- cert-manager 1.21.3: a CRD field added in a patch (`status.acme.ari.certID`) - CRDs with the controller (the chart's).
- ClickHouse 26.8.34: outbound TLS hostname verification is OFF by default again (26.8.26) - set
  `openSSL.client.extendedVerification=true` to keep today's; privilege tightenings (CREATE TABLE AS, MODIFY QUERY,
  CREATE OR REPLACE needs DROP) - the copy's checks exercise ours.
- Mimir 3.2.5: stored tenant Alertmanager configs validated on load - ours is the separate Prometheus Alertmanager.
- Kubernetes 1.36.6: `kubeadm upgrade apply` re-applies addons - upgrade-kubeadm.yml skips kube-proxy from its config
  file (an old kubeadm bug ignored `skipPhases` there: the copy run checks no kube-proxy appears); certificates renewed;
  no downgrade - an etcd snapshot first.
- Cilium 1.20.4: CIDR groups with 0.0.0.0/0 now select (none here), a CNP with nodeSelector marked invalid.
- Forgejo 15.0.11: a ONE-WAY migration (15.0.7 - a 15.0.3 binary refuses the database after it): its pg_dump first
  (upgrade-forgejo.yml takes one), `forgejo doctor check --all` after; REVERSE_PROXY_TRUSTED_PROXIES advisory checked.
- Patroni 4.1.5: fixes `systemctl reload` hanging on trixie's systemd; `patroni_postgres_timeline` becomes a gauge
  (alerts using rate() on it to check).
- Vault 1.21.4: restarts sealed - each Pi's own unseal brings it back; a Consul snapshot first.
- Debian: openssl/haproxy restart their users (haproxy's restart may move the VIP), a kernel update needs a reboot;
  postgresql-17 17.11 on the Pis carries the same reindex notes as 17.12/18.7 - checked with the Pis' wave.

**Wave 1 as built (2026-11-14):**
- 1a: infra `upgrade/wave-1` 6a91c972, platform `upgrade/wave-1` 7abd7a1 - the table's versions, the test namespace's
  Valkey and ScyllaDB with production's, platform CI's ClickHouse image with the chart's. ClickHouse stays at 26.8.34.13:
  26.8.35/36 are Docker tags without a GitHub release, 26.8.37 came out the same morning (notes unread). pushgateway
  1.11.4 (1.11.5: a tag, no release). ClickHouse 26.8.26's TLS default touches nothing: the server opens no TLS of its
  own (its Kafka engine inside the mesh) - no setting added. Velero chart 12.2.0 -> 12.2.5 diffed: POD_NAME (the
  server restarts), caCertRef, a node-agent lifecycle key fixed - none of our values changes meaning; the 1.18.4 pin stays.
- 1b: `deploy:kubeadm:upgrade -- -e k8s_upgrade_to=1.36.6` (RESTARTS_EXPECTED on the copy); Cilium by a new
  `deploy:cilium:upgrade -- -e cilium_version=1.20.4` (setup-kubeadm.yml `--tags cilium`, its tagged pre-pull first -
  plan 100's runner, which passed the tags, is gone). The defaults (`k8s_package_version`, `cilium_version`) move with
  the inventory read after production: the copy is built from them.
- 1c: a new `upgrade-pi-packages.yml` (`deploy:pi-packages:upgrade`, `-- --check` previews): one Pi at a time, the VIP's
  holder last; before anything Patroni healthy and not paused, both Vaults unsealed, Consul with a loss to spare, Gluster
  mounted and healed, each Pi's running enabled services recorded (keepalived's Nexus aside); each Pi with anything to
  upgrade hands over first - Patroni switchover, Vault step-down, the VIP (keepalived stopped, Nexus answering on the
  other) - then `apt-get upgrade --with-new-pkgs` (holds kept, no removal, confold), Consul's raft leadership off it,
  no tier-0 backup, the reboot, and every check back. No Patroni pause (the leader is on the other Pi with its own
  Consul agent; paused, the shutdown would kill a Postgres Patroni left running). Its reads in
  `playbooks/scripts/pi-packages.py` (harness `pi-packages`, each judgement broken and caught); setup-consul's Vault
  step-down, Consul handover and tier-0 lock check moved into task files both share (harness `consul-handover`
  follows the includes).
- The Pis read 2026-11-14 (reads only): pi1 plans 46 upgraded + 8 new (a 6.18.60 kernel, rpi-eeprom, openjdk-21,
  OpenSSL, curl, postgresql-17 17.11 -> 17.12, haproxy deb13u4), pi2 20 (its package lists older: the playbook updates
  them first). PostgreSQL 17.12's reindex notes: no bpchar btree or gist_trgm_ops index in postgres/keycloak/forgejo,
  no incremental backups (summarize_wal off) - nothing to do. Debian's postgresql-17 scripts beside Patroni: prerm stops
  `postgresql@17-*` (inactive - Patroni runs Postgres), postinst starts `postgresql` (disabled) - harmless. rpi-eeprom
  may stage a bootloader update at the boot; it applies at the reboot after.
- Forgejo's pin 15.0.11, its sha256 from the release on code.forgejo.org and codeberg.org (the same).
- The copy run: `test:copy:build`; `test:copy:change INFRA_REF=upgrade/wave-1 PLATFORM_REF=upgrade/wave-1`;
  `test:copy:playbook` for upgrade-kubeadm.yml (`-e k8s_upgrade_to=1.36.6`, RESTARTS_EXPECTED=true), setup-kubeadm.yml
  (`--tags cilium -e cilium_version=1.20.4`), upgrade-pi-packages.yml, upgrade-patroni.yml, upgrade-vault.yml
  (`-e @vars/vault.yml -e @vars/vault-vagrant.yml` - amd64), upgrade-forgejo.yml - each with every check.

**Out of wave 1** (found in the notes): PostgreSQL 18.7 - CNPG publishes no bullseye image for it; moving means the
trixie (or bookworm) image, a glibc change (collations: reindex, `REFRESH COLLATION VERSION`) and 18.7's own reindex
steps (unbounded `bpchar` btree, pg_trgm GiST) - its own step, on its own run. containerd 2.3.7 - Docker publishes
none for trixie (2.3.6, then 2.4.x): containerd.io stays held at 2.3.6 (it is: `apt-mark` hold), 2.4 with wave 3.
Vault: 1.21 gets no more free fixes - Vault 2.x moves up in wave 3.

## Wave 2 — minors (one or two per copy run)

| Component | From → to | Note |
|---|---|---|
| Istio + Gateway API | 1.31.1 → 1.32.0; 1.5.1 → 1.7.0 | together (Istio 1.32's supported Gateway API); sidecars restart (`deploy:mesh:restart`) |
| Argo CD | 3.5.4 (chart 10.9.7) → 3.6.1 (chart 10.18.0) | alone; ops `setup-argocd.yml` default + `argocd_image_pins` (argocd-versions harness) |
| External Secrets | 2.12.0 → 2.15.0 | CRDs |
| kube-prometheus-stack | 91.8.2 → 93.3.0 | two chart majors: CRDs, Prometheus 3.15 → 3.16, Alertmanager 0.34 → 0.35 |
| Strimzi + Kafka | 1.2.0 → 1.3.1; Kafka 4.3.1 → 4.3.2 | Kafka 4.3.2 needs Strimzi 1.3 (1.2.0 supports 4.2.x, 4.3.0-4.3.1) |
| Scylla operator / Manager | 1.22 → 1.23 / 3.12.1 → 3.13.0 | scylla-backup-check on the copy |
| Grafana / Fluent Bit / Centrifugo | 13.2.3 → 13.3.1 / 5.1.3 → 5.2.0 / 6.9.7 → 6.10.3 | |
| Keycloak / versitygw / Caddy / Nexus (Pis) | 26.5.7 → 26.8.2 / 1.8.0 → 1.11.0 / 2.10.0 → 2.11.9 / 3.90.1 → 3.98.1 | Pi playbooks |
| SonarQube | 26.9 → 26.11 | not in the copy (left out): its own care |

## Wave 3 — majors and one-way changes (each its own plan)

Kubernetes 1.37 (one minor; Cilium's and Istio's support first), containerd 2.4, Vault 2.x, Consul 2.x (plan 101
phase 2's path: snapshots before each hop), Forgejo 16/17, ScyllaDB 2026.3 (one-way), k6 2.x (the smoke scripts).
A one-way change to a store without a backup of its own (Kafka, ClickHouse, Grafana, OpenSearch - Velero holds no
volume data) names its backup first (plan 117, Open).

## Current, nothing to do

CNPG 1.30.1, Velero 1.18.4, OpenSearch 3.9.0, local-path 0.0.37, kube-state-metrics 2.20.0, Woodpecker 3.20.1,
metrics-server 0.9.0 (0.9.1 out, no chart release yet). kagent: disabled, left alone.

## Order

1. ~~Plan 117's proof and its Velero change green, pushed, production's Velero backup proven.~~ Done 2026-11-14.
2. Wave 1: release notes; 1a branches → `test:copy:change` → merge; 1b playbooks → `test:copy:playbook` → production
   tasks; 1c the same, one Pi service at a time; inventory read again.
3. Wave 2, then wave 3's plans - each the same way.
