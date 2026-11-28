# Estonia (EE) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (one capped GET or HEAD per URL), the
Claude Code WebFetch tool with its own default client, and web search. No account, key or login was used.

"In use" below means: the production registry's source list (`/home/sm/src/masi/docs/sources.md`, read on
2026-11-28) shows the source as already read by that system. For every host named in that file at most one
request was made, to a terms page, and none to a data endpoint.

## Takeaway

Estonia has no open-data dump and no documented public API of job adverts. The only openly licensed job data are
statistics: Töötukassa's monthly vacancy tables on the national open data portal (XLSX, CC BY-NC 3.0, so not for
commercial reuse) and Statistics Estonia's quarterly job-vacancy tables (PxWeb API, no key, CC BY-SA 4.0). The
adverts themselves are on Töötukassa's portal (web application only; its terms could not be read), and on the two
commercial boards, both of whose terms restrict reuse: CV Keskus forbids automated queries outright (10 000 € a
query), and cv.ee's terms for visitors forbid extracts and copies of its database. The one new advert source
found is the Ministry of Finance's "Avalikud konkursid" page: every public-sector competition (445 on the day) in
one HTML page, each linking to its Töötukassa posting; no licence is stated for it.

## Sources

### Eesti Töötukassa (Estonian Unemployment Insurance Fund) - vacancy portal
- Publisher: Eesti Töötukassa, the public employment service and EURES member for Estonia.
- Documentation: none found for reading vacancies. The only public guide found is for employers entering
  vacancies: https://www.fin.ee/sites/default/files/documents/2023-11/Juhend%20t%C3%B6%C3%B6pakkumiste%20sisestamiseks%20ametiasutustele.pdf
- Data or endpoint: https://www.tootukassa.ee/et/toopakkumised (web application). Per the production file, the
  site's own GraphQL operations (`jobOfferSearch`, `publicJobOfferQuery`) are what that system reads; they are
  the site's internal interface, not a documented public API. Not requested here.
- Holds (per the production file): title, employer, first address, salary in EUR with no period stated,
  part-time flag, contract duration code (fixed-term or permanent), description; occupation is assigned when the
  employer enters the vacancy (per the employers' guide).
- Access: web only. No open-data dump, RSS or documented API was found (web search, the open data portal and
  data.europa.eu were all searched).
- Registration or key: none for reading the public pages.
- Cost: free.
- Licence or terms (exact wording, with URL): NOT READ. The site links "Kasutustingimused" (terms of use) from
  its pages (seen in search results), but the site is a client-rendered application and the one permitted
  request returned only the empty application shell. The production file records "Crawl-delay 10 honoured"
  for robots.txt.
- Volume: not stated on anything read. Töötukassa's own monthly statistics (below) give the counts.
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.tootukassa.ee/et/kasutustingimused -> 200, text/html, 140 799 bytes, an
  application shell with the title "Töötukassa" and no page text (content is loaded by script). No further
  request made to this host.
- Caveats: IN USE (key `tootukassa`, enabled; at least 10 s between calls). Public-sector employers must post
  here (see the next block), so the portal also holds civil-service vacancies.

### Avalikud konkursid (public-sector competitions), Ministry of Finance
- Publisher: Rahandusministeerium (Ministry of Finance); the page is the successor of avalikteenistus.ee (its
  footer says: "Kui avalikteenistus.ee veebilehe kasutamisega esineb probleeme, palume pöörduda ...").
- Documentation: https://www.fin.ee/riigihaldus-ja-avalik-teenistus-kinnisvara/avalik-teenistus/varbamine-ja-valik
  (not fetched; found by search) and the employers' guide above, which says public bodies enter their vacancies
  in e-töötukassa, where the portal recognises a public-sector body by its registry code and asks whether the
  post is an official's post under the Civil Service Act.
- Data or endpoint: https://www.fin.ee/avalikud-konkursid (the long URL
  https://www.fin.ee/riigihaldus-ja-avalik-teenistus-kinnisvara/avalik-teenistus/avalikud-konkursid answers 301 to it).
- Holds: title, institution, region or address, deadline (ISO date-time in the markup), a field id, and the link
  to the full advert at `https://www.tootukassa.ee/toopakkumised/<slug>-<id>`. No description, salary or
  occupation code on this page.
- Access: one HTML page holding the whole list as embedded JSON (`<script type="application/json"
  id="datatable-...">`), filterable in the browser by field, region and institution. No API or feed for the
  list was found; the site's `/rss-feeds/rss.xml` link is the ministry's general feed and was not requested.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): none stated on the page. Not established.
