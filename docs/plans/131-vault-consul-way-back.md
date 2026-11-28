# Plan 131 - Vault's and Consul's way back, rehearsed on the copy (minimum plan)

**Status:** the operator answered the question (2026-11-27: keep the root token). Vault's part (items 1-2 and the root
token) merged (ops #84) and **rehearsed green on the copy (2026-11-28)**: `task test:copy:vault-way-back` took Vault
1.21.4 to 2.2.2 and back - the secret written before there, the one written after gone, unsealed on both Pis, one active,
External Secrets reading it (the first run, 2026-11-27, stopped at its first check on a list-typed fail_msg - ops #87);
its store's `missing` cleared. Consul's part (items 3-4) merged (ops #88) and **rehearsed green on the copy in both modes
(2026-11-28)**: `task test:copy:consul-way-back` took Consul 1.20.6 to 2.1.0 and back - from the running cluster's KV (the
marker written after the upgrade kept) and from the pre-upgrade snapshot (it gone), the same primary on the same timeline,
Patroni not paused, Vault unsealed with one active (the first run stopped on the copy's absent tier-0 timers - ops #90);
its store's `missing` cleared.

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
3. **Consul's way back - `restore-consul.yml`**: the three servers a new cluster on the kept old binary, Consul's keys
   carried over - by default the running cluster's whole KV, exported once Vault is stopped and imported (nothing in it
   lost); the pre-upgrade snapshot only for a cluster that cannot be read (the operator's choice, 2026-11-27). Patroni
   stopped while paused around it and started again unpaused, Vault started and unsealed. Refused unless the unit is
   reverted, the way back confirmed, the old binary everywhere (section "Consul's part" below).
4. **Its copy check - `consul-way-back-check.yml`** (`task test:copy:consul-way-back MODE=current|snapshot`, both run):
   a KV marker before, the upgrade, a marker after and a Patroni switchover, the way back; the old version on all three
   servers, the same primary on the same timeline, the database writable, Vault unsealed, the first marker there and the
   second kept (current) or gone (snapshot).
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

## Consul's part - built (2026-11-27), reworked after its review

`upgrade-consul.yml` leaves a whole-state snapshot on pi1 (now fetched to the controller too) and the old binary on all
three servers. An old binary may not read a raft data directory the new one wrote, so `restore-consul.yml` starts the
servers again as a new cluster on the old binary and loads Consul's keys into it from one of two sources:
- **current (the default, the operator's choice 2026-11-27):** the running cluster's whole KV, exported once Vault is
  stopped (nothing of Vault's written after it) and before Patroni's pause (no pause or marker in it), checked, fetched
  to the controller, imported and compared key by key. Nothing in the KV is lost; the catalog and the sessions start
  afresh (agents register again, locks free themselves). Confirmed with `-e confirm=consul-<pin>`.
- **snapshot (`-e consul_restore_from=snapshot`):** the pre-upgrade snapshot, for a cluster that cannot be read -
  everything written since is lost (the end lists what to run again). Confirmed by the snapshot's file name; an earlier
  snapshot named with `-e consul_restore_snapshot` (a retried upgrade names its snapshot by the version pi1 ran then).

Refused before anything stops: a server left out, the unit not reverted (a snapshot not of the pin), not confirmed, the
kept binary gone or another version, a snapshot that binary cannot inspect, nothing newer running to go back from (the
current source), no leader to export through, a reboot scheduled on a server, Postgres on the Pis not one primary and a
running replica (read from Postgres itself), the admin password not working on the primary's own port, Patroni paused by
someone else, a tier-0 backup or a restore check running.

What the review (2026-11-27) found and the build now does:
- **patroni-pause.py takes `consul-way-back`** - it refused any run name but its three callers, so every way back would
  have failed at its second step; the marker harness now runs restore-consul's own pause.
- **Patroni stopped, not only paused, and off at a boot.** A pause does not survive the load (the keys loaded hold
  none), and a Pi booting mid-way would start Patroni on an empty DCS, where the replica could promote. Patroni is
  paused (this run's marker), stopped on both Pis and disabled - paused, it leaves Postgres running; HAProxy marks the
  primary down without Patroni's REST, so the database is away through it until Patroni is back.
- **Patroni's stale keys deleted** after the load - its leader, member and failover keys (sessions that died with the old
  cluster; a leader key naming the other Pi would demote the running primary) - and the keys' initialize compared with
  the system id Postgres runs before Patroni starts; Patroni on the primary's Pi first, holding the leader key, then the
  replica; not paused and no marker after.
- **Vault before Patroni** (it needs nothing of it), exactly one active read on both Pis together and again until one
  says so (a carried lock frees in under a minute), its root token proven.
- **The node-id and gossip keyring carried over, and required.** Each data directory is set aside whole; the new one
  gets the node's node-id (a new id would clash with the catalog) and keyring (an empty keyring reads consul.hcl's key).
- **A run again takes up where one stopped.** A record on each server (`/var/lib/consul/restore-consul.state`) names
  the source, the state before's directory and the version left: a run again loads the same source (never exports the
  new, empty cluster), moves a failed run's new directory aside as a failed one (the state before is always the
  recorded one), skips the stops and the load once its record says the keys were loaded, takes up a pause it made
  itself, and starts the locked jobs' timers by whether they are enabled. The rescue names the state before and the
  way forward in full (the directory and the new binary back, the pause resumed and its marker deleted, Vault enabled,
  the timers), and never deploy:vault-pi meanwhile.
- **The locked jobs' timers stopped first, their jobs read again** (one could start between a read and the stop).

Its copy check (`tests/ansible/copy/consul-way-back-check.yml`, `task test:copy:consul-way-back MODE=current|snapshot`):
a KV marker before, `upgrade-consul.yml` to the target, a marker after and a Patroni switchover (the snapshot's leader key
then names the Pi no longer the primary), the way back; then the pin on all three, three voters and a leader, the
before-marker there with its value and the after-marker kept (current) or gone (snapshot), the same primary on the same
timeline (no failover, no promotion), Patroni healthy and not paused with no marker, the database writable through each
Pi's HAProxy, Vault unsealed with one active, the locked jobs' timers back, External Secrets reading it after a forced
sync. The consul store's `missing` clears only when both modes pass.

## Could add later (not needed to clear the gates)

- Consul's way back with Consul down (no quorum): the pause needs Consul answering, so today that case is refused before
  anything stops and is a hand job.

- A rehearsal of the likelier trigger: upgrade-vault.yml failing in the active's turn (a 2.x standby beside a 1.21
  active), then restore-vault.yml - the review's suggestion.

The rest of the vault-2.x review (plan 101 holds the list): the rehearsal starting from 1.21.4, the unit's copy step
running the rehearsal's outside checks (two-actives sampler, leader moved, sealed-node refusal), a step-down and a KV
read plus a Kubernetes-auth login on the new active before the old node stops, a failed run never leaving a newer
standby beside an older active, a Vault probe in keepalived's check, SonarQube's KV PATCH and hvac's list and delete on
2.x in the copy, free space before the download, vault-backup.sh, the stale comments.
