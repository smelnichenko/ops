# Estonia (EE) - check of the research

The research file has no section on the employer route; it is added in a later pass.

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent, one capped GET or HEAD per URL, one at
a time; web search for leads only. No account, key or login. Hosts named in the production file
(`/home/sm/src/masi/docs/sources.md`): one request each to `hr.cv.ee` (terms), `www.cvkeskus.ee` (terms) and
`www.tootukassa.ee` (terms), none to a data endpoint, none to any other host of that file. Their robots.txt
files were read as dated copies in the Internet Archive, not from the hosts. `www.fin.ee` (a ministry site, not
in that file) got four requests: the list, the guide PDF, robots.txt and one HEAD. Official statistics were not
requested (out of purpose); the open data record of Töötukassa's statistics had been read before that rule came.

## Corrections and unverified claims (apply these first)

- WRONG: "Avalikud konkursid ... is a subset of Töötukassa's portal, so it adds no adverts", and "each linking to
  its Töötukassa posting". Of the 445 rows on 2026-11-28, 347 link to `www.tootukassa.ee`, 81 to `talendipank.ee`
  and 17 to `tallinn.teamdash.com`: 98 rows (22 %) are not Töötukassa links.
- CORRECTED: deadlines on that page run to 2027-03-29 (95 in November 2026, 344 in December, 6 in January-March
  2027), not "up to late December 2026".
- CORRECTED: cv.ee clause 1.2 belongs to the terms "REGISTREERUMATA VÕI AUTENTIMATA TÖÖOTSIJALE" (for the
  unregistered or unauthenticated JOB SEEKER using www.cv.ee), not to "visitors" in general. Its ban is on
  extracts and copies of the database and on "any other purpose"; it does not name automated reading. The only
  clause on the page that names programs and scripts is 3.6 of the terms for registered EMPLOYERS.
- CORRECTED: the cv.ee terms page does carry a date, in its HTML head, not in the visible text:
  `<meta http-equiv="last-modified" content="Thu, 26 Mar 2026 11:53:26 GMT">`.
- CORRECTED: CV Keskus volume IS on the page read: its header shows "Tööpakkumised 3 378" (3 378 job offers).
- CORRECTED: Töötukassa publishes 17 datasets on the portal as harvested by data.europa.eu (16 besides the
  vacancy statistics), not "about twenty other".
- CORRECTED (addition): the production file's "ToS allows; polite hourly" for cv.ee is not supported by today's
  wording: no clause on the page allows automated reading or copying. See claims 20-22.
- UNVERIFIED: Töötukassa's terms of use - the one request allowed returned the application shell again
  (200, 140 799 bytes, no text); a site-restricted web search did not return the text.
- UNVERIFIED: "Public-sector employers must post here [on Töötukassa's portal]" - the guide read today explains
  how to enter vacancies and states no obligation; and 98 competitions on the ministry's list link elsewhere.
- UNVERIFIED: "fed automatically from Töötukassa's portal" (fin.ee list) - the ministry's recruitment page was
  not requested (request budget for the host spent); the list's own links contradict "only from Töötukassa".
- UNVERIFIED: everything about Töötukassa's live portal (endpoint, fields, no registration to read, continuous
  updates) - data endpoints of an in-use host were not requested; the claims match the production file only.
- UNVERIFIED: today's robots.txt of tootukassa.ee, cv.ee and cvkeskus.ee - not requested from the hosts (one
  request each, spent on the terms); Internet Archive copies of March-May 2026 were read instead.
- UNVERIFIED: terms of cvpro.ee (terms address not found; the archived front page is a script shell) and of
  MeetFrank (the archived copy of meetfrank.com is a CloudFront "403 ERROR - Request blocked" page; not requested).
- UNVERIFIED: the Statistics Estonia block (PAV011-PAV015, CC BY-SA 4.0, quarterly) and the HEAD of the
  statistics file (302 to s3.pilw.io) - not requested: statistics are of no use for the purpose.
