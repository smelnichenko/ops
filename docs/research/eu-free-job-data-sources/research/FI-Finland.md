# Finland (FI) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (one capped GET per URL), the Claude Code
WebFetch tool with its own default client, and web search. No account, key or login was used.

## Takeaway

The best free source is the retrieval interface of Job Market Finland (Työmarkkinatori), the public employment
service's vacancy database: a documented REST API returning adverts as newline-delimited JSON. It is free and
open to "any organisation that wants to display job postings", but not self-service: the organisation files an
implementation notification, accepts the terms, and the KEHA Centre issues a subscription key and opens the
caller's IP addresses. The terms allow showing and combining the adverts with a source credit, and forbid passing
them to third parties and keeping removed adverts. Every advert there also goes to EURES. Keyless and openly
licensed are only small or statistical sources: the City of Vantaa's vacancy API (CC BY 4.0, 65 adverts today)
and Statistics Finland's vacancy tables (PxWeb API, CC BY 4.0). The largest commercial board, Duunitori, closes
its site to unnamed robots and forbids scraping in its terms.

## Sources

### Työmarkkinatori (Job Market Finland) - job posting retrieval interface
- Publisher: KEHA-keskus (KEHA Centre, the Development and Administration Centre for the ELY Centres and TE
  Offices), which runs the national employment service platform.
- Documentation: https://tyomarkkinatori.fi/en/instructions-and-support/interfaces/interfaces-for-job-postings/retrieval-interface-description-and-instructions
  (updated 25.5.2026; guide for version 2.0); technical page
  https://tyomarkkinatori.fi/jobpostingprovider/documentation/KIPA-search-jobpostings-en.html ; terms
  https://tyomarkkinatori.fi/en/instructions-and-support/interfaces/interfaces-for-job-postings/terms-of-use-for-job-market-finlands-job-posting-apis
  (updated 12.3.2026).
- Data or endpoint: production `https://api.ahtp.fi/kipa/p67/v2/jobpostings`, test
  `https://api-qa.ahtp.fi/kipa/p67/v2/jobpostings` (HTTP POST with filters; header `KIPA-Subscription-Key`).
  Not called (no key).
- Holds: whole job postings "in accordance with the structure of the jobposting", with code sets for country,
  municipality, region, industry (TOIMIALA), occupation (ESCO), skills (ESCO), employment relationship, type of
  contract, duration of temporary employment, working time, wage principle and wage range, language, driving
  licence, permits, advertiser type and posting status. An OpenAPI (yaml) description is linked from the
  documentation page.
- Access: API, results as an NDJSON stream.
- Registration or key: yes. "Using the job posting retrieval interface requires accepting the terms of use and
  contacting the KEHA Centre to obtain the credentials required to use the interface (implementation
  notification)." The technical page adds: "The credentials for using the integration platform and the IP
  addresses openings are provided by the KEHA Center as part of the interface implementation process." The
  notification is a web form (webropolsurveys.com, linked from the page). Free, but by application and tied to
  fixed IP addresses; the Service Provider may refuse activation, giving reasons. Not applied for.
- Cost: no fee is stated; "The API User is responsible for all costs it accumulates from the use of the API."
- Licence or terms (exact wording, with URL - the terms page above): "The user of the retrieval interface can
  be any organisation that wants to display job postings shown in Job Market Finland in their E-services."
  "Job postings displayed in other services through the retrieval interface must always indicate the original
  source (Source: Job Market Finland's customer information system)." "The API User has the right to present
  job postings received through the retrieval interface in its own services and use them as part of the data
  content of its services. As a result, the API User can merge information obtained through the interface with
  information it has obtained from other sources or produced by itself." "Job postings displayed through the
  retrieval interface cannot be forwarded to third parties without separate permission." "Job postings must be
  removed immediately when necessary and removed job postings cannot be stored so that they can still be
  retrieved." "Any data used through the API cannot be used to advertise or market any software or service
  based on the dataset without the KEHA Centre's permission."
- Volume: not stated on the pages read.
- Update cycle: live.
- Seen on 2026-11-28: GET of the technical page -> 200, text/html, 7 125 bytes; GET of the terms -> 200,
  132 098 bytes; GET of the retrieval-interface page -> 200, 122 327 bytes. Three requests to this host; none to
  api.ahtp.fi.
- Caveats: version 1.0 of the interface still exists (its description on request by e-mail); a search summary
  of the Finnish page says the old job-posting interfaces are withdrawn in May 2027 and new openings follow the
  new terms. The terms make this a display licence, not open data: no onward transfer, no archive of removed
  adverts. The public web search is at https://tyomarkkinatori.fi/henkiloasiakkaat/avoimet-tyopaikat (not
  requested).

### Valtiolle.fi (central government jobs)
- Publisher: Palkeet (the Finnish Government Shared Services Centre for Finance and HR) for the Ministry of
  Finance (per search summaries of valtiolle.fi pages).
