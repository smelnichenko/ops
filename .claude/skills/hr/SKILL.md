---
name: hr
description: HR and recruiting domain for the masi job-registry robot and for anything that writes, tunes, reviews or scores a CV, cover letter or job posting. Read BEFORE designing or reviewing CV tuning prompts, claims/lint rules, posting extraction, match scoring, the CV master schema, or a prepared package — and whenever an output "reads fine" but a recruiter would bin it. Encodes how parsers and recruiters read a CV, the fabrication line a tuner must not cross and which of its rules are machine-gated, the LLM-specific tuning failures, Estonian IT-market facts (boards, law, permits — dated), registry privacy, and the package review that checks only what the guard cannot see.
---

# HR / recruiting discipline

The employer sees only what the CV shows: a strong candidate stays invisible not for lack of
experience but because the value is not on the page — and a CV that shows value the candidate
does not have is worse than invisible. A robot tuning a CV fails in both directions at once,
and most of its rules below are **not** enforced by a machine. Every rule is tagged:
`[gate]` = a deterministic check that fails the package, `[lint]` = a warning that triggers
one retry, `[human]` = the reviewer's job. Treat an untagged sentence as `[human]`.

## 1. How a CV is actually read

- **Two readers: a parser, then a person.** Boards and ATSs (cv.ee, cvkeskus, Greenhouse, Lever,
  SmartRecruiters, Teamtailor, TeamDash) parse the file into fields and let recruiters
  keyword-search; automatic ranking is rare, an unparseable file is fatal. `[gate]` Render
  real text: single column, standard section headings, no tables for layout, no icons as
  bullets, one date format, a font with a Unicode map. PDFBox extraction is the
  *parse-ability* test and only that: it must run with `setSortByPosition(true)` **and** agree
  with DOM order (a two-column layout extracts "in order" without the sort and interleaved with
  it), assert ≤ 2 pages per package, and prove the bundled font is embedded. Headings, tables,
  bullets and date format are template review, not a test.
- **Where a board offers quick-apply, the board profile is what is sent**, not the PDF (cv.ee
  exposes `quickApply` per vacancy). The tuned PDF counts where a file is attached; the profile
  must not contradict the master's dates and titles. `[human]`
- **The person spends seconds on the first pass.** Top third of page one: name, target role,
  a 3–4 line summary naming the fit for *this* role and company `[lint: names the role]`, then
  the most relevant recent role. Anything the posting asks for appears above the fold. `[human]`
- **A title says nothing.** "Backend Engineer" at one company means CRUD endpoints under a lead;
  at another it means owning a payments domain, on-call and hiring. Every role states the area
  owned, the scale (users, requests/s, data, team size, budget), the problems solved, the
  technologies, and the degree of autonomy (decided / proposed / executed). The company-context
  line is **rendered from master fields** (`company{domain,type,size_band}`), never model prose
  — "a leading fintech with 5 M users" is fabrication by adjective and number. `[lint: context
  line present]`
- **Results, not duties.** "Responsible for the API" is a duty; "cut p99 latency of the order
  API from 800 ms to 120 ms for 2 M daily requests" is a result. Shape: action → scale →
  outcome. `[lint]` a bullet with *responsible for*, *worked with*, *participated in*, *involved
  in* and no metric. `[gate]` a selected achievement whose master `metric` is missing from the
  bullet — dropping a number makes a bullet *more* similar to the master under a token-overlap
  check, so this needs its own rule. Every number verbatim from the evidence bank. `[gate]`
