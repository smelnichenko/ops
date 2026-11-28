# Belgium (BE) - check of the research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`), no added headers, no
`-L`, every transfer capped (`--max-filesize 2000000 -m 30`), one request at a time. Web search (run by the
search service, not from this address) only to find page addresses. No account, key or login.
Requests per host: www.vdab.be 3, developer.vdab.be 3, www.leforem.be 3, data.europa.eu 4, www.actiris.brussels 2,
www.stepstone.be 2, company.cvwarehouse.com 2, www.otys.com 2, and 1 each to www.odwb.be (429),
economie.fgov.be (CAPTCHA), data.gov.be (CAPTCHA), kbopub.economie.fgov.be (302 to a login), e-justice.europa.eu,
www.vacature.com (301), travaillerpour.be (bot check), www.talent.brussels, www.vlaanderen.be,
opendata.infrabel.be, c.cvwarehouse.com (404), www.cvwarehouse.com (301), intercom.help (301), help.carerix.com,
kb.bullhorn.com, www.otys.nl (301).
No request to jobat.be, adg.be, references.be or extranet.vdab.be (they refused the researcher). Indeed and
LinkedIn were read once today for the France check and not requested again. No employer's board and no vendor
data endpoint was requested. Redirects were followed only to the same publisher's own page and never to a login.

The research file has the section "Through the employers"; it is checked below (claims 31-44).

## Corrections and unverified claims (apply these first)

- UNVERIFIED (blocked): **Le Forem's dataset on odwb.be - its licence (CC BY-SA 4.0), its 26 fields, the `url`
  field and the record count (25,307)**. The one request allowed to odwb.be (`.../records?limit=1`, 17:32 UTC)
  answered **429** again: "You have exceeded the requests limit for anonymous users.", `call_limit` 10000,
  `limit_time_unit` "day", `reset_time` "2026-11-29T00:00:00Z". No record and no metadata were seen by this
  check. Seen elsewhere today: Le Forem's own page (free reuse, free of charge, real time, contacts through the
  Forem's site - claim 9) and the EU portal's copy of the record (publisher, description, 15 export formats,
  "continuous", access "public" - claim 12); the EU copy carries **no licence**.
- ADDITION (claim 11, confirmed): anonymous reading of the dataset failed twice today from this address (the
  researcher's second request and this check's first). For a program this means: read shortly after 00:00 UTC, or
  with a portal account's key (not tested, no account made).
- CORRECTED (claim 6): VDAB's disclaimer is now read (https://www.vdab.be/disclaimer). It allows use by a person:
  "Je mag informatie op onze website kopiëren, afdrukken en gebruiken voor informatieve doeleinden." It has no
  clause on robots or scripts. The vacancy-sharing statement the research took from a search summary is on the
  page: "We delen ze met publieke bemiddelingsdiensten zoals FOREM, Actiris, ADG en Eures. Ook Google for Jobs,
  Jobat en Regiotalent publiceren VDAB-vacatures op hun site. We maken hierover afspraken en leggen die vast in
  een overeenkomst."
- CORRECTED (claim 36): the company register's open file - cycle and status. The national portal's record, as
  copied on data.europa.eu (publisher FPS Economy, modified 2025-01-23): "a complete file: this file contains
  all the active registered entities and business units registered in the CBE [...]; an update file [...] New
  files are available every first Sunday of the month."; frequency "monthly"; licence identifier
  `http://data.gov.be/license/cbe/open`; `is_hvd: false` (not flagged as a high-value dataset there). The "31
  days" was not seen.
- CORRECTED (claim 39): CVWarehouse NV is at Ternesselei 330, 2160 Wommelgem (near Antwerp), per its own site,
  which is "currently down for scheduled maintenance"; its documentation address and its flyer address both
  answer 404 today.
