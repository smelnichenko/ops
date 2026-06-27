# Plan 075: Vault storage Consul → integrated Raft

## Status: DRAFT (2026-06-27)

## Context

The Pi Vault — the secret store behind every `ExternalSecret` in the cluster
(ESO reads it via VIP `192.168.11.5:8200`) — uses the **Consul storage backend**:

```hcl
# setup-vault-pi.yml ~L213
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}
```

That is the *legacy* backend. HashiCorp made **Integrated Storage (Raft)** the
recommended backend in Vault 1.4 (2020); the Consul backend is supported but not
where new deployments go. Moving Vault to Raft:

- **Removes Vault's dependency on Consul** — the single biggest Consul consumer.
  After the MinIO→versitygw migration ([[project_pi_backup_store_versitygw]],
  Plan 074) dropped the consul-lock, Vault + Patroni are Consul's two remaining
  load-bearing users. This decouples Vault.
- **Enables native `vault operator raft snapshot save`** — a real, consistent
  Vault backup (Plan 071-B wanted this; the current "tar the Consul KV" path is
  not a proper Vault backup).
- Is **step 1 of the broader Consul retirement** (Patroni DCS + HAProxy
  service-discovery remain — separate, on hold).

### Current state (verified from `setup-vault-pi.yml`)

| Aspect | Today |
|---|---|
| Nodes | **2** — pi1 (`.4`) + pi2 (`.6`), `hosts: pis` |
| Storage **and HA** | `storage "consul"` (Consul provides both the data store and the HA lock) |
| Seal / unseal | **Shamir** (`KEY1` + `KEY2`); a `vault-unseal.service` holds the keys and auto-unseals. **No** transit/KMS auto-seal. |
| Listener | TLS on `[::]:8200`, certs in `/etc/vault.d/tls/` |
| Addrs | `api_addr https://<ip>:8200`, `cluster_addr https://<ip>:8201` |
| Fault tolerance today | A single Pi Vault can fail — the other stays active because Consul (3-node raft incl. `ten`) still has quorum and the shared `vault/` data. |

## The decisive design point — Raft needs an odd quorum

With Consul storage, HA quorum is **Consul's** (pi1+pi2+`ten` = 3-node raft), so
2 Vault nodes are fine. With **integrated Raft, the Vault nodes ARE the quorum.**
A 2-node Vault Raft has quorum 2 → **zero fault tolerance** (lose one node → no
leader → Vault sealed/unavailable on the survivor). That would be a *regression*
from today.

So Raft requires a **3rd Vault node**. The natural choice — mirroring Consul —
is **`ten` as the 3rd Vault Raft node** (pi1 + pi2 + `ten`):

- `ten` is x86 (its own Vault binary; fine — separate arch from the ARM Pis).
- **No new secret exposure:** `ten` already holds Vault's data today, because
  Consul's 3-node raft (incl. `ten`) stores the `vault/` KV. Vault-Raft-on-`ten`
  is the same data on the same box, just in Vault's store instead of Consul's.
- 3-node Vault Raft: quorum 2, tolerates any one node down — **same fault
  tolerance as today**, now without depending on Consul.

Rejected alternatives: **2-node Raft** (no fault tolerance — unacceptable for the
secret store); **single-node Raft** (no HA); **stay on Consul** (the status quo
this plan exists to change).

## Target architecture

- **3-node Vault Raft** on pi1 + pi2 + `ten`, `storage "raft"` with a local data
  dir (e.g. `/opt/vault/data`), per-node `node_id`, and `retry_join` stanzas to
  the other two peers (over the existing TLS cluster port `:8201`).
- **Unseal unchanged** — Shamir + the `vault-unseal.service` (the migration
  preserves the keyring; the same `KEY1`/`KEY2` unseal the Raft-backed Vault).
- **TLS, `api_addr`, `cluster_addr` unchanged.**
- **Autopilot** left at defaults (dead-server cleanup); optionally pin
  `cleanup_dead_servers`.
- **Scheduled `vault operator raft snapshot save`** → versitygw (`vault-snapshots`
  bucket), replacing the Consul-KV tar (delivers Plan 071-B).
