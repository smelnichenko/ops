# 095 — masi: calendar, activity log, and the recruiter ↔ company graph

## Decision

Three additions to masi (`ops/docs/plans/094-masi-job-registry.md`), one arc, four PRs:

1. **An activity log** — the append-only record of the operator's search: postings collected, applications
   sent, messages sent and received, calls, interviews, offers, rejections, notes — every row linked to its
   job, company and person, written by masi where masi did it and by the operator where they did.
2. **A calendar** — Outlook-like month / week / day views for scheduling calls, interviews, deadlines and
   follow-ups; every day cell shows the day's numbers (**sent**, **collected**, **communicated**) and each number
   opens that day's activity log.
3. **Persons and their ties to companies** — a person is one identity across boards and companies (a recruiter
   at an agency posts for many clients; a company's board members come from the register); the ties carry
   their evidence. Today the registry has 128 contact rows, every one an employer's own HR person from cv.ee
   or Töötukassa, one company each, no recruiter seen twice, no agency → client link, no communication —
   the area the operator called weak. The research below says where ties can come from within the rules.

Operator, 2026-09-22: *"masi user should have a calendar for scheduling calls/interviews, similar to outlook.
a day should show stats like sent, collected, communicated that lead to activity log with links to jobs,
companies, contacts. also, I would like to see connections between recruiters and companies, this area is
weak and need research."*

## Why

- The search is a process with dates: an interview on Thursday, a follow-up due after a week of silence, a
  posting's deadline. masi records what it collected and what it tuned, and nothing of what the operator did
  with it after "Mark applied"; the weekly digest counts applications, not conversations.
- A recruiter is the person who decides whether an application is read. Which agencies place at which
  companies, and who at a company answered last time, is knowledge the operator keeps in their head today.
- The register import (`ariregister`) streams the general-data dump weekly and keeps company fields only; the
  same dump carries every company's board members and representatives — a person ↔ company tie with the
  register as evidence, free, open data (CC BY 4.0), already fetched.

## Research: where recruiter ↔ company ties can come from

| source | what it gives | evidence quality | within the rules | verdict |
|---|---|---|---|---|
| cv.ee listing contact block (`contacts`) | name, e-mail, phone of the poster; 118 of the 128 contacts | the poster of THIS listing; an agency shows as a contact whose e-mail domain is not the employer's | yes (already read) | **use**: `person` from the contact, `POSTED_FOR` tie to the listing's company; domain mismatch marks a recruiter outside the employer |
| Töötukassa `avalikKontaktisik` | name, e-mail, phone | same | yes (already read) | **use**, same rule |
| e-Business Register general-data dump | board members, representatives, contact persons per company (`isikud` in the yldandmed record) | the register: the strongest tie there is (who signs for the company) | yes (open data, already streamed; persons' rows are public register entries) | **use**: `person` + `REPRESENTS` ties for the 28 000 IT companies; the operator's contact at a small company is usually its board member |
| Analysis `agencyRelay` (Haiku reads "on behalf of our client") | the posting is an agency's, employer hidden | a model's reading, 2 of 74 so far | yes | **use as a hint** on the job and the poster's company: an agency |
| Company names (Stafferty, Stafflow, EduTalent, e-staff, ESTIT HR, guavaHR, Global Talent Advantage, …) | who is an agency | name pattern + the register's EMTAK 78.10/78.20/78.30 (employment activities) | yes (register) | **use**: `company.agency` from EMTAK, name pattern as fallback |
| MeetFrank, Bolt, ATS feeds | no recruiter fields (checked: Greenhouse, Lever, SmartRecruiters, Teamtailor, Workable, Personio, BambooHR carry none) | — | — | nothing to take |
| LinkedIn, Glassdoor | recruiter profiles, "people at" | rich | **no** — dropped altogether (operator, 2026-09-22, after the API investigation: no tier of the API returns other members or connections, the terms forbid storing member content, scraping and throwaway accounts are out) | nothing from LinkedIn enters masi, not even the operator's export; a person is entered by hand where it matters |
| Company websites ("team", "careers contact") | HR contacts | good | **no**: hosts not on the allow-list — the same wall as enrichment | not without a per-host listing |
| masi's own inbox | every reply a recruiter sends: sender, company (by domain), thread | the conversation itself | yes: monitor already receives inbound mail through a Resend webhook (`WebhookController`, `ResendWebhookService`); masi gets its own address (`masi@…`) the operator puts in the CV's contact line | **use** (PR4): a received message → `RECEIVED_MESSAGE` activity, the sender matched to a person by e-mail, a new person otherwise; sent mail stays the operator's to log (or a BCC address, PR4b) |
| The operator | "talked to X at Y" | first-hand | yes | **use**: a person and a tie in three fields on the person page |

What the graph can then answer: who posted this job; whom the operator has talked to at this company; which
agencies place at this company and who there answered before; every company one recruiter has posted for; who
signs for a company (the register). What it will not answer: who works at a company today beyond its
representatives and its posters — LinkedIn is out by decision, so that gap stays and is said so on the page.

Open questions the first PRs settle with data: how many cv.ee contacts have an e-mail domain other than the
employer's (the agency share); how many register persons sit on more than one IT company's board (the
operator's "connections" between companies); whether Töötukassa's contact is the same person across a
company's postings (identity by e-mail vs name).

## Architecture

### Data model (Liquibase, `author="masi-service"`, changesets 028+)

| table | columns | notes |
|---|---|---|
| `person` | id, name, name_norm, email, email_norm (unique, nullable), phone, title, agency (bool), first_seen_at, last_seen_at, do_not_contact, user_note | identity: e-mail first, else name + one company; `contact` rows migrate into persons (`contact.person_id`), the contact staying the listing-level capture |
| `person_company` | person_id, company_id, role (`POSTED_FOR` / `REPRESENTS` / `WORKS_AT` / `RECRUITS_FOR` / `TALKED_TO`), evidence (`LISTING` / `REGISTER` / `MAIL` / `OPERATOR`), evidence_ref (listing id, register code, activity id), since, until, unique (person, company, role, evidence, evidence_ref) | the tie with its proof; a role is never inferred from another |
| `activity` | id, user_uuid, at, kind (`COLLECTED`, `ANALYSED`, `PREPARED`, `APPLIED`, `SENT_MESSAGE`, `RECEIVED_MESSAGE`, `CALL`, `INTERVIEW`, `OFFER`, `REJECTED`, `NOTE`, `SCHEDULED`), origin (`SYSTEM` / `OPERATOR` / `MAIL`), job_id, company_id, person_id, package_id, event_id, summary (≤ 300), detail (text), created_at | append-only; `at` is when it happened (a call yesterday logged today keeps yesterday); SYSTEM rows are written where the thing happens (ingest: one `COLLECTED` per new job; review `APPLIED`; the tuner `PREPARED`) |
| `calendar_event` | id, user_uuid, kind (`CALL`, `INTERVIEW`, `DEADLINE`, `FOLLOW_UP`, `OTHER`), starts_at, ends_at, all_day, title, job_id, company_id, person_id, location (a room, a link), notes, outcome (`NONE` / `DONE` / `CANCELLED` / `NO_SHOW`), remind_before, created_at, updated_at | the operator's own; a posting's `expires_at` is shown as a deadline marker without a row |

The day's numbers are derived, never stored: `sent` = APPLIED + SENT_MESSAGE, `collected` = COLLECTED,
`communicated` = SENT_MESSAGE + RECEIVED_MESSAGE + CALL + INTERVIEW — counted by `at` in Europe/Tallinn days
(the calendar is the operator's; the reports stay UTC and say so).

### API (`/api/masi/…`, `@RequirePermission(JOBS)`, everything scoped by `user_uuid`)

| endpoint | purpose |
|---|---|
| `GET /activity?from&to&kind&job&company&person&page` | the log, newest first, each row with its links |
| `POST /activity` {at, kind, job, company, person, summary, detail} | the operator logs a call, a message, a note |
| `GET /calendar?from&to` | events in the range plus per-day counts {sent, collected, communicated} and deadline markers |
| `POST /calendar`, `PATCH /calendar/{id}`, `DELETE /calendar/{id}` | events; creating one writes a `SCHEDULED` activity, marking an outcome writes `CALL` / `INTERVIEW` with it |
| `GET /calendar.ics` (token-scoped link) | the operator's phone subscribes; later |
| `GET /persons?q&company&agency`, `GET /persons/{id}` (ties with evidence, activities, listings posted), `PATCH /persons/{id}`, `POST /persons`, `POST /persons/{id}/ties` | the graph |
| `GET /companies/{id}` gains `persons` (ties by role) and `agencies` (who placed here) | |

### site/ pages

`MasiCalendar.tsx` (month grid → week columns → day list; the radar repo's booking calendar is the shape to
follow, not code to share), `MasiActivity.tsx` (the log with filters; the day link from the calendar lands
here), `MasiPersons.tsx` + `MasiPersonDetail.tsx`; the company page gets a "People" card; the job page gets
"Log a call / Schedule an interview" beside "Mark applied". Every page with its vitest test; the calendar
measured headless at 390 and 1280.

### Writers of SYSTEM activities

`ListingIngest` (COLLECTED per new job, no user: the log's system rows carry `user_uuid` null and are shown to
every JOBS user — today one), `TuningService.review` (APPLIED / REJECTED), `TuningService` (PREPARED),
`CalendarService` (SCHEDULED, outcomes), PR4's `InboundMailService` (RECEIVED_MESSAGE).

## Migration strategy

1. **PR1 — activity log** (`masi` + `site`): changeset 028 (`activity`), `ActivityService`, the SYSTEM writers,
   `GET/POST /activity`, `MasiActivity.tsx`, a backfill of `COLLECTED` from `job.first_seen_at` and `APPLIED`
   from `application_package.applied_at` (a one-time changeset, so the log reaches back to day one).
   Invariant: every new job writes exactly one COLLECTED row in the same transaction; a review to APPLIED
   writes one APPLIED row; the log for a day equals the rows whose `at` falls in that Tallinn day.
1b. **PR1b — the integration API** (`masi` + `admin`/`platform` for the partner role). Operator, 2026-09-22: *"we need
   an API for import/export/reading/updating of data regarding companies, jobs, hrs which allow 3rd parties to
   provide us with connections, updates, etc. use swagger so I can test/view it."* Swagger UI is already served
   (`/api/masi/swagger-ui/index.html`, `/api/masi/api-docs`); it gains a bearer security scheme so Authorize works,
   and a `partner` OpenAPI group with examples. The API:
   - **Identity.** A partner is a Keycloak client (client-credentials) whose token carries the realm role
     `MASI_PARTNER` and a `partner` claim (its key); masi maps it to a `source` row `partner:<key>` (kind
     `DETERMINISTIC`, never scheduled). Every write is that source's: a partner's jobs are its listings, its
     companies its discoveries, its persons its ties — the same dedupe, history and evidence rules as a board, and
     "who told us" on every row. `@RequirePermission(MASI_PARTNER)` on the group; the operator's `JOBS` token may
     call it too (that is how it is tested in Swagger).
   - **Import** (`POST`, JSON arrays, 1–500 items, all-or-nothing per item, a per-item result): `/partner/jobs`
     (the `RawListing` shape: url, title, company, location, description, postedAt, expiresAt, salary, applyUrl,
     contacts) → `RegistryService.tryIngest` under the partner's source; `/partner/companies` (`RawCompany`);
     `/partner/persons` (name, e-mail, phone, title, company reference by registry code or name, role, since) →
     persons and `person_company` ties with evidence `PARTNER` and the partner's key as `evidence_ref`.
   - **Export / read** (`GET`, paged, `since` on the row's own timestamps, JSON; `format=ndjson` for bulk):
     `/partner/jobs`, `/partner/companies`, `/partner/persons` (persons and their ties), `/partner/changes?since`
     (a feed of job opens/closes/reposts and merges from the lifecycle log, so a partner can follow the registry).
   - **Update** (`PATCH`, fields a partner may state): a company's website, careers URL, ATS, size, city; a job's
     closed-by-partner (a listing close on the partner's own listing only); a person's title, e-mail, phone —
     never the operator's notes, never another source's rows.
   - **Rate and size**: 60 requests a minute per partner, 500 items a call, bodies ≤ 2 MB; an import over the
     partner's daily request cap (`dailyRequestCap` on its source row, like MeetFrank's) is refused with 429.
   Invariant: a partner's import of a job a board already shows adds a listing, never a job; a partner cannot
   read another user's activities or packages (the group exposes none); every imported row's `source` is the
   partner's; Swagger's "Try it out" with the operator's token round-trips an import and an export.
2. **PR2 — calendar** (`masi` #40 + `site`): changeset 031 (`calendar_event`; 029 and 030 went to PR1b), `CalendarService`, `GET /calendar`
   with the day counts, the three views, event create/edit/outcome, deadline markers from `expires_at`; the
   weekly digest lists the coming week's events. Invariant: the day cell's three numbers equal the day's log
   filtered by kind; an event's outcome writes the activity; DST week (2026-10-25) renders 25 hours right.
**What measuring the live registry before PR3 found (2026-09-23), and what it changes:**

| measured | consequence |
|---|---|
| All 10 Töötukassa contacts held a **ROT13-rotated e-mail** (`neab@rssrg.rr` = `arno@effet.ee`); all 118 cv.ee ones plain | identity is matched on e-mail, so PR3 was blocked on unusable addresses — fixed first in masi #42 (collector turns it back only where the arriving TLD is not real and the turned one is; changeset 032 for the rows already stored) |
| **96 of 128** contacts belong to companies with **no website recorded** | the domain-mismatch rule for spotting an agency recruiter applies to a quarter of them at best. Company enrichment (careers URL, website) is a **prerequisite** of that signal, not an optional extra — PR3 ships the rule but reports its own coverage, and the plan's "agency share" question cannot be answered until enrichment runs |
| **No e-mail and no name appears at two companies** in the 128 | the cross-company edges the graph exists for are not in the collected data at all. They come from the register dump (board members, `REPRESENTS`) and later the inbox — so PR3's value rests on the register import, and a person page will look thin until it lands |

3. **PR3 — persons and ties** (`masi` + `site`): changesets 030 (`person`, `person_company`, `contact.person_id`),
   the migration of contacts into persons (identity by e-mail, else name + company), `ariregister` keeping the
   persons' rows (`REPRESENTS` ties), agency detection (EMTAK 78.x, name pattern), the domain-mismatch rule on
   listing contacts, the person pages, the company "People" card, `TALKED_TO` from operator activities.
   Invariant: one e-mail is one person across companies; a register person on two boards shows both ties
   with `REGISTER` evidence; a tie is never shown without its evidence.
4. **PR4 — the inbox** (`masi` + `platform` + `infra`): a masi inbound address on the existing Resend domain,
   the webhook (monitor's `ResendWebhookService` as the pattern; masi verifies Svix signatures itself), sender →
   person by e-mail (a new person otherwise, company by domain when known), `RECEIVED_MESSAGE` with the subject
   as summary and the text as detail, attachments dropped. Invariant: a mail from a known recruiter lands on
   their person and the company's log; an unknown sender makes a person without a tie; a replayed webhook
   writes one row.

Later: ICS subscription; sent mail via a BCC address; reminders (a mail before an interview); a person's
"last contact" ageing on the company list.

## Verification (revert checks)

| mechanism | fixture | revert |
|---|---|---|
| COLLECTED per new job | two boards, one job → one COLLECTED | the write moved out of the ingest transaction |
| APPLIED on review | NEW → APPLIED → one row with `applied_at` | the write removed |
| Day counts | rows at 23:30 and 00:30 Tallinn on the DST night → the right days | the zone set to UTC |
| Event outcome → activity | INTERVIEW event marked DONE → one INTERVIEW activity with the event's job | the write removed |
| Person identity | the same e-mail on two companies' listings → one person, two POSTED_FOR ties | identity by name |
| Register ties | a dump record with two board members → two persons, REPRESENTS, evidence = the code | persons dropped |
| Agency by EMTAK | 78.10 → agency true; 62.01 → false | the code list emptied |
| Domain mismatch | contact `anna@stafferty.ee` on a Bolt listing → the person's company is Stafferty, tie POSTED_FOR Bolt | the rule removed |
| Inbox | a signed webhook payload from a known e-mail → RECEIVED_MESSAGE on that person; a bad signature → 401, no row | signature check removed |
| Scoping | a second JOBS user sees no activity, event or person note of the first | the filter removed |

## Log

- **PR1 as built (masi #37, site #20), 2026-09-22.** `activity` carries `contact_id` until PR3 brings persons (PR3
  migrates it to `person_id`); the day counts live at `GET /activity/days` (counted in the database per Tallinn day)
  rather than inside `GET /calendar`; kinds shipped only with their writers (COLLECTED, PREPARED, APPLIED,
  the operator's seven) — SCHEDULED comes with PR2, a mail origin with PR4; a plain reply on a package is no row (a
  message received has one source: the operator, later the inbox); reposts stay in `lifecycle_event` (the job's
  history) and are not doubled into the log; a merged job's package and operator rows follow the survivor. The
  test-quality audit (27 revert checks red) found one defect: a **company** merge deleted the stub and the FK set
  the log's `company_id` to null — `ActivityRepository.repointCompany` now runs in `CompanyService.merge` before
  the delete, as jobs, contacts and aliases already did. Merged 2026-09-22 (masi #37, site #20).
- **PR1b as built (masi #39), 2026-09-22.** As planned, with these choices: the partner is told apart by the token's
  `azp` (no custom `partner` claim, so onboarding is a plain Keycloak client + the `MASI_PARTNER` realm role); the
  `@RequirePermission` aspect gained `or = {…}` so `MASI_PARTNER` or `JOBS` suffices; persons land in `contact`
  (PR3 migrates them to `person` with `PARTNER` evidence); no `format=ndjson` — paging at 500 a page covers bulk; no
  2 MB body cap — 500 items × clipped fields bounds a call; no per-partner `dailyRequestCap` yet — 60 a minute in the
  process is the guard, a daily cap comes with the first partner whose volume warrants it; the changes feed merges
  first-seen, `lifecycle_event` (JOB) and `merged_at` in memory, `next` = the last instant returned (two changes at one
  instant across a page boundary re-ask from a minute earlier). Swagger: bearer scheme + groups *Partner API* /
  *Operator API*, only where `MASI_API_DOCS_ENABLED` (test). The reviews then changed four things: the **changes feed
  is one table** — `lifecycle_event` gained OPENED and MERGED (changeset 030 backfills them) and the ingest writes each
  listing's rows with its own commit instant, so the feed pages by `(at, id)` and a follower cannot lose what a
  ten-minute run committed after its poll; a withdrawal closes **every** listing the caller has on the job and follows a
  merge to the survivor; a partner corrects **only blanks** on a company and **only its own** contacts; the client id is
  carried verbatim (no slugging, so two clients cannot become one source), reads and writes share one minute budget, a
  **2 MB body cap** (413) is applied before parsing, and an import skips the duplicate sweep (the collector runs do it).
  The test audit (65 revert checks, 12 of which bit nothing) then found three more: a body with no declared length was a
  400, not a 413 — the cap now READS the body itself and refuses one byte past it, so nothing oversized is parsed and no
  override of Spring's handler is needed; a partner correcting a person's e-mail onto a colleague's was a 500, now a 400;
  a masked rival's listing still carried the link that named them, so a masked listing has no link. Nothing had ever read
  `GET /partner/persons`, so both privacy filters it promises could have been deleted with the suite green — they are
  pinned now. **Merged 2026-09-22 (masi #39).**

- **PR2 as built (masi #40, site #21), 2026-09-23.** `calendar_event` is changeset **031** (029/030 went to PR1b); the
  view answers a range at once — the day numbers, the bookings touching it, the postings closing in it (read live from
  the open listings, never copied) — and **states which kinds each number counted**, so the page links a number to
  exactly those rows and keeps no copy of a list that lives in masi. A booking says so as `SCHEDULED`; one marked held
  writes its own kind at the hour it was booked for, once per booking however the kind is later corrected; a call-off
  writes nothing and a delete leaves what happened. An all-day booking IS its day in the operator's zone, and the length
  limit is that day's own length — 2026-10-25 in Tallinn is 25 hours. Bookings follow a job merge and a company merge,
  as the log's rows do. The weekly digest names the week the reader is about to have. `GET /activity` now takes several
  kinds at once. The page is month/week/day with lanes for events that share an hour, spans drawn on every day they
  cover, and the phone's month reduced to dated bars; `GET /calendar/job/{id}` has no caller yet — the job page's card
  comes with PR3.
- **What the three passes over PR2 cost and bought.** Architecture: bookings orphaned by both merges, an all-day flag
  that meant nothing, a meeting counted twice when its kind was corrected, day numbers linking to the wrong rows.
  Rendered UI (measured in Chromium, not read): the event form pushed the page 280 px sideways at 390 and left the title
  field 26 px; two events at one hour were drawn exactly on top of each other; a three-day booking showed on one day and
  one running past midnight became a 10 px sliver. Test audit (52 revert checks): the job-merge test did the repointing
  itself and passed with the production call deleted; the site test mocked the very list that can drift; the deadlines
  query, the multi-kind filter, the digest's week-ahead block and the long-text cut were all unprotected; nothing
  rendered the calendar through the app's routes. **All fixed in the PRs.**
- **Measured live, the hour it shipped (masi #41).** Six weeks of the test registry hold **205** closing postings —
  against a `MAX_DEADLINES` of 200. The operator's first month view would have dropped five with nothing said, and the
  cell's "+N more" would have undercounted with them. The cap is there to bound a pathological range, so it now sits far
  above a month's worth. The number looked generous in the abstract and was wrong against one query of the real data.
- **Open, and honest about it:** `src/index.css` is invisible to vitest — an empty stylesheet passes all 478 tests — so
  every layout defect this arc found would ship green. The headless harness catches them but runs nothing in CI.
  Promoting it (`npm run test:layout` in Chromium, asserting no overlap, no sideways scroll, aligned columns, no tap
  target under 20 px) is its own change, and belongs before the next page this size.

- **PR3a as built (masi #44), 2026-09-23.** `person`, `person_company` and `contact.person_id` (changeset 033), with
  the address as the identity — one address is one person wherever they appear — and a name recognising someone only
  among the people already tied to that company. Every tie carries the proof that made it (`TieEvidence` LISTING,
  REGISTER, MAIL, PARTNER, OPERATOR) and a role is only claimed by evidence that can say it: `POST /persons/{id}/ties`
  refuses `POSTED_FOR` and `REPRESENTS`, which are a listing's and the register's to say. `ContactOrigin.evidence()`
  owns the mapping, so a contact a partner sent makes a `PARTNER` tie and a register row a `REGISTER` one.
  - **The backfill was written twice, and the two disagreed.** The first version was a SQL changeset that restated the
    recognising rules. Review against a throwaway PG 17 found three faults my tests had not: grouping by e-mail *and*
    name violated `uq_person_email` (a boot failure), a missing `company_id is not null` guard was a second, and a
    name-link without a company fabricated a cross-company tie. The rewrite was audited and still ignored the
    shared-mailbox list and `contact.kind`, so one agency desk on two employers' listings would have become one
    person tied to both. **The SQL is gone.** `PersonBackfill` walks the unlinked contacts by id cursor at
    `ApplicationReadyEvent` and puts each through `PersonService.adopt` — the same rule a newly collected contact goes
    through — in a transaction of its own, so a row that cannot be placed costs one row and not the pass. A migration
    that restates a rule the code already owns is two rules; this is the lesson from 032 in a second form.
  - **Two defects the new tests found.** A contact who asked not to be written to became a person who could be
    (`doNotContact` was not carried onto the person, and a later sighting must not undo it); and the operator's
    `PATCH /contacts/{id}` onto a colleague's address at the same company answered 500 where the partner API already
    refuses it with 400 — the same guard now stands on both.
  - **What the architecture review found (ten defects).** Three would have reached production: `CompanyService.merge`
    repointed jobs, contacts, aliases, activities and bookings but **not `person_company`**, and `fk_tie_company`
    cascades — so the automatic register dedupe would have deleted every proof about whoever posted for the stub;
    the backfill ran inside the `ApplicationReadyEvent` listener, where a throw ends `SpringApplication.run` and the
    same rows are waiting at the next boot, so one bad row meant an app that would not start; and `DELETE /contacts`
    still claimed to erase personal data that now also sat on the person row, which nothing could reach. The rest: a
    racy read-before-write deciding a tie (the index arbitrates now, which also removed a full tie scan per capture);
    the evidence→role rule living in one controller while creating a contact by hand made the tie that controller
    refuses; a register row claiming a posting it never published; an unvalidated note running past `varchar(200)`
    into a 500; a 201 for a tie that was not created; an `agency` filter that could only ever return nothing because
    nothing writes the column (the **operator** sets it now — the register import keeps EMTAK 62/63, so no collector
    ever can); two narrowings materialising unbounded id sets into `IN (...)`, now `EXISTS` subqueries; a patch that
    could orphan a person; and a search for `a_b` that silently wildcarded.
  - **What the test audit found.** **Six mechanisms could be deleted at once with the whole suite green.** The worst
    was a fixture doing two jobs badly: the merge test pinned its person to one company, so the survivor could never
    already hold the same proof and the repoint could never collide — which is what `dropProofsTheSurvivorHolds` is
    for. Every contact captured without a listing id has a null `evidence_ref` and `uq_tie_proof` is
    `NULLS NOT DISTINCT`, so that collision **rolls the whole ingest back** and leaves two rows for one employer for
    good — the ordinary register and partner path. Two tests could not see what they were named for: the cursor test
    asserted only that the pass ends, but `seen` rises whether the cursor moves or not, so a cursor stuck at zero ends
    too after grinding one page 20 000 times; and "the second caller is not harmed" opened its own transaction, so
    there was no caller to harm. Three things nothing could write were **deleted rather than tested**:
    `person_company.until` had no writer, `TieEvidence.MAIL` no producer until PR4, and the LIKE escaping on the name
    branch was unreachable because `Normalizer.person` folds every non-letter to a space first.
  - **Live in schnappy-test 2026-09-23 15:05 (12:05 UTC), and every predicted number came out.** The shape was taken
    from the database *before* the deploy and checked after: **128 people** (114 recognised by address, 14 shared
    desks by name with a null `email_norm`), **0** contacts left unlinked, **0** never put through the rule, **128**
    ties all `POSTED_FOR`/`LISTING` with the listing that showed them, **0** people at two companies — today's
    registry has no cross-company edge, exactly as the pre-flight said. Changeset 033 ran four changesets clean
    (`Update has been successful`, 0 restarts), and the log shows `Started Application in 42.687 seconds` at 12:05:13
    with the pass logging at 12:05:18 on thread `task-1`: after readiness, off the main thread, which is the fix the
    architecture review asked for, visible in production. `/api/masi/persons` answers 401 through the gateway.
  - **Thirty-one revert checks red in all.** Five tests on this branch passed for the wrong reason and were rewritten:
    one did the production call itself; one went through a column the normaliser folds, so the wildcard could never
    show; one "refused" contact was never refused; one derived its loop from the very allow-list it was checking, so
    narrowing the list narrowed the loop; and one asserted that both people **survive** a merge, the opposite of the
    forgetting it was named for.
  - **Eight revert checks red**, each naming its test: `fill` overwriting what the row already says; the name asked
    before the address; one desk deleted from the list; the subdomain arm of `domainOf` (the hiring-platform case,
    where a company whose site *is* its ATS would read every outside recruiter as its own staff); the `agency=false`
    removal turned into a no-op; the page ceiling; the contact address guard; `doNotContact`. The list is pinned by
    name as well as looped over — deriving the loop from the constant proves each entry works but lets an entry be
    deleted with its own assertion.

- **PR3b as built (masi #45), 2026-09-23.** The register's card of who may represent a company, read for the companies
  masi has met, recorded as `REPRESENTS`/`REGISTER` ties dated by the appointment — which PR3a's rule already produces,
  so this is mostly a collector. The register publishes `isikukood_hash`, a hash of the ID code rather than the code,
  so a consumer can follow a person between companies without holding anyone's ID; it becomes `person.register_id`
  (unique) and outranks an address, because a card never shows one. That is what gives masi its **first cross-company
  connections**.
  - **Measured from the real 1 GB dump, and four things changed because of it.** Role codes across the whole file:
    `JUHL` 450 210, `KISIK` 14 640, `PROK` 1 973, and **no supervisory-board role at all** — the default had been
    `JUHL,NOUK,PROK` and `NOUK` does not exist, so it would have shipped dead like the two things PR3a deleted.
    **8 769 of 497 598** entries carry no hash (foreign members, whose unhashed national code masi will not store), so
    they fall back to a name within one company. Of 3 196 cards read in full, **none** had an ended term: the dump
    publishes current entries only. A legal person **never** holds `JUHL` or `PROK` (524 338 entries), so that guard
    is reachable only through config — `KISIK` is 14 018 legal entities — and is tested the way config would reach it.
  - **"Companies masi knows" had to be redefined.** masi holds **28 134** companies (the whole EMTAK 62/63 import) but
    has engaged with **156**: posted a job, had someone captured, or an operator mark. The runner hands a
    companies-scope source only the engaged codes, so a national dump is read past rather than stored.

  - **The architecture review, then the test audit — and the audit found my fix for the review's worst defect had
    introduced two more.** The review's critical: a register key that *missed* fell through to a name match, so two
    board members sharing a name at one company (a father and son on one board) fused into one person, the second
    key discarded for good. My guard accepted a weaker match only from a row "not keyed as somebody else" — and
    checked the null on one side only. Once the register keyed a listing's contact row, the next ordinary listing
    capture (unkeyed) was refused its own row, inserted a duplicate, broke `uq_contact_company_email`, and from then
    on **no listing of that source would ever close** (a run with problems counts no misses). One level down the same
    check made one address stop being one person. The rule that is right: **a conflict is both sides keyed and the
    keys differ; a key missing on either side is no key.** Both round trips are tests, written first and seen failing
    with the constraint violations.
  - The review's other two criticals: `fill` could write across companies an address another person held
    (`uq_person_email` at flush — same run-poisoning), and there was **no retention story** — a delete lasted until
    Sunday, and a `REPRESENTS` tie was a permanent claim the source had stopped making. Now: an erasure leaves a
    key-only suppression record the register cannot undo (the operator's delete only — a company merge is
    housekeeping and bans nobody); a card that stops naming someone **ends** the tie, a card naming them again
    **reopens** it, and `until` reaches the page; a card masi could not fully place retires nobody (fail closed).
  - Also from the audit: an empty `lopp_kpv` would have dropped every board member in the country, because it was read
    `!= null` while the dump already writes its sibling as `""`; the stream-safety caps the zip-bomb review cited were
    asserted by nothing; the shared-key test passed on `[null, null]`; the timing test timed a copy of the loop, not the
    collector — now **378 385 cards in 2.9 s through the shipped class**; and nothing walked source row → runner →
    collector → ties end to end. **Thirty revert checks on the audit's fixes**; the two that stayed green were a test
    that ran the one harmless order, and a `keyIsFree` guard that **cannot fire** (the keyed lookup always reaches the
    key's holder first) — deleted rather than tested.
  - From the live registry, a PR3a defect: `recognised_at` was set only by the backfill, so every contact recognised
    at capture — the first new contact after the deploy among them — claimed nobody had looked. Fixed here.

- **THE GAP THAT CAPS PR3b, AND THE NEXT PR (measured 2026-09-23).** Of the 156 engaged companies only **41 have a
  registry code**. The other 115 include **every one of masi's biggest employers**: Bolt (86 jobs), Wise (68), Luminor
  (22), SEB, Kaitseressursside Amet, Playtech, Skeleton, Bondora, Bigbank, Swedbank, LHV, Inbank. They are not missing
  by accident — **the register import keeps EMTAK 62/63, and these companies are registered under finance (64),
  transport (49/52) and gaming (92)**, so their register rows were never imported at all. What masi holds instead are
  unrelated lookalikes: `Wise Estonia OÜ`, `WiseLabs OÜ`, `SWEDBANK SUPPORT OÜ`, `Sebcode OÜ`, `Sebi Tech OÜ`. Only 4
  of the 115 even have a website, and 1 of those matches a register row by domain; a name-prefix rule matches 18, of
  which 16 are unambiguous — and **matching "Wise" to "Wise Estonia OÜ" would attach the wrong registry code, the
  wrong board and the wrong EMTAK to the company holding 68 jobs**, which is the fabricated connection this whole area
  exists to avoid. Consequence: every register fact — EMTAK, size, city, board members, the agency flag — is invisible
  for the companies that matter most, and no amount of name cleverness fixes it. The import filter is what has to
  change, and the match has to be **confirmed rather than guessed**. This is worth more than PR3c's pages and should
  come before them.

## Status

IN PROGRESS 2026-09-23 — PR1 (masi #37, site #20), PR1b (masi #39), PR2 (masi #40, site #21) and **PR3a (masi #44)**
all MERGED and live in schnappy-test. Next: **PR3b** — the register's board members as `REPRESENTS` ties, and EMTAK
78.x rows kept for companies masi already knows, which is what will make `company.agency` mean something beyond the
operator's own mark. Then PR3c (person and company pages) and PR4 (inbox). The CSS layout test and the job page's
bookings card are carried into PR3c. Enrichment and analysis batching (094 Later) queued behind them.
