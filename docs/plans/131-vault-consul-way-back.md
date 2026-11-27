# Plan 131 - Vault's and Consul's way back, rehearsed on the copy (minimum plan)

**Status:** draft, 2026-11-27 - for the operator's OK before any build.

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

## Could add later (not needed to clear the gates)

The rest of the vault-2.x review (plan 101 holds the list): the rehearsal starting from 1.21.4, the unit's copy step
running the rehearsal's outside checks (two-actives sampler, leader moved, sealed-node refusal), a step-down and a KV
read plus a Kubernetes-auth login on the new active before the old node stops, a failed run never leaving a newer
standby beside an older active, a Vault probe in keepalived's check, SonarQube's KV PATCH and hvac's list and delete on
2.x in the copy, free space before the download, vault-backup.sh, the stale comments.
