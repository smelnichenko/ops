# Plan 062: Vagrant test harness rework

## Status: TODO

## Context

Today's session added `test-vault-unseal.yml` to catch the vault-unseal
regressions. Attempting to run it end-to-end via
`task test:dual-pi-clean` surfaced 9 pre-existing bugs in the harness —
9 fixed this session, at least 2 more uncovered but not fixed:

- `setup-patroni.yml` creates `replicator` role after Pi1-failure
  simulation, but postgres socket is briefly missing during the
  simulation (local socket removed when patroni restarts). Task needs
  retry-until or to delegate to a pi whose postgres is up.
- Forgejo pi2 health check fails during `setup-vault-pi.yml` — probably
  ordering: vault restart on pi1 triggers something that takes Forgejo
  on pi2 down while we're checking it.

Beyond those two, there's a structural concern: the chain is a
9-playbook sequence where any one failure aborts the run, and several
playbooks were written as one-time migrations (e.g. migrate-vault-consul
was literally "migrate from raft to consul storage", yet is the only
place that sets up vault-unseal.service).

The problem isn't this-or-that task — it's that the test harness has
accumulated entropy since its last known-green run.

## Fixes committed this session

See commits between `43a227f` and `c49d0ad` on ops main. Net: 9
idempotency + ordering + concurrency fixes in playbooks that are
supposed to be idempotent and vagrant-safe.

## Remaining work (new plan — do separately)

1. **Reproduce the two known bugs** above in isolation.
2. **Untangle `migrate-vault-consul.yml`**: split into two files —
   `setup-vault-consul-backend.yml` (idempotent, always-run, creates
   vault+vault-unseal units with consul storage) and
   `migrate-vault-raft-to-consul.yml` (one-time, archived).
3. **Test-dual-pi needs a static pre-condition check** at the start:
   verify postgres sockets on both pis before starting the Pi1-failure
   simulation. Currently implicit assumption that fails intermittently.
4. **Chain test**: run `task test:dual-pi-clean` fresh (destroy + up)
   and iterate until green. Expect 2–5 more surface bugs before
   reaching the new `test-vault-unseal` assertion block.
5. **Update doc**: `ops/CLAUDE.md` and any "how to test" docs to
   reflect the canonical test command (`test:dual-pi-clean` covers
   dual-pi + vault-unseal).

## Effort estimate

½ – 1 day for a dedicated pass. Much faster than the interleaved
approach I took today, because each fix can be tested directly without
re-running the full chain (use `ansible-playbook --limit pi1 --tags X`).

## Verification

- `task test:dual-pi-clean` exits 0
- Output shows both `test-dual-pi` and `test-vault-unseal` PLAY RECAPs
  with `failed=0`
- `vault-unseal` test specifically asserts vault sealed=false within
  90s of simulated cold start — the regression it's meant to catch.

## Deferred from plan 061

This plan supersedes the "run test:vault-unseal against Vagrant"
follow-up item in plan 061.
