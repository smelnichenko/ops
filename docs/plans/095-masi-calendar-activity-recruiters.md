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
2. **PR2 — calendar** (`masi` + `site`): changeset 029 (`calendar_event`), `CalendarService`, `GET /calendar`
   with the day counts, the three views, event create/edit/outcome, deadline markers from `expires_at`; the
   weekly digest lists the coming week's events. Invariant: the day cell's three numbers equal the day's log
   filtered by kind; an event's outcome writes the activity; DST week (2026-10-25) renders 25 hours right.
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

## Status

DRAFT 2026-09-22 — written on the operator's request; queued after enrichment (094 Later) and the analysis
batching; PR1 not started.