- UNVERIFIED: manatal.com calling CV Keskus Estonia's largest board - third-party page, not re-read.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | Estonia has no open-data dump and no documented public API of job adverts | NOT DISPROVED | `https://andmed.eesti.ee/api/datasets?search=...` -> 200 JSON: "tööpakkumised" total 0, "tööpakkum" 0, "töökuulutus" 0, "vabad töökohad" 0, "vacancies" 3 and "töökohtade" 2 (statistics only). data.europa.eu hub search, country ee: "tööpakkumised" count 0; "töötukassa" count 21, all statistics by title. Web search returned only third-party scrapers on apify.com | - |
| 2 | Töötukassa portal: web application at https://www.tootukassa.ee/et/toopakkumised; the production system reads the site's GraphQL (`jobOfferSearch`, `publicJobOfferQuery`), not a documented API | UNVERIFIED | Not requested (data endpoint of an in-use host). The production file says "GraphQL (`jobOfferSearch`, `publicJobOfferQuery`); >=10 s between calls" | - |
| 3 | Employers' guide PDF on fin.ee | CONFIRMED | GET `https://www.fin.ee/sites/default/files/documents/2023-11/Juhend%20t%C3%B6%C3%B6pakkumiste%20sisestamiseks%20ametiasutustele.pdf` -> 200, application/pdf, 871 526 bytes, 8 pages, "TÖÖPAKKUMISTE SISESTAMINE E-TÖÖTUKASSAS" | - |
| 4 | Töötukassa holds title, employer, first address, salary in EUR with no period, part-time flag, contract duration code, description (per the production file) | UNVERIFIED | Not requested live. The production file's table gives: EUR with no period, part-time on a row that offers it, `toosuhteKestusKood` (TAHTAJALINE / TAHTAJATU), first address | - |
| 5 | Occupation is assigned when the employer enters the vacancy | CONFIRMED | Guide: "Ametialad ilmuvad automaatselt ametinimetuse sisestamisel ning aitavad leida süsteemist sobivaid kandidaate." | - |
| 6 | Töötukassa: web only; no open-data dump, RSS or documented API found | NOT DISPROVED | As claim 1. The archived robots.txt (claim 9) names `Sitemap: https://www.tootukassa.ee/web/joboffers/sitemap.xml` (not requested) | - |
| 7 | No registration or key for reading the public pages; free; continuous updates | UNVERIFIED | Public pages not requested | - |
| 8 | Töötukassa terms of use: not read; the terms page is a client-rendered shell | CONFIRMED | GET `https://www.tootukassa.ee/et/kasutustingimused` -> 200, text/html, 140 799 bytes, `<title>Töötukassa</title>`, inline font CSS, no page text. The terms stay unread | - |
| 9 | robots.txt "Crawl-delay 10" (from the production file) | CONFIRMED | Production file: "Crawl-delay 10 honoured". Internet Archive copy of 2026-05-01 (`https://web.archive.org/web/20260501170514id_/https://www.tootukassa.ee/robots.txt`, 200, 2 048 bytes): "User-agent: *", "Crawl-delay: 10", "Disallow: /et/toopakkumised?", "Disallow: /en/joboffers?". Today's file not requested | - |
| 10 | Töötukassa is IN USE (key `tootukassa`, enabled, at least 10 s between calls) | CONFIRMED | Production file row `tootukassa` | - |
| 11 | Public-sector employers must post on Töötukassa's portal | UNVERIFIED | The guide explains how and says public-sector offers "avalikustatakse koheselt"; no obligation is stated in it | - |
| 12 | Avalikud konkursid: publisher Ministry of Finance, successor of avalikteenistus.ee | CONFIRMED | GET `https://www.fin.ee/avalikud-konkursid` -> 200, text/html, 1 037 677 bytes; footer "Kui avalikteenistus.ee veebilehe kasutamisega esineb probleeme, palume pöörduda ..." | - |
| 13 | The long URL answers 301 to /avalikud-konkursid | CONFIRMED | HEAD `https://www.fin.ee/riigihaldus-ja-avalik-teenistus-kinnisvara/avalik-teenistus/avalikud-konkursid` -> 301, Location `https://www.fin.ee/avalikud-konkursid` | - |
| 14 | The page holds title, institution, region or address, deadline (ISO in the markup), a field id, and the advert link; no description, salary or occupation code | CONFIRMED | Each row of the embedded list has 8 values: title link, institution, `<time datetime="2026-12-10T12:00:00Z">`, address, link, a field id ("215"), two sort keys. The card list also has "Koormus: Põhikoht" (workload) | Add the workload field |
| 15 | Every row links to `https://www.tootukassa.ee/toopakkumised/<slug>-<id>` | WRONG | Link hosts over the 445 rows: www.tootukassa.ee 347, talendipank.ee 81, tallinn.teamdash.com 17 | 347 of 445 rows link to Töötukassa; 98 link to talendipank.ee or tallinn.teamdash.com |
| 16 | One HTML page holding the whole list as embedded JSON (`<script type="application/json" id="datatable-...">`), filtered in the browser | CONFIRMED | Two embedded lists (`datatable-...` and `cards-...`), 445 rows each, `pageLength` 15 | - |
| 17 | No API or feed for the list found; `/rss-feeds/rss.xml` is the ministry's general feed | NOT DISPROVED | The page links `/rss-feeds/rss.xml`; not requested | - |
| 18 | No licence stated on the page | NOT DISPROVED | No licence, Creative Commons or copyright wording in the page text; the footer links only `/privaatsussatted` | - |
| 19 | Volume "Kuvatud 445 töökuulutust"; 347 distinct tootukassa.ee advert links | CONFIRMED | "Kuvatud 445 töökuulutust" in the page; 445 rows; 347 distinct Töötukassa advert ids | - |
| 20 | Page "Viimati uuendatud 02.09.2025"; adverts carry deadlines up to late December 2026 | CORRECTED | "Viimati uuendatud 02.09.2025" seen. Deadlines 2026-11-28 to 2027-03-29 | Deadlines run to 2027-03-29 |
| 21 | The list is fed automatically from Töötukassa's portal | UNVERIFIED | The ministry's recruitment page was not requested; 98 rows link to two other sites | - |
| 22 | It is a subset of Töötukassa's portal and adds no adverts | WRONG | As claim 15 | It adds 98 competitions hosted on talendipank.ee and tallinn.teamdash.com |
| 23 | It covers schools and municipal bodies, not only civil servants | CONFIRMED | Rows such as "Matemaatikaõpetaja - Tallinna Lilleküla Gümnaasium", "Abiõpetaja" | - |
| 24 | fin.ee is not named in the production file | CONFIRMED | No match for "fin.ee" or "talendipank" in the file | - |
| 25 | Töötukassa vacancy statistics on the open data portal: record, two XLSX files (1 784 303 and 3 249 382 bytes), `"license": "CC_BY_NC_3.0"`, coverage "2004-01-01/", "IRREG" | CONFIRMED | GET `https://andmed.eesti.ee/api/datasets/e5707aaa-a6cc-4cd9-a3e6-fb9df309ac76` -> 200, application/json, 16 338 bytes; both distributions `license: CC_BY_NC_3.0`, `byteSize` as stated, `temporalCoverage: 2004-01-01/`, `accrualPeriodicity: IRREG` | Statistics: of no use for the purpose |
| 26 | In practice about monthly (versions 2026-02-05, 2026-04-07, 2026-11-05); record updated 2026-11-05 | CONFIRMED | `datasetFiles`: a pair of files on 2026-01-09, 02-05, 03-05, 04-07, 05-05, 06-05, 07-06, 08-06, 09-08, 10-05, 11-05; `updatedAt: 2026-11-05` | - |
| 27 | HEAD of the first file -> 302 to s3.pilw.io | UNVERIFIED | Not requested (statistics; s3.pilw.io is a host of the production file) | - |
| 28 | The dataset is on data.europa.eu as `oai-andmed-eesti-ee-e5707aaa-...` | CONFIRMED | Listed under that id in the hub search answer, publisher "Eesti Töötukassa", format XLSX | - |
| 29 | `avaandmed.eesti.ee` answers 301 to `andmed.eesti.ee` | CONFIRMED | HEAD `https://avaandmed.eesti.ee/` -> 301, Location `https://andmed.eesti.ee/` | - |
| 30 | The portal's search for "tööpakkumised" returned 0 datasets: there is no advert-level dataset | NOT DISPROVED | `{"data":[],"metadata":{"page":1,"limit":20,"total":0,"search":"tööpakkumised"}}`. The search matches whole words of titles ("vabad töökohad" also gives 0 although the statistics dataset exists), so 0 alone proves little; the other queries of claim 1 found nothing either | - |
| 31 | Töötukassa publishes about twenty other datasets there, all statistics | CORRECTED | data.europa.eu hub search "töötukassa", country ee: 21 results, 17 with publisher "Eesti Töötukassa" (work ability, benefits, registered unemployed, redundancies, labour market services...), 4 by Statistikaamet | 16 other datasets, all statistics by title |
| 32 | data.europa.eu: "tööpakkumised" + Estonia = 0; "Töötukassa" = 21, one about vacancies | CONFIRMED | `https://data.europa.eu/api/hub/search/search?q=...&facets={"country":["ee"]}` -> count 0 and count 21 | - |
| 33 | cv.ee publisher: Alma Career Estonia OÜ, registry code 10166144 | CONFIRMED | Terms preamble: "Alma Career Estonia OÜ, registrikood 10166144, aadress Pärnu mnt 158/1, 11317 Tallinn" | - |
| 34 | cv.ee terms, clause 1.2, at https://hr.cv.ee/tingimused, as quoted | CONFIRMED | GET -> 200, text/html, 186 356 bytes. "1.2 Kõik õigused andmebaasile kuuluvad AC-le. Te ei omanda andmebaasi kasutamisel ühtegi õigust andmebaasile ega selle osadele. Võite kasutada andmebaasi andmeid, et võtta töökohale kandideerimiseks tööandjaga heas usus ühendust, kasutades selleks tööpakkumises esitatud kontaktandmeid. Te ei tohi teha andmebaasist väljavõtteid ega koopiaid ega kasutada seda ühelgi muul eesmärgil. Samuti ei tohi te andmebaasi kahjustada ega katkestada selle käitust." | - |
| 35 | Clause 1.2 is for "unregistered visitors" | CORRECTED | Heading: "Alma Career Estonia ANDMEBAASI KASUTUSTINGIMUSED REGISTREERUMATA VÕI AUTENTIMATA TÖÖOTSIJALE"; "neid kohaldatakse registreerumata või autentimata tööotsijale, kui ta kasutab veebisaiti www.cv.ee"; next paragraph: "Kui kasutate veebisaiti, et kandideerida sellel pakutavale töökohale, ja te ei ole endale veebisaidil kasutajakontot registreerinud ... kohaldatakse teile siinseid tingimusi." The page holds three documents: unregistered job seeker, registered job seeker, registered employers | It applies to the unregistered or unauthenticated job seeker; no document on the page addresses "any visitor" |
| 36 | Does clause 1.2 cover automated reading? (research: "forbids extracts and copies ... and any other purpose") | CORRECTED | 1.2 names no program, robot or automated query; it forbids "väljavõtteid ega koopiaid" of the database and use "ühelgi muul eesmärgil". The registered job seeker's 2.5 says the same with "muul eesmärgil kui teenuste kasutamiseks". Only the employers' terms name programs - 3.6: "Klient ei tohi Andmebaasi ja/või Veebisaiti täielikult või osaliselt kopeerida või kahjustada ega selle tööd häirida, sealhulgas mistahes arvutiprogrammide (rakenduste, skriptide, käsurealiidese kaudu tehtavate päringute vms) abil." | Job-seeker terms: copying and extraction forbidden, automated reading not named. Employer terms: copying by programs or scripts forbidden |
| 37 | Contradiction: the production file says "ToS allows; polite hourly" | CONFIRMED | The file's `cvee` row reads "ToS allows; polite hourly". A search of the page's whole text for automation words (automaat, robot, skript, crawl, päring, API ...) found only: data collected automatically from the visitor's device, automated decisions (GDPR), the Kombo API for employers, and the employers' clause 3.6. No clause permits automated reading, reuse or copying | Today's wording does not support "ToS allows" |
| 38 | No date of the terms' current version is printed on the page | CORRECTED | No date in the visible text (only "2016" of the GDPR). HTML head: `<meta http-equiv="last-modified" content="Thu, 26 Mar 2026 11:53:26 GMT" />` | Page last modified 2026-03-26 per its own meta tag |
| 39 | No public documentation of a read API of cv.ee found | NOT DISPROVED | The terms name only employer-side integrations: "Kombo Technologies GmbH API-d" and "SoftExpert OÜ vahekiht" for syncing an employer's adverts and candidates with its own system | - |
| 40 | cv.ee holds (per the production file) title, employer, town and county, country, salary (monthly or hourly, EUR), working-time types, description sections or a picture | UNVERIFIED | Not requested live; it matches the production file (`townId`, `countyId`, `countryId`, `hourlySalary`, `workTimes`, sections else picture) | - |
| 41 | cv.ee robots.txt was not requested | CONFIRMED | Still not requested from the host. Internet Archive copy of 2026-03-24 of `https://cv.ee/robots.txt` (200, 1 777 bytes): "User-agent: *", "Content-Signal: search=yes,ai-train=no", "Allow: /"; "Disallow: /" for Amazonbot, Applebot-Extended, Bytespider, CCBot, ClaudeBot, CloudflareBrowserRenderingCrawler, Google-Extended, GPTBot, meta-externalagent | - |
| 42 | CV Keskus publisher: CV Keskus OÜ; the same terms govern cvmarket.lv and cvmarket.lt | CONFIRMED | GET `https://www.cvkeskus.ee/kasutustingimused` -> 200, text/html, 193 407 bytes. "1.1. Käesolevad kasutustingimused ... reguleerivad veebikeskkonna www.cvkeskus.ee, www.cvmarket.lv ja www.cvmarket.lt (Veebikeskkond) kasutamist."; 1.3 "CV Keskus OÜ (registrikood: 11325768 ...)" | - |
| 43 | Clause 2.10 as quoted (browsers only; automated queries forbidden; 10 000 EUR per breach; each query a breach) | CONFIRMED | "2.10. Kasutajal on õigus Veebikeskkonda kasutada üksnes üldlevinud veebibrauserite (näiteks Internet Explorer, Edge, Chrome, Mozilla Firefox, Safari jne) abil. Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või vahendite abil, mis võimaldavad teha ilma inimese sekkumiseta automaatseid päringuid. Käesoleva punkti rikkumisel on CV Keskusel õigus nõuda igalt rikkujalt leppetrahvi 10 000 eurot iga rikkumise eest. Sealjuures loetakse eraldi rikkumiseks iga päringut, mis rikub käesolevas punktis kokkulepitut." It applies to every visitor: "1.4. Veebikeskkonna kasutajaks (Kasutaja) on iga isik, kes kasutab Veebikeskkonda." and "1.5. ... kasutamine [on] mistahes Veebikeskkonna moodustava dokumendi allalaadimine, avamine või muul viisil töötlemine." | - |
| 44 | Clause 4.4 as quoted | CONFIRMED | "4.4. Kasutajal ega kolmandatel isikutel ei ole ilma CV Keskuse eelneva kirjaliku nõusolekuta õigust Veebikeskkonda ja selle koostisosi mistahes viisil reprodutseerida, levitada, edastada, tõlkida, lülitada teistesse andmebaasidesse, teha väljavõtteid jms viisil kasutada. Kasutaja kohustub mitte edastama kolmandatele isikutele mistahes teoseid, mis ta on saanud Veebikeskkonda kasutades." | - |
| 45 | The clause is unchanged today; the production file records it and the operator's acceptance of the risk in 2026-10; key `cvkeskus` seeded off | CONFIRMED | Page: "Viimati muudetud: 18.10.2021". Production file row `cvkeskus`: "ToS §2.10 forbids automated queries (10 000 € a request); the operator accepted the risk 2026-10; 1 s between calls", "seeded off" | - |
| 46 | CV Keskus volume: not stated on the page read | CORRECTED | The page header shows "Tööpakkumised 3 378" | 3 378 job offers on 2026-11-28 |
| 47 | A third-party guide (manatal.com) calls CV Keskus Estonia's largest board | UNVERIFIED | Not re-read | - |
| 48 | Other sources described from the production file (cvpro, MeetFrank, Bolt, the `ats:*`, `teamdash:*`, `icims:nortal` feeds for some thirty employers, the surveyed-and-not-built list, the non-job sources) | CONFIRMED | Against the file only: `cvpro` "robots allows; no automation clause (database rights claimed)", seeded off 2026-09-29; `meetfrank` "no clause; the site blocks bots, the API does not", enabled in test; `bolt` enabled; 23 `ats:*` + 5 TeamDash + 1 iCIMS rows; the not-built table as listed. No request made | - |
| 49 | Statistics Estonia: PxWeb API, tables PAV011, PAV013-PAV015, no key, quarterly to 2026 Q2, CC BY-SA 4.0 | UNVERIFIED | Not requested: statistics | - |
| 50 | EURES: Töötukassa provides the service; a vacancy is sent to EURES when the employer answers "Mujalt Euroopa Liidust" | CONFIRMED | Guide: "Valides „Kust soovite leida töötajaid?“ vastuseks „Mujalt Euroopa Liidust“ saadame Teie töökuulutuse inglise keelsena üle-euroopalisse EURES portaali (eures.europa.eu)." See "Found beyond the research" for the other vacancies | - |
| 51 | CV Keskus forbids automated queries outright, 10 000 EUR a query; reuse and inclusion in other databases forbidden without written consent | CONFIRMED | Claims 43 and 44 | - |
| 52 | Töötukassa's vacancy statistics are CC BY-NC 3.0 | CONFIRMED | Claim 25 | - |
| 53 | No paid data product or partner feed was found described on any page read | NOT DISPROVED | None on the two terms pages; only employer-side integrations (claim 39) | - |
| 54 | Third-party scrapers of tootukassa.ee are sold on apify.com | CONFIRMED | In today's search results: `apify.com/studio-amba/tootukassa-scraper`, `apify.com/unfenced-group/tootukassa-ee-scraper` (not opened) | - |

