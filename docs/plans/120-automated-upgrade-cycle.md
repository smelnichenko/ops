# Plan 120 — the automated upgrade cycle

Status: **DECIDED, NOT BUILT** - the review answered 2026-11-14 (below). Built once plan 119's wave 1 has gone
through by hand (steps 1-3 live 2026-11-14; the cycle automates a run already seen to work). Plan 117 shipped.

## Decisions (operator, 2026-11-13)

- An agent runs the whole cycle: find the upgrades, prepare them as git changes, prove them on the Vagrant copy, apply
  them to production - **minors and majors, the node and the Pis included**.
- **Patches and minors apply directly** after a green proof, a notification after each.
- **Majors: a veto notice first** - what, the proof's results, when it applies - **24 h** to say no; applied if nothing
  is heard.
- Delivery through Argo CD: one infra and one platform branch per unit, as plan 119; what Argo cannot carry (node,
  Cilium, Argo CD itself, Gateway API CRDs, the Pis) through ops version vars and their `deploy:*` tasks.
- Vault needs no new access: each Pi unseals its own Vault already; `deploy:vault:upgrade` runs as by hand.

## Parts

**1. Renovate CLI - finds the upgrades, opens the PRs** (chosen over Updatecli, Dependabot, Argo CD Image Updater,
Flux image automation, Keel, Kargo: the only one with native Forgejo, every version source here, and grouping;
comparison 2026-11-13). Runs as a Woodpecker cron in ops (`.woodpecker/renovate.yaml`), image pinned exactly, against
`schnappy/infra`, `schnappy/platform`, `schnappy/ops`; the existing `renovate-bot` account and secrets
(docs/renovate-setup.md). Shared preset:
- `automerge: false` (the cycle merges, not Renovate), `dependencyDashboardApproval: false`, `minimumReleaseAge: 3 days`,
  `separateMinorPatch: true`, `separateMajorMinor: true`; first-party images (`git.pmon.dev/*`) off.
- Units, as branch names shared across the repos (one `test:copy:change` per unit): `renovate/wave-patches`; minor
  groups `istio` (the three Argo apps + ops `istio_version` + Gateway API), `observability`, `data-operators` (Strimzi
  + Kafka, Scylla), `argocd`, `pi-services`; each major its own branch.
- Custom managers: annotated Ansible vars (`# renovate: datasource=... depName=...` above each version var - Cilium,
  cert-manager, chart versions, Kubernetes, containerd.io via Docker's apt repo, Keycloak, Caddy, versitygw, Patroni
  via PyPI, Forgejo via forgejo-releases, Vault/Consul via GitHub releases); CNPG `imageName: tag@sha256:digest`;
  a post-upgrade script (`deploy/ansible/scripts/renovate-checksums.sh`, the only allowed command) that rewrites the
  per-arch sha256 maps from each release's own checksums.
- Not seen by Renovate, covered beside it: Debian host packages (an `apt_info.py` node_exporter textfile collector on
  ten and the Pis + an alert, and an apt-upgrade playbook the cycle runs as a unit), the Pis' drift from their pins
  (`task test:copy:inventory`), `argocd_image_pins` (by hand), deprecated APIs before a Kubernetes minor (Pluto on the
  rendered charts, in CI).

