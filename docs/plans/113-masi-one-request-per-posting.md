# Plan 113 — masi: requests made once, a history that replays and verifies

**Status:** reviewed 2026-11-09 (architecture and platform reliability), findings merged below; waiting on the operator's
decisions. Asked for by the operator, in order: "is it possible to add timestamps so no retries ever made again on source
request level?", "make plan and build", "essentially we should be able to replay the history to get a determined data
state", "maybe we need cluster's scylla for this?", "good to have a data verification built-in, like blockchain", "plan
needs update and review".

## Goal

1. **A board is asked for a posting's page once.** No pod and no later run asks again until a recorded time runs out, with
   the exceptions named below.
2. **What a source read is kept, in order,** so the data masi derives from it can be rebuilt without sending a request.
3. **The history proves it has not changed.** A stored record that is altered or removed is detected.

**"Determined" means:** the same history and the same code version give the same data, down to a compared digest. New code
over the same history gives a new state on purpose: that is how a parser fix reaches old data.

## Why

- **masi repeats requests and cannot say why its data is what it is.** On 2026-11-09 `cvkeskus` spent 103 of its 120 daily
  requests re-reading pages. The immediate cause was a bug, fixed separately (masi #215): the collector read a map-pin icon
  instead of the place, the Estonia filter dropped Estonian postings as foreign, they closed, and closed postings count as
  new. The bug is fixed, but the weakness it exposed is general: anything not open with a detail is read again.
- **Nothing that was read is kept,** only what the parsers took from it. A parser bug loses data for good. That same day
  130 Estonian listings had been closed wrongly, and an address had merged two people. Neither could be replayed.

## Phase 1: requested once (written, needs the review's changes before it ships)

A posting's own page is requested once by a source, with the time written down. Table `source_request` in Postgres, fed by
`CollectContext.asking(id)` at the 12 places that check `isKnown`, seeded from listings read in the last 30 days.

| State of the request | Not asked again for |
|---|---|
| Asked, or read but not yet stored | 1 day |
| Read and ingested (scope-dropped counts) | 30 days |
| A 404 or 410: the posting is gone | 30 days |
| Anything else: an error, a timeout, 401, 403, 408, 429, a 5xx | 1 day |

**Changed by the review:**

- **Remember only what was kept.** The row was written at response time, but listings are ingested after the collector
  returns. A deploy-cut run lost the text while its postings counted as known for 30 days. Now: 1 day at request time,
  promoted to 30 days only after ingest succeeds.
- **`readsAgainWithNoText` collectors keep their rule.** MeetFrank, cv.ee and cvpro read until a posting gives a text. Their
  no-text postings stay out of the memory and the seed.
- **Only 404 and 410 count as a final 4xx.** A 401 or 403 is a block, not an answer about the posting.

**What this does not cover, on purpose:** list pages (how a listing closes), Workday's full read (its last-day logic needs
it), and a card with no title (`JobCards`, nothing else names it).

## What replay needs: every input to the state

