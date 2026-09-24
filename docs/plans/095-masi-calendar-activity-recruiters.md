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
| `activity` | id, user_uuid, at, kind (`COLLECTED`, `ANALYSED`, `PREPARED`, `APPLIED`, `SENT_MESSAGE`, `RECEIVED_MESSAGE`, `CALL`, `INTERVIEW`, `OFFER`, `REJECTED`, `NOTE`, `SCHEDULED`), origin (`SYSTEM` / `OPERATOR` / `MAIL`), job_id, company_id, contact_id (the person through `contact.person_id`, see PR3c), package_id, summary (≤ 300), detail (text), created_at | append-only; `at` is when it happened (a call yesterday logged today keeps yesterday); SYSTEM rows are written where the thing happens (ingest: one `COLLECTED` per new job; review `APPLIED`; the tuner `PREPARED`) |
| `calendar_event` | id, user_uuid, kind (`CALL`, `INTERVIEW`, `DEADLINE`, `FOLLOW_UP`, `OTHER`), starts_at, ends_at, all_day, title, job_id, company_id, contact_id, location (a room, a link), notes, outcome (`NONE` / `DONE` / `CANCELLED` / `NO_SHOW`), remind_before, created_at, updated_at | the operator's own; a posting's `expires_at` is shown as a deadline marker without a row |

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
   **Operator, 2026-09-24:** build masi's side only for now — the webhook, verified and tested offline on
   recorded signed payloads; the Resend endpoint (and its `whsec_` secret) waits until masi runs in production. The
   address is on a **dedicated subdomain** (its own MX to Resend: a Porkbun DNS change at go-live), so masi takes
   the mail sent to its configured addresses and ignores the rest of what Resend delivers.

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

