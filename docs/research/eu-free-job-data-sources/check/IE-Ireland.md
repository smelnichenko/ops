# Ireland (IE) - check of the research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`), no added headers, no
`-L`, every transfer capped (`--max-filesize 2000000 -m 30`), one request at a time. Web search (run by the
search service, not from this address) only to find page addresses. No account, key or login.
Requests per host: opendata.cro.ie 4, data.gov.ie 3, www.publicjobs.ie 3, jobsireland.ie 2, www.irishjobs.ie 2,
www.jobs.ie 2, www.rezoomo.com 2, and 1 each to data.europa.eu, docs.hirehive.com, www.oleeo.com,
intercom.help (404), occupop.com (301), www.occupop.com (301). Indeed and LinkedIn were read once today for the
France check. No employer's board and no vendor data endpoint was requested; publicjobs.tal.net was not
requested.

The research file has the section "Through the employers"; it is checked below (claims 13-25).

## Corrections and unverified claims (apply these first)

- CORRECTED (claim 6): publicjobs.ie's terms are at https://www.publicjobs.ie/en/terms-conditions and were read:
  "This site is for your personal, non-commercial use. You may not modify, copy, distribute, transmit, display,
  perform, reproduce, publish, license, create derivative works from, transfer, or sell any information [...]
  provided that you may download, reproduce, and retransmit publicjobs Information solely for non-commercial
  purposes within your organisation."; and under "Copyright": "The material may be downloaded to file or printer
  for personal use only." No clause on robots, scripts or scraping.
- CORRECTED (claim 9): IrishJobs.ie's and Jobs.ie's terms are at https://www.irishjobs.ie/recruiters/terms/ and
  https://www.jobs.ie/recruiters/recruitment-news/terms/ and were read. They have no clause on scraping, robots
  or automated reading. "4.7.1 You may only use the Website and/or the Website Services for lawful purposes when
  seeking employment or help with your career, or when recruiting staff."; "13 COPYRIGHT STATEMENT [...] Content
  on the IrishJobs.ie website can be downloaded for personal non-commercial use." The Belgian Stepstone wording
  the research borrowed ("individual job search by natural persons", the scraping clause) is not in them.
- CORRECTED (claim 15): the CRO record has one resource, the CSV; no data dictionary is among its resources.
- CORRECTED (claim 16): the CRO dataset does carry the high-value-dataset label: `high_value_dataset` "true",
  `hvd_category` `http://data.europa.eu/bna/c_a9135398`, `applicable_legislation`
  `http://data.europa.eu/eli/reg_impl/2023/138/oj`.
- CORRECTED (claim 21): HireHive's own documentation describes a "Public Jobs API":
  `GET https://<account>.hirehive.com/api/v2/jobs`, "Get a paginated list of published jobs"; the examples send
  no credentials and the specification lists no security scheme. The research had left the key requirement open.
- CORRECTED (claim 23): Rezoomo was read on its own site: "Rezoomo Ireland Limited, Company No. 545025, whose
  registered address is 2nd Floor, 76 Grand Parade, Cork". Its home page links employers' job pages on
  rezoomo.com itself (`/company/<name>/jobs/`, `/job/<number>/`). Its terms forbid automated collection: "You
  must not conduct any systematic or automated data scraping, data mining, data extraction or data harvesting,
  or other systematic or automated data collection activity, by means of or in relation to the Services."
