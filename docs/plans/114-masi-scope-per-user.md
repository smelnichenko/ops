# Plan 114 — masi: each user's own scope (countries, remote work)

**Status:** reviewed 2026-11-11 (architecture: 4 critical, 15 warnings, all merged below). **The operator accepted all six
decisions as proposed the same day ("yes to everything"),** then amended them: "there should be an admin settings page,
visible for admins, where the countries list can be configured, bootstrapped as estonia, this list will be used by people
connections as well. turning on a new country is like extending to a new market", and "user should be able to configure,
which companies and people - all data classes country filters apply to him", and "essentially, any masi entity should
have some location, either physical or virtual, so it can be sorted by", and "think about db performance!". Phases 1-3
are next. Asked for by the operator: "set of countries scope and/or remote jobs should be
configurable per user account in app settings" (2026-11-11), after "we don't care about company location that posts
remote or work from home positions" (2026-11-10).

## Goal

1. **Each user sets their scope in the app,** per kind of data: the countries for jobs (and how remote jobs count), for
   companies, and for people.
2. **Each user sees, is matched to and is told about only the jobs, companies and people in their scope.**
4. **Every masi entity has a location, physical or virtual,** shown and sortable in every list (plan 112's practice).
3. **masi collects for the countries an admin has turned on, and nothing beyond them** (plan 110's rule, generalised:
   the list starts as `{EE}`). Jobs and people alike. **Turning a country on is entering a new market.**

Until this ships, Estonia stays the only scope. A user with no saved scope has the default, exactly today's: `{EE}`,
remote open to it counted. So the first phases change nothing anyone sees.

## The one choice that shapes the rest

**Collection follows the countries an admin has turned on (the markets); a user's picks only narrow what that user sees.**
- A user can pick only countries that are on. An admin turns a country on in masi's admin settings, and only then does
  masi collect for it: its jobs and its people.
- The gate, `ScopeWatch` and the sweep stamp read the market list, which changes rarely and only by an admin. A user
  editing their settings never restarts a sweep, never widens collection, and never closes anything.
- Why: the union of user picks as the gate (the first draft) let an empty or shrunk union close the registry (any bug, or
  the operator's account disabled), let any user widen collection unasked, restarted every sweep on every settings edit,
  and closed a dropped country's listings at once.

## Where masi is today (HEAD 1c46af9 plus the open timezone PR)

- **The scope is a store-time gate,** fixed in code: `EstoniaScope.posting` and `person`, with `EstoniaReach` and
  `Countries` (pinned by `EstoniaGatePinTest`). It runs in `RegistryService` (`:249` people, `:333` listings of every
  source but `manual`). `ScopeWatch` runs on every pod every 600 s and **closes** open listings the gate rejects, rebuilt
  from the job's first-source-wins fields (`job.country`, `remote`, `remote_scope`); `job_listing` has no such columns.
- **Remote is not a switch:** it is the `openRemote` / `admits` / working-hours branch of the gate.
- **Collectors filter by Estonia in code and config:** `EstoniaReach` in `AtsCollector` (`:146`, `:211`, `:244`, `:405`,
  `:447`, `:507`), `IcimsCollector:86`, `PersonioFeed:74`, `CvKeskusCollector`; GitHub's searches from `PLACE_NAMES`;
  `EstoniaScope.ABROAD` hard-codes Latvia, Finland, Riga...; seed config `country` EE, MeetFrank `countryId`; LinkedIn
  stamps EE. Estonian boards (cv.ee, cvkeskus, cvpro, Töötukassa, TeamDash) and registers (Äriregister, EMTA, ITL) hold
  Estonia's inventory alone.
- **Users:** identity from the gateway JWT (`GatewayUser`); `users` mirrors every platform user (chat and chess too,
  disabled ones included, no JOBS flag). Per-user tables key on `user_uuid` with no FK to `users`. **No per-user settings
  store exists;** `app_flag` is global.
- **Read paths:** `GET /jobs` (filters `country` exactly on `job.country`, often null; `remote` by type), job detail,
  similar, listings, companies and their figures, dashboard, `/stats` and `/stats/daily`, reports and the weekly digest
  (built from the stored global report alone), the partner API.
- **Background lanes ignore scope:** analysis, word scoring (`MatchService`), AI matching (`MatchingLane`), auto-tune and
  retune (`TuningService`, `jobsWithoutPackageIn`). The match alert goes to the operator's channel for any user's CV.

## Design

### A scope

`Scope = (jobs: countries + remote, companies: countries, people: countries)`, each a non-empty set of ISO-2 codes of
countries that are on.
- **jobs.countries:** where the user can work. Default `{EE}`. At least one; only countries that are on.
- **companies.countries, people.countries:** default "the same as jobs" (one list for most users, kept in step when the
  jobs list changes); a user may set either separately - Estonian companies but people from every market, say.
- **remote:** `ALSO` (default, today's rule): on-site and hybrid jobs in the countries, and remote jobs that can be done
  from them. `ONLY`: remote jobs alone. `OFF`: on-site and hybrid alone.
- A job of unknown work form counts as on-site or hybrid (it is shown under `ALSO` and `OFF`, not `ONLY`).
- Where the employer sits never matters (the operator, 2026-11-10).

### Judging each listing once, reading per user

Each listing is judged once against the market list, and the verdict is stored **on the row itself** as two small arrays
of ISO-2 codes (design for speed: see "Database performance"):
- `reach_onsite char(2)[]`: the market countries where it is on site, hybrid, or of unknown work form (unknown counts as
  on-site);
- `reach_remote char(2)[]`: the market countries it can be done remotely from - located there and remote, or open to
  them by region, by naming them, or by working hours.

A **job's** arrays are the union of its open listings' (a closed job keeps its last), recomputed under the job lock in
`ingestOne`, `closeListingsOf` and `mergeDuplicates`, and written only when they change. `manual` listings get arrays too
(`EE` when they state nothing). Listings of open and closed jobs alike.

**A user's filter**, one indexed predicate on the job row: `ALSO`: `reach_onsite && :c or reach_remote && :c`; `ONLY`:
`reach_remote && :c`; `OFF`: `reach_onsite && :c`. **When the user's countries cover the whole market list and remote is
`ALSO`, no filter is added at all** - every user today, and most later.

**Listing fields:** a changeset adds `country`, `remote`, `remote_scope` to `job_listing`, filled at ingest, so each
listing is judged on its own words. Until each source's next run fills them, a re-judge uses the job's fields.

**Reads by id stay unscoped:** `/jobs/{id}`, packages, links in alerts and the digest. Removing a country never hides a
user's applications in flight.

### Every entity has a location

`Location = (kind: PHYSICAL | VIRTUAL, country: ISO-2 or null, region: EU | EEA | EUROPE | EMEA | NORDICS | BALTICS |
WORLDWIDE | null, place: text or null)`. **Physical:** a place on the map (an office, a home address, a town). **Virtual:**
a presence with no place - remote work, a website, an online meeting, a mail domain - placed by the country or region it
serves when it says one.

**One primary location per entity, for showing and sorting;** the reach rows (below) for filtering, since a job or company
can reach several countries. Stored as `loc_kind`, `loc_country`, `loc_region`, `loc_place` on the root entities; the
others take theirs from what they belong to.

| Entity | Its location |
|---|---|
| Listing | its own words: a place (physical) or remote with its scope (virtual) |
| Job | its open listings': the first physical one, else the first virtual one; a closed job keeps its last |
| Company | its registered address (physical; an Äriregister code is `EE`); else its website's country-code domain or its jobs' (virtual) |
| Person | the place they state (physical); else where they were found: a register's country, or GitHub with no place (virtual, no country) |
| Contact | the person's or, failing that, the company's |
| Source | virtual: the board's site and the market it serves (cvkeskus `EE`, Jobicy `WORLDWIDE`); an employer's own board takes the employer's |
| Calendar event | its meeting place (physical), an online meeting (virtual), else the linked job's or company's |
| Inbound mail | virtual: the sender's country-code domain, else the linked company's |
| CV version | virtual: the market its language serves (`et` -> `EE`, `en` -> none) |
| Report | virtual: the market list it covers |
| Package, match, override, activity, run, lifecycle event | the job's, company's, person's or source's they belong to (a join, not a copy) |
| Internal rows (flags, LLM calls, fingerprints, rejections, pictures, register placements) | their parent's; not shown |

**Sorting** (one rule for every list): by the country's English name (a region's label when there is no country, after the
countries; no location last), then physical before virtual, then the place text. Server-side for paged lists, as plan 112
requires; a `Location` column on every list that shows one of these entities.

**Filtering** stays on the reach rows: the location says where an entity is, the reach says which markets it counts for
("remote, EU" is one virtual location reaching every EU country that is on).

### Companies and people, judged once too

- `company.reach char(2)[]`: the market countries it is registered in (an Äriregister code is `EE`) or hiring in (a job
  of its reaches the country). Rewritten when the company is registered or merged and when its jobs' arrays change.
- `person.reach char(2)[]`: the country of the place the person states (by `CountryReach`), or of a register listing
  them (Äriregister's people are `EE`). Rewritten when the person is captured or merged.
- The user's filter is `reach && :c` on the row, skipped when their list covers the market list. Read paths: `/companies`
  and their figures and contacts, `/persons` and `/persons/of-company`, `/contacts` (the person's array). Reads by id stay
  unscoped, as for jobs.

### Database performance

Measured in production 2026-11-11: `company` 28,953 rows, `person` 11,956, `contact` 11,994, open jobs 1,410, open listings
1,709, `register_company` 371,595 (the register's index). Designed to stay fast at ten times that, when markets are added.
- **No reach tables, no joins:** the arrays live on the row, each with a GIN index (`gin (reach_onsite)`, `gin
  (reach_remote)`, `gin (reach)`); `&&` with a handful of codes is an index scan, and the planner ORs the two job indexes.
  A market list has a few countries, so the arrays stay tiny.
- **The common case costs nothing:** no predicate when a user's lists cover the market list.
- **Sorting by location never computes:** `loc_sort text` is written with the location (the country's English name or the
  region's label, kind, place, lower-cased), with a btree index `(loc_sort, id)`; on `job` a partial one `where status =
  'OPEN'`. Paged lists that can grow large (companies, people, the register) page by key (`where (loc_sort, id) > (...)`),
  not `OFFSET`.
- **Derived locations** (packages, matches, activity, runs) sort through a join to their parent's indexed `loc_sort`: the
  parents are small and the foreign keys are indexed (`SchemaIntegrityTest`).
- **No write churn:** arrays and locations are compared before an update and written only when they differ, so the WAL and
  the GIN indexes see changes, not traffic; a `reach_of text` column holds the market-list digest a row was judged under,
  and only rows whose digest differs are re-judged - once per market change, in batches, never every `ScopeWatch` sweep.
- **Backfill in batches** of 1,000 rows per transaction with a pause between, idempotent and resumable, outside the busy
  collection minutes; the gauge `masi_rows_without_reach{kind}` shows the rest.
- **Measured before each phase ships:** `EXPLAIN (ANALYZE, BUFFERS)` of every new or changed list query on production's
  standby (read-only), pasted in the PR; budget **p95 under 50 ms** for a list page and its count; after deploy,
  `pg_stat_statements` compared with the week before.

### The gate on the market list

- `EstoniaScope` becomes `ScopeGate(on)`, `EstoniaReach` becomes `CountryReach` per country, from data (below).
  **Kept** = the posting reaches a country that is on. Today that is exactly `{EE}`.
- **ScopeWatch** closes only on the market list, read from the database after its open-postings query (no per-pod
  cache). **A market list that is empty or cannot be read closes nothing:** the sweep logs, alerts and leaves the gauge
  stale. `EE` is a floor that cannot be removed without a code change.
- **Retiring a country** (the operator removing it) closes nothing at once: it is marked retired, and its listings close
  by their boards' own misses, or after 7 days, with the reason recorded. No wave of closures and reposts in the reports.
- **Sweep stamp:** a digest of the market list joins `Collector.reading(config)`, snapshotted into `CollectContext` at
  run start; `RegistryService.listings` gates with that snapshot, so a change during a run neither mis-stamps nor half-gates
  it. The gate pin covers the new classes and the country data file.
- **People** follow the same list (the operator, 2026-11-11): the person gate keeps a person whose own stated place is in
  a country that is on; GitHub's place searches come from each country's place names; `masi_out_of_scope_rows{kind="people"}`
  counts against the list; a retired country's people are counted out of scope after the same grace (never deleted by a
  sweep, as today). The runbooks `MasiOutOfScopeRows.md` and `MasiOutOfScopeNotCounted.md` say "the countries that are on".
- **Partner pushes** are gated on the market list. The scope is a relevance filter, not an access boundary: the partner
  API stays unscoped.

### Country data and matching

- One bundled, versioned, pinned file: per country its names (English and own language), ISO codes, regions (EU, EEA,
  Europe, EMEA, Nordics, Baltics...), UTC offsets (standard and summer), and place names. Estonia keeps its hand-made list.
  Others start from GeoNames `cities15000` filtered to cities of 100k or more plus capitals (CC BY 4.0: attribution in
  `NOTICE` and on the settings page; the dump date pinned; only the derived file committed).
- **Matching by lookup, not regex alternations:** a token and bigram map `name -> countries`, linear, no ReDoS.
- **Ambiguity guards:** ISO codes match case-sensitively and only in country or remote-scope fields ("IN", "IT", "NO",
  "BE" are English words); foreign city names match only in location fields, never free text, with a stop-list ("Reading",
  "Split", "Nice", "Mobile"); a name shared by countries (London, Valencia, Hamilton) resolves only with a qualifying country
  or region beside it. `ABROAD` becomes "places of countries outside the market list".

### Collecting for a new market

Everything that filters by Estonia in code or config takes the market list: `AtsCollector`'s regions and location
regexes, `IcimsCollector`, `PersonioFeed`, SmartRecruiters/Teamtailor/Eightfold `country`, MeetFrank `countryId` (one row
per country). Estonian boards and registers stay Estonian. A country's own boards, and the remote-job boards of
`docs/remote-sources-investigation.md` (being built separately, open to any market country by their own place fields),
are each their own collection path.

### Per-user lanes

- **Word scoring, AI matching, auto-tune and retune:** a CV is matched and tuned only against jobs in its owner's scope
  (`MatchService.refresh`, `MatchingLane.matchSome`, `TuningService.autoCreate`, `retune`, `retuneEstimate`).
- **Posting analysis** stays global, limited to jobs that reach a market country.
- **Match alerts:** sent only for the operator's own CVs (the operator's uuid in config), in the operator's scope. Other
  users' matches stop reaching the operator's channels.
- **Weekly digest and reports:** the stored report gains per-reader figures (new, closed, open, top companies in each
  reader's scope), as the funnel already is, with a payload version; the digest reads them. Drill-down links
  (`GET /jobs?event=`) pass the reader's scope so the list keeps exactly the jobs the figure counts.

### The settings page

`/masi/settings` (tab "Settings"): three blocks - Jobs (countries, the remote choice as three radio buttons, a line on
what remote means), Companies and People (each "same as jobs" or their own countries) - each a searchable multi-select
of the countries that are on; and the GeoNames attribution. API: `GET/PUT /me/scope`, the
caller's own only; refused: no countries, a country that is off. Countries are never shown with their owners.

### The admin settings page

`/masi/admin` (tab "Admin", shown only to admins): the markets - the list of countries masi collects for, bootstrapped
as `{EE}`. Admin = the platform's `MANAGE_USERS` permission (the site's own Admin page uses it); the API
`GET /admin/countries`, `PUT /admin/countries/{code}` (on / off), `@RequirePermission(MANAGE_USERS)`, every change written
to the activity log with who and when.
- **Turning a country on** shows what follows before it is confirmed: the sources that will ask for it, its place data,
  the sweeps that begin again, and (once measured) the postings it adds. A country can be turned on only when its country
  data exists (phase 4); before that the page lists the countries and refuses with "not ready: its places are not in masi
  yet".
- **Turning a country off** retires it (the grace above); users whose scope held it keep their other countries, and one
  left with none falls back to the list's first country.
- At least one country stays on.
Rendered sample to the operator before either page ships.

**Who has a scope:** a missing row is the default. `user_scope` keys on `user_uuid` (no FK to `users`: a JOBS user not yet
mirrored can still save). Only users with masi access ever write one.

## Phases (one PR each, in order; failing test first in each)

| # | What | Visible change |
|---|---|---|
| 1 | `market_country` (seeded `EE`) and `user_scope` (changeset 121), `GET/PUT /me/scope`, `GET /admin/countries`, `PUT /admin/countries/{code}` (`MANAGE_USERS`; turning on refused until phase 4), refusal of a country that is off | none |
| 2 | Site pages: Settings (every user) and Admin (admins only), samples first | the pages |
| 3a | location columns and `loc_sort` on the root entities; `job_listing` place columns; reach arrays on listings, jobs, companies and people with GIN indexes, written at ingest, registration, close and merge only when changed; batched idempotent backfill of every row (open, closed, manual); gauge `masi_rows_without_reach{kind}` with an alert and runbook; EXPLAIN on the standby | none |
| 3b | a sortable `Location` column on every list (plan 112's header and server-side sort); read filters on every list path (jobs, similar, listings, companies and their figures and contacts, persons, contacts, dashboard, stats), scoped lanes (scoring, matching, tuning), match alerts owner-only; an architecture test that every `Job` list query goes through the scope spec. Only after 3a is fully rolled out and the gauge is 0 | remote `OFF`/`ONLY` work; nothing else while all scopes are `{EE}` |
| 3c | Per-reader report figures and the scoped digest | each reader's own figures |
| 4 | Country data, `CountryReach`, `ScopeGate` on the list for postings AND people; the EE verdict replay over production's open postings and people pinned against the merged gate; ScopeWatch on the list with the empty-list guard; retirement grace; list digest in the sweep stamp, snapshotted per run; the admin page may turn countries on | none until an admin turns a country on |
| 5 | Every Estonia filter in collector code and config takes the list (ATS, SmartRecruiters, MeetFrank, GitHub people searches) | a new market's jobs and people from global sources |
| 6+ | A market's own boards and registers (its job boards, its company register), one by one, each with numbers and the operator's OK | per source |

**Tests named now:** the EE verdict replay; a reach-row invariant (every job has rows; rows match its open listings);
the reach arrays' GIN and `loc_sort` indexes present (`SchemaIntegrityTest`); a list-query plan test (no sequential scan on `job`, `company`, `person` for a scoped list); `TwoInstancesTest` for ScopeWatch and reach writes; a run whose market list changes
mid-run keeps its stamp and gate; the empty-set guard closes nothing; the scoped-read architecture test; vitest for the
settings page; Sonar complexity checked by eye on `CountryReach`.

## Decisions (accepted 2026-11-11, decision 5 amended, an admin page added)

1. **Collection follows the market list (admins turn countries on), user picks only narrow** (the shape above). Proposed: yes.
2. **Build phases 1-3 now, 4-5 when a second country is wanted.** Proposed: yes.
3. **Remote choices:** `ALSO` / `ONLY` / `OFF`, unknown work form counted as on-site. Proposed: yes.
4. **Each user sets only their own scope.** Proposed: yes.
5. ~~People stay Estonia-only~~ **People follow the market list** (the operator, 2026-11-11).
6. **The partner API stays unscoped** (a relevance filter, not access control). Proposed: yes.

## Risks

- **A wrong verdict for a new country** (coarse place names, shared names): matching only in place fields, case-sensitive
  codes and the ambiguity rule keep false keeps rare; misses are shown on the Sources page per country.
- **Spend:** a new market adds postings to analyse; the AI lanes keep their daily budgets, and the Sources page
  shows what each market adds.
- **A row without reach** hides a job from every user: the gauge and its alert, and ScopeWatch filling gaps it finds.