- Documentation: none found for a feed or API.
- Data or endpoint: https://valtiolle.fi/fi/
- Holds: "Valtiolle.fi kokoaa yhteen kaikki avoimet valtion työpaikat" (brings together all open state jobs).
- Access: web only as far as found. The home page links no RSS, feed, JSON or API address; the site offers
  e-mail search alerts (hakuvahti).
- Registration or key: none to browse.
- Cost: free.
- Licence or terms (exact wording, with URL): https://valtiolle.fi/robots.txt: "User-agent: * Allow: /" with
  two sitemaps on tuotanto.valtiolle.fi. Terms page not read.
- Volume: not stated on the home page.
- Update cycle: continuous.
- Seen on 2026-11-28: www.valtiolle.fi/robots.txt -> 302 to valtiolle.fi; valtiolle.fi/robots.txt -> 200, 129
  bytes; valtiolle.fi/fi/ -> 301; valtiolle.fi/ -> 200, text/html, 231 685 bytes.
- Caveats: a search summary says the State Treasury's own vacancies can be followed "through an rss feed";
  whether that is a feed of valtiolle.fi was not established.

### Kuntarekry (municipal and wellbeing-county jobs)
- Publisher: FCG (Kuntarekry service) - publisher name not confirmed on a page read.
- Documentation: none found for a feed or API.
- Data or endpoint: https://kuntarekry.fi/
- Holds: vacancies of municipalities and wellbeing services counties (not examined).
- Access: web only as far as found; the home page links no RSS, feed, JSON or API address.
- Registration or key: none to browse.
- Cost: free.
- Licence or terms (exact wording, with URL): https://kuntarekry.fi/robots.txt: "User-agent: * Allow: /" with
  sitemaps https://kuntarekry.fi/fi/sivukartta/ and /se/sitemap/. Terms page not read.
- Volume: not stated on the home page.
- Update cycle: continuous.
- Seen on 2026-11-28: www.kuntarekry.fi/robots.txt -> 301; kuntarekry.fi/robots.txt -> 200, 113 bytes;
  kuntarekry.fi/fi/ -> 301; kuntarekry.fi/ -> 200, text/html, 216 620 bytes.
- Caveats: Kuntarekry and Valtiolle.fi serve the same robots.txt pattern and sitemap paths, which suggests one
  platform; not confirmed.

### City of Vantaa - open vacancies REST API
- Publisher: City of Vantaa (Vantaan konsernijohdon ja elinvoiman toimiala).
- Documentation: https://gis.vantaa.fi/rajapinnat/tyopaikat (Finnish); catalogue record
  https://avoindata.suomi.fi/data/dataset/32237f05-0d0e-4eb4-9638-001cd32cfaa5 ; on data.europa.eu
  https://data.europa.eu/data/datasets/32237f05-0d0e-4eb4-9638-001cd32cfaa5
- Data or endpoint: `https://gis.vantaa.fi/rest/tyopaikat/v1` (list of fields with counts),
  `.../v1/kaikki` (all), `.../v1/<field>`, `.../v1/<field>/<id>`; spatial filters by radius or bounding box.
- Holds: id, organisation, occupational field, task title, job key, workplace address, application end date,
  WGS84 coordinates, link to the advert in the city's recruitment system. No description or salary.
- Access: REST API, JSON.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "Creative Commons Attribution 4.0 International" (the catalogue
  record's licence, as carried on data.europa.eu).
- Volume: 65 vacancies on 2026-11-28 (`"ammattiala": "kaikki", "lukumäärä": "65"`).
- Update cycle: live (not stated).
- Seen on 2026-11-28: GET https://gis.vantaa.fi/rajapinnat/tyopaikat -> 200, text/html, 6 702 bytes (the
  documentation); GET https://gis.vantaa.fi/rest/tyopaikat/v1 -> 200, application/json, 907 bytes.
- Caveats: one city only. No comparable dataset for other cities turned up in two data.europa.eu searches
  (country Finland: "avoimet työpaikat", and "työpaikkailmoitukset rekrytointi vacancies jobs API").

### Duunitori
- Publisher: Duunitori Group.
- Documentation: none found for a public API. Terms: https://duunitori.fi/compliance/kayttoehdot ("Päivitetty
  13. marraskuuta 2026").
- Data or endpoint: https://duunitori.fi/tyopaikat ; sitemap https://duunitori.fi/sitemap.xml (not requested).
- Holds: job adverts, own and aggregated (not examined).
- Access: web only. robots.txt closes the site to unnamed agents.
- Registration or key: not applicable.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): https://duunitori.fi/robots.txt begins "User-agent: *
  Disallow: /"; only named agents (AhrefsBot, Baiduspider, Bingbot, DuckDuckBot, Googlebot, Slurp,
  Twitterbot, YandexBot, ChatGPT-User, GPTBot, OAI-SearchBot, Claude-User, Claude-SearchBot, PerplexityBot and
  a few more) are let in, each with "Disallow: /api/". Terms, section "Käytön rajoitukset - Sisällön käyttö"
  (fragments as returned by the fetch tool, which shortens quotations): "Käyttäjä ei saa tallentaa,
  arkistoida, skrapata tai muutoin järjestelmällisesti kopioida Palvelun sisältöä"; "Käyttäjä ei saa käyttää
  Palvelua tai sen sisältöä luodakseen tai tarjotakseen kilpailevaa tai [...] järjestelmällisesti linkittämällä
  sisältöön tai upottamalla sisältöä osaksi toista palvelua tai tuotetta"; "Käyttäjä saa luoda tavallisia
  linkkejä Palvelun julkisesti saatavilla oleville sivuille".
