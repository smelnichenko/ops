# Denmark (DK) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (one capped GET per URL), the Claude Code
WebFetch tool with its own default client, and web search. No account, key or login was used.

## Takeaway

Denmark has no open dump or keyless API of job adverts. The official route to the adverts is the employment
agency's JobannonceService, a free web service that sends Jobnet adverts out to other job portals, but access
is granted by the agency (STAR) on request, not self-service. Without any agreement, the best free advert source
found is Jobindex's RSS feed of a search (public, no key, answered today), though Jobindex states no reuse
terms for it and its robots.txt closes paged and filtered search URLs. Statistics are fully open: Statistics
Denmark's vacancy tables (API, no key, CC BY 4.0) and STAR's monthly count of vacancies on Jobnet (CC BY 4.0 on
the national data catalogue; the Jobindsats API behind it needs a key issued by e-mail within 14 days). Ofir's
robots.txt forbids all automated reading.

## Sources

### Jobnet (public employment service job bank)
- Publisher: Styrelsen for Arbejdsmarked og Rekruttering, STAR (Danish Agency for Labour Market and Recruitment).
- Documentation: none found for public reading of the site. STAR's page on its web services (next block).
- Data or endpoint: https://jobnet.dk/find-job (web application, "Find Job").
- Holds: job adverts entered by employers on Jobnet or delivered to it by other job databases. Fields not
  examined (no data endpoint was requested).
- Access: web only for the public. A third party (a published scraper description, tessl.io / apify.com, seen
  in search results) says the site's own search runs on an undocumented `jobnet.dk/bff` REST interface without
  credentials; this is the site's internal interface, not offered or documented by STAR, and was not requested.
- Registration or key: none for searching on the web page.
- Cost: free.
- Licence or terms (exact wording, with URL): not found. No terms page for reuse was located, and the site
  serves no robots.txt (see below).
- Volume: not read from the site. STAR publishes the monthly count as a dataset (below).
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://jobnet.dk/robots.txt -> 307 to
  `/auth/duendebff/login?returnUrl=%2Frobots.txt` (a login redirect; not followed). GET
  https://jobnet.dk/find-job -> 200, text/html, 78 550 bytes (a Next.js page shell).
- Caveats: the old info.jobnet.dk host no longer resolves (DNS error on 2026-11-28).

### JobannonceService - STAR's web service for job adverts in and out of Jobnet
- Publisher: STAR.
- Documentation: https://star.dk/digital-service/saadan-arbejder-vi-med-it-i-styrelsen/oversigt-over-digitale-platforme-for-eksterne-brugere/styrelsen-for-arbejdsmarked-og-rekrutterings-webservices-og-wiki/jobnet-webservice
  ("Sidst opdateret: 26-01-2026"); technical pages on STAR's wiki, e.g.
  https://starwiki.atlassian.net/wiki/spaces/FYS/pages/54788185/Jobnets+webservices (the wiki returned an empty
  page to this client; its content is known here only from search-result summaries).
- Data or endpoint: not public; given to approved users.
- Holds: Jobnet's job adverts; the service works both ways. "Jobnet tilbyder en webservice (JobannonceService)
  der kan sende jobannoncer ind og ud af Jobnet". The target group includes those who want to import adverts
  for display on their own job portal or website.
- Access: web service by agreement with STAR (per search-result summaries of the wiki: SOAP with HR-XML in the
  older JobAdService, replaced by the new JobAnnonceService from release 2023-3, version 2 from 2024-12-06).
