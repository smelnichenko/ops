# Belgium (BE) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL), and web search for finding pages. No account, key or login was used. Requests made, per
host: www.vdab.be 3, developer.vdab.be 3, www.leforem.be 3, www.actiris.brussels 3, www.odwb.be 2 (the second
answered 429), adg.be 2 (the second answered 403), www.stepstone.be 2, www.jobat.be 2 (the second answered
403), and 1 each to www.adg.be, extranet.vdab.be (403), www.vacature.com, www.references.be (403),
travaillerpour.be (bot challenge), www.talent.brussels, www.vlaanderen.be, kbopub.economie.fgov.be (login
redirect), economie.fgov.be (CAPTCHA), e-justice.europa.eu, c.cvwarehouse.com (404), data.europa.eu. Indeed and
LinkedIn were not requested again: their terms were read once for the France file of this pass.

## Takeaway

No single source covers the whole country: the public employment service is regional (VDAB in Flanders, Le
Forem in Wallonia, Actiris in Brussels, ADG in the German-speaking community), and the four exchange vacancies
among themselves only in part. The best free source is Le Forem's open dataset "Offres d'emploi Forem" on the
Wallonia-Brussels open data portal: every offer the Forem distributes, 25,307 records today, CC BY-SA 4.0,
readable by API without a key - a summary per offer (title, employer, place, contract, dates) with a link to
the offer on the Forem's site, where the text and the way to apply are. Its records endpoint answered 429 today
("exceeded the requests limit for anonymous users"), so only the metadata was read. VDAB, by far the largest
(Belgium has 237,924 vacancies on EURES), has a vacancy API on its developer portal, but it is labelled "voor
werkgevers", needs an account and a subscription, and its public pages are script-rendered with
`/api/vindeenjob/` closed in robots.txt. Actiris is web-only with terms that allow use "à condition d'en citer
la source" for job search; ADG and the federal job portal refused the client. Of the commercial boards only
StepStone's terms could be read (individual job search only; scraping for other purposes forbidden); Jobat and
Références answered 403. The company register (KBO/BCE) is national and its open file is free but only after
registration - nothing in it could be verified today.

## Sources

### VDAB (Flanders) - Vlaamse Dienst voor Arbeidsbemiddeling en Beroepsopleiding, "Vind een job"
- Publisher: VDAB, the Flemish public employment service.
- Documentation: developer portal https://developer.vdab.be/openservices/ ("API Developer Portal"); product
  page https://developer.vdab.be/openservices/product/6468 ; access guides on extranet.vdab.be (PDF, refused).
- Data or endpoint: web https://www.vdab.be/vindeenjob/vacatures ; API "Vacatures" 4.1.4 behind the portal's
  gateway (address not public; operations `GET /vacatures`, `POST /vacatures`, `GET /vacatures/bulk`,
  `GET /vacatures/initial`, `GET /vacatures/{id}`).
- Holds: VDAB's vacancy files. The API product "Vacature 4.1.5" is summarised "Vacaturedata opvragen - voor
  werkgevers"; a second one, "Vacature 4.2.2", "Vacaturedata met C2 opvragen - voor werkgevers"; "Vacature
  Posting 1.0.3" is for posting. The API text: "Deze api van het vacatureproduct stelt je in staat om continu
  over actuele gegevens van vacaturedossiers bij VDAB te beschikken. Naast het initieel ophalen van
  vacaturedossierreferenties, laat de api je toe om interactief te zoeken naar deze, alle bestaande informatie
  van één of meer specifieke vacaturedossiers op te vragen of je vacaturedossiers in bulk te synchroniseren."
  Fields not read (the specification needs a login).
- Access: web pages (script-rendered); API by subscription. No open-data dump, no RSS (robots.txt disallows
  `/feed$` and `/rss.xml$`).
- Registration or key: the portal says "Create a new account and get started with our APIs. It's free to join."
  and "In order to subscribe, you must sign in."; plan "Developer", "2000 calls per minute" (bulk and initial
  operations "5 calls per second"). Per VDAB's access guides (search summaries of the PDFs, 2022-2025), a
  subscription to an API product is granted by VDAB's Center of Excellence and gives a client id and secret. Not
  self-service in the end, and aimed at employers and partners. No account was created.
