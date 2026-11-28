# Netherlands (NL) - check of the research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`), no added headers, no
`-L`, every transfer capped (`--max-filesize 2000000 -m 30`), one request at a time. Web search (run by the
search service, not from this address) only to find page addresses. No account, key or login.
Requests per host: www.werkenvoornederland.nl 3, data.overheid.nl 2, www.werk.nl 2, www.kvk.nl 2,
www.jobbird.com 2, techleap.nl 2 (308, then 404), and 1 each to developers.kvk.nl, opendata.kvk.nl,
www.nationalevacaturebank.nl, www.intermediair.nl, www.monsterboard.nl (301), data.europa.eu,
developers.homerun.co, help.homerun.co, www.tellent.com, help.afas.nl. Vendor pages read earlier today for the
France and Belgium checks (Recruitee, Carerix, OTYS, Connexys and the international vendors) were not requested
again. No request to werkzoeken.nl (it refused the researcher). Indeed and LinkedIn were read once today for the
France check. No employer's board and no vendor data endpoint was requested.
**Four requests were declined by the session's permission system and not retried**: developer.overheid.nl
(`/apis/cso-vacature-api`), data.overheid.nl (`/dataset/vacatures-overheid` and `package_show?id=vacatures-overheid`)
and api.cso20.net (`/v1/JobAPI/`). What depends on them is UNVERIFIED.
Nationale Vacaturebank and Intermediair were asked for robots.txt only: both shut out "ClaudeBot" by name, and
this check is run by Claude.

The research file has the section "Through the employers"; it is checked below (claims 21-36).

## Corrections and unverified claims (apply these first)

- CORRECTED (claim 8): Werken voor Nederland's vacancy sitemap was requested: 200, 304,694 bytes, **1,309 vacancy
  addresses**, each with a last-modified time (newest 2026-11-28T11:10:14Z), of the form
  `https://www.werkenvoornederland.nl/vacatures/<title>-<organisation code>-<year>-<number>`. The "1500
  vacatures" of the list page was not re-read; the sitemap is the count a program would get.
- ADDITION (claim 1, confirmed): the statement "geen API vanuit het UWV" is the answer recorded on the national data
  portal's request page ("Toelichting status", request no. 2258 of 25-08-2020, result "Data is beschikbaar - niet
  in gewenste vorm"), which reports UWV's position ("volgens het UWV"); it is not a page of UWV's own. The words
  are as quoted.
- CORRECTED (claim 31): the vendors "named from memory" were read on their own pages. Carerix documents an XML
  feed per employer application for job sites (`https://application.carerix.com/cxtools/jobboardFeed.php?start=0&count=300&medium=mediumcode`),
  no key mentioned. Bullhorn Connexys' web services need "Username, Password, Security-token". OTYS's product
  page (Houten, "OTYS is part of Mysolution") documents no feed or API. AFAS's help page describes vacancies on
  the employer's own "OutSite" site and documents no feed.
- CORRECTED (claim 29): the third-party report of an authentication change at Recruitee "for 2027" does not
  match the owner's own notice found today (Tellent, "Offers refactor and rate limiting - upcoming changes to
  the API"): it concerns the ATS API used with a personal API token - a rate limit of "1000 requests/60 seconds",
  deadline "15th October 2025", and a reworked `/offers` endpoint. It says nothing about the careers-site
  endpoint and names no 2027 date.
