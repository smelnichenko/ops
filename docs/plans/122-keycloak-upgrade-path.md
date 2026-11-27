# Plan 122 - Keycloak's upgrade path: restarted on a new version, proven on the copy, one-way

**Status:** the first build (parts 1-4 below, 2026-11-26/27) was refused by its review and replaced - see "Rework after the review of 2026-11-27" at the end: upgrade-keycloak.yml (vars/keycloak.yml, the dump first, every Pi stopped, the VIP's first), no version move in setup-pi-services or keycloak-restart, restore-keycloak.yml and its rehearsal (task test:copy:keycloak-way-back: a real upgrade, then the restore). Parts 1-4 are kept as the record of what was refused. Open: the rehearsal passing on a real copy, then the store's `missing` cleared and #79 merged.

## Why

- **A new version never ran.** setup-pi-services.yml installs `keycloak_version` as a tarball and moves the
  `/opt/keycloak` symlink; the unit (`ExecStart=/opt/keycloak/bin/kc.sh`) and its secrets file stay the same, and
  `tasks/keycloak-restart.yml` restarts only when those files change. A version bump left the old Keycloak running,
  until the next reboot or crash started the new one and migrated its database unattended. (26.5.7 has been the
  version since the playbook was written: the gap never fired.)
- **No proof.** copy-unit.sh refuses setup-pi-services.yml (upgrade-renovate's NO_PROOF names Keycloak).
- **No backup in the cycle.** Keycloak's schema migrates on minors too (Liquibase; no downgrade). The Pis' daily
  backup holds `pg-keycloak.dump` (setup-pi-backups.yml), but nothing dumps it right before a version moves, and
  Keycloak is not in the one-way table (`scripts/upgrade-stores.json`).

## Parts

1. **The restart (drafted, tested).** `tasks/keycloak-restart.yml` reads the version Keycloak runs - the install its
   processes (kc.sh and its java child) hold open, as `scripts/version-inventory-pi.sh` reads it - against the one
   `/opt/keycloak` names. Another version (or two: a stale process) makes a restart due, as a changed file does; the
   three rolling restarts (a Pi not serving, the Pi without the VIP, the VIP's last) run on it. After them, the version
   running must be the one installed, or the run fails. Compared with the symlink rather than `keycloak_version`, so
   setup-patroni's import of the same tasks works unchanged. Harness: pi-restart-guard (the read with systemctl,
   pgrep and readlink stubbed; the due fact and the check as Ansible evaluates them; five mutations bite). The read
   ran on the copy's Pis (2026-11-18): 26.5.7 installed and running on both.
2. **The proof (drafted, tested).** copy-unit.sh's `KEYCLOAK = {keycloak_version, keycloak_sha256}`: production's
   setup-pi-services.yml on the copy's Pis, `-e @../../tests/ansible/copy/pi-versions.yml` first (production's Pi
   versions, read when the step runs) and the unit's version and hash after; any other value or task moved is refused.
   The copy's Keycloak database is the realm built from git (keycloak-realm.yml), not production's: the proof shows
   the new version starts, migrates a realistic schema and serves tokens (the smoke's k6-smoke token), not that
   production's data migrates.
3. **The dump before the version moves (built 2026-11-27).** In `tasks/keycloak-restart.yml`, before any restart, when a version
   change is due: `pg_dump` of `keycloak` through HAProxy (the primary) on the first Pi into `/var/backups/keycloak`,
   the last 3 kept - as upgrade-forgejo.yml dumps Forgejo's. Its restore: the dump into an emptied `keycloak`
   database with Keycloak stopped on both Pis, the old version's symlink back.
4. **Its own unit, one-way (built: #78 split it; the store taken_by deploy:pi-services 2026-11-27).** renovate/upgrade-cycle.json: `quay.io/keycloak/keycloak` out of the
   "pi services" group (as ScyllaDB's release lines left the data operators' unit), minors and majors labelled
   `one-way`; `scripts/upgrade-stores.json`: a `keycloak` store, `taken_by: ["deploy:pi-services"]` (part 3's dump
   is in that command), its units' regex and an example; upgrade-cycle.sh's apply: `test:copy:playbook
   PLAYBOOK=setup-pi-services.yml` -> `deploy:pi-services` (copy-unit's harness now fails a playbook a proof can run
   with no production command - it names setup-pi-services.yml until this lands).
5. **Review and a copy proof (open).** The full review; then a run on the copy with a real unit (26.5.7 -> 26.8.2:
   its tarball and `.asc` checked by scripts/renovate-checksums.py): both Pis restarted onto 26.8.2, the dump
   there, every check after green. Then the push, with the upgrade cycle idle.

## Rework after the review of 2026-11-27 (ops #79 held)

The review (platform reliability, test quality - real Ansible) refused parts 1-4 as built: the rolling restart ran
two Keycloak versions on one database while it migrated (Keycloak supports only stop-and-start across minors), a run
limited to one Pi left them split for good, the dump came after the symlink moved and was keyed on the processes, not
the database, the cycle's command (deploy:pi-services) ran far more than Keycloak, setup-patroni would have upgraded
Keycloak outside the cycle, the check after failed on a stopped Keycloak, the dump's check refused every ordinary run
(real Ansible: the skipped run_once result), and the store was cleared before any way back had run. The shape that
answers all of it is the one Forgejo and Consul already have:

1. **upgrade-keycloak.yml** (as upgrade-forgejo.yml): every Pi in the run, one installed version on all; the version
   each serves and the schema the database holds (migration_model); nothing to do when all serve the target; never a
   downgrade; a run cut short taken forward; the dump BEFORE anything changes - pg_dump through HAProxy on the first
   Pi, named for the database's version, written aside, checked, the newest pre-upgrade dump never rotated away, its
   path said; then Keycloak stopped on every Pi, the target's tarball checked and installed, the symlink moved
   (`ln -sfn`), the VIP's Pi started first (it migrates; Keycloak's database-lock wait), serving the target, then the
   other; every Pi serving the target.
2. **setup-pi-services.yml** installs Keycloak where none is (a fresh Pi, the copy's build); where one runs another
   version it refuses, naming `task deploy:keycloak:upgrade` - never a restart onto a new version.
   **tasks/keycloak-restart.yml** goes back to file changes alone, plus that refusal (setup-patroni imports it).
3. **The cycle:** copy-unit.sh proves keycloak_version/keycloak_sha256 with upgrade-keycloak.yml on the copy's Pis;
   upgrade-cycle.sh maps it to `deploy:keycloak:upgrade`; the store's backup is that command's (taken_by).
4. **The way back, scripted and rehearsed:** `restore-keycloak.yml` - Keycloak stopped on both Pis, the dump restored
   into an emptied keycloak database, the old version's symlink back, started, the old version serving; and a copy
   check (as scylla-way-back-check.yml): a marker before the upgrade there after the restore, one made after the
   upgrade gone. Only when it passes does the store's `missing` clear.
5. **Tests:** the playbooks' conditions as Ansible renders them, and a real-Ansible smoke of the run_once/hostvars
   paths (two local hosts, pg_dump stubbed); the review's revert table re-run.
   Done as two harnesses: `tests/ansible/unit/keycloak-upgrade` (the conditions rendered, the scripts run on stubs)
   and `tests/ansible/unit/keycloak-smoke` (both playbooks run by ansible-playbook against two stand-in Pis - what ran
   on which Pi, in which order, what a `when:` skipped; the test-quality pass's smoke, taken in). Its first runs found
   two faults now fixed: a clean stop resumed named its dump for no version (restore-keycloak.yml could not read it -
   the dump is named for the one install both Pis hold), and a schema read that failed still let pg_dump run (the
   dump now runs only once the schema is known).
