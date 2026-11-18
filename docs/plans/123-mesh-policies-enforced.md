# Plan 123 - every mesh policy enforced by a proxy

**Status:** 2026-11-18 - found, fixed in platform fix/mesh-hygiene (cede958, de8f102 and the review's follow-ups) and
infra fix/mesh-hygiene (7df3db7b); copy run 6 then production (the chain stopped for it); enforcement after a day.

## Why

A live audit (2026-11-18: pods each policy selects, per namespace, with a sidecar) found eight of the mesh's
AuthorizationPolicies and PeerAuthentications enforced by nothing:

- **postgres** selected `app.kubernetes.io/component=postgres`; CNPG labels its pods `component=database`. Production's
  and test's 5432 had no identity check - the NetworkPolicy alone (by labels).
- **Kafka's pair** (from before Strimzi), **Scylla's pair** (the operator's pods run without a sidecar), **SonarQube's
  old Postgres**, **ClickHouse** (runs in schnappy-infra, where no AuthorizationPolicy renders), **Elasticsearch**
  (gone), **Mimir** (no sidecar); Alertmanager's and s3gw's exceptions held in production and test for pods only
  schnappy-infra runs.

## What changes

1. postgres re-selected by `cnpg.io/cluster`: 5432 for the app services, the instances (replication) and the init-users
   Job (its own ServiceAccount now - it ran as `default`); 8000 from any source (the operator's status calls and the
   primary's liveness isolation check on the replica, both plaintext). In dry run first, per environment.
2. The seven removed from the chart; the mesh apps do not prune - each deleted on the cluster by kind and name after the
   push (scratchpad mesh-prune-delete.sh: the app's requiresPruning set must be exactly the expected one).
3. CI: `.woodpecker/mesh-selectors.py` fails a mesh policy whose selector matches no pod with a proxy (every chart
   rendered with everything on, the operators' pods modelled); postgres's policy checked exactly; each environment's
   PeerAuthentication exceptions by its switches.
4. The live audit committed (ops) and run - what the render cannot see (which namespace runs what).

## Rollout

Copy run 6 (the refs, the deletes beside the change, dry-run 0 and every new source listed, the enforced-twin A/B,
Kafka's restore rehearsal) -> full review -> infra, then platform, pushed -> the 23 objects deleted (test, infra,
production) -> the mesh restart (Istio 1.31.4's sidecars, and every client reconnecting under both dry-run policies) ->
a day of shadow_denied 0 -> enforced in schnappy-test (its value), then production a day later. Applying the policy and
enforcing it each reset every Postgres connection once (an Envoy filter-chain update drains them).