- UNVERIFIED (declined by the session's permission system): **that the CSO Vacature API is gone** - its register
  pages (404), its dataset record (404, and 403 on `package_show`) and its address (503) were not re-requested.
  A web search still lists both register pages, as the research says.
- UNVERIFIED (blocked): Werkzoeken.nl - terms, the "API documentatie" page at `/doc/` (a web search still lists
  it), access. No request made.
- UNVERIFIED: the list page of Werken voor Nederland ("1500 vacatures", 604,029 bytes, no vacancy links in the
  HTML) - not re-requested (three requests spent on robots.txt, the copyright page and the sitemap).
- UNVERIFIED: Nationale Vacaturebank's and Intermediair's terms - not located by a web search and no further
  page requested (see the note on ClaudeBot above); the 404 on the guessed address was not re-requested.
- UNVERIFIED: werk.nl's terms of use. A web search finds none for job seekers; a UWV report (search summary)
  refers to "de algemene voorwaarden van Werk.nl", so terms exist somewhere. Whether the vacancy search needs a
  login is still open (the redirect to the login server was seen, not followed).
- UNVERIFIED: Techleap "Finder" (free account, paid export) - Techleap's blog post answers 308 and then 404
  today; the claim rests on a search summary of a 2021 post.
- UNVERIFIED: that Recruitee and Homerun are Dutch - not stated on the pages read. That any vendor in the table
  is used by Dutch employers - no source.
- UNVERIFIED: the dates of the files inside UWV Open Match Data (2019-2021); KVK's free web search and its
  limits; the EURES count of 285,437 (EU-wide file); the scrapers on apify.com - not requested.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | UWV said itself, on the national data portal: "Werk.nl beschikt helaas niet over een API van alle vacatures. [...] In principe is het volgens het UWV mogelijk om de data te scrapen. [...] helaas is er geen API vanuit het UWV [...] en die gaat voorlopig ook niet gerealiseerd worden." (request of 25-08-2020, status "Afgehandeld") | CONFIRMED | GET https://data.overheid.nl/community/datarequest/vacatures-werk-nl -> 200, text/html, 30,653 bytes: the text word for word under "Beantwoording - Toelichting status"; "Aangevraagde datum: 25-08-2020", "Status: Afgehandeld", "Afgehandeld resultaat: Data is beschikbaar - niet in gewenste vorm", "Data eigenaar: Uitvoeringsinstituut Werknemersverzekeringen (Rijk)", "Laatst aangepast: 6 years 3 months geleden" | The wording is right; it is the portal's recorded answer reporting UWV's position, six years old, not a UWV page. |
| 2 | UWV / werk.nl offers no API and no dump of vacancies | NOT DISPROVED | Portal search GET `https://data.overheid.nl/data/api/3/action/package_search?q=vacatures&rows=40` -> 200, 428,210 bytes, 61 results, 40 read: CBS tables, "UWV Open Match Data" (counts), no vacancy-level dataset of UWV. EU portal search for the Netherlands (`q=vacatures`, 62 results, 25 read): CBS tables only. A web search for a UWV developer portal or vacancy API found none (a UWV tender text speaks of "B-t-B-koppelingen met partners", search summary) | - |
| 3 | werk.nl robots.txt, whole file: "User-agent: * Disallow: /webpublicaties Sitemap: https://www.werk.nl/nl/sitemap.xml" | CONFIRMED | GET https://www.werk.nl/robots.txt -> 200, text/plain, 85 bytes, exactly that | - |
| 4 | The vacancy path answers with a redirect to UWV's login server | CONFIRMED | GET https://www.werk.nl/werkzoekenden/vacatures/ -> 302, `Location: https://login.werk.nl:443/oam/server/obrareq.cgi?...agentid=LN_UWV_EXTERN_ACCESS_SERVER...` (not followed: a login) | - |
| 5 | No terms page of werk.nl was found | NOT DISPROVED | A web search found no terms page for job seekers; see the unverified list | - |
| 6 | UWV Open Match Data: counts per occupation and postcode area, CC BY 4.0, record updated 28-08-2025 | CONFIRMED | Portal search (claim 2): "UWV Open Match Data", licence `http://creativecommons.org/licenses/by/4.0/deed.nl`, `metadata_modified` 2025-08-28, 182 resources. Not opened: statistics | - |
| 7 | Werken voor Nederland: "Tenzij anders vermeld is op de inhoud van deze website de Creative Commons zero verklaring (CC0) van toepassing. Dit houdt in dat hergebruik van de inhoud van deze site is toegestaan [...] Voor foto's is de CC0 niet van toepassing."; "Bij hergebruik van de inhoud van deze website is naamsvermelding niet verplicht." | CONFIRMED | GET https://www.werkenvoornederland.nl/copyright -> 200, text/html, 47,557 bytes: both passages word for word; it adds "Maar bij het citeren van de inhoud mag niet de indruk worden gewekt dat de Rijksoverheid zonder meer de strekking van het afgeleide werk onderschrijft." No word robot, scrap or crawl | - |
| 8 | Werken voor Nederland has a vacancy sitemap (named in robots.txt, not requested); about 1,500 vacancies | CORRECTED | GET https://www.werkenvoornederland.nl/sitemap-vacatures.xml -> 200, application/xml, 304,694 bytes: 1,309 `<loc>` entries under `/vacatures/`, each with `<lastmod>` and `<changefreq>daily</changefreq>`; newest 2026-11-28T11:10:14Z | The sitemap lists 1,309 vacancy pages today. |
| 9 | Its robots.txt, whole file: "User-agent: * Disallow: /login Request-rate: 10/1 Visit-time: 0000-2400" and two sitemaps | CONFIRMED | GET https://www.werkenvoornederland.nl/robots.txt -> 200, text/plain, 200 bytes, exactly that; sitemaps `/sitemap.xml` and `/sitemap-vacatures.xml` | - |
| 10 | The list page says "1500 vacatures" and holds no vacancy links or JSON-LD (604,029 bytes) | UNVERIFIED | Not re-requested (three requests used) | - |
| 11 | The CSO Vacature API is gone: register pages 404, dataset record 404 / 403, `https://api.cso20.net/v1/JobAPI/` 503 | UNVERIFIED | The four requests were declined by the session's permission system; not retried | - |
| 12 | The CSO API served the vacancies of WerkenvoorNederland.nl, WerkenbijdeOverheid.nl and Mobiliteitsbank.nl as REST/JSON, free, CC0 (search summaries) | UNVERIFIED | Not readable at the publisher (claim 11). A web search summary of the register page says it covers counting, fetching and filtering vacancies and names "Uitvoeringsorganisatie Bedrijfsvoering Rijk" | - |
| 13 | Nationale Vacaturebank robots.txt, all agents: "Disallow: /vacature/zoeken?*", "/vacatures/*?page=", "/vacature/apply/", "/vacature/external-url/", "/solliciteren/", "/archief/"; "User-agent: ClaudeBot Disallow: /"; ten sitemaps, among them `/cdn/sitemaps/vacature.xml` | CONFIRMED | GET https://www.nationalevacaturebank.nl/robots.txt -> 200, text/plain, 2,818 bytes: every line; ten `Sitemap:` lines | - |
| 14 | Intermediair shares the robots.txt structure (3,735 bytes) | CONFIRMED | GET https://www.intermediair.nl/robots.txt -> 200, text/plain, 3,735 bytes: a ClaudeBot group as well, nine `Sitemap:` lines with `/cdn/sitemaps/vacature.xml` | - |
| 15 | Nationale Vacaturebank's terms were not located (404 on a guessed address) | UNVERIFIED | Not requested; a web search did not find them | - |
| 16 | Jobbird terms: adverts are "geanonimiseerd, met uitzondering van bedrijfsnaam en logo"; Art. 3: "Het is nadrukkelijk verboden om zonder voorafgaande schriftelijke toestemming van de platforms verveelvoudiging of (her) publicatie van (een deel van) de website of de daarop vermelde informatie over te nemen."; no contact details allowed in an advert; applying through Jobbird | CONFIRMED | GET https://www.jobbird.com/nl/algemene-voorwaarden -> 200, text/html, 60,868 bytes: all four passages; no clause on robots or scripts (the hits for "geautomatiseerd" and "software" concern data files and suppliers) | - |
| 17 | Jobbird robots.txt disallows `/*/api`, `/*/export`, `/*/xml`, `/nl/vacature?*`, `/*/job_contact`, `/*/job_mail`, `/outgoing/*` | CONFIRMED | GET https://www.jobbird.com/robots.txt -> 200, text/plain, 1,514 bytes: every line under `User-agent: *` | - |
| 18 | Werkzoeken.nl blocked the client (403); an "API documentatie" page exists at /doc/ | UNVERIFIED | No request made (blocked host) | - |
| 19 | Monsterboard redirects to https://www.monster.com/nl/ | CONFIRMED | GET https://www.monsterboard.nl/ -> 301, `location: https://www.monster.com/nl/` (not followed) | - |
| 20 | Indeed and LinkedIn forbid automated reading; CBS publishes vacancy tables as open data | CONFIRMED | Indeed and LinkedIn terms read once today for the France check (200, 665,417 and 184,070 bytes; clauses as quoted). CBS: portal search (claim 2), e.g. "Vacatures (openstaande, ontstane en vervulde); overheid en onderwijs", CC BY 4.0 | - |
| 21 | KVK: "Ontvang verschillende, anoniem gemaakte, bedrijfsgegevens van een BV of NV uit het Handelsregister."; "De HVDS (High Value Data Set) bevat geen persoonsgegevens. [...] Dit geldt voor de naam van de onderneming en het KVK-nummer. Van het vestigingsadres zijn alleen de eerste twee cijfers van de postcode onderdeel van de datasets." | CONFIRMED | GET https://www.kvk.nl/producten-bestellen/kvk-handelsregister-open-data-set/ -> 200, text/html, 187,281 bytes ("Bijgewerkt 7 augustus 2025"): both passages word for word | - |
| 22 | The free dataset carries: "Datum aanvang", "Actief", "Insolventie", "Rechtsvorm (BV of NV)", "Postcode regio (eerste twee cijfers)", "SBI-activiteiten", "Hoofdactiviteiten", "Lidstaat"; not supplied: "Het aantal werkzame personen. Het KVK-nummer. Naam van de organisatie. De volledige postcode. [...] Gegevens van eenmanszaken." | CONFIRMED | Same page: the list "Bedrijfsgegevens die je ontvangt" and the answer to "Welke gegevens worden niet geleverd?", word for word | - |
| 23 | Licence: "De HVDS wordt voor hergebruik beschikbaar gesteld onder de voorwaarden van de Creative Commons BY 4.0 licentie (CC BY 4.0)."; "Het is daarbij niet toegestaan om deze HVDS op een zodanige manier te verrijken waardoor de gegevens herleidbaar zijn naar een individueel persoon." | CONFIRMED | Same page, both sentences | - |
| 24 | "Gebruik van de Open Dataset Basis Bedrijfsgegevens is gratis"; "Deze dataset wordt elke werkdag vernieuwd."; bulk zip at `https://www.kvk.nl/download/kvk-open-dataset-basis-bedrijfsgegevens.zip` | CONFIRMED | Same page: both sentences; the link is in the HTML. The zip was not downloaded | - |
| 25 | A keyless API `https://opendata.kvk.nl/api/v1/hvds/basisbedrijfsgegevens/kvknummer/{kvknummer}` answers only for a KVK number one already has; with the documentation's example 12345678 it answers 404 "Op basis van het KVK-nummer 12345678 kan het product niet worden geleverd." | CONFIRMED | GET https://developers.kvk.nl/documentation/open-dataset-basis-bedrijfsgegevens-api -> 200, 82,756 bytes: the endpoint and the example; no word key or authentication. GET of the example -> 404, application/json, 121 bytes, `"code":"IPD0005"` and that message, no key sent | - |
| 26 | Named data is paid: "Om KVK-API's te gebruiken, heb je altijd de API 'Zoeken' nodig. Een abonnement kost €6,40 per maand. Voor sommige API's betaal je daarnaast €0,02 per bevraging."; "Het maken van selecties of zoekopdrachten op kenmerken zoals SBI-code is niet mogelijk."; free testing with fictitious data | CONFIRMED | GET https://www.kvk.nl/producten-bestellen/api/ -> 200, text/html, 185,091 bytes: all three passages ("Je kunt de API's kosteloos testen. Met een kleine set aan fictieve data") | - |
| 27 | KVK's register can be searched free on kvk.nl, one company at a time | UNVERIFIED | Not requested; the product page's menu has "Zoeken in het Handelsregister" | - |
| 28 | Recruitee: keyless JSON per employer, "GET https://{clientname}.recruitee.com/api/offers" (vendor documentation, via a search summary) | CONFIRMED | Read today for the France check: GET https://docs.recruitee.com/reference/offers -> 200, 197,897 bytes: `GET https://{yourcompany}.recruitee.com/api/offers/` "Returns a collection of published company jobs."; the Careers Site API menu also has an "Authentication" page (not read) | The endpoint is documented; that it needs no key is not stated on the page read. |
| 29 | A third-party page claims an authentication change at Recruitee is announced for 2027 | CORRECTED | GET https://www.tellent.com/hubfs/API%20Changes_Offers%20and%20Rate%20Limiting.pdf -> 200, application/pdf, 252,017 bytes (last modified 2026-06-06): "Offers refactor and rate limiting - upcoming changes to the API"; "New rate limit 1000 requests/60 seconds", "Deadline 15th October 2025"; the `/offers` endpoint of the ATS API "with the use of Personal API token" gets pagination and filters | The owner's notice concerns the token-based ATS API and 2025; no 2027 change and nothing on the careers-site endpoint was found. |
| 30 | Homerun: "All API endpoints require Bearer authentication"; an XML feed whose link the employer generates under Settings > Integrations > "Homerun XML" ("Copy feed link") and shares | CONFIRMED | GET https://developers.homerun.co/ -> 200, 607,497 bytes ("Homerun Public API (2.0.0)"): that sentence; "402 Your plan doesn't include Public API feature"; rate limit "60 requests per minute". GET https://help.homerun.co/en/articles/5013627-how-to-generate-an-xml-feed -> 200, 82,259 bytes: the four steps ending in "Copy feed link" | - |
| 31 | Carerix, OTYS, AFAS, Bullhorn Connexys: named from memory, not checked | CORRECTED | Carerix, Connexys and OTYS read today for the Belgium check (claim 41 there). AFAS: GET https://help.afas.nl/help/EN/SE/Ins_Ess_Rcruit_Apply_Out.htm -> 200, 21,219 bytes ("Help Center Nederland"): vacancies and applications on the employer's "OutSite" site; no word feed, XML, API or connector on the page | Carerix: documented XML feed per employer application. Connexys: credentials. OTYS and AFAS: no feed documented on the page read. |
| 32 | Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Personio, Workday: international vendors, documentation in the EU-wide file; not established for the Netherlands | CONFIRMED | One documentation page per vendor read today for the France check (claims 54-61 there) | - |
| 33 | No source says which systems Dutch employers use most | NOT DISPROVED | Not searched | - |
| 34 | No free source gives links to employers' own pages; Nationale Vacaturebank's robots.txt shows adverts can carry an external link (`/vacature/external-url/`) but closes that path | CONFIRMED | robots.txt line "Disallow: /vacature/external-url/" (claim 13). Werken voor Nederland's vacancy pages are the employer's own (sitemap, claim 8) | - |
| 35 | Techleap "Finder": a free database, free account for all results, export in a paid tier | UNVERIFIED | GET https://techleap.nl/blog/discover-the-dutch-tech-ecosystem-with-startup-finder/ -> 308 -> same address without the slash -> 404 (376,168 bytes) | - |
| 36 | No public member list of NLdigital was found | NOT DISPROVED | Not searched | - |
| 37 | The Netherlands has no open feed or dataset of the labour market's vacancies | NOT DISPROVED | The two portal searches (claim 2): statistics only | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (the deciding clause if "no") |
|---|---|---|
| UWV - werk.nl | unclear | No terms read; robots.txt closes only `/webpublicaties`; the vacancy path redirects to UWV's login server. The 2020 note that scraping is possible "in principe" is not a licence |
| UWV Open Match Data | no | Counts only, no adverts (CC BY 4.0) |
| Werken voor Nederland (central government) | yes | "hergebruik van de inhoud van deze site is toegestaan" (CC0); robots.txt admits all agents at "Request-rate: 10/1"; vacancy sitemap of 1,309 pages |
| CSO Vacature API | unclear | Could not be checked today (requests declined); reported gone by the research |
| Nationale Vacaturebank | unclear | Terms not read; robots.txt closes search and apply addresses and shuts out "ClaudeBot" entirely; the every-agent part (search, paging, apply) is listed in `prohibited/` |
| Intermediair | unclear | Terms not read; robots.txt of the same structure, ClaudeBot shut out by name |
| Jobbird | unclear | Terms silent on programs, but copying is forbidden: reproduction or republication needs written permission (listed in `prohibited/`); robots.txt closes `/nl/vacature?*` |
| Werkzoeken.nl | unclear | Could not be read (blocked host) |
| Monsterboard | unclear | Site gone: 301 to monster.com/nl/; terms there not read |
| Indeed | no | Forbidden: "Utiliser un système automatisé (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données" (terms of 1 April 2026, read in French) |
| LinkedIn | no | "Use bots or other unauthorized automated methods to access the Services" |
| CBS vacancy tables | no | Counts only, no adverts |
| KVK - open dataset and its API | yes | Allowed (CC BY 4.0, free, no key) but of no use as a list of employers: no name, no KVK number, no address |
| KVK - APIs with named data | no | Paid: "Een abonnement kost €6,40 per maand. Voor sommige API's betaal je daarnaast €0,02 per bevraging." |
| Employers' boards on Recruitee | unclear | Endpoint documented by the vendor; no licence stated; key requirement not stated on the page read |
| Employers' boards on Carerix | unclear | Vendor documents an XML feed per employer for job sites; no licence stated; needs the application name and a medium code |
| Employers' boards on Homerun, Connexys | no | Key or credentials of the employer: "All API endpoints require Bearer authentication"; Homerun's feed link is not published |
| Techleap Finder | unclear | Not read (its blog page answers 404) |

## Found beyond the research

- **A program can list every central-government vacancy from one file**: the sitemap (claim 8) gives 1,309
  addresses with last-modified times; the address ends in the organisation code and vacancy number
  (e.g. `.../vacatures/jurist-beroep-TOE-2026-1556`). No vacancy page was requested, so fields and the way to
  apply are still unread.
- **Other records on data.overheid.nl** in the search for "vacatures" (not opened): "Diversiteitsstatement in
  organisatiebeschrijving bij vacatureteksten op Werken voor Nederland" (CC0, 2023), "Vactures ABD" (closed
  licence, 2022), "Startersvacatures hoger opgeleiden (Metropoolregio Amsterdam)" (CC BY 4.0, 2022). The record
  "vacatures-overheid" was not among the first 40 of 61 results.
- **Intermediair's robots.txt also names ClaudeBot** ("User-agent: ClaudeBot / Disallow: /"), like Nationale
  Vacaturebank's; a reading program built on Claude is shut out of both by name.
- **Recruitee's owner Tellent** tightened the token-based ATS API in 2025 (1,000 requests per 60 seconds); the
  notice shows the full field set an employer's own integration can read (description, requirements, salary,
  work model), none of it without the employer's token.
- **Homerun's API is a paid-plan feature** ("402 Your plan doesn't include Public API feature") limited to 60
  requests a minute.
- **KVK's developer page** repeats the licence in English: "It is not permitted to enrich this HVDS in such a way
  that the data can be traced back to an individual person."
