# Plan 120 — the automated upgrade cycle

Status: **PROPOSED, for the operator's review** (2026-11-13). Nothing built yet; built after plan 117 ships and plan
119's wave 1 has gone through by hand once (the cycle automates a run already seen to work).

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

## For the operator's review

1. **Notification channel** for the notices and reports: e-mail, a push service (ntfy), a Forgejo issue? (Not a public
   Telegram channel.)
2. **The Claude agent's own access**: it runs unattended on the workstation with production-changing tasks - which
   account/API key, and is its fix step (3) wanted, or should a failed proof only report?
3. **The workstation as the runner**: it must be on at night; the copy takes ~25 GB of its 30 GB while the radar jar
   runs beside it.
4. **Cadence**: nightly units (a wave can take a week of nights), or weekly batches.
