# Lithuania (LT) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (one capped GET per URL), the Claude Code
WebFetch tool with its own default client, and web search. No account, key or login was used.

## Takeaway

The best free source is the open dataset "Užimtumo Tarnybos skelbiamos laisvos darbo vietos" on the national
open data portal: every vacancy the Employment Service has registered since the 1990s (3 254 957 records
today), one record per vacancy with occupation, description, salary, validity dates, workplace address, the
employer and its requirements. It is served by the portal's API (JSON, JSON lines, CSV, RDF) with no key, under
CC BY 4.0, and declared daily; the newest records seen were loaded on 2026-11-25. Its "current today" flag
cannot be trusted (it marked only 114 records), so live vacancies must be picked by status and validity dates.
The Employment Service's own website and the new state job portal both refused this client with a Cloudflare
challenge (403), as did the statistics portal. The largest commercial board, CVbankas, forbids bots, scraping
and text and data mining in terms revised on 2026-09-03.

## Sources

### Užimtumo tarnyba - open dataset of vacancies (data.gov.lt)
- Publisher: listed publisher Valstybės duomenų agentūra (State Data Agency), which opened the data; source
  Užimtumo tarnyba prie Socialinės apsaugos ir darbo ministerijos (Employment Service).
- Documentation: dataset 2894 on https://data.gov.lt (record on data.europa.eu:
  https://data.europa.eu/data/datasets/https-data-gov-lt-datasets-2894-~~1); model page
  https://get.data.gov.lt/datasets/gov/uzt/ldv
- Data or endpoint: `https://get.data.gov.lt/datasets/gov/uzt/ldv/Vieta` (JSON; query functions such as
  `?limit(2)`, `?count()`, `?select(...)`, `?sort(-ikelimo_data)`); bulk forms
  `https://get.data.gov.lt/datasets/gov/uzt/ldv/Vieta/:format/csv`,
  `https://get.data.gov.lt/datasets/gov/uzt/ldv/:all/:format/jsonl`, `.../:all/:format/json`,
  `.../:all/:format/rdf`.
- Holds: per vacancy - darbo_vietos_id, statusas, ikelimo_data (load date), salary fields
  (prelim_darbo_uzmokestis, vid_darbo_uzmokestis, maks_darbo_uzmokestis, valiuta, uzmokescio_komentaras_lt),
  occupation (profesijos_grupes_kodas and name, profesijos_kodas, profesijos_pareigybes_pav), kontrakto_tipas,
  darbo_aprasymas_lt (description), galioja_nuo / galioja_iki (valid from / to), ar_aktuali_siandien (current
  today), ar_uzpildyta (filled), pageidaujama_darbo_pradzia, darbo_vietu_skaicius (number of posts),
  darbo_vietos_adresas and municipality, registration channel, benefits flags (travel, housing, meals), risks,
  employer (jar_kodas registry code, darbdavys name, legal form and status, registration date, office address,
  contact person, phone numbers, e-mail), requirements (experience, competences, abilities, education, study
  programme) and target-group flags (pupils, under 18, students, soldiers, Ukrainians, people with disability).
  The description says ISCO-08 fields were added on 2026-04-24 and salary, advert status and employer contact
  fields on 2026-02-10.
- Access: API and bulk download.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): the record carries the licence
  https://creativecommons.org/licenses/by/4.0/deed.lt (CC BY 4.0).
- Volume: `{"count()":3254957}` records in all on 2026-11-28; "nuo 1990m. iki šių dienų" (from 1990 to today)
  per the description; the oldest records seen are from 1995-1996.
- Update cycle: declared daily. The three newest records carried ikelimo_data 2026-11-25.
- Seen on 2026-11-28: GET ...Vieta?limit(2) -> 200, application/json, 3 601 bytes, 2 records (archived posts
  from 1995-1996, salary currency LTL); GET ...?ar_aktuali_siandien="1"&count() -> 200, `{"count()":114}`; GET
  ...?count() -> 200, `{"count()":3254957}`; GET ...?select(...)&sort(-ikelimo_data)&limit(3) -> 200, 932
  bytes (three posts loaded 2026-11-25, status "sukurta", valid to 2026-12-03 and 2026-12-07, average salary
  576.5 to 1 160 EUR, employer names).
- Caveats: the flag ar_aktuali_siandien was "0" on posts created three days earlier and valid into December, and
  counted only 114 records - it does not identify the live stock. The whole dataset is very large; do not pull
  `:all` without need. The records carry employers' contact persons, telephone numbers and e-mail addresses,
  which are personal data: the open licence does not lift data-protection law. The record's metadata date
  (2026-05-06) is older than the data.

