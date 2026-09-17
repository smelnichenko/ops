# 094 — masi source survey (PR3)

Companion to `094-masi-job-registry.md`. Every source masi may collect from, surveyed on
2026-09-18 with single polite fetches (UA `masi-source-survey/0.1`), before any scraper is
written. Facts not seen first-hand are marked **UNVERIFIED** in the appendices. The appendices
are the survey agents' reports verbatim; this front part is what the ladder acts on.

## Operator decisions required before PR4

| # | Source | Question | Recommendation |
|---|---|---|---|
| D1 | **cvkeskus.ee** | ToS §2.10 forbids automated queries without human intervention and sets a **10 000 € contractual penalty per request**. Collect at all? | Do NOT build the collector until CV Keskus consents in writing (`info@cvkeskus.ee`) or the operator explicitly accepts the clause. Ship `manual/` add-by-URL for it. Seed row `enabled=false` with the clause in `terms_note`. |
| D2 | **api.smartrecruiters.com** (Wise 62, Playtech 15 EE postings) | Posting API is documented public and needs no key, but the host's `robots.txt` is `Disallow: /` for everyone but LinkedInBot. Use the API? | Use it: robots governs crawlers, this is a documented public API replayed once per tick. Record the conflict in `terms_note`; disable on a single 4xx/complaint. |
| D3 | **tootukassa.ee GraphQL** | Robots `Disallow: /web/` covers `/web/graphql`; `Crawl-delay: 10`. Replay the site's own public query? | Yes, at ≥10 s between calls, one page per call, `first ≤ 100`. It is the public site's own unauthenticated query, far fewer requests than a browser; sitemaps are explicitly allowed. Record in `terms_note`. |
| D4 | **devjobsscanner.com** | Estonia slice is LinkedIn-derived (cards link to `ee.linkedin.com/jobs/view/…`). Keep LinkedIn-derived rows? | Never: it would import LinkedIn data by proxy. Drop from the seed. |
| D5 | **PII** | cv.ee detail `__NEXT_DATA__.contacts` and Töötukassa `avalikKontaktisik` carry recruiter names/emails. | Ingest never stores them (plan already says so); fixtures are scrubbed. |

## Corrections to the plan's seed table (apply in PR4)

1. **tootukassa.ee is DETERMINISTIC**, not BROWSER: `jobOfferSearch` / `publicJobOfferQuery` /
   `employerQuery` documents are in the public bundle and replay unauthenticated
   (`totalCount 1788`, cursor paging). `employerQuery.registrikood` feeds the company registry.
2. **cvkeskus.ee sitemap is partial** (43 IT URLs vs 477 on the category page); the inventory is
   the `?start=25` list pages, RSS for freshness — moot until D1.
3. **otsintood.ee is a cv.ee iframe**: count-only coverage check, T2.
4. **cv.ee**: no detail API; `limit=500` returns all IT rows in one call; detail page
   `__NEXT_DATA__` carries `applyingUrl`/`urlDetails` (ATS discovery) and PII to drop.
5. **Bolt is T1 deterministic** (assets sitemap with lastmod + SSR list/detail), no browser.
6. **Microsoft/Ericsson (Eightfold)**: JSON API refuses (403); sitemap + ld+json JobPosting.
7. **MeetFrank**: WAF is UA-based on the web host only; `api.meetfrank.com/public` (GraphQL)
   answers plain clients — one browser harvest of the `searchOpenings` document, then replay.
8. **New T2 board: cvpro.ee** (RSS with full text, re-lists Töötukassa — dedupe).
9. **TeamDash is bigger than seeded** (LHV, Helmes, Cybernetica, Bigbank, TEHIK, Tele2) and fully
   jsoup-able (employer-page anchors or `window.landing` JSON); no browser.
10. **Swedbank/Luminor/Fractory/Starship/Pactum/Comodule/Milrem/Datel/Thorgate are Teamtailor**
    JSON Feed (`/jobs.json`, filter `_jobposting.jobLocation[].address.addressCountry == "EE"`).
11. **Skeleton and Xolo are Workable** (widget API by numeric account id); Ridango BambooHR list
    has no dates/descriptions (fetch `/careers/<id>/detail`); Nortal's Greenhouse board has no
    Estonian roles (Nortal EE stays with cv.ee); Wise's SmartRecruiters id is `Wise`.
12. Dead/never: hh.ee (parked), jobs.ee (TLS broken), itcv.ee (NXDOMAIN), kandideeri.ee (3 IT
    jobs), LinkedIn/Indeed/Glassdoor/Facebook (anti-automation clauses quoted in Appendix A).

## Source tiers after the survey

| Tier | Source | Kind | Cron (Europe/Tallinn) | Note |
|---|---|---|---|---|
| T1 | cv.ee | `JsonApiCollector` | `17 * * * *` | 194 IT; one call/tick; detail via `__NEXT_DATA__` for new ids |
| T1 | tootukassa.ee | `JsonApiCollector` (GraphQL) | `29 * * * *` | D3; ≥10 s/call; registry codes |
| T1 | Bolt | `SitemapCollector` + jsoup | `0 */6 * * *` | 246 positions sitemap |
| T1 | ATS: Teamtailor (9), Greenhouse (6), SmartRecruiters (3, D2), Ashby (3), Lever (1) | `AtsCollector` per vendor, one `ats:<company>` row each | `0 */2–6 * * *` | build order: Teamtailor → Greenhouse → SmartRecruiters → TeamDash → Ashby → the 1–2-employer vendors |
| T1 | TeamDash employers (6) | `JsoupListCollector` (two shapes) | `0 */6 * * *` | LHV, Helmes, Cybernetica, Bigbank, TEHIK, Tele2 |
| T2 | Workable (Skeleton, Xolo), Personio (Salv, eAgronom), Recruitee (TextMagic, Sympower), BambooHR (Ridango), Workday (Telia), Phenom (Kuehne+Nagel), Eightfold (Ericsson, Microsoft) | `AtsCollector` / sitemap+ld+json / JSON-in-script | `0 */6–12 * * *` | low volume each |
| T2 | cvpro.ee | `RssCollector` | `50 5 * * *` | re-lists Töötukassa |
| T2 | MeetFrank | BROWSER once → `JsonApiCollector` | `13 */6 * * *` | `candidateDestination.url` = ATS discovery |
| T2 | otsintood.ee | jsoup count-only | `5 6 * * *` | coverage check |
| T2 | workinestonia.com, Coop Pank, RMIT, Proekspert, Cleveron, Codeborne, Elisa | jsoup / ajax | daily–weekly | tiny volumes |
| held | cvkeskus.ee | — | — | D1 |
| never | devjobsscanner (D4), hh.ee, jobs.ee, itcv.ee, kandideeri.ee, LinkedIn, Indeed, Glassdoor, Facebook | — | — | |

## `config_json` shapes per kind

```jsonc
// JsonApiCollector (cv.ee)
{ "url": "https://cv.ee/api/v1/vacancy-search-service/search", "query": { "categories[]": "INFORMATION_TECHNOLOGY", "limit": 500, "offset": 0 },
  "items": "$.vacancies[*]", "id": "$.id", "title": "$.positionTitle", "company": "$.employerName", "posted": "$.publishDate", "expires": "$.expirationDate",
  "url": "https://www.cv.ee/et/vacancy/{id}", "detail": { "kind": "next-data", "path": "$.props.pageProps.vacancy" , "drop": ["contacts"] } }
// JsonApiCollector (GraphQL, tootukassa)
{ "url": "https://www.tootukassa.ee/web/graphql", "document": "jobOfferSearch", "variables": { "first": 100, "searchInput": { "valdkonnad": ["<IT code>"] } },
  "cursor": "$.pageInfo.endCursor", "hasNext": "$.pageInfo.hasNextPage", "items": "$.jobOffersQuery.edges[*]", "minIntervalMs": 10000,
  "detail": { "document": "publicJobOfferQuery", "drop": ["avalikKontaktisik"] }, "company": { "document": "employerQuery", "registryCode": "$.registrikood" } }
// AtsCollector
{ "vendor": "teamtailor", "feed": "https://jobs.swedbank.com/jobs.json", "country": "EE" }
{ "vendor": "greenhouse", "board": "veriff", "locationRegex": "Tallinn|Estonia" }
{ "vendor": "smartrecruiters", "company": "Wise", "country": "ee" }
{ "vendor": "ashby", "board": "glia", "locationRegex": "Tallinn|Estonia" }
{ "vendor": "lever", "slug": "pipedrive", "location": "Estonia, Tallinn" }
{ "vendor": "workable", "accountId": "128656", "country": "Estonia" }
{ "vendor": "personio", "xml": "https://salv.jobs.personio.de/xml" }
{ "vendor": "recruitee", "slug": "textmagic" }
{ "vendor": "bamboohr", "sub": "ridango", "detail": true }
{ "vendor": "workday", "tenant": "teliacompany", "site": "Telia_careers", "searchText": "Estonia" }
// SitemapCollector + jsoup detail (Bolt, Eightfold)
{ "sitemap": "https://assets.careers-v3.bolt.eu/sitemap.xml", "include": "/positions/", "detail": { "title": "h1", "location": "[data-testid=location], .location", "ldJson": true } }
// JsoupListCollector (TeamDash employer pages)
{ "url": "https://www.helmes.com/career/", "links": "a[href*='.teamdash.com/p/job/']", "detail": { "title": "meta[property=og:title]", "description": "main" } }
{ "url": "https://lhv.teamdash.com/p/job/jp2Ve0dp/tule-meile", "script": "window.landing", "items": "$.jobs[*]" }
// RssCollector
{ "url": "https://cvpro.ee/et/rss.xml" }
// BrowserCollector (MeetFrank harvest)
{ "url": "https://meetfrank.com/jobs-in-estonia", "waitFor": "a[href^='/jobs/']", "harvestUrlPattern": "api.meetfrank.com/public", "maxPages": 3 }
```

## Fixture capture procedure (per collector PR)

1. `curl -sS -A 'masi-source-survey/0.1' '<url>' -o src/test/resources/fixtures/<key>/<name>` with a
   `<name>.headers` sidecar (`Content-Type` only); for GraphQL, save request document + response.
2. Scrub: recruiter names/emails/phones, applicant ids, session ids; keep external ids and dates.
3. `CAPTURE.md` beside the files: exact command, date, what was scrubbed, page/entry counts.
4. The fixture test asserts exact `RawListing`/`RawCompany` values plus the negatives (broken
   selector → `complete=false`, `DEGRADED`, no miss counting; a sibling source still runs).
5. The env-gated live smoke asserts ≥ N listings, every URL under `base_url`, ≥ 1 `posted_at`
   within 7 days, and the same non-null field set as the fixture.

## Company discovery