## For a personal job search and applications

| Source | Job-seeker use | Automated reading | Private copy | How to apply | Basis (quoted clause, URL) |
|---|---|---|---|---|---|
| Töötukassa vacancy portal | not stated - terms not read (script shell) | not stated in terms (unread). robots.txt, archive copy of 2026-05-01: allowed with a delay - "User-agent: *", "Crawl-delay: 10"; list addresses with a query are disallowed ("Disallow: /et/toopakkumised?", "/en/joboffers?", "/ru/vakansii?"); a job-offer sitemap is named. A crawl-delay rule, not a ban | not stated | not stated on anything read (advert pages not requested) | https://www.tootukassa.ee/et/kasutustingimused (shell); https://web.archive.org/web/20260501170514id_/https://www.tootukassa.ee/robots.txt |
| Avalikud konkursid (fin.ee) | not stated - no terms on the page | not stated in terms. robots.txt today: allowed for the page - "User-agent: *" with Drupal's standard Disallow lines (/admin/, /search/, /user/login ...), none covering /avalikud-konkursid, no Crawl-delay | not stated - no licence on the page | apply link in the record: each row links to the advert on tootukassa.ee (347), talendipank.ee (81) or tallinn.teamdash.com (17) | https://www.fin.ee/avalikud-konkursid ; https://www.fin.ee/robots.txt |
| cv.ee | allowed - "AC volitab teid siinsete tingimuste kohaselt veebisaiti kasutama ning annab tasuta juurdepääsu AC andmebaasile" (1.1); "Võite kasutada andmebaasi andmeid, et võtta töökohale kandideerimiseks tööandjaga heas usus ühendust" (1.2) | not stated for job seekers - no clause of the job-seeker terms names bots, scripts or automated queries. The employers' terms forbid copying by programs: 3.6 "... ei tohi Andmebaasi ja/või Veebisaiti täielikult või osaliselt kopeerida ... sealhulgas mistahes arvutiprogrammide (rakenduste, skriptide, käsurealiidese kaudu tehtavate päringute vms) abil" (a ban on copying, whatever the purpose, addressed to employer clients). robots.txt, archive copy of 2026-03-24: "User-agent: *", "Content-Signal: search=yes,ai-train=no", "Allow: /"; named AI crawlers (ClaudeBot, GPTBot, CCBot ...) "Disallow: /" | forbidden - "Te ei tohi teha andmebaasist väljavõtteid ega koopiaid ega kasutada seda ühelgi muul eesmärgil" (1.2; registered: 2.5 "... muul eesmärgil kui teenuste kasutamiseks"). Not limited to commercial reuse: it bans extracts and copies as such | employer contact in the advert ("kasutades selleks tööpakkumises esitatud kontaktandmeid", 1.2) or the site's application form; without submitting it one must "i) võtma tööandjaga ise ühendust või ii) registreeruma veebisaidil kasutajaks" (2.7) | https://hr.cv.ee/tingimused ; https://web.archive.org/web/20260324190422id_/https://cv.ee/robots.txt |
| CVKeskus.ee | allowed, and only that - "2.5. Kasutaja võib kasutada Veebikeskkonda üksnes enesele töökoha või töötaja leidmiseks." | forbidden - a ban on bots whatever the purpose: 2.10 "Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või vahendite abil, mis võimaldavad teha ilma inimese sekkumiseta automaatseid päringuid", browsers only, 10 000 EUR "iga rikkumise eest", "eraldi rikkumiseks iga päringut". It binds "iga isik, kes kasutab Veebikeskkonda" (1.4). robots.txt, archive copy of 2026-05-01: "User-agent: *" disallows only login, CV and form paths and lists sitemaps and `rss-listings.xml` - the terms forbid what robots.txt leaves open | forbidden without prior written consent - 4.4 "... reprodutseerida, levitada, edastada, tõlkida, lülitada teistesse andmebaasidesse, teha väljavõtteid ..."; data from the site may be used only for finding oneself a job (2.5) | only through the board: 3.2 "Kasutajakonto võimaldab Kasutajal luua oma CV, kandideerida tööpakkumistele"; employers' 5.3 (iii) "tööpakkumises ei või sisalduda viidet võimalusele kandideerida tööpakkumisele muul viisil kui saates CV läbi Veebikeskkonna, välja arvatud kui selleks on CV Keskuse kirjalik nõusolek" | https://www.cvkeskus.ee/kasutustingimused ("Viimati muudetud: 18.10.2021"); https://web.archive.org/web/20260501042053id_/https://www.cvkeskus.ee/robots.txt |
| CV Pro (cvpro.ee) | not stated - terms not found | not stated - not read; the production file records "robots allows; no automation clause (database rights claimed)" | not stated | not stated | No request made: terms address unknown, the archived front page is a script shell |
| MeetFrank | not stated - terms not found | not stated - not read; the production file records "no clause; the site blocks bots, the API does not"; the Internet Archive's copy of meetfrank.com is a CloudFront "403 ERROR ... Request blocked" page | not stated | not stated | No request made to meetfrank.com or api.meetfrank.com |
| Bolt careers and the employers' feeds (`ats:*`, `teamdash:*`, `icims:nortal`) | not stated - not read here | not stated - not read here | not stated | not stated | Employer route: left to the later pass; no request made |
| Töötukassa vacancy statistics; Statistics Estonia tables | not stated - counts only, no adverts: of no use for this purpose | not stated | limited - the Töötukassa files are `CC_BY_NC_3.0` (non-commercial; a private copy is not commercial reuse) | not applicable: no adverts | https://andmed.eesti.ee/api/datasets/e5707aaa-a6cc-4cd9-a3e6-fb9df309ac76 |