- CORRECTED (claim 41): of the vendors "met in searches" and not examined, three were read on their own pages:
  Carerix documents an XML feed per employer application for job sites
  (`https://application.carerix.com/cxtools/jobboardFeed.php?start=0&count=300&medium=mediumcode`), no key
  mentioned; Bullhorn Connexys' web services need "Username, Password, Security-token"; OTYS's product page
  documents no feed or API. Cegid Talentsoft's APIs are for partners or need a client id and secret (France
  check, claim 46).
- UNVERIFIED (blocked): the company register's own documentation - the open file's layout (which CSVs; whether a
  `contact` file holds telephone, e-mail and web address; no number of employees), the licence text and the
  ban on direct marketing. economie.fgov.be answered a CAPTCHA page, data.gov.be (the licence address) answered
  the same CAPTCHA page, and the download address redirects to a login.
- UNVERIFIED (blocked): ADG (adg.be), Jobat, Références, and VDAB's access guides on extranet.vdab.be (approval
  by VDAB's centre of excellence, client id and secret) - no request made.
- UNVERIFIED: CVWarehouse's "free jobs XML API" and its Jobs API - the flyer address answers 404 and the site is
  in maintenance. Keep the vendor (sourced by name and address), drop the feed statement until read.
- UNVERIFIED: the Forem press figure ("plus de 78.000 offres d'emploi"; seen only as a search result title);
  Actiris's "33,000+" offers and the KBO number on Actiris offers (third-party scraper pages); the EURES count of
  237,924 (EU-wide file); scrapers on apify.com and the feed on AWS Marketplace; Wallonia's cluster member lists -
  none requested.