- Volume: "Kuvatud 445 töökuulutust" (445 adverts shown) on 2026-11-28.
- Update cycle: fed automatically from Töötukassa's portal (per the search summary of the ministry's
  recruitment page; the page itself was "Viimati uuendatud 02.09.2025" as a page, while the adverts carried
  deadlines up to late December 2026).
- Seen on 2026-11-28: GET https://www.fin.ee/avalikud-konkursid -> 200, text/html, 1 037 753 bytes; 347
  distinct tootukassa.ee advert links in the embedded data.
- Caveats: NOT in the production file (fin.ee is not named there). It is a subset of Töötukassa's portal, so it
  adds no adverts, only a ready-made public-sector filter. It covers schools and municipal bodies too (teachers,
  support staff), not only civil servants.

### Vacancy statistics of Töötukassa on the open data portal
- Publisher: Eesti Töötukassa.
- Documentation: https://andmed.eesti.ee/datasets/eesti-tootukassa-poolt-vahendatud-vabade-tookohtade-statistika ;
  landing page https://www.tootukassa.ee/et/statistics-and-research/peamised-statistilised-naitajad/vabad-tookohad (not fetched).
- Data or endpoint: record
  https://andmed.eesti.ee/api/datasets/e5707aaa-a6cc-4cd9-a3e6-fb9df309ac76 ; files
  `https://andmed.eesti.ee/api/v2/datasets/e5707aaa-a6cc-4cd9-a3e6-fb9df309ac76/distribution/9889e170-e2bd-4a6d-bfd4-9375098fe195/file`
  (by occupation and county, 1 784 303 bytes) and
  `.../distribution/efd452e0-f515-49ea-9374-c5b16bb0ee4b/file` (by economic activity and county, 3 249 382 bytes).
  On data.europa.eu: https://data.europa.eu/data/datasets/oai-andmed-eesti-ee-e5707aaa-a6cc-4cd9-a3e6-fb9df309ac76
- Holds: counts of vacancies mediated by Töötukassa - at month end, added in the month, open in the month - by
  occupation or activity and by county, from 2004 (temporal coverage "2004-01-01/"). Aggregates, not adverts.
- Access: bulk XLSX files; the portal's JSON API for the record.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): the record gives each distribution `"license": "CC_BY_NC_3.0"`
  (https://andmed.eesti.ee/api/datasets/e5707aaa-a6cc-4cd9-a3e6-fb9df309ac76). Non-commercial.
- Volume: two files, 1.8 MB and 3.2 MB.
- Update cycle: declared "IRREG"; in practice about monthly (file versions dated 2026-02-05, 2026-04-07,
  2026-11-05; record updated 2026-11-05).
- Seen on 2026-11-28: GET of the record -> 200, application/json, 16 338 bytes. HEAD of the first file -> 302 to
  a signed object-store URL on s3.pilw.io (not followed; file not downloaded).
- Caveats: NOT in the production file. The portal moved: `avaandmed.eesti.ee` answers 301 to `andmed.eesti.ee`.
  The portal's search for "tööpakkumised" returned 0 datasets: there is no advert-level dataset. Töötukassa
  publishes about twenty other datasets there (registered unemployed, benefits), all statistics.

### CV.ee (CV-Online)
- Publisher: Alma Career Estonia OÜ (registry code 10166144).
- Documentation: no public documentation of a read API found. Terms: https://hr.cv.ee/tingimused
- Data or endpoint: https://www.cv.ee (per the production file: the site's JSON search API and each page's
  `__NEXT_DATA__`). Not requested here.
- Holds (per the production file): title, employer, town and county, country, salary (monthly or hourly, EUR),
  working-time types, description sections or a picture of the advert.
