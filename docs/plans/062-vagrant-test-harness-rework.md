# Plan 062: Rewrite Vagrant test harness as final-state, not migrations

## Status: DONE (2026-04-22)

## Context

The current Vagrant test chain is a sequence of historical migration
playbooks. `setup-vault-pi.yml` installs Vault with a **file** backend
(the raft-era setup), then `migrate-vault-consul.yml` migrates **both**
Pis to a Consul backend and — as a side effect — installs
`vault-unseal.service`. The `test-*.yml` playbooks `import_playbook` five
sibling setup playbooks and intermix deploy with assertions. Several
playbooks were written as one-time transitions, not idempotent
converge-to-state.

Running the full chain fresh (2026-04-21 session) surfaced 9 real bugs,
fixed in commits `43a227f` → `c49d0ad` on ops main (idempotency,
ordering, Patroni-leader discovery, etc.). At least 2 more remain
(postgres socket missing during Pi1-failure simulation; Forgejo pi2
health check fails during vault restart). Every turn-of-the-crank
uncovers another.

The root problem isn't this-or-that task — it's that the harness has
accumulated entropy since its last known-green run. Each playbook
assumes a specific pre-migration state.

**Goal:** rewrite the harness to describe the **current production
final state** directly. Each service has one idempotent playbook; tests
verify, don't deploy; the chain is a clean two-phase (deploy → assert).
`task test:dual-pi-clean` goes from `vagrant destroy` to green without
any fix-then-retry dance.

## User decisions (captured before execution)

- `setup-vault.yml` (in-cluster Vault): **delete**. There is no `vault`
  namespace in production; ESO talks to Pi Vault directly.
- Pi Vault unseal mechanism: **keep Shamir + `vault-unseal.service`**
  (plan 061 Sub-plan A — cloud-KMS auto-unseal — was declined).

## Scope

### 1. Consolidate vault playbooks into one final-state file

Rewrite `deploy/ansible/playbooks/setup-vault-pi.yml` from scratch to
produce the current production state in a single idempotent pass, on
**both** Pis:

- vault user/group + binary on pi1 and pi2
- vault.hcl with **Consul** backend directly (skip file/raft
  intermediate)
- `vault.service` systemd unit, `Wants=consul.service` (soft, not hard
  — see commit `aec9422`)
- Init on pi1 only if uninitialized (`vault operator init -status` rc=2)
- Distribute Shamir keys pi1 → pi2 via `fetch` + `copy`
- Unseal both nodes on first run
- KV v2 + ESO policy + Kubernetes auth (lifted in from
  `migrate-vault-consul.yml`)