- UNVERIFIED, not sourced - drop: **Occupop** - its help article answers 404 and its site answers 301 to another
  site (occupop.com -> www.occupop.com -> https://cezannehr.com/, not followed). No page of its own was read.
- UNVERIFIED: that tal.net is Oleeo's system - Oleeo's own home page was read and names neither tal.net nor an
  API or feed; the link rests on third parties. That Oleeo is a UK vendor and HireHive an Irish one - not on the
  pages read.
- UNVERIFIED: JobsIreland's publisher, terms, fields and volume - every address requested returns the same
  script shell. The fields and feeds of publicjobs.tal.net - not requested (a vendor-hosted board).
- UNVERIFIED: HireHive's old blog address redirecting to the home page - not re-requested. The employer
  directories named from memory (IDA Ireland, Enterprise Ireland, TechIreland) - not requested. The EURES count
  of 999 (EU-wide file). The scrapers on apify.com and the feed on AWS Marketplace.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | The national portal answers a search for job vacancies with two statistics tables only: "EHQ16 - Job Vacancies" and "EHQ59 - Job Vacancies" (CC-BY-4.0), `count` 2, 13,319 bytes | CONFIRMED | GET `https://data.gov.ie/api/3/action/package_search?q=job%20vacancies` -> 200, application/json, 13,319 bytes: `count` 2, both from the Central Statistics Office, `license_id` CC-BY-4.0 | - |
| 2 | Ireland publishes no open feed, API or dataset of individual vacancies | NOT DISPROVED | Second search GET `...package_search?q=vacancies&rows=30` -> 200, 196,036 bytes, 50 results, 30 read: all Central Statistics Office tables (job vacancies, housing vacancy rates). EU portal: GET `https://data.europa.eu/api/hub/search/search?q=job vacancies&filter=dataset&facets={"country":["ie"]}&limit=15` -> 200, 40,339 bytes, 178 matches, 15 read: statistics only | - |
| 3 | JobsIreland returns its application shell even for `/robots.txt` (200, text/html, 38,436 bytes) | CONFIRMED | GET https://jobsireland.ie/robots.txt -> 200, text/html, 38,436 bytes: an HTML page with an empty `<title>` and scripts. GET https://jobsireland.ie/en-US/eures-terms-and-conditions -> 200, 38,436 bytes, byte for byte the same body | - |
| 4 | No documentation of a feed, API or dataset of JobsIreland exists | NOT DISPROVED | The two portal searches (claims 1-2); no page of the site could be read | - |
| 5 | publicjobs.ie hands its job search to a vendor-hosted system, `https://publicjobs.tal.net/vx/.../candidate/jobboard/vacancy/3/adv/`; "Register and set up job alerts on our new recruitment [system]"; robots.txt disallows only system directories | CONFIRMED | GET https://www.publicjobs.ie/en/ -> 200, text/html, 77,596 bytes: links to `publicjobs.tal.net/.../candidate/jobboard/vacancy/3/adv/` (and `/6/adv/`, `/7/adv/`), to its register and login pages; "Register and set up job alerts on our new recruitment platform." GET https://www.publicjobs.ie/robots.txt -> 200, text/plain, 244 bytes: Allow lines for scripts, styles and images; "Disallow: /bin/", "/cache/", "/cli/", "/includes/", "/language/", "/layouts/", "/libraries/", "/tmp/" | - |
| 6 | publicjobs.ie's terms were not read | CORRECTED | GET https://www.publicjobs.ie/en/terms-conditions -> 200, text/html, 55,163 bytes: the passages quoted above; "The material featured on this site is subject to Government copyright"; no word robot, automat, scrap, crawl or spider | Personal, non-commercial use; download for personal use allowed; silent on programs. |
| 7 | IrishJobs.ie and Jobs.ie serve the same robots.txt but for the site name ("last updated 25 03 26"): for all agents "Disallow: /jobs/permanent", "Disallow: /*&page=", "Disallow: /*/apply?", "Disallow: /*/apply$", "Disallow: /*.ashx$", "Disallow: /Login/", "Disallow: /savedjobs"; named search engines get "Allow: /job/", "Allow: /jobs/" | CONFIRMED | GET https://www.irishjobs.ie/robots.txt -> 200, text/plain, 6,236 bytes; GET https://www.jobs.ie/robots.txt -> 200, 6,191 bytes: all lines in both; apart from the site name the two differ in three comment lines only | - |
| 8 | The two sites belong to The Stepstone Group | CONFIRMED | IrishJobs.ie terms, 8.1.8: "The Stepstone Group Ireland Recruit Limited Database (Group made up of IrishJobs.ie, Jobs.ie and NIJobs.com)" | - |
| 9 | Their terms were not read (503 on a guessed address); the same group's Belgian terms limit the service to "the individual job search by natural persons" and forbid scraping for other purposes | CORRECTED | GET https://www.irishjobs.ie/recruiters/terms/ -> 200, text/html, 128,598 bytes ("Terms of Use"); GET https://www.jobs.ie/recruiters/recruitment-news/terms/ -> 200, 133,088 bytes ("Terms and Conditions"): clauses 4.7.1-4.7.3 and 13 as quoted above; "4.7.3 You are prohibited from using or removing any Content from the Website by any means for any purposes deemed to be in competition with our business activities"; no word scrap, robot, spider, crawl or harvest in either | The Irish terms are silent on programs, allow download for personal non-commercial use and forbid use in competition with the sites. |
| 10 | Indeed and LinkedIn forbid automated reading | CONFIRMED | Terms read once today for the France check (200, 665,417 and 184,070 bytes; clauses as quoted). ie.indeed.com not requested | - |
| 11 | CSO tables EHQ16 and EHQ59 are open under CC BY 4.0 | CONFIRMED | Claim 1; both modified 2026-11-28 | - |
| 12 | No partner or paid vacancy feed from the State was found | NOT DISPROVED | Not searched further | - |
| 13 | CRO publishes every company's basic record as a daily CSV and a keyless API under CC BY 4.0: "license_id": "CC-BY-4.0", "frequency": "Daily", record modified 2026-11-17 | CONFIRMED | GET https://opendata.cro.ie/api/3/action/package_show?id=companies -> 200, application/json, 4,467 bytes: title "Company Records", `license_id` CC-BY-4.0, "Creative Commons Attribution 4.0", `frequency` Daily, `metadata_modified` 2026-11-17T04:00:49, `isopen` true; resource note "The Company Records resource is a daily snapshot of the main details of all registered companies"; download address as in the research | - |
| 14 | 829,416 records; fields `company_num`, `company_name`, `company_status` (+ code and date), `company_type` (+ code), `company_reg_date`, `company_address_1` to `_4`, `eircode`, `comp_dissolved_date`, `last_ar_date`, `nard`, `last_accounts_date`, `nace_v2_code`, `princ_object_code`, name and type effective dates; no website, e-mail, phone or head count; the first record is a company dissolved in 2000 | CONFIRMED | GET `https://opendata.cro.ie/api/3/action/datastore_search?resource_id=3fef41bc-b8f4-4b10-8434-ce51c29b1bba&limit=1` -> 200, 4,278 bytes, no key sent: `total` 829416; the 21 fields exactly (plus `_id`); first record status "Dissolved", dissolved 2000-06-30 | - |
| 15 | A data dictionary is among the dataset's resources | CORRECTED | Record: `num_resources` 1 - "Company Records", CSV | No data-dictionary resource in the record; the field list comes from the API. |
| 16 | Whether the dataset carries the high-value-dataset label was not seen | CORRECTED | Record: `high_value_dataset` "true", `hvd_category` `http://data.europa.eu/bna/c_a9135398`, `applicable_legislation` Regulation (EU) 2023/138 | Labelled a high-value dataset. |
| 17 | `nace_v2_code` is empty in the one record seen and the older `princ_object_code` is filled; coding may be uneven | CONFIRMED | First record: `nace_v2_code` empty, `princ_object_code` "74.84". Three more rows (filter `company_status` "Normal", 894 rows): one with `nace_v2_code` 4120, two without | - |
| 18 | A separate "Financial Statements" dataset exists on the same portal | CONFIRMED | GET https://opendata.cro.ie/api/3/action/package_search?rows=20 -> 200, 10,336 bytes: two datasets - "Company Records" and "Financial Statements" (three CSV resources: 2022, 2023, 2024), both CC-BY-4.0 and flagged high-value | - |
| 19 | publicjobs.ie's job board runs on Oleeo's tal.net (vendor from memory; no vendor page read) | UNVERIFIED | The link to publicjobs.tal.net is confirmed (claim 5). GET https://www.oleeo.com/ -> 200, text/html, 157,788 bytes: "Recruitment technology provider Oleeo"; no word tal.net, API, feed, RSS or XML | Oleeo exists and documents no public feed on the page read; that tal.net is its system is not on that page. |
| 20 | HireHive's old blog address now redirects to the home page | UNVERIFIED | Not re-requested | - |
| 21 | HireHive: "every company that has a HireHive account will have a custom API URL"; whether it needs a key is not confirmed | CORRECTED | GET https://docs.hirehive.com/website-integration/jobs-api/list -> 200, text/html, 246,437 bytes: "Public Jobs API", "Get a paginated list of published jobs", `GET /api/v2/jobs` on `https://hirehive-testing-account.hirehive.com`; request samples without any credential; `"security":[]` in the embedded specification; also "Get job by id", "Get categories", "Hosted careers page", "Iframe" | A keyless public jobs API per account is documented by the vendor. |
| 22 | Occupop: Irish vendor (from memory); feed not found | UNVERIFIED | GET https://intercom.help/occupop/en/articles/8867619-choosing-the-best-careers-page-integration-option -> 404 ("Not found"). GET https://occupop.com/all-features -> 301 -> https://www.occupop.com/(all-features) -> 301 to https://cezannehr.com/ (another site; not followed) | not sourced - drop. |
| 23 | Rezoomo: Irish vendor (from memory); feed not found | CORRECTED | GET https://www.rezoomo.com/ -> 200, text/html, 178,990 bytes: a page titled Rezoomo, "Recruitment Software & Talent Acquisition Platform"; links to `/company/<name>/jobs/` and `/job/<number>/` pages on the same host. GET https://www.rezoomo.com/terms-of-use/ -> 200, 105,783 bytes ("Terms of Use 19.05.2019"): the company and the data-mining clause quoted above | Irish (Cork). Employers' job pages are public on rezoomo.com; no feed or API is documented on the pages read; automated collection is forbidden by the terms. |
| 24 | Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Recruitee, Personio, Workday: international vendors, documentation in the EU-wide file; not established for Ireland | CONFIRMED | One documentation page per vendor read today for the France check (claims 54-61 there). Use in Ireland: no source | - |
| 25 | No free source gives links to employers' own pages; employer directories known from memory only | NOT DISPROVED | Not searched; the CRO fields hold no website (claim 14) | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (the deciding clause if "no") |
|---|---|---|
| JobsIreland | unclear | Nothing could be read: every address returns the same script shell, the terms address included |
| publicjobs.ie | unclear | "This site is for your personal, non-commercial use"; download "for personal use only"; silent on programs; the vacancies sit on publicjobs.tal.net, not requested |
| CSO job-vacancy tables | no | Counts only, no adverts |
| IrishJobs.ie | unclear | Terms silent on programs; "Content on the IrishJobs.ie website can be downloaded for personal non-commercial use"; robots.txt closes paged, filtered and apply addresses |
| Jobs.ie | unclear | Same terms and robots.txt as IrishJobs.ie |
| Indeed | no | Forbidden: "Utiliser un système automatisé (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données" (terms of 1 April 2026, read in French) |
| LinkedIn | no | "Use bots or other unauthorized automated methods to access the Services" |
| CRO - Company Records (bulk and API) | yes | CC BY 4.0, no key; every company with name, number, status, type, address and activity code; no website |
| CRO - Financial Statements 2022-2024 | yes | CC BY 4.0 on the same portal; files not opened |
| Employers' boards on HireHive | unclear | Vendor documents a keyless "Public Jobs API" per account; no licence stated; use in Ireland not established |
| Employers' job pages on Rezoomo | no | "You must not conduct any systematic or automated data scraping, data mining, data extraction or data harvesting, or other systematic or automated data collection activity" |
| publicjobs.tal.net (vendor-hosted board) | unclear | Not requested; no vendor documentation of a feed found |

## Found beyond the research

- **Rezoomo is a job site as well as a vendor**: its home page lists live job pages of Irish employers (health
  service, defence forces, education boards, by the link texts). A web search result (careerhub.hse.ie, not
  requested) says the health service's career hub uses Rezoomo for job alerts. Its terms close it to programs.
- **The CRO portal holds exactly two datasets**, both high-value datasets under Regulation (EU) 2023/138:
  "Company Records" and "Financial Statements" (2022, 2023, 2024).
- **The company file was last changed on 2026-11-17** (`last_modified` 2026-11-17T04:00:49) although its
  frequency is "Daily" - eleven days before this check.
- **Status values are not uniform**: the filter `company_status` "Normal" matches only 894 of 829,416 rows; a
  program must look at the status codes before selecting live companies.
- **publicjobs.ie links three boards** on the vendor system (`/vacancy/3/`, `/6/`, `/7/`), not one.
- **Occupop's address now leads to Cezanne HR** (cezannehr.com); the product may have changed hands.
