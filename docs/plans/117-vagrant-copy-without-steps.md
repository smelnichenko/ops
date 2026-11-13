# Plan 117 — the Vagrant copy of production, without upgrade steps

**Status:** decided 2026-11-13 (operator); implementation next, the Vagrant run at the end.

## Why

Plan 100's upgrade is done in production (all 62 steps, 00-61; Argo: 31 apps Synced on infra/platform `main`). Its
Vagrant harness still builds the copy as production stood on 2026-10-02 and replays the steps on it, and production's
own procedure (`deploy:upgrade:*`, the ledger on ten) still wants a step for every change. A Velero setting
(skip ephemeral volumes, after VeleroDailyBackupMissing on 2026-11-13) could be tested only by framing it as step 62.
Operator, 2026-11-13: "if the upgrade is complete, then why to run its tests?" — "update current vagrant test suites,
so upgrade step is gone and like we start with prod versions" — "plan it and test in vagrant at the end".

## Decisions (operator, 2026-11-13)

1. **No steps.** The copy is built from infra/platform `main` — production as it runs now, at production's versions.
2. **Production's upgrade procedure goes too**: `deploy:upgrade:*`, `scripts/upgrade-production.py` and what only it
   uses. The ledger ConfigMap `kube-system/upgrade-ledger` on ten stays until the operator OKs deleting it.
3. **A change is tested by applying it to a built copy**: build from `main` once, mirror the change's branches
   (`INFRA_REF`/`PLATFORM_REF`) into the copy's Forgejo, Argo syncs them as production's would, then **every check
   runs** — none is chosen per change.

## The model