- Registration or key: yes - a request to STAR (spoc@star.dk; page section "Hvordan bliver du ny bruger af
  Jobnets webservices?"). Not self-service. Not requested.
- Cost: "Det er gratis at bruge Jobnets webservices"; new users must expect costs for their own development.
- Licence or terms (exact wording, with URL): the STAR page states no terms of reuse; conditions are presumably
  set when access is granted (not confirmed).
- Volume: not stated.
- Update cycle: event-driven, near real time (per the page).
- Seen on 2026-11-28: the STAR page was read through WebFetch (200); the wiki short link
  https://starwiki.atlassian.net/wiki/x/jQI5Aw returned no readable text.
- Caveats: the conditions under which STAR approves a new importer, and whether a non-Danish or non-portal
  user qualifies, are not on the page.

### STAR / Jobindsats - "Antal ledige stillinger på Jobnet" (monthly statistics)
- Publisher: STAR.
- Documentation: https://jobindsats.dk/api/ and
  https://jobindsats.dk/api/kom-i-gang/introduktion-til-apijobindsatsdk/ ; user guide
  https://jobindsats.dk/api/kom-i-gang/brugervejledning-til-version-3/ (not fetched).
- Data or endpoint: databank page
  https://jobindsats.dk/databank/arbejdsmarked/status-pa-arbejdsmarkedet/virksomhedernes-behov-for-arbejdskraft/antal-ledige-stillinger-pa-jobnet/ ;
  API at api.jobindsats.dk/v3. On data.europa.eu:
  https://data.europa.eu/data/datasets/https-data-gov-dk-dataset-y25i07 (catalogue "datavejviser").
- Holds: number of positions on Jobnet, "Periode: 2004-01-01 - 2026-10-31". Counts, not adverts.
- Access: web databank with file export (CSV, XLSX, JSON listed in the catalogue); API with a key.
- Registration or key: for the API, yes: "For at du kan bruge api.jobindsats.dk, skal du have en adgangsnøgle.
  Den får du ved at sende en mail til jobindsats-api@star.dk [...] Du vil herefter modtage en nøgle inden for
  14 dage [...] Vi giver i udgangspunktet kun én nøgle per organisation." Free, but by application, not
  self-service. The guidelines for use are handed out with the key.
- Cost: free.
- Licence or terms (exact wording, with URL): the catalogue record gives every distribution the licence
  "Creative Commons Attribution 4.0 International" (http://spdx.org/licenses/CC-BY-4.0).
- Volume: one monthly series from 2004.
- Update cycle: monthly (record modified 2026-11-05).
- Seen on 2026-11-28: GET https://jobindsats.dk/api/ -> 200, text/html, 221 166 bytes; GET of the introduction
  page -> 200, 223 028 bytes; one mistyped URL -> 404. The API itself was not called (no key).
- Caveats: API version 2 was closed (the site's news list: "Version 2 af API'et er nu lukket"; a secondary
  source dates this 30 September 2026); only v3 answers.

### Jobindex
- Publisher: Jobindex A/S (also runs it-jobbank.dk; its robots.txt is the same family).
- Documentation: none found for the RSS feed or for a read API. Terms:
  https://www.jobindex.dk/betingelser ("Privatlivspolitik og brugsvilkår", "Version 1.0 gældende fra 30. juni
  2026"); business terms https://www.jobindex.dk/handelsbetingelser (not fetched).
- Data or endpoint: RSS of a search, `https://www.jobindex.dk/jobsoegning.rss?q=<words>`; the site
  https://www.jobindex.dk/jobsoegning ; sitemap https://www.jobindex.dk/sitemap.gz (named in robots.txt, not
  requested).
- Holds (RSS item): title with employer, link to the advert, a description holding the search-result card as
  escaped HTML (logo, summary, place); channel `<ttl>1440</ttl>`. Jobindex lists both adverts placed with it and
  adverts its own robot collects from employers' sites (per its pages, seen in search summaries).
- Access: RSS feed and web pages. Robots.txt disallows `/api/`.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): the user terms page read today is a privacy policy plus rules
  for profiles and employer evaluations; it contains no clause on automated reading, copying of adverts or
  reuse of the feed. robots.txt (https://www.jobindex.dk/robots.txt) for all agents includes: "Disallow:
  /api/", "Disallow: /jobsoegning*page=", "Disallow: /jobsoegning*sort=", "Disallow: /jobsoegning*jobage=",
  "Disallow: /jobsoegning*archive=", "Disallow: /jobsoegning/*?*&", "Disallow: /job/*?", "Disallow:
  /annoncer/", "Disallow: /jobannonce/embed/", "Disallow: /iframe/"; plain `/jobsoegning?q=` and `/vis-job/`
  pages are not disallowed.
- Volume: not stated on the pages read. The feed for one narrow query returned 14 items.
- Update cycle: continuous; the feed declares a 1440-minute time to live.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 4 218 bytes; GET /betingelser -> 200, text/html,
  144 385 bytes; GET /jobsoegning.rss?q=landinspektør -> 200, application/rss+xml, 25 576 bytes, 14 items.
- Caveats: Jobindex defends its adverts in court: it and Danske Medier appealed a 27 August 2024 Maritime and
  Commercial Court ruling that had cleared Google for Jobs of infringing Jobindex's rights (Jobindex investor
  news, seen in search summaries). Reuse beyond reading the feed is therefore a legal risk even though no clause
  was found. Whether the feed pages (more than the first results) was not tested.

### Ofir
- Publisher: Ofir A/S.
- Documentation: none found.
- Data or endpoint: https://www.ofir.dk
- Holds: job adverts (not examined).
- Access: web only; automated reading refused by robots.txt.
- Registration or key: not applicable.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): https://www.ofir.dk/robots.txt, whole file: "User-agent: *
  Allow: /.well-known/ Disallow: /".
- Volume: not stated.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 47 bytes. No other request.
- Caveats: terms page not read.

