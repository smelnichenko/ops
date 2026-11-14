# Plan 117 — the Vagrant copy of production, without upgrade steps

**Status:** DONE 2026-11-14. The copy built from main = production green (ninth build, every check, 09:01-10:03); the Velero change green on it (10:11) and live in production (infra bb738de4, platform ff5e99c, synced 10:17): a daily backup from its schedule Completed with 4299 items and no volume read in 9 s, a weekly one 6609 items in 18 s (was ~70 min); no Velero alert. ops 6eeb9a72. The copy destroyed after.

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

## The copy beside the radar station (2026-11-13 night, operator: "yes" to a smaller copy with a guard)

The third build's VMs held 25 GB of the workstation's 30 while another session's work ran: the host swapped 14 GB, the
Argo settle timed out, and the radar station on the same host died (22:17, restarted 22:17:30). Now:
- **VMs 22 GB**: the node 18 GB (was 20), each Pi 2 GB (was 2.5; the Pi stack uses ~1.3).
- **Requests sized to the 18 GB node** (~17.4 GiB allocatable): ~14.8 GiB in all, computed from production's running
  pods with the overlay's values - the apps 384 Mi, masi-browser 256 Mi, Kafka 384 Mi, OpenSearch 512 Mi with a 512m heap
  (its fixed heap the one real-memory saving: a derived index), every sidecar 96 Mi and istiod 256 Mi (new overlay:
  `istio/istiod-values.vagrant.yaml`), Prometheus 256 Mi (`prometheus/values.vagrant.yaml`). Postgres stays 512 Mi
  (CNPG's shared_buffers floor).
- **`scripts/copy-host-guard.sh`**: the Vagrantfile hands every vagrant command's arguments to it - `up`/`reload`/
  `resume` refused unless the host has the starting VMs' memory (the Vagrantfile's sizes, those not running already)
  plus 2 GB available since 2026-11-14 17:00 (operator: "lower vagrant copy requirements by little"; the trip at
  2 GB available unchanged - the kubeadm guest itself used 16.95 of its 17.99 GB, no VM shrinks); 2.5 GB before (3 GB at first: it refused every start once the desktop and the radar held ~4.5 GB - 25.4-25.6
  of 25.6 GB needed, 2026-11-14 08:27-09:00; fully resident the green builds ran at ~4 GB available); a detached watcher (also started by every copy task working on the VMs) powers off the biggest
  running VM when the host's available memory is under 2 GB on two polls 5 s apart - the run fails, said in
  `.copy/host-guard.log`, the station keeps its memory. Every Vagrant suite here is guarded, not only the copy.
