# Ireland (IE) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`, no added headers, one
capped GET per URL), and web search for finding pages. No account, key or login was used. Requests made, per
host: opendata.cro.ie 2 (open data portal API), www.publicjobs.ie 2, www.irishjobs.ie 2 (the second answered
503), and 1 each to jobsireland.ie, www.jobs.ie, data.gov.ie, hirehive.com and www.hirehive.com (both
redirects). Indeed and LinkedIn were not requested again (terms read once for the France file).

Per the brief's simplification of 28 November, each source has one line "Usable for own job search" in place
of the four separate readings of its terms.

## Takeaway

Ireland publishes no open feed, API or dataset of vacancies: the national open data portal answers a search
for job vacancies with two statistics tables only. The State's job site JobsIreland is a script-rendered
application that returns the same page shell even for `/robots.txt`, and publicjobs.ie (public-sector
recruitment) hands its job search to a vendor-hosted system (publicjobs.tal.net); neither states terms for
programs that could be read. The commercial market is led by the Stepstone group's IrishJobs.ie and Jobs.ie,
whose shared robots.txt closes most filtered and paged URLs, and by Indeed and LinkedIn, whose terms forbid
bots. Ireland's presence on EURES is small (999 vacancies on the day). The employer route is where Ireland is
strong: the Companies Registration Office publishes every company's basic record (829,416 records: number,
name, status, type, registration date, address, NACE code) as a daily CSV and a keyless API under CC BY 4.0 -
without websites or e-mail addresses.

## Sources

### JobsIreland (public employment service job site)
- Publisher: Department of Social Protection (Intreo, the public employment service).
- Documentation: none found for a feed, API or dataset (one search).
- Data or endpoint: https://jobsireland.ie
- Holds: vacancies placed by employers with the public employment service. Fields not examined.
- Access: web application only.
- Registration or key: not established. Cost: free.
- Licence or terms (exact wording, with URL): not read; the site has no robots.txt in the usual sense (see Seen).
- Usable for own job search: unclear - no terms or robots rules could be read, and no documented way to read the
  vacancies exists.
- Volume: not read. On EURES 999 vacancies had a workplace in Ireland on 2026-11-28 (this study's EU-wide file,
  which notes the figure is far below what the service lists at home).
- Update cycle: continuous.
- Seen on 2026-11-28: GET https://jobsireland.ie/robots.txt -> 200, text/html, 38,436 bytes: not a robots file but
  the site's application shell (an empty `<title>`, scripts). No further request.
- Caveats: third parties sell a JobsIreland scraper on apify.com and note the data "may change without notice".

