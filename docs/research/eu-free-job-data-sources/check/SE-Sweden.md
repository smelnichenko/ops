# Sweden (SE) - check of the research

The research file has no section on the employer route; it is added in a later pass.

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent, one capped GET or HEAD per URL, one at
a time. No account, key or login. At most three requests per host. No bulk file was downloaded (one HEAD).
Statistics Sweden was not requested: out of purpose. The second table has one verdict per source, as the brief
was simplified during the check.

## Corrections and unverified claims (apply these first)

- CORRECTED: Linköping's feed address in the catalogue record today is
  `https://site106.reachmee.com/Public/rssfeed/external.ashx?id=24&InstallationID=I017&CustomerName=linkoping&lang=SE`
  (`id=24`, not `id=10`).
- ADDITION (claim 25, confirmed): the EURES statement's page has moved: `.../for-arbetsgivare/rekrytera/rekrytera-i-europa` answers
  301 to `.../for-arbetsgivare/kom-igang-med-din-rekrytering/rekrytera-i-europa`. The statement is there.
- ADDITION (claim 10, confirmed; two official figures): the file index says "fler än 7 miljoner annonser"; the dataset page says
  "Datamängden innehåller cirka 6,9 miljoner annonser". The historical API counts 7 842 069 today.
- ADDITION (claim 4, confirmed): a JobSearch record holds more than the research lists, among it `application_contacts`
  and, inside `employer`, `email` and `phone_number` - fields that can carry a contact person's details.
- UNVERIFIED: the overview page https://arbetsformedlingen.se/om-webbplatsen/oppna-data and the GitLab pages -
  not requested (three requests to arbetsformedlingen.se were spent on robots.txt and the EURES page).
