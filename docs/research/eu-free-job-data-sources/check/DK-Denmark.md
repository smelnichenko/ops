# Denmark (DK) - check of the research

The research file has no section on the employer route; it is added in a later pass.

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent, one capped GET per URL, one at a time;
web search for leads; the Internet Archive for two pages not requested live. No account, key or login. At most
three requests per host. One slip: a request to `www.job-i-staten.dk` was made with redirects followed and ran
through `job.jobnet.dk` and `jobnet.dk` (the third request to jobnet.dk) to the login page of STAR's identity
server; nothing was submitted. Statistics (Jobindsats, Statistics Denmark) were not requested: out of purpose.

## Corrections and unverified claims (apply these first)

- CORRECTED: JobannonceService is not obtainable now. STAR's page "Webservice til import og eksport af
  jobannoncer" ("Sidst opdateret: 24-11-2026") says: "Indtil denne proces er afsluttet, vil der ikke blive indgået
  nye tilslutningsaftaler." Access needs an e-mail to spoc@star.dk, a signed connection agreement
  (tilslutningsaftale), a function certificate, a whitelisted IP address and a CVR (company) number.
- CORRECTED: STAR's wiki is readable (curl: 200, about 1.8 MB of HTML per page). It says the SOAP-based JobAD was
  replaced by a REST version named JobannonceService, in production 16-09-2023 (version 1, release 2023-3);
  version 2 is "release 2024-4". "Version 2 from 2024-12-06" and "HR-XML" were not seen.
