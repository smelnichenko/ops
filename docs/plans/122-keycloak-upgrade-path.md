# Plan 122 - Keycloak's upgrade path: restarted on a new version, proven on the copy, one-way

**Status:** parts 1-4 built 2026-11-26/27 (ops, stacked on the Keycloak unit split #78): the version-aware restart, the copy's proof, the dump before a version moves, the store taken by deploy:pi-services. Part 5 open: the full review, then the first real proof - the cycle proving renovate/keycloak-26.8 (26.5.7 -> 26.8.2) on the copy, before any production apply.

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