- Access: web only; the JSON the production system reads is the site's own interface, not an offered feed.
- Registration or key: none for reading.
- Cost: free to read.
- Licence or terms (exact wording, with URL): terms for an unregistered job seeker, clause 1.2
  (https://hr.cv.ee/tingimused): "Kõik õigused andmebaasile kuuluvad AC-le. [...] Võite kasutada andmebaasi
  andmeid, et võtta töökohale kandideerimiseks tööandjaga heas usus ühendust, kasutades selleks tööpakkumises
  esitatud kontaktandmeid. Te ei tohi teha andmebaasist väljavõtteid ega koopiaid ega kasutada seda ühelgi muul
  eesmärgil." (All rights to the database belong to AC. You may use its data to contact an employer in good
  faith in order to apply. You may not make extracts or copies of the database or use it for any other purpose.)
- Volume: not stated on the page read.
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://hr.cv.ee/tingimused -> 200, text/html, 186 356 bytes (the terms in Estonian).
  No request to cv.ee or www.cv.ee.
- Caveats: IN USE (key `cvee`, enabled). CONTRADICTION: the production file's terms column says "ToS allows;
  polite hourly", while clause 1.2 as read today forbids extracts and copies and any other purpose. robots.txt
  was not requested (one-request limit); no date of the terms' current version is printed on the page.

### CVKeskus.ee
- Publisher: CV Keskus OÜ (the same terms also govern cvmarket.lv and cvmarket.lt).
- Documentation: none for reading. Terms: https://www.cvkeskus.ee/kasutustingimused
- Data or endpoint: https://www.cvkeskus.ee (per the production file: server-rendered search pages and each
  advert's JobPosting ld+json). Not requested here.
- Holds (per the production file): title, employer, place, salary with unit (hour or month), employment type,
  remote flag, description.
- Access: web only.
- Registration or key: none for reading.
- Cost: free to read.
- Licence or terms (exact wording, with URL): https://www.cvkeskus.ee/kasutustingimused clause 2.10:
  "Kasutajal on õigus Veebikeskkonda kasutada üksnes üldlevinud veebibrauserite (näiteks Internet Explorer,
  Edge, Chrome, Mozilla Firefox, Safari jne) abil. Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või
  vahendite abil, mis võimaldavad teha ilma inimese sekkumiseta automaatseid päringuid. Käesoleva punkti
  rikkumisel on CV Keskusel õigus nõuda igalt rikkujalt leppetrahvi 10 000 eurot iga rikkumise eest. Sealjuures
  loetakse eraldi rikkumiseks iga päringut, mis rikub käesolevas punktis kokkulepitut." Clause 4.4: "Kasutajal
  ega kolmandatel isikutel ei ole ilma CV Keskuse eelneva kirjaliku nõusolekuta õigust Veebikeskkonda ja selle
  koostisosi mistahes viisil reprodutseerida, levitada, edastada, tõlkida, lülitada teistesse andmebaasidesse,
  teha väljavõtteid jms viisil kasutada."
- Volume: not stated on the page read. A third-party guide (manatal.com) calls it Estonia's largest board.
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.cvkeskus.ee/kasutustingimused -> 200, text/html, 193 332 bytes.
- Caveats: IN USE in the sense of built: key `cvkeskus`, "seeded off"; the production file records the same
  clause and that the operator accepted the risk in 2026-10. The clause is confirmed unchanged today.

### Other job sources named in the production file (described from that file; no request made)
- CV Pro, cvpro.ee (key `cvpro`, seeded off 2026-09-29): IT category list pages plus JobPosting ld+json; the
  file records "robots allows; no automation clause (database rights claimed)" and that it re-lists Töötukassa.
- MeetFrank, api.meetfrank.com (key `meetfrank`, enabled in test; `meetfrankpeople` seeded off): the site's
  public GraphQL API; "no clause; the site blocks bots, the API does not"; salary range with currency and period.
- Bolt careers, bolt.eu (key `bolt`, enabled): sitemap plus detail pages.
- Employer feeds through applicant-tracking vendors (keys `ats:*`, `teamdash:*`, `icims:nortal`): Teamtailor,
  Greenhouse, Lever, Ashby, Workable, Personio, BambooHR, SmartRecruiters, Phenom, Eightfold, Workday, TeamDash
  and Nortal's iCIMS listing, for some thirty named employers. These vendors' public feeds belong to the
  EU-wide layer of this study.
