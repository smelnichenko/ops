# Plan 114 — masi: each user's own scope (countries, remote work)

**Status:** reviewed 2026-11-11 (architecture: 4 critical, 15 warnings, all merged below). **The operator accepted all six
decisions as proposed the same day ("yes to everything"),** then amended them: "there should be an admin settings page,
visible for admins, where the countries list can be configured, bootstrapped as estonia, this list will be used by people
connections as well. turning on a new country is like extending to a new market". Phases 1-3 are next. Asked for by the operator: "set of countries scope and/or remote jobs should be
configurable per user account in app settings" (2026-11-11), after "we don't care about company location that posts
remote or work from home positions" (2026-11-10).

## Goal

1. **Each user sets their scope in the app:** the countries they can work in, and how remote jobs count.
2. **Each user sees, is matched to and is told about only the jobs in their scope.**
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

`Scope = (countries: non-empty set of ISO-2 codes of countries that are on, remote: OFF | ALSO | ONLY)`.
- **countries:** where the user can work. Default `{EE}`. At least one; only countries that are on.
- **remote:** `ALSO` (default, today's rule): on-site and hybrid jobs in the countries, and remote jobs that can be done
  from them. `ONLY`: remote jobs alone. `OFF`: on-site and hybrid alone.
- A job of unknown work form counts as on-site or hybrid (it is shown under `ALSO` and `OFF`, not `ONLY`).
- Where the employer sits never matters (the operator, 2026-11-10).

### Judging each listing once, reading per user

`job_reach(job_id, listing_id, country, form)`, `form` ∈ `ON_SITE` | `HYBRID` | `REMOTE_PLACED` (remote, located in the
country) | `REMOTE_OPEN` (remote, open to it by region, by naming it, or by working hours) | `UNKNOWN`. One row per listing
and market country it reaches: rows carry their listing, so a closed listing's rows go with it and a merge moves rows
with their listings. Written under the job lock at ingest (`ingestOne`), on close (`closeListingsOf`) and on merge
(`mergeDuplicates`), diff-only (insert on conflict do nothing, delete what no longer holds), so two pods converge.

**A user's filter**, one indexed `exists` for every list path: `r.country in (:countries) and (:remote = 'ALSO' or
:remote = 'ONLY' and r.form in ('REMOTE_PLACED','REMOTE_OPEN') or :remote = 'OFF' and r.form not in
('REMOTE_PLACED','REMOTE_OPEN'))`. Listings of open and closed jobs alike, `manual` included (they get rows for every
market country they reach, or `EE` when they state nothing).

**Listing fields:** a changeset adds `country`, `remote`, `remote_scope` to `job_listing`, filled at ingest, so each
listing is judged on its own words. Until each source's next run fills them, a re-judge uses the job's fields.

**Reads by id stay unscoped:** `/jobs/{id}`, packages, links in alerts and the digest. Removing a country never hides a
user's applications in flight.

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

`/masi/settings` (tab "Settings"): the user's countries (searchable multi-select of the countries that are on), the remote
choice (three radio buttons), a line on what remote means, and the GeoNames attribution. API: `GET/PUT /me/scope`, the
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
| 3a | `job_listing` place columns; `job_reach` written at ingest, close and merge; idempotent backfill of every job (open, closed, manual) repeated until none lacks rows; gauge `masi_jobs_without_reach` with an alert and runbook | none |
| 3b | Read filters on every list path (jobs, similar, listings, companies and figures, dashboard, stats), scoped lanes (scoring, matching, tuning), match alerts owner-only; an architecture test that every `Job` list query goes through the scope spec. Only after 3a is fully rolled out and the gauge is 0 | remote `OFF`/`ONLY` work; nothing else while all scopes are `{EE}` |
| 3c | Per-reader report figures and the scoped digest | each reader's own figures |
| 4 | Country data, `CountryReach`, `ScopeGate` on the list for postings AND people; the EE verdict replay over production's open postings and people pinned against the merged gate; ScopeWatch on the list with the empty-list guard; retirement grace; list digest in the sweep stamp, snapshotted per run; the admin page may turn countries on | none until an admin turns a country on |
| 5 | Every Estonia filter in collector code and config takes the list (ATS, SmartRecruiters, MeetFrank, GitHub people searches) | a new market's jobs and people from global sources |
| 6+ | A market's own boards and registers (its job boards, its company register), one by one, each with numbers and the operator's OK | per source |

**Tests named now:** the EE verdict replay; a reach-row invariant (every job has rows; rows match its open listings);
`SchemaIntegrityTest` on `job_reach`; `TwoInstancesTest` for ScopeWatch and reach writes; a run whose market list changes
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
- **A gap in reach rows** hides a job from every user: the gauge and its alert, and ScopeWatch filling gaps it finds.