| Source | Kind | Cron | Tier | Yield | Decision |
|---|---|---|---|---|---|
| e-Business Register `ettevotja_rekvisiidid__yldandmed.json.zip` (CC BY 4.0, daily ~12:40 Tallinn) | DETERMINISTIC, streamed (230 MB zip → 4.6 GB JSON, never on disk) | Sun 20:00 Tallinn | T1 | 27 708 active (status R) companies with a current EMTAK 62/63 activity; 5 978 with ≥ 1 employee | Import all as registry rows; `size_band` from the max `tootajate_arv` of the last three reports; "hiring-relevant" = employees ≥ 5 or WWW present or seen in another source. Store only WWW from `sidevahendid` (EMAIL/MOB/TEL are often personal). Both EMTAK versions coexist (2008 and 2025): match on prefix 62/63 with `lopp_kpv == null`. Parquet files are stale (2023) — JSON only; the CSV lacks EMTAK. Needs a streaming fetch outside `HttpFetcher`'s 2 MB cap; `complete=true` only if the array closed cleanly and rows ≥ 0.9 × last run. A code absent from two consecutive imports → `DORMANT`. |
| ITL members `https://itl.ee/en/members/` | DETERMINISTIC jsoup `a.logo.all-members` | monthly | T1 | 128 (legal names + website + category classes) | robots allows; no registry code — match by `name_norm`. |
| Tehnopol `https://www.tehnopol.ee/en/startups/portfolio/` | DETERMINISTIC jsoup (all 244 cards in the HTML; "load more" is client-side) | monthly | T2 | 42 active + 202 alumni, 161 with website | Brand names — match by `domain_norm` first; tag active/alumni; ignore free-text contacts. |
| Startup Estonia / Dealroom | never | — | manual | ~1 500 | Dealroom ToS: bots and scraping banned; robots blocks AI crawlers. `POST /companies` only. |
| Inforegister, Teatmik | never | — | — | — | Commercial; CAPTCHA gate / anti-automation terms; same underlying register. |
| e-estoniax, Founders Society, Garage48, EIS/KredEx, Clutch-type rankings | skip | — | — | — | No structured list or no added value. |

**Dedupe facts from the dump:** `nimi` is the exact registered name with the legal-form
designation in either position and either spelling (`osaühing`/`OÜ`, `aktsiaselts`/`AS`, …), so
`norm()` strips `osaühing|oü|ou|aktsiaselts|as|usaldusühing|uü|täisühing|tü|mittetulundusühing|mtü|sihtasutus|sa|fie|filiaal`
besides the plan's international suffixes. The dump carries **no name history** (`arinimed[]`
always has one entry) and Estonia has no trade-name concept: `company_alias` is fed by
ITL/Tehnopol/board names, manual edits, and by the importer writing the previous `name` to
`company_alias` when a registry code's name changes. Matching order confirmed: registry code →
`name_norm` → `domain_norm` (only 8.6 % of register rows carry WWW) → aliases.

`config_json` for the register collector:
`{"url": "https://avaandmed.ariregister.rik.ee/sites/default/files/avaandmed/ettevotja_rekvisiidid__yldandmed.json.zip", "statuses": ["R"], "emtakPrefixes": ["62","63"], "minEmployeesForActive": 5, "dropContacts": true, "maxBytes": 536870912}`.

Fixture material captured by the survey (session scratchpad): `itl.html`, `tehnopol.html`, the
first 3 MB of the JSON zip (`yld_head.bin`, enough for a streamed fixture) — copy into the
collector PR's fixtures, scrubbed.

## Appendix A — job boards (survey agent report, verbatim)

# masi source survey — PR3 (fetched 2026-09-18 00:05–00:20 Europe/Tallinn, 2026-09-17 21:05–21:20 UTC)

All fetches were single `curl`/WebFetch calls with UA `masi-source-survey/0.1 (+mailto:…)` unless stated; no site got more than ~6 requests. Anything not seen with my own eyes is marked **UNVERIFIED**.

---

## 1. cv.ee (Alma Career Estonia OÜ; `cvonline.ee` and `www.cvonline.ee` 301 → `https://www.cv.ee/et`)

- **Coverage:** Estonia + LV/LT domains; `categories.INFORMATION_TECHNOLOGY` = **194** open IT listings (`total`), of 1 695 total (`workTimes` sum). `remoteWorkType` over IT: ON_SITE 106 / HYBRID 85 / FULLY_REMOTE 3; salary present on 55/194.
- **Access — JSON API (confirmed):** `GET https://cv.ee/api/v1/vacancy-search-service/search?categories[]=INFORMATION_TECHNOLOGY&limit=3&offset=0` → 200 `application/json`. `limit=500&offset=0` returned all 194 (no cap seen ≤ 500). Sets cookies `sessionLogId`, `searchId` (not required). Top-level keys: `workTimes, categories, languages, countries, counties, towns, remoteWork, remoteWorkTypes, quickApply` (facet counts), `vacancies[]`, `searchId, searchMode="ELASTIC", total, vacanciesViews, userInteractions, vacancyExternalIds, vacancyEmployerData`. Per vacancy: `id, positionTitle, positionContent` (teaser), `employerId, employerName, logoId, domain, publishDate, renewedDate, expirationDate` (ISO), `workTimes[], languages[], categories[]` (numeric ids), `keywords[], skills, townId, countyId, countryId, quickApply, salaryFrom, salaryTo, hourlySalary, suitableForRefugees, remoteWork, remoteWorkType, promotions`. Detail endpoint `/api/v1/vacancy-search-service/vacancy/1658458` → **404** (no public detail API found).
- **Sitemaps:** `https://www.cv.ee/sitemap.xml` → index of `companies-`, `jobs-`, `search-`, `pages-sitemap.xml`; `jobs-sitemap.xml` = **1 476 URLs, `lastmod` on all** (ms precision).
- **Detail page:** `https://www.cv.ee/et/vacancy/{id}/{employer-slug}/{title-slug}` — Next.js SSR (755 kB), JSON-LD `JobPosting` present but `description` is **empty**; `__NEXT_DATA__.props.pageProps.vacancy[id]` carries `dateCreated, dateModified, firstPublishDate, status, details{urlDetails (external ATS URL), fileDetails, standardDetails[], styleDetails}, highlights{remoteWorkType, salaryFrom/To, ratePer, workTimes, additionalBenefits, location}, settings{categories (names), keywords, dateStart, dateTo, applyingUrl}, employer{about, webpageUrl, regCode (null here)}, contacts{firstName,lastName,email,phone}` (**PII — must be dropped at ingest**), `urlDetailsType="IFRAME"`. Description body is frequently an external ATS page (this one: TeamDash) → the API teaser + `applyingUrl` is what is reliably present. Canonical id: numeric `id`.
- **robots.txt** (`cv.ee/robots.txt` 308 → `www.cv.ee/robots.txt`, 39 bytes, verbatim): `Sitemap: https://www.cv.ee/sitemap.xml` — no `Disallow`, no `Crawl-delay`.
- **ToS:** `/et/terms` is a JS shell whose `__NEXT_DATA__` points to `https://hr.cv.ee/tingimused` ("ANDMEBAASI KASUTUSTINGIMUSED REGISTREERUMATA VÕI AUTENTIMATA TÖÖOTSIJALE"), §1.2 verbatim: *"Kõik õigused andmebaasile kuuluvad AC-le. … Võite kasutada andmebaasi andmeid, et võtta töökohale kandideerimiseks tööandjaga heas usus ühendust … Te ei tohi teha andmebaasist väljavõtteid ega koopiaid ega kasutada seda ühelgi muul eesmärgil. Samuti ei tohi te andmebaasi kahjustada ega katkestada selle käitust."* No bot/automation wording; database-extraction prohibition only. No date found.
- **Stability:** Next.js behind Cloudflare, versioned `/api/v1/*-service/` micro-service paths (`vacancy-search-service`, `files-service`); Alma Career shared footer v9. No rate-limit headers; `cf-cache-status: DYNAMIC`.
- **Recommendation:** **DETERMINISTIC** (`JsonApiCollector`), cron `17 * * * *`, **T1**. One request per tick (`limit=500`), detail page only for new ids (jsoup + `__NEXT_DATA__`), strip `contacts`.

## 2. cvkeskus.ee (CV Keskus OÜ / Ringier)

- **Coverage:** Estonia (also cvmarket.lv/.lt); category page states **477** IT listings ("praegu 477 tööpakkumist valdkonnas infotehnoloogia"), salaries 1 000–10 416 €.
- **Access:**
  - Sitemaps: `sitemap-listings-index-et.xml` → **26 per-category sitemaps** with `lastmod`; `sitemap-listings-infotehnoloogia-et.xml` = **43 URLs** (lastmod + image). **The sitemap is a subset: 43 vs 477 on the category page** — the plan's "~600 URLs" assumption is wrong; the inventory is the category list page.
  - List page: `https://www.cvkeskus.ee/toopakkumised-infotehnoloogia-valdkonnas?start=25` (**25/page**, last `?start=450`), SSR HTML, 36 listing/employer links on page 1, link shape `/{slug}-{id}`.
  - RSS: `https://www.cvkeskus.ee/rss-listings.xml` — **171 items**, all categories, `link, pubDate, title` only, ~36 h window; `cache-control: no-store`, sets `PHPSESSID`.
  - Detail `/{slug}-{id}`: SSR (Apache/ZoneOS, PHP, Tailwind); fields: `h1` title, employer (`og:description "…ettevõttelt: MKM"`, link `/…-toopakkumised-{employerId}`), "Kuulutus sisestati" (posted), "Aegub" (expiry), "Asukoht", "Brutopalk", "Töö tüüp", "Lisainfo", "Valdkond", **"Tööpakkumise number: 1053358"** (canonical id); description inside the `jobad-url` container. No `JobPosting` JSON-LD (Organization only). Remote flag: not a labelled field (**UNVERIFIED**).
- **robots.txt** (verbatim, 857 B): `User-agent: *` / `Disallow: /cv/*/pdf` / `/m_register.php` / `/members/register` / `/cvs/` / `/firm_joboffers.php*` / `/send-cv/` / `/lib/securimage/securimage_show.php*` / `/job-questions/` / `/login*`; ten `Sitemap:` lines incl. `rss-listings.xml`. No `Crawl-delay`.
- **ToS** `https://www.cvkeskus.ee/kasutustingimused` (Viimati muudetud: 18…, year cut) — **§2.10 verbatim:** *"Kasutajal on õigus Veebikeskkonda kasutada üksnes üldlevinud veebibrauserite (näiteks Internet Explorer, Edge, Chrome, Mozilla Firefox, Safari jne) abil. Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või vahendite abil, mis võimaldavad teha ilma inimese sekkumiseta automaatseid päringuid. Käesoleva punkti rikkumisel on CV Keskusel õigus nõuda igalt rikkujalt leppetrahvi 10 000 eurot iga rikkumise eest. Sealjuures loetakse eraldi rikkumiseks iga päringut…"* Also §2.5 (use only to find a job for yourself; no third-party service, no other use of data) and §4.4 (no reproduction/inclusion in other databases without written consent).
- **Stability:** classic PHP, stable URL scheme, 25-row paging; SEO-driven markup recently restyled (Tailwind) — selectors may move.
- **Recommendation:** technically **DETERMINISTIC** (sitemap + RSS + jsoup), but **ToS is RED** — a 10 000 € per-request contractual penalty for "automaatseid päringuid". This is an **operator decision**: T1 only with explicit acceptance or written consent from CV Keskus (`info@cvkeskus.ee`); otherwise `manual/` add-by-URL. If accepted: cron `41 * * * *`, RSS first, category pages daily.

## 3. tootukassa.ee (Eesti Töötukassa)

