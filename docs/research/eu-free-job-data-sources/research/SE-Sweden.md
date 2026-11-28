# Sweden (SE) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (one capped GET per URL), the Claude Code
WebFetch tool with its own default client, and web search. No account, key or login was used.

## Takeaway

Sweden is the open case. Arbetsförmedlingen publishes every advert of its job bank Platsbanken as open data
under Creative Commons CC0: the JobSearch API (43 770 adverts, 72 745 positions today), the JobStream API of
changes, yearly bulk files of every advert since 2006 (more than 7 million), and a historical-ads API. All
answered without a key or registration. A further CC0 service, JobAd Links, lists adverts found on other Swedish
job sites (45 444 today) with a short text and a link back. Statistics Sweden's vacancy tables are CC0 too, and
several municipalities publish their vacancies as RSS on the national data portal. What is missing is small:
full texts of adverts that exist only on commercial boards, and rate limits, which are not stated on the pages
read.

## Sources

### Arbetsförmedlingen - Platsbanken adverts: JobSearch API
- Publisher: Arbetsförmedlingen (Swedish Public Employment Service); its open-data work was branded JobTech.
- Documentation: dataset page https://data.arbetsformedlingen.se/dataset/job-ads/ ; overview
  https://arbetsformedlingen.se/om-webbplatsen/oppna-data ; code and examples https://gitlab.com/arbetsformedlingen
- Data or endpoint: `https://jobsearch.api.jobtechdev.se/search` (Swagger at the host root).
- Holds: per advert - id, headline, description (text), employer (name and more), workplace_address
  (municipality, region, country), occupation, occupation_group, occupation_field (taxonomy concept ids and
  labels), employment_type, duration, working_hours_type, scope_of_work, salary_type, salary_description,
  number_of_vacancies, publication_date, last_publication_date, application_deadline, application_details,
  must_have and nice_to_have (skills, languages), driving_license, experience_required, webpage_url,
  source_type, removed and removed_date, logo_url.