- `/etc/vault-unseal/unseal.sh` (Consul-leader wait + rc=2 sealed check,
  lifted from today's fixes `4773821`, `1964e7f`) +
  `vault-unseal.service`
- Existing good bits: health-check cron, offsite-backup dir,
  git-mirror bare repo, daily data-backup cron

Drops from current `setup-vault-pi.yml`:
- File storage backend phases
- Transit engine + autounseal-token generation (only the dead cluster
  vault consumed it)
- `vars/vault-pi-runtime.yml` output

### 2. Delete dead vault scaffolding

- `playbooks/setup-vault.yml` — deploys Vault inside k8s; no consumer
- `playbooks/migrate-vault-consul.yml` — everything it did is now in
  the consolidated setup-vault-pi.yml
- `vars/vault-pi-runtime.yml` — only consumer was setup-vault.yml
- `vars/vault-k3s-init.json` — k3s-era recovery keys for the dead
  cluster vault
- Taskfile tasks: `deploy:vault`, `deploy:vault-consul`, `test:vault`,
  `test:eso` (the ESO test was built around the in-k8s vault stack)
- Any docstring cross-references in sibling playbooks

### 3. Rewrite `tests/ansible/test-dual-pi.yml` as assertions-only

Drop every `import_playbook` + the in-line "reconfigure services for
Patroni multi-host" block (another historical migration step). The
resulting playbook does only:

- `systemctl is-active` on all expected services (forgejo, keycloak,
  minio, patroni, consul, keepalived, glusterd, haproxy, vault,
  vault-unseal)
- HTTP health checks (endpoints unchanged from today)
- Consul cluster member count assertion (≥ 2)
- Patroni replication: write on leader, read on replica via local
  socket (uses the leader-discovery fact from commit `c49d0ad`)
- GlusterFS replication
- Keepalived VIP present + Forgejo-via-VIP responds
- Pi-1 failure simulation + Pi-2 takeover + recovery (this is a
  scenario test, legitimately lives here)
- Final cleanup

### 4. Rewrite the Taskfile test chain

Replace the messy `test:dual-pi-clean` with a clean two-phase chain:

```
test:dual-pi-clean:
  - vagrant destroy -f
  - vagrant up
  # deploy (each idempotent, final-state)
  - setup-consul.yml
  - setup-pi-services.yml
  - setup-patroni.yml
  - setup-vault-pi.yml        # rewritten
  - setup-gluster.yml
  - setup-keepalived.yml
  # assert
  - tests/test-dual-pi.yml
  - tests/test-vault-unseal.yml
```

Keep a symmetric `test:dual-pi` (no destroy) for fast iteration during
development.

## Files modified

| Path | Change |
|---|---|
| `deploy/ansible/playbooks/setup-vault-pi.yml` | rewrite from scratch (consolidated final-state) |
| `deploy/ansible/playbooks/migrate-vault-consul.yml` | delete |
| `deploy/ansible/playbooks/setup-vault.yml` | delete |
| `deploy/ansible/vars/vault-pi-runtime.yml` | delete |
| `deploy/ansible/vars/vault-k3s-init.json` | delete |
| `tests/ansible/test-dual-pi.yml` | rewrite as assertions-only |
| `Taskfile.yml` | rewrite `test:dual-pi*`, drop `deploy:vault`, `deploy:vault-consul`, `test:vault`, `test:eso` |
| sibling playbooks (`setup-argocd.yml`, `setup-velero.yml`, `setup-woodpecker.yml`) | scrub docstring prereqs referencing deleted playbooks |
| `ops/CLAUDE.md`, `ops/README.md`, `deploy/README.md`, `docs/DR-PROCEDURE.md` | refresh deploy-chain references |

## Reuses from the 2026-04-21 session

All already committed to ops main; the rewrite lifts them into the new
single-playbook shape rather than re-deriving:

- rc-based sealed check (`vault status` rc=2) — `4773821`
- Consul-leader wait in `unseal.sh` — `1964e7f`
- `Wants=consul.service` (soft) instead of `Requires=` — `aec9422`
- Patroni-leader discovery for post-init DB bootstrap — `c49d0ad`
- `/etc/minio` parent dir before env file — `764f072`
- Minio UID pre-stop on drift — `6a6ae63`
- `test-dual-pi` replication read over local socket — `43a227f`
- `migrate-vault-consul` idempotency fixes — `aac2baa` (whole playbook
  goes away; keep the key improvements inline in setup-vault-pi.yml)
- HAProxy Consul-DNS node discovery — `28f0f1b`

## Execution approach

Because each fix can be tested in isolation via
`ansible-playbook --limit pi1 --tags X`, the rewrite is faster than
today's interleaved debug-and-re-run:

1. Write new `setup-vault-pi.yml` (consolidated); dry-run against
   production with `--check --diff` to confirm it represents live state.
2. Apply live to one Pi (pi1) via `task deploy:pi-services` equivalent
   for vault; verify unchanged behavior.
3. Apply to the other Pi; run through a rolling restart.
4. Delete the dead playbooks + taskfile entries.
5. Rewrite `test-dual-pi.yml` (remove imports, keep assertions).
6. Run `task test:dual-pi-clean` end-to-end on a fresh Vagrant.
7. Iterate on any remaining Vagrant-specific drift.

## Effort estimate

½–1 day for the full pass.

## Verification

1. `cd /home/sm/src/ops && task test:dual-pi-clean` — ends with
   `failed=0` for every PLAY RECAP across the chain.
2. Output includes both assertion playbooks:
   - `test-dual-pi.yml` — all service + HA + failover scenarios green
   - `test-vault-unseal.yml` — vault unseals from cold start in ≤ 90s
     (catches the three vault-unseal regressions from 2026-04-20)
3. Dry-run against production:
   `venv/bin/ansible-playbook -i inventory/production.yml playbooks/setup-vault-pi.yml --check --diff`
   — expect zero changes; live state already matches.
4. Idempotency check: run `task test:dual-pi` twice back-to-back (no
   destroy); second run's deploy phase should be all `ok=…, changed=0`.

## Out of scope

- Swap Shamir for cloud-KMS auto-unseal (plan 061 sub-plan A, declined)
- Other `test-*.yml` playbooks (`test-grafana`, `test-failure-modes`)
  — touched only to the extent they reference deleted playbooks
- Production migration — production already matches the final state
  these playbooks will describe, per the 2026-04-20/21 live patching.

## Supersedes

- Plan 061 sub-plan B follow-up ("run test:vault-unseal in Vagrant")
- The 9 interim fixes will remain in git history as the step-stones
  that produced the knowledge captured in this plan.

## Execution notes (2026-04-22)

Beyond the scope outlined above, the rewrite surfaced latent bugs in
`setup-patroni.yml` that the migration-era chain had been papering
over. All fixes below are now in the consolidated playbook:

1. **Replicator role not created by Patroni bootstrap.** The patroni
   version we run ignores `bootstrap.users.replicator` — the non-leader
   Pi's `pg_basebackup` fails with `Role "replicator" does not exist`,
   and the data-dir wipes on each retry. Fix: explicit `CREATE ROLE
   replicator WITH REPLICATION LOGIN PASSWORD ...` on the discovered
   leader (not hardcoded pi1).

2. **Data-dir wipe wasn't gated.** `rm -rf /var/lib/postgresql/*/main/*`
   ran unconditionally, which would destroy a healthy cluster on the
   second playbook run. Gated on `patroni.service` not already being
   `active`.

3. **Data-dir path lookup was fragile.** `ls /var/lib/postgresql/*/main`
   fails after Patroni's "Removing data directory" during a failed
   bootstrap loop. Switched to computing the path from `pg_version`.

4. **Cluster-convergence wait.** Downstream playbooks (vault, gluster,
   keepalived) raced against a replica still doing `pg_basebackup`.
   Added a poll-until-all-members-streaming gate at the end of
   setup-patroni.

5. **Forgejo/Keycloak reconfigure needs HAProxy health first.** The old
   chain flipped these services from raw `localhost:5432` to HAProxy
   `localhost:5000` via an ad-hoc block in `test-dual-pi.yml` (migration
   smell). Moved to a dedicated final play in `setup-patroni.yml` that
   (a) waits for HAProxy's L7 `/primary` check to pass before (b)
   restarting Forgejo + Keycloak. Without the wait, Forgejo crash-loops
   during HAProxy's ~60–90s backend-discovery window.

6. **Test cleanup must route through HAProxy.** The failover scenario
   can leave pi1 as replica (read-only), so `test-dual-pi.yml`'s final
   `DROP TABLE` ran against pi1's local socket and hit "cannot execute
   in a read-only transaction". Routed it through `localhost:5000`.

7. **Taskfile needs `-e @vars/pi-services.yml` on setup-patroni.yml.**
   Without it, `kc_db_pw` is undefined and Patroni bootstraps the
   postgres superuser with `changeme` — but setup-pi-services already
   set the real password on raw Postgres, so Forgejo/Keycloak then
   can't authenticate after Patroni takes over.

## Verification result

`task test:dual-pi-clean` (fresh `vagrant destroy -f` → `vagrant up` →
full deploy chain → both assertion playbooks) ends with `failed=0` for
every PLAY RECAP. Specifically:

- deploy chain (consul, pi-services, patroni, vault-pi, gluster,
  keepalived) — all PLAY RECAPs green
- `test-dual-pi.yml` — all HA assertions pass, including Pi-1
  failure/takeover/recovery scenario with data catch-up
- `test-vault-unseal.yml` — pi1 vault unsealed from cold start in <90s