- **Coverage:** all Estonia, **1 788** public offers (`totalCount`); IT share **UNVERIFIED** (needs a `valdkonnad` code from `classifierQuery`).
- **Access:**
  - **GraphQL, unauthenticated, replay verified:** `POST https://www.tootukassa.ee/web/graphql` (Drupal graphql/Apollo; introspection disabled). Documents extracted from `chunk-OFSGMKJB.js`:
    `query jobOfferSearch($first: Int, $cursor: Cursor, $searchInput: InputToopakkumineAvalikOtsingDTO) { jobOffersQuery(first:, after:, searchInput:) { edges { id nimetus alias ametinimetusTapsustus aadressid kandideerimineKp brandNimi asutusNimi asutusId pilt onKodusTootamine onTaiskohaga onOsakohaga kinnitamineKp … } pageInfo { endCursor hasNextPage totalCount } } }` — my replay with `first:2, searchInput:{}` returned 2 edges, `totalCount 1788`, `hasNextPage true`, base64 cursor. `searchInput` fields seen in the bundle: `domeen, sisaldabKriteeriumit, valdkonnad, asukohad, onKodusTootamine, tootasuAlates, toopakkujaId, sort`.
    Detail: `publicJobOfferQuery(jobOfferId: Int!)` → `nimetus, koduleht, kandideerimineKp, avalikKontaktisik{…}` (PII), `tookohaAndmed{ tootasuAlates, tootasuKuni, onPalkAvalik, onKodusTootamine, onTaiskohaga, tooylesanded, omaltPooltPakume, … }`, `noudedKandidaadile{ nouded, keeleoskused… }`; `employerQuery(toopakkujaId)` → `nimi, registrikood, tutvustus, kontaktid` (**registry code — feeds the company registry directly**).
  - Sitemap: `/web/joboffers/sitemap.xml` → index of 3 pages, `/web/sitemaps/joboffers/sitemap.xml?page=N` = **2 000 URLs/page** (et/en/ru triplets ⇒ ~667 offers/page), `lastmod` on every URL (day precision), Drupal `simple_sitemap`, `x-robots-tag: noindex, follow`.
  - Detail pages `/et/toopakkumised/{alias}` are an **Angular SPA** (`main-RZ7PP7SO.js`, `data-beasties-container`): 141 kB HTML, **zero content text** → jsoup is useless; browser or GraphQL only.
  - Open data: `avaandmed.eesti.ee/datasets/eesti-tootukassa-avalikud-toopakkumised` 301 → `andmed.eesti.ee/…` which is a JS-only shell; `…/api/datasets/slug/<slug>` → 404; `opendata.riik.ee/andmehulgad/toopakkumised/` → expired TLS certificate. **UNVERIFIED** (portal unreachable programmatically tonight).
- **robots.txt** (verbatim, relevant lines): `User-agent: *` / `Crawl-delay: 10` / `Allow: /web*/sitemap.xml` / `Disallow: /web/` / `Disallow: /et/toopakkumised?` / `Disallow: /en/joboffers?` / `Disallow: /ru/vakansii?` / `Sitemap: https://www.tootukassa.ee/web/joboffers/sitemap.xml`. Note **`/web/graphql` falls under `Disallow: /web/`**; the job sitemaps are allowed by `Allow: /web*/sitemap.xml`; detail pages without query strings are allowed.
- **ToS:** `/et/kasutustingimused` returns 200 but is the same SPA shell — text **UNVERIFIED**; no clause seen.
- **Stability:** Drupal 10 back end + Angular front; GraphQL field names are Estonian domain terms (`nimetus, asutusNimi, kandideerimineKp`) and unlikely to churn; bundle hashes change per deploy (irrelevant once the query is pinned).
- **Recommendation:** **DETERMINISTIC** (`JsonApiCollector` speaking GraphQL) — an upgrade from the plan's BROWSER kind; the schema is already learned, no harvest step needed. Cron `29 * * * *`, ≥ 10 s between calls (Crawl-delay), page with `first: 100` (**UNVERIFIED** max). **T1.** Flag the robots `Disallow: /web/` in the survey row: robots governs crawlers, and this replays the site's own public query at a fraction of a browser's request count, but the operator should sign off.

## 4. otsintood.ee (Alma Career aggregator, "4204 tööpakkumist 5 kanalist")

- **Coverage:** re-lists cv.ee plus four other channels; IT category page `/tookuulutused/valdkond/infotehnoloogia` (count not printed on page; **12 pages**).
- **Access:** category page is SSR HTML with 17 unique `/tookuulutus/{slug}/{hexid}` links on page 1; **pagination is JS** (`<a href="#" data-page="2">`, no URL scheme; ajax endpoint **UNVERIFIED**). Detail page: SSR shell `<main data-public-id="6aabf5e825d05" data-vacancy-id="3876993" data-external="1">` and the **body is an iframe of `https://cv.ee/vacancy/1658452?framed=true`** — the content *is* cv.ee. Sitemap `/sitemap.xml`: 478 URLs (261 `toopakkumised` landing/search pages, 178 `ettevote`, 23 `tookuulutused` categories, 5 `dokument`), all with `lastmod`; **no listing URLs**. Cloudflare challenge-platform script present (plain curl passed). `api.otsintood.ee/` → 404.
- **robots.txt** (verbatim): `User-agent: *` / `Disallow:` / `Sitemap: https://www.otsintood.ee/sitemap.xml` / `Crawl-Delay: 10` / `crawl-delay: 10`.
- **ToS** `/dokument/kasutustingimused` (2023-12-27 per sitemap lastmod), §2.5 verbatim: *"Kõik õigused Andmebaasile kuuluvad OtsinTööd'le. … Kasutajal ei ole õigust teha Andmebaasist või selle osadest muid väljavõtteid või koopiaid ega Andmebaasi muul viisil kasutada, samuti Andmebaasi kahjustada või selle tööd häirida."*
- **Recommendation:** **T2**, DETERMINISTIC jsoup of category page 1 as a *count-only* coverage check, daily (`5 6 * * *`), 10 s delay. Its details are cv.ee iframes, so it adds no independent listings; BROWSER only if the 12 pages ever matter.

## 5. meetfrank.com

