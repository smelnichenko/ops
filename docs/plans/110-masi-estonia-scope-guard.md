# Plan 110 — masi: nothing without a tie to Estonia, and no hidden settings

**Status:** asked for 2026-11-08 by the operator: "this fuckup with no estonia ties and random organisations in config
should not happen again. plan".

Masi gets one PR at a time. Each PR follows the usual routine: a failing test first, revert checks, the clean check, a
PR, CI, merge, a smoke test on test, a promote, and a check in production.

## What happened

- **The org walk.** The GitHub source walked the public members of 20 GitHub organisations, and stored every member.
  The organisations were set by changesets 087 and 088 (2026-10-23), which I wrote. Nobody asked for them, and the
  operator never saw them: the Sources page shows only a source's daily cap.
- **Global organisations.** Several of them are global companies. Microsoft alone brought 999 people, of whom 5 say
  they are in Estonia.
- **Search was the only check.** The tie to Estonia lived only in the location searches. The org walk was a second
  way in that no check covered.
- **Cleaned up.** 1,064 stored people had no tie to Estonia (529 with no place, the rest Redmond, Seattle, Shanghai
  and so on). They were deleted on 2026-11-08 with the operator's OK, together with their 898 commit addresses and their
  person rows.
- **Missing foreign keys, from the same prototype haste.** The contact-picture tables, `llm_call` and
  `lifecycle_event` reference other tables with no foreign key. `github_email` and `github_follow` join contacts by
  login only, and `contact.github_login` is not even unique (24 duplicates). 14 foreign-key columns have no index.

## Causes, and what answers each

| Cause | Answer |
|---|---|
| A source's query was the only gate; a second input path bypassed it | One scope check where records are written, for every source (PR 3) |
| I added a collection path, and global companies to it, unasked | A process rule in memory (written 2026-11-08); PR descriptions and reports name every new path and setting |
| Settings lived in the database, invisible | The Sources page shows every source's whole config, secrets masked, and its change history (PR 4) |
| Nothing watched the stored data for the rule | A production invariant, measured hourly and alerting (PR 5) |
| Tables without foreign keys and indexes | Foreign keys and indexes, and a schema test that fails the build on a new gap (PR 2) |

## PRs, in order

1. **GitHub: organisation members only with a stated tie** (in progress). An org member is kept only when their own
   profile's place names Estonia; the places come from the source's own location searches, plus "Eesti". A member
   abroad is dropped before their follows and commit addresses are fetched. Without detail mode there is no place to
   check, so members are not kept at all. The run reports how many it dropped.
2. **Schema: foreign keys, indexes and a test that keeps them.**
   - Foreign keys, with indexes:
     - the picture tables: `ON DELETE CASCADE`;
     - `llm_call` and `lifecycle_event.source_id`: `ON DELETE SET NULL`, so the spend ledger outlives what it names.
   - Merge the 24 duplicate GitHub logins, make `contact.github_login` unique, and point `github_email.login` and
     `github_follow.follower_login` at it with cascade.
   - The 14 missing indexes.
   - **A schema test:** after the migrations, every column named `*_id` either has a foreign key with an index, or sits
     on a short allow-list with a reason (an outside id: Resend, the register, an ATS's posting id; the polymorphic
     `lifecycle_event.subject_id`). A new table that skips this fails the build.
   - The rows pointing at nobody (182 commit addresses, 14,090 follow links of deleted people) are deleted only with
     the operator's OK.
3. **One scope gate where records are written.**
   - **People:** the person sink keeps a person only with a tie. Their own stated place names Estonia; or an Estonian
     source vouches for them: the e-Business Register (`ariregisterpeople`), MeetFrank's Estonia-only talent search, or
     a contact on an Estonian posting.
   - **Postings:** the ingest keeps a posting only when `EstoniaReach` says it is connected (plan 109 PR 1d): located in
     Estonia, or remote open to it. An Estonian board's own postings are Estonian by the board.
   - **Every source** goes through it, whatever its query; a collector cannot bypass it.
   - Each run counts what the gate dropped ("not connected to Estonia: N"), and the Sources page shows the count.
   - **Tests:**
     - per source, a record from each of its input paths with no tie, not stored;
     - an architecture test that every writer of contacts and listings goes through the gate.
4. **The Sources page shows everything.**
   - Each source's whole config, read-only, secrets masked, beside the cap that can be edited today.
   - A history of config changes (old value, new value, when, by whom: a migration, the operator, or masi itself),
     kept in a table the Sources page reads.
   - The deployment's own switches (enrichment, pictures, name search, mail) on the same page, read from the running
     pod.
   - A rendered sample goes to the operator before it ships.
5. **The invariant, watched.**
   - A metric `masi_out_of_scope_rows`, by kind (people, postings): stored rows with no tie to Estonia. It must be 0.
   - An alert when it is not.
   - The hourly report carries it.

## Process (in memory, not code)

- **No new collection path without the operator's OK.** A new query kind, an organisation list, a follow-graph walk, a
  crawl seed, or a wider filter is proposed with the measured share of Estonia-connected results, and waits for the
  operator's own words.
- **Settings changes are said.** A migration that changes a source's settings is named in the PR description and in
  the next report.