- UNVERIFIED: when and how Vacature.com was folded into Jobat - only the redirect was seen.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | VDAB developer portal ("API Developer Portal"): products "Vacature 4.1.5 - Vacaturedata opvragen - voor werkgevers", "Vacature 4.2.2 - Vacaturedata met C2 opvragen - voor werkgevers", "Vacature Posting 1.0.3"; "Create a new account and get started with our APIs. It's free to join." | CONFIRMED | GET https://developer.vdab.be/openservices/ -> 200, text/html, 26,180 bytes: all four, word for word; also "Profiel 2.1.2 Profieldata opvragen - voor Federgonleden" | - |
| 2 | API "Vacatures" 4.1.4: "stelt je in staat om continu over actuele gegevens van vacaturedossiers bij VDAB te beschikken [...]"; operations `GET /vacatures`, `POST /vacatures`, `GET /vacatures/bulk`, `GET /vacatures/initial`, `GET /vacatures/{id}` | CONFIRMED | GET https://developer.vdab.be/openservices/product/6468 -> 200, text/html, 37,887 bytes: the text and the five operations; "Download API Specs (zip)"; contact "API CoE" | - |
| 3 | "In order to subscribe, you must sign in."; plan "Developer", "2000 calls per minute", bulk and initial "5 calls per second" | CONFIRMED | Same page, word for word | - |
| 4 | A subscription is granted by VDAB's centre of excellence and gives a client id and secret (access guides on extranet.vdab.be); not self-service in the end | UNVERIFIED | No request made (blocked host). The product page only names "API CoE" as contact | - |
| 5 | The portal's "Terms of use" hold only a generic paragraph | CONFIRMED | GET https://developer.vdab.be/openservices/tsandcs -> 200, 16,208 bytes: "The terms of service that are outlined here are a legal agreement between you and our company [...] Without notification, the terms can be changed at any time." Nothing else | - |
| 6 | VDAB's disclaimer was not read; sharing with Forem, Actiris, ADG, EURES and publication by Google for Jobs, Jobat and Regiotalent known from a search summary | CORRECTED | GET https://www.vdab.be/disclaimer -> 200, text/html, 67,132 bytes: "Je mag informatie op onze website kopiëren, afdrukken en gebruiken voor informatieve doeleinden."; the sharing statement quoted above; no word robot, scrap, crawl or spider | The disclaimer allows copying, printing and use for information, is silent on programs, and states the sharing agreements itself. |
| 7 | robots.txt of www.vdab.be, all agents: "Disallow: /api/vindeenjob/", "/include/vacature/", "/vac/", "/vacatures/", "/zoeken/", "/vindeenjob/prive/", "/mijnvdab/", "/feed$", "/rss.xml$"; Baiduspider shut out; sitemap `https://www.vdab.be/sitemap/vindeenjob/vacatures/index.xml` | CONFIRMED | GET https://www.vdab.be/robots.txt -> 200, text/plain, 3,564 bytes: every Disallow line, ahead of the Baiduspider group; six `Sitemap:` lines. The check did not record the User-agent line the Disallow lines stand under | The lines are there; that they apply to all agents rests on the research. |
| 8 | A VDAB vacancy page comes back as an application shell (46,710 bytes, no advert text, no JSON-LD) | CONFIRMED | GET https://www.vdab.be/vindeenjob/vacatures/74660948/storingstechnieker-2-ploegen -> 200, text/html, 46,710 bytes: site navigation and `<app-root>`; no `application/ld+json`; the job title is not in the HTML | - |
| 9 | Le Forem's page: "Cette base de données permet à tout utilisateur d'ouvrir et de réutiliser les données disponibles en toute liberté."; "Ces données sont gratuites et mises à jour en temps réel"; "Le contenu "offres d'emploi" est donné à titre informatif. Les contacts et sollicitations se font via le site du Forem."; "Bien que les données disponibles restent la propriété du Forem [...]" | CONFIRMED | GET https://www.leforem.be/open-data.html -> 200, text/html, 151,560 bytes: all four, word for word; "le Forem met l'ensemble des offres d'emploi qu'il diffuse à disposition en Open Data sur le site odwb"; links to `https://www.odwb.be/explore/dataset/offres-d-emploi-forem/information` and `.../table/?sort=-numerooffreforem`. The page names no licence and no key | - |
| 10 | Le Forem's dataset on odwb.be: licence "CC BY-SA 4.0"; readable by API without a key; 26 fields with `nomemployeur`, `source`, `referenceexterne`, `url` ("Lien redirigeant vers l'offre sur le site du Forem"); no description text, salary or contact; 25,307 records; `update_frequency: CONT` | UNVERIFIED | Blocked: the one request to odwb.be answered 429 (claim 11). Not contradicted by what was seen: the field name `numerooffreforem` is in the Forem's own link; the EU copy says "continuous" and "public" | - |
| 11 | The records endpoint answered 429: "You have exceeded the requests limit for anonymous users.", `call_limit` 10000, `limit_time_unit` "day", reset 2026-11-29T00:00:00Z | CONFIRMED | GET `https://www.odwb.be/api/explore/v2.1/catalog/datasets/offres-d-emploi-forem/records?limit=1` -> 429, application/json, 187 bytes, at 17:32:49 GMT: the same body, `errorcode` 10005. Host not asked again | - |
| 12 | data.europa.eu lists the dataset ("Vacatures Forem", catalogue data-gov-be, modified 2026-11-17); the description says VDAB offers are exposed only when translated into French | CONFIRMED | GET https://data.europa.eu/api/hub/search/datasets/https-www-odwb-be-explore-dataset-offres-d-emploi-forem- -> 200, 45,091 bytes: titles "Offres d'emploi Forem" / "Vacatures Forem", publisher FOREM, catalogue data-gov-be, modified 2026-11-17T15:24:51, frequency "continuous", access right "public", contact opendata@forem.be, 15 distributions (CSV, JSON, JSONL, Parquet, XLSX ...) at `.../exports/<format>`; "In the case of offers from the VDAB, only offers translated into French are exposed"; `license` empty on every distribution | - |
| 13 | Le Forem's site terms list "un service de recherche et de consultation en ligne d'offres d'emploi", "un service de candidatures en ligne", PDF download of search results in the mobile application, online application for an authenticated user | CONFIRMED | GET https://www.leforem.be/conditions-d-utilisation.html -> 200, text/html, 167,237 bytes: all four passages | - |
| 14 | Le Forem's site terms have no clause on robots, scripts or extraction | NOT DISPROVED | Same page searched for robot, automatis, extraction, aspir, scrap, moissonn, logiciel, interdit: no hit | - |
| 15 | Le Forem's partner APIs ("Utilisation des APIs - Décembre 2023"): for entities that asked to publish offers and received access codes; "échanger de manière automatique des offres d'emploi [...] depuis le site Internet du Forem vers le site Internet de l'Utilisateur ou inversement"; not for an individual | CONFIRMED | GET https://www.leforem.be/partenaires/cgu-apis.html -> 200, 157,007 bytes: "Mise à jour le 12 décembre 2023"; "« Utilisateur » : toute entité Belge enregistrée auprès de la Banque-carrefour des entreprises, ou entité étrangère, qui a introduit une demande d'utilisation des APIs du Forem pour publier [...] et qui a reçu, de la part du Forem, des codes pour accéder aux APIs"; the definition of « API » word for word. No statement of cost on the page | - |
| 16 | Actiris legal notice: "L'utilisation des informations présentes sur les sites est autorisée à condition d'en citer la source."; data may not be used "à d'autres fins que celles pour lesquelles elles sont mises en ligne, à savoir l'offre et la recherche d'un emploi" | CONFIRMED | GET https://www.actiris.brussels/fr/citoyens/mentions-legales/ -> 200, text/html, 97,808 bytes: both sentences; no word robot, automatis, extraction, scrap or logiciel | - |
| 17 | Actiris has no robots.txt (404, the site's "Page404", 86,980 bytes) | CONFIRMED | GET https://www.actiris.brussels/robots.txt -> 404, text/html, 86,980 bytes, title beginning "Page404" | - |
| 18 | Actiris is web-only: no open dataset or documented API | NOT DISPROVED | EU portal search for Belgium (claim 23): nothing from Actiris. A web search found only third-party scrapers | - |
| 19 | ADG: robots.txt content; the home page answered 403 (Cloudflare challenge) | UNVERIFIED | No request made (blocked host) | - |
| 20 | travaillerpour.be answers a JavaScript bot check instead of its robots.txt | CONFIRMED | GET https://travaillerpour.be/robots.txt -> 200, text/html, 50,228 bytes: a script page (`bobcmn`, `TSPD`), no robots rules. Not asked again | - |
| 21 | talent.brussels' robots.txt is the stock Drupal file (2,141 bytes) | CONFIRMED | GET https://www.talent.brussels/robots.txt -> 200, text/plain, 2,141 bytes, the Drupal header comment | - |
| 22 | The Flemish government's vacancies page is a shell with a search box and no vacancy in the HTML (60,861 bytes) | CONFIRMED | GET https://www.vlaanderen.be/werken-voor-vlaanderen/vacatures -> 200, text/html, 60,861 bytes: "Bezig met laden...", no vacancy titles | - |
| 23 | data.europa.eu, Belgium: besides Le Forem's dataset only "Open vacatures bij Infrabel" (modified 2023-10-20) and statistics; nothing from VDAB, Actiris or ADG | CONFIRMED | GET `https://data.europa.eu/api/hub/search/search?q=vacatures offres d'emploi jobs&filter=dataset&facets={"country":["be"]}&limit=25` -> 200, 104,389 bytes, 25 of 676 read: Forem; Infrabel (twice, catalogues data-gov-be and geoportal-be, 2023-10-20); Statbel and IWEPS statistics | - |
| 24 | No feed, API or dataset of the federal or regional public-sector job portals | NOT DISPROVED | Not searched beyond the EU portal query above | - |
| 25 | StepStone Belgium terms: "The Services under these Terms of Use are intended only for the individual job search by natural persons as an employee or as a freelancer."; the user shall not "use scraping or similar techniques, to collect content to use it for another purpose, to publish it again or use it in a different way than what the Services are intended for"; applications stored on Stepstone or sent to the customer's "application management system" | CONFIRMED | GET https://www.stepstone.be/about-us/terms-of-use/ -> 200, text/html, 118,235 bytes: all three passages | - |
| 26 | StepStone robots.txt opens with "Any other use of robots or failure to obey the robots exclusion standards [...] is strictly prohibited." and disallows "/?*", "/*?*", "/5/resultlistpage", "/5/jobapply", "/public-api/v1/job-applications/", "/jobagent/", "/widget/" | CONFIRMED | GET https://www.stepstone.be/robots.txt -> 200, text/plain, 2,897 bytes: the comment and every line | - |
| 27 | Jobat's robots.txt and 403; Références' 403 | UNVERIFIED | No request made (blocked hosts) | - |
| 28 | Vacature.com points to Jobat | CONFIRMED | GET https://www.vacature.com/robots.txt -> 301, `location: https://www.jobat.be/nl/vacature` (not followed) | - |
| 29 | Indeed's terms of 1 April 2026 and LinkedIn's User Agreement of 3 November 2025 forbid automated reading | CONFIRMED | Read once today for the France check: GET https://fr.indeed.com/legal -> 200, 665,417 bytes; GET https://www.linkedin.com/legal/user-agreement -> 200, 184,070 bytes; clauses as quoted. be.indeed.com not requested | - |
| 30 | Statbel's vacancy tables are on data.gov.be (aggregates) | CONFIRMED | EU portal search (claim 23): "Emplois vacants" and "Les emplois salariés vacants en Belgique", catalogue data-gov-be, Statbel. Licence not checked: statistics | - |
| 31 | The register (KBO/BCE) is national, "managed by an office in the Federal Department of the Economy"; "The database covers all enterprises, and the law requires all enterprises to register" | CONFIRMED | GET https://e-justice.europa.eu/topics/registers-business-insolvency-land/business-registers-eu-countries/be_en -> 200, text/html, 68,586 bytes: both sentences | - |
| 32 | The Public Search shows, per enterprise: registration number, status, legal situation, start date, name, address of head office, telephone number, fax, email, website, legal form, number of establishments, officers, activities, financial information, links | CONFIRMED | Same page, the list word for word | - |
| 33 | "An 'Open Data' file is also available free of charge: this can be reused by any interested person provided they register."; the web service for one's own applications "is provided for a fee" | CONFIRMED | Same page, both sentences. This is the e-Justice portal's wording, not the register's own page | - |
| 34 | The open-data address redirects to a login; the FPS Economy page answers a CAPTCHA | CONFIRMED | GET https://kbopub.economie.fgov.be/kbo-open-data -> 302, `Location: .../kbo-open-data/login` (not followed). GET https://economie.fgov.be/en/themes/enterprises/crossroads-bank-enterprises/services-everyone/public-data-available-reuse/cbe-open-data -> 200, 47,048 bytes: "This question is for testing whether you are a human visitor"; host not asked again | - |
| 35 | The open file is a set of CSVs in which `contact` holds telephone, e-mail and web address, and it has no number of employees (from memory) | UNVERIFIED | Blocked: the register's documentation could not be read (CAPTCHA, login) | - |
| 36 | Full and update files are published and stay available 31 days; whether the file is a high-value dataset was not established | CORRECTED | GET https://data.europa.eu/api/hub/search/datasets/fpseco-cbeopen-download -> 200, 26,550 bytes ("CBE - Open data", catalogue data-gov-be, publisher FPS Economy, modified 2025-01-23): the description quoted above, frequency "monthly", two CSV distributions ("full file", "file containing the changes") with licence `http://data.gov.be/license/cbe/open`, `is_hvd: false`, access right "public" | Monthly: a full file of active entities and establishment units and an update file, new "every first Sunday of the month"; not flagged as a high-value dataset on the EU portal. "31 days" not seen. |
| 37 | The licence is one of the FPS's own, with a ban on reusing personal data for direct marketing (third parties) | UNVERIFIED | Licence identifier seen (`http://data.gov.be/license/cbe/open`); GET https://data.gov.be/license/cbe/open -> 200, 45,752 bytes, a CAPTCHA page; host not asked again | - |
| 38 | There is no free keyless API of the register | NOT DISPROVED | Not searched further; the EU portal lists only the files and, in other catalogues, "Banque Carrefour des Entreprises (CBE)" and the Flemish copy "VKBO" (not opened) | - |
| 39 | CVWarehouse: Belgian (Antwerp); documentation at https://c.cvwarehouse.com/en/documentation answers 404; a "free jobs XML API" is advertised in flyers | CORRECTED | GET https://c.cvwarehouse.com/en/documentation -> 404, 103 bytes. GET https://company.cvwarehouse.com/downloads/Flyers/EN_CVWarehouse_Jobsite_Options.pdf -> 404. www.cvwarehouse.com -> 301 -> GET https://company.cvwarehouse.com/ -> 200, 12,985 bytes: "This website is currently down for scheduled maintenance"; "CVWarehouse NV, Ternesselei 330, 2160 Wommelgem, Belgium"; no word API, feed or XML | Belgian vendor confirmed (Wommelgem). Its feed statements could not be read today. |
| 40 | Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Recruitee, Personio, Workday: international vendors, documentation in the EU-wide file; not established for Belgium | CONFIRMED | One documentation page per vendor read today for the France check (claims 54-61 there): keyless reading documented by Teamtailor, Greenhouse, Lever, Workable, Personio; SmartRecruiters and Recruitee document the endpoint without saying that no key is needed; Workday's product page documents no feed. Use in Belgium: no source | - |
| 41 | Cegid Talentsoft, Otys, Carerix, Bullhorn Connexys were met in searches and not examined | CORRECTED | Carerix: intercom.help -> 301 -> GET https://help.carerix.com/en/articles/2398236-publish-job-orders-on-job-sites -> 200, 109,481 bytes: "You find the feed using the following url: [applicationname].carerix.com/cxtools/", `jobboardFeed.php?start=0&count=300&medium=mediumcode`, no key mentioned. Connexys: GET https://kb.bullhorn.com/connexys/Content/Topics/English/WebservicesforConnexysResourceManager.html -> 200, 70,994 bytes: "To use the web services, a session-id is necessary [...] Username, Password, Security-token". OTYS: www.otys.nl -> 301 -> GET https://www.otys.com/nl/ -> 200, 806,827 bytes: product page ("OTYS is part of Mysolution", Houten), no word API, feed or XML | Carerix: XML feed per employer application, documented, no key mentioned. Connexys: credentials. OTYS: nothing documented on the page read. Cegid: partners or token. |
| 42 | Le Forem's dataset names the employer and the offer's origin, but its only link goes to the Forem's page, not to the employer | UNVERIFIED | No record or field list seen (429). The Forem's page says "Les contacts et sollicitations se font via le site du Forem" | - |
| 43 | The register shows a website and e-mail per enterprise where declared (Public Search); whether the open file carries them is unconfirmed | CONFIRMED | e-Justice page: "telephone number, fax, email, website" at enterprise and establishment level in the Public Search. The open file's columns: not read (claim 35) | - |
| 44 | Agoria has no public member directory that a search found; no employer directory verified | NOT DISPROVED | Not searched | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (the deciding clause if "no") |
|---|---|---|
| Le Forem - open dataset "Offres d'emploi Forem" (odwb.be) | yes | Le Forem: "permet à tout utilisateur d'ouvrir et de réutiliser les données disponibles en toute liberté", "gratuites". Licence name not seen today; anonymous quota was spent on both tries (429) |
| Le Forem - site | unclear | Terms silent on programs; they list search, consultation and online application as services |
| Le Forem - partner APIs | no | Partners only: "toute entité [...] qui a introduit une demande d'utilisation des APIs du Forem pour publier [...] et qui a reçu, de la part du Forem, des codes" |
| VDAB - site ("Vind een job") | unclear | Disclaimer allows copying and use "voor informatieve doeleinden", silent on programs; robots.txt has "Disallow: /api/vindeenjob/"; pages are script-rendered |
| VDAB - vacancy API | no | "voor werkgevers", by account and subscription: "In order to subscribe, you must sign in." |
| Actiris - site | unclear | Use allowed for "l'offre et la recherche d'un emploi" with the source cited; silent on programs; no robots.txt |
| ADG | unclear | Could not be read (blocked host) |
| travaillerpour.be / werkenvoor.be (federal) | unclear | Bot check instead of pages; terms not read |
| Werken voor Vlaanderen | unclear | Terms not read; list filled by script |
| talent.brussels | unclear | Terms not read |
| Infrabel open dataset | yes | Licence "Open licentie CC0 - Universeel", keyless metadata read; one employer, 185 vacancies, titles and places only |
| StepStone Belgium | unclear | "intended only for the individual job search by natural persons"; scraping banned only "to use it for another purpose"; robots.txt closes the result lists and search pages for every agent (that part is listed in `prohibited/`) |
| Jobat (with Vacature.com) | unclear | Could not be read (blocked host) |
| Références | unclear | Could not be read (blocked host) |
| Indeed | no | Forbidden: "Utiliser un système automatisé (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données" |
| LinkedIn | no | "Use bots or other unauthorized automated methods to access the Services" |
| Statbel vacancy tables | no | Counts only, no adverts |
| KBO/BCE - open data file | unclear | Free after registration per the e-Justice portal ("can be reused by any interested person provided they register"); the register's own licence text could not be read |
| KBO/BCE - Public Search (one company at a time) | unclear | Terms not read; shows website and e-mail where declared |
| KBO/BCE - web service | no | Paid: "this latter service is provided for a fee" |
| Employers' boards on Carerix | unclear | Vendor documents an XML feed per employer for job sites; no licence stated; needs the employer's application name and a medium code |
| Employers' boards on Connexys, Cegid Talentsoft | no | Credentials of the employer or a partner needed ("Username, Password, Security-token") |

## Found beyond the research

- **Infrabel's dataset is alive**: GET https://opendata.infrabel.be/api/explore/v2.1/catalog/datasets/joblistinfrabel
  -> 200, 15,759 bytes: "Open vacatures bij Infrabel", licence "Open licentie CC0 - Universeel", 185 records,
  data processed 2026-11-27T23:01 ("Deze worden dagelijks bijgewerkt"); the 2023-10-20 date is the metadata's.
  Fields: `job_title_fr`, `job_title_nl`, `publication_language`, `department_*`, `publication_start_date`,
  `location_sap`, `zipcodes`, `provincie`, geometry. No description text and no link field by name.
- **The Forem dataset's anonymous quota** (10,000 calls a day, reset at 00:00 UTC) was exhausted at both
  attempts today, so "readable without a key" holds only for part of the day.
- **Le Forem** has two more pages on the subject, found by search and not requested (three requests used):
  `https://www.leforem.be/articles/open-data-offres-emploi.html` and `https://www.leforem.be/partenaires/api.html`.
- **The company register on the EU portal**: two records from FPS Economy, "Banque-Carrefour des Entreprises -
  Open Data" (`fpseco-cbeopen-download`) and "Fichier complet des données publiques réutilisables"
  (`fpseco-cbefull-download`, not opened), both modified 2025-01-23; and a Flemish copy, "VKBO" (Agentschap
  Digitaal Vlaanderen; active legal persons with an address in Flanders, per a search summary; not opened).
- **data.gov.be is behind the same CAPTCHA as economie.fgov.be** for this client, so the national portal cannot
  be searched by a program from this address.
- **Carerix** (used by staffing firms in Belgium and the Netherlands; use not established) documents per-employer
  XML feeds at `{application}.carerix.com/cxtools/` - a possible employer-route feed where the application name
  and medium code are known.
