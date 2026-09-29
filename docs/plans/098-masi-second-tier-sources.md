# 098 — masi: the second-tier job sources

## Decision

Add the job sources plan 094's survey ranked second tier and that still carry Estonian IT postings, highest volume
first, one collector per PR, each seeded **disabled** and enabled after its first run is checked on live data:

1. **cvpro.ee** — full-text RSS (`https://cvpro.ee/et/rss.xml`, 93 items; 20 on the IT category page). It re-lists
   Töötukassa's offers, so its value is the postings nobody else carries; masi's fingerprint dedupe merges the rest.
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

1. masi: `cvpro` — RssCollector over the RSS feed, IT items only (the feed's category), full description; a posting
   Töötukassa also lists merges by fingerprint.
2. masi: AtsCollector vendor `phenom` (K+N), Tallinn/Estonia jobs; job page for the description.
3. masi: vendor `eightfold` (sitemap + ld+json JobPosting), Ericsson and Microsoft rows.
4. masi: vendor `workday` (Telia), relative `postedOn` read against the run's day.
5. platform: allowed hosts per source, pushed before each enable.

## Status

2026-09-29: plan written; volumes measured from the live sites (above).