- Access: API (JSON); free-text and structured search.
- Registration or key: none. The call below was answered with no key; the dataset page lists access as "Publik".
- Cost: free.
- Licence or terms (exact wording, with URL): "Licens: Creative Commons CC0"
  (https://data.arbetsformedlingen.se/dataset/job-ads/); the record on data.europa.eu carries
  http://creativecommons.org/publicdomain/zero/1.0/ for this distribution.
- Volume: `"total": {"value": 43770}`, `"positions": 72745` on 2026-11-28.
- Update cycle: live.
- Seen on 2026-11-28: GET https://jobsearch.api.jobtechdev.se/search?limit=1 -> 200, application/json, 9 583
  bytes, one advert (published 2026-11-27, description 2 558 characters, link to
  arbetsformedlingen.se/platsbanken/annonser/<id>).
- Caveats: rate limits are not stated on the pages read. The APIs still live on jobtechdev.se hosts while the
  catalogue has moved to data.arbetsformedlingen.se; host names may change.

### Arbetsförmedlingen - JobStream API
- Publisher: Arbetsförmedlingen.
- Documentation: https://data.arbetsformedlingen.se/dataset/job-ads/ (section "Datatjänst JobStream").
- Data or endpoint: `https://jobstream.api.jobtechdev.se/v2/stream?updated-after=<timestamp>` (changes) and a
  snapshot of all current adverts on the same host (not requested: large).
- Holds: all adverts currently published on Platsbanken and their changes in near real time - publications,
  removals, text updates - filterable by occupation or place (per the dataset page).
- Access: API (JSON).
- Registration or key: none (answered without one).
- Cost: free.
- Licence or terms (exact wording, with URL): "Licens: Creative Commons CC0" (same page).
- Volume: the whole live stock (see JobSearch).
- Update cycle: real time.
- Seen on 2026-11-28: GET .../v2/stream?updated-after=<three minutes earlier> -> 200, application/json, 2
  bytes (`[]`: no change in that window).
- Caveats: the snapshot endpoint and the fields of a stream record were not examined.

### Arbetsförmedlingen - historical adverts (bulk files and API)
- Publisher: Arbetsförmedlingen.
- Documentation: https://data.jobtechdev.se/annonser/historiska/README.txt ->
  https://gitlab.com/arbetsformedlingen/job-ads/getting-started-code-examples/historical-ads-info
- Data or endpoint: file area https://data.jobtechdev.se/annonser/historiska/index.html (also listed as
  https://data.arbetsformedlingen.se/annonser/historiska/index.html); API https://historical.api.jobtechdev.se
- Holds: "Datamängden Historiska platsannonser innehåller fler än 7 miljoner annonser som publicerats på
  Arbetsförmedlingens Platsbanken sedan 2006. Datamängden uppdateras kontinuerligt." One zipped JSON-lines
  file per year 2006-2025 and per quarter for 2026 (2026-Q1, Q2, Q3), plus a folder `berikade` of enriched
  files and a folder `jobad_links`. The API holds adverts from 2016 on, each findable once it has left
  Platsbanken, with enriched skills and remote-work information (per the dataset page).
- Access: bulk download; API.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "Licens: Creative Commons CC0"
  (https://data.arbetsformedlingen.se/dataset/job-ads/).
- Volume: files from 105 620 693 bytes (2006) to 1 488 544 519 bytes (2022); 2025 is 817 792 226 bytes; the
  2026 quarters are 176-219 MB each.
- Update cycle: "uppdateras kontinuerligt"; in practice a file per closed quarter.
- Seen on 2026-11-28: GET of the index -> 200, text/html, 17 639 bytes; GET README.txt -> 200, 242 bytes. No
  data file was downloaded.
- Caveats: the files are large (0.1 to 1.5 GB each); the historical API was not called.

### Arbetsförmedlingen - JobAd Links (adverts on other job sites)
- Publisher: Arbetsförmedlingen.
- Documentation: https://data.arbetsformedlingen.se/dataset/job-ads/ (section "Datatjänst JobAd Links").
- Data or endpoint: `https://links.api.jobtechdev.se/joblinks` ; files
  https://data.arbetsformedlingen.se/annonser/jobtechlinks/index.html (not requested).
- Holds: id, headline, brief (a short text, 206 characters in the record seen), employer name,
  workplace_addresses (municipality, region, country with concept ids), occupation_group, occupation_field,
  publication_date, and source_links (label and URL of the advert on the site it comes from; the record seen
  pointed to offentligajobb.se). No full description.
- Access: API (JSON) and files.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "Licens: Creative Commons CC0" (same page).
- Volume: `"total": {"value": 45444}` on 2026-11-28.
- Update cycle: not stated.
- Seen on 2026-11-28: GET https://links.api.jobtechdev.se/joblinks?limit=1 -> 200, application/json, 1 129
  bytes, one record.
- Caveats: which sites are covered, and on what agreement with them, is not on the pages read. The full text
  stays on the source site, whose own terms apply to reading it.

### Municipal vacancy feeds on the national data portal
- Publisher: individual municipalities, e.g. Linköping, Vingåker, Tidaholm.
- Documentation: the records on https://www.dataportal.se (harvested to data.europa.eu, catalogue "oppnadata"),
  e.g. https://data.europa.eu/data/datasets/https-linkoping-entryscape-net-store-1-resource-12
- Data or endpoint: for Linköping an RSS/XML feed of its recruitment system:
  `https://site106.reachmee.com/Public/rssfeed/external.ashx?id=10&InstallationID=I017&CustomerName=linkoping&lang=SE`
- Holds: the municipality's own vacancies ("alla lediga tjänster inom Linköpings kommun"), updated as posts are
  advertised.
- Access: RSS/XML feed.
- Registration or key: none stated.
- Cost: free.
- Licence or terms (exact wording, with URL): Linköping and Tidaholm: "Creative Commons Attribution 4.0
  International"; Vingåker: no licence in the record.
- Volume: one employer each.
- Update cycle: continuous.
- Seen on 2026-11-28: the catalogue records only (one data.europa.eu search); the feeds themselves were not
  requested (reachmee.com is a recruitment-system vendor host).
- Caveats: only three municipalities turned up in the one search made; the same adverts are normally in
  Platsbanken too.

### Commercial boards
- JobbSafari (jobbsafari.se; per a press release seen in search results, now under Duunitori Group, with
  Jobbland merged into it): https://jobbsafari.se/robots.txt -> 200, 288 bytes: "User-agent: * Allow: /
  Disallow: /api Disallow: /monitoring Disallow: /lediga-jobb*yrke=* Disallow: /lediga-jobb*ort=* Disallow:
  /lediga-jobb*kategori=* Disallow: /lediga-jobb*foretag=*", sitemap https://jobbsafari.se/sitemap.xml. No
  official read API or feed found; terms not read.
- Ledigajobb.se: https://ledigajobb.se/robots.txt -> 200, 116 bytes: "User-Agent: * Disallow: /sok?*
  Disallow: /jobb-red/* Disallow: /cdn-cgi/", sitemap https://ledigajobb.se/sitemap.xml. No official read API
  or feed found; terms not read.
- Blocket Jobb: `jobb.blocket.se` does not resolve (curl: "Could not resolve host"). A Finnish-language source
  seen in search results says Schibsted announced that Jobbsafari and Blocket Jobb would close on 16 December
  2024 and that Jobbsafari continues under Duunitori Group. Treated as closed; not confirmed on a Blocket page.
- Indeed, LinkedIn, StepStone: not checked (EU-wide layer).

### Statistics Sweden - job openings and vacancies
- Publisher: Statistikmyndigheten SCB.
- Documentation: terms https://www.scb.se/about-website (not fetched; named in a search summary as stating
  CC BY 4.0 for the site, while the table records carry CC0 - see Caveats).
- Data or endpoint: PxWeb API `https://api.scb.se/OV0104/v1/doris/en/ssd/AM/AM0701/` with the folders AM0701A
  "Job openings and vacancies", AM0701B "Recruitment and vacancy rate", AM0701C "Recruitment time", AM0701D
  "Old tables, not updated". Tables on the data portal include TAB6400 (whole economy by sector, quarters
  2024K2-2026K2), TAB6403 (business sector by industry SNI 2007), TAB6402 (by number of employees), TAB6424 (by
  region and sector).
- Holds: quarterly numbers of job openings and vacancies from an employer survey.
- Access: API (GET for lists and metadata, POST for data), JSON.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): the table records on data.europa.eu (e.g.
  https://data.europa.eu/data/datasets/https-statistikdatabasen-scb-se-dataset-tab6400) carry
  http://creativecommons.org/publicdomain/zero/1.0/.
- Volume: about ten current tables.
- Update cycle: quarterly (TAB6400 modified 2026-08-28).
- Seen on 2026-11-28: GET of the AM0701 folder -> 200, application/json, 246 bytes.
- Caveats: the series was rebuilt in 2024 (old tables end 2024K1, new ones start 2024K2). A search summary says
  scb.se's own terms page names CC BY 4.0; the catalogue says CC0; the terms page was not read to settle it.

### EURES
- Arbetsförmedlingen's employer pages say an advert published in Platsbanken shows up automatically on the
  EURES portal (search summary of https://arbetsformedlingen.se/for-arbetsgivare/rekrytera/rekrytera-i-europa ;
  the page itself was not fetched).

## Not free or not allowed

- Nothing of the public employment service's vacancy data is paid or closed. Partner APIs exist only for
  writing: the "Direct Transferred Job Posting API" lets recruitment systems publish adverts to Platsbanken and
  needs registration with Arbetsförmedlingen.
- JobbSafari disallows `/api` and filtered listing URLs to robots; Ledigajobb.se disallows its search URLs.
  Their terms of use were not read.

## Gaps

- Rate limits and fair-use rules of the JobTech APIs: not stated on the pages read; the service pages under
  data.arbetsformedlingen.se/dataservice/ were not fetched.
- https://arbetsformedlingen.se/robots.txt answered 301 to a download URL and was not followed.
- A portal of central-government vacancies with a feed (Arbetsgivarverket) and the private offentligajobb.se:
  not checked.
- Terms of use of JobbSafari and Ledigajobb.se: not read. Blocket Jobb's closure: from a third party only.
- Which sites JobAd Links covers: not established.
- SCB's licence wording on its own terms page: not read.
- Arbetsförmedlingen's own statistics (monthly vacancy counts): not looked for.
