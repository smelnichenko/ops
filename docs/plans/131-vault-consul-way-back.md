# Plan 131 - Vault's and Consul's way back, rehearsed on the copy (minimum plan)

**Status:** the operator answered the question (2026-11-27: keep the root token) - building. Vault's part (items 1-2 and
the root token) on its own branch: restore-vault.yml, the copy check, upgrade-vault.yml's root-token check and its
backups fetched off the Pi, backup-vault-keys.yml requiring the token; its store's `missing` clears only once
`task test:copy:vault-way-back` passes. Consul's part (items 3-4) next.

## Why

`scripts/upgrade-stores.json` blocks Vault's and Consul's one-way units (`hashicorp-vault-2.x`, `hashicorp-consul-2.x`)
since ops #79: their entries claimed a way back that has never run. `upgrade-vault.yml` and `upgrade-consul.yml` take
the backups (a Consul snapshot, Vault's `vault/` export) and keep the old binary, but restoring from them is "by hand"
in both headers, and the Pi restore check only counts restored keys - no Vault or Consul ever starts on them.
HashiCorp supports no binary-only downgrade for either: the data must go back with the binary. Same rule as Keycloak
and ScyllaDB: a gap clears only when its way back has run green on the copy.

## Must fix (the minimum that can clear the two gates)

1. **Vault's way back - `restore-vault.yml`** (`task deploy:vault:way-back -- -e confirm=<export file>`): both Vaults
   stopped; `vault/` emptied and the pre-upgrade export imported (`consul kv delete -recurse vault/`, `consul kv import`)
   - Vault's keys alone, Patroni untouched; the kept old binary back on both Pis; started, unsealed by each Pi's own
   unseal script, one active. Refused unless the unit is reverted first (vars/vault.yml pins the export's version), the
   export is named, and the old binary is on every Pi. The backups fetched off the active Pi to the controller by
   `upgrade-vault.yml` before anything stops (the review's finding: they lived on one Pi's disk only).
2. **Its copy check - `tests/ansible/copy/vault-way-back-check.yml`** (`task test:copy:vault-way-back VAULT_TO=...`),
   as Keycloak's: a KV secret written before the upgrade, `upgrade-vault.yml` to the target, a second secret, the
   restore, then the old version serving, unsealed, one active, External Secrets reading through the VIP, the first
   secret there and the second gone; cleanup always.
3. **Consul's way back - `restore-consul.yml`**: Vault and Patroni stopped (Patroni paused first), the three servers
   stopped, the kept old binary back, started, three voters and a leader, `consul snapshot restore` of the pre-upgrade
   snapshot (the snapshot and the cluster on one version, as the restore needs), then Patroni resumed and Vault started
   and unsealed. Same refusals (unit reverted, snapshot named, old binary everywhere).
4. **Its copy check - `consul-way-back-check.yml`**: a KV marker before, the upgrade, a marker after, the restore; the
   old version on all three servers, Patroni's leader back and the database writable, Vault unsealed, the first marker
   there and the second gone.
5. **The table:** each store's `missing` cleared only by the commit that records its check's green copy run.

## Question for the operator before the build (one)

Vault 2.x needs a token for `sys/rekey` and `sys/generate-root` (HashiCorp's 2.0.0 notes). Today the root token is
kept as optional and the keys are said to recover Vault alone. Pick one before `vault-2.x` can go (not needed for the
way back itself):
- **(recommended)** keep the root token: `upgrade-vault.yml` refuses unless `vault token lookup` succeeds with it on
  each Pi, and backup-vault-keys.yml stores and checks it with the keys;
- or set `enable_unauthenticated_access = ["rekey", "generate-root"]` in vault.hcl (anyone who reaches the API can
  then submit key shares - HashiCorp calls it a last resort).

## Vault's part, after its review (2026-11-27)

The review found no Critical; its warnings fixed on the branch: vault/ as it stands set aside beside the export before
the delete (the way forward again); from the stop on, both units off at a boot, the kept binary back first, a rescue that
says where Vault was left and what to run (never deploy:vault-pi meanwhile - an empty vault/ reads as uninitialised and
its init would overwrite the keys); the root-token check reads the file on its own line (a failed read in a prefix
assignment fell through to the CLI's token helper) and requires a root token that never expires; the controller's
backups one directory per inventory (the copy's export never beside production's), 0700/0600; the end names what to run
again (deploy:ci-bot, deploy:argocd-reader, preview environments, External Secrets force-synced); the rehearsal reads the
secret's value back and has External Secrets sync through the VIP after the restore; setup-vault-pi's root-token purge
replaced by a refusal. Also: the kept binary's version and the export's seal config and keyring checked before the stop,
the export host's Consul leader asked, the import compared key by key, the newest export by name, the root token proven
on the restored keys.

## Consul's part - its design (next)

`upgrade-consul.yml` leaves a whole-state snapshot on pi1 and the old binary on all three servers. An old binary may not
read a raft data directory the new one wrote, and `consul snapshot restore` needs a cluster on the snapshot's version, so
the way back is: Patroni paused (scripts/patroni-pause.py, as setup-consul's restarts do), Vault stopped on both Pis;
the three servers stopped, their data directories moved aside (never deleted), the old binary back, a fresh cluster of
three (bootstrap_expect) with a leader, the snapshot restored, three voters healthy; Patroni resumed (its leader key as
the snapshot holds it - the rehearsal must show Patroni takes it back cleanly), Vault started and unsealed. Its copy check:
a KV marker and a Patroni-side write before, the upgrade, markers after, the restore; the old version on all three, the
database writable through its leader, Vault unsealed, the before-marker there and the after-marker gone.

## Could add later (not needed to clear the gates)

- A rehearsal of the likelier trigger: upgrade-vault.yml failing in the active's turn (a 2.x standby beside a 1.21
  active), then restore-vault.yml - the review's suggestion.

The rest of the vault-2.x review (plan 101 holds the list): the rehearsal starting from 1.21.4, the unit's copy step
running the rehearsal's outside checks (two-actives sampler, leader moved, sealed-node refusal), a step-down and a KV
read plus a Kubernetes-auth login on the new active before the old node stops, a failed run never leaving a newer
standby beside an older active, a Vault probe in keepalived's check, SonarQube's KV PATCH and hvac's list and delete on
2.x in the copy, free space before the download, vault-backup.sh, the stale comments.