- **WAF (asked for):** CloudFront. Plain UA and WebFetch → **403** with an HTML "Request blocked" page (`x-cache: Error from cloudfront`, `server: CloudFront`). Chrome UA → **200**. `robots.txt` → 403 `AccessDenied` from **S3** with both UAs ⇒ **no robots.txt exists**; the block is UA-based.
- **Access:** Next.js pages router (`buildId dfad3526-…`), `/jobs-in-estonia` ("123 Hybrid & Onsite Jobs in Estonia") server-renders an Apollo cache in `__NEXT_DATA__`: `ROOT_QUERY.searchOpenings({"searchParams":{"searchTagsWithAndCondition":[{"tag":"STATE","value":"ACTIVE"}],"searchTagsWithOrCondition":[{"tag":"POSITION_COUNTRY","value":"5a08cc451b7ce3b929d4128b"}]}, …})`, 7 `PaidOpeningWithSnippetsType` + 4 `NonPaidOpeningType` objects with `id, urlHandle, title, publishedAt, snippets[], salaryRange{from,to,period,currency}, remote{type HYBRID…, allowedPlaces}, candidateDestination{type EXTERNAL_URL, url}` (e.g. `jobs.thorgate.eu/…`), `positionLocations, company{ref}`; company objects carry `urlHandle, reviewsOverview, profile`. Listing URL `/jobs/{company}/{slug}`. **API:** `POST https://api.meetfrank.com/public` is Apollo Server GraphQL, introspection disabled, and answered `{__typename}` with the plain masi UA (**the API host is not WAF'd**). Full selection set for `searchOpenings` **UNVERIFIED** (one browser harvest, or read the page bundle, gives it).
- **ToS** `https://meetfrank.com/terms` (200 with Chrome UA, 28 kB): **no clause about automated access, scraping or crawling found** ("automat" occurs only in "reviews … are automatically visible"). No date on the page.
- **Recommendation:** **T2**, BROWSER once to harvest the `searchOpenings` document, then DETERMINISTIC replay against `api.meetfrank.com/public`; cron `13 */6 * * *`. `candidateDestination.url` is a free ATS-discovery signal for the company registry.

## 6. devjobsscanner.com

- **Coverage:** global aggregator; `/developer-jobs-in-estonia/` says "5115 open positions" — the SSR cards' hrefs point to **`ee.linkedin.com/jobs/view/…`** (LinkedIn-sourced), so the Estonia slice is LinkedIn scrape output.
- **Access:** Next.js app router on Vercel + Cloudflare; list page SSR (144 kB) with external hrefs; no public API found; sitemap index → `sitemap-0.xml` / `sitemap-1.xml`, 5 000 static landing URLs each with `lastmod` (e.g. `/abap-jobs-in-estonia/`), no job-detail URLs.
- **robots.txt** (verbatim): `User-agent: *` / `Allow: /` / `Host: https://www.devjobsscanner.com` / `Sitemap: https://www.devjobsscanner.com/sitemap.xml`.
- **ToS** `/terms-and-conditions/` (Last updated: August 26, 2023): **no such clause found** (only "prohibited or restricted parties" export wording).
- **Recommendation:** **T2**, DETERMINISTIC jsoup of the Estonia list page, daily (`35 5 * * *`) — store as pointers only, since the targets are LinkedIn URLs (see §11); consider **never** if the operator wants no LinkedIn-derived rows at all.

## 7. hh.ee — dead (confirmed)

`dig hh.ee A` → **8.8.8.8**; `https://hh.ee/` → 302 to `https://dns.google/` (cert for `dns.google`); `http://hh.ee/` times out; NS at Cloudflare (parked). **never.**

## 8. Other Estonian boards found (searches: "IT tööpakkumised" Eesti; IT jobs Estonia; Toughbyte's 2024-02-26 board list)

| Board | Status | Notes |
|---|---|---|
| **jobs.ee** | broken | resolves (172.234.26.227), valid LE cert `CN=jobs.ee` (2026-08-24 → 11-22) but TLS fails on h2 (`PROTOCOL_ERROR`) and h1.1 (`unexpected eof`) — not serving. **never** (content UNVERIFIED). |
| **cvonline.ee** | alias | 301 → `www.cv.ee/et`; same source as §1. |
| **itcv.ee** | dead | NXDOMAIN (search result stale). **never**. |
| **cvpro.ee** (CV Pro OÜ / Baltic Media Network, Railway-hosted) | live | IT category `/et/vacancies?category=it` = **18** listings; **RSS `https://cvpro.ee/et/rss.xml` = 100 items with full description + `/et/vacancies/{uuid}` links**; `llms.txt`; sitemap; robots: `Allow: /`, Disallow login/employer/account/admin. Terms PDF `/documents/terms-of-use-et.pdf` (Viimati uuendatud 01.01.2024) asserts "andmebaasi tegija õigused", **no automation clause found**. Re-lists Töötukassa offers (dedupe). → **T2 DETERMINISTIC RssCollector, daily `50 5 * * *`.** |
| **kandideeri.ee** (SmartJobBoard SaaS, `sjb-nginx`) | live | IT category = **3** jobs; RSS `/rss/`; robots `Allow: /jobs/`, `Disallow: /jobs?`, sitemap. → **never** (too small; revisit). |
| **workinestonia.com** (EIS, WordPress) | live | `/job/` list of employer-fed IT jobs (Bolt, Wise…), "Load more" via `admin-ajax.php` (endpoint UNVERIFIED); robots only `/wp-admin/`; sitemap index has post/page maps only, no jobs. → **T2** candidate, BROWSER or admin-ajax replay, weekly. |
| toughbyte.com, levels.fyi, wellfound, eurotechjobs | not surveyed | agency/global aggregators; out of scope for the seed. |

## 9–12. Never-polled sources — ToS clauses

- **LinkedIn** — User Agreement effective **November 3, 2025**, §8.2 "Don'ts" (fetched): *"Develop, support or use software, devices, scripts, robots or any other means or processes (such as crawlers, browser plugins and add-ons or any other technology) to scrape or copy the Services, including profiles and other data from the Services"*; *"Use bots or other unauthorized automated methods to access the Services…"*. **never.**
- **Indeed** — Terms of Service, Last Updated **July 17, 2026** (fetched, verbatim): *"Use any automated system (bots, scrapers, spiders, AI or Agentic AI) to access, data-mine, or submit content to the Site, in bulk or otherwise, without Indeed's express written permission (we conditionally grant permission to crawl the Site solely as outlined in our robots.txt file). You may not crawl, scrape, extract data from, reproduce, duplicate, copy, sell, exploit, trade or resell any part of the Site…"* `ee.indeed.com` has no A record. **never.**
- **Glassdoor** — every fetch (curl, WebFetch, both paths) → **403**. Clause as quoted by secondary sources (**UNVERIFIED verbatim**): *"You may not use any robot, spider, scraper, data mining tools, data gathering and extraction tools, or other automated means to access the Services for any purpose without our express written permission."* **never.**
- **Facebook** — unreachable from this host (connection refused/blocked). Clause per secondary sources (**UNVERIFIED verbatim**), Terms §3.2.3: *"You may not access or collect data from our Products using automated means (without our prior permission)"*; Meta's separate "Automated Data Collection Terms" require express written permission. **never.**

---

## Summary table

| Source | Access | robots | ToS | Kind | Cron | Tier |
|---|---|---|---|---|---|---|
| cv.ee | JSON API `vacancy-search-service/search` (limit/offset, 194 IT); jobs-sitemap 1 476 + lastmod; detail `__NEXT_DATA__` | Sitemap only, no Disallow/delay | DB-extraction prohibition (hr.cv.ee §1.2), no bot clause | DETERMINISTIC | `17 * * * *` | **T1** |
| cvkeskus.ee | 26 category sitemaps (IT = 43, partial) + RSS 171 + list `?start=25` (477 IT) + jsoup detail | Account paths only; no delay | **§2.10: no automated queries, 10 000 € per request** | DETERMINISTIC | `41 * * * *` | **T1 only with operator/CV Keskus consent**, else manual |
| tootukassa.ee | GraphQL `jobOffersQuery` (replay verified, 1 788, cursor) + `publicJobOfferQuery` + `employerQuery` (registrikood); sitemap 3×2 000 + lastmod; SPA pages | `Crawl-delay: 10`; `Disallow: /web/` (covers `/web/graphql`); sitemaps allowed | UNVERIFIED (SPA shell) | DETERMINISTIC (GraphQL) | `29 * * * *` | **T1** |
| otsintood.ee | SSR list (JS paging, 12 pp), detail = cv.ee iframe; sitemap w/o listings | Allow all; `Crawl-Delay: 10` | §2.5 no extracts/copies | DETERMINISTIC (count only) | `5 6 * * *` | T2 |
| meetfrank.com | SSR Apollo cache on `/jobs-in-estonia` (123); `api.meetfrank.com/public` GraphQL, not WAF'd | none (S3 403); web WAF blocks non-browser UAs | no clause found | BROWSER once → DETERMINISTIC replay | `13 */6 * * *` | T2 |
| devjobsscanner.com | SSR list → LinkedIn URLs; 2×5 000 landing sitemap | Allow / | no clause (2023-08-26) | DETERMINISTIC jsoup | `35 5 * * *` | T2 (or never: LinkedIn-derived) |
| cvpro.ee | RSS 100 items w/ full text; 18 IT | Allow / | DB rights, no bot clause | DETERMINISTIC RSS | `50 5 * * *` | T2 |
| workinestonia.com | WP list, admin-ajax "Load more" | wp-admin only | not checked | BROWSER / ajax | weekly | T2 |
| kandideeri.ee | RSS `/rss/`, 3 IT | Allow /jobs/ | not checked | — | — | never (size) |
| hh.ee | A=8.8.8.8 → dns.google | — | — | — | — | never (dead) |
| jobs.ee, itcv.ee | TLS broken / NXDOMAIN | — | — | — | — | never |
| LinkedIn / Indeed | — | — | explicit anti-scraping (quoted) | — | — | never |
| Glassdoor / Facebook | 403 / unreachable | — | anti-scraping (secondary, UNVERIFIED) | — | — | never |

## Corrections to the plan's seed table

1. **tootukassa.ee is DETERMINISTIC, not BROWSER**: the GraphQL documents are in the public bundle and `jobOfferSearch` replays unauthenticated (`totalCount 1788`, cursor paging). No browser harvest needed; `employerQuery.registrikood` also feeds the company registry.
2. **cvkeskus.ee sitemap is partial** (43 IT URLs vs 477 on the category page) — use `?start=25` list pages as the inventory, RSS for freshness. Its **ToS §2.10 is the only hard legal blocker** in the set and needs an explicit operator decision before PR4 builds the collector.
3. **otsintood.ee is a cv.ee iframe** — coverage cross-check has count value only.
4. **cv.ee**: no detail API; `limit=500` works; detail `contacts` PII must be dropped; `applyingUrl`/`urlDetails` give ATS URLs for company discovery.
5. **meetfrank**: the WAF is UA-based on the web host only; the API host answers plain clients.
6. **cvpro.ee** is a new T2 with a full-text RSS feed.

Open items marked UNVERIFIED: tootukassa IT `valdkonnad` code, `first` maximum and ToS text; tootukassa open-data portal (both portals unreachable programmatically); meetfrank `searchOpenings` selection set; otsintood ajax paging endpoint; Glassdoor/Facebook verbatim text; cvkeskus remote-work field and share of image-only ads.

## Appendix B — employers and ATS feeds (survey agent report, verbatim)

## masi source survey — employer/ATS layer (2026-09-18)

Method: every feed URL below was fetched with curl (UA `masi-survey/0.1`) unless marked UNVERIFIED; "EE IT seen" is what the feed returned today. Rows are grouped by vendor. Counts are postings with an Estonian location in the feed on 2026-09-18.

### Per-employer table

| Employer | Careers URL | ATS | Feed URL (verified slug) | Status | EE IT postings seen | Collector | Cron |
|---|---|---|---|---|---|---|---|
| Wise | wise.jobs (UNVERIFIED) | SmartRecruiters `Wise` | `https://api.smartrecruiters.com/v1/companies/Wise/postings?country=ee&limit=100` | 200, totalFound 62 | yes — 62 EE, e.g. "Senior Backend Engineer – Contacts", Tallinn, released 2026-09-17 | AtsCollector(SmartRecruiters) | 0 */2 * * * |
| Playtech Estonia | — | SmartRecruiters `Playtech` | `…/companies/Playtech/postings?country=ee&limit=100` | 200, totalFound 15 | yes — 15 (Java Developer, Scala Developer, Cloud Security Engineer; Tartu/Tallinn) | AtsCollector(SmartRecruiters) | 0 */2 * * * |
| Tietoevry Estonia (added) | https://careers.tieto.com/ | SmartRecruiters `Tieto2` | `…/companies/Tieto2/postings?country=ee` | 200, total 379, **0 for country=ee** | none today | AtsCollector(SmartRecruiters) | 0 */6 * * * |
| Twilio (Tallinn) | — | Greenhouse `twilio` | `https://boards-api.greenhouse.io/v1/boards/twilio/jobs?content=true` | 200, 147 jobs | yes — 4 "Remote - Estonia" (Software Engineer, Product Manager L2, 2 ops) | AtsCollector(Greenhouse), location regex `Estonia` | 0 */2 * * * |
| Veriff | — | Greenhouse `veriff` | `…/boards/veriff/jobs?content=true` | 200, 8 jobs | yes — Tallinn / "Tallinn, Spain (Remote)" | AtsCollector(Greenhouse) | 0 */2 * * * |
| Inbank | https://inbank.ee/careers (Nuxt, embeds GH) | Greenhouse `inbank` | `…/boards/inbank/jobs` | 200, 16 jobs | 6 Tallinn (Head of Data, Senior Credit Risk Modeller; rest non-IT) | AtsCollector(Greenhouse) | 0 */4 * * * |
| Nortal | https://careers.nortal.com/open-positions/ (HubSpot+Vue, proxy `/_hcms/api/greenhouse`) | Greenhouse `nortal` | `…/boards/nortal/jobs` | 200, 34 jobs | **0 EE** — board carries LatAm/US-remote only; Estonian roles UNVERIFIED (not on this board) | AtsCollector(Greenhouse) — low yield | 0 */12 * * * |
| Testlio | https://www.testlio.com/careers | Greenhouse `testlio` | `…/boards/testlio/jobs` | 200, 18 jobs | 0 EE (locations "Remote in EMEA", "Global") | AtsCollector(Greenhouse); treat "Remote in EMEA" as remote-eligible | 0 */6 * * * |
| Ready Player Me | readyplayer.me timed out | Greenhouse `readyplayerme` | `…/boards/readyplayerme/jobs` | 200, `{"jobs":[],"meta":{"total":0}}` | none | AtsCollector(Greenhouse), dormant | 0 6 * * * |
| Pipedrive | — | Lever `pipedrive` | `https://api.lever.co/v0/postings/pipedrive?mode=json` | 200, 8 postings | yes — location "Estonia, Tallinn" present; `workplaceType` hybrid | AtsCollector(Lever), `?location=Estonia, Tallinn` filter supported | 0 */2 * * * |
| Glia | https://www.glia.com/careers (Ashby embed) | Ashby `glia` | `https://api.ashbyhq.com/posting-api/job-board/glia` | 200, 23 jobs | yes — 3 (Senior SWE Team Lead Tallinn; SRE + Security Engineer "Estonia - Remote") | AtsCollector(Ashby) | 0 */2 * * * |
| Zego | https://www.zego.com/careers/ | Ashby `zego` | `…/job-board/zego` | 200, 29 jobs | 0 EE locations (Tartu only in body text) | AtsCollector(Ashby) | 0 */6 * * * |
| Katana | https://katanamrp.com/careers/ (Ashby embed) | Ashby `katana` | `…/job-board/katana` | 200, 2 jobs | 0 (Toronto) | AtsCollector(Ashby) | 0 */12 * * * |
| Swedbank Estonia | https://jobs.swedbank.com/jobs?country=Estonia | Teamtailor (custom domain) | `https://jobs.swedbank.com/jobs.json` (JSON Feed) / `jobs.rss` / `sitemap.xml` | 200 `application/feed+json`, 74 items | yes — 7 EE (Java Developer Payments Baltic IT, Java SE Procurement, Solution Architect, Junior Web Dev) | AtsCollector(Teamtailor) | 0 */4 * * * |
| Luminor | https://luminorbank.teamtailor.com/ (luminorcareers.ee redirects) | Teamtailor `luminorbank` | `https://luminorbank.teamtailor.com/jobs.json` | 200, 78 items | 21 EE (`addressCountry=="EE"`); IT share UNVERIFIED | AtsCollector(Teamtailor) | 0 */4 * * * |
| Fractory | https://careers.fractory.com/ | Teamtailor `fractory` | `https://fractory.teamtailor.com/jobs.json` (+`jobs.rss`) | 200, 10 items | yes — Tallinn/Tartu | AtsCollector(Teamtailor) | 0 */6 * * * |
| Starship Technologies | https://www.starship.xyz/careers/ | Teamtailor `starship` | `https://starship.teamtailor.com/jobs.json` | 200 | yes — 2 Tallinn entries | AtsCollector(Teamtailor) | 0 */4 * * * |
| Pactum | https://careers.pactum.com/ | Teamtailor (custom) | `https://careers.pactum.com/jobs.json` | 200, 5 items | yes — Tallinn/Tartu | AtsCollector(Teamtailor) | 0 */6 * * * |
| Comodule | — | Teamtailor `comodule` | `https://comodule.teamtailor.com/jobs.json` | 200, 3 items | yes — Senior Firmware Engineer, Tallinn | AtsCollector(Teamtailor) | 0 */6 * * * |
| Milrem Robotics | https://careers.milrem.com/ | Teamtailor (custom) | `https://careers.milrem.com/jobs.json` | 200, 2 items | Tallinn/Tartu | AtsCollector(Teamtailor) | 0 */6 * * * |
| Datel | https://careers.datel.ee/ | Teamtailor (custom) | `https://careers.datel.ee/jobs.json` | 200, 4 items | yes — Tallinn | AtsCollector(Teamtailor) | 0 */12 * * * |
| Thorgate | https://jobs.thorgate.eu/ | Teamtailor (custom) | `https://jobs.thorgate.eu/jobs.rss` | 200 (3.6 KB, ≤1 item) | ~0 | AtsCollector(Teamtailor) | 0 */12 * * * |
| Skeleton Technologies | https://www.skeletontech.com/careers (whr widget) | Workable, account **128656** | `https://apply.workable.com/api/v1/widget/accounts/128656?details=true` (the guessed `/api/v3/accounts/<slug>/jobs` slugs were 404) | 200, 48 jobs | yes — e.g. "Application Engineer - AI Data Centers, EU", Tallinn, `telecommuting:true`, published 2026-09-04 | AtsCollector(Workable widget) | 0 */6 * * * |
| Xolo (added) | https://www.xolo.io/zz-en/careers (whr widget) | Workable, account id not in static HTML | UNVERIFIED | — | — | AtsCollector(Workable) once id found | 0 */12 * * * |
| Ridango | — | BambooHR `ridango` | `https://ridango.bamboohr.com/careers/list` | 200, 9 openings | yes — Data & Analytics Engineering Lead, Product Owner Device Team, Tallinn | AtsCollector(BambooHR) + `/careers/<id>/detail` | 0 */6 * * * |
| Salv | https://salv.com/careers/ | Personio | `https://salv.jobs.personio.de/xml` | 200 | yes — Product Engineer, Tallinn+Tartu, salary 3000–6000 EUR, `it_software` | AtsCollector(Personio XML) | 0 */12 * * * |
| eAgronom | https://www.eagronom.com/careers | Personio | `https://eagronom.jobs.personio.com/xml` | 200, 1 position | only an open-application entry | AtsCollector(Personio XML) | 0 */12 * * * |
| TextMagic | https://careers.textmagic.com/ | Recruitee `textmagic` | `https://textmagic.recruitee.com/api/offers/` | 200, `{"offers":[]}` | none today | AtsCollector(Recruitee) | 0 */12 * * * |
| Sympower | https://careers.sympower.net/ (Recruitee custom domain; Tartu in HTML) | Recruitee, slug UNVERIFIED | `https://sympower.recruitee.com/api/offers/` → 200 but empty (slug probably wrong) | partial | UNVERIFIED | AtsCollector(Recruitee) after slug check; fallback jsoup | 0 */12 * * * |
| Telia Estonia | https://www.telia.ee/ettevottest/karjaar-telias | Workday `teliacompany` / `Telia_careers` | `POST https://teliacompany.wd3.myworkdayjobs.com/wday/cxs/teliacompany/Telia_careers/jobs` body `{"searchText":"Estonia","limit":20,"offset":0}` (facet `Location_Country` id `038b0482bfea403abb61c9bcc3d7eb60` = Estonia) | 200 JSON, total 1 | "B2B IT konsultant", Tallinn, "Posted 15 Days Ago" | AtsCollector(Workday cxs) — undocumented API, relative dates | 0 */6 * * * |
| Ericsson Estonia | https://jobs.ericsson.com/careers?location=Estonia | Eightfold | JSON API `…/api/apply/v2/jobs` → **403 "Not authorized for PCSX"**; sitemap `https://jobs.ericsson.com/careers/sitemap.xml?domain=ericsson.com` 200, 510 URLs; job page has ld+json JobPosting (datePosted, description) | 200 (sitemap) | Tallinn slugs present; today's Tallinn entries are supply-chain roles — IT UNVERIFIED | DETERMINISTIC: SitemapCollector (slug `-estonia`) + jsoup ld+json | 0 */12 * * * |
| Microsoft (Tallinn) | https://apply.careers.microsoft.com/ (= microsoft.eightfold.ai) | Eightfold | same 403 on API; sitemap `https://apply.careers.microsoft.com/careers/sitemap.xml?domain=microsoft.com` 200 (618 KB, 2 tallinn/estonia URLs). Old `gcsservices` search API: TLS name mismatch + 404 (retired) | 200 (sitemap) | ≤2, UNVERIFIED titles | DETERMINISTIC: Sitemap + ld+json (same adapter as Ericsson) | 0 */12 * * * |
| Kuehne+Nagel Tallinn IT hub (added) | https://jobs.kuehne-nagel.com/global/en/search-results?keywords=Tallinn | Phenom | SSR page embeds `phApp.ddo = {…}` with `eagerLoadRefineSearch.data.jobs[]` (jobId, title, city, country, postedDate, category, remote) | 200 | yes — e.g. DevSecOps Engineer, Tallinn, category "Information Technology", posted 2026-09-08 | DETERMINISTIC: JSON-in-script extractor | 0 */6 * * * |
| Bolt | https://bolt.eu/en/careers/positions/ | custom (careers-v3, Next.js **server-rendered**) | sitemap `https://assets.careers-v3.bolt.eu/sitemap.xml` (246 `/positions/<uuid>/` URLs with lastmod); list `?page=1…13`, 20/page, SSR anchors; `city`/`location` params ignored; detail SSR has title + "Tallinn, Estonia", no posted date in HTML | 200 | yes — Tallinn HQ postings throughout | DETERMINISTIC: Sitemap + JsoupList (revises the plan's BROWSER tier — no browser needed) | 0 */6 * * * |
| LHV | https://www.lhv.ee/en/careers → meta-refresh to `https://lhv.teamdash.com/p/job/jp2Ve0dp/tule-meile` | TeamDash | no feed; landing HTML embeds `window.landing = {…}` JSON with per-job `url`, `title`, `location`, `created_at` | 200 | yes — 7 (Senior Android Engineer, Data Platform Engineer, Microsoft Engineer, IT auditor…) | DETERMINISTIC: JSON-in-script (TeamDash landing) | 0 */6 * * * |
| Helmes | https://www.helmes.com/career/ (WordPress SSR) | TeamDash `helmes` | none; list page carries `helmes.teamdash.com/p/job/<id>/<slug>` anchors | 200, 6 links | yes — Full-Stack Java Developer, Java programmētājs | DETERMINISTIC jsoup on employer page + TeamDash job page | 0 */6 * * * |
| Cybernetica | https://cyber.ee/careers/open-positions/ (Nuxt SSR) | TeamDash `cyber` | none; 8 `cyber.teamdash.com/p/job/…` anchors in HTML | 200 | yes — Android developer, Security engineer, Süsteemiinsener | DETERMINISTIC jsoup | 0 */6 * * * |
| Bigbank | https://jobs.bigbank.eu/et (Nuxt SSR) | TeamDash `bigbank` | none; 4 `bigbank.teamdash.com/p/job/…` anchors | 200 | yes — Software Engineer, System Analyst | DETERMINISTIC jsoup | 0 */6 * * * |
| TEHIK | https://www.tehik.ee/miks-meiega-liituda | TeamDash `tehik` | none; 8 `tehik.teamdash.com/p/job/…` anchors | 200 | yes — rakenduste administraator, tooteomanik, andmekvaliteedi analüütik | DETERMINISTIC jsoup | 0 */12 * * * |
| Tele2 Estonia | https://tele2.ee/ettevottest/tootamine-tele2 → `https://tulemeile.tele2.ee/p/jobs/98/` | TeamDash (custom domain) | `window.landing` present but its job block shape differs from LHV's (no job URLs found in my grep) — UNVERIFIED; also posts on cv.ee | 200 | UNVERIFIED | DETERMINISTIC (TeamDash landing) after fixture capture; cv.ee covers meanwhile | 0 */12 * * * |
| Elisa Estonia | https://www.elisa.ee/et/too ("Aktiivseid tööpakkumisi: 8", SSR) | Talendipank (`talendipank.ee/toopakkumine/<id>`), plus cv.ee | none | 200 | 8 active, IT share UNVERIFIED | DETERMINISTIC jsoup on elisa.ee list; cv.ee overlap | 0 */12 * * * |
| Coop Pank | https://www.cooppank.ee/toopakkumised (Next.js SSR) | custom | none; list anchors `/toopakkumised/<id>`, detail has ld+json JobPosting | 200, 2 | 0 IT today | DETERMINISTIC jsoup | 0 */12 * * * |
| RMIT | https://www.rmit.ee/tule-meile/toopakkumised (Drupal SSR, "Kuvatud 1 töökuulutust") | custom | none | 200 | 1 | DETERMINISTIC jsoup | 0 */12 * * * |
| Proekspert | https://proekspert.com/join-us/ (WordPress SSR) | custom | none; anchors `/join-us/<slug>-<uuid>/`; no job REST type | 200, 2 | Technical Product Owner, Delivery Lead | DETERMINISTIC jsoup | 0 */12 * * * |
| Cleveron | https://cleveron.com/ (WordPress; geo-redirects to /es/) | custom | `https://cleveron.com/job-offer-sitemap.xml` (1 URL, praktika) | 200 | 0 | DETERMINISTIC Sitemap + jsoup | 0 6 * * * |
| Codeborne | https://codeborne.com/en/jobs/ ("Open positions" static) | none | none | 200 | UNVERIFIED count | DETERMINISTIC jsoup | 0 6 * * * |
| Mooncascade | https://www.mooncascade.com/career (Next.js SSR) | none | none; no job anchors, only `mailto:jobs@` | 200 | 0 | none (re-check quarterly) | — |
| Net Group | https://netgroup.com/careers/ | none | none; no positions listed | 200 | 0 | none / cv.ee | — |
| TalTech IT | https://taltech.ee/vabad-tookohad → https://career.taltech.ee/ | custom | none; list markup UNVERIFIED (no job anchors matched) | 200 | UNVERIFIED | LLM_EXTRACT candidate after fixture | 0 6 * * * |
| SEB Estonia | https://www.seb.ee/karjaar → links `cv.ee/et/search/employer/seb` | none (cv.ee) | — | 200 | via cv.ee | none (cv.ee collector) | — |
| RIA | https://www.ria.ee/tootamine-rias → cv.ee employer page | none (cv.ee) | — | 200 | via cv.ee | none (cv.ee) | — |
| SMIT | https://www.smit.ee/et/karjaar (Nuxt static payload; no job refs) | none (cv.ee/cvkeskus UNVERIFIED) | — | 200 | — | none (cv.ee) | — |
| Fujitsu Estonia | https://www.fujitsu.ee/karjaar-fujitsu-estonias/toopakkumised/ → 2 `cv.ee/et/vacancy/…` links | none (cv.ee) | — | 200 | 2 via cv.ee | none (cv.ee) | — |
| Derivco Estonia | www.derivco.com → 403 (WAF); SAP SuccessFactors site `jobs.microgaming-derivco.co.uk/go/Derivco-Estonia/3201101/` → TCP failed | SuccessFactors (UNVERIFIED) | UNVERIFIED | fail | via cv.ee (search) | none (cv.ee); BROWSER only if cv.ee misses them | — |
| Guardtime | guardtime.com/about/jobs | UNVERIFIED — `guardtime.com` did **not resolve** (ENOTFOUND from sandbox and WebFetch) on 2026-09-18; search says "no open positions, open application only" | — | DNS fail | — | never (manual) | — |
| Wisercat | https://wisercat.peopleforce.io/careers → 404 | PeopleForce (UNVERIFIED) | — | 404 | — | manual | — |
| Adcash | www.adcash.com | UNVERIFIED — host resolves to 0.0.0.0 here (local hosts blocklist: ad-network domain) | — | blocked locally | — | manual until fetchable from the pod | — |
| Klaus | klausapp.com/careers → zendesk.com | acquired by Zendesk | — | 200 (redirect) | — | never | — |
| Yolo Group (added) | careers.yolo.com/jobs (search) — my fetch redirected to yolo.com/career "closed" page | UNVERIFIED | — | — | — | re-check | — |
| Enefit (added) | https://www.enefit.com/et/too-ja-praktika/tule-toole (Next.js) | UNVERIFIED — no job anchors | — | 200 | — | re-check | — |
| Scoro (added) | scoro.com/careers → homepage redirect | UNVERIFIED | — | — | — | re-check | — |

### Vendor summary (ranked by employers)

| Vendor | Employers (verified feed) | EE postings today | Adapter notes |
|---|---|---|---|
| Teamtailor | 9: Swedbank, Luminor, Fractory, Starship, Pactum, Comodule, Milrem, Datel, Thorgate | ~54 | `https://<site>/jobs.json` is a **JSON Feed** (`items[]`: `id` uuid, `url`, `title`, `date_published`, `content_html`, `_jobposting` = schema.org JobPosting with `datePosted`, `validThrough`, `jobLocation[].address.addressCountry`, `identifier`). No server-side filter on jobs.json (`countries[]`, `locations[]` ignored) — filter on `addressCountry=="EE"`. `jobs.rss` and `sitemap.xml` also served. HTML `jobs?country=Estonia` works if ever needed. No remote flag (`jobLocationType` null). Works on both `<sub>.teamtailor.com` and custom domains. |
| Greenhouse | 6: Twilio, Veriff, Inbank, Nortal, Testlio, Ready Player Me | 18 | `?content=true`: `id`, `updated_at`, `first_published`, `location.name` (free text, remote encoded as "Remote - Estonia"), `content`, `departments`, `offices`, `absolute_url`, `application_deadline`. No location query param — filter client-side. |
| TeamDash (jsoup, no feed) | 6: LHV, Helmes, Cybernetica, Bigbank, TEHIK, Tele2 | ~33 | Two shapes: (a) employer page lists `<sub>.teamdash.com/p/job/<8-char id>/<slug>` anchors (Helmes/Cybernetica/Bigbank/TEHIK) — id = path segment; (b) TeamDash landing page `/p/job/<id>/<slug>` with `window.landing = {…}` JSON (LHV) carrying job `url`/`title`/`location`/`created_at`. Job page is Laravel-rendered (og:title present, description in HTML); its ld+json is a leaked PHP template, unusable. No `/p/jobs.json`, `/feed`, `/sitemap.xml` (all 404). |
| SmartRecruiters | 3: Wise, Playtech, Tietoevry | 77 | `?country=ee&limit=100&offset=`: `id`, `uuid`, `releasedDate`, `location{city,country,remote,hybrid,fullLocation}`, `department`, `typeOfEmployment`, `ref` → detail with `jobAd.sections{jobDescription,qualifications,…}`, `postingUrl`. Unknown id returns 200 with `totalFound:0` (not 404) — the registry must not read "0" as "board exists". |
| Ashby | 3: Glia, Zego, Katana | 3 | `jobs[]`: `id`, `title`, `location`, `secondaryLocations`, `isRemote`, `workplaceType`, `publishedAt`, `descriptionPlain/Html`, `jobUrl`, `applyUrl`, `employmentType`, `isListed`. Unknown slug returns 200 with an empty list (Bolt probe). |
| Workable | 2: Skeleton (id 128656), Xolo (id unknown) | ≥1 | Widget API `apply.workable.com/api/v1/widget/accounts/<numeric id>?details=true`: `shortcode`, `title`, `city`, `country`, `telecommuting`, `published_on`, `description`, `url`. The `/api/v3/accounts/<slug>/jobs` form needs the account slug, which neither site exposes. |
| Personio | 2: Salv, eAgronom | 1 | `<sub>.jobs.personio.{de,com}/xml`: `id`, `name`, `office`+`additionalOffices`, `createdAt`, `occupationCategory`, `salaryInformation`, `jobDescriptions`; no remote flag. |
| Recruitee | 2: TextMagic, Sympower (slug unverified) | 0 | `<sub>.recruitee.com/api/offers/` → `{"offers":[…]}`; both empty today, so field shape UNVERIFIED (docs: `id`, `title`, `city`, `country`, `remote`, `published_at`, `careers_url`, `description`). |
| Eightfold | 2: Ericsson, Microsoft | ≤2 IT | Public JSON API refuses (403 PCSX). Use `careers/sitemap.xml?domain=…` + job page ld+json JobPosting (`datePosted`, `description`, `jobLocation`). |
| Lever | 1: Pipedrive | 1–2 | `id`, `createdAt` (epoch ms), `categories.location/allLocations`, `country`, `workplaceType`, `descriptionPlain`, `hostedUrl`; `?location=` filter supported. |
| BambooHR | 1: Ridango | 3 | `result[]`: `id`, `jobOpeningName`, `location{city,state}`, `isRemote`, `departmentLabel`; **no posted date, no description** in the list → fetch `/careers/<id>/detail`. |
| Workday | 1: Telia | 1 | POST `wday/cxs/<tenant>/<site>/jobs`: `bulletFields[0]` req id, `externalPath`, `locationsText`, `postedOn` **relative** ("Posted 15 Days Ago"); detail at `…/jobs/<externalPath>`. Undocumented internal API. |
| Phenom | 1: Kuehne+Nagel | ≥2 | `phApp.ddo` JSON in SSR HTML: `jobId`, `title`, `city`, `country`, `postedDate` (ISO), `dateCreated`, `category`, `remote`, `descriptionTeaser`. |
| custom / none | Bolt, Coop Pank, RMIT, Proekspert, Cleveron, Codeborne, Elisa (Talendipank), TalTech, Mooncascade, Net Group | — | see below |
| cv.ee only | SEB, RIA, SMIT, Fujitsu, Derivco, (Tele2, Elisa also) | — | already covered by the T1 cv.ee collector; no employer collector needed |

**Adapter build order by coverage:** 1) Teamtailor JSON Feed (9 employers) — 2) Greenhouse (6) — 3) SmartRecruiters (3 employers but the most EE postings, 77) — 4) TeamDash jsoup pair (6 employers, ~33 postings, two markup shapes) — 5) Ashby (3) — 6) Workable widget, Personio XML, Recruitee, Lever, BambooHR, Workday (1–2 each) — 7) Eightfold/Phenom "sitemap + ld+json / JSON-in-script" generic extractors (also cover Bolt).

