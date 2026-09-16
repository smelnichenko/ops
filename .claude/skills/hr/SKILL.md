---
name: hr
description: HR and recruiting domain for the masi job-registry robot and for anything that writes, tunes, reviews or scores a CV, cover letter or job posting. Read BEFORE designing or reviewing CV tuning prompts, claims/lint rules, posting analysis, match scoring, application-package review, the CV master schema, or a job/company registry — and whenever an output "reads fine" but a recruiter would bin it. Encodes how recruiters and ATS parsers actually read a CV (the top-third scan, keyword matching, parse-ability), the results-not-duties rule with the "a title says nothing" test, company-context per role, cover-letter shape, Estonian IT-market specifics (boards, languages, salary fields, contracts, probation), the fabrication line the tuner must never cross, and the review checklist for a prepared package.
---

# HR / recruiting discipline

One thesis:

> **The employer sees only what the CV shows.** A strong candidate stays invisible not for lack of
> experience but because the value is not on the page — and a CV that shows value the candidate
> does not have is worse than invisible.

Everything here follows from that. Generic career advice is out of scope; what follows is what a
CV-tuning robot and its reviewers get wrong.

## 1. How a CV is actually read

- **Two readers, in this order: a parser, then a person.** Boards and ATSs (cv.ee, cvkeskus,
  Greenhouse, Lever, SmartRecruiters, Teamtailor, TeamDash) extract text and match keywords before
  a human opens the file. A PDF whose text does not extract (image-only, text in shapes, exotic
  fonts without a Unicode map) scores zero. **Render with real text**, single column, standard
  section headings (Summary, Experience, Skills, Education), no tables for layout, no icons as
  bullets, dates in one format. PDFBox text extraction of the rendered file is the test.
- **The person spends seconds on the first pass.** Top third of page one decides whether the rest
  is read: name, target role, a 3–4 line summary that names the fit for *this* role, then the most
  relevant recent role. Anything the posting asks for must appear above the fold.
- **A title says nothing.** "Backend Engineer" at one company means CRUD endpoints under a lead;
  at another it means owning a payments domain, on-call, and hiring. The reader cannot tell which
  unless the CV says: the area owned, the scale (users, requests/s, data, team size, budget), the
  problems solved, the technologies, and the degree of autonomy (decided / proposed / executed).
  Every role needs those five facts or it reads as the weaker interpretation.
- **Results, not duties.** "Responsible for the API" is a duty; "cut p99 latency of the order API
  from 800 ms to 120 ms for 2 M daily requests" is a result. Verbs like *responsible for*, *worked
  with*, *participated in*, *involved in* without a number or an outcome are lint failures.
  Action → scale → outcome is the bullet shape. Keep every number verbatim from the evidence bank.
- **Company context per role.** One line under each employer: domain, type (product / consultancy /
  bank / public sector / startup), size band, and what the team owned. It places the role for a
  reader who has never heard of the company — most Estonian employers are unknown abroad and many
  foreign ones are unknown here.
- **The posting's vocabulary.** Parsers and people both look for the posting's own terms
  ("Kubernetes" not "container orchestration", "Kafka" not "message bus"). Mirror them *only where
  the evidence bank supports them*; keyword stuffing is detected by both readers and by the
  claims checker.
- **One CV per posting.** The universal CV lists what the candidate finds important; the tuned CV
  shows what this employer is looking for. Order roles and bullets by relevance to the posting,
  collapse irrelevant roles to one line, never delete a role (gaps raise questions).

## 2. The fabrication line

The tuner may **select, order, emphasise and rephrase**. It may **never add**: an employer, a
title, a date, a tool, a certification, a language level, a number, a customer, a team size, or an
outcome that is not in the evidence bank. Rephrasing keeps the fact; "led" for "participated" is
a new fact. Salary figures never appear in a CV or letter. Education, certifications and
languages are copied from the master by the renderer, not written by the model. A package with
one fabricated claim is a rejection at interview and a reputational loss with a recruiter who
talks to other recruiters — this is why the claims checker is a hard gate and the lint is not.

## 3. Cover letter shape

Three short paragraphs, under ~250 words, addressed to the company by name and naming the role:

1. **Why this role and company** — one specific reason drawn from the posting or the company
   (product, domain, scale), not flattery.