| Task | What it does |
|---|---|
| `test:copy:inventory` | Reads production now (read-only: ten and both Pis, `version-inventory*.sh`) into `tests/ansible/copy/prod-inventory.txt` and the Pis' versions into `pi-versions.yml`. Run before a build when production changed. |
| `test:copy:build` | From nothing: VMs, the Pi stack at production's versions, kubeadm, then the Argo layer from `main` (or `INFRA_REF`/`PLATFORM_REF`), seeded data, the recorded scrape pools; ends with the inventory against production's. VMs stay up. |
| `test:copy:change INFRA_REF=… PLATFORM_REF=…` | On the built copy: mirror the branches, Argo settles on them, then `test:copy:check`. |
| `test:copy:check` | Every check, always: Argo settled, data, survival, storage, metrics, k6 smoke, production-data, isolation, barman base backup, Postgres recovery and Velero volume restore (restore-check), Velero backup from production's schedule (backup-check), Scylla Manager backup, certificate renewal (cert-check), the PR-env sweeper (sweeper-check), the inventory against production's (minus the change's own lines, which it prints). |
| `vagrant:destroy` | As today. |

`tests/ansible/upgrade/` becomes `tests/ansible/copy/` (`git mv`, paths updated).

## What goes

- **Steps:** `tests/ansible/upgrade/steps/` (62 files), `defaults-committed.txt`, `api-versions.txt`,
  `targets-allowed-missing.txt`, `prod-transient.txt`, `production-argocd-state.yml` (moot past step 31),
  `tempo-flush.yml`.
- **Scripts:** `upgrade-production.py` (its live inventory read moves to `test:copy:inventory` first),
  `upgrade-rules.py`, `upgrade-expected-inventory.py`, `upgrade-defaults.py`, `upgrade-merge-step.sh`,
  `upgrade-merge-order.py`, `argo-helm-diff.py`, `upgrade-full-steps.sh`, `upgrade-build-with-pin.sh`,
  `upgrade-step-playbooks.sh`, `upgrade-restack.py`, `upgrade-restack-in-place.sh`, `vagrant-image-digests.sh`,
  `vagrant-image-listing.sh`, `tempo-flush.py`, `check-mode-lint.py` (its only caller was the full run).
- **Taskfile:** `_upgrade:base` and `test:upgrade:*` (replaced by `test:copy:*`), `test:clickhouse-pin`,
  `test:upgrade:wave0`, every `deploy:upgrade:*`.
- **Wave 0** (the pre-step backup of stateful stores into the Pi store, production procedure's): `upgrade-backup.yml`
  and its tasks, `wave0-rehearsal.yml`, `tasks/wave0-pg-dump.yml`, `files/pg-dump-verify.py`, the inventory's
  `upgrade_backup_*` variables.
- **Production upgrade playbooks used only by it:** `upgrade-prepull.yml`, `tasks/image-store-room.yml`.
- **One-shot migrations already done in production:** `eso-helm-forget.yml` (step 44), `strimzi-v1-conversion.yml`
  (step 37).
- **`tests/clickhouse-pin/`** (steps 59/61's rollback pin).
- **Unit harnesses of only the above** (~45): argo-helm-diff, backup-window, build-with-pin, check-mode-lint,
  confirm-typeahead, finished-pods, full-run-proof-order, image-digests, k8s-holds-follow-production, plan-steps,
  prepull, production-argocd-state, production-state-gateway, production-state-gluster, proof-integrity,
  remote-timeouts, restack-own, runner-checks, runner-refusals, runner-review, scrape-pools-gone, step-abort-defaults,
  step-fence, step-host-recheck, step-lines, step-order, step-stamper, step-tags-same-on-copy, tempo-flush,
  tempo-flush-traces, upgrade-abort, upgrade-defaults, upgrade-ledger, upgrade-merged-steps, upgrade-merge-order,
  upgrade-merge-step, upgrade-proof-freeze, upgrade-restack, upgrade-resume, defaults-follow-inventory (+
  `defaults_baseline.py`), eso-helm-record, backup-parts, backup-space, scylla-snapshot-fresh,
  upgrade-backup-guards, wave0-guards, pg-dump-verify; waiter-kill's strimzi case.

**Kept** (reusable for the next version change, applied as a change on the copy): `upgrade-kubeadm.yml`,
`upgrade-containerd.yml`, `postgres-analyze.yml`, `restart-mesh-workloads.yml`, `acme-check.yml`, with their
harnesses.

## What is rewired

- **`production-state.yml`:** only what ten has that no repo creates (namespaces, the CNPG owner secret, the
  ServiceAccounts, the wildcard and its check). The pre-step put-backs (CNI/crictl unheld, Gateway API CRDs
  client-side, Keycloak's pre-step unit, Gluster before step 00) go — at production's state they are wrong.
- **`survival-check.yml`:** defaults are production's: ClickHouse compatibility 25.8, users `schnappy`.
- **`argo-settled.yml` / `files/argo-settled.py`:** no `--step`/`restart_step`; `expect_apps` records the copy's apps
  after the build and a change may add or remove apps — its own (named in the output) are allowed.
- **`restore-check.yml`:** the fresh-backup path only (no `restore_backup=wave0`, no `restore_server` undo).
- **`backup-check.yml`:** reads what the schedule leaves out: pods left out (production's since 2026-11-13) - no
  volume backup at all, the whole namespace's manifests backed up; pods backed up - every selected emptyDir Completed.
  An empty backup fails either way; the kopia epoch job runs only when a volume was copied.
- **`upgrade-step-checks.sh` → `copy-checks.sh`:** no step arguments.
- **`vagrant-gitops-mirror.py`, `vagrant-preload-*.sh`, `vagrant-smoke.sh`:** wording; floating digests no longer
  written for a proof.
- **`inventory/vagrant.yml`:** no baseline pins (`external_secrets_by_helm_override`,
  `kubelet_grace_in_kubelet_config_map`) — the playbooks' defaults are production's; no Wave 0 variables.
- **`pi-baseline.yml` → `pi-versions.yml`**, written by `test:copy:inventory` (2026-11-13: the file says Forgejo
  15.0.3 / Patroni 4.1.0 / Vault 1.21.3; the playbooks pin 15.0.9 / 4.1.5 / 1.21.4 — production is read, not assumed).
- **`vagrant-allowed-missing.txt`:** the left-outs at production's versions.
- **Harnesses with step wiring** (keep, rewire): argo-settled, argocd-versions, base-backup-major, bootstrap-vault-eso,
  argocd-reader, inventory-diff, keycloak-db-url, pi-restore-check, postgres-analyze, process-groups,
  production-data-check, restore-check-cleanup, side-cluster-delete, scylla-backup-check, sweeper-check, step-checks
  (→ copy-checks), versitygw-checksum.
- **Docs:** plan 100's status (done, harness retired by this plan), plan 101's Pi upgrade path (a change on the
  copy), DR-PROCEDURE's Wave 0 bucket line.

## Order

1. `test:copy:inventory` and production's inventory captured (read-only).
2. The tasks, the checks' rewiring, the deletions, the harnesses; `bash tests/ansible/unit/run.sh` green, ansible-lint
   green.
3. `backup-check.yml` reads what the schedule leaves out (the first change it must prove).
4. Full review (architecture, test-quality).
5. **Vagrant, at the end:** `test:copy:build` (from `main`) → `test:copy:check` green → `test:copy:change
   INFRA_REF=fix/velero-skip-ephemeral PLATFORM_REF=fix/velero-runbooks` green (backup-check: pods left out, no volume
   backup, the backup Completed with its items; restore-check still restores a volume) → `vagrant:destroy`.
6. Push ops; then the Velero change to infra/platform `main`, one on-demand backup on production must end Completed.

## Full review (2026-11-13) - what changed

Code review, architecture, platform reliability; every finding fixed but the ones named under Open.

- **A change's inventory is judged:** `test:copy:change` (and `test:copy:playbook`) record the copy's inventory before
  the change; after it `scripts/copy-change-inventory.sh` prints the change's own differences and fails on a
  difference the copy had before it too (a stale copy, a leftover). Was: printed, never judged.
- **`test:copy:check` on its own** checks the refs the copy runs (`.copy/copy-refs`), a change's as a change.
- **Restart history:** every settle labels its stage anew (`build-`/`change-`/`check-`/`playbook-<time>`); with the
  fixed `build`/`change` no crash loop was ever caught. `test:copy:check`'s settle is a stage.
- **Ops changes on the copy:** `test:copy:playbook PLAYBOOK= ARGS=` - the playbook behind the Vagrant guard, both
  isolations put back, settled, every check. **Production tasks** for the playbooks that lost `deploy:upgrade:*`:
  `deploy:kubeadm:upgrade`, `deploy:containerd:upgrade`, `deploy:mesh:restart`, `deploy:postgres:analyze`,
  `deploy:postgres:base-backup`, `check:production:data`, `check:production:acme`, `check:production:scylla-backup`.
- **Pis:** Consul, Keycloak and versitygw pinned to production's too (`scripts/pi-versions.py`, its own harness);
  `setup-consul` gets the pins.
- **Mirror:** the fixed sync waves gone (infra main holds them; they undid a change that moved one); a change touching
  what the overlay drops or replaces refused. The overlay read from `tests/ansible/upgrade` after the rename - fixed.
- **Allow-list by name** (` *`) for the left-outs production upgrades (Woodpecker, kagent, SonarQube, Nexus); `? ` for
  a Job's image production has only for a day.
- **`defaults-follow-production`**: the node defaults against production's inventory (the step-era guard's purpose).
- **Base guards:** a change's refs must contain `origin/main`; `test:copy:argo` checks main on its own run too.
- **Velero (infra, platform):** hostPath/local and unbound PVCs (pvcPhase Pending/Lost) skipped too - with a policy
  Velero resolves every PVC's PV and one it cannot find failed the backup; the comment and runbooks say Velero holds
  manifests only; the server's logs, not a node-agent's; FailedValidation rows. `deploy:backup` from the schedule.
- Sonar's open issues (argocd-repos.py: S3776, S5332) fixed.

## Second full review (2026-11-13 evening) - what changed

Correctness, security, architecture, platform reliability, test-quality (~120 reverts in a copy of the tree).

- **A change's inventory** is judged from the build's own (`.copy/vagrant-inventory-build.txt`): a difference the build
  had too fails (production moved since); the copy right after the change settled is kept, and what the checks change
  after it fails (a leftover); a comparison with no verdict fails. A change applied again needs no rebuild.
- **`.copy/copy-refs`** holds each ref with its commit, written before the change is applied; a build clears it; an
  applied playbook stays marked.
- **`test:copy:playbook`** runs under `env -i` (production's `.env` never reaches a playbook on the copy);
  `RESTARTS_EXPECTED=true` for kubeadm/containerd.
- **Mirror**: judged against `origin/main`, renames as both paths, and a values key the overlay sets refused.
- **One copy run at a time** (`scripts/copy-lock.sh`, the outermost go-task process holds it).
- **Pins**: caddy too; a reported version must be one; `stale`/`not-running`/`unknown` refused.
- **Harnesses**: copy tasks pinned whole (`copy-tasks/expected.json`), production-inventory, copy-lock, the pin wiring.
- **Velero alerts** (platform): `VeleroScheduledBackupFailed` read the last-status gauge, which Velero resets within a
  minute - it never fired; now the failure and validation counters. Runbooks name `backups.velero.io` (`backup` alone is
  CNPG's here).
- **The copy no longer fit the VM**: production grew (masi and monitor at 2 replicas, OpenSearch) - 25.9 GiB requested
  of 19.4 allocatable; Scylla and OpenSearch Pending held the data app's sync before its init-users hook, so every app's
  login failed. The overlay's requests sized to ~18 GiB (limits production's).
- process-groups: a process that ignored the TERM when it came (forked by a deaf job) and catches it later is sent it
  once - it was counted sent and KILLed at the grace with its handler never run.

## Open

- ~~The ledger ConfigMap `kube-system/upgrade-ledger` on ten~~: deleted 2026-11-13 18:2x with the operator's OK, its
  events saved first in `docs/plans/100-upgrade-ledger.txt`.

- process-groups' harness under all-core CPU load: one of its five failing cases is fixed (above); the other four
  (-n task scans, a session's check) to measure again under load once the Vagrant run is done.
- ~~Velero mechanism~~: decided 2026-11-13 (operator, "ok, go"): pods left out of both schedules
  (`excludedResources: [pods]`, `defaultVolumesToFsBackup: false`) instead of the resource policy - the volume backup
  runs only for a pod item, so none runs: no policy ConfigMap, no PV looked up per PVC (with a policy a PVC whose PV
  vanished mid-backup failed it); the weekly leaves `woodpecker` and `schnappy-pr-*` out too. Velero first on the copy
  (test:copy:change), production after. The charts' `backup.velero.io/backup-volumes` annotations (inert since) and
  Velero's node agent can go later in a window (removing the annotations restarts the data stores).
- **One-way changes to Kafka, ClickHouse, Grafana**: Wave 0 was their only pre-change backup; Velero holds no volume
  data. A one-way change to one of them needs its backup named in its own plan first.