- UNVERIFIED: Blocket Jobb's closure on 16 December 2024 - a third-party report; only the dead host name was seen.
- UNVERIFIED: the Statistics Sweden block (PxWeb folders, CC0 against CC BY 4.0) - not requested: statistics.
- UNVERIFIED: the JobStream snapshot endpoint, the JobAd Links file area and the municipal feeds themselves -
  not requested (size, or a vendor host).

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | JobSearch API at `https://jobsearch.api.jobtechdev.se/search` answers without a key or registration | CONFIRMED | GET `...search?limit=1` -> 200, application/json, 9 583 bytes, no credentials sent. The publisher's service page (GET `https://data.arbetsformedlingen.se/dataservice/jobsearch/` -> 200, 6 826 bytes) says "API nyckel eller registrering: Nej" | - |
| 2 | Volume `"total": {"value": 43770}`, `"positions": 72745` | CONFIRMED | Same answer: `total {'value': 43770}`, `positions 72745` | - |
| 3 | One advert published 2026-11-27, description 2 558 characters, link to arbetsformedlingen.se/platsbanken/annonser/<id> | CONFIRMED | `publication_date 2026-11-27T17:04:00`, description text 2 558 characters, `webpage_url https://arbetsformedlingen.se/platsbanken/annonser/31789139` | - |
| 4 | Fields of an advert (id, headline, description, employer, workplace_address, occupation..., application_details, must_have, nice_to_have, webpage_url, source_type, removed, logo_url ...) | CONFIRMED | All named keys present. Also: `access`, `access_to_own_car`, `application_contacts`, `driving_license_required`, `external_id`, `label`, `original_id`, `relevance`, `timestamp`, `workplace_addresses`, `workplace_model`. `application_details` has `email`, `information`, `other`, `reference`, `url`, `via_af`; `employer` has `email`, `name`, `organization_number`, `phone_number`, `url`, `workplace` | Add the fields named here |
| 5 | Swagger at the host root | CONFIRMED | GET `https://jobsearch.api.jobtechdev.se/` -> 200, text/html, 3 811 bytes, title "JobSearch", loads `swagger.json` | - |
| 6 | Licence "Licens: Creative Commons CC0"; access "Publik" (dataset page) | CONFIRMED | GET `https://data.arbetsformedlingen.se/dataset/job-ads/` -> 200, text/html, 23 316 bytes. For JobSearch, the historical API, JobStream, the historical files, JobAd Links and its files: "Licens: Creative Commons CC0 ... Åtkomsträttigheter: Publik"; the page links `http://creativecommons.org/publicdomain/zero/1.0/` | - |
| 7 | JobStream API `https://jobstream.api.jobtechdev.se/v2/stream?updated-after=<timestamp>` answers without a key | CONFIRMED | GET with a timestamp three minutes back -> 200, application/json, 2 bytes (`[]`), no credentials sent | - |
| 8 | JobStream holds all adverts published on Platsbanken and their changes in near real time, filterable by occupation or place | CONFIRMED | Dataset page: "JobStream ger tillgång till alla platsannonser som är publicerade i Platsbanken, inklusive realtidsinformation om förändringar ... t.ex. publiceringar, avpubliceringar eller uppdateringar av annonstexter. Det ger möjlighet att ha en egen kopia av alla platsannonser som publiceras via Arbetsförmedlingen. Det går även att filtrera på yrkes- eller geografiska begrepp." | - |
| 9 | Historical adverts: file area at https://data.jobtechdev.se/annonser/historiska/index.html, one zipped JSON-lines file per year 2006-2025 and per quarter of 2026 (Q1-Q3), folders `berikade` and `jobad_links` | CONFIRMED | GET -> 200, text/html, 17 639 bytes; files `2006.jsonl.zip` ... `2025.jsonl.zip`, `2026-Q1`, `2026-Q2`, `2026-Q3`, folders `berikade`, `jobad_links`; also `2018_municipality_patched.zip` and `2019_municipality_patched.zip` | - |
| 10 | "Datamängden Historiska platsannonser innehåller fler än 7 miljoner annonser som publicerats på Arbetsförmedlingens Platsbanken sedan 2006. Datamängden uppdateras kontinuerligt." | CONFIRMED | Word for word on the file index. The dataset page says "cirka 6,9 miljoner annonser" | Two figures are published |
| 11 | File sizes: 105 620 693 bytes (2006) to 1 488 544 519 (2022); 2025 is 817 792 226; 2026 quarters 176-219 MB | CONFIRMED | Index: 2022 `1488544519`, 2025 `817792226`, Q1 `219077958`, Q2 `200415758`, Q3 `176154439`. HEAD `.../2006.jsonl.zip` -> 200, application/zip, `content-length: 105620693`, `last-modified: Tue, 10 Nov 2026` - offered without a key | - |
| 12 | README.txt points to the GitLab description | CONFIRMED | GET `.../historiska/README.txt` -> 200, text/plain, 242 bytes: "For info about the files, see https://gitlab.com/arbetsformedlingen/job-ads/getting-started-code-examples/historical-ads-info ... YYYY.zip are unprocessed files, in the folder berikade/ you can find files that have been enriched and enhanced." | - |
| 13 | Historical API at https://historical.api.jobtechdev.se: adverts from 2016 on, findable once off Platsbanken, enriched | CONFIRMED | Dataset page: "Apiet innehåller platsannonser från 2016 och framåt för att annonsen ska hittas i Apiet behöver den vara avpublicerad från Platsbanken. Alla platsannonser är berikade med kompetenser, samt innehåller data om distansarbete." GET `https://historical.api.jobtechdev.se/search?limit=0` -> 200, application/json, 162 bytes, no key: `"total": {"value": 7842069}, "positions": 15927165` | - |
| 14 | JobAd Links API `https://links.api.jobtechdev.se/joblinks`: id, headline, brief, employer, workplace_addresses, occupation_group, occupation_field, publication_date, source_links; no full description; CC0; no key | CONFIRMED | GET `...joblinks?limit=1` -> 200, application/json, 1 129 bytes, no key; exactly those nine keys; `brief` 206 characters; `source_links` label "offentligajobb.se" | - |
| 15 | JobAd Links volume `"total": {"value": 45444}` | CONFIRMED | Same answer | - |
| 16 | Which sites JobAd Links covers is not on the pages read | NOT DISPROVED | Not on the dataset page | - |
| 17 | Municipal vacancy feeds on the data portal: Linköping and Tidaholm with "Creative Commons Attribution 4.0 International", Vingåker with no licence | CONFIRMED | data.europa.eu hub search, country se: `https-linkoping-entryscape-net-store-1-resource-12` "Lediga jobb" (XML, CC BY 4.0, "alla lediga tjänster inom Linköpings kommun"), `https-catalog-tidaholm-se-store-2-resource-28` (XML, CC BY 4.0), `https-free-entryscape-com-store-510-resource-11` Vingåker "Lediga jobb (RSS)" (`https://www.vingaker.se/ledigajobb/rss`, no licence). No other municipality's vacancy feed among the first 30 of 2 070 results | - |
| 18 | Linköping's feed is `...external.ashx?id=10&InstallationID=I017&CustomerName=linkoping&lang=SE` | CORRECTED | The record's access address has `id=24` | `id=24` |
| 19 | JobbSafari robots.txt (200, 288 bytes): "User-agent: * Allow: / Disallow: /api Disallow: /monitoring Disallow: /lediga-jobb*yrke=* ..."; sitemap | CONFIRMED | GET `https://jobbsafari.se/robots.txt` -> 200, text/plain, 288 bytes; also "Disallow: /lediga-jobb*?*&*&*&*" and "Host: https://jobbsafari.se" | - |
| 20 | JobbSafari is now under Duunitori Group | CONFIRMED | Duunitori's terms (read today, see the Finland check): "Se, mikä Duunitori Groupin yhtiö on sopimusosapuoli ... Duunitori Oy Suomessa, JobbSafari AB Ruotsissa ja Jobbland AS Norjassa." | - |
| 21 | Ledigajobb.se robots.txt (200, 116 bytes): "User-Agent: * Disallow: /sok?* Disallow: /jobb-red/* Disallow: /cdn-cgi/"; sitemap | CONFIRMED | GET `https://ledigajobb.se/robots.txt` -> 200, text/plain, 116 bytes, those lines | - |
| 22 | `jobb.blocket.se` does not resolve | CONFIRMED | curl: "Could not resolve host: jobb.blocket.se" | - |
| 23 | Schibsted announced Jobbsafari and Blocket Jobb would close on 16 December 2024 | UNVERIFIED | Third-party report, not re-read | - |
| 24 | Statistics Sweden: PxWeb folders AM0701A-D, tables TAB6400 ..., CC0 on the catalogue | UNVERIFIED | Not requested: statistics. The hub search answer does list TAB6400 "Kvartal 2024K2 - 2026K2", TAB6402, TAB6403, TAB6424 with `creativecommons.org/publicdomain/zero/1.0/` | - |
| 25 | EURES: an advert published in Platsbanken shows up automatically on the EURES portal | CONFIRMED | GET `https://arbetsformedlingen.se/for-arbetsgivare/rekrytera/rekrytera-i-europa` -> 301 to `https://arbetsformedlingen.se/for-arbetsgivare/kom-igang-med-din-rekrytering/rekrytera-i-europa` -> 200, 98 445 bytes: "När du publicerar en annons i Platsbanken visas den automatiskt i Eures-portalen." | The page has moved |
| 26 | Nothing of the employment service's vacancy data is paid or closed; the only partner API is for writing and needs registration | CONFIRMED | Dataset page: "Direct Transferred Job Posting är ett api för att publicera platsannonser från externa system ... Api:et är ett partner-api och kräver registrering för åtkomst." All reading services: "Publik" | - |
| 27 | Rate limits are not stated on the pages read | NOT DISPROVED | None on the dataset page or on the JobSearch service page; no rate-limit header in the JobSearch answer | - |
| 28 | https://arbetsformedlingen.se/robots.txt answers 301 to a download URL | CONFIRMED | GET -> 301, Location `https://arbetsformedlingen.se/download/18.47a458fb16df81b91335c6e/1777983016986/robots.txt` (not followed) | - |
| 29 | The APIs live on jobtechdev.se hosts while the catalogue is on data.arbetsformedlingen.se | CONFIRMED | As seen in claims 1, 6, 7, 13, 14 | - |
| 30 | Overview page https://arbetsformedlingen.se/om-webbplatsen/oppna-data; code on gitlab.com/arbetsformedlingen | UNVERIFIED | Not requested | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (deciding clause if "no") |
|---|---|---|
| JobSearch API (Platsbanken adverts) | yes | CC0, public, "API nyckel eller registrering: Nej"; full text, `webpage_url` and `application_details` (e-mail, url, via Arbetsförmedlingen) in each record |
| JobStream API | yes | CC0, public, no key; the publisher says it "ger möjlighet att ha en egen kopia av alla platsannonser" |
| Historical adverts (files and API) | yes | CC0, public, no key; old adverts, so of use for looking back, not for applying |
| JobAd Links API | yes | CC0, public, no key; gives a short text and the link; the full advert stays on the source site, whose own terms were not read |
| Municipal feeds (Linköping, Tidaholm) | yes | Catalogue licence CC BY 4.0; the feeds themselves were not requested |
| Municipal feed (Vingåker) | unclear | No licence in the catalogue record; feed not requested |
| JobbSafari | unclear | Its own terms page was not read. robots.txt allows the site except `/api` and filtered lists. Duunitori Group's terms, which name JobbSafari AB as the party in Sweden, forbid scraping ("Käyttäjä ei saa tallentaa, arkistoida, skrapata tai muutoin järjestelmällisesti kopioida Palvelun sisältöä"); whether jobbsafari.se publishes the same terms was not checked |
| Ledigajobb.se | unclear | Terms not read; robots.txt disallows only `/sok?*`, `/jobb-red/*`, `/cdn-cgi/` |
| Blocket Jobb | no | Not there: `jobb.blocket.se` does not resolve |
| Statistics Sweden's vacancy tables | no | Counts only, no adverts |

## Found beyond the research

- The publisher's service page states it outright: "API nyckel eller registrering: Nej" (JobSearch,
  https://data.arbetsformedlingen.se/dataservice/jobsearch/). Sister pages exist for `/dataservice/jobstream/`,
  `/dataservice/historiska_annonser/`, `/dataservice/jobad-links/` (not requested).
- The historical API answers without a key and holds 7 842 069 adverts (15 927 165 positions) today.
- JobSearch records carry `application_contacts` and employer e-mail and phone fields: personal data of contact
  persons may be in the open data. Nothing of it was copied.
- The dataset page names the purpose JobStream is meant for: keeping one's own copy of all adverts.
- Still unchecked, as in the research: a central-government vacancy portal with a feed, offentligajobb.se, the
  terms of JobbSafari and Ledigajobb.se, Arbetsförmedlingen's own monthly statistics.