### publicjobs.ie (public-sector recruitment)
- Publisher: publicjobs (the State's recruitment and selection body, formerly the Public Appointments Service).
- Documentation: none found for a feed or API; the home page carries no RSS link.
- Data or endpoint: https://www.publicjobs.ie/en/ ; the job search is on a vendor-hosted system,
  `https://publicjobs.tal.net/vx/.../candidate/jobboard/vacancy/3/adv/` (linked from the home page; not requested).
- Holds: civil-service and public-sector competitions and "Available Appointments". Fields not examined.
- Access: web only.
- Registration or key: none to browse; an account on the vendor system to apply and for alerts ("Register and
  set up job alerts on our new recruitment [system]").
- Cost: free.
- Licence or terms (exact wording, with URL): not read. robots.txt (https://www.publicjobs.ie/robots.txt) for all
  agents disallows only system directories ("/bin/", "/cache/", "/cli/", "/includes/", "/language/",
  "/layouts/", "/libraries/", "/tmp/").
- Usable for own job search: unclear - terms not read; the vacancies sit on the vendor's system, which was not
  requested.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 244 bytes; GET /en/ -> 200, text/html, 76,756 bytes.
- Caveats: local-authority and health-service vacancies are advertised on their own sites; not checked.

### Vacancy datasets on data.gov.ie
- Publisher: Central Statistics Office (the only matches).
- Data or endpoint: `https://data.gov.ie/api/3/action/package_search?q=job%20vacancies`
- Holds: two results, both statistics: "EHQ16 - Job Vacancies" and "EHQ59 - Job Vacancies" (CC-BY-4.0). No
  dataset of individual vacancies.
- Usable for own job search: no - aggregates only (official vacancy statistics, quarterly).
- Seen on 2026-11-28: the request above -> 200, application/json, 13,319 bytes, `count` 2.

### IrishJobs.ie and Jobs.ie (Stepstone group)
- Publisher: The Stepstone Group (the two sites serve the same robots.txt but for the site name).
- Documentation: none read (the terms address tried answered an error page).
- Data or endpoint: https://www.irishjobs.ie ; https://www.jobs.ie ; no reading feed found.
- Holds: adverts of paying recruiters. Not examined.
- Access: web only.
- Registration or key: none to browse. Cost: free for candidates.
- Licence or terms (exact wording, with URL): terms not read. robots.txt (https://www.irishjobs.ie/robots.txt,
  "last updated 25 03 26") for all agents: "Disallow: /jobs/permanent", "Disallow: /*&page=", "Disallow:
  /*/apply?", "Disallow: /*/apply$", "Disallow: /*.ashx$", "Disallow: /Login/", "Disallow: /savedjobs", and
  tracking-parameter URLs; named search engines get "Allow: /job/", "Allow: /jobs/" with query strings closed.
- Usable for own job search: unclear - terms not read here; the same group's Belgian terms (see `BE-Belgium.md`)
  limit the service to "the individual job search by natural persons" and forbid scraping for other purposes.
- Volume: not read. Update cycle: continuous.
- Seen on 2026-11-28: GET https://www.irishjobs.ie/robots.txt -> 200, text/plain, 6,236 bytes; GET
  https://www.irishjobs.ie/about-us/terms-of-use/ (a guessed address) -> **503**, the site's error page ("Well,
  that wasn't supposed to happen!"); the host was not asked again. GET https://www.jobs.ie/robots.txt -> 200,
  6,191 bytes.
- Caveats: third parties sell scrapers of both sites on apify.com.

### Indeed and LinkedIn in Ireland
- Usable for own job search: no for a program - Indeed's terms (1 April 2026, read in French) forbid using an
  automated system ("bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique") to access the site
  without written permission; LinkedIn's User Agreement forbids "software, devices, scripts, robots or any other
  means or processes [...] to scrape or copy the Services". Read once for this pass's France file
  (`FR-France.md`); ie.indeed.com was not requested.

### Official vacancy statistics (one line)
- CSO tables EHQ16 and EHQ59 (job vacancies, from the quarterly earnings survey) are open under CC BY 4.0;
  aggregates only.

## Through the employers

### Business register
- Publisher: Companies Registration Office (CRO) - one national register.
- Documentation: https://opendata.cro.ie/dataset/companies (data dictionary among its resources; not fetched).
- Data or endpoint: bulk
  https://opendata.cro.ie/dataset/bf6f837d-0946-4c14-9a99-82cd6980c121/resource/3fef41bc-b8f4-4b10-8434-ce51c29b1bba/download/companies.csv.zip ;
  API `https://opendata.cro.ie/api/3/action/datastore_search?resource_id=3fef41bc-b8f4-4b10-8434-ce51c29b1bba&limit=1`
- Holds: basic data on every company is really free, in bulk and by API, with no approval and no key. Fields
  seen: `company_num`, `company_name`, `company_status` (+ code and date), `company_type` (+ code),
  `company_reg_date`, `company_address_1` to `_4`, `eircode`, `comp_dissolved_date`, `last_ar_date`, `nard`,
  `last_accounts_date`, `nace_v2_code`, `princ_object_code`, name and type effective dates. Of the eight minimum
  attributes of Regulation (EU) 2023/138 it carries seven by name: name, status, registration date, registered
  office address, legal form (company type), registration number, activity code; the Member State is not a
  field of its own. Beyond them: Eircode, annual-return and accounts dates. No website, e-mail, phone or number
  of employees.
- Access: bulk CSV (zip) and CKAN datastore API.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "license_id": "CC-BY-4.0", "Creative Commons Attribution 4.0"
  (dataset record).
- Usable for own job search: yes - an open list of companies with addresses and activity codes; the careers
  page of each still has to be found elsewhere.
- Volume: 829,416 records (dissolved companies included; the first record is a company dissolved in 2000).
- Update cycle: daily ("frequency": "Daily"; record modified 2026-11-17).
- Seen on 2026-11-28: GET `.../api/3/action/package_show?id=companies` -> 200, application/json, 4,467 bytes; GET
  of the datastore request above -> 200, 4,278 bytes, one record and the field list.
- Caveats: in that one record `nace_v2_code` is empty and the older `princ_object_code` ("74.84") is filled, so
  activity coding may be uneven. Whether the dataset carries the portal's high-value-dataset label was not seen
  (its only tag is "Company"); a separate "Financial Statements" dataset exists on the same portal (search
  result). Business names of sole traders are a different register, not examined.

### Applicant-tracking vendors seen in the country

| Vendor | Local or international | Public feed for an employer's board (format, key?) | Documentation URL | Basis for "used here" |
|---|---|---|---|---|
| Oleeo (tal.net) | International (UK vendor, from memory) | Not checked; no vendor page read | - | publicjobs.ie links its job search and candidate login to publicjobs.tal.net (seen today) |
| HireHive | Irish (from memory, not confirmed today) | Per HireHive's own blog as summarised by a search, "every company that has a HireHive account will have a custom API URL available from your Settings"; whether it needs a key is not confirmed | the blog address https://www.hirehive.com/hirehive-api-new-job-integration-option/ now redirects to the home page | Not established |
| Occupop, Rezoomo | Irish (from memory) | Not found | - | Named from memory only |
| Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Recruitee, Personio, Workday | International | See this study's `00-EU-wide.md`, topic 5 | there | Not established for Ireland |

No source was found on which systems Irish employers use most.

### Links to employers' own pages
- None found in a free source a program may read. No open vacancy dataset exists; the boards were not examined
  at advert level.

### Employer directories
- None verified. Known from memory only (not requested, terms not read): IDA Ireland's and Enterprise Ireland's
  company listings, the TechIreland directory.

## Not free or not allowed

- Indeed, LinkedIn: automated reading forbidden by their terms.
- IrishJobs.ie / Jobs.ie: paged, filtered and apply URLs closed in robots.txt; terms not read.
- No partner or paid vacancy feed from the State was found either; third-party scrapers of JobsIreland,
  publicjobs.ie, IrishJobs.ie and Jobs.ie are sold on apify.com, and a commercial vendor lists an Irish job
  postings feed on AWS Marketplace (search results only).

## Gaps

- **JobsIreland**: terms, fields, volume, apply path and any interface behind the application were not seen;
  why so few Irish vacancies reach EURES is not known.
- **publicjobs.ie**: terms not read; the vendor-hosted job board was deliberately not requested, so fields and
  feeds there are unknown.
- **IrishJobs.ie / Jobs.ie**: terms not read (503 on a guessed address). Recruit Ireland, university and
  sector boards, and local-authority or HSE job pages: not checked.
- **CRO**: the data dictionary and the zip were not fetched; coverage of `nace_v2_code` and the dataset's
  high-value-dataset status are unconfirmed.
- **Applicant-tracking vendors and employer directories**: nothing verified beyond the publicjobs link; HireHive's
  documentation was not found at its old address.
- Ireland's data.europa.eu entries were not requested again (the EU-wide file counts two, both statistics).