### Užimtumo tarnyba - website and vacancy search
- Publisher: Užimtumo tarnyba.
- Documentation: not readable.
- Data or endpoint: https://uzt.lt
- Holds: the service's vacancy search for jobseekers (not examined).
- Access: web; refused to this client.
- Registration or key: not established.
- Cost: free.
- Licence or terms (exact wording, with URL): not readable.
- Volume: a search summary cites the service's figure of 172.4 thousand vacancies announced by employers in
  2024 (third-hand).
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://uzt.lt/robots.txt -> 403, text/html, 5 317 bytes, a Cloudflare "Just a
  moment..." challenge page. No further request to this host.
- Caveats: blocked for a plain client; the open dataset above is the way to the same data.

### Older Employment Service file on data.gov.lt
- Publisher: Užimtumo tarnyba.
- Documentation: dataset 241 on https://data.gov.lt ("Darbdavio Lietuvos Respublikoje (numatoma darbo vieta)
  duomenys").
- Data or endpoint: https://data.gov.lt/media/filer_public/42/37/42377bdb-f10d-48e4-8591-fb4011387a62/45.csv
- Holds: data on the employer in Lithuania (the intended workplace); content not examined.
- Access: bulk CSV.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): https://creativecommons.org/licenses/by/4.0/deed.lt
- Volume: not read.
- Update cycle: declared monthly; issued 2020-05-18.
- Seen on 2026-11-28: the catalogue record only; the file was not requested.
- Caveats: what the file actually holds was not checked; it may concern work permits rather than vacancies.

### Dirbu valstybei (public-sector job portal)
- Publisher: Viešojo valdymo agentūra, VVA (Public Management Agency), per search summaries of VVA documents;
  its 2025 work plan set the new public-sector job advert portal for the third quarter of 2025. Older notices
  point to the former portal portalas.vtd.lt.
- Documentation: not readable.
- Data or endpoint: https://dirbuvalstybei.vva.lt/
- Holds: civil-service competitions and public-sector job adverts (not examined).
- Access: web; refused to this client.
- Registration or key: not established.
- Cost: free.
- Licence or terms (exact wording, with URL): not readable.
- Volume: not read.
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://dirbuvalstybei.vva.lt/ -> 403, text/html, 5 358 bytes, a Cloudflare "Just a
  moment..." challenge page. No further request.
- Caveats: civil-service adverts also appear on lrvalstybe.lt under "darbas valstybės tarnyboje" (seen in
  search results; not requested). Whether either offers a feed is not established.

### CVbankas.lt
- Publisher: UAB "Diginet LTU".
- Documentation: none for reading vacancies. Terms: https://www.cvbankas.lt/naudojimosi-taisykles.html
  ("Naudojimosi cvbankas.lt portalu taisyklės (REDAKCIJA 2026-09-03)").
