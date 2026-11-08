# Plan 109 — masi: more companies' own job boards

**Status:** proposed 2026-11-08, waiting for the operator's OK. The operator asked whether masi can widen its sources by
finding each company's ATS, then whether more kinds of ATS are worth reading ("maybe more flavours of ATS?").

Masi gets one PR at a time. Each PR follows the usual routine: a failing test first, revert checks, the clean check, a
PR, CI, merge, a smoke test on test, a promote, and a check in production.

## What masi does today

- **Detection by link.** `AtsDetector` recognises a board from an apply link or a careers link, by its host:
  - Greenhouse, Lever, Ashby and SmartRecruiters, which keep each customer's board on one shared host;
  - Teamtailor, TeamDash, Workable, BambooHR, Recruitee, Workday and Eightfold, which give each customer a host.

  It does this on every ingest (`CompanyService.attachAts`) and on every site visit (`EnrichmentService.take`).
- **Source rows.** A board on a vendor with a reader gets an `ats:<slug>` source row, created disabled. The other
  vendors are only written to the company as its vendor.
- **Who gets visited.** The site visits (on in production, 5 per 10-minute tick) only ever pick companies that already
  have an open job (`CompanyEnrichmentRepository.dueForVisit` joins `job`). That pool is used up: one visit in the last
  day.
- **Production, 2026-11-08:**

  | | count |
  |---|---|
  | companies | 28,746 |
  | with a website | 2,603 |
  | with a careers page | 107 |
  | with an ATS | 53 |
  | `ats:` sources | 31 (29 enabled) |
  | `teamdash:` sources | 4 |

## Measured 2026-11-08

The data and both scripts are in `109-data/`.

### 1. Apply links masi already holds, grouped by host

Most of the missed boards are in links masi has already ingested:

| Missed | Boards | What it would take |
|---|---|---|
| **Teamtailor on the company's own domain.** Scoro, Monese, Lightyear, NetGroup, Frankenburg, DefSecIntel, Gepard, Entain, Avarda, Ergo, Iute, Smartful, Swappie, Greenstep, Mercell, plus three boards that are empty now (Coolbet, Thorgate, Yolo). Datel, Milrem and Swedbank are already sources, added by hand. | 18 | Nothing in the reader: each serves the same `/jobs.json` feed. The 18 feeds hold 68 postings located in Estonia or remote. |
| **Lever's EU host**, `jobs.eu.lever.co`. SEB's board has 123 postings, 10 of them in Tallinn; masi has 13 SEB jobs open from the boards. | 1 | The reader already takes `apiBase`, so `api.eu.lever.co` works. The detector knows only `jobs.lever.co`. |
| **Short links** `grnh.se` (Greenhouse) and `smrtr.io` (SmartRecruiters). | 2 employers | One request to follow the redirect. |
| **TeamDash on the company's own domain** (`teamdash.enefit.com`, `jobs.bigbank.eu`). | 2 | Bigbank is already a source; Enefit is not. |
| **Vendors with no reader:** Recrur (Tartu Ülikool, Tallinna Ülikool, Tartu Linnavalitsus, Coop Pank, Manpower), iCIMS (Nortal), SuccessFactors, Jobvite (Malwarebytes), njoyn (CGI), Recman (Talentor, an agency), HaileyHR. | 11 employers | A reader each. |

### 2. Companies masi knows no job of

There are 146 active companies with 10 or more staff, a website and no job, nearly all IT (EMTAK 62/63). Each one's
homepage, and up to two careers pages it links, were read for ATS links, honouring robots.txt:

| | count |
|---|---|
| homepages that answered | 134 |
| careers pages found | 60 |
| boards found | 12 (10 real) |

The 10 real boards:

| Company | Vendor |
|---|---|
| Finest, Insly | TeamDash |
| Dun & Bradstreet | Lever |
| Rush Street Interactive | Greenhouse |
| Toggl | Ashby |
| Uptime | Recruitee |
| Dream Finance | Lever |
| Kodality | BambooHR |
| 3 Step IT | Teamtailor |
| Qminder | Workable |

The two false matches were Tieto's `my-applications` and Tilde's `oneclick-ui`. The other 48 careers pages either sit on
the company's own site with no ATS link, or name a vendor only through the page itself, as the custom-domain Teamtailor
boards above do.