| Input | Kept today | Plan |
|---|---|---|
| Answers through `CollectContext` | no | Phase 2 |
| With each: final URL, content type, the headers used, request hash, a thrown error, the time | no | Phase 2 |
| Each run's verdict and the set of known postings | partly | Phase 2 |
| LLM prompts and answers (`llm_call` holds usage and cost only) | no | **Phase 2, or the answers are lost** |
| Operator's edits (`source_config_change` covers sources only), manual pastes, inbound mail | partly | Phase 3 as events |
| Order of ingest across sources (commit order, not request time) | no | Phase 3 |
| Streams (`ctx.stream`: the register's CSVs, EMTA), browser pages (LinkedIn, TeamDash landing) | no | Decision 4 |
| Paths outside `CollectContext`: `OpenWebFetcher`/visits, pictures, `PostingImages`, `BoardCensus`, `BoardProbe`, `CompanyService` | no | Each logged or excluded by name, Decision 4 |

Phases 1 and 2 are useful alone. **Phase 3 changes how masi writes time and edits,** and is planned after Phase 2 has run.

## Phase 2: the history

### Where it goes: split between Postgres and Scylla

| | Log and chain | Answer bodies |
|---|---|---|
| **Postgres** | Chosen: one transaction with the run claim, two instances, point-in-time recovery, restore-checked. About 3-4 GB a year (estimate) | No: WAL and the nightly Pi restore |
| **Scylla** | No: cannot write a log row and a chain head atomically, and a crash can lose acknowledged rows, which reads as tampering | Chosen: large answers, each distinct answer stored once |

The first draft put both in Scylla. Both reviews rejected that for the log. **A Scylla outage now records `body_missing` in
an unbroken chain, and collection continues.** That removes the choice of stopping every source when one node is down,
which would have auto-disabled sources after ten failures.

**The node today:** one member, 2 CPU limit (100m requested), 2 GiB, 2026.1.14, `developerMode: true`, 20 Gi declared on
`local-path`, used by `chat`. Before go-live: Guaranteed QoS, disk-use alerting (`local-path` enforces nothing, and Scylla
could fill the node's disk), and try any change to the declared size in test first: the operator's webhook may refuse it.

### Volume (an estimate: step 1 measures it)

22,325 requests in 24 hours, 21,326 of them GitHub. At a guessed 20 KB an answer: about 450 MB a day raw, an estimated 60 to
120 MB after compression and storing identical answers once. Backups re-upload compacted files, so expect 2 to 3 times that.

### Schema

Postgres `source_response`: source, `seq`, `epoch`, run, method, URL commitment, request hash, status, final URL commitment,
content type, headers used, error, `body_sha256`, `body_missing`, code version, `prev_hash`, `hash`. Primary key
(source, epoch, seq). The head is the last row.

Postgres `response_url`: URL commitment to URL, erasable.

Scylla `masi_history.response_body`: `PRIMARY KEY (body_sha256, chunk)`, split at 512 KB, Incremental Compaction.

### The chain

The operator's "like blockchain" is a **hash chain**: tamper evidence, no consensus, one writer per source.

- `hash = sha256(prev_hash ‖ canonical fields ‖ body_sha256)`. The URL is in the chain as a **salted commitment**, because
  URLs can carry a person (a GitHub login, a name search).
- **Fencing:** appended in one Postgres transaction with the check that this pod still holds the run's claim, so a pod that
  lost its claim cannot extend the chain.
- **A daily anchor,** per source `(seq, hash)` plus one hash over them, written by **a separate CronJob with a write-only key**
  to its own bucket. masi's pods get no route to it, so what can rewrite the log cannot rewrite the proof.
- **A daily verifier,** throttled, outside masi's pods: walks records since the last anchor, recomputes the chain and each
  body's hash. A break raises an alert.
- **A restore starts a new `epoch`** with a signed restore record, so old anchors stay valid and the gap is stated. Rows of
  `source_request` newer than the restore point are cleared so lost answers can be fetched again.

**What this does not do:** it detects a change and does not prevent one. It cannot prove a board told the truth.

### Erasure

A permanent record conflicts with `PersonService.erase`. As first drafted, it would not have erased anything.

- An **erasure ledger,** for every person erased (today only register-keyed people leave a mark).
- A **person-to-body index,** written at ingest, so erasing a person finds their answers. One list page holds many people, so
  Decision 2 sets what happens to a shared page.
- The body and the URL are deletable; the hash and the salted commitment stay, so the chain still verifies.
- A **suppression check before every body write,** so re-fetching identical content does not restore it.
- Re-applied after any restore. Backups hold an erased body for up to their retention: Decision 2 states the maximum delay.

### Rollout

1. **Measure:** bytes per source and a sample of distinct answers, for a week, and the share of out-of-scope data.
2. **Provision,** test first: data app before masi app. Keyspace in `schnappy-data/files/scylla-schema.cql`, Scylla ingress and
   masi egress on 9042, `AuthorizationPolicy`, and the anchor CronJob, bucket and key (Ansible, on the existing store). Scylla
   runs without authentication today, so any admitted pod could rewrite bodies: the hashes would catch it.
3. **Prove a restore** with `sctool` into test Scylla on ten, then run the verifier against the anchors. Exclude Scylla's
   volume from Velero's file copy, which is live and inconsistent.
4. **Write, verify, anchor,** with alerts for a broken chain, a missing anchor, and `body_missing`.

## Phase 3: replay (a separate plan once Phase 2 has run)

A replaying fetcher serves answers by run, URL and request hash, so new code that asks differently still finds them. **A
replay never sends a request.** A replay clock replaces `Instant.now()`. It runs into a scratch database and compares a digest
with production. First target: `cvkeskus` postings, replayed twice to the same digest.

## Decisions for the operator

1. **Retention:** forever, or a number of years? Proposed: forever, while the measured size allows. Retention by age needs a
   signed checkpoint to keep the chain verifiable.
2. **Erasure of a shared page:** delete the whole page, and how long may a backup hold an erased body? Proposed: delete the
   page, and 30 days at most.
3. **The Estonia-only rule.** Keeping everything read also keeps the non-Estonian postings and people masi refuses to store.
   Proposed: keep only answers that yielded something Estonia-connected, and for the rest keep the hash and the time. Replay is
   then complete for what masi holds.
4. **GitHub (95% of requests), the register's CSVs, browser pages, pictures:** which go in? Proposed: GitHub after measuring;
   the others by hash only at first.
5. **LLM prompts and answers:** record them? Without it replay can never reproduce analysis and matching. Proposed: yes.
6. **Scylla nodes:** stay at one? Proposed: one for now. Bodies are the only thing there, and a lost one is stated as missing.
7. **A Scylla restore drill** on ten needs your OK, and the Pi restore check does not cover Scylla today.

## Tests

- **Phase 1:** each request state; 1 day until ingest, then 30; a deploy-cut run's postings asked again; no-text postings still
  read; both window edges; a second `cvkeskus` sweep asks nothing for a posting read; every collector that asks `isKnown` also
  says `asking`. Each mechanism reverted: red.
- **Phase 2:** a changed byte, a removed row and a reordered row each detected; a pod that lost its claim refused; Scylla down
  records `body_missing` and the run goes on; an erased body still verifies and is not restored by a re-fetch; the restore drill.
- **Phase 3:** the same history replayed twice gives the same digest.

## Deploy

Each step is one masi deploy, outside a GitHub run: a restart during that two-hour run risks `MasiSourceStale`.