### Jobbank.dk (Akademikernes Jobbank) and it-jobbank.dk
- Publisher: jobbank.dk - "jobbankerne" (per its robots.txt header); it-jobbank.dk - Jobindex A/S.
- Documentation: none found.
- Data or endpoint: https://jobbank.dk/job/ ; https://www.it-jobbank.dk
- Holds: job adverts for graduates; IT job adverts (not examined).
- Access: web only as far as checked.
- Registration or key: none to browse.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): https://jobbank.dk/robots.txt for all agents: "Host-load: 2",
  "Allow: /job/", and disallows for /job-arkiv/, /ajax/, /link/, /redirect/, /profil/. it-jobbank.dk's
  robots.txt mirrors Jobindex's ("Disallow: /api/", paged and filtered `/jobsoegning` URLs disallowed).
- Volume: not stated.
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://jobbank.dk/robots.txt -> 200, 626 bytes; GET
  https://www.it-jobbank.dk/robots.txt -> 200, 1 889 bytes.
- Caveats: terms pages not read; whether it-jobbank.dk offers the same RSS as Jobindex was not tested.

### Statistics Denmark - job vacancies
- Publisher: Danmarks Statistik.
- Documentation: https://www.dst.dk/da/api ; console https://api.statbank.dk/console ; statistics documentation
  https://www.dst.dk/da/Statistik/dokumentation/statistikdokumentation/ledige-stillinger
- Data or endpoint: `https://api.statbank.dk/v1/tableinfo/LSK11?format=JSON&lang=en` (metadata),
  `https://api.statbank.dk/v1/data` (data). Tables LSK11-LSK15 (quarterly), LS01, LS02 (annual). On
  data.europa.eu: dst-lsk11 ... dst-lsk15, dst-ls02.
- Holds: LSK11 - job vacancies (number) and vacancy rate by industry (DB25, 10 groups) and workplace size,
  2010Q1-2026Q3; LSK12/13 by region and sector or industry; LSK15 seasonally adjusted. From an employer
  survey.
- Access: API, no key for tables and data; CSV, XLSX, JSON, XML.
- Registration or key: none (only the catalogue method needs a key, on application).
- Cost: free.
- Licence or terms (exact wording, with URL): "Alle statistikdata på Statistikbanken.dk og hjemmesiden dst.dk
  kan benyttes frit både kommercielt og ikke-kommercielt, blot kilde angives. Det svarer til den licens, der
  benævnes Creative Commons, CC 4.0 BY." (https://www.dst.dk/da/api)
- Volume: seven tables.
- Update cycle: quarterly (LSK11 updated 2026-11-27).
- Seen on 2026-11-28: GET .../v1/tableinfo/LSK11 -> 200, text/json, 4 627 bytes (4 variables, 67 quarters);
  GET .../v1/tables?subjects=2 -> 200, 79 301 bytes (a table list, not used further).
- Caveats: the statistics documentation says Jobnet is a main source and warns that some firms post many
  vacancies under too few workplace numbers (seen in a search summary, not read directly).

### EURES and Workindenmark
- STAR's page says: "Annoncer på Jobnet kan desuden blive vist på Workindenmark.dk og EURES (Den europæiske
  portal for jobmobility)." So Jobnet adverts can reach EURES; whether all do, or only those the employer marks,
  is not stated. https://www.workindenmark.dk/robots.txt answered 404 (no robots file); the site was not read
  further.

## Not free or not allowed

- Ofir: robots.txt disallows the whole site to all agents.
- Jobnet's adverts in bulk: only through JobannonceService by STAR's approval - free of charge but not open.
- Jobindsats API: free, but a key by e-mail application, one per organisation.
- Jobindex: `/api/` and paged or filtered search URLs disallowed by robots.txt; advert reuse is something it
  litigates. Its paid products for employers (advert placement, robot scanning agreement) are not read access.
- Third-party scrapers of jobnet.dk and jobindex.dk are sold on apify.com (seen in search results only).

## Gaps

- Jobnet's terms of use and the fields of its adverts: not read (no terms page located; two of three requests
  used; data endpoints not requested).
- The number of live adverts on Jobnet and Jobindex today: not read. STAR's monthly series holds it for Jobnet.
- A central portal for state, municipal and regional vacancies with a feed: none found. Two searches for a
  state job portal ("Job i staten") returned nothing Danish beyond individual agencies' pages and a mention of
  the state's shared recruitment system (Statens eRekruttering). Not established either way.
- STAR wiki documentation of JobannonceService (formats, endpoints): not readable by this client.
- StepStone.dk, Jobfinder, Indeed and LinkedIn in Denmark: not checked.
- Jobindex's business terms (handelsbetingelser) and its advert archive page: not read (three-request limit).
- Whether every Jobnet advert goes to EURES: not established.