### 3. Guessing the slug, rejected

Slugs were made from each company's name and domain and asked at nine vendor APIs. Only about 5 of the 13 hits with
jobs were the company (D&B, Konecranes, Powerfleet, Twilio, SocialLab), and those boards are mostly abroad. The false
hits were:

- `ee` on Greenhouse: "Emily's Entourage";
- `aka`, `build` and `mobi` on Ashby;
- `spin`, `alpha` and `opus` on Greenhouse and Recruitee.

Workable answers 200 for any name at all. Guessing makes rows that point at the wrong company, and is not built.

## PRs, in order

1. **The detector reads the page as well as the host.**
   - **Teamtailor on any domain.** A careers page whose HTML names Teamtailor's assets, confirmed by its
     `/jobs.json` answering `application/feed+json`, becomes a `teamtailor` row with that `feedUrl`. The key comes from
     the registrable domain: `careers.scoro.com` gives `ats:scoro`.
   - **TeamDash on any domain.** The same, as a `teamdash:` row.
   - **Lever EU.** `jobs.eu.lever.co/<slug>` gets `apiBase: https://api.eu.lever.co`, and its existence check asks the
     EU API.
   - **Short links.** `grnh.se` and `smrtr.io` are followed once and the target is detected.
   - **Vendors read but never made into rows.**
     - Personio (`*.jobs.personio.de|com`, which is not recognised at all today) gets `xmlUrl` and `jobBase`.
     - BambooHR gets `sub`.
     - Workable gets `accountId`, read once from its widget API (`/api/v1/widget/accounts/<slug>`).
     - Workday and Eightfold stay vendor-only: a Workday row needs a country facet no link carries.
   - **Tests.** The real links measured above, each with its expected row, plus the two false matches staying out.
2. **Detection over the links already held.** A one-off, re-runnable pass over every listing's apply link and every
   company's careers link, through `attachAts`. It only creates rows that are missing, and asks each board once. This
   is what turns section 1's 18 Teamtailor boards, SEB and Enefit into rows. **Check:** their rows exist in production.
3. **Visits to companies with no job.** A second queue for the visit lane: active, not blacklisted companies with 10 or
   more staff and no open job. It is ordered by size, revisited every 30 days, and runs after the hiring companies at
   the same per-tick rate.
   - It covers companies with no website, through the visit's existing website guesses.
   - Measured yield: about 7% get a board (10 of 146). With PR 1's page markers, more of the 48 careers pages with no
     ATS link should resolve. That is measured after PR 1, not assumed.
   - **Check:** the visits' outcomes and the new rows, a week after it ships.
4. **The browser for careers pages built by scripts.** When a careers page's static HTML names no ATS, render it once in
   the `masi-browser` pod and detect again. It is kept only if it finds boards on the 48: measured first on the saved
   list, then shipped or dropped.
5. **Recrur reader.** It is Estonian and covers universities and public bodies (Tartu Ülikool, Tallinna Ülikool, Tartu
   Linnavalitsus) plus Coop Pank. It reads the public `/public` job pages, records its terms and robots facts in
   `docs/sources.md`, and is detected from `*.recrur.com`.
6. **iCIMS reader, for Nortal**, one of the larger IT employers in Estonia. The same routine. The rest (SuccessFactors,
   Jobvite, njoyn, HaileyHR, Recman) each have one employer, so a reader is added only once more employers on that
   vendor turn up; until then the company is written as that vendor only.

## Decision needed from the operator

Auto-detected rows are created **disabled** today, "for the operator to enable after the terms check". PR 2 alone makes
about 20 rows, and PR 3 keeps making them.

- **Recommended:** create rows **enabled** for the vendors whose board API is public and meant for job aggregation:
  - Greenhouse Job Board API
  - Lever Postings API
  - Ashby posting API
  - Teamtailor JSON Feed
  - Personio XML
  - Recruitee offers API
  - Workable widget
  - BambooHR careers list

  Every row masi reads today is one of these, and all 29 enabled `ats:` rows are healthy. New readers (Recrur, iCIMS)
  start disabled until their terms are recorded.
- **Otherwise:** they stay disabled, and the sources page lists them for enabling.

## Not doing

- Guessing slugs (section 3 above).
- Reading boards abroad: the `locationRegex` filter (Estonia, Tallinn, Tartu) stays on every row.
