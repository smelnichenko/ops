# Plan 118: masi - paging only, so no search or list can take the system down

The operator, 2026-11-13: "make sure we have paging only api everywhere, so the system cannot be fucked up by
search/list/etc" (after 2026-11-11: "make sure we use paging everywhere and never get like millions in result lists").

## What was found (audit of masi 6bb77f3, 2026-11-13)

- Paged lists clamped their size in each controller, by hand (`Math.min(size, 200)`, `clamp(..., 500)` on the partner
  API, `100` on source runs), with no lower clamp in six and no limit on the page: an OFFSET as deep as asked.
- Whole lists without a bound: `GET /packages` (every package of the caller unless `job=`), `GET /persons/of-company`
  (every tie of a company; no caller left), `/contacts/pictures/for` (any number of ids), a person's GitHub
  connections, every CV version, the register's exact-name lookup.
- Request paths reading large or growing results into memory: `/stats` (every closed listing's lifetime, every new
  job's tags and salaries in the window), `/stats/daily` (~9 queries a day, ~3,300 for a year), the retune estimate and
  the retune itself (every eligible job, packages written inside the request), the picture backfill (inside the request),
  the picture status (10,000 rows read to count them).
- The source table (225 rows) read whole by `GET /sources`, `/dashboard`, `/stats` and stored in every report.
- `ResultSizes` (every result counted, 1,000 rows the limit) failed the tests but only warned in production.
- Biggest tables a request reaches today: company 29k, contact 12k, person 12k, source_run 9k, job_listing 2.9k, activity
  2.4k, job 2.3k (production, 2026-11-13); register_company 372k only through the register lookups (26 at most each);
  official_address 1.37M through no endpoint. A page's total is an uncounted `count(*)` over its filter: fine at these
  sizes; a table past 100k rows pages by key and caps its count.

## Decisions

1. One paging rule (`Paging`): a page holds 1..200 rows whatever is asked; a negative page is refused; a page starting
   past row 100,000 is refused (narrow the filter). OFFSET stays while every paged table is under 100k rows; a table
   that grows past that pages by key.
2. A list answered whole says how many at most and why (`@BoundedList(max, why)`, max <= 1,000); a build-time test fails
   any endpoint answering a list, a map or an array without it.
3. In production a read serving an HTTP request is stopped at its first row past the limit (`ResultTooLargeException`,
   500 with a clear message, counted and logged); background work is only said, as before.
4. Response shapes the site reads stay as they are in PR 1 and PR 2; the shape changes (sources paged) come with the
   site's change, previewed to the operator first.

## Phases (one PR each)

| # | What | Visible |
|---|---|---|
| 1 | masi #248: `Paging` on every paged endpoint (ArchUnit: controllers only through it; `PagedResponse` only from a Page); `@BoundedList` + `BoundedResultsTest` over every response record however deep (52 endpoints say their bound); `PagingEverywhereTest` (every GET with a size, from the handler mapping); a request's oversized read stopped in production; `/stats`, report generation and the retune read their large windows a page (500) at a time by id, the retune estimate counted; package artifacts read without their bytes; `GET /packages` needs `job`; `/persons/of-company` removed; caps: contact ids <= 200, connections <= 200, CV versions newest 200, deadlines <= 1,000, exact register name <= 26; the picture status counted in the database | none |
| 2 | `/stats/daily` in a fixed number of queries (about 9 a day today, ~3,300 for a year); the picture backfill as background work answering 202 | none |
| 3 | Sources paged: `GET /sources` a page (sort and counts on the server), the dashboard's and the stats' sources a page or counts, reports storing a capped source health; the site's Sources page, dashboard and report detail with it - a rendered sample for the operator's OK first | Sources page, dashboard, reports |

## Status

- 2026-11-13: audit done; PR 1 = masi #248, both reviews' findings fixed (the architecture review's critical: the guard
  would have stopped `/stats`, report generation and the retune - their windows now read by page in PR 1); merge held
  for the 15:23 UTC GitHub sweep (a deploy cuts it), then the next :45 window.