- CORRECTED: the conditions for a new importer ARE published (the STAR page above and the wiki page "Procedure for
  tilslutning: Adgang til testmiljø"); the terms are in the connection agreement, whose text was not seen.
- CORRECTED: whether Jobnet adverts go to EURES is stated: the employer chooses for each advert. STAR's rules
  (PDF of 2025-04-22): "Virksomheden kan ved den enkelte annonceoprettelse vælge, om annoncen også skal vises på
  www.workindenmark.dk samt på EURES".
- CORRECTED: the Jobindex v. Google case is over. The appeal (lodged 24 September 2024, straight to the Supreme
  Court) was withdrawn after a settlement in February 2025.
- CORRECTED: Jobindex's volume is on the terms page read: its header shows "35.000 job i dag".
- CORRECTED: it-jobbank.dk does offer the same RSS feed as Jobindex (`/jobsoegning.rss?q=`, 14 items); the
  research had left it untested.
- CORRECTED: Jobnet's content - besides employers' own adverts, "Jobnet høster job fra virksomheders hjemmesider"
  (STAR's rules), i.e. Jobnet also collects jobs from companies' websites by robot.
- WRONG (on archive evidence): Ofir as a live board ("holds job adverts", "free to browse", "continuous"). The
  Internet Archive's copy of `https://www.ofir.dk/` of 2026-10-10 is a 410 page: "Ofir.dk er lukket, besøg
  Jobindex i stedet". The live front page was not requested, because robots.txt disallows everything.
- UNVERIFIED: jobbank.dk's pages and terms - `https://jobbank.dk/job/` and `https://jobbank.dk/` both answered
  500 with an empty body to this client (robots.txt answered 200); stopped at three requests.
- UNVERIFIED: that it-jobbank.dk's publisher is Jobindex A/S - its terms name "Computerworld it-jobbank ... CVR:
  26533880" at Jobindex's address (Carl Jacobsens Vej 29-31, 2500 Valby); "Jobindex A/S" is not named there.
- UNVERIFIED: Jobnet's terms of use for job seekers - no terms link on the page read; three requests used.
- UNVERIFIED: the third-party claim that Jobnet's search runs on `jobnet.dk/bff` without credentials - an
  internal interface, not requested.
- UNVERIFIED: the Jobindsats API block (key by e-mail within 14 days, one per organisation, v2 closed) and the
  Statistics Denmark block (API, CC BY 4.0, LSK11 to 2026Q3) - not requested: statistics.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | Denmark has no open dump or keyless API of job adverts | NOT DISPROVED | data.europa.eu hub search, country dk: "jobannoncer" count 0; "ledige stillinger stillingsopslag jobopslag Jobnet" count 60, the first 25 all statistics (STAR's counts, Statistics Denmark tables). Web search: only third-party scrapers | - |
| 2 | Jobnet: STAR's job bank; web application at https://jobnet.dk/find-job | CONFIRMED | GET -> 200, text/html, 78 550 bytes, a Next.js shell: menu, "Log ind", empty result rows, no adverts in the HTML. STAR's rules: "Jobnet er en statslig jobportal, som Styrelsen for Arbejdsmarked og Rekruttering har ansvaret for." | - |
| 3 | Jobnet serves no robots.txt: 307 to `/auth/duendebff/login?returnUrl=%2Frobots.txt` | CONFIRMED | GET `https://jobnet.dk/robots.txt` -> 307, Location `https://jobnet.dk/auth/duendebff/login?returnUrl=%2Frobots.txt` (not followed) | - |
| 4 | Jobnet holds adverts entered by employers or delivered by other job databases | CORRECTED | STAR's rules PDF: employers post through JobAG or "webservicen JobannonceService"; "ligesom Jobnet høster job fra virksomheders hjemmesider" | Add: Jobnet also harvests jobs from companies' websites |
| 5 | Web only for the public; a third party says the search runs on an undocumented `jobnet.dk/bff` interface | UNVERIFIED | Not requested. Today's search results list several Apify "Jobnet scraper" actors; one summary says it "talks directly to Jobnet's public search API and needs no login" | - |
| 6 | No registration for searching on the web page; free | CONFIRMED | The search page answered 200 without login; "Alle danske virksomheder kan bruge Jobnet. Det er gratis." is said of employers. Adverts themselves were not seen (script-rendered) | - |
| 7 | Jobnet: no terms page for reuse located | NOT DISPROVED | The page read links only `/hjaelp-og-support`. STAR's rules PDF has terms for EMPLOYERS only (bilag 1, "Vilkår for brug af Jobnet for Arbejdsgivere") | - |
| 8 | info.jobnet.dk no longer resolves | CONFIRMED | curl: "Could not resolve host: info.jobnet.dk" | - |
| 9 | JobannonceService: STAR's page, "Sidst opdateret: 26-01-2026", quote "Jobnet tilbyder en webservice (JobannonceService) der kan sende jobannoncer ind og ud af Jobnet" | CONFIRMED | GET `https://star.dk/.../jobnet-webservice` -> 200, text/html, 60 101 bytes: "Jobnet tilbyder en webservice (JobannonceService) der kan sende jobannoncer ind og ud af Jobnet som en "Event driven service", der giver mulighed for nær-realtids synkronisering med Jobnets data."; "Sidst opdateret: 26-01-2026" | - |
| 10 | The target group includes those who want to import adverts for their own job portal or website | CONFIRMED | "Målgruppen er virksomheder og organisationer, der: ønsker at eksporterer jobannoncer til publicering på Jobnet og/eller ønsker at importere annoncer til udstilling på egen jobportal eller hjemmeside" | The target group is companies and organisations |
| 11 | Access on request to STAR (spoc@star.dk), not self-service | CORRECTED | GET `https://star.dk/.../webservice-til-import-og-eksport-af-jobannoncer` -> 200, 60 021 bytes, "Sidst opdateret: 24-11-2026": new users "skal sende en e-mail til spoc@star.dk" naming who they are, which web service, and what it is for; "Der skal indgås en tilslutningsaftale, som skal være udfyldt og underskrevet, inden serviceaftageren kan få adgang til et testmiljø"; "Med baggrund i den øgede fokus på IT-sikkerhed er styrelsen i gang med at gennemgå procedurerne for indgåelse af tilslutningsaftaler. Indtil denne proces er afsluttet, vil der ikke blive indgået nye tilslutningsaftaler." | No new connection agreements are made at present; when they are, access is by e-mail request plus a signed agreement and a test |
| 12 | Older SOAP/HR-XML JobAdService replaced by JobAnnonceService from release 2023-3; version 2 from 2024-12-06 | CORRECTED | GET `https://starwiki.atlassian.net/wiki/spaces/FYS/pages/3909583640/...` -> 200, text/html, 1 810 468 bytes ("Updated May 20, 2024"): "SOAP basseret JobAD erstattes med REST-version - og hedder fremover: JobannonceService", 16-09-2023; "JobAnnonceService version 1 (release 2023-3)"; "JobAnnonceService version 2 (release 2024-4)", link added 29-07-2024 | REST since 16-09-2023; version 2 = release 2024-4; the date 2024-12-06 and HR-XML were not seen |
| 13 | The wiki returned an empty page; its content is known only from search summaries | CORRECTED | Three wiki pages answered 200 with full text to curl | The wiki is readable without login |
| 14 | "Det er gratis at bruge Jobnets webservices"; own development costs | CONFIRMED | "Det er gratis at bruge Jobnets webservices, men alle nye kunder skal forvente udgifter til den egen udvikling". Wiki: "i alt 5 timers gratis support ... Support ud over 5 timer faktureres" | - |
| 15 | No terms of reuse on the STAR page; conditions presumably set when access is granted | CORRECTED | Wiki page 3926655785 ("Procedure for tilslutning: Adgang til testmiljø", 200, 1 718 251 bytes): "skal alle eksterne aftagere indgå en ny tilslutningsaftale (aftale mellem den enkelte aftager og STAR om brug af JobannonceService)"; the request must give "firmanavn, CVR-nummer, kontaktperson", the "IP-adresse ... som skal whitelistes", the role ("Publicering af jobannoncer på Jobnet.dk", "Afhentning af publicerede jobannoncer fra Jobnet.dk", "Indhentelse af data i forbindelse med statistiske formål") and the "Brugsmønster" | Conditions are in the connection agreement (text not seen); a CVR number, a function certificate and a fixed IP address are required |
| 16 | Event-driven, near real time | CONFIRMED | Claim 9 quote | - |
| 17 | The conditions for approving a new importer are not on the page | CORRECTED | Claims 11 and 15 | They are on the linked STAR page and the wiki |
| 18 | STAR's monthly count of vacancies on Jobnet is on data.europa.eu as `https-data-gov-dk-dataset-y25i07`, CC BY 4.0, CSV/XLSX/JSON, modified 2026-11-05 | CONFIRMED | In the hub search answer: that id, publisher STAR, formats CSV, Excel XLSX, HTML, JSON, licence "Creative Commons Attribution 4.0 International", modified 2026-11-05 | Statistics: of no use for the purpose |
| 19 | Jobindsats API: key by e-mail to jobindsats-api@star.dk within 14 days, one per organisation; v2 closed; page sizes | UNVERIFIED | Not requested: statistics | - |
| 20 | Jobindex terms: https://www.jobindex.dk/betingelser, "Privatlivspolitik og brugsvilkår", "Version 1.0 gældende fra 30. juni 2026" | CONFIRMED | GET -> 200, text/html, 144 385 bytes; "Versionsinformation Version 1.0 gældende fra 30. juni 2026. Mindre tekstrettelser ... (13.08.2026)" | - |
| 21 | Jobindex RSS of a search, `https://www.jobindex.dk/jobsoegning.rss?q=<words>`: public, no key, answered | CONFIRMED | GET `...jobsoegning.rss?q=landinspekt%C3%B8r` -> 200, application/rss+xml, 25 576 bytes, 14 items, `<ttl>1440</ttl>` | - |
| 22 | RSS item: title with employer, link, description with the result card as escaped HTML | CONFIRMED | Item elements: title, link, description, plus `pubDate`, `guid`, `category`. No copyright or licence element in the feed | Add pubDate, guid, category |
| 23 | Jobindex lists adverts placed with it and adverts its robot collects | CONFIRMED | Internet Archive copy of 2026-10-19 of `https://www.jobindex.dk/handelsbetingelser` ("Gældende fra 1. januar 2026"): "Robotscanningsaftale ... Robotannoncer vises på Jobindex i tre uger"; STAR's rules name Jobindex among job banks that "via en robot 'høster' job fra Jobnet" | - |
| 24 | robots.txt quotes (`/api/`, `/jobsoegning*page=`, `*sort=`, `*jobage=`, `*archive=`, `/jobsoegning/*?*&`, `/job/*?`, `/annoncer/`, `/jobannonce/embed/`, `/iframe/`); plain `/jobsoegning?q=` and `/vis-job/` not disallowed; sitemap.gz named | CONFIRMED | GET `https://www.jobindex.dk/robots.txt` -> 200, text/plain, 4 218 bytes; all quoted lines present under "User-agent: *"; "sitemap: https://www.jobindex.dk/sitemap.gz"; six single `/vis-job/` adverts are disallowed by id; no rule matches `/jobsoegning.rss?q=` with one parameter; no Crawl-delay | - |
| 25 | The user terms contain no clause on automated reading, copying of adverts or reuse of the feed; Jobindex states no reuse terms for the feed | NOT DISPROVED | In today's `/betingelser` text: 0 occurrences of robot, crawl, scrap, kopier, RSS; "ophavsret" once (about employer evaluations). The business terms (archive copy of 2026-10-19) address employers: "Jobindex har den fuldstændige ophavsret, adkomst og alle andre rettigheder til sine produkter, herunder retten til personoplysninger og anden data" | - |
| 26 | Jobindex volume: not stated on the pages read | CORRECTED | Header of `/betingelser`: "35.000 job i dag" | About 35 000 jobs on 2026-11-28 |
| 27 | The feed for one narrow query returned 14 items; whether it pages was not tested | CONFIRMED | 14 items. The it-jobbank feed for "java" also returned exactly 14, which suggests a cap of 14 a feed; not tested further | - |
| 28 | Jobindex and Danske Medier appealed the 27 August 2024 ruling that cleared Google for Jobs; reuse is a legal risk | CORRECTED | Ritzau release of 25.9.2024 "Jobindex og Danske Medier anker dom i retssag mod Google" (200). Dansk Erhverv, "Opdateret 27.02.2025" (200): "Dommen blev den 24. september 2024 anket direkte til Højesteret. Jobindex og Danske Medier har dog efterfølgende trukket anken tilbage, da sagens parter i februar 2025 har indgået et forlig." | The appeal was withdrawn after a settlement in February 2025 |
| 29 | Ofir robots.txt, whole file: "User-agent: * Allow: /.well-known/ Disallow: /" | CONFIRMED | GET `https://www.ofir.dk/robots.txt` -> 200, text/plain, 47 bytes, those three lines | - |
| 30 | Ofir: publisher Ofir A/S, holds job adverts, free to browse, continuous | WRONG | Internet Archive copy of 2026-10-10 of `https://www.ofir.dk/`: status 410, title "Ofir.dk er lukket", body "Ofir.dk er lukket, besøg Jobindex i stedet". Jobindex's robots.txt also carries "Disallow: /jobsoegning*q=ofir". Live front page not requested (robots.txt) | Ofir.dk is closed and points to Jobindex (archive copy of 2026-10-10) |
| 31 | jobbank.dk robots.txt: "Host-load: 2", "Allow: /job/", disallows /job-arkiv/, /ajax/, /link/, /redirect/, /profil/ | CONFIRMED | GET -> 200, text/plain, 626 bytes, "# robots.txt for jobbankerne"; also "User-agent: Scrapy / Crawl-delay: 5" | - |
| 32 | jobbank.dk: adverts at https://jobbank.dk/job/, web only, free to browse | UNVERIFIED | GET `https://jobbank.dk/job/` -> 500, 0 bytes; GET `https://jobbank.dk/` -> 500, 0 bytes | - |
| 33 | it-jobbank.dk's robots.txt mirrors Jobindex's | CONFIRMED | GET -> 200, text/plain, 1 889 bytes; same `/api/` and `/jobsoegning*` rules; "sitemap: https://www.it-jobbank.dk/sitemap.gz" | - |
| 34 | it-jobbank.dk is published by Jobindex A/S | UNVERIFIED | Terms (GET `https://www.it-jobbank.dk/betingelser` -> 200, 118 693 bytes, "Betingelser og privatlivspolitik (Gældende fra 15. marts 2023)"): "Den dataansvarlige er: Computerworld it-jobbank Carl Jacobsens Vej 29-31 2500 Valby ... CVR: 26533880" | Same address and software as Jobindex; the company name is not on the page |
| 35 | Whether it-jobbank.dk offers the same RSS was not tested | CORRECTED | GET `https://www.it-jobbank.dk/jobsoegning.rss?q=java` -> 200, application/rss+xml, 36 845 bytes, 14 items, `<ttl>1440</ttl>`, channel "Computerworld it-jobbank - Ledige job indeholdende ordet java" | It does |
| 36 | Statistics Denmark: API without key, tables LSK11-LSK15, LS01, LS02, CC BY 4.0 | UNVERIFIED | Not requested: statistics. The hub search answer lists dst-lsk11 to dst-lsk15, dst-ls01, dst-ls02 with CC BY 4.0 | - |
| 37 | EURES: "Annoncer på Jobnet kan desuden blive vist på Workindenmark.dk og EURES (Den europæiske portal for jobmobility)."; whether all or only marked ones is not stated | CORRECTED | The sentence is on STAR's page (claim 9). STAR's rules PDF (GET `https://star.dk/media/uovn5mx3/2025_04_22_regler-for-kvalitetssikring-af-annoncer-paa-jobnet-og-virksomhedernes-brug-af-cv-banken.pdf` -> 200, application/pdf, 1 088 266 bytes, 24 pages): "Virksomheden kan ved den enkelte annonceoprettelse vælge, om annoncen også skal vises på www.workindenmark.dk samt på EURES, den Europæisk Portal For Jobmobilitet."; such an advert "skal som hovedregel skrives på engelsk" | Only the adverts the employer marks go to Workindenmark and EURES |
| 38 | https://www.workindenmark.dk/robots.txt answers 404 | CONFIRMED | GET -> 404, 0 bytes | - |
| 39 | Jobindex `/api/` and paged or filtered search URLs are disallowed by robots.txt | CONFIRMED | Claim 24 | - |
| 40 | Third-party scrapers of jobnet.dk and jobindex.dk are sold on apify.com | CONFIRMED | Today's search results: `apify.com/studio-amba/jobnet-scraper`, `apify.com/blackfalcondata/jobnet-scraper`, `apify.com/parsebird/jobindex-dk-scraper` and others (not opened) | - |
| 41 | A central portal for state, municipal and regional vacancies with a feed: none found | NOT DISPROVED | `https://www.job-i-staten.dk/` (named in older state documents as the state's job portal) -> 302 to `https://job.jobnet.dk/CV/frontpage`, which leads to Jobnet's login. The state portal's address now ends in Jobnet | - |

## For a personal job search and applications

| Source | Job-seeker use | Automated reading | Private copy | How to apply | Basis (quoted clause, URL) |
|---|---|---|---|---|---|
| Jobnet (jobnet.dk) | not stated - no job-seeker terms found; the search page opens without login | not stated - no robots.txt (307 to login), no terms for readers. STAR's terms for employers describe robots as normal practice: "Job på Jobnet kan også blive vist i andre jobbanker ... Det sker ved, at andre jobbanker via en robot 'høster' job fra Jobnet - ligesom Jobnet høster job fra virksomheders hjemmesider." A statement to employers, not a permission to readers | not stated | not stated on anything read; the employer sets it when posting ("Hvordan vil du modtage ansøgninger?" is one of the advert's fields) | https://jobnet.dk/robots.txt ; https://star.dk/media/uovn5mx3/2025_04_22_regler-for-kvalitetssikring-af-annoncer-paa-jobnet-og-virksomhedernes-brug-af-cv-banken.pdf (bilag 1) |
| JobannonceService (STAR) | forbidden in effect - not offered to a private person: "Målgruppen er virksomheder og organisationer"; the request needs "firmanavn, CVR-nummer"; and "vil der ikke blive indgået nye tilslutningsaftaler" for now | limited - an API client is the intended use, but only under a signed connection agreement, with a function certificate and a whitelisted IP address | not stated - set in the connection agreement (not seen) | not stated | https://star.dk/digital-service/saadan-arbejder-vi-med-it-i-styrelsen/oversigt-over-digitale-platforme-for-eksterne-brugere/styrelsen-for-arbejdsmarked-og-rekrutterings-webservices-og-wiki/webservice-til-import-og-eksport-af-jobannoncer ; https://starwiki.atlassian.net/wiki/spaces/FYS/pages/3926655785 |
| Jobindex (site and RSS feed) | allowed - the terms are written for job seekers ("Denne politik beskriver, hvordan Jobindex behandler dine personoplysninger, når du bruger vores tjenester") | not stated in the terms (no clause; 0 mentions of robot, crawl, RSS). robots.txt: limited - "Disallow: /api/", "Disallow: /jobsoegning*page=", "*sort=", "*jobage=", "*archive=", "Disallow: /job/*?"; the plain search, `/vis-job/` pages and the one-parameter RSS address are not disallowed; no Crawl-delay; agents 008, sogou spider and CariBot are banned outright. These are path rules for all bots, whatever the purpose | not stated for readers. For employers the business terms claim "den fuldstændige ophavsret ... og alle andre rettigheder til sine produkter" (archive copy of 2026-10-19) - a rights claim, not a clause on private copies | "Ansøg" in the advert: "Dine ansøgningsoplysninger håndteres enten i virksomhedens eget ansøgningssystem eller i Jobindex' ansøgningssystem." | https://www.jobindex.dk/betingelser ; https://www.jobindex.dk/robots.txt ; https://www.jobindex.dk/jobsoegning.rss?q=landinspekt%C3%B8r |
| it-jobbank.dk (site and RSS feed) | allowed - terms written for job seekers' profiles | not stated in the terms. robots.txt: limited, the same path rules as Jobindex ("Disallow: /api/", paged and filtered `/jobsoegning` addresses) | not stated | not stated on the terms page (the site has profile-based applications: menu "Ansøgninger") | https://www.it-jobbank.dk/betingelser ("Gældende fra 15. marts 2023") ; https://www.it-jobbank.dk/robots.txt |
| Ofir | not stated - site closed per the archive copy ("Ofir.dk er lukket, besøg Jobindex i stedet") | forbidden - a ban on all bots whatever the purpose: "User-agent: * / Allow: /.well-known/ / Disallow: /" | not stated | not applicable | https://www.ofir.dk/robots.txt ; https://web.archive.org/web/20261010060140id_/https://www.ofir.dk/ |
| Jobbank.dk | not stated - pages answered 500 | limited by robots.txt: "Allow: /job/", "Host-load: 2", disallows for /job-arkiv/, /ajax/, /link/, /redirect/, /profil/; "User-agent: Scrapy / Crawl-delay: 5". Terms not read | not stated | not stated | https://jobbank.dk/robots.txt |
| Workindenmark (job search at workindenmark.jobnet.dk) | allowed - "Workindenmark assists highly qualified and skilled professionals seeking employment in Denmark" | not stated - no robots.txt (404); the site links a privacy policy, a cookie policy and an accessibility statement, no terms of use | not stated | not stated (the job search host was not requested) | https://www.workindenmark.dk/about-workindenmark-eures ; https://www.workindenmark.dk/robots.txt |
| STAR's count of vacancies on Jobnet; Statistics Denmark's tables | not stated - counts only, no adverts: of no use for this purpose | not stated - not read | allowed - CC BY 4.0 per the catalogue | not applicable | data.europa.eu hub search answer (ids `https-data-gov-dk-dataset-y25i07`, `dst-lsk11` ...) |

## Found beyond the research

- STAR has stopped making new connection agreements for its web services (page updated 24-11-2026, four days
  before this check). The route is closed to newcomers until STAR finishes reviewing its procedures.
- STAR's wiki documents the service openly: roles (publish, fetch published adverts, fetch data for statistics),
  REST, function certificates, test and production environments, version 1 and version 2 welcome pages
  (`.../pages/4023386657`, `.../pages/4324458548`, not requested).
- STAR's rules for adverts on Jobnet (PDF of 2025-04-22) hold the employer terms and three facts the research
  lacked: other job banks harvest Jobnet by robot; the employer chooses per advert whether it goes to
  Workindenmark and EURES; "Annoncer slettes automatisk fra Jobnet 12 måneder efter annoncens udløb."
- Ofir.dk is closed (archive copy of 2026-10-10, HTTP 410, pointing to Jobindex).
- it-jobbank.dk has the same RSS feed as Jobindex (`/jobsoegning.rss?q=`), 14 items a feed.
- `www.job-i-staten.dk` redirects to Jobnet (`https://job.jobnet.dk/CV/frontpage`), so the state's own job
  portal is no longer a separate public site.
- Workindenmark's job search lives on a Jobnet host, `https://workindenmark.jobnet.dk/` (linked from its front
  page; not requested). Workindenmark describes itself as "part of the European Employment Services (EURES)".
- Jobindex's business terms let Jobindex pass adverts on: "Jobindex er berettiget, men ikke forpligtet til at
  publicere annoncer i andre medier eller at distribuere annoncer til tredjeparter" (archive copy of 2026-10-19).
- Still unchecked, as in the research: StepStone.dk, Jobfinder, Indeed and LinkedIn in Denmark.