- Volume: not stated on the pages read.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt (curl) -> 200, text/plain, 11 424 bytes; the terms page was read through
  WebFetch only, because robots.txt disallows everything to an unnamed agent such as curl.
- Caveats: the lead "Duunitori has an API" was not confirmed: no documentation was found, `/api/` is disallowed
  to every agent, and the terms forbid systematic copying. No API request was made.

### Jobly.fi and Oikotie Työpaikat
- Publisher: Jobly - Alma Career (publisher not confirmed on a page read); Oikotie - Sanoma (not confirmed).
- Documentation: none found.
- Data or endpoint: https://www.jobly.fi ; https://tyopaikat.oikotie.fi
- Holds: job adverts (not examined).
- Access: web only as far as checked.
- Registration or key: none to browse.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): https://www.jobly.fi/robots.txt: "User-agent: * Crawl-delay:
  10" followed by the usual Drupal allow and disallow lists. Terms pages not read.
- Volume: not stated.
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.jobly.fi/robots.txt -> 200, text/plain, 2 281 bytes. GET
  https://tyopaikat.oikotie.fi/robots.txt -> 301 to https://asunnot.oikotie.fi/ (Oikotie's housing section).
- Caveats: the redirect suggests Oikotie's job section is no longer served at that host; one web search found
  no announcement, so its status is not established.

### Statistics Finland - job vacancy survey and employment service statistics
- Publisher: Tilastokeskus (Statistics Finland); the employment service statistics are produced by the
  Ministry of Economic Affairs and Employment and published in the same database.
- Documentation: terms https://stat.fi/en/about-us/get-to-know-statistics-finland/legislation/terms-of-use ;
  open data https://stat.fi/org/avoindata/index_en.html (not fetched).
- Data or endpoint: PxWeb API `https://pxdata.stat.fi/PXWeb/api/v1/en/StatFin/atp/` (job vacancy survey) and
  `.../StatFin/tyonv/` (employment service statistics).
- Holds: atp - job vacancies by quarter 2013Q1-2026Q3 (tables 11l1, 11my, 11mz, 11n1, 15ia) and by year, by
  establishment size, sector, location and industry. tyonv - monthly 2009M01-2026M10: vacancies at the
  employment service by occupation, province, sector and industry (tables 12ti, 12tt, 12tu, 12tv, 12tw, 12tx,
  12ty, 12tz).
- Access: API (GET for lists and metadata, POST for data); web tables.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): Statistics Finland's open data and public web content are
  "covered by the Creative Commons Attribution 4.0 International licence." Excluded: "Data produced by other
  organisations published on Statistics Finland's website." (terms page above)
- Volume: 10 tables in atp; at least 10 vacancy tables in tyonv.
- Update cycle: atp quarterly (updated 2026-11-19); tyonv monthly (updated 2026-11-20).
- Seen on 2026-11-28: GET .../StatFin/atp/ -> 200, application/json, 1 341 bytes; GET .../StatFin/tyonv/ ->
  200, 13 297 bytes. No data rows requested.
- Caveats: the tyonv tables are another organisation's data, so the exclusion quoted above may apply to them;
  their own terms were not read.

### EURES
- The Job Market Finland terms state: "All job postings published on Job Market Finland are automatically
  added to the European job search portal EURES. This is based on the EURES Regulation binding on EU
  countries".

## Not free or not allowed

- Duunitori: all automated reading by unnamed agents refused in robots.txt; scraping, archiving and systematic
  copying forbidden in its terms; `/api/` disallowed to all.
- Job Market Finland's adverts: free but only under KEHA's terms after approval - no forwarding to third
  parties, no retention of removed adverts, no use to market a service built on the data without permission.
- Third-party scrapers of duunitori.fi are sold on apify.com (seen in search results only).

## Gaps

- The number of live vacancies on Job Market Finland, Duunitori, Valtiolle.fi and Kuntarekry: not read.
- How long KEHA takes to issue credentials, and whether a non-Finnish organisation is accepted: not stated.
- The date the old (version 1.0) interfaces are withdrawn - May 2027 - comes from a search summary of the
  Finnish page, not from a page read.
- Terms of use of Valtiolle.fi, Kuntarekry and Jobly: not read. Whether any of them has an RSS feed: none
  linked from the two home pages read; deeper pages not checked.
- Oikotie Työpaikat: status not established (its host redirects to the housing section).
- Duunitori's full terms text: read only through the fetch tool's summary, with shortened quotations.
- The terms of the employment service statistics (tyonv) as another producer's data: not read.
- LinkedIn, Indeed, Monster and academic or sector boards in Finland: not checked.
