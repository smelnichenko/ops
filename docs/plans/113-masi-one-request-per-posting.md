# Plan 113 — masi: a posting's page is requested once

**Status:** asked for 2026-11-09 by the operator: "is it possible to add timestamps so no retries ever made again on
source request level?", then "make plan and build".

## Why

- **`cvkeskus` spent its day on pages it had already read.** Its budget is 120 requests a day. Its normal run takes about
  17. The 08:47 UTC run on 2026-11-09 took 103, so the board's read stopped early, no listing could close, and
  `MasiSourceNotClosing` fired.
- **The cause is what masi forgets.** Before reading a posting's own page, a collector asks `isKnown`, and only open
  listings that already carry a detail count as known. A posting not connected to Estonia is read, then not stored
  (plan 110), so it is never known and is read again at every sweep. When the listings already stored for such postings
  were closed, they became unknown too.
- **It is not the HTTP layer.** `HttpFetcher` has no retries. The repeats are masi's own, one level up.
- **12 places in 10 collectors share the check,** so all of them can repeat themselves the same way.

## The rule

A posting's own page is requested once by a source, and that is written down with its time. Until the time runs out, the
request is not made again, on any pod, after any restart.

| What the request got | How long it is not asked again |
|---|---|
| An answer, including 404 and 410: the posting is gone or was read | 30 days |
| No answer: an error, a timeout, 408, 429 or a 5xx | 1 day |

- **List pages are not covered.** They must be read every time: that is how masi sees what is still open, and how a
  listing closes. The sweep's cursor already keeps them from repeating within a sweep.
- **30 days** is the longest a board's posting lives, in practice. A posting still listed after that is read once more,
  which also catches a changed text.
- **1 day** so a server that said "slow down" is left alone, and a posting caught by an outage is still read.

## The change (one masi PR)

1. **Table `source_request`:** source, the posting's external id, when, whether it was answered. One row per posting per
   source, deleted with the source. Rows past 45 days are removed as a source's run starts.
2. **Seeded** from the listings read in the last 30 days, closed ones included, so `cvkeskus` stops at the deploy
   instead of spending three more days re-reading.
3. **`CollectorRunner`** adds the remembered ids to the set `isKnown` answers from. Every collector gets the rule through
   the check it already makes.
4. **`CollectContext.asking(id)`** is called where a collector decides to read a posting's page. The next request's
   outcome is remembered against that id. The id also counts as known for the rest of the run (a page boundary read twice).
5. **Writing it down never costs a run:** a database error is logged, and the posting is at worst read again.

## What stays as it was

- A posting skipped this way is still emitted from its list card. A posting that was stored and closed comes back from
  the card, with the text it has.
- A card with no place, or a place outside Estonia, stays out: the Estonia filter judges it as before.
- A card that names nothing (`JobCards`, a blank title) still reads the page: without it there is no title at all.
- `cvkeskus`'s budget stays 120 a day.

## Tests

- The context: asking then an answer, 404, 429, 5xx, an exception; a list page remembers nothing; a companies source is
  untouched.
- The store against Postgres: both windows either side of their edge, one source's rows not another's, the row replaced,
  the old rows removed.
- The whole chain on `cvkeskus`: a second sweep sends no request for a posting it read and did not store.
- Every collector that asks `isKnown` also says `asking`, so a new collector cannot forget.
- Each mechanism reverted: red. The seed's `select` read against production before it ships.

## Deploy

One masi deploy, after the face matching first pass is over and outside a GitHub run: a restart during that two-hour run
risks `MasiSourceStale`.