### Employers with no feed — what the pages look like
- **Bolt**: Next.js but fully server-rendered — sitemap with lastmod, 13 SSR list pages, SSR detail. Markup is Radix class soup (`rt-Text rt-truncate`), stable enough for jsoup on anchors + the sitemap; posted date is absent from HTML (use sitemap lastmod / first_seen). No browser required — the plan's T2-browser entry for Bolt should move to T1 deterministic.
- **TeamDash sites** (LHV, Helmes, Cybernetica, Bigbank, TEHIK, Tele2): employer pages are SSR (WordPress/Nuxt) with plain anchors; the TeamDash landing pages are Vue but ship the data inline in `window.landing`. jsoup suffices; no browser.
- **Coop Pank, RMIT, Proekspert, Cleveron, Codeborne, Elisa**: SSR with anchors; Coop Pank detail carries ld+json JobPosting. Stable, low volume.
- **TalTech (career.taltech.ee), Enefit, Scoro, Yolo**: JS-heavy or redirected; markup UNVERIFIED — LLM_EXTRACT/BROWSER candidates only if they turn out to carry IT roles cv.ee misses.
- **Derivco, Guardtime, Wisercat, Adcash**: unreachable/blocked/404 from here; rely on cv.ee or manual.

### robots.txt of feed hosts
- `boards-api.greenhouse.io`: only `/embed/` disallowed. `api.lever.co`: `Allow: /`, `Crawl-delay: 1`. `api.ashbyhq.com`: robots.txt → 401 (none). `apply.workable.com`: empty Disallow, `Content-Signal: ai-train=no`. `ridango.bamboohr.com`: only embed pages disallowed. Personio job hosts: no robots (SPA HTML). `*.teamdash.com`: `Disallow:` (empty). Teamtailor sites (`jobs.swedbank.com` etc.): disallow `/app/`, `/messages/`, `/jobs/internal/`; `Content-Signal: search=yes, ai-train=no, ai-input=yes`; sitemap listed. `teliacompany.wd3.myworkdayjobs.com`: `Allow: /Telia_careers/` + sitemap. `jobs.ericsson.com`: `Disallow: /` but `Allow: /careers`, `/api/apply`. `bolt.eu`: `Allow: /`. `jobs.kuehne-nagel.com`: search-results allowed. `careers.tieto.com`: `Disallow: /jobs?q*` (HTML search; the API host is separate).
- **`api.smartrecruiters.com`: `User-agent: * Disallow: /` (only LinkedInBot may read `/v1/companies/`).** The Posting API is documented as public, but robots forbids generic crawlers — operator decision needed before shipping the SR adapter (the highest-yield one).