## Found beyond the research

- The ministry's list is a source of its own for 98 competitions: 81 rows link to `talendipank.ee` and 17 to
  `tallinn.teamdash.com` (the City of Tallinn's board). Neither host was requested. A search result (a vendor's
  price offer, not the publisher's page) describes Talendipank as recruitment software of SoftExpert OÜ used by
  public bodies; the cv.ee terms name "SoftExpert OÜ" as an integration layer too. Unverified beyond that.
- Whether all Töötukassa vacancies reach EURES: a draft official letter of 28.04.2025 from Estonia to the
  Commission, read on a third-party mirror of public documents
  (`https://adr-docs.karlerss.com/5FcLla2VrZdIKtry8rFS585W71KqrqTI/438-5projekt_ET_Nava_EURES.pdf`, 200,
  application/pdf, 2 pages), says: "EURESe portaalile edastatakse teave kõikide vabade töökohtade kohta, mis on
  töötukassa poolt üldsusele kättesaadavaks tehtud", quotes the notice on Töötukassa's site ("... edastatakse kõik
  töötukassa kaudu avaldatud avalikud tööpakkumised üleeuroopalisesse EURESe portaali eures.europa.eu ...", at
  `https://www.tootukassa.ee/et/teenused/tooandjatele/tookuulutuse-lisamine`, not requested), and says a small
  number do not show there because some ISCO codes cannot be matched to ESCO codes. A draft on a mirror, not the
  publisher's own page: it suggests "all public offers", against the guide's "only when EU recruitment is chosen".
- Töötukassa's robots.txt (archive copy of 2026-05-01) names three sitemaps, among them
  `https://www.tootukassa.ee/web/joboffers/sitemap.xml`: a published list of job-offer addresses. Not requested.
- CV Keskus's robots.txt (archive copy of 2026-05-01) lists `https://www.cvkeskus.ee/rss-listings.xml` and
  listing sitemaps in three languages. Not requested; clause 2.10 forbids automated queries regardless.
- cv.ee's robots.txt (archive copy of 2026-03-24) opens with "As a condition of accessing this website, you agree
  to abide by the following content signals" and sets "search=yes,ai-train=no"; no signal is set for "ai-input",
  for which the file says the operator "neither grants nor restricts permission".
- CV Keskus terms: the board's count ("Tööpakkumised 3 378") and the date of the terms ("Viimati muudetud:
  18.10.2021") are both on the terms page.
- The cv.ee terms page states its own modification time in a meta tag: 26 March 2026.
- Still unchecked, as in the research: tippjuhid.riigikantselei.ee, municipal job pages, kandideeri.ee,
  GoWorkaBit, Delfi's job section, the Work in Estonia job board.