- **PR1 as built (masi #37, site #20), 2026-09-22.** `activity` carries `contact_id` (PR3c decided to keep it: see the
  PR3c entry below — the person follows from the contact); the day counts live at `GET /activity/days` (counted in the database per Tallinn day)
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
  - **Merged (masi #45) and deployed 2026-09-23 21:23 (18:23 UTC).** All five 034 changesets ran clean, 0 restarts;
    every object present; the source seeded **disabled** at `0 30 21 ? * SUN`. Nothing about real people changed —
    0 suppressions, 130 people, 0 unlinked. The `recognised_at` fix is not yet seen on a live row: contacts 130 and 131
    arrived before the deploy under the old code, and none has arrived since; the next capture is the first proof.
    **Not yet done: the first enabled run** — the real 1 GB dump against the 41 companies masi has met.

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

### PR3d — the register covers every business, and a match is confirmed rather than guessed

**Operator, 2026-09-23:** *"we cannot limit IT vacancies just to IT companies, it can be any business."* The unit of
interest is the vacancy, not the employer's industry: a bank hiring a Java developer is as relevant as a consultancy.

Checked first: **nothing filters or down-ranks a vacancy by its employer's EMTAK** — the code is only stored and passed
through, so jobs from any business are already collected. The IT assumption bites in one place: the register import
keeps EMTAK 62/63, so register facts, board members and the agency flag are missing for every employer outside IT.

**Measured against the whole country's register (377 146 distinct names), with masi's own `Normalizer`:** of 156
companies masi has met, 115 have no register row, and they hold **486 of 599 jobs (81%)**. Of those 115: **76 exact
unique** name matches (263 jobs), **10** where the name is a prefix of exactly one company (44), **7 ambiguous**
(`Wise` → 45 candidates, `SEB` → 7, `LHV` → 6), **22 with no match** (88 — foreign-registered like `Luminor Group`,
`Yolo`, `Betsson`, or brands like `TEHIK`, `TalTech`).

**And "exact and unique" is not "correct".** `Bolt` (88 jobs) matches exactly one register row — **`Bolt UÜ`**, an
unrelated limited partnership. The employer is **`Bolt Technology OÜ`** (beside `Bolt Services EE OÜ` and `Bolt
Operations OÜ`), whose longer legal name does not match the bare brand. An exact-name auto-match would have attached
88 jobs, their register facts and — through PR3b — their board members to a stranger, with full confidence.

**Design.**
1. **A country-wide register index**, separate from `company`: a lean `register_company` row (code, legal name,
   `name_norm`, legal form, status, EMTAK, city, size band, website) for every entered company, with **no activity
   filter**. Reference data to resolve employers against — public business data, not people — so `company` stays
   "the companies masi deals with" and does not become the population. Filled by the `ariregister` run it already
   streams (one download, not two), through a sink the runner provides, in batches; the 62/63 discovery set it returns
   today is unchanged.
2. **Matching produces candidates, and attaches only what is strong.** Strong: an exact `name_norm` match to one
   company **and** the listing published a legal form (the board gave the legal name: `Bigbank AS`, `LHV Pank AS`), or
   an exact match to a public body (a code in the 7xxxxxxx range, whose names are unique institutional names). Never
   auto-attached: a partnership or sole trader (`UÜ`, `TÜ`, `FIE`) — the `Bolt UÜ` shape. Everything else waits for the
   operator.
3. **The operator confirms** through `GET /companies/{id}/register-candidates` and `POST /companies/{id}/register-match`
   (the page comes with PR3c). A confirmed code flows through the existing register machinery: facts, board members.

**As built (masi #46), and what the two reviews changed.** The index and the matcher as designed, plus: a placement
**never merges on its own** (making two companies one deletes one — the operator's call); every placement is written to
the activity log; a placement records what it replaced and can be **taken back**, restoring exactly that — the register's
website brings a domain, and a domain is an identity key, so left behind it routed another company's listings in — and
the operator's no is remembered so the weekly pass does not place it again. The candidate list marks forms that are
never employers and names a company masi already holds (choosing it merges).
- **The architecture review ran the rule over the real register** and found `Revolut Ltd` attached to `Revolut MTÜ`, a
  non-profit, and `Nitor Oy`, a Finnish IT consultancy, to `Nitor OÜ`, a leasing intermediary with no staff: a foreign
  legal form had been read as proof of the registered name. The rule is now a positive list read from the register's
  own forms (counted over the country: OÜ 293 490, KÜ 25 664, FIE 24 630, MTÜ 23 048, UÜ 3 659, AS 2 039 …), failing
  closed: the board's form must be Estonian, **equal** the registered form, and be an employer's (OÜ, AS, SA, FIL, SE);
  public bodies by the register's form (KOVAS, TRAS, AVOIG); names equal once a form is taken off their start and end
  only. It also found a merge losing the operator's blacklist, note and rating — pre-existing, but reached now.
- **The test audit found the critical one:** deleting the runner's "only after a register read" guard left all 866 tests
  green — and without it every job-board run would prune the index to nothing. Also: a placement taken back came back
  the next Sunday; taking one back left the website and its domain behind; and the form reader gave different answers
  on different JVM starts (`Map.ofEntries` order is randomised per start, and two same-length forms tied), so the same
  employer was placed on one pod and not the next. **Forty-four revert checks across the two rounds**, every one red
  against a build that compiled; the forms the rule names are checked against the real dump through the shipped
  collector.

Why this beats PR3c now: PR3b's board members reach 41 companies; every match here adds one, weighted towards the
employers that actually hire.

**Merged (masi #46) and deployed 2026-09-24 01:30 (22:30 UTC).** The three 035 changesets ran clean in 167 ms, 0
restarts; `register_company`, `register_placement`, `register_rejection` and `ix_register_company_name_norm` exist;
health 200, the candidate and person routes 401 without a token. The index is empty until the next **complete**
`ariregister` read (Sunday 20:00, or the operator's Run now) — the guard that keeps a job-board run from pruning it.
Still to measure on that first run: its duration against the 840 s deadline (104–125 s expected), the WAL a weekly
rewrite of ~369 000 rows costs (the database is 24 MB beside 666 MB of pgdata, mostly WAL — an upsert of changed rows
only, with an anti-join prune, is the follow-up if it matters), and what the pass places and what it leaves as
candidates.

### PR3e — the register marks employment agencies; the operator's word still wins

PR3b moved EMTAK 78.x agencies out of scope because the 62/63 import could not reach them. PR3d removed that wall:
a placed company carries the register's main line of business. **Measured on the dump (EMTAK 2025 / NACE Rev. 2.1):
2 015 entered companies have a current main activity in division 78** — labour hire 1 358 (`78201`/`7820`),
placement 394 (`78101`/`7810`), other provision of people 263 (`78209`/`78301`). Among the companies masi has met,
Grafton Estonia OÜ, Barona Eesti OÜ and Brandem Baltic OÜ match exactly, and `M-Partner` is a candidate for
`M-Partner HR OÜ`. None of the four is placed yet, so none is marked until a placement is made.

**As built (masi #47).** `company.agency` is a stored generated column,
`coalesce(agency_mark, registry_code is not null and emtak_code like '78%', false)`. EMTAK reaches a company by
several paths, one of them a single SQL statement over every coded company, and a rule restated on each path would
drift. The operator's word is in `agency_mark`: either way it overrules the register, and `PATCH
{agencyFromRegister: true}` takes it back. The upgrade carried every earlier `agency = true` over as a mark (0 rows
live). The name-pattern fallback in the source table above was **dropped**: a name is not the register's word, and
the operator's mark covers the recruiter registered under a consultancy code. **Rollback order: the database first
(`rollbackCount 2`), then the image** — the old image writes `agency`, and Postgres refuses a value for a generated
column.
- **The architecture review** found the two writers of a company's line of business disagreeing. The IT import
  recorded the 62/63 activity that brought a company in, and the refresh then set its main activity. So labour hire
  with a software sideline was not an agency from the import until the refresh, and for a whole week whenever the
  refresh did not run. Both now record the main activity. It also found that a partner's EMTAK on a code-less
  company would mark it for good, never refreshed; the rule now needs a placement. And a mark could not be taken back.
- **The test audit** ran 30 reverts. Four left the suite green: a merge dropping the operator's no, the tie badge,
  the division's neighbours (`7%`, `%78%`), and a take-back to a prior line of business. All four are guarded now.
  My own first merge test passed without merging, because the brand's name normalised to the holder's. It was fixed
  and proven by the revert it had missed. **19 revert checks of mine over two rounds**, every one red against a build
  that ran; the changeset's rollback is tested too.
- Left as is: an unverified race in which an edit loaded just before the refresh writes the old EMTAK back. The window
  is one request, and the next refresh heals it.
- **Merged (masi #47) and deployed 2026-09-24 03:00 (00:00 UTC).** Both 036 changesets ran clean in 167 ms, 0 restarts;
  `agency` is `GENERATED ALWAYS` with the expression above; 28 134 companies, 0 agencies and 0 marks — every coded
  company still carries the 62/63 code the old import wrote. The next complete register read writes the main activity
  (and fills the index), and that is when the first agencies appear; count them then. The company page (PR3c) has to
  show whose word the flag is (`agencyMark` null = the register's) and offer "let the register decide".

### Found while previewing PR3c: a no-reply address is nobody (masi #48)

The preview of the person pages, built from the live rows, showed Bolt's only "person" as `noreply@cv.ee`: cv.ee's own
mailbox, sent for every employer whose recruiter it hides. The shared-mailbox rule knew `info@`, `jobs@`, `hr@` and not
the no-reply family, so the second employer listed that way would have been filed under Bolt's person, with a tie between
two companies that never met (the failing test: both captures returned person 36). Fixed: `Normalizer.noReply` in the
identity rule itself; capture keeps no such address; the operator's and the partner's edits refuse one with a 400;
a partner item that was only one is refused in its report line (it had made the import 500); the rows stored before
lose it at start through the same Java rule, one targeted update per row, contacts and people each on their own, a row
that without its address duplicates its twin folded into it. **Two reviews, 24 revert checks.** Live 2026-09-24 06:28
(03:28 UTC): "2 no-reply address(es) forgotten" — contact 123 and person 122 kept, linked, no address; 0 left.

### PR3c — the people and company pages (masi #49 + site)

**Operator, 2026-09-24:** People replaces Contacts on the company page ("ok to replace contacts") — two lists of the same
people drift; `/masi/contacts` redirects to `/masi/persons`.

**`activity.contact_id` stays; the person follows from it.** The migration to `person_id` the PR1 entry promised is not
done, deliberately: the contact is the more specific record (this person at this company), a contact re-recognised as
someone else takes its history with it, and `GET /activity?person=` is a subquery on `contact.person_id`. The cost is that
deleting a contact would drop its rows (`SET NULL`), so every delete of a contact as another's duplicate — a company merge,
the no-reply fold — hands its log rows and bookings to the one that stays; a register take-back's board contacts keep
`SET NULL` (placed by mistake). A person merge, when one exists, repoints `contact.person_id`.

masi #49: `GET /activity?person=` and `personId` on every row; `POST /activity` with a person and a company writes to
their contact there (400 when they are not a contact of it — a tie first); a row with only a contact is about the
contact's company; `GET /companies/{id}/register-match` — the placement and what taking it back restores, 204 when none
or when its code is no longer the company's.

**PR3c as built (masi #49, #50; site #22).** The people list and person page, the company's People card (Contacts
removed; its desks and addresses listed apart), the agency line, the Register card. Reviews found, across three rounds:
- **"Do not contact" set on a person was never enforced** — the letter's addressee and the partner export read the
  contact row. Copying the flag onto the rows (first fix) held only for rows present at the time. Final shape: the rule
  is read, in one place (`ContactRepository.WRITABLE`: neither the row nor its person refused), by both readers; a
  contact's PATCH of it is the person's word; a flag set on a desk moves to the person the desk turns out to be, and off
  the row (changeset 037 for rows already there). `ContactDto.doNotContact` is the answer, not the column.
- **A typed registry code was placed without confirmation** (a merge nothing takes back) — now looked up
  (`?code=`) and confirmed like a candidate.
- **"The register has no company by this name"** while the index was empty or its prefix list truncated — the
  candidates answer `{indexed, truncated}`; `indexed` is a mark (`register_index_read`) the refresh sets only after a
  whole read written in full. **Live: not indexed until the next complete `ariregister` read.**
- The confirmation pushed the page 50 px sideways at 390 px (measured headless); "Do not contact" submitted the form;
  the page did not reload after a placement; the log link was offered on ties without a contact; the typed person
  fields could not be cleared; a blank name was accepted.
- Test audits: ~50 green mutations found and pinned across the three PRs (the real API functions, the routes, a
  stateful parent for the card, sort edge cases, the export's count query). **~110 revert checks**, all red.
- **Live in test 2026-09-24:** masi #50 at 08:45 (05:45 UTC) — changesets 037 ×2 clean, 0 stranded row flags,
  `register_index_read` empty until the next complete register read; site #22 at ~09:00 — the people pages, the
  company's People and addresses cards and the Register card served from the new bundle.

**PR3c-2 as built (site #23, masi #51, site #24): the job page's bookings, and what a merged job sends on.**
- **The card:** a Bookings card on the job page, the first caller of `GET /calendar/job/{id}`.
  - It lists bookings oldest first. Each opens its day in the calendar (the day in Tallinn, `&job=` kept).
  - "Book a call or an interview" opens the week with `?job=`.
  - The bookings load with the job: arriving late, they had pushed the note and its Save button 278 px down at 390 px.
- **The review found the merge hole.** A booking, log row or note for a merged job went where no page shows it. masi #51 closes it:
  - A booking or log row follows `mergedIntoId` through any chain (`JobRepository.survivorOf`, bounded at 20 hops). It takes the survivor's company.
  - The job is read under a share lock (`findForShare`), so a merge committing meanwhile is waited for and followed (a latch test on `pg_locks`).
  - A note on a merged job is 409.
  - `JobDto.becameId` names where the chain ends. `/activity?job=` and `/activity/days?job=` read a merged job as that job.
- **Site #24:** a merged job's page has a read-only note (the note written before the merge stays), no Save, and every link going to `becameId`.
- **Revert checks:** 7 + 7 on #23, 12 on #51, 12 on #24, all red.

### PR3f — AI matching: a verdict per requirement, each citing the master's evidence

Operator, 2026-09-24: "we need AI matching!". The word scorer (`MatchScorer`) does not catch:
- **synonyms:** "K8s" or "container orchestration" against Kubernetes;
- **implied skills:** Spring Boot means Java;
- **concepts:** "distributed systems" against a sharding achievement;
- **years, seniority and language levels** a requirement states;
- **any posting not in English:** 136 of 519 open postings are "another language, no score" live, because the analysis keeps the posting's own language.

It also passes "ten years of Java in avionics" on Java alone.

**Shape: the model judges, the code verifies and counts.**
- **Input:**
  - *Requirements:* the requirement list the analysis already stores. Must-haves, keywords and nice-to-haves are numbered `M1…`, `K1…`, `N1…`, so the set is fixed by the analysis, not by the call.
  - *Master:* the master as an evidence catalogue rendered by code from `CvModel`, byte-stable per version, each item with an id derived from its order: skills `S1…`, roles `R1…`, achievements `R1.A1…`, education `E1…`, certifications `C1…`, languages `L1…`, positioning `P`.
- **Output, structured, per requirement:**
  - `id`;
  - `verdict`: MET, PARTLY, NOT_MET, or NOT_A_CV_THING;
  - `evidence` ids;
  - `kind`: SKILL, YEARS, LANGUAGE, DEGREE, DOMAIN, SENIORITY or OTHER;
  - for YEARS, `years` and `subject`; for LANGUAGE, `language` (ISO 639-1) and `level` (CEFR);
  - `english`: the requirement in English, for a posting in another language;
  - `reason`: one line.
- **The code verifies, and fails closed:**
  - Every requirement must be answered exactly once, with no unknown ids. Otherwise the whole answer is refused: the attempt counts and the word score stands.
  - An evidence id not in the catalogue is dropped. A MET or PARTLY left without evidence becomes NOT_MET.
  - YEARS is decided by the master's dates when the subject is found in roles (tech, title, achievement keywords). Overlapping roles count once. At least the required years is MET, at least half is PARTLY, below that NOT_MET; the evidence is those roles.
  - LANGUAGE is decided by the master's languages list when the language is recognised. At or above the level is MET, one step below is PARTLY, anything lower or not listed is NOT_MET.
  - The code only decides what it can compute. Everything else keeps the model's verdict, which must cite evidence.
- **The score** uses the word scorer's formula and weights (must 0.60, keywords 0.25, nice 0.15, `FULL_LIST` 3): MET = 1, PARTLY = 0.5, NOT_A_CV_THING left out. The number can be re-derived from the stored verdicts.
- **Storage:**
  - `job_match` gains `method` (WORDS | AI) and `ai_attempts`.
  - `detail_json` keeps the old fields, derived, and gains `requirements[]`: each verdict with its evidence resolved to labels ("Nortal · Senior Engineer 2019-03 – 2022-06: cut p99 …") and `decidedBy` (model | dates | languages).
  - The free word score is written at once and stays until the AI row replaces it. The word refresh never overwrites an AI row.
  - A new master version is scored by words at once and by AI through the lane.
- **Lane and budget:**
  - The analysis lane gains a matching step under a new purpose `MATCH`, switched by `masi.analysis.match-auto` (`MASI_MATCH_AUTO`), with its own per-tick count and max attempts.
  - The budget share is `MATCH: 0.25`. At the test namespace's $2.30 a day that is ~$0.57, about 70 postings a day. The 519-posting backlog takes about 8 days and costs about $4 of the $10 monthly cap ($1.24 spent this month).
- **Model:** Haiku 4.5 by default (`masi.ai.match-model`), about $0.008 per posting. Haiku caches only prompts of 4096 tokens or more; rules plus master are about 3k, so nothing caches. Sonnet 5 (caches from 1024 tokens) is the step up if the evaluation below asks for it.
- **Evaluation before it ranks:**
  - A labelled set in the repo: requirement lists copied from real analyses (phrases only, never posting text), in English and Estonian, against the fictitious sample CV, each with hand-written verdicts.
  - An env-gated evaluation runs both matchers on it. AI replaces the word score in the ranking only when it agrees with the labels more often.
  - CI tests the verifier and the scoring on recorded answers.
- **Site:** the Match card lists each requirement with its verdict, the evidence it cites, the reason, and who decided (your dates, your languages). A requirement in another language shows in English, with the original beside it. The card says whether the score is the AI match or the word match.

PRs:
- **PR3f-1** (masi): catalogue, call, verifier, scorer, storage, lane, evaluation harness.
- **PR3f-2** (site): the card.
- **PR3f-3** (infra): the `MATCH` share and `matching.auto` on in test, after the evaluation passes.

Revert checks:
- a citation no longer checked;
- a MET without evidence kept;
- YEARS from the model instead of the dates;
- overlapping roles counted twice;
- the language level not checked;
- an incomplete answer accepted;
- the word refresh overwriting an AI row;
- PARTLY weighed as MET;
- NOT_A_CV_THING counted.

**PR3f as built (masi #52, platform dcb976d, infra d76d434).**
- **First live evaluation (Haiku 4.5, 26 real requirement lists, 187 hand labels):** 96% agreement, against 46% for the word scorer (0% on Estonian). The model left one keyword out of a long list, so the prompt now names every id again at the end: 0 refusals since.
- **Architecture review: 13 warnings, all fixed.** The ones that mattered:
  - **Years from the dates overturned the model's NOT_MET** on a subject it had shortened: "Java in avionics" became MET on ten years of Java. The dates now decide only when the subject carries every word of the requirement, and otherwise only cap. Years no role shows are at most PARTLY.
  - **Role names were one bag of words:** "React" plus a keyword "native app" made "React Native". Now one item names a subject; a title never by two letters ("R&D" is not R).
  - **NOT_A_CV_THING let a hard requirement out of the score.** It now holds only for kind OTHER.
  - **Target roles (wishes) were citable.** They are out of the catalogue.
  - **Language alternatives:** any of the languages asked for will do, and absence counts only when every master language was read.
  - **Budget:** the MATCH share squeezed the tune. SCORE goes to 0.10, and the shares are checked at startup to leave 15%.
  - **Busy call slots:** a slot wait cost the posting an attempt in every lane. It now has its own exception, and the attempt is given back.
  - **Also:** the drain flag, masters taking turns, the verdict stored only on its own row, a rewritten repost dropping its scores, the match model price-checked.
- **Test audit: 101 mutations, 60 green.** Serious gaps:
  - another master's rows could be taken;
  - the switch was untested;
  - one assertion could not fail.

  All closed. The catalogue's text is now written by hand in the test, and 038 is run on the live shape. The revert checks: 16 + 36 + 1, all red.
- **The model's behaviour, tuned against the set:**
  - traits (problem-solving, product mindset) must not be credited from achievements;
  - English is asked for on every requirement (asked only for non-English ones, it was left out on a whole run);
  - reasons speak to the candidate, never by id.

  **Final evaluation:** 97% agreement, 98% MET precision, 0 must-haves MET against their label. These floors are asserted by the (env-gated) evaluation.
- **Live in test 2026-09-24:**
  - masi 2b864a1: 038 ran on 536 live rows, all WORDS with 0 attempts;
  - platform dcb976d passes `MASI_MATCH_AUTO`, `MASI_MATCH_PER_TICK` and `MASI_AI_MATCH_MODEL`;
  - infra d76d434 switches the match on.
- **Next:** PR3f-2, the site's Match card. It is previewed from real results and waits for the operator's go.

### PR3g — the master in Estonian: an Estonian posting gets an Estonian CV

Operator, 2026-09-24:
- Match to an Estonian posting with a CV in its language, "translated and kept", rather than the "language mismatch" masi showed.
- **The language a CV is written in is not a claim of level.** The level lives in the Languages section, which is copied from the master. So nothing is gated on the stated level (the hr skill is corrected to match).

**Why translate the master and not each CV:** the fabrication guard compares a tuned CV with the master it was tuned from, bullet by bullet and number by number. An Estonian CV cannot be checked against an English master, and translating after the guard would put unguarded text in front of a recruiter. So the master is translated once, checked, reviewed, and kept as a version of its own.

**As built (masi #53):**
- **A translation is a `cv_version` of its own.**
  - Changeset 039 adds `translated_from_id` and `reviewed_at`, with a database check that a translation is never active.
  - It is **current** when it is the newest reviewed translation of the active master in its language that still passes parity. A new master version, or a newer reviewed sibling, takes that from it.
- **What the model is sent — prose only** (`MasterText`):
  - summary, value proposition and differentiators;
  - a role's location, team role, scope, statements, metrics and problems;
  - skill-group names, education fields, language names, availability, work permit.
- **What is copied, never written:** employers and their context line (domain, type, size, users; the hr rule is "rendered from master fields, never model prose"), titles, degrees, target roles, dates, tech, skills and certifications.
- **Translating:** `POST /cv/versions/{v}/translations {language}` runs one call to the tuning model (purpose `TRANSLATE`) with each field as JSON, carrying the schema's `maxLength`.
  - The answer is written back into a copy of the source.
  - It takes half a minute or more, longer than a request may wait at the gateway: **202**, then `GET /cv/translation` (RUNNING / DONE with the version / FAILED with why). One at a time per user.
  - Only **English and Estonian**, both ways: the ladder that checks a translation reads those two, and Russian waits for a Russian ladder.
- **Parity (`MasterParity` + `Figures`), run on every read and required before approval:**
  - every non-prose field is the source's, and every list is as long;
  - every figure is kept with its magnitude or unit in any of the three languages, in order within each unit ("2 M" is not "2 miljardit", 800 ms and 120 ms never swap);
  - a metric counts as in its statement when its figures are, in a row (Estonian inflects it);
  - no verb in a role's scope, statements or team role, or in the candidate's own voice, ranks above the source's. The Estonian ladder reads verbs and role nouns, never verbal nouns, adjectives, or a leader in the object;
  - a blank field stays blank;
  - no sentence of four words or more comes back unchanged;
  - the translation says its own language.
- **Review:** `POST /cv/versions/{v}/review` approves, refused with every violation (409). `POST /cv/versions {yaml, translatedFrom}` saves the operator's edit, checked the same way.
- **Real model:** the env-gated `MasterTranslationLiveTest` translates the sample master and requires parity as it comes back.
- **For PR3g-2:**
  - the claims gate's "metric verbatim in the bullet" must become "the metric's figures in the bullet", or an Estonian bullet that inflects its metric fails;
  - the PDF template's headings and "present" are English, and need the tuned CV's language;
  - the language gate should read the prose too, not only the `language` field.

**As built (masi #54, PR3g-2):**
- **Which version a package is tuned from:**
  - The operator's choice (`application_package.language`) comes first. Otherwise the posting's analysed language decides.
  - The master's **current** translation into that language is sent as the CV block. With no current translation, the master is sent.
  - The package keeps its master (`cv_version_id`) as its key. Changeset 040 records `master_version_id`, the version it was tuned from.
- **The operator's choice:**
  - `POST /jobs/{id}/packages?language=` and `POST /packages/{id}/regenerate?language=`.
  - 409 without a current translation, 400 for a language masi does not write, and `auto` hands the choice back to the posting.
  - If an asked-for translation stops being current, the package ends FAILED before any tune call.
- **The guard in Estonian:**
  - The language gate reads every part (summary, letter, each bullet) with `LanguageGuess`, so Russian is refused too.
  - A metric part is kept when its figures are there (with their units, in order) and so are its other words, in any case ending. "40 kliendi" has not kept "40 teenust".
  - A comma between digits is a decimal or a thousands group ("1,5 korda"), never a split.
  - Two words are one when they share a stem of at least 4 letters and what is left on each side is a real Estonian ending: a stem vowel or plural marker, then a case ending ("teenust", "teenusele"). So a compound's head is not an ending ("andmetorustiku" is not "andmeteaduse"), and neither is a lookalike: "Nortalix" is not Nortal, "kasutajad" (users) is not "kasutus" (use). Bullet overlap and the role-words check both use this.
  - The letter may name the company and the role with such a case ending ("Nortalile", "Developeri").
  - A posting's figure in a first-person Estonian sentence ("Mul on 5 aastat…", "Töötasin…") is refused, as in English.
  - Short bullets are also judged together.
  - English is unchanged.
- **Asking for a language:** on an existing package it is taken while the package is NEW, and is 409 once the package is tuned ("regenerate it").
  - Regenerate checks again that the language asked earlier still has a current translation.
  - A Russian master may be asked for in Russian, its own language.
- **Russian translations:** parity refuses a translation into a language masi cannot check, so a hand-made Russian translation is never current and never tuned from.
- **Labels:** Russian labels exist too, and a test pins the labels to every language the schema allows.
- **The written-in language:** it is stored with the package (`written_in`), so the queue never parses a CV.
- **Budget estimate:** it counts the longest version a package may send.
- **The page:** the PDF's headings, "present" and "native" follow the master's language (`CvLabels`), and the lint reads Estonian duties and boilerplate.
- **Still English in an Estonian CV:** the company-context line (domain, type, size, users). It is copied, never written, so a translated "type" cannot gain an adjective.

**As built (site #26, PR3g-3):**
- **The CV page's Translations card:**
  - translate the active master into the other language, following the model's status;
  - each translation's standing and its parity problems, with the way past them said in words;
  - approve;
  - an edited translation is saved as a translation.
- **The package panel** says what a package is written in and from which version. Prepare and Regenerate take a language: the posting's by default, or English or Estonian.
- **Reviewed:** two rounds in the rendered DOM at 1366, 375 and 320 px, and a test audit whose 17 tests kill all 43 mutants (the requests to masi pinned in `api.test.ts`).

PRs:
- **PR3g-1** (masi): changeset, translation call, parity check, review.
- **PR3g-2** (masi): tuning picks the language, the per-package switch, the language gate for any language.
- **PR3g-3** (site): the CV page's translation card and the package page's switch.

Revert checks:
- a model-written number kept;
- a title taken from the model;
- a dropped achievement accepted;
- a raised autonomy verb accepted;
- review allowed while a violation stands;
- a stale translation used;
- an Estonian posting tuned in English while a current translation exists;
- a Russian output passing against an English master.

## Status

IN PROGRESS 2026-09-24 — PR1 (masi #37, site #20), PR1b (masi #39), PR2 (masi #40, site #21), **PR3a (masi #44)**,
**PR3b (masi #45)**, **PR3d (masi #46, the register covers every business)** all MERGED and live in
schnappy-test; PR3b's source is seeded off, PR3d's index fills on the next complete register read. **PR3e (masi #47, the
register marks agencies)** merged and live; **PR3c (masi #49, #50, site #22: the people and company pages)** merged;
**PR3c-2 (site #23, masi #51, site #24: the job page's bookings; a merged job sends everything to where its merges
end)** live in test 2026-09-24 (masi dd50b2e: 7 merged jobs, 0 rows or bookings stranded on them; site 938215b).
**PR3f (AI matching: masi #52, platform dcb976d, infra d76d434)** live in test 2026-09-24 (first live matches: ~0.0095
USD a posting). **PR3f-2 (site #25, the Match card)** live. **PR3g (the master in Estonian): PR3g-1 (masi #53,
translation + parity + review) and PR3g-2 (masi #54, an Estonian posting tuned from the Estonian master; the guard reads
Estonian) live in test 2026-09-24 (masi 4dde79d, changeset 040); PR3g-3 (site #26, the translation card and the package
language) merged 2026-09-24.** **PR3c-3 (site #27): the masi pages' layout measured in Chromium in CI** — `npm run
test:layout` (`layout/`: the real pages under the real stylesheet, API answered from fixtures typed against `api.ts`),
asserting at 390/1366 px no sideways scroll, no text past its box (width and height, tables and grid included),
WCAG 2.5.8 target size with its spacing exception, the masi select height, every page's stress data drawn, and the
calendar's lanes, hour rows and booking times. An empty stylesheet fails all 18. Its first run found four defects (day
counts and day number reaching into the next day's cell on a phone; claims/lint not wrapping a URL; a bare 19 px
select), fixed there; its audit found eight ways the checks could be fooled, all closed. Next: PR4 (inbox). Enrichment and analysis batching (094 Later) queued behind them.
