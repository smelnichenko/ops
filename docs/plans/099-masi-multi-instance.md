# 099 — masi: any number of equal instances

## Context

- Every masi deploy takes the service down for the whole startup (4–5 min on the busy node `ten`; the operator hit
  "Failed to load jobs" on 2026-09-30). Plan 094 made the scheduler, the per-source locks, the ingest lock and several
  lanes in-memory and pinned `replicas: 1` / `maxSurge: 0`.
- Operator's requirement: **no special instance of any kind** — no leader, no active/passive, and no global lock or
  lane that makes one pod "the one" for a kind of work; **a second instance runs in the test namespace**; multiple pods
  must work in production.
- Direction (operator's choice, 2026-09-30): **every pod does every kind of work in parallel; only individual work
  items are claimed; a claim expires on the item's own row.** No instance registry, no lease table, no global locks.
  Where two pods touch the same data, Postgres row-level concurrency (conditional updates, row locks, unique
  constraints, idempotent upserts) decides.
- Outcome: masi `replicas: 2` in test with `maxSurge: 1, maxUnavailable: 0` (zero-downtime deploys); production values
  get the same shape (production stays disabled — the operator's call).
- Step 0 done: the foreground-blocking memory rule is revoked and the memory index cleaned.

## The one mechanism: a claim on the item's row

A claimed row carries `claimed_by` (the pod's name + a random token per claim) and `claimed_until` (database time).
- **Claim**: one conditional statement — `UPDATE … SET claimed_by=?, claimed_until=clock_timestamp()+ttl WHERE id=?
  AND <still due> AND (claimed_until IS NULL OR claimed_until < clock_timestamp()) RETURNING …`, or an `INSERT` that
  a unique index lets only one pod win. The pod that gets the row does the item; the others move on.
- **Renew**: while the work runs, the worker extends `claimed_until` every ttl/3 with `… WHERE id=? AND claimed_by=?`;
  0 rows = the claim was lost → the worker stops. Renewal runs on a platform thread per worker set, not the TaskScheduler.
- **Fence**: every write that finishes or acts on the item includes `AND claimed_by=?` (and, for the final write,
  `AND claimed_until > clock_timestamp()`); a transaction ingesting under a run's claim begins with
  `SELECT … FROM source_run WHERE id=? AND claimed_by=? AND finished_at IS NULL FOR SHARE`, so recovery by another pod
  waits for the commit and a paused pod's late write is refused (a check in memory is never enough).
- **Recovery**: any pod, in its ordinary sweeps, frees rows whose `claimed_until` has passed (conditional update, so
  two sweeping pods can't both act). No pod is judged dead; only claims expire.
- Clock: `clock_timestamp()` in single statements — never a pod's clock, never transaction-start `now()`.
- TTL 60 s, renewal every 20 s (configurable; tests shorten both).

## Which rows carry a claim

| Work item | Row (table) | Claim columns | How one pod wins |
|---|---|---|---|
| one run of one source (cron slot, "Run now", catch-up) | `source_run` (existing) | new `slot`, `attempt`, `claimed_by`, `claimed_until` | the `INSERT` itself: unique `(source_id, slot, attempt)`; partial unique `(source_id) WHERE finished_at IS NULL` stops overlap |
| tuning one package | `application_package` (existing; NEW→PREPARING + `claimed_at` already atomic) | new `claimed_by`, `claimed_until` | the existing conditional NEW→PREPARING update |
| analysing one posting | `job` (existing) | new `analysis_claimed_by`, `analysis_claimed_until` | conditional `UPDATE job … WHERE id=? AND requirements_json IS NULL AND (claim expired)` |
| AI-matching one job against the CV | `job_match` (existing) | new `claimed_by`, `claimed_until` | conditional update on the match row |
| visiting one company's site | `company` (existing) | new `enrich_claimed_by`, `enrich_claimed_until` | conditional update where the company is still due |
| one LLM call in flight | `llm_call` (existing, PENDING row) | new `claimed_by`, `claimed_until` | the row is created by the caller; renewal keeps it from turning LOST |
| one CV translation | new `master_translation` row (replaces the in-memory status map) | `state`, `claimed_by`, `claimed_until` | insert per (user, version, language) with a unique key |
| weekly/monthly report, digest | `report`, `report_notification` (existing) | — (already unique per kind+period / claimed per row) | unchanged |

Not claims, but shared rows instead of memory: `source.last_request_at` (pacing), `masi_lane_pause(lane,
paused_until)` (pause), `partner_rate_window(key, window_start, count)` (rate limit, atomic increment). The ingest paths
take no claim at all: they rely on `SELECT … FOR UPDATE` of the `job` rows they change and on upserts on the existing
unique keys (`job.fingerprint`, `job_listing (source_id, url)`).

## Every single-instance place and its row-level replacement

| Place (file) | Replacement |
|---|---|
| Cron slots — `scheduler/SourceScheduler.java` | the cron fires on every pod; the fire time is captured by a trigger wrapper (not `previousFire(now)`); the pod **inserts `source_run(source_id, slot, attempt=1)`** — unique `(source_id, slot, attempt)` lets exactly one pod win; the winner runs |
| Per-source overlap — `collector/CollectorRunner.java` `Semaphore` map, `isRunning` (the 409) | partial unique index `source_run(source_id) WHERE finished_at IS NULL`: at most one unfinished run per source, cron or "Run now" alike; `isRunning` = one query for unfinished runs; the run's claim is renewed until the collector thread actually ends (an abandoned collector keeps its row claimed) |
| Pacing — `CollectorRunner` `paceClocks` | last request time stored on the source row |
| Catch-up (#83, `MissedSlot`) | a sweep on every pod (and at start) finds slots whose run expired unfinished or never ran, frees an expired run (INTERRUPTED, conditional), and inserts `(source_id, slot, attempt=2)` — the unique index lets one pod win; no attempt 3 ("a second run without a verdict ends it", as `MissedSlot.unanswered` today) |
| Interrupted runs — `scheduler/RecoverySweeper.java` | only runs whose `claimed_until` has passed; never "unfinished at my start" |
| Ingest serialization — `registry/IngestLock.java` (global `ReentrantLock`) used by `RegistryService`, `ListingIngest`, `RegisterMatcher`, `PartnerService`, `RecoverySweeper`, `DomainKeyRepair` | **removed**: every write path it guards gets row-level safety — job find-or-create by fingerprint as an upsert on the unique fingerprint; listing upsert on `(source_id, url)`; a job's reopen/close and miss counting as conditional updates under `SELECT … FOR UPDATE` of the job row (rows locked in id order for merges); the expiry sweep's closes conditional on `last_seen_at`; register placement conditional on the company row. PR 3 inventories every guarded write with a two-writer test each |
| Posting analysis — `tuning/PostingAnalysisService.java` 64 stripe locks | a claim on the **job row** (`analysis_claimed_by/until`) inside `requirementsOf`, then re-read, then call — shared by the tuning path and the analysis lane, so neither pod pays twice |
| Analysis / matching lanes — `scheduler/AnalysisScheduler.java`, `scheduler/MatchingLane.java` | each job claimed on its row before the call (stale backlog pages are safe) |
| AI match write — `tuning/MatchService.java:84-100` | conditional update (a word score never overwrites an AI match written by another pod) |
| Pause — `pausedUntil` in TuningScheduler / AnalysisScheduler / MatchingLane | a `masi_lane_pause(lane, paused_until)` row every pod reads (shared state, not a lock); the dashboard reads it |
| Tuning — `scheduler/TuningScheduler.java` lane semaphore, queued/running sets | lane removed: every pod ticks; each package is claimed by the existing atomic NEW→PREPARING with `claimedAt`, plus `claimed_until` renewal for recovery; per-pod concurrency is a pod resource bound, not a lane |
| Enrichment — `enrich/EnrichmentScheduler.java` | the company is claimed on its row (or the visit marker row with a partial unique index) before the visit |
| Reports / digests — `reports/*` | already per item (unique report per kind+period, digests claimed per row) — kept |
| Retention, expiry and sweeps on fixed delay | idempotent conditional statements; every pod may run them |
| Startup repairs — `registry/DomainKeyRepair.java`, `registry/PersonBackfill.java`, `collector/CollectorRegistry.java` | made idempotent per row (conditional updates), safe to run on every pod at once |
| LLM calls — `ai/LlmLedgerService.java` LOST sweep with process-local live ids | `llm_call.claimed_by/until` renewed while the call is in flight; LOST when expired (the age rule stays as a backstop); budget reservation keeps its transaction advisory lock (a short transaction on the shared budget, not a pod-exclusive lane) |
| PREPARING packages | existing `claimedAt` + limit, plus `claimed_until` renewal |
| Translation status — `tuning/MasterTranslationService.java` map | a translation row (state, claimed_by/until); any pod reads it; an expired claim reads as interrupted |
| Partner rate windows — `partner/PartnerService.java` | a rate row per key and window, atomic upsert-increment |
| Browser permits, Anthropic in-flight | stay per-pod resource bounds; browser `max-parallel` × replicas ≤ browserless `CONCURRENT` (set in values) |
| Per-pod caches (DNS, known users, PDF permits), Kafka group `masi-user`, CV numbering lock | unchanged |

**Version skew:** old and new pods overlap every deploy (`maxSurge: 1`). Changesets are expand/contract (add, never
drop/rename in the same release); claim columns, unique keys and the slot format are a contract kept stable; a pod only
claims slots for sources it has a collector bean for.

**Metrics:** source health and refused-host gauges published from the database in `SourceScheduler.refresh()` (today
only the pod that ran the source sets them); masi alert rules in `platform/helm/schnappy/templates/prometheus-rules.yaml`
aggregated (`max by (source)` for DB gauges, `sum` across pods for counters and `MasiBrowserSaturated`, budget alerts
`without (pod, instance)`); an alert when ready masi pods < `kube_deployment_spec_replicas` for 10 min.

## PRs (one at a time; each: failing tests first → architecture review + test audit → own revert checks, each compiled and red → local Sonar gate + clean check → PR → CI → merge → deploy → live check → plan updated)

1. **masi — the claim helper + collectors**: a small `ItemClaims` support (claim / renew / fence / expire statements on
   `clock_timestamp()`), changeset 059 (`source_run.slot, attempt, claimed_by, claimed_until`, unique
   `(source_id, slot, attempt)`, partial unique unfinished-per-source, source pacing column), captured fire time, cron
   slot insert, run renewal, conditional finish + ingest fence, catch-up attempt 2, sweep by expiry, DB-published health
   gauges. Introduces **`TwoInstancesTest`**.
2. **masi — the lanes**: posting-analysis job claim inside `requirementsOf`, analysis/matching row claims, MatchService
   conditional write, pause row, tuning lane removed (package claim + renewal), enrichment company claim, LLM call
   claims, translation row, partner rate row, idempotent startup repairs.
3. **masi — the ingest lock removed**: every guarded write converted to row-level safety, one two-writer test per write
   path, then `IngestLock` deleted.
4. **platform + infra** (push to main; only after 1–3 are live): masi `replicas` a real knob; `maxSurge: 1,
   maxUnavailable: 0`; PodDisruptionBudget `minAvailable: 1` rendered when replicas > 1; a `preStop` lifecycle wait so
   endpoints stop routing before Tomcat's graceful shutdown (a Kubernetes hook, not a shell sleep of mine);
   `terminationGracePeriodSeconds` ≥ preStop + the 40 s tuning drain; `progressDeadlineSeconds` above the 600 s startup
   budget; alert aggregation; test and production values `replicas: 2` (production still disabled); browser
   `max-parallel`/`CONCURRENT` consistent.
5. **Live proof**, then plan 099 COMPLETE.

## Critical files

- masi: `scheduler/SourceScheduler.java`, `scheduler/MissedSlot.java`, `scheduler/RecoverySweeper.java`,
  `collector/CollectorRunner.java`, `registry/{IngestLock,ListingIngest,RegistryService,RegisterMatcher,DomainKeyRepair,PersonBackfill}.java`,
  `partner/PartnerService.java`, `tuning/{PostingAnalysisService,MatchService,MasterTranslationService,TuningService}.java`,
  `scheduler/{TuningScheduler,AnalysisScheduler,MatchingLane}.java`, `enrich/EnrichmentScheduler.java`,
  `ai/LlmLedgerService.java`, `db/changelog/changes/059-*.xml` onward, `ArchitectureTest.java`.
- platform: `helm/schnappy/templates/masi-deployment.yaml`, new `masi-pdb.yaml`, `prometheus-rules.yaml` (masi group).
  infra: `clusters/production/schnappy-test-apps/values.yaml`, `schnappy-production-apps/values.yaml`.
- Reuse: the package claim pattern (`TuningService` NEW→PREPARING with `claimedAt`), `RegisterIndex.java:83` upsert
  style, `ListingIngest.java:87-88` REQUIRES_NEW TransactionTemplate, the `SecondTierMigrationTest` changeset test.

## Verification

**`TwoInstancesTest`** — a second full application (`SpringApplicationBuilder`, `server.port=0`, Kafka off, same
Postgres: a static Testcontainers container locally, the shared one in CI), closed in `@AfterAll`; a hook stops an
instance's claim renewals without closing it; sweeps called explicitly. Each case has a named revert that turns it red:

| Case | Revert |
|---|---|
| a cron slot fires on both → one run, one row for that slot | unique `(source_id, slot, attempt)` |
| a slot fired a few ms early on both → one run of the right slot | captured fire time |
| "Run now" on B while A runs → refused, no second row | partial unique unfinished-per-source |
| A stops renewing mid-run → after expiry B frees the run and the slot runs once more (attempt 2), never a third | expiry sweep / attempt limit |
| A resumes after B freed its run → A's late finish and ingest refused | fence + conditional finish |
| B starts while A runs → A's run untouched | sweep-on-start |
| both ingest the same job concurrently → one job, both listings, consistent miss counts | row-level ingest safety (one case per write path in PR 3) |
| tune on A + analysis lane on B for the same job → one analysis call | job claim inside `requirementsOf` |
| both analysis lanes on the same backlog page → each job analysed once | row claim |
| AI match on A, word score on B → AI match kept | conditional write |
| pause set on A → B's lanes paused, dashboard identical | pause row |
| a due company on both enrichment lanes → one visit | company claim |
| translation started on A, polled on B → status seen; A stops renewing → reads interrupted | translation row |
| partner calls split A/B → one rate window | rate row |

Plus the full suite (`./gradlew clean check`) and the Sonar gate.

**Live, test namespace, two pods:**
- both Ready and serving, alerts quiet;
- 24 h: no `(source_id, slot)` with more than one run except an expired run + its attempt 2; no report or digest twice;
  the ledger shows no job analysed twice;
- a deploy while a read-only request loop (k6-smoke token, through the gateway) hits `/api/masi/jobs`: no failed request;
- one pod force-deleted mid-run (`--grace-period=0 --force`, a write on `ten` — **the operator's approval at that step**):
  the other frees the run after expiry and runs the slot once more;
- one pod frozen (SIGSTOP on the node — **approval needed**): its claims expire, the other takes the items, the thawed
  pod's late writes are refused.

## Status

2026-09-30: approved by the operator (no special instance of any kind; claims expire on the item's own row). PR 1 next.