- **The posting's vocabulary.** Both readers look for the posting's own terms ("Kubernetes", not
  "container orchestration"). Mirror them only where the evidence bank supports them. The
  claims checker refuses terms absent from the master `[gate]`; **repeating a supported term is
  caught by nothing today** — stuffing needs a density lint (a term more than N times, or a
  skills list longer than the master's top-K for the posting) and, until then, a reviewer.
- **One CV per posting.** Keep roles reverse-chronological (a relevance-ordered history reads
  as concealment and defeats the gap check); order bullets *within* a role by relevance;
  collapse irrelevant roles to one line with company, title and dates verbatim; **never delete
  a role** `[gate: a master role absent from the output is a violation, the mirror of "none
  added"]`.

## 2. The fabrication line

The tuner may **select, order, emphasise and rephrase**. It may never add an employer, a title,
a date, a tool, a certification, a language level, a number, a customer, a team size or an
outcome absent from the evidence bank. What the guard sees and what it does not:

| Rule | Enforcement |
|---|---|
| employers, titles, dates match the master; none added, none removed | `[gate]` |
| skills list ⊆ master | `[gate]` — the list only; a tool named inside a bullet ("… using Kafka") passes token overlap |
| every number, year, percentage in the CV is in the master | `[gate]`; posting numbers ("5 years of Kubernetes") are the likeliest fabrication and are allowed only in the letter's description of the role, never as the candidate's |
| no salary figures | `[gate]` |
| education, certifications, languages copied from the master by the renderer, never written by the model | `[gate]` (a model-supplied certification is absent from the PDF text) |
| autonomy verbs do not outrank the matched master bullet — participated < contributed < proposed < owned/led < decided; "led" for "participated" is a new fact | `[gate]` verb-ladder rule; a single verb swap keeps token overlap near 1.0, so overlap alone is blind to the highest-frequency tuning failure, seniority inflation |
| a customer name, a worded team size ("a team of five"), a worded outcome appended to a master bullet | `[human]` — passes overlap; the reviewer's first look |
| output language = the master's language; an Estonian-language posting must not produce an Estonian CV or letter unless the master's stated level supports it — posting terms are translated for matching only | `[gate: language detection on the output]` |
| no LLM boilerplate: spearheaded, leveraged, passionate, results-driven, proven track record, "I am excited" — recruiters read these as machine text | `[lint: stop-list]` |
| tense and voice: past roles past tense, current role present, no first person in the CV, first person in the letter, one spelling variant | `[lint]` |
| the posting's title may be the target-role line, never the candidate's current title | `[gate]` (title match) |
| with an agency relay the letter names the agency; never guess the hidden employer | `[human]` |

One fabricated claim is a rejection at interview and a reputational loss with a recruiter who
talks to other recruiters. The claims checker is a hard gate **for what it can see** — the
`[gate]` rows. Each new rule needs its own red row in the plan's revert table before it may be
called a gate.

The master must answer, before any tuning, the operator's three questions: **who am I → what
can I give an employer → who needs that now** (the `positioning` block: target roles, value
proposition, differentiators). The completeness check scores per-role metric gaps *and* an
empty positioning block; a master that cannot answer produces generic packages whatever the
model.

## 3. Cover letter

Under 250 words `[gate: word count]`, names the company `[gate]` and the role `[gate]`, and
maps two or three evidence-bank achievements with their numbers to the posting's must-haves
`[human]`. One specific reason for this company drawn from the posting or the product, not
flattery; availability, location, language and permit in one line. No restating the CV, no
"hard-working team player", no salary. In Estonia the letter is read less than the CV; keep it
short and let the CV carry the evidence.

## 4. Posting analysis

Before tuning, reduce a posting to `must_have[]`, `nice_to_have[]`, `keywords[]`, `seniority`,
`domain`, `language`, `remote`, `salary` (if stated). Traps:

- Postings may exist in ET/EN/RU variants; the employer's original is the signal, the board's
  company blurb is noise. Some postings are agency relays with the employer hidden.
- "Senior" on a board and "Senior" at a bank are different ladders; read scope and band, not
  the label.
- An Estonian-language posting usually means Estonian is required for the job; record the
  language, it is a filter and a fabrication risk (see §2).
- `remote` is tri-state (on-site / hybrid / remote); never infer remote from "flexible".
- Salary: Estonian law has not required pay in the ad; the EU pay-transparency directive
  (2023/970, due June 2026) requires the range before interview, not necessarily in the ad —
  verify the transposition before telling the operator either way. On cv.ee about a third of IT
  postings fill `salaryFrom/To` (32 of 100 sampled 2026-09-16); absence is not a signal,
  presence is a filter.

## 5. Estonian IT market (facts verified 2026-09-16; re-verify before quoting to the operator)

- **Boards**: cv.ee (Alma Career, which also runs otsintood.ee — so otsintood is **not** an
  independent oracle for cv.ee) and cvkeskus.ee (CV Keskus OÜ, Ringier) carry most postings;
  tootukassa.ee (the public employment service, all sectors) mirrors many; MeetFrank skews to
  startups; the largest employers (Wise, Bolt, Pipedrive, Veriff, Twilio, Swedbank, LHV, Nortal,
  Helmes) post on their own ATS first. TeamDash (Recruitment Software OÜ, Tallinn) is the common
  local ATS.
- **Lifetime**: boards sell 30-day slots but employers set shorter windows (cv.ee IT median
  ~17 days, range 2–37, sampled 2026-09-16); use `publishDate`/`expirationDate`/`renewedDate`,
  not a fixed 30. A listing renewed past two cycles is evergreen or filled.
- **Employment**: a *tööleping* under the Employment Contracts Act; probation (*katseaeg*) is up
  to four months (§ 86; can be shortened by agreement, not lengthened); contractor work via an
  OÜ is common.
- **Work permits**: EU/EEA/Swiss citizens need none (residence registration only). Others:
  short-term employment registered by the **employer** with the Police and Border Guard Board
  (visa-free or D-visa), or a temporary residence permit for employment applied for by the
  **candidate** with the employer's support. State permit status in the CV only when the posting
  asks or the candidate is a non-EU national.
- **CV conventions**: no photo, birth date, marital status or ID code — a deliberate choice
  (parse-ability, GDPR), not a market norm; photos remain common on board profiles. `[gate:
  the master schema has no such fields and rejects unknown ones]`. Location on the first line.

## 6. Data and privacy in the registry

- Companies are legal persons; storing their public data is fine. **Recruiter and contact
  persons are personal data and are never stored as fields, never enriched, never displayed
  as a contact**; `description_raw` often contains a recruiter name or email — it stays inside
  that field for matching and lifecycle only and goes with the listing.
- The candidate's CV is sensitive personal data: DB only, no fixtures, no request bodies in
  logs `[gate: a log-capture test greps one gateway call's output for a master substring]`, and
  the rendered PDF contains only what the master says.
- Postings are the board's or employer's text (copyright and board ToS): keep `description_raw`
  for matching and lifecycle, never republish.

## 7. Reviewing a prepared package

Outcome is **Regenerate** (with notes) or **Skip**; a package that survives becomes Reviewed,
then Applied by hand. Do not re-check what the guard gates (claims report 0 violations; dates,
employers, titles; PDF order and ≤ 2 pages) — check what it cannot see:

1. `[human]` The summary's fit argument is specific to this posting, not transplantable.
2. `[human]` Each must-have maps to a visible bullet or skill, or the gap is stated, not hidden.
3. `[human]` No customer, team size, worded outcome or tool inside a bullet beyond the master.
4. `[human]` No autonomy verb outranks the master's (until the verb-ladder gate exists).
5. `[human]` Skills are ordered by the posting's priority, not padded.
6. `[human]` The letter's achievements are the right ones for this company; no boilerplate.
7. `[human]` Language and register match a level the master claims.
8. `[lint]` Warnings are read, not dismissed: duty verbs, missing context lines, stop-list hits.

Rules a machine cannot check are judged, and a judge is only a test against a labelled set:
N fictitious postings × the sample CV with hand-written expected mappings, plus an adversarial
set of tuned outputs each carrying exactly one fabrication (kept as fixtures, appended, never
re-typed). Report precision on that set; a judge with no set is an opinion.