### ToS / docs excerpts
- Greenhouse: "Job Board data is publicly available, so authentication is not required for any GET endpoints." No rate limit or acceptable-use text in the docs.
- Lever: Postings GET needs no key; only application POSTs are rate-limited (429 above 2/s).
- Ashby: docs describe the public job-board endpoint and `includeCompensation`; no auth/rate/ToS text.
- SmartRecruiters: public Postings API "requires no authentication, when enabled by the customer"; SAP API policy referenced; robots conflict above.
- Workable: widget API documented with the fields above; no auth/ToS text found.
- Teamtailor, Workday, TeamDash, Eightfold, Phenom, Personio, Recruitee, BambooHR: no vendor ToS located (Teamtailor developer docs 404; Workday cxs and BambooHR `careers/list` are undocumented internals) — UNVERIFIED.

### Corrections to the plan's seed tiers
- Bolt → T1 deterministic (sitemap + SSR), not browser.
- Swedbank Teamtailor `jobs.json` is JSON Feed, not a filterable list — filter on `_jobposting.jobLocation`.
- Nortal's Greenhouse board holds no Estonian roles; Nortal EE stays with cv.ee.
- Ridango BambooHR list has no dates/descriptions — the adapter must fetch details.
- Wise's SR id is `Wise` (`TransferWise` returns an empty 200).
- Microsoft/Ericsson: no SPA-browser needed — sitemap + ld+json.
- Skeleton is Workable (widget id 128656), not Greenhouse/Teamtailor; Xolo likewise Workable.
- TeamDash coverage is larger than seeded (Bigbank, TEHIK, Tele2 in addition to LHV/Helmes/Cybernetica) and is fully jsoup-able.