- Data or endpoint: https://www.cvbankas.lt ; sitemap https://www.cvbankas.lt/sitemap.xml (not requested).
- Holds: job adverts (not examined).
- Access: web only; automated reading forbidden by the terms.
- Registration or key: not applicable.
- Cost: free to browse.
- Licence or terms (exact wording, with URL - the terms page above): the user undertakes "neatgaminti,
  nekopijuoti ir nenaudoti Svetainių turinio tekstų ir duomenų gavybos, dirbtinio intelekto sistemų kūrimo,
  apmokymo, tobulinimo, testavimo, analizės bei panašiais tikslais" and "nenaudoti automatizuotų priemonių,
  įskaitant interneto robotais (angl. bots), duomenų nuskaitymo (angl. scraping), indeksavimo ar bet kokio
  kito tipo kompiuterinėmis programomis, skirtomis kopijuoti, apdoroti, analizuoti, saugoti ar perkelti
  Svetainių turinį"; and again, "Naudojantis Svetainėmis, draudžiama: [...] naudoti automatizuotas priemones
  („botus", „scraping" ir kt.); naudoti Svetainių turinį dirbtinio intelekto sistemoms apmokyti". Section 6:
  all intellectual property rights in the sites, their content and databases belong to the operator. robots.txt
  (https://www.cvbankas.lt/robots.txt): for all agents only account and apply paths are disallowed; under
  "#Block AI bots" it sets "Disallow: /" for anthropic-ai, Claude-Web, Applebot, Bytespider, CCBot, cohere-ai,
  Diffbot, FacebookBot, GoogleOther, PerplexityBot, Amazonbot, Google-Extended, PetalBot, ChatGPT-User, GPTBot,
  OAI-SearchBot and others.
- Volume: not read. The site calls itself the most visited job portal in Lithuania.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 2 744 bytes; GET /naudojimosi-taisykles.html -> 200,
  text/html, 430 925 bytes.
- Caveats: the lead that CVbankas could be read was checked against its current terms: it may not. No RSS feed
  was found or looked for on the site.

### CV-Online (cvonline.lt), cv.lt and CVMarket.lt
- Publisher: cvonline.lt - Alma Career (not confirmed on a page read; its robots file matches cv.lv's);
  cvmarket.lt - CV Keskus OÜ; cv.lt - not confirmed (its robots file follows the CVMarket pattern).
- Documentation: none found for reading vacancies.
- Data or endpoint: https://www.cvonline.lt ; https://www.cv.lt ; https://www.cvmarket.lt
- Holds: job adverts (not examined).
- Access: web only.
- Registration or key: none to browse.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): cvmarket.lt falls under the CV Keskus terms
  (https://www.cvkeskus.ee/kasutustingimused, clause 1.1 names www.cvmarket.lt), whose clause 2.10 forbids
  automated queries on pain of 10 000 euros per breach (quoted in the Estonia and Latvia files). robots.txt:
  https://www.cvonline.lt/robots.txt, whole file "Sitemap: https://www.cvonline.lt/sitemap.xml";
  https://www.cv.lt/robots.txt "User-agent: * Disallow: /cv/*/pdf Disallow: /login* Sitemap:
  https://www.cv.lt/sitemap_cvl.xml"; https://www.cvmarket.lt/robots.txt disallows account, login and CV paths
  and lists listing sitemaps. Terms pages of cvonline.lt and cv.lt were not read.
- Volume: not read.
- Update cycle: continuous.
- Seen on 2026-11-28: three robots.txt requests, each 200 (45, 95 and 723 bytes). No other request.
- Caveats: one request per host only.

### Official statistics - job vacancies
- Publisher: Valstybės duomenų agentūra (State Data Agency, Statistics Lithuania).
- Documentation: Official Statistics Portal https://osp.stat.gov.lt ; API description
  https://osp.stat.gov.lt/rdb-rest (refused, see below).
- Data or endpoint: the Database of Indicators on osp.stat.gov.lt.
- Holds: quarterly numbers of job vacancies and the vacancy rate from the employer survey (per the portal's
  "Labour Market in Lithuania" pages, seen in search results).
- Access: web tables and an API, per the page titles; not confirmed.
- Registration or key: not established.
- Cost: free.
- Licence or terms (exact wording, with URL): not read.
- Volume: not read.
- Update cycle: quarterly.
- Seen on 2026-11-28: WebFetch of https://osp.stat.gov.lt/rdb-rest -> 403 Forbidden. No further request.
- Caveats: a second data.europa.eu search (country Lithuania, vacancy number and rate) found no statistical
  vacancy table on the open data portal, only the Employment Service dataset above.

## Not free or not allowed

- CVbankas: bots, scraping, indexing programs, text and data mining and AI training all forbidden by its terms
  of 2026-09-03; AI agents disallowed in robots.txt.
- CVMarket.lt: automated queries forbidden, 10 000 € per breach (CV Keskus terms, clause 2.10).
- uzt.lt, dirbuvalstybei.vva.lt and osp.stat.gov.lt: not forbidden as such, but closed to a plain client by a
  bot challenge or a 403.
- No paid vacancy data product was found described on any page read.

## Gaps

- Which `statusas` values mark a live vacancy in the open dataset, and the size of the live stock: not
  established (the flag meant for it counted 114).
- The licence text on data.gov.lt itself: taken from the data.europa.eu copy of the record; data.gov.lt was not
  requested.
- Užimtumo tarnyba's website, its terms and robots.txt: blocked (403 challenge).
- The public-sector portal Dirbu valstybei: blocked (403 challenge); feeds and terms unknown.
- Statistics Lithuania's vacancy tables, API and licence: blocked (403).
- Whether Užimtumo tarnyba sends its vacancies to EURES: not established.
- Terms of cvonline.lt and cv.lt; who operates cv.lt: not read.
- Content of the older file (dataset 241): not examined.
- Other boards (darbo.lt, skelbiu.lt jobs, LinkedIn): not checked.