- The unit runner fences `virsh` too; CI's image carries ruby (the hook is tested by loading the Vagrantfile).
- **The JVMs' heaps too** (the fourth build, 2026-11-14 00:00-01:12): requests alone did not fit - the JVMs grew to
  production's heap caps (masi 3g x2, monitor 2g x2, chat/chess/admin 1g), the pods held 16.9 of the node's 18 GB
  (kube-apiserver 2.15 GB, OpenSearch 1.47, chat 1.37, admin 1.35, masi 1.21, Argo's controller 1.06), the kernel
  OOM-killed JVMs, load 350, kube-apiserver calls timed out and the Argo settle failed at 40 min. The host was fine
  throughout (4.3 GB available, the guard never tripped; the VMs 22.2 GB resident). Now the test environment's heaps
  (monitor 1g, chat/chess/admin/masi 512m - schnappy-test-apps runs the same apps on them), masi one replica (as
  there), OpenSearch 512m; Kafka's 1 GB is the chart's own.
- **The fifth build** (01:19-02:32): every pod ready at the end, the node still full - pods 16.7 of 18 GB, 1.2 GB
  available, two JVMs OOM-killed during the settle (kube-apiserver 1.9 GB, monitor's two pods 1.3 + 1.0 GB, masi 1.2 on
  its 512m heap, OpenSearch 0.95). Monitor one replica now too (~1.1 GB each). The Pis use ~1.15 of their 2 GB - no
  room to take there. The host: 5.7 GB available at the fullest, its swap 4 -> 7 GB, the guard never tripped.
- **And a real finding**: the apps' sync failed on `schnappy-production-masi-credentials` - production's Vault has
  `<prefix>/masi-credentials` (from its .env), the copy's none (its secrets file names no operator credential), and an
  ExternalSecret extracting a path that is not there fails. The copy now renders no such ExternalSecret
  (`masiService.credentials.existingSecret: ""`): masi without the operator's credentials, each optional in its
  deployment - never a placeholder (it would log in to the real Gmail with a wrong password).
- **The sixth build** (02:37-03:25): settled - every app green, no OOM kill, the node at 16.4 of 18 GB with 1.6 GB
  available (kube-apiserver 1.85 GB, monitor 1.46, masi 1.32, OpenSearch 0.93). It failed next, in the survival seed:
  plan 117's rewrite had dropped the ClickHouse compatibility and users the old task passed it, so the seed expected
  none and production's `compatibility 25.8` failed it. Now `scripts/clickhouse-expected.sh` reads them from a platform
  ref's clickhouse-users.xml for both the seed (main) and the verify (the ref under test); the seed stops if the lookup
  fails (inside a here-string its failure went unseen - proven in go-task's shell). The other arguments the old tasks
  passed (argo-settled's allow_out_of_sync/restart_step, barman-check's pg_major, restore-check's restore_*,
  production-state's upgrade_from) are read by nothing left.
- **The seventh build** (03:43-04:34): settled, seeded, the k6 smoke passed, the node 16.9 of 18 GB with 1.1 GB
  available, no OOM kill - and the inventory failed on the Pis' Debian packages: the copy had haproxy deb13u4 and
  postgresql-17 17.12, production deb13u3 and 17.11 (its pending security updates, plan 119's wave 1c). The copy
  installs whatever the archive serves; production runs the level it last took. Now `scripts/pi-versions.py` records
  the Debian packages the Pis report (version-inventory-pi.sh's own list) as `pi_apt_versions`, and
  `tests/ansible/copy/pi-apt-versions.yml` (in `_copy:base` after the Pi stack, Gluster and keepalived, before the cold
  boot) moves each installed one to production's version with `scripts/pi-apt-pin.sh` - from the archive while it
  still has it, else from snapshot.debian.org at that version's first publication. Run on the seventh build's Pis:
  both moved from the archive (it still serves the point release beside the security update), the inventories then
  matched (238 lines, 19 allowed missing). Only the Debian packages the inventory lists (postgresql-17, pgbouncer,
  haproxy, glusterfs-server, keepalived - and their same-source siblings) start where production is: the Pis' other
  packages (OpenSSL, curl, expat, liblzma... - plan 119's wave 1c names 46 on pi1, 20 on pi2) are the archive's newest
  on the copy, so an apt upgrade proven on it exercises those five, not the rest (Open).
- **The eighth build: ALL GREEN** (build 04:56-05:48, every check 05:48-05:55; the node ~1 GB available at the end, no
  OOM kill; the host at least ~4.1 GB available, the guard never tripped). Every serial check said its verdict: base
  backup, 3 certificates renewed, Postgres restored into a side cluster, a Velero volume restored, the daily schedule's
  backup Completed (pods backed up, 6 of 6 volume backups), Scylla Manager backed up, the sweeper.
- **The Velero change's first run** (05:56-06:36): every app green on the change's commits, but the settle waited 40 min
  on one failed pod - `kube-system/restore-check-age`, which reads each Pi's restore-check report from the Pi store. The
  copy's Pis do not run production's Pi restore check (its containers are bounded at 1.5 GB each; the copy's 2 GB Pis
  have ~0.8 GB free), so the job fails at every :50 of every third hour - the build's checks passed only because none
  fell inside them. The copy's settle now takes `--failing-cronjobs` from `tests/ansible/copy/copy-failing-cronjobs.txt`
  (each CronJob with its reason): their failed runs are not waited for, a run still going is, every other failed Job
  fails the settle as before. The check itself keeps its own Vagrant test (task test:pi-restore-check).

## Third full review (2026-11-14 morning) - what changed

Correctness, security, architecture, platform reliability, concurrency, test quality (reverts in a copy of the tree),
SonarQube (ops' red gate: three issues of argocd-repos.py on main's last analysis, fixed on this branch already).
- **Host guard rewritten** (all three of correctness, security, concurrency found it - the concurrency pass Critical):
  a `watch` trusted a watcher about to end (3 empty polls after its VMs went), so a `vagrant up` right after a
  `destroy` - every build's first provisioning - could run unwatched. Now the watcher holds `.copy/host-guard.alive` for
  its life, ends only after a whole grace with no VM, and decides to end under the callers' lock, re-reading whether
  a caller relied on it since it went quiet. Started under `env -i` (production's `.env` never in it), its start and
  end logged, `set +e` with explicit checks, the power-off before its record and a failed one said as such, a memory
  stall (PSI full over 25%) a second trip signal, the running VMs' untouched memory counted as promised, settings that
  are no number and a VM without a size refused, an option's value no machine name, `virsh` under a time limit and
  named by path in tests. The Vagrantfile holds one start at a time (`.copy/vagrant-start.lock`) and refuses only a
  start it cannot judge - halt and destroy always go on.
- **The copy's node VM was destroyed at 07:50** (`virsh` "shut off (destroyed)") while the review's reverts ran; the
  guard recorded no trip, and the kernel and libvirt logs are root's, so the cause is not proven. What allowed a test
  to reach real libvirt is fixed: a harness's watcher found `virsh` on PATH, so one outliving its stub directory
  reached the real one - now its `virsh` is named by path (gone means failing), and the harness stops every watcher of
  its directory before removing it. My revert batch's cleanup (`pkill -f .../copy-host-guard.sh _loop`) also stopped
  the real watcher at ~08:05 - a pattern matching more than the test's own.
- **Unattended upgrades**: the box carries unattended-upgrades, production's hosts do not (ten and pi1 read 11-14) -
  it would have taken production's pending security updates mid-run and undone the Pis' pins. Purged in the
  Vagrantfile's OS upgrade; listed in both inventories (a difference would show).
- **pi-apt-pin**: the packages built with a pinned one move with it (postgresql-client-17, libpq5); `sid` among the
  snapshot's suites (a version that reached trixie from unstable); the snapshot origin pinned at 100 (dependencies stay
  the archive's); `--no-remove`; signed by Debian's keyring; a killed run's source and pin cleared first; one Pi at a
  time (the HA pair's services restart).
- **The settle**: a container OOM-killed during the wait fails it, named (the near-full node hid them);
  `--failing-cronjobs` quoted.
- **backup-check** reads pods left out from `excludedNamespaceScopedResources` too, and runs for the weekly schedule
  as well (`test:copy:check`), which it checks only with pods left out (cluster-wide: `*`).
- **clickhouse-expected.sh and pi-apt-pin.sh compare in the C locale**: the new harness found `usér` passing the users
  check (bash's `[A-Za-z]` under UTF-8).
- **Velero (infra)**: the weekly holds the cluster's own resources again (`includeClusterResources: true` - any
  excluded namespace had dropped every cluster-scoped kind since 2026-10-11); the server's default reads no volume
  either (`defaultVolumesToFsBackup: false`: ad-hoc backups); the comments say which stores have a backup of their own
  and which none, and what a restore brings back.
- **Velero alerts (platform)**: `VeleroDailyBackupMissing` at 26 h (holds any failed, partial, refused or restart-killed
  daily until a success); a failure counter born at 1 on a new Velero pod caught; `VeleroBackupFailing` an ad-hoc
  backup's only (no double alert); the runbooks rewritten for the counter rule's one-hour window.

### What the copy does not prove (it differs from production here, each covered elsewhere or open)

- JVM heaps (the test environment's, not production's: an OOM of production's heap against its limit cannot happen on
  the copy) - production's own alerts (JvmMemory) and the deploy's watch.
- masi and monitor at 1 replica: masi's multi-instance claims and its PDB, monitor's two-replica slot claims - the test
  environment runs monitor at 2; masi at 2 only in production.
- masi without the operator's credentials (no ExternalSecret): a credential path change - production only.
- The Pis' Debian packages beyond the five the inventory lists: the archive's newest on the copy.
- The Pis' restore check (its containers do not fit the 2 GB Pis): `restore-check-age` skipped by name; the check has
  its own Vagrant test (task test:pi-restore-check) - whether it still fits 2 GB Pis is Open.
- The memory picture: requests sit below real use (fixed heaps: Kafka 1 GiB on 384 Mi), so the scheduler does not
  protect the node; an OOM during the wait now fails the settle.

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
- **From the third review, not done here (decisions or new work):** the mirror refuses changes to keys the overlay
  sets (masi's heap, monitor's and masi's replicas): such a change cannot be proven on the copy - a mirror that
  rewrites only `-Xmx` in production's `javaOpts` would let it through; `seed-vault-secrets.yml` writing
  `<prefix>/masi-credentials` even with no key named (production's DR: a Vault re-seeded from an `.env` without
  `MASI_*` fails the apps' sync as the copy's did) - a production playbook change; CNPG Clusters restored by Velero onto
  empty volumes (the DR drill excludes them; production's schedules do not) and a drill restoring the schedules'
  manifests-only backups; one storage blip at 02:00 losing a day's daily backup (twice a day, or an alert on the
  storage location's status); `restore-check-age` exercised on the copy (seed the Pis' reports instead of skipping);
  a harness that checks the overlay's keys against the charts (needs the platform repo: at mirror time); pinning every
  Debian package of each Pi; `ops/.env` readable by the group (0664); Velero's store URL plain http on the LAN.
- **One-way changes to Kafka, ClickHouse, Grafana**: Wave 0 was their only pre-change backup; Velero holds no volume
  data. A one-way change to one of them needs its backup named in its own plan first.