- Cost: free.
- Licence or terms (exact wording, with URL): the portal's "Terms of use" page
  (https://developer.vdab.be/openservices/tsandcs) holds only a generic paragraph ("The terms of service that
  are outlined here are a legal agreement between you and our company [...]"). The site's disclaimer was not
  read (see Seen). robots.txt (https://www.vdab.be/robots.txt), all agents, among others: "Disallow:
  /api/vindeenjob/", "Disallow: /include/vacature/", "Disallow: /vac/", "Disallow: /vacatures/", "Disallow:
  /zoeken/", "Disallow: /vindeenjob/prive/", "Disallow: /mijnvdab/"; Baiduspider is shut out; sitemaps listed
  include `https://www.vdab.be/sitemap/vindeenjob/vacatures/index.xml`.
- For a personal job search: job-seeker use allowed in practice (the public service's job search; terms not
  read); automated reading - not stated in any terms read, robots.txt closes the site's own search interface
  (`/api/vindeenjob/`) but not the vacancy pages (`/vindeenjob/vacatures/...`) or their sitemap; private copy not
  stated.
- How to apply: not established - the vacancy page requested came back as an empty application shell.
- Volume: not read from VDAB. On EURES 237,924 vacancies had a workplace in Belgium on 2026-11-28 (this study's
  EU-wide file); the split by region is not known.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 3,564 bytes; GET /disclaimer.shtml -> 301 to
  /disclaimer (not followed); GET /vindeenjob/vacatures/74660948/storingstechnieker-2-ploegen -> 200, text/html,
  46,710 bytes (navigation only, no advert text, no JSON-LD). Developer portal: home -> 200, 26,180 bytes;
  product 6468 -> 200, 37,887 bytes; terms -> 200, 16,208 bytes. GET of the access guide PDF on
  extranet.vdab.be -> 403 (an HTML page; host not asked again).
- Caveats: whether the "voor werkgevers" API gives an employer only its own files or all published vacancies is
  not clear from the pages read. Per a search summary of VDAB's disclaimer, VDAB shares vacancies with Forem,
  Actiris, ADG and EURES, and Google for Jobs, Jobat and Regiotalent publish VDAB vacancies under agreements.
  Third parties sell scrapers of vdab.be on apify.com.

### Le Forem (Wallonia) - open dataset "Offres d'emploi Forem"
- Publisher: Le Forem (Office wallon de la Formation professionnelle et de l'Emploi), the Walloon public
  employment service; contact opendata@forem.be.
- Documentation: https://www.leforem.be/open-data.html ; dataset page
  https://www.odwb.be/explore/dataset/offres-d-emploi-forem/information
- Data or endpoint: `https://www.odwb.be/api/explore/v2.1/catalog/datasets/offres-d-emploi-forem` (metadata),
  `.../records` and `.../exports/{csv,json}` (Opendatasoft Explore API v2.1).
- Holds: "un résumé des offres d'emploi publiées sur le site du Forem", created by employers or received "de
  partenaires tels que des sociétés d'intérim ou d'autres services régionaux de l'emploi via des flux
  informatiques. Dans le cas des offres issues du VDAB, seules les offres traduites en français sont exposées".
  26 fields: `numerooffreforem`, `titreoffre`, `nomemployeur`, `lieuxtravaillocalite`, `lieuxtravailregion`,
  `lieuxtravailcodepostal`, `lieuxtravailregionnuts`, `lieuxtravailgeo`, `typecontrat`, `regimetravail`,
  `nombrepostes`, `niveauxetudes` (+ ISCED), `langues` (+ ISO codes), `experiencerequise`, `permisdeconduire`,
  `secteurs` (+ NACE code), `source` ("Provenance de l'offre"), `referenceexterne`, `url` ("Lien redirigeant
  vers l'offre sur le site du Forem"), `datedebutdiffusion`, `datefindiffusion`, `metier` (+ DIMECO code). No
  description text, no salary, no contact.
- Access: API and bulk exports.
- Registration or key: none stated; anonymous calls are under a daily quota (see Seen).
- Cost: free ("Ces données sont gratuites et mises à jour en temps réel").
- Licence or terms (exact wording, with URL): dataset metadata: "license": "CC BY-SA 4.0"
  (https://creativecommons.org/licenses/by-sa/4.0/deed.fr). The Forem's page: "Cette base de données permet à
  tout utilisateur d'ouvrir et de réutiliser les données disponibles en toute liberté." and "Le contenu "offres
  d'emploi" est donné à titre informatif. Les contacts et sollicitations se font via le site du Forem." and
  "Bien que les données disponibles restent la propriété du Forem, toute utilisation ou réutilisation des
  données qui reprendrait des informations incorrectes ne pourrait engager la responsabilité du Forem".
- For a personal job search: job-seeker use allowed (free reuse); automated reading allowed (an open-data API);
  private copy allowed (CC BY-SA 4.0: share-alike and attribution bind only what is passed on).
- How to apply: not from the record - "Les contacts et sollicitations se font via le site du Forem"; the `url`
  field leads to the offer there. Per the site's terms an authenticated user can "postuler en ligne aux offres
  d'emploi qui acceptent ce mode de candidature".
- Volume: 25,307 records (`records_count`; data processed 2026-11-28 01:50 UTC). A Forem press item speaks of
  "plus de 78.000 offres d'emploi" in Wallonia (search result title; date and counting unit not checked).
- Update cycle: continuous (`update_frequency: CONT`).
- Seen on 2026-11-28: GET of the Forem page -> 200, text/html, 151,560 bytes; GET of the dataset metadata -> 200,
  application/json, 33,238 bytes (headers `x-ratelimit-limit: 20000`, `x-ratelimit-remaining: 19999`); GET
  `.../records?limit=1` three seconds later -> **429**, application/json, 187 bytes: "You have exceeded the
  requests limit for anonymous users.", "call_limit": 10000, "limit_time_unit": "day", "reset_time":
  "2026-11-29T00:00:00Z". The host was not asked again, so no record was seen.
- Caveats: the 429 came on this client's second request of the day, so the anonymous quota is shared or was
  spent by others; a portal account's API key (not requested) would have its own quota. On data.europa.eu:
  "Vacatures Forem", https://data.europa.eu/data/datasets/https-www-odwb-be-explore-dataset-offres-d-emploi-forem-
  (catalogue data-gov-be, modified 2026-11-17).

### Le Forem - site and partner APIs
- Publisher: Le Forem.
- Documentation: site terms https://www.leforem.be/conditions-d-utilisation.html ; API conditions
  https://www.leforem.be/partenaires/cgu-apis.html ("Utilisation des APIs - Décembre 2023").
- Data or endpoint: https://www.leforem.be/citoyens/offres-emploi.html (search); partner APIs (addresses given
  with the access codes).
- Holds: the offers with their full text. Partner APIs: "la solution informatique mise à disposition des
  Utilisateurs par le Forem pour échanger de manière automatique des offres d'emploi, que ce soit depuis le site
  Internet du Forem vers le site Internet de l'Utilisateur ou inversement".
- Access: web; APIs for approved users only.
- Registration or key: API users are entities that "a introduit une demande d'utilisation des APIs du Forem
  pour publier, sur le site Internet du Forem, des offres d'emploi [...] et qui a reçu, de la part du Forem, des
  codes pour accéder aux APIs". Not for an individual.
- Cost: free.
- Licence or terms (exact wording, with URL): the site terms list among the services "un service de recherche et
  de consultation en ligne d'offres d'emploi", "un service de candidatures en ligne"; the mobile application lets
  the user "télécharger des offres d'emploi résultant de ses recherches dans un format PDF lui permettant de les
  conserver dans un document externe". No clause on robots, scripts or extraction was found in the page.
- For a personal job search: job-seeker use allowed; automated reading not stated in the site terms (robots.txt
  not requested); private copy allowed for one's search results (PDF download is a stated service).
- How to apply: online through the Forem for offers that accept it (authenticated user), otherwise as the offer
  says; not examined on an offer.
- Volume: as above. Update cycle: continuous.
- Seen on 2026-11-28: GET of the site terms -> 200, text/html, 167,237 bytes; GET of the API conditions -> 200,
  157,007 bytes.
- Caveats: three requests to the host used; robots.txt and an offer page were not read.

### Actiris (Brussels)
- Publisher: Actiris, the Brussels regional employment office.
- Documentation: legal notice https://www.actiris.brussels/fr/citoyens/mentions-legales/
- Data or endpoint: https://www.actiris.brussels/fr/citoyens/offres-d-emploi/ (not requested).
- Holds: job offers for Brussels; not examined. Third-party scraper descriptions on apify.com say the site holds
  "33,000+" offers and mixes Actiris's own offers with offers shared by VDAB and Forem.
- Access: web only; no open dataset or documented API was found (one search; none among the Belgian datasets
  returned by data.europa.eu).
- Registration or key: none to browse; "My Actiris" account for services.
- Cost: free.
- Licence or terms (exact wording, with URL): "Les droits de propriété intellectuelle relatifs aux présents sites
  appartiennent exclusivement à Actiris. L'utilisation des informations présentes sur les sites est autorisée à
  condition d'en citer la source." and "Les données contenues sur ce site ne peuvent être utilisées par des
  employeurs et les chercheurs d'emploi à d'autres fins que celles pour lesquelles elles sont mises en ligne, à
  savoir l'offre et la recherche d'un emploi." There is no robots.txt (404).
- For a personal job search: job-seeker use allowed (quoted: use for "la recherche d'un emploi"); automated
  reading not stated (no clause, no robots.txt); private copy not stated (use allowed with the source cited).
- How to apply: not examined.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 404 (the site's "Page404", 86,980 bytes); GET /fr/citoyens/ -> 200,
  103,328 bytes; GET of the legal notice -> 200, 97,808 bytes.
- Caveats: the offers page itself was not read (three requests used).

### ADG (German-speaking community) - Arbeitsamt der Deutschsprachigen Gemeinschaft
- Publisher: Arbeitsamt der Deutschsprachigen Gemeinschaft Belgiens.
- Documentation: none read.
- Data or endpoint: https://adg.be (www.adg.be redirects there).
- Holds: job offers for East Belgium; not examined.
- Access: web only as far as known; refused to this client.
- Registration or key: not known. Cost: free.
- Licence or terms (exact wording, with URL): not read. robots.txt (https://adg.be/robots.txt), whole file:
  "User-agent: * Disallow: /addons/ Disallow: /sitemanager/ Disallow: /*/usetemplate-print".
- For a personal job search: job-seeker use not stated (nothing read); automated reading refused in practice
  (bot challenge); private copy not stated.
- How to apply: not examined.
- Volume: not read. Update cycle: not read.
- Seen on 2026-11-28: GET https://www.adg.be/robots.txt -> 302 to https://adg.be/robots.txt -> 200, text/plain,
  90 bytes; GET https://adg.be/ -> **403**, a Cloudflare page "Just a moment..." (`cf-mitigated: challenge`).
  The host was not asked again.
- Caveats: the smallest of the four services; nothing about its vacancy pages is confirmed.

### Federal and regional public-sector job portals
- Publisher: FPS BOSA (federal: travaillerpour.be / werkenvoor.be, formerly Selor); Flemish government
  ("Werken voor Vlaanderen"); talent.brussels (Brussels regional civil service).
- Documentation: none found for a feed, API or dataset (one search).
- Data or endpoint: https://travaillerpour.be ; https://www.vlaanderen.be/werken-voor-vlaanderen/vacatures ;
  https://www.talent.brussels
- Holds: civil-service vacancies; not examined.
- Access: web only as far as found.
- Registration or key: none to browse. Cost: free.
- Licence or terms (exact wording, with URL): not read. talent.brussels' robots.txt is the stock Drupal file
  (closes `/core/`, `/profiles/`, admin and user paths).
- For a personal job search: job-seeker use not stated (terms not read); automated reading - the federal portal
  answered a script challenge instead of its robots.txt; private copy not stated.
- How to apply: not examined.
- Volume: not read. Update cycle: not read.
- Seen on 2026-11-28: GET https://travaillerpour.be/robots.txt -> 200, text/html, 52,941 bytes: not a robots
  file but a JavaScript bot-check page (`TSPD` script); the host was not asked again. GET
  https://www.talent.brussels/robots.txt -> 200, 2,141 bytes. GET of the Flemish vacancies page -> 200, 60,861
  bytes, a page shell with a search box and no vacancy in the HTML.
- Caveats: a Walloon public-service portal was not looked for.

### Open datasets of vacancies (data.gov.be / data.europa.eu)
- Publisher: various. One search on data.europa.eu limited to Belgium returned, besides Le Forem's dataset, "Open
  vacatures bij Infrabel" (the rail infrastructure company's own vacancies, opendata.infrabel.be, modified
  2023-10-20; not requested) and statistics tables. No dataset from VDAB, Actiris or ADG.
- Seen on 2026-11-28: GET of the search API -> 200, application/json, 944,160 bytes, 15 results read of 801
  matches.
- For a personal job search / How to apply: see Le Forem above; the Infrabel dataset was not examined.

### StepStone Belgium
- Publisher: Stepstone NV/SA (The Stepstone Group).
- Documentation: https://www.stepstone.be/about-us/terms-of-use/
- Data or endpoint: https://www.stepstone.be ; no feed or API for reading adverts is offered.
- Holds: adverts of paying recruiters. Not examined.
- Access: web only.
- Registration or key: none to browse; an account to apply through the platform.
- Cost: free for candidates.
- Licence or terms (exact wording, with URL): "The Services under these Terms of Use are intended only for the
  individual job search by natural persons as an employee or as a freelancer. Otherwise, it is not permitted to
  use the Services offered by us in a commercial way". The user shall not "use scraping or similar techniques, to
  collect content to use it for another purpose, to publish it again or use it in a different way than what the
  Services are intended for". robots.txt (https://www.stepstone.be/robots.txt) opens with "Any other use of
  robots or failure to obey the robots exclusion standards [...] is strictly prohibited." and, for all agents,
  disallows among others "/?*", "/*?*", "/5/resultlistpage", "/5/jobapply", "/public-api/v1/job-applications/",
  "/jobagent/", "/widget/".
- For a personal job search: job-seeker use allowed ("individual job search by natural persons"); automated
  reading - the terms forbid scraping "to collect content to use it for another purpose, to publish it again or
  use it in a different way than what the Services are intended for" (as worded, a ban tied to other purposes,
  not a ban on every program), and robots.txt closes every URL with a query string and the result-list pages;
  private copy not stated.
- How to apply: on the platform where the recruiter allows it - the application is then either stored on
  Stepstone for the recruiter or "transmit[ted] directly to the Stepstone-Customer's application management
  system"; otherwise on the recruiter's side.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 2,897 bytes; GET of the terms -> 200, text/html,
  118,234 bytes.
- Caveats: third-party scraper listings say Stepstone's sites sit behind Akamai bot protection.

### Jobat (with Vacature.com) and Références
- Publisher: Jobat (Mediahuis); Vacature.com (DPG Media) now points to Jobat; Références / references.be (Rossel).
- Documentation: none read.
- Data or endpoint: https://www.jobat.be ; https://www.references.be
- Holds: job adverts. Not examined. Access: web only as far as checked.
- Registration or key: none to browse. Cost: free to browse.
- Licence or terms (exact wording, with URL): not read. Jobat's robots.txt (https://www.jobat.be/robots.txt)
  disallows for all agents login and register pages, `/*.aspx*`, old article paths and URLs with
  `joblanguage=`, `action=`, `Pref_Lang=`, `favorites=`; it shuts out DataForSeoBot, AwarioBot, Cxensebot,
  PetalBot and Baiduspider ("# added 20250526: block crawlers"); job pages are not disallowed.
- For a personal job search: job-seeker use not stated (terms not read); automated reading refused in practice
  beyond robots.txt (403 on the home page); private copy not stated.
- How to apply: not examined.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.jobat.be/robots.txt -> 200, 1,317 bytes; GET https://www.jobat.be/nl ->
  **403**, a Cloudflare page "Sorry, you have been blocked" (host not asked again). GET
  https://www.vacature.com/robots.txt -> 301 to https://www.jobat.be/nl/vacature. GET
  https://www.references.be/robots.txt -> **403** "Access Denied" (an Akamai edge error page; host not asked again).
- Caveats: per VDAB's disclaimer (search summary) Jobat republishes VDAB vacancies. When and how Vacature.com
  was folded into Jobat was not established (a 2019 joint-venture plan of DPG Media and Mediahuis is all a
  search found).

### Indeed and LinkedIn in Belgium
- Same terms as recorded in this pass's France file (`FR-France.md`): Indeed's terms of 1 April 2026 forbid
  using "un système automatisé (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique)" to access
  the site without written permission; LinkedIn's User Agreement (effective 3 November 2025) forbids software,
  scripts, robots or crawlers "to scrape or copy the Services". Job-seeker use allowed, automated reading
  forbidden whatever the purpose, private copy forbidden as worded. No request was made to be.indeed.com.

### Official vacancy statistics (one line)
- Statbel's quarterly job vacancy survey ("Vacatures op de arbeidsmarkt", "Vacatures in loondienst in België",
  CC BY 4.0 on data.gov.be per the data.europa.eu records); aggregates only.

## Through the employers

### Business register
- Publisher: FPS Economy (SPF Economie / FOD Economie) - the Crossroads Bank for Enterprises (KBO / BCE). The
  register is **national**, one for the whole country: "The Belgian business register [...] is managed by an
  office in the Federal Department of the Economy [...] The database covers all enterprises, and the law requires
  all enterprises to register" (European e-Justice Portal).
- Documentation:
  https://economie.fgov.be/en/themes/enterprises/crossroads-bank-enterprises/services-everyone/public-data-available-reuse/cbe-open-data
  (answered with a CAPTCHA); https://e-justice.europa.eu/topics/registers-business-insolvency-land/business-registers-eu-countries/be_en
- Data or endpoint: Open Data files behind https://kbopub.economie.fgov.be/kbo-open-data (login); Public Search
  https://kbopub.economie.fgov.be/kbopub/zoeknummerform.html (one company per request; not requested).
- Holds: per the e-Justice page, the Public Search shows per enterprise: "enterprise registration number, status,
  legal situation, start date, name, address of head office, telephone number, fax, email, website, legal form of
  the enterprise, number of establishments, officers, [...] activities for purposes of VAT and social security,
  financial information, links with other businesses", and per establishment number, start date, name, address,
  telephone, fax, e-mail, website, activities. That covers seven of the eight minimum attributes of Regulation
  (EU) 2023/138 by name (name, status, registration/start date, registered office address, legal form,
  registration number, activity) - the Member State is implicit - and, beyond them, telephone, e-mail and
  website where the enterprise has declared them. Which of these columns the free Open Data file carries could
  not be checked today (login). From memory, not confirmed: the file is a set of CSVs (enterprise,
  establishment, denomination, address, contact, activity, branch, code) in which `contact` holds telephone,
  e-mail and web address, and it has no number of employees.
- Access: (1) free web search, one company at a time; (2) the Open Data file, free, **only after registration**;
  (3) a web service to build the public data into one's own applications, "provided for a fee" (e-Justice
  page). So basic data on every company is free in bulk, but behind an account, not anonymously; there is no
  free keyless API.
- Registration or key: an account for the Open Data file ("An 'Open Data' file is also available free of
  charge: this can be reused by any interested person provided they register"). Not created.
- Cost: free (file, search); web service paid.
- Licence or terms (exact wording, with URL): not read (the FPS page and the download page were not
  readable). Third parties describe a licence of the FPS's own with a ban on reusing personal data for direct
  marketing - not confirmed.
- For a personal job search: use not stated (licence not read); automated reading allowed for the Open Data file
  once registered, by the e-Justice wording ("can be reused by any interested person"); private copy not stated.
- How to apply: not applicable.
- Volume: all enterprises and establishment units. Update cycle: per a search summary of the FPS page, full and
  update files are published and stay available 31 days; not confirmed.
- Seen on 2026-11-28: GET https://kbopub.economie.fgov.be/kbo-open-data -> 302 to `/kbo-open-data/login`; GET of
  the FPS Economy page -> 200, 47,005 bytes, but a CAPTCHA page ("This question is for testing whether you are a
  human visitor"); the host was not asked again. GET of the e-Justice page -> 200, text/html, 68,586 bytes.
- Caveats: whether the file is published as an EU high-value dataset ("companies and company ownership") was not
  established - no record of it was among the 15 Belgian results read on data.europa.eu, and the publisher's
  pages could not be read.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| CVWarehouse | Belgian (Antwerp, per its corporate presentation) | A "free jobs XML API" and a Jobs API are advertised in its flyers; whether readable without a key is not documented publicly - the documentation page named by a search answers 404 today and the full documentation is on a customer help desk | https://c.cvwarehouse.com/en/documentation (404); flyers at company.cvwarehouse.com/downloads/Flyers/ (search summaries, not fetched) | Vendor's own material (search summaries); no customer list read |
| Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Recruitee, Personio, Workday | International | See this study's `00-EU-wide.md`, topic 5 | there | Not established for Belgium from any source read today |

No source was found on which systems Belgian employers use most. Other vendors met in searches (Cegid
Talentsoft, Otys, Carerix, Bullhorn Connexys) were not examined for Belgium.

### Links to employers' own pages
- Le Forem's dataset gives the employer's name (`nomemployeur`), the offer's origin (`source`) and an external
  reference (`referenceexterne`), but its only link (`url`) goes to the Forem's own page, not to the employer.
- The company register shows a website and e-mail per enterprise where declared (e-Justice description of the
  Public Search); if the Open Data file carries them (unconfirmed), it is the one free bulk source of employer
  websites found for Belgium.
- Third-party descriptions of Actiris scrapers say Actiris offers carry the employer's KBO number; not verified.

### Employer directories
- None was verified. Agoria (the technology federation, "over 2,000 member companies" per third-party pages)
  has no public member directory that a search found; Wallonia's cluster sites (clusters.wallonie.be) publish
  member lists (seen in search results only). Terms not read.

## Not free or not allowed

- VDAB's vacancy API: free but by account, subscription and VDAB's approval; aimed at employers and partners.
- Le Forem's partner APIs: access codes on request, for organisations that publish offers.
- KBO/BCE: bulk file only after registration; the web service is paid.
- StepStone: scraping for purposes other than the individual job search forbidden; query-string and result
  pages closed in robots.txt. Indeed and LinkedIn: automated reading forbidden.
- Refused or challenged a plain client: adg.be (403, Cloudflare challenge), jobat.be (403, Cloudflare block),
  references.be (403, Akamai), travaillerpour.be (script challenge), economie.fgov.be (CAPTCHA),
  extranet.vdab.be (403).
- Scrapers of VDAB, Actiris and StepStone are sold on apify.com; a vendor sells a "Belgian job postings feed" on
  AWS Marketplace (search results only).

## Gaps

- **Le Forem's records**: none seen (429 on the anonymous quota); the field list is from the metadata. Whether
  the export endpoints share the quota is not known.
- **VDAB**: disclaimer and terms not read (redirect used the request); the API specification, who qualifies for
  a subscription, and whether it returns all published vacancies were not established; the vacancy page's
  content and apply paths are loaded by script and were not seen; number of live vacancies not read.
- **Actiris**: the offers page, its volume and apply paths were not read; no statement found on reuse by
  programs.
- **ADG**: nothing but robots.txt.
- **Vacancy exchange between regions**: taken from Le Forem's dataset description and a search summary of VDAB's
  disclaimer; how complete it is, is not known. Hence no claim that any regional source covers the country.
- **Federal and regional public-sector portals**: no feed found, pages not readable or not examined; Wallonia's
  portal not looked for.
- **Jobat, Références**: terms not read (403). **Vacature.com**: only the redirect seen. ICTjob.be, Monster.be
  and others not checked.
- **KBO/BCE**: licence, file layout, update cycle, the presence of website and e-mail columns in the free file,
  and its high-value-dataset status are all unconfirmed (login, CAPTCHA).
- **Applicant-tracking vendors and employer directories**: no reliable source for Belgium; CVWarehouse's feed
  terms not read; Agoria's site not requested.
- Belgium's EURES count is for the whole country and comes from this study's EU-wide file.