- Consul keeps running (still Patroni's DCS + service discovery) — this plan does
  **not** remove Consul.

## Migration procedure (offline `vault operator migrate`)

`vault operator migrate` copies one backend to another with Vault **stopped** —
a brief planned downtime where ESO cannot refresh secrets (existing k8s Secrets
persist; only refreshes pause).

1. **Pre-flight / backup (reversible-by-design):**
   - Confirm the Shamir unseal keys (`KEY1`/`KEY2`) and the root token are in
     hand.
   - **Consul snapshot** (`consul snapshot save`) — captures the `vault/` KV =
     the rollback copy. Do **not** delete the Consul `vault/` data until Raft is
     verified.
   - Take a `consul kv export vault/` as a second copy.
2. **Stop Vault** on pi1, pi2 (and confirm sealed/stopped).
3. **Migrate on pi1** — write `migrate.hcl`:
   ```hcl
   storage_source "consul" { address = "127.0.0.1:8500"  path = "vault/" }
   storage_destination "raft" { path = "/opt/vault/data"  node_id = "pi1" }
   ```
   `vault operator migrate -config=migrate.hcl` → writes the Raft data dir.
4. **Reconfigure** Vault config on all 3 nodes to `storage "raft"` (data dir,
   node_id, `retry_join` to the peers). Add the Vault role to `ten`.
5. **Start pi1** (single-node Raft), unseal (auto-unseal service / Shamir).
6. **Join pi2 + `ten`** — `vault operator raft join https://192.168.11.4:8200`,
   then unseal each; they replicate the data from pi1 over Raft.
7. **Verify** — `vault operator raft list-peers` shows 3 voters; ESO
   `ExternalSecret`s refresh; a representative secret read works through the VIP;
   `vault status` shows `Storage Type: raft` on all nodes.
8. **Cut snapshots** to versitygw; once green for a bake-in period, decommission
   the Consul `vault/` data (or leave it inert).

## Testing (Vagrant)

The `ops/Vagrantfile` harness already deploys Vault via `setup-vault-pi.yml`
(pi1/pi2). For the 3-node test, add `ten`/kubeadm as the 3rd Vault node.
Cases:
- Run the full Consul→Raft migration; assert `Storage Type: raft`, 3 peers, and
  a known secret survives the migration byte-for-byte.
- **Kill one node** → Vault stays unsealed + serving on the majority (the whole
  point — must NOT regress vs today).
- **Unclean restart** of a node → it rejoins Raft and catches up.
- A `raft snapshot save` + `snapshot restore` round-trip.

## Risks & tradeoffs

- **This is the secret store — a botched migration loses every secret.** Mitigated
  by: backup-first (Consul snapshot + export kept until verified), the migration
  being **reversible** (revert config to `storage "consul"` and restart — the
  Consul data is untouched), and a full Vagrant rehearsal before prod.
- **Downtime window** — Vault is down during `migrate` + the joins. ESO refreshes
  pause; existing Secrets keep working. Schedule it.
- **`ten` joins the Vault quorum** — couples a Vault replica to the k8s node. No
  new exposure (Consul on `ten` already holds the data), but `ten` is now part of
  Vault's availability. A 3-node raft tolerates `ten` down (2/3).
- **Two raft clusters during the interim** — Vault-raft (new) + Consul-raft (still
  there for Patroni/DNS). More moving parts until Consul is fully retired; the
  end state (Consul gone) is simpler.
- **Unseal still Shamir** — this plan does not change the seal. A later
  improvement could move to a real auto-seal, but it's out of scope.

## Rollback

Vault config back to `storage "consul"`, restart Vault, unseal — it reads the
preserved Consul `vault/` data. Non-destructive as long as the Consul data isn't
deleted until Raft is signed off (step 8).

## Interaction with the Consul retirement

This is **step 1** of decoupling from Consul (Vault off Consul). After it, Consul
runs only for **Patroni's DCS** and **HAProxy service discovery**. Whether to go
further (Patroni → etcd/embedded-raft, HAProxy → static, then drop Consul) is a
separate decision, currently on hold. Vault → Raft stands on its own merits
(recommended backend + native snapshots) regardless of that.

## Out of scope

- Patroni DCS migration off Consul; HAProxy de-Consul; fully retiring Consul.
- Changing the Vault seal/unseal mechanism (stays Shamir + auto-unseal service).
- Pi Vault → cluster Vault (the in-cluster Vault was retired; Pi Vault stays).

## Open decisions

1. **`ten` as the 3rd Vault node** (recommended) vs accepting a non-HA Vault vs
   keeping Consul storage. Confirm `ten` can carry a Vault replica.
2. **Snapshot cadence + retention** to versitygw (e.g. daily, 30 d).
3. **The migration window** — Vault downtime is short but real.
