# 098 — masi: the second-tier job sources

## Decision

Add the job sources plan 094's survey ranked second tier and that still carry Estonian IT postings, highest volume
first, one collector per PR, each seeded **disabled** and enabled after its first run is checked on live data:

1. **cvpro.ee** — the IT category's list pages (`/et/vacancies?category=it`, 20 cards a page, 21 postings on
   2026-09-29) and a new posting's own page (its schema.org `JobPosting`). Not the RSS: its 100 items spanned 27 days
   with ONE in the IT category, and every item carried the recruiter's e-mail (108 addresses in one capture). It
   re-lists Töötukassa's offers, often under another title (Töötukassa's "occupation – refinement" against the
   employer's own words), so only some merge by fingerprint; its value is the postings nobody else carries.
2. **Kuehne+Nagel's Tallinn IT hub** — Phenom: the SSR search page embeds `phApp.ddo` with
   `eagerLoadRefineSearch.data.jobs[]` (jobId, title, city, country, postedDate, category, remote); 7 Tallinn jobs.
3. **Eightfold employers (Ericsson Estonia, Microsoft Tallinn)** — the JSON API answers 403; the sitemap
   (`careers/sitemap.xml?domain=…`) plus each job page's ld+json `JobPosting` (datePosted, description,
   jobLocation), Estonia only.
4. **Telia Estonia** — Workday's internal search (`POST …/wday/cxs/teliacompany/Telia_careers/jobs`, searchText
   "Estonia"); `postedOn` is relative ("Posted 15 Days Ago"); 2 jobs.

Not now (measured 2026-09-29): eAgronom (Personio: only an open application), TextMagic (Recruitee: none), Sympower
(Recruitee: one, Amsterdam), the tiny jsoup employers (Coop Pank, RMIT, Proekspert, Cleveron, Codeborne, Elisa:
0–8 each, mostly not IT) and workinestonia.com (an unverified admin-ajax endpoint). Never: cvkeskus.ee (a 10 000 €
per automated request clause, held until CV Keskus consents — D1), devjobsscanner.com (LinkedIn-derived — D4).

## Why

The operator's standing order after plan 096: continue with plan 094's Later list, T2 collectors first. The ladder's
T1 sources all run; what masi misses today is these employers' own boards and cvpro.ee's own postings.

## Per collector (the acceptance list of plan 094's "Adding a source")

- the host(s) added to `masiService.http.allowedHosts` (platform chart) in the same arc, before the source is enabled;
- a fixture captured from the live site, scrubbed of personal data and scripts, with its `CAPTURE.md` line;
- a collector test on the fixture asserting exact listings, plus the negatives (a broken page → an error or an
  incomplete run, never an empty board; a posting outside Estonia skipped; dates as that day in Tallinn);
- a seed changeset, `enabled=false`, and `docs/sources.md`;
- after deploy: one run by hand (`enable-one.sh`), its listings and titles read against the live site, then enabled on
  its seeded cron.

## PRs

1. masi: `cvpro` — the category's list pages read to the site's count (else incomplete), then each new posting's
   page within the day's request budget; the card's pay ("kuni"/"alates"/range, by the month) and last day on every
   run; the text only when the posting has its own (the site writes a stand-in line otherwise). How many of its
   postings merge with Töötukassa's is read on the first hand-run. 6 of the 21 "IT" cards were not IT work (a builder,
   a salesperson, an electrician): the category is the site's, and the operator's to judge.
2. masi: AtsCollector vendor `phenom` (K+N), Tallinn/Estonia jobs; job page for the description. Measured 2026-09-29:
   the search page for "Tallinn" shows 8 of 8 (7 in Tallinn, 1 in Porto) with a page size of 10; asked for its next
   page (`&from=N&s=1`) the site DROPS the keywords and pages through all 1 122 jobs worldwide. So the collector reads
   the first page only and calls a larger count an incomplete run (nothing is closed for it). Before K+N's Tallinn
   count passes 10, survey the page's `widgetApiEndpoint` (`https://jobs.kuehne-nagel.com/widgets`) for a paged search
   that keeps the keywords. A job's page answers at `/job/<jobId>` without its title; its JobPosting's `datePosted` is
   the day it was served, so the list's `postedDate` stands.