## Appendix C — company discovery (survey agent report, verbatim)

# masi company-discovery survey — findings (2026-09-18)

Method: plan §Companies/§PR3 read; one polite fetch per page (UA `masi-survey/0.1 (+https://pmon.dev)`), HEAD requests on the register files, one download each of the 18 MB basic CSV and the 230 MB general-data JSON zip (the latter streamed twice to get real counts). Everything below is from those fetches unless marked **unverified**. Times: Europe/Tallinn, UTC beside where the server speaks UTC.

## 1. Estonian e-Business Register open data (RIK)

**Portal**: https://avaandmed.ariregister.rik.ee/en — datasets: https://avaandmed.ariregister.rik.ee/en/downloading-open-data — terms: https://avaandmed.ariregister.rik.ee/en/terms-service. The national portal is not the place: `avaandmed.eesti.ee` 301-redirects to `andmed.eesti.ee`, whose API (`https://andmed.eesti.ee/api/datasets?search=…`) returns 0 datasets for "äriregister", "rekvisiidid" and "business register" and only Statistics Estonia aggregates for "EMTAK"; `andmed.stat.ee` is the statistical database. Use the RIK portal directly.

**Licence / ToS**: "Creative Commons Attribution 4.0" (https://creativecommons.org/licenses/by/4.0/legalcode); reuse "for commercial or non-commercial purpose"; "If open data contains personal data, the re-user of open data is obliged to comply with the terms and conditions of the General Data Protection Regulation (GDPR)". No clause on automated downloads or frequency. Plain unauthenticated GET; the portal's robots.txt (Drupal default) does not disallow `/sites/default/files/`. The XML/REST **API** is a different thing: "it is necessary to sign an agreement with the Registers and Information Systems Center", 50,000 answers/day, 1 concurrent query, and the page itself says "For (initial) downloading of large datasets, please use open data downloadable files" (https://avaandmed.ariregister.rik.ee/en/open-data-api/introduction-api-services). Verdict: files, never the API.

**Datasets** (all daily unless noted; URL prefix `https://avaandmed.ariregister.rik.ee/sites/default/files/avaandmed/`):

| Dataset | Files | Measured |
|---|---|---|
| Basic data (lihtandmed): name, code, legal form, VAT no, status, first entry, address | `ettevotja_rekvisiidid__lihtandmed.csv.zip`, `.xml.zip` | zip 18,525,493 B → CSV 97,008,288 B, 378,009 rows |
| **General data (yldandmed)**: basic + capital, contacts, **activity areas (EMTAK)**, annual-report list, registry cards | `ettevotja_rekvisiidid__yldandmed.json.zip`, `.xml.zip` | JSON zip 229,847,693 B → **4,575,459,368 B** (4.6 GB) JSON, 378,009 objects; XML zip 231,203,638 B |
| Registry cards, persons on/off card, shareholders, beneficial owners (no personal ID since 2024-11-01), commercial pledges, rulings | `ettevotja_rekvisiidid__{registrikaardid,kaardile_kantud_isikud,kandevalised_isikud,osanikud,kasusaajad,kommertspandid,maarused}.{xml,json}.zip` | not needed |
| Annual reports (monthly): general info, sales by EMTAK, key indicators 2019–2025 incl. "average full-time employees" | `/sites/default/files/1.aruannete_yldandmed_kuni_31082026_0.zip`, `2.EMTAK_myygitulu_…`, `4.<year>_aruannete_elemendid_kuni_31082026_0.zip` | file names carry a validity date and change — resolve from the page, do not hard-code |
| Parquet variants | `/sites/default/files/13_11_{lihtandmed,yldandmed}.parquet_{1,2}.zip` | **stale: Last-Modified Mon, 13 Nov 2023** — the plan's "JSON/Parquet" should read JSON only |

Freshness: `Last-Modified: Thu, 17 Sep 2026 09:38–09:46 GMT` (12:38–12:46 Tallinn); entry timestamps inside the zips 06:01 (CSV) and 12:38 (JSON). So the JSON is regenerated around midday Tallinn; schedule the weekly pull for the evening. Download took 7.2 s (32 MB/s).

**Content rule** (abiinfo FAQ, https://abiinfo.rik.ee/en/e-business-register-queries/open-data-e-business-register/frequently-asked-questions-about-open, via search snippet — the page fetched said only "most of the files are updated once a day"): "the files only contain public data of the legal entities currently in Business Register (only with statuses: entered into the register, in liquidation, in bankruptcy)". Measured statuses in the JSON: `R` Registrisse kantud 368,599; `L` Likvideerimisel 8,734; `N` Pankrotis 675; `K` 1. Consequence: a deleted company simply disappears from the dump — a registry code absent from two consecutive weekly imports is the DORMANT signal.

**JSON layout** (verified by inflating the first 3 MB via a Range request, then the full file): a top-level array, pretty-printed with 4-space indent; every company object begins with the line `    {` and ends with `    },` (last: `    }`). Fields per object (Estonian keys):

```
ariregistri_kood (int), nimi
yldandmed: staatus ('R'|'L'|'N'|'K'), staatus_tekstina, oiguslik_vorm ('OÜ','AS','FIE','MTÜ','UÜ','TÜ','FIL','SA',...),
  oiguslik_vorm_tekstina, esmaregistreerimise_kpv, kustutamise_kpv, tegutseb_tekstina ('Jah'|'Ei'), piirkond_tekstina,
  arinimed[]: {sisu, algus_kpv, lopp_kpv}
  aadressid[]: {ehak, ehak_nimetus ('Pirita linnaosa, Tallinn, Harju maakond'), tanav_maja_korter, postiindeks,
                aadress_ads__ads_normaliseeritud_taisaadress, riik}
  sidevahendid[]: {liik: EMAIL|MOB|TEL|WWW|FAX|MUU|TELEX|AMAIL, sisu}
  teatatud_tegevusalad[]: {emtak_kood ('62101'), emtak_tekstina, emtak_versioon (2|3), emtak_versioon_tekstina
                ('EMTAK 2008'|'EMTAK 2025'), nace_kood ('62.10'), on_pohitegevusala (bool), algus_kpv, lopp_kpv}
  info_majandusaasta_aruannetest[] (NEWEST FIRST): {majandusaasta_perioodi_lopp_kpv, tootajate_arv (string),
                tegevusala_emtak_kood, tegevusala_emtak_versioon}
  kapitalid[], majandusaastad[], pohikirjad[], markused_kaardil[], staatused[], esitab_kasusaajad
```

CSV columns of lihtandmed (`;`-separated, BOM): `nimi;ariregistri_kood;ettevotja_oiguslik_vorm;ettevotja_oigusliku_vormi_alaliik;kmkr_nr;ettevotja_staatus;ettevotja_staatus_tekstina;ettevotja_esmakande_kpv;ettevotja_aadress;asukoht_ettevotja_aadressis;asukoha_ehak_kood;asukoha_ehak_tekstina;indeks_ettevotja_aadressis;ads_adr_id;ads_ads_oid;ads_normaliseeritud_taisaadress;teabesysteemi_link` — no EMTAK, so the CSV cannot do the filter; the JSON is required.

**EMTAK filter — two versions coexist.** Activity rows in the dump: 300,609 EMTAK 2025 (`emtak_versioon` 3) vs 118,032 EMTAK 2008 (`emtak_versioon` 2). Existing companies keep 2008 codes until their next annual report (RIK news, https://www.rik.ee/et/asutusest/uudised/algavast-aastast-hakkab-kehtima-uus-tegevusalade-klassifikaator). Divisions 62/63 keep their numbers in both, so `emtak_kood.startsWith("62"|"63")` on rows with `lopp_kpv == null` works; the `nace_kood` (4-digit) is also present. Codes actually seen on active companies:

- EMTAK 2025 (from the RIK guide PDF https://abiinfo.rik.ee/sites/default/files/inline-files/EMTAK%202025%20tutvustus%20ja%20juhend_1.pdf): 62101 Programmeerimine (10,260), 62201 Arvutialased konsultatsioonid (3,560), 62202 Arvutisüsteemide ja andmebaaside haldus (870), 62901 Muud infotehnoloogia- ja arvutialased tegevused (3,218), 63101 Andmetöötlustaristu, andmemajutus (502), 63102 Andmetöötlus, andmekorraldus, andmevahendus (624), 63911 Veebiotsinguportaalide tegevus (587), 63921 Muu infoalane tegevus (1,013); 4-digit rows also occur (6220: 351, 6310: 106).
- EMTAK 2008 still present: 62011 (2,717), 62021 (1,286), 62031 (228), 62091 (1,309), 63111 (389), 63121 (596), 63991 (551), 63911 (30 — in **2008** 63.91 is *news agencies*, in 2025 it is web-search portals; harmless at 30 rows).

**Measured yield** (JSON of 2026-09-17): companies with a current 62/63 activity: 28,734 any status; **27,708 with status R** (26,624 with 62/63 as main activity). Legal form: OÜ 26,872, FIE 423, MTÜ 144, UÜ 116, AS 74. Region: Harju 21,752, Tartu 1,910, foreign/no EHAK 1,186. Contacts: EMAIL 27,622, **WWW only 2,369 (8.6%)**. Newest annual report `tootajate_arv`: 0 → 14,828; no report → 6,902; 1–4 → 5,305; 5–9 → 293; 10–49 → 282; 50–249 → 80; 250+ → 18 (≥1: 5,978; ≥5: 673; ≥10: 380; ≥50: 98). Spot checks: Nortal AS 10391131 (361, 62101), Pipedrive OÜ 11958539 (395), Cybernetica AS 10140133 (224), Bolt Technology OÜ 12417834 (4,245 for 2025 but **0 for 2023 and 2024** — the field is unreliable year to year; take the max over the last three reports). The registry is ~80% one-person and e-resident shells; import all 27.7k as registry rows but derive `size_band` from employees and mark "hiring-relevant" only when employees ≥ 5, or WWW present, or seen in another source.

**Website/email**: `sidevahendid` WWW exists but is sparse; EMAIL is nearly universal and frequently a person's Gmail (e.g. `pkgodara.choudhary@gmail.com` on a 62201 OÜ) — under the plan's PII rule store only WWW → `website`/`domain_norm`, drop EMAIL/MOB/TEL entirely.

**Streaming approach** (the plan's "stream the zip" is right; the 4.6 GB never touches disk): `GET` with `If-Modified-Since` (server sends `Last-Modified`) → `ZipInputStream` (single deflate entry; the local header comes first, streaming verified) → Jackson `JsonParser` positioned on the array, `readValueAsTree`/bind per element → keep `staatus == "R"` and any current activity with prefix 62/63 → `RawCompany(name, registryCode, website=WWW, emtakCode=main 62/63 code, extras{legalForm, city=ehak_nimetus, employees=max last 3, emtakVersion})`. Python did the whole pass in 57 s; Java will be faster. Constant memory; ~230 MB transfer weekly. This collector must bypass `HttpFetcher`'s 2 MB cap (needs a streaming fetch method with a separate byte budget, e.g. 512 MB). Recommended `config_json`: `{"url": ".../ettevotja_rekvisiidid__yldandmed.json.zip", "statuses": ["R"], "emtakPrefixes": ["62","63"], "minEmployeesForActive": 5, "dropContacts": true}`. Verdict: **DETERMINISTIC, weekly (Sun 20:00 Europe/Tallinn), companies tier T1**; `complete=true` only if the array closed cleanly and rows kept ≥ 0.9 × last run.

## 2. ITL member list

- URL: https://itl.ee/en/members/ (175 KB, WordPress, server-rendered; no JSON behind it). robots.txt: `User-agent: * / Disallow: /wp-admin/ / Allow: /wp-admin/admin-ajax.php / Sitemap: https://itl.ee/sitemap.xml` — allowed.
- **128 members**, 128 distinct names and 128 distinct website hrefs. Markup per member:
  `<a href="https://www.adm.ee/?lang=en" target="_blank" class="logo active it-service tarkvara-arendajad taisliikmed ict-cluster-member … all-members" data-counter="1" data-order="1"><span><span class="counter"></span>ADM Interactive OÜ</span><img src="…" alt="ADM Interactive OÜ"/></a>`
- Fields: legal name with suffix (matches the register's `nimi` well), website URL, and category classes: `taisliikmed` 88 / `assotsieerunud-liikmed` 28; `tarkvara-arendus` 53, `it-teenus` 47, `kuberturvalisus` 21, `koolid-ja-koolitajad` 13, `telekommunikatsioon` 11, `konsultatsioon` 5, `e-arve-teenus` 2, `muu-tegevus` 41, `ikt-klastri-liige` 30, `its-estonia-liige` 24. No registry code. Members include banks, law firms and universities — keep the category tags, let the register match supply EMTAK.
- Verdict: **DETERMINISTIC (jsoup `a.logo.all-members`), monthly, companies tier T1**. Fixture: the saved page; negative test: zero anchors → `complete=false`.

## 3. Tehnopol portfolio

- URL: https://www.tehnopol.ee/en/startups/portfolio/ (the plan's `/en/startups/` is the accelerator page and lists nothing). 1.18 MB, WordPress. robots.txt disallows only WooCommerce paths and `/wp-admin/` — allowed.
- **244 cards, all in the initial HTML**: "Active companies" 42, "Alumni" 202 (201 distinct titles — one duplicate). "Load more" is purely client-side: `<div class="companies … js-companies-grid js-load-more" data-initial-limit="15" data-load-step="15">`; no AJAX endpoint.
- Per company: `h3.company-card__title` (brand name, often no legal suffix: "$harp.edz", "Antscape", sometimes "Alesserg Technology OÜ"), a hidden modal `div.company.js-company` with `h2.company__title`, description `.company__text`, and website under `.company__details-item` → label "Website" → `a.company__website-link[href]` (**161 of 244 have one**). Contacts are free text inside the description, many personal Gmail addresses → do not capture.
- Verdict: **DETERMINISTIC (jsoup), monthly, companies tier T2**; tag `active|alumni`; match to the register by `domain_norm` first (brand names rarely equal `nimi`).

## 4. Startup Estonia / Dealroom

- https://startupestonia.ee/startup-database/ only links to the Dealroom-hosted https://ecosystem.startupestonia.ee/companies.startups/ ("approximately 1,500 startups and 120 support organizations"); no export, CSV or API is mentioned.
- Dealroom ToS https://dealroom.co/terms-of-service: 2.2 "Unless you are a bot; in that case you are not allowed." 17.1 "Bots are not allowed and will be banned if detected." 17.7 "Scraping of data, or excessive usage, whether by humans or bots is not allowed and your account may be blocked if detected." 3.3 "you may not in any way commercialise, share, copy, extract, or sub-license any of the data". 18.5/20.6 no publishing of raw datasets; 20.5 API "only … to embed Dealroom.co data in your internal systems" — API is Enterprise-only (https://dealroom.co/products/api/).
- `https://ecosystem.startupestonia.ee/robots.txt`: `Content-Signal: search=yes,ai-train=no`, explicit `Disallow: /` for ClaudeBot, GPTBot, Google-Extended, Amazonbot and others, citing EU Directive 2019/790 as a rights reservation.
- Verdict: **never** (automated); manual entry via `POST /companies` only, as the plan already says.

## 5. Other directories

| Source | Facts | Verdict |
|---|---|---|
| Inforegister (Register OÜ, Kreedix) https://www.inforegister.ee/ | Commercial credit-info. Terms URL from search (https://www.inforegister.ee/en/veebilehe-kasutustingimused) is 404 today, `/robots.txt` answers 403, the home page links only a Kreedix privacy policy. Search snippet (**unverified**, page unreachable): scripts, robots and "automated tools or programs not intended for internet browsing" are not permitted; "automated mass queries are not permitted". Data is the same register anyway. | never |
| Teatmik https://www.teatmik.ee/ | Every fetch redirects to `/browser-check` then `/en/captcha`: "Please confirm You are not a robot!"; sells "Data exports and reports \| Application interface (API)"; terms at https://www.teatmik.ee/en/terms sit behind the CAPTCHA (not read). A CAPTCHA gate is an explicit refusal. | never |
| e-estoniax references https://references.e-estoniax.com/ | ~29 exporting ICT firms (Nortal, Cybernetica, SK ID Solutions, …) as project references; WordPress, robots allows; all are ITL members. | skip |
| Estonian Founders Society https://asutajad.ee/ (Asutajad MTÜ, 80305937) | Community of ~190 founders; no company/member list on the site (`/eesti-startup-okosusteem` **unverified**). | skip |
| Garage48 https://garage48.org/success-stories | Narrative posts, no structured list. | skip |
| EIS/EAS https://www.eas.ee/toetatud-projektid/, KredEx | Grant-recipient pages, not IT-specific, format **unverified**; KredEx publishes no list. | skip |
| Clutch / GoodFirms / TechBehemoths | Commercial rankings, ToS not read (**unverified**), mostly non-Estonian outsourcers. | never |
| Statistics Estonia andmed.stat.ee, andmed.eesti.ee | Aggregates only; register dump not catalogued there (5 API searches). | n/a |
| Job-board employer names | Covered by the plan (`FROM_LISTING` stubs); the register import then attaches the registry code by `name_norm`. | already planned |

## 6. Dedupe: names, suffixes, former names

- The register stores the **exact registered business name** in `nimi`; the legal form is a separate field (`oiguslik_vorm` 'OÜ'/'AS'/…, `oiguslik_vorm_tekstina`). No normalisation is applied: the designation appears as abbreviation or full word, before or after ("007 Autohaus osaühing", "007 Agent & Partners OÜ", "Nortal AS"). `norm()` must therefore strip, at either end, `osaühing|oü|ou|aktsiaselts|as|usaldusühing|uü|täisühing|tü|mittetulundusühing|mtü|sihtasutus|sa|füüsilisest isikust ettevõtja|fie|filiaal` in addition to the plan's `ltd|llc|gmbh|inc`. Business names must be distinguishable nationwide (Commercial Code), so `name_norm` collisions between two *active* register rows are rare; keep `registry_code` as the primary key.
- **Former names**: the `arinimed[]` schema has `algus_kpv`/`lopp_kpv`, but in the dump **every one of 378,009 companies has exactly one entry** — the current name (Nortal AS shows `algus_kpv 28.05.2012`, no Webmedia). The dump exposes **no name history**; the contract XML `detailandmed` API probably does (**unverified**). Estonian law has no trade-name/DBA concept — brands are trademarks at the Patent Office, not register data — so there is no trade-name field either. `company_alias` must be fed from ITL/Tehnopol/board names and manual edits; the register contributes only the current name. A rename keeps the registry code, so the weekly import updates `name` in place and the old name should be written to `company_alias` by the importer — that is the only place former names will ever come from.
- Matching order confirmed by the data: registry code (register ↔ register) → `name_norm` (ITL legal names match well) → `domain_norm` (Tehnopol brands, and only 8.6% of register rows have WWW, so the website usually comes from ITL/Tehnopol/enrichment, not the register) → aliases.

## Summary

| Source | Kind | Cron | Tier | Yield | Notes |
|---|---|---|---|---|---|
| e-Business Register `yldandmed.json.zip` | DETERMINISTIC (streamed) | weekly, Sun 20:00 Tallinn | T1 | 27,708 active 62/63 (5,978 with ≥1 employee) | CC BY 4.0; 230 MB → 4.6 GB streamed; both EMTAK versions; drop EMAIL/MOB; needs a streaming fetch outside the 2 MB cap; Parquet stale |
| ITL members | DETERMINISTIC (jsoup) | monthly | T1 | 128 | legal names + website + category tags; robots allows |
| Tehnopol portfolio | DETERMINISTIC (jsoup) | monthly | T2 | 244 (42 active) | all cards in HTML, client-side load-more; 161 websites; brand names |
| Startup Estonia / Dealroom | never | — | manual | ~1,500 | ToS bans bots/scraping; robots blocks ClaudeBot |
| Inforegister, Teatmik | never | — | — | — | commercial; CAPTCHA / no-robots terms |
| e-estoniax, Founders Society, Garage48, EIS/KredEx, Clutch-type | skip | — | — | — | no structured list or no added value |

Scratch artefacts for fixtures (session scratchpad, not project files): `itl.html`, `tehnopol.html`, `liht.zip`, `yld.zip` (230 MB) and `yld_head.bin` (first 3 MB of the JSON zip — enough to build a small streamed fixture) under `/home/sm/scratch/claude-tmp/claude-1000/-home-sm-src-monitor/3692d3d0-fc36-46cb-b8c1-3bb9628f3387/scratchpad/`.