**2. The upgrade runner - proves and applies** (on the workstation: the copy needs ~25 GB and libvirt; nowhere else).
A systemd user timer (nightly, outside 02:00-03:00 and Sunday's 03:00-04:15 backup windows) runs a deterministic
driver, `scripts/upgrade-cycle.sh`; no CI agent on the workstation (a Woodpecker agent there would give any pipeline a
shell on it). Each night, one unit:
1. **Pick**: the next open Renovate unit in order - wave-patches, then minor groups, then one major whose 24 h notice
   has run out unvetoed. Paused when an `upgrades-paused` label is on ops' dashboard issue (the kill switch).
2. **Prove**: the copy lock; `test:copy:build` (from main = production), `test:copy:change` with the unit's infra and
   platform branches, `test:copy:playbook` for each ops part the unit moves (Kubernetes → upgrade-kubeadm.yml,
   containerd → upgrade-containerd.yml, a Pi service → its upgrade playbook, Cilium → its playbook); every check.
   Then the unit's diff gets a full review (the review agents, as by hand). The results go on the PRs.
3. **Fix**: a failed proof calls the Claude agent (headless, a skill of its own) to diagnose and push a fix commit to
   the unit's branches (labelled `stop-updating` so Renovate leaves them), then proves again - once. Still red: labelled
   `upgrade-blocked`, reported, the next unit next night.
4. **Gate**: patches and minors go on. A major gets its notice (PR comment + notification) and waits 24 h; a `veto`
   label or comment stops it for good.
5. **Back up** before any one-way change (below) - taken and its restore proven on the copy in step 2.
6. **Apply**: merge the infra/platform PRs (the bot through Forgejo's API, never an admin account), Argo syncs; the ops
   part merged and its PRODUCTION task run non-interactively (`task --yes deploy:...`), the Pis one at a time, the
   VIP's last.
7. **Verify**: Argo settled on the merge, `check:production:data`, a Velero backup from the schedule
   (`deploy:backup`), no critical alert for an hour. Red: a reversible change is reverted (a revert PR, merged, Argo
   syncs) and reported; a one-way change pages the operator with its backup and restore steps - never undone blind.
8. **Record**: the run (unit, proof, review, apply, verify) committed to ops (`docs/upgrades/<date>.md`) and sent as a
   notification; `task test:copy:inventory` read again so the next copy is built to the new production.

**3. One-way changes and their backups.** One-way: Kubernetes (kubeadm does not downgrade, patches included),
containerd, database majors and format changes (Postgres majors, ScyllaDB release lines, ClickHouse compatibility,
Kafka metadata, Strimzi CRD conversions), Vault/Consul majors (storage), Forgejo majors (migrations), Grafana majors.
Each takes its stores' backup first: Postgres (a CNPG base backup - `deploy:postgres:base-backup`), ScyllaDB (Scylla
Manager - `check:production:scylla-backup`), Kafka, ClickHouse, Grafana, OpenSearch, etcd (none today: plan 100's
Wave 0 backups - `upgrade-backup.yml` and its rehearsal, in git history before plan 117 - come back as the pre-change
backup, each store's restore proven on the copy), the Pis (Consul snapshot, Forgejo's own pg_dump, Patroni's base
backup - their upgrade playbooks take them).

## Guardrails

One unit per night, one production apply per day; the copy lock (one copy run at a time); production touched only
through Taskfile tasks and merges by the bot; no force-sync of root, no prune; a run that cannot finish (the
workstation off, the copy not building) changes nothing in production and says so; the kill switch above.

## Rollout of this plan

1. Renovate in lookup mode (`RENOVATE_DRY_RUN=lookup`) until its log reproduces plan 119's tables.
2. Renovate opening PRs; the runner proving them, applying nothing, a week (shadow).
3. Patches and minors applied automatically.
4. Majors with the 24 h notice; the pre-change backups proven first.
Each step reviewed before the next.

## The operator's review (answered 2026-11-14)

1. **Notifications: e-mail to one address - the single admin's, sent as Alertmanager sends** (operator: "just to single
   admin email", "like alertmanager does"): the runner posts each notice to Alertmanager's API as an alert of its own
   (`alertname=UpgradeCycle`, its kind and unit as labels, the text as annotations), and Alertmanager's existing route
   and e-mail receiver deliver it - one mail path, one address (`alertEmailTo`), its silences. Never a list, a user, a
   channel. One exception: a one-way change's failure may have broken the cluster Alertmanager runs in - that page
   falls back to the same sender (Alertmanager's SMTP settings) to the same address directly. Sent only for what is
   acted on or was asked for: a major's veto notice (24 h), a unit blocked (red after its fix) or a one-way change's
   failure (page, with its backup and restore steps), and - asked 2026-11-13 - each patch/minor applied. A night with
   no unit sends nothing (the no-unattended-mail rule: no scheduled noise).
2. **The agent: the current Claude account** - the same Claude Code login the operator's sessions use, headless on the
   workstation. **The fix step (part 2, step 3) is required**: a red proof is diagnosed and fixed, then proven again;
   only a second red blocks the unit. Its permissions are set for this job explicitly: in an interactive session the
   auto mode refused `deploy:kubeadm:upgrade` (2026-11-14) - the runner's settings allow exactly the cycle's tasks
   (`task --yes deploy:<the unit's>`, the bot's merges) and nothing else.
3. **The workstation runs it; the operator stops the radar for it** ("I will stop radar again"): the copy needs ~24.6 GB
   of the 30 GB (VMs 22.5 GB + the guard's 2 GB start reserve), and on 2026-11-14 it fit only with radar-live.service
   stopped. The runner cannot stop it (a system unit, sudo asks a password): a unit's night begins only once the copy
   guard admits the build; while it does not, the run waits within the night's window and, unadmitted, e-mails that the
   unit waits for the radar to stop - and after the copy is destroyed, that the radar may start again. (A polkit rule
   letting the runner stop and start radar-live itself would remove the step - the operator's call, not assumed.)
4. **No batches: one unit a night** (a wave can take a week of nights).

## What wave 1 by hand taught the cycle (2026-11-14)

- A change to the test namespace cannot be proven on the copy (its mirror refuses what the overlay drops): the cycle
  splits it onto a branch of its own, merged first - the test environment its own proof (plan 100's order) - then the
  production unit.
- The Pis' Debian unit runs `deploy:pi-packages:upgrade -- -e pi_packages_turns=1` one night (the Pi without the VIP,
  its new kernel and bootloader soaking) and the second Pi the next; a preview (`-- --check`, fresh lists) goes in the
  proof's record.
- After each apply: `task test:copy:inventory` and the ops defaults that restate production (defaults-follow-production:
  cert_manager_version, k8s_package_version, cilium_version, ...) moved in the same ops commit - by hand on 2026-11-14,
  the next build's own inventory check failed otherwise.
- Before a Kubernetes apply, a fresh etcd snapshot (a Job from the etcd-backup CronJob) - upgrade-kubeadm takes none.
- The full review found real defects after a green copy run (Nexus double start, a failed run's reboot skipped): the
  review stays a gate, and its fixes are proven on the copy again before the apply.