3. masi: vendor `eightfold` (sitemap + ld+json JobPosting), Ericsson and Microsoft rows.
4. masi: vendor `workday` (Telia), relative `postedOn` read against the run's day.
5. platform: allowed hosts per source, pushed before each enable.

## Status

2026-09-29: plan written; volumes measured from the live sites (above).
2026-09-29: **PR1 cvpro LIVE** — masi #77 (e785ec7), platform daf03e6 (allowed host). First hand-run 15:21 Tallinn:
OK, complete, 23 requests (2 list pages + 21 posting pages), 21 postings, 12 new jobs; 9 merged with jobs cv.ee and/or
Töötukassa already had (6 each, 3 with both), so "may merge" is about half. 16 carry their own text; 5 only the site's
stand-in line (kept as no description). Enabled on its seeded cron `0 50 5,17 * * *`. Found on the way: the site answers
an Estonian list request in English or Russian now and then (1 of 4 reads) — read alike in all three. 7 of the 21 "IT"
cards are not IT work (builder, salesperson, electrician, low-voltage installer, CCTV technician, support, repair
technician): the category is the site's, and whether to filter it is the operator's call. Follow-up masi #78: the four
register collectors' dates made strict (the same "31.02" flaw).
2026-09-29: **PR2 Kuehne+Nagel LIVE** — masi #79 (1373ec8), platform 44d0eaf. First hand-run 17:08 Tallinn: OK, complete,
8 requests (the search + 7 job pages), 7 Tallinn jobs, all with their text and the list's posting dates; enabled on
`0 49 */6 * * *`. `HtmlText.MAX_DESCRIPTION` is now the one description cap for every collector.
2026-09-29: **PR3 Eightfold LIVE** — masi #80 (e264b7a), platform a2b039c. First hand-runs 19:47/19:49 Tallinn: Microsoft
OK, complete, 3 requests, its 2 Estonian jobs; Ericsson OK, complete, 10 requests (sitemap + 3 Estonian + its 6 slugs
without a place, whose pages all named another country), 3 jobs (1 merged with a job masi had). Enabled on
`0 51 */12` and `0 53 */12`. The sites' API is closed (403): a job in several countries whose slug names another first
is not found. Microsoft's trailing dashes are punctuation ("…-washington-d-c-"), so `placelessSlugs` is Ericsson's only.
2026-09-29: **PR4 Telia LIVE** — masi #81 (7be0619), platform 9f37f03. First hand-run 21:49 Tallinn: OK, complete,
4 requests (the list by its Estonia facet + 3 records), 3 jobs with text, posting dates and deadlines (endDate is the
day the posting comes down: the last day stored is the day before — Raadiovõrgu insener 01.10 for endDate 02.10), all
places kept; 1 merged with a job masi had. Enabled on `0 57 */6 * * *`.

**PLAN 098 COMPLETE (2026-09-29).** Five second-tier sources live and enabled: cvpro.ee, Kuehne+Nagel (Phenom),
Microsoft and Ericsson (Eightfold), Telia (Workday); their first runs listed 36 Estonian postings (21 + 7 + 2 + 3 + 3),
11 of them merging with jobs masi already had (cvpro 9, Ericsson 1, Telia 1). Side fixes on the way: strict dates in every collector (a
"31.02" read as 28.02), ingest keeping a posting date a later run does not say, one description cap for every
collector. Open for later: K+N's Tallinn search past 10 jobs (survey the widget endpoint); Eightfold jobs whose slug
names another country first; 7 of cvpro's 21 "IT" cards are not IT work (the operator's call).