2. **Why me** — two or three achievements from the evidence bank mapped to the posting's
   must-haves, with the numbers; this is the summary's argument in prose.
3. **Why now / logistics** — availability, location or remote fit, language, work permit if
   relevant; one line.

No restating the CV, no "I am a hard-working team player", no salary. In Estonia the letter is
read less often than the CV; keep it short and let the CV carry the evidence.

## 4. Posting analysis

Before tuning, reduce a posting to `must_have[]`, `nice_to_have[]`, `keywords[]`, `seniority`,
`domain`, `language`, `remote`, `salary` (if stated). Traps:

- Boards translate and pad postings; the *requirements* section is the signal, the company
  boilerplate is noise. Some postings are recruiter-agency relays with the employer hidden.
- "Senior" on cv.ee and "Senior" at a bank are different ladders. Read the years, the scope and
  the salary band rather than the label. Common Estonian IT ladder: junior (0–2 y), mid (2–5),
  senior (5+ with ownership), lead / staff / architect (cross-team scope).
- Estonian-language postings often mean Estonian is required for the job; English-language ones
  usually mean English-speaking teams. Russian appears for support/ops roles. Record the language.
- Salary: Estonian law does not oblige a posting to state pay; cv.ee carries `salaryFrom/To` when
  the employer fills it. Absence is not a signal; presence is a filter.
- `remote`: tri-state (on-site / hybrid / remote). Do not infer remote from "flexible".

## 5. Estonian IT market specifics

- **Boards**: cv.ee and cvkeskus.ee (both Alma Career) carry most postings; tootukassa.ee is the
  public-sector portal and mirrors many; MeetFrank skews to startups; the largest employers
  (Wise, Bolt, Pipedrive, Veriff, Twilio, Swedbank, LHV, Nortal, Helmes) post on their own ATS
  first and on boards second. TeamDash is the common local ATS.
- **Employment**: a *tööleping* (employment contract) under the Employment Contracts Act; the
  probation period (*katseaeg*) is up to four months by default; contractor arrangements are
  common via an OÜ. Verify current law before stating figures to the operator.
- **Work permits**: EU/EEA citizens need none; others need a residence permit for employment,
  which employers handle via the Police and Border Guard Board. A CV should state the permit
  status only if the posting asks or the candidate is a non-EU national.
- **CV conventions**: no photo, birth date, marital status or ID code — they add nothing and cost
  GDPR care. Two pages for a senior profile; one for a junior. Location (Tallinn/Tartu/remote) on
  the first line.
- **Timing**: apply in the first week of a posting; boards keep postings ~30 days; a listing that
  stays open longer than two cycles is often evergreen or already filled.

## 6. Data and privacy in the registry

- Companies are legal persons; storing their public data is fine. **Recruiter and contact
  persons are personal data** — store a contact only when needed to apply, never scrape or
  enrich individuals, never keep their data after the package is closed.
- The candidate's own CV is sensitive personal data: DB only, no fixtures, no logs, no LLM
  request bodies in logs, and the rendered PDF contains only what the master says.
- Postings are copyrighted text; keep `description_raw` for matching and lifecycle, do not
  republish it.

## 7. Reviewing a prepared package — the checklist

Reject the package if any of these fail; these are what a recruiter notices in the first pass.

1. Summary names the target role and the company and states the fit in ≤ 4 lines.
2. The posting's must-haves each map to a visible bullet or skill — or the gap is honest.
3. Every bullet is action → scale → outcome with a number where the evidence bank has one.
4. Each role has its company-context line and its scope/autonomy stated.
5. No claim absent from the evidence bank (claims report: 0 violations).
6. Skills list is a subset of the master, ordered by the posting's priority, no stuffing.
7. Dates, employers and titles match the master exactly; no gaps introduced.
8. The PDF's extracted text reads in order, single column, and fits two pages.
9. The letter is ≤ 250 words, names the company and role, contains one mapped achievement.
10. Nothing personal beyond name, location, email, phone, links.

## 8. The candidate's own three questions

The operator's framing, which the CV master's `positioning` block must answer before any tuning:
**Who am I → what can I give an employer → who needs that now.** A master that cannot answer
these produces generic packages regardless of the model; the completeness check exists for this.