- Surveyed and not built, per the file: Recruitee boards (empty), Glassdoor and Facebook (terms forbid), Indeed
  and hh.ee (no Estonian site / dead), otsintood.ee (a cv.ee iframe), devjobsscanner.com (lists LinkedIn
  URLs), workinestonia.com (low volume, not surveyed to fixture depth).
- Not job sources (company and place data, in the file for other purposes): the e-Business Register open data,
  the Tax and Customs Board files, ITL, Tehnopol, LinkedIn company pages, EHAK/ADS, GeoNames, GISCO, GitHub.

### Statistics Estonia - job vacancy tables
- Publisher: Statistikaamet (Statistics Estonia).
- Documentation: API manual https://andmed.stat.ee/help/api-manual.pdf (Estonian:
  https://andmed.stat.ee/abi/api-juhend.pdf); not fetched.
- Data or endpoint: PxWeb API `https://andmed.stat.ee/api/v1/en/stat/PAV011` (also PAV013, PAV014, PAV015 under
  /majandus/palk-ja-toojeukulu/vabad-ametikohad).
- Holds: PAV011 - number of job vacancies, vacancy rate, occupied posts, employees hired and separated, with
  standard errors, by economic activity (20 groups), quarterly 2008 Q1 to 2026 Q2. PAV014 by county, PAV015 by
  kind of owner. From the employer survey, not from adverts.
- Access: API (GET for metadata, POST for data), also web tables.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "Statistics Estonia's open data can be shared under Creative
  Common (CC) licence BY-SA 4.0."
  (https://stat.ee/en/statistics-estonia/about-us/strategy/principles-dissemination-official-statistics)
- Volume: four current tables.
- Update cycle: quarterly (tables last published 2026-09-07).
- Seen on 2026-11-28: GET https://andmed.stat.ee/api/v1/en/stat?query=vacancies -> 200, application/json, 1 858
  bytes, 7 tables; GET .../stat/PAV011 -> 200, application/json, 3 467 bytes (metadata: 3 variables).
- Caveats: NOT in the production file. No data rows were requested.

### EURES
- Töötukassa provides the EURES service. The employers' guide says a vacancy is sent to the EURES portal when
  the employer answers "Mujalt Euroopa Liidust" (from elsewhere in the EU) to where it wants to find workers:
  "saadame Teie töökuulutuse inglise keelsena üle-euroopalisse EURES portaali (eures.europa.eu)". Whether
  vacancies without that choice are also sent was not established.

## Not free or not allowed

- CV Keskus: automated queries forbidden, 10 000 € contractual penalty per query (clause 2.10); reuse and
  inclusion in other databases forbidden without written consent (clause 4.4).
- cv.ee: extracts and copies of the database and any use other than applying forbidden for unregistered
  visitors (clause 1.2).
- Töötukassa's vacancy statistics: CC BY-NC 3.0 - no commercial reuse.
- No paid data product or partner feed was found described on any page read; both commercial boards sell
  employer services (advert posting, CV database access), which are not read access to vacancies.
- Third-party scrapers of tootukassa.ee are sold on apify.com (seen in search results only); they are not an
  official channel.

## Gaps

- Töötukassa's terms of use: not read (client-rendered page; one request allowed). Its robots.txt: not
  requested; "Crawl-delay 10" is from the production file.
- cv.ee robots.txt and cvkeskus.ee robots.txt: not requested (one-request limit per in-use host).
- The number of live vacancies on Töötukassa, cv.ee and CVKeskus: not stated on any page read.
- Licence of the fin.ee "Avalikud konkursid" page: not stated; the ministry's site terms were not read.
- Whether Töötukassa sends all vacancies to EURES or only those flagged for EU recruitment: not established.
- Not checked at all: tippjuhid.riigikantselei.ee (top civil-service competitions, named in a ministry FAQ),
  municipal job pages (Tallinn, Tartu), kandideeri.ee, GoWorkaBit, Delfi's job section, the Work in Estonia job
  board (said by a third-party guide, manatal.com, to aggregate the local portals).
- The data.europa.eu search for "tööpakkumised" with country Estonia returned 0; "Töötukassa" returned 21, of
  which only the statistics dataset above concerns vacancies.
