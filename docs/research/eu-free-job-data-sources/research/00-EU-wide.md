# EU-wide layer - free online job data sources: research

Checked on 28 November 2026. Client: curl 8.14.1 with its own default User-Agent (`curl/8.14.1`; no browser-like
headers; `Accept` / `Content-Type` only where the protocol needs them), and Claude Code's WebFetch and WebSearch tools
(their own client identity). No account, key or login was used anywhere. Hosts that masi already reads (named in
masi's `docs/sources.md` and `docs/remote-sources-investigation.md`) got at most one request, to a documentation or
terms page, and none to a data endpoint; what is said about their data comes from those two files and from the
vendor's public documentation, and is marked so.

Conventions: "Seen on" lines give the request made on 28 November 2026 and what came back. "Third party" marks a
statement taken from someone other than the publisher. Anything not confirmed is in "Gaps" at the end.

## 1. EURES

### EURES portal - job vacancy search
- Publisher: European Labour Authority (ELA), European Coordination Office of the EURES network; the portal is run on
  the Commission's europa.eu infrastructure (response header `X-Owner-Dg: ELA`).
- Documentation: https://eures.europa.eu/ (content site); legal basis Regulation (EU) 2016/589 and Commission
  Implementing Decision (EU) 2017/1257 (see topic 2). The technical specification ("EURES Single Coordinated Channel
  Specifications", HR Open Standards `PositionOpening` based) is published on the EURES portal Extranet, which is not
  public (Decision 2017/1257 Art. 10(2)).
- Data or endpoint: web search at https://europa.eu/eures/portal/jv-se/home. No documented public API, no open-data
  dump, no RSS/XML feed was found on the publisher's pages. The web search's own back end is an unauthenticated JSON
  endpoint, `POST https://europa.eu/eures/api/jv-searchengine/public/jv-search/search`; it is **not documented and
  not offered as an API** by ELA.
- Holds: every vacancy the member states' public employment services (and other EURES Members/Partners) publish and
  pass on. One record as returned by the search back end: `id`, `title`, `description` (HTML, full text),
  `creationDate`, `lastModificationDate`, `numberOfPosts`, `locationMap` (country -> NUTS codes), `euresFlag`,
  `jobCategoriesCodes` (ESCO occupation URIs), `positionScheduleCodes` (full/part time), `positionOfferingCode`
  (contract form), `employer` (`name`, `legalID`, `website`, size, ownership, `sectorCodes`), `availableLanguages`,
  `translations`. No salary field in the list record (not checked on the detail record).
- Access: web search; the undocumented JSON back end behind it. Application interfaces exist by law, but only for
  EURES Members and Partners (Decision 2017/1257 Art. 2(4), quoted in topic 2).
- Registration or key: none for the web search or its back end. The Member/Partner interfaces need admission to the
  EURES network through a National Coordination Office (not self-service; an organisation is admitted under national
  rules, Regulation 2016/589 Art. 11).
- Cost: free.
- Licence or terms (exact wording, with URL):
  - Site content: "Copyright © for the entire content of this website unless otherwise stated: European Labour
    Authority (ELA). Re-use is authorised, provided that ELA is acknowledged as the source of the material. For
    individual documents, the general principle of re-use outlined above may be subject to specific conditions as
    indicated in individual copyright notices contained therein." - https://eures.europa.eu/eures-legal-notice_en
  - The vacancies themselves are not ELA's: "The transmission of data to the EURES portal shall not affect the rights
    to the data held by the originators of the data or the EURES data holders" and the data "is indexed, stored and
    made available there solely for search and matching purposes ... Data that has been anonymised may be stored and
    released, also to third parties, for research and statistical purposes" (Decision (EU) 2017/1257 Art. 3(1)-(2)).
    So the site's "re-use is authorised" line cannot be read as an open licence on the vacancy texts.
  - Crawling is watched: "User actions can also be logged for data protection and security auditing, to detect web
    crawlers (for example, number of pages viewed within a time period). In case of misuse/abuse of the information
    provided by the EURES portal, ELA may initiate an investigation" -
    https://eures.europa.eu/data-protection-statements/data-protection-statement-and-specific-terms-and-conditions-use-eures-portal-services_en
    (that page, despite its title, holds the two privacy statements and no separate reuse clause).
  - https://europa.eu/robots.txt: no rule names `/eures/`; `Crawl-delay: 10` for all agents.
- Volume: **1,914,393** vacancies on 28 November 2026 (`numberRecords`); 77,527 carry the EURES flag (employer
  explicitly wants workers from other countries). Per country of the workplace, from the same answer's
  `POSITION_LOCATION` facet (a vacancy with places in two countries counts in both; the facet sums to 1,914,727):

  | | | | | | |
  |---|---|---|---|---|---|
  | AT 57,261 | BE 237,924 | BG 10,685 | CY 3,713 | CZ 41,094 | DE 660,831 |
  | DK 1,465 | EE 2,107 | EL 208 | ES 26,927 | FI 14,528 | FR 427,029 |
  | HR 6,345 | HU 1,154 | IE 999 | IT 4,266 | LT 6 | LU 3,223 |
  | LV 3,748 | MT 5,331 | NL 285,437 | PL 15,122 | PT 934 | RO 4,524 |
  | SE 44,823 | SI 3,085 | SK 11,797 | (CH 26,813) | (NO 12,555) | (IS 22, LI 34, not stated 737) |

  All 27 EU states are present, but very unevenly: DE, FR, NL and BE hold 84% of the total, while LT (6), EL (208),
  PT (934), IE (999) and HU (1,154) are far below what their employment services list at home. The answer also has a
  `CONNECTION_POINT_ID` facet with 34 numbered connection points (the national single coordinated channels and a few
  others); the numbers are not labelled with country names in the answer.
- Update cycle: continuous (the newest record seen was modified on 2026-11-28 15:15 UTC; national channels push
  through the day).
- Seen on 2026-11-28:
  - `GET https://eures.europa.eu/eures-legal-notice_en` -> 200, text/html, 17.5 kB: the copyright notice quoted above.
  - `GET https://eures.europa.eu/data-protection-statements/...-use-eures-portal-services_en` -> 200, text/html,
    22 kB: two privacy statements (jobseekers, employers), the crawler sentence quoted above.
  - `GET https://europa.eu/robots.txt` -> 200, text/plain.
  - `POST https://europa.eu/eures/api/jv-searchengine/public/jv-search/search` with a JSON body asking for one result
    (`resultsPerPage: 1`, empty filters) -> 200, application/json, 5.7 kB: `numberRecords`, one vacancy (a Belgian
    bus-driver post, Dutch text, employer and its website named) and ten facets. One request only; no paging.
- Caveats: the back end is undocumented, can change without notice, and reading it in bulk is exactly the "web
  crawler" behaviour the portal says it logs; there is no published rate limit or permission. Third parties sell
  scrapers built on it (several Apify "EURES jobs scraper" actors; one claims "Open data under CC BY 4.0", another
  "personal / link-back use" - both third party, contradictory, and neither is backed by anything ELA publishes).
  National coverage depends on what each state passes on (Art. 17(2) lets states leave out some categories, and
  employers may opt out). Texts stay in the original language; machine translations are optional per record.

### EURES portal statistics - job vacancy statistics
- Publisher: ELA (dashboards hosted on the Commission's Qlik platform, `dashboard.tech.ec.europa.eu`).
- Documentation: https://eures.europa.eu/eures-services/eures-portal-statistics/job-vacancy-statistics_en
- Data or endpoint: eight embedded dashboards (by occupation, working location, education level, language,
  experience, skills, contract type, work schedule); iframe sources such as
  `https://dashboard.tech.ec.europa.eu/qs_digit_dashboard_mt/public/extensions/EMPL_STATIS_JV_LOCATION/EMPL_STATIS_JV_LOCATION.html`.
- Holds: counts of vacancies currently on the portal, by country and NUTS region, ESCO occupation, ISCED level etc.
- Access: interactive dashboards; "You can download the table by using the download button on the top right of the
  specific statistic view." No file URL or API is documented.
- Registration or key: none.
- Cost: free.
- Licence or terms: the EURES legal notice above (re-use authorised with acknowledgement of ELA).
- Volume: aggregate tables only.
- Update cycle: not stated on the page.
- Seen on 2026-11-28: `GET` of the page -> 200, text/html, 17.6 kB; the text and the eight iframe addresses; the
  dashboards themselves were not opened (they need a browser session).
- Caveats: stock figures only; no time series was seen. A second set, "Job vacancies insights"
  (https://eures.europa.eu/living-and-working/job-vacancies-insights_en), shows shares by occupation per country
  (not opened; from a search result).

### Single Market Scoreboard - EURES
- Publisher: European Commission.
- Documentation: https://single-market-scoreboard.ec.europa.eu/node/270_en
- Holds: per-country indicators from the EURES Performance Measurement System, among them the "labour market share":
  "job vacancies on the EURES portal as a proportion of all job vacancies in the participating countries" (Eurostat
  `jvs_q_nace2` as the denominator), and PMS indicator 4c, "the number of job vacancies made available through the
  single coordinated channel to the EURES portal". Data year: 2024 (PMS collection).
- Access: web page with charts; the per-country figures are in the charts, not in the page text.
- Registration or key: none. Cost: free.
- Licence or terms: Commission reuse policy (Decision 2011/833/EU, CC BY 4.0 for Commission content unless stated).
- Seen on 2026-11-28: one WebFetch of the page: the indicator definitions quoted above; no figures in text.
- Caveats: this is the one maintained, official per-country comparison of how much of each state's vacancy stock
  reaches EURES; the figures were not read (chart-only).

## 2. EU legal framework

### Open Data Directive (EU) 2019/1024 and the high-value datasets Regulation (EU) 2023/138
- Publisher: European Union (Official Journal).
- Documentation: Directive (EU) 2019/1024, http://data.europa.eu/eli/dir/2019/1024/oj; Commission Implementing
  Regulation (EU) 2023/138, http://data.europa.eu/eli/reg_impl/2023/138/oj (applies from 9 June 2024).
- Holds (what the law says):
  - **Vacancy data is not a high-value dataset.** Annex I of the Directive lists six thematic categories:
    "1. Geospatial 2. Earth observation and environment 3. Meteorological 4. Statistics 5. Companies and company
    ownership 6. Mobility". The word "vacancy" does not occur in the Directive or in Regulation 2023/138 (full text
    of both searched). The Statistics category of 2023/138 does include labour-market statistics - "Employment",
    "Unemployment" and "Potential labour force" (Labour Force Survey indicators under Regulation (EU) 2019/1700) -
    but not job vacancy statistics and not vacancy listings. For the datasets it does list, 2023/138 requires an API,
    bulk download where indicated, and CC0 / CC BY 4.0 or an equivalent open licence.
  - Outside the high-value list the Directive's general rule applies to a public employment service as a public
    sector body: "Member States shall ensure that documents to which this Directive applies ... shall be re-usable
    for commercial or non-commercial purposes" (Art. 3(1)). But it builds on national access regimes and excludes
    "documents for which third parties hold intellectual property rights" (Art. 1(2)(c)) and protects personal data.
    A vacancy text is written by the employer, so whether a PES vacancy database is re-usable is settled by each
    state's own law and by the PES's terms - which is why some states publish their PES vacancies as open data
    (covered in the country files) and others do not. This paragraph's last sentence is my reading, not a quotation.
- Access: n/a (law).
- Seen on 2026-11-28: both texts fetched from the Publications Office (`publications.europa.eu/resource/celex/...`,
  200, XHTML); searched for "vacanc": 0 matches in each. EUR-Lex itself answered a plain client with
  `202` and `x-amzn-waf-action: challenge` (an empty page), so the Publications Office address was used instead.
- Caveats: the Commission's Digital Omnibus proposal (COM(2025) 837, 19 November 2025, procedure 2025/0360(COD))
  would repeal the Open Data Directive and move its rules into the Data Act as a "re-use of public sector
  information" chapter; a Council presidency compromise text was dated June 2026 (third party: law-firm notes and
  Council document listings from a web search). Whether it has been adopted, and whether it changes the high-value
  list, was not confirmed today (see Gaps). Nothing found suggests vacancy data is being added.

### EURES Regulation (EU) 2016/589 and Implementing Decision (EU) 2017/1257
- Publisher: European Union (Official Journal).
- Documentation: http://data.europa.eu/eli/reg/2016/589/oj; http://data.europa.eu/eli/dec_impl/2017/1257/oj. (The
  ELA Regulation (EU) 2019/1149 later moved the European Coordination Office from the Commission to ELA; the 2016
  text read here is the original, not a consolidated version.)
- Holds (what the law says):
  - **Yes, member states must hand their public vacancies over - to the EURES portal, not to the public as data.**
    Art. 17(1): "each Member State shall make available to the EURES portal: (a) all job vacancies made publicly
    available through PES as well as those provided by the EURES Members and, where relevant, the EURES Partners in
    accordance with Article 12(3)". Art. 12(3) puts the same duty on every EURES Member.
  - Exceptions, Art. 17(1) second subparagraph and 17(2): employers may be allowed to opt out "if the request is duly
    justified on the basis of the skills and competence requirements relating to the job"; states "may exclude: (a)
    job vacancies which due to their nature or to national rules are open only to citizens of a specific country;
    (b) job vacancies relating to categories of apprenticeships and traineeships ... (c) other job vacancies as part
    of a Member State's active labour market policies."
  - How: "through a single coordinated channel" (Art. 9(2)(a), 18(4)); each National Coordination Office must also
    tell the Coordination Office about "discrepancies between the number of job vacancies notified and the total
    number of job vacancies at national level" (Art. 9(2)(c)).
  - To whom the data goes back out, Decision 2017/1257 Art. 2(4): "The European Coordination Office shall make the
    data available for searches and matching not only by end-users directly on the EURES portal but also through
    application interfaces allowing the EURES Members and, where relevant, EURES Partners to make the information
    available in their respective systems to their staff and to users of their job-search portals and services."
    Art. 3(1): the data "is indexed, stored and made available there solely for search and matching purposes during
    the period of validity set by the originator ... Data that has been anonymised may be stored and released, also
    to third parties, for research and statistical purposes even after the expiry of the period of validity."
    Art. 3(2): transmission "shall not affect the rights to the data held by the originators".
  - Classification: Art. 19 obliges states to map national occupation and skill classifications to the European
    classification (ESCO; Implementing Decisions (EU) 2018/1020 and 2018/1021).
- Access: n/a (law).
- Consequence: the Regulation creates a public *search* (the portal) and a machine interface for *network members*.
  It gives the general public no right to a bulk copy or an API, and neither act mentions open data. A member
  state's own open-data release of PES vacancies comes from national policy, not from this Regulation.
- Seen on 2026-11-28: both texts fetched from the Publications Office (200, XHTML, 236 kB and 59 kB); the passages
  above are copied from them.
- Caveats: the 2017 "EURES Single Coordinated Channel Specifications" sit on the EURES Extranet and were not read.

## 3. Official statistics

### Eurostat - job vacancy statistics (JVS)
- Publisher: Eurostat (European Commission).
- Documentation: https://ec.europa.eu/eurostat/cache/metadata/en/jvs_esms.htm (metadata);
  https://ec.europa.eu/eurostat/web/user-guides/data-browser/api-data-access (API guide).
- Data or endpoint: API `https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/<table>?format=JSON&...`
  (JSON-stat; SDMX 2.1 and 3.0 and TSV/CSV bulk files of each table are served by the same service); table list in
  `https://ec.europa.eu/eurostat/api/dissemination/catalogue/toc/txt?lang=en`. Tables as listed today:
  - `jvs_q_r21` - by NACE Rev. 2.1 activity, quarterly, 2001-Q1 to 2026-Q3, updated 19.11.2026 (the current table);
  - `jvs_q_isco_r21` - by NACE Rev. 2.1 activity, occupation and NUTS 2 region, quarterly, to 2026-Q3;
  - `jvs_a_r21` - job vacancy rate by NACE Rev. 2.1, annual, 2008-2025;
  - `jvs_q_nace2`, `jvs_q_isco_r2`, `jvs_a_rate_r2` - the NACE Rev. 2 versions, now filed under "historical data",
    ending 2025-Q4 / 2025 (last updated 20.03.2026);
  - headline tables `ei_lmjv_q_r2`, `teilm310`, `tps00172`; older `jvs_q_nace1`, `jvs_a_nace1`, `jvs_a_nace2`.
- Holds: numbers of job vacancies and occupied posts, job vacancy rate, by economic activity, size class
  (total / 10+ employees), seasonal adjustment, country; an occupation and region breakdown for the countries that
  supply it. Survey-based statistics from national statistical institutes (Regulation (EC) No 453/2008); **no
  individual vacancies**.
- Access: API and bulk download.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): "Reuse of statistical data, metadata, publications, and other
  dissemination tools published on this website for commercial or non-commercial purposes is authorised provided the
  source is acknowledged. ... There is no special procedure or requirement for a written licence. Just download the
  material and use it, unless the material is listed in the exceptions above." (editorial content: CC BY 4.0) -
  https://ec.europa.eu/eurostat/help/copyright-notice
- Volume: `jvs_q_r21` 749,892 observations; `jvs_q_isco_r21` 2,055,710.
- Update cycle: quarterly (about 45 days for a flash figure and 70-80 days for full data after the quarter; the
  latter from memory of the metadata, not re-read today).
- Seen on 2026-11-28: `GET .../catalogue/toc/txt?lang=en` -> 200, text/plain, 1.99 MB (the table list above);
  `GET .../data/jvs_q_r21?format=JSON&lang=EN&geo=EE&lastTimePeriod=1` -> 200, application/json, 6.5 kB: dimensions
  `freq, nace_r2_1, sizeclas, s_adj, indic_em, geo, time`, time 2026-Q3, updated 2026-11-19, DOI 10.2908/JVS_Q_R21;
  the Estonian cells for 2026-Q3 were empty (0 values) in that answer.
- Caveats: the move from NACE Rev. 2 to Rev. 2.1 happened during 2026 - a reader of `jvs_q_nace2` now gets a table
  that stops at 2025-Q4. Country coverage of each breakdown differs (some states report only 10+ employee firms or
  leave out sections); not every state has a value for every quarter.

### Eurostat - online job advertisement (OJA) statistics "under development"
- Publisher: Eurostat, from the Web Intelligence Hub's OJA data.
- Documentation: https://ec.europa.eu/eurostat/web/experimental-statistics/online-job-advertisement-rate ;
  https://cros.ec.europa.eu/wih/oja
- Data or endpoint: Eurostat tables `jvs_a_isco3_r1` ("Job vacancy statistics by occupation and NUTS 1 region (OJA
  breakdowns) - annual data - statistics under development", 2019-2024, updated 17.02.2026) and `isoc_sk_oja1`,
  `isoc_sk_oja2`, `isoc_sk_oja3` (demand for ICT specialists in online job advertisements, by NUTS 2 region and
  ISCO-08, 2019-Q4 to 2026-Q3, updated 16.11.2026), through the same API as above.
- Holds: aggregates only (shares, rates, changes).
- Access: API and bulk download. Registration or key: none. Cost: free.
- Licence or terms: Eurostat's notice quoted above.
- Seen on 2026-11-28: listed in the table of contents fetched above; the tables themselves were not requested.
- Caveats: Eurostat labels them experimental: "The coverage of the web portals is not exhaustive" (from a search
  result of the Eurostat page).

### Web Intelligence Hub OJA data (Eurostat) and Cedefop Skills-OVATE
- Publisher: Eurostat's Web Intelligence Hub (WIH) collects and classifies the adverts (since 2021; Cedefop built
  the system from 2017); Cedefop publishes the Skills-OVATE dashboards from it.
- Documentation: https://cros.ec.europa.eu/wih/oja ; https://www.cedefop.europa.eu/en/tools/skills-online-vacancies
- Data or endpoint: none public for the adverts. Public outputs are dashboards (Skills-OVATE; the WIH "Top &
  Trending skills" app) and the Eurostat tables in the block above.
- Holds: "millions of OJAs collected from diverse sources" - private job portals, public employment service portals,
  recruitment agencies - found by a "landscaping" per country (2017 by Cedefop for the EU 27 and the UK; 2021 by
  Eurostat, extended to EFTA), each advert classified by occupation (ISCO/ESCO), skills (ESCO), region (NUTS),
  activity (NACE), etc. Skills-OVATE (third-hand: search-result text of Cedefop's page) "covers online job
  advertisements in 32 European countries", "presents data for the last 4 available quarters and is updated four
  times a year".
- Access:
  - the adverts (microdata): **not public and not downloadable**. "Access to OJA data in the WIH is open to ESS
    members, National Statistical Institutes, and other national statistical authorities"; scientific use datasets
    "are accessible for scientific research purposes via the Datalab" where researchers query with SQL in R/Python;
    "WIH OJA microdata cannot be downloaded"; researchers apply through Eurostat's microdata access portal
    (research entities only) - wording from https://cros.ec.europa.eu/wih/oja as summarised by the fetch tool;
  - aggregates: Skills-OVATE dashboards (web; the dashboards have per-chart export - not verified today, see Gaps).
- Registration or key: none for the dashboards; a recognised research entity and an approved proposal for microdata.
- Cost: free.
- Licence or terms: the WIH page states no licence. Cedefop's site-wide copyright notice was not read (403).
- Volume: not stated on the page read.
- Update cycle: quarterly ("released to statisticians on the WIH's DataLab, on a quarterly basis").
- Seen on 2026-11-28: WebFetch of https://cros.ec.europa.eu/wih/oja -> content returned (summarised above);
  WebFetch of https://www.cedefop.europa.eu/en/tools/skills-online-vacancies -> **HTTP 403 Forbidden**; the host was
  not asked again.
- Caveats: the page notes that reading portals through their APIs "requires formal agreements with website
  operators" - the WIH's sources are scraped or contracted, so its adverts cannot be passed on. Skills-OVATE leaves
  out portals without a stable feed ("job ads from these portals are excluded", search-result text). The list of
  portals per country is in the landscaping reports, not on the page read.

### ESCO - European Skills, Competences, Qualifications and Occupations
- Publisher: European Commission (DG Employment, Social Affairs and Inclusion).
- Documentation: https://esco.ec.europa.eu/en/use-esco/download ;
  https://esco.ec.europa.eu/en/use-esco/use-esco-services-api
- Data or endpoint: download page (versions v1.0.3 to **v1.2.1**; formats "RDF, TTL, ODS, CSV, XML, JSON-LD"; "all
  28 ESCO languages"; delta files between versions); web-service API at `https://ec.europa.eu/esco/api/` (e.g.
  `/search`, `/resource/occupation`, `/resource/skill`); a downloadable "Local API" (the page says the current local
  API version "is provided for reference only and will be replaced shortly").
- Holds: about 3,000 occupations mapped to ISCO-08, and about 13,900 skills, with labels in 28 languages and
  occupation-skill relations (counts for v1.2 from memory, not re-read today). It is the classification EURES uses
  (`jobCategoriesCodes` in a EURES vacancy are ESCO occupation URIs).
- Access: bulk file and API.
- Registration or key: the API needs none. The download form asks for an e-mail address: "Read and accept the
  [privacy] statement, then enter your email address. You will receive a link to download your chosen dataset." (not
  done here); the page also gives a direct link to the v1.2.0 RDF file.
- Cost: "free of charge".
- Licence or terms (exact wording, with URL): the ESCO site's legal link is the Commission's notice: "Unless
  otherwise indicated (e.g. in individual copyright notices), content owned by the EU on this website is licensed
  under the Creative Commons Attribution 4.0 International (CC BY 4.0) licence" -
  https://commission.europa.eu/legal-notice_en . The API software: "The ESCO API is licensed under the EUPL 1.2".
- Volume: small (tens of MB per language package).
- Update cycle: major versions every few years (v1.1 January 2022, v1.2.0 May 2024), minor ones between (v1.2.1).
- Seen on 2026-11-28: download page -> 200, 12.9 kB (wording above);
  `GET https://ec.europa.eu/esco/api/search?text=software%20developer&type=occupation&language=en&limit=1` -> 200,
  application/json, 1.1 kB: `total` 490, one occupation with its URI and labels in all languages; API page -> 200.
- Caveats: no vacancy data; it is what makes vacancies from different countries comparable.

## 4. Job aggregators with an API or feed

Summary: **every general aggregator needs a key except Arbeitnow and Jobicy** (and Himalayas, topic 6). The keyed ones
are built to show their listings on a partner's site and send clicks back; none of them permits building a standing
copy of the listings, and none returns the full advert text.

### Adzuna API
- Publisher: Adzuna Ltd (UK).
- Documentation: https://developer.adzuna.com/overview ; https://developer.adzuna.com/docs/search
- Data or endpoint: `https://api.adzuna.com/v1/api/jobs/{country}/search/{page}?app_id=...&app_key=...` (also
  histogram, top-companies, geodata, history endpoints).
- Holds: title, company, location (with area hierarchy), category, `salary_min`/`salary_max` (flag
  `salary_is_predicted`), contract type/time, `created`, `redirect_url` (back to Adzuna), and a **snippet** of the
  description: "Please note we currently only provide a snipped of the job description in the response."
- Countries: 19 country codes, of which eight are EU: **AT, BE, DE, ES, FR, IT, NL, PL** (list from third-party
  pages; Adzuna's own list sits in its interactive docs, not read).
- Access: REST API (JSON/XML).
- Registration or key: **key needed** (`app_id` + `app_key`). "Every registered API user receives a free API key
  immediately, with no payment details required. The free tier is intended for evaluating the API." Self-service
  registration; not requested here.
- Cost: free tier for evaluation; "Paid plans are available for personal and academic use at higher volumes"; a
  licence agreement for commercial use.
- Licence or terms (exact wording, https://developer.adzuna.com/docs/terms_of_service): permitted use is "Personal job
  search; Publishing Adzuna ad listings; Publishing Jobsworth salary estimates; Personal and academic research. Any
  other use, including commercial analysis, resale of data, and sales prospecting or lead generation, requires our
  written agreement." "Any use of the Adzuna API by a commercial, government or academic organisation ... is permitted
  subject to a 14 day trial period ... It may not be used in its original format or in aggregation (including but not
  limited to vacancy counts, average salaries etc) to deliver any ongoing work or research ... without written
  consent." Attribution: "label each displayed advert with the phrase "Adzuna" at least 116 X 23 pixels in size ...
  hyperlinked". On termination the user "shall immediately remove all ... data acquired from Adzuna".
- Volume: not stated on the pages read. Update cycle: continuous.
- Seen on 2026-11-28: three documentation pages -> 200 (overview 3.5 kB, search 3.3 kB, terms 3.8 kB). No API call
  (key needed).
- Caveats: the free-tier call limits are shown only inside an account ("The plans available to you, and their
  limits, are shown in your account").

### Jooble REST API
- Publisher: Jooble (Ukraine-founded aggregator; per-country domains).
- Documentation: https://jooble.org/api/about ;
  https://jooblehelpcenter.freshdesk.com/en/support/solutions/articles/60001448238-rest-api-documentation
- Data or endpoint: `POST https://jooble.org/api/{api_Key}` (JSON body: `keywords`, `location`, `radius`, `salary`,
  `page`, `ResultOnPage`); other countries on their own domains.
- Holds: `id`, `title`, `location`, `snippet`, `salary`, `source`, `type`, `link`, `company`, `updated`,
  `totalCount`. Snippet only, no full text.
- Countries: "a key generated on jooble.org provides access exclusively to US job listings"; each country domain
  needs its own key. Which EU countries have an API domain was not confirmed (third parties say 60-70 countries).
- Access: REST API.
- Registration or key: **key needed**; "Register on the Jooble API portal for your target country. Once registered,
  your API key will be sent to you via email." The form is aimed at owners of a website (third-hand: search-result
  text of the API page). Not requested here.
- Cost: free; "The free REST API plan includes a limit of 100 requests per day per key for a specific country";
  more on request.
- Licence or terms: the help-centre article states none; the terms are said to be on `jooble.org/api/about`, which
  could not be read.
- Seen on 2026-11-28: `GET https://jooble.org/api/about` -> **HTTP 403** (3 kB HTML) for curl; the host was not asked
  again. The help-centre article was read through WebFetch.
- Caveats: 100 requests a day at 20-odd results a request is a search widget, not a data source.

### Careerjet Job Search API
- Publisher: Careerjet Ltd (UK).
- Documentation: https://www.careerjet.com/partners/api/ ; terms
  https://www.careerjet.com/partners/api/terms-and-conditions
- Data or endpoint: `https://search.api.careerjet.net/v4/query` (HTTP Basic auth with the API key; parameters
  `locale_code`, `keywords`, `location`, `sort`, `page`, `page_size` up to 100, and - required - `user_ip` and
  `user_agent` "of the user whose action(s) triggered the API call").
- Holds: title, company, locations, date, salary (with currency code, min/max, type), an excerpt of the description
  (120 characters by default), tracking `url` on `jobviewtrack.com`. No full text.
- Countries: by locale (`[language_code]_[COUNTRY_CODE]`, default `en_GB`); the list of supported locales was not
  read (Careerjet advertises some 90 countries; not confirmed per EU state).
- Access: REST API.
- Registration or key: **key needed**: "Each publisher website requires a unique API key, which you can obtain from
  your Publisher account"; "you will need to declare your IP address(es) / range ... Dynamic IP addresses or
  serverless environments without fixed outbound IP addresses are not supported." Not requested here.
- Cost: free for publishers (revenue share on clicks). A separate **paid** "Jobs Data API" exists for data use
  ("Commercial, high-volume access to our jobs database for data-driven applications", with full descriptions):
  https://www.careerjet.com/recruiter/jobs-data-api
- Licence or terms (exact wording): "Careerjet's free Job Search API is intended for partners who integrate Careerjet
  job search into their websites ... The API must not be used to: Extract or collect job listings in bulk for
  purposes unrelated to displaying them to jobseekers and referring traffic to Careerjet. Build or maintain an
  independent job database, search index, or competing job search service using Careerjet data. Sell, license,
  redistribute, or otherwise make Careerjet job data available to third parties as a standalone data product. Train,
  fine-tune, or evaluate artificial intelligence or machine learning models using Careerjet data. Develop independent
  commercial data, analytics, research, or market intelligence products using Careerjet data."
- Seen on 2026-11-28: three pages -> 200 (API 9.3 kB, terms 7.9 kB, data API 19 kB). No API call (key needed).
- Caveats: the terms rule out exactly the "collect and keep" use.

### Talent.com (formerly Neuvoo) publisher programme
- Publisher: Talent.com Inc. (Canada).
- Documentation: https://employers.talent.com/publishers
- Data or endpoint: publisher XML feeds, a "self-serve job API", affiliate URLs; no public technical documentation.
- Holds: "30M+ jobs in 79 countries" (their figure); fields not documented publicly.
- Access: partner feed/API. Registration or key: **partnership needed** - "Get in touch with our team of experts to
  learn more"; no self-service key was found. Cost: free to publishers (paid per click to them).
- Licence or terms: none on the page beyond the site's general terms (not read).
- Seen on 2026-11-28: one WebFetch of the publishers page.
- Caveats: a traffic-monetisation product for job sites, not a data service.

### Arbeitnow job board API  (host read by masi's investigation; documentation only)
- Publisher: Arbeitnow (one developer, Berlin).
- Documentation: https://www.arbeitnow.com/blog/job-board-api (and a Postman collection linked from it).
- Data or endpoint: `https://www.arbeitnow.com/api/job-board-api` (JSON; parameters such as
  `visa_sponsorship=true`); "In 2026, I have now launched the same API for the United Kingdom" at
  `https://www.arbeitnow.co.uk/api/job-board-api`. Neither was requested.
- Holds: jobs "mostly from Applicant Tracking Systems (ATS)", in one format, with a `remote` flag; title, company,
  location, description, tags, URL, created date (field list from the documentation).
- Countries: "some of the latest jobs in Europe" - in practice Germany: masi's investigation of 2026-11-10 found
  300 jobs a page, every remote one at a German or Swiss city.
- Access: REST API. Registration or key: "requires no API key". Cost: free; "For commercial use of the API, please
  get in touch and propose a monthly fee in EUR. In general, donations are welcome."; a "custom, private, tailored
  API endpoint ... for a monthly fee".
- Licence or terms: no formal terms on the page read; the commercial-use sentence above is the only condition.
- Seen on 2026-11-28: the documentation page -> 200, 10 kB.
- Caveats: DE-centred; re-lists employer ATS boards (the same adverts as topic 5).

### The Muse API
- Publisher: The Muse (US).
- Documentation: https://www.themuse.com/developers/api/v2
- Data or endpoint: `https://www.themuse.com/api/public/jobs?page=N` (from memory and third-party directories).
- Holds: jobs of The Muse's employer partners, mostly US; some European locations.
- Access: REST API. Registration or key: third-party directories say a key is optional and lifts the limit from 500
  to 3,600 requests an hour; one third party says the public API has been replaced. **Not confirmed.**
- Seen on 2026-11-28: `GET https://www.themuse.com/developers/api/v2` -> **HTTP 403** (3 kB HTML) for curl; the host
  was not asked again.
- Caveats: nothing here is from the publisher today; of little weight for EU coverage in any case.

### Jobicy  (host read by masi's investigation; documentation only) - see topic 6

### Others found
- **JobData API** (jobdataapi.com, https://jobdataapi.com/docs/): "All API endpoints are publicly accessible, except
  for parameters and queries that require a certain subscription"; "Without a valid API key there is a maximum of
  ~10 requests per hour"; anonymous lists return at most 20 items; paid plans for more (weekly CSV/Parquet dumps on
  the top plan). Example feeds for about 45 countries. Source of the jobs and reuse terms not stated on the page.
  One WebFetch of the docs; no data request.
- **Findwork.dev**: its developers page is a sign-in form ("If you have not created an account yet, then please sign
  up first") - an account and token are needed. Developer jobs only.
- **Indeed**: no reading API - "the Indeed API is no longer maintained and it requires a published account which we
  cannot obtain anymore" (third party: Arbeitnow's blog); masi's sources list also records no usable Indeed route.
- **Paid only** (named for completeness, not examined): Careerjet Jobs Data API, TheirStack, Coresignal, Techmap,
  LinkUp, Fantastic.jobs, JSearch on RapidAPI. See "Gaps".

## 5. Applicant-tracking vendors with publicly readable job boards

What these have in common: the vendor hosts each employer's careers board and serves it as JSON, XML or RSS at a
predictable address, without a key, because the employer's own careers page reads it. Country is not a property of
the vendor: a board is found only by knowing the employer's board name, and each posting carries its own location.
There is no directory of boards. No vendor publishes a reuse licence for the postings - they are the employer's
content, published by the employer; the vendor's documentation speaks only of the technical access. All of the
vendors below except Pinpoint, Breezy HR, HireHive and Manatal are hosts masi reads today, so **only documentation
was requested**, one page per vendor; field details marked "masi" come from masi's `docs/sources.md`.

### Greenhouse - Job Board API
- Publisher: Greenhouse Software (US).
- Documentation: https://developers.greenhouse.io/job-board.html (redirects to `docs.greenhouse.io`).
- Data or endpoint: `GET https://boards-api.greenhouse.io/v1/boards/{board_token}/jobs` (`?content=true` adds the
  full description, departments and offices); `/jobs/{job_id}` (`?pay_transparency=true` adds `pay_input_ranges`);
  `/offices`, `/departments`. JSON, JSONP.
- Holds: `id`, `title`, `location.name` (free text), `absolute_url`, `updated_at`, `first_published`, `content`
  (HTML), departments, offices, metadata, pay ranges where set.
- Access: API. Registration or key: none for reading - "Only the application submission endpoint (POST ...) requires
  Basic Auth." Cost: free.
- Licence or terms: none stated; "Requests may be rate limited for security and traffic reasons."
- Volume: one employer per board. Update cycle: live.
- Seen on 2026-11-28: the documentation page -> 200, 16 kB. No board was requested.
- Caveats: board names are not case-sensitive (masi, measured 2026-11-07); a board with content can exceed 2 MB
  (masi); a gone board answers 404.

### Lever - Postings API
- Publisher: Lever (Employ Inc., US).
- Documentation: https://github.com/lever/postings-api
- Data or endpoint: `GET https://api.lever.co/v0/postings/{site}?mode=json` (`skip`, `limit`; filters `location`,
  `commitment`, `team`, `department`); **EU instance: `https://api.eu.lever.co/v0/postings/{site}`** for customers
  hosted in the EU. JSON, HTML or XML by `mode`.
- Holds: `id`, `text` (title), `categories` (location, commitment, team, department), `country`, `workplaceType`
  (`on-site`/`remote`/`hybrid`), `description`/`descriptionPlain`, `lists`, `additional`, `salaryRange`
  (`currency`, `interval`, `min`, `max`), `hostedUrl`, `applyUrl` (the documented field table names no date field).
- Access: API. Registration or key: none for reading. Cost: free.
- Licence or terms (exact wording): "Note that all job postings in the `published` state are publicly viewable.
  These jobs may be scraped by third parties. All other jobs are completely hidden from the jobs API." Rate limits
  are stated only for application POSTs.
- Seen on 2026-11-28: the README from `raw.githubusercontent.com` -> 200, 7.9 kB. No board was requested.
- Caveats: board names are case-sensitive (masi). A customer on the EU instance does not answer on `api.lever.co`
  (my reading of the two base URLs; not tested).

### Ashby - public job posting API
- Publisher: Ashby (US).
- Documentation: https://developers.ashbyhq.com/docs/public-job-posting-api
- Data or endpoint: `GET https://api.ashbyhq.com/posting-api/job-board/{JOB_BOARD_NAME}?includeCompensation=true`.
- Holds: `title`, `location`, `secondaryLocations`, `department`, `team`, `isListed`, `isRemote`, `workplaceType`,
  `descriptionHtml`/`descriptionPlain`, `publishedAt`, `employmentType` ("FullTime", "PartTime", "Intern",
  "Contract", "Temporary"), `address.postalAddress` (with country), `jobUrl`, `applyUrl`, `compensation`.
- Access: API. Registration or key: none. Cost: free.
- Licence or terms: none stated: "This API allows you to get data for all currently published Job Postings for your
  organization. If you host your own careers page, you can use this data to populate it."
- Seen on 2026-11-28: the documentation page -> 200, 36 kB. No board was requested.
- Caveats: `isListed: false` postings are meant to be reachable by direct link only.

### Workable - public account endpoints
- Publisher: Workable (Greece/US).
- Documentation: https://workable.readme.io/reference/jobs-1 ("Public Endpoints").
- Data or endpoint: `GET https://www.workable.com/api/accounts/{subdomain}?details=true` ("Returns a collection of the
  public jobs for an account"), `/locations`, `/departments`. (masi reads the careers widget instead,
  `apply.workable.com/api/v1/widget/accounts/{id}`, which is not in the vendor's documentation.)
- Holds: `title`, `shortcode`, `country`, `state`, `city`, `department`, `telecommuting`, `workplace_type`
  (`on_site`/`hybrid`/`remote`), `published_on`, `created_at`, `url`, `application_url`, `description` (with
  `details=true`), `employment_type`, `industry`, `function`, `experience`, `education`.
- Access: API. Registration or key: none for the public endpoints (the rest of the API needs a token). Cost: free.
- Licence or terms: none stated on the page.
- Seen on 2026-11-28: the documentation page -> 200, 45 kB ("Updated over 1 year ago"). No account was requested.

### SmartRecruiters - Posting API
- Publisher: SmartRecruiters (US; bought by SAP in 2025 - third party, from memory).
- Documentation: https://developers.smartrecruiters.com/docs/posting-api
- Data or endpoint: `GET https://api.smartrecruiters.com/v1/companies/{companyIdentifier}/postings` (paged) and
  `/postings/{postingId}` for the full text.
- Holds: `name`, `location` (city, region, `country`), `typeOfEmployment`, `releasedDate`, department, function,
  experience level, `jobAd` sections, `applyUrl` (field names from masi and from memory of the endpoint reference).
- Access: API. Registration or key: none for public postings (masi reads it so); the overview read today says "Posting
  API allows for access to a job posting that was previously made public using SmartRecruiters application" and
  speaks of an API key or OAuth only for *internal* postings. Cost: free.
- Licence or terms: none stated on the page read.
- Seen on 2026-11-28: the overview page -> 200, 40 kB ("Updated 3 months ago"). No company was requested.
- Caveats: the landing page answers 200 for any company name, so a wrong name cannot be told from an empty board (masi).

### Teamtailor - RSS feed (and `jobs.json`)
- Publisher: Teamtailor (Sweden); many Nordic and Baltic employers.
- Documentation: https://support.teamtailor.com/en/articles/11171756-rss-feed-how-to-guide
- Data or endpoint: "Go to the main jobs page of your careers site and add ".rss"", e.g.
  `https://career.teamtailor.com/jobs.rss` (`offset`, `per_page`; "the RSS feed will show the first 100 jobs").
  masi reads the same boards' `jobs.json` (a JSON Feed with a schema.org `_jobposting` object per item), which the
  support article does not mention.
- Holds: title, description, publication date, job URL, remote status, global ID, locations, department, role,
  division.
- Access: feed. Registration or key: none. Cost: free.
- Licence or terms (exact wording): "all of the data is publicly available"; the feed is meant for "other promotion
  channels where an XML feed or API integration is not possible".
- Seen on 2026-11-28: the support article through WebFetch ("Updated over 3 weeks ago"). No board was requested.
- Caveats: boards live on `{company}.teamtailor.com` or on the employer's own domain.

### Recruitee - Careers Site API
- Publisher: Recruitee (Netherlands; part of Tellent).
- Documentation: https://docs.recruitee.com/reference/offers
- Data or endpoint: `GET https://{yourcompany}.recruitee.com/api/offers/` - "Returns a collection of published company
  jobs. Offers can be filtered by department or tag."
- Holds: title, slug, description and requirements (HTML), location, city, `country_code`, remote flag, employment
  type, department, salary object, dates, careers URL (field names from memory of the reference, not re-read).
- Access: API. Registration or key: none for the Careers Site API. Cost: free.
- Licence or terms: none stated on the page read.
- Seen on 2026-11-28: the reference page -> 200, 40 kB. No company was requested.
- Caveats: masi's two Recruitee boards were empty on capture, so it has no collector.

### Personio - XML positions feed
- Publisher: Personio (Germany); widespread among German-speaking and other EU SMEs.
- Documentation: https://developer.personio.de/docs/retrieving-open-job-positions
- Data or endpoint: "Current open job postings can be retrieved in XML format under `myaccount.jobs.personio.de/xml`"
  (`?language=en`).
- Holds: `id`, `subcompany`, `office`, `department`, `recruitingCategory`, `name`, `jobDescriptions` (name + HTML
  value blocks), `employmentType` ("permanent", "intern", "trainee", "freelance"), `seniority`, `schedule`,
  `yearsOfExperience`, `keywords`, `occupation`, `createdAt`; masi also reads `salaryInformation`.
- Access: feed (XML). Registration or key: none. Cost: free.
- Licence or terms: none stated.
- Seen on 2026-11-28: the documentation page -> 200, 40 kB. No account was requested.
- Caveats: offices are city names; no country field (masi).

### BambooHR, Workday, Phenom, Eightfold, iCIMS, TeamDash - readable, but not documented as public APIs
- BambooHR (`{company}.bamboohr.com/careers/list` JSON + a detail call per opening), Workday
  (`{tenant}.wd{N}.myworkdayjobs.com`, the careers site's own `POST .../wday/cxs/{tenant}/{site}/jobs` search and a
  record per job), Phenom (the site's search widget), Eightfold (`/api/pcsx` search; answers 429 without the careers
  page's session), an employer's own iCIMS listing, TeamDash (HTML pages): all described in masi's `docs/sources.md`
  as the careers page's own back end. No vendor documentation presents them as a public API (BambooHR's and
  Workday's documented APIs need the customer's credentials), and no terms were found that grant reading. They work
  per employer and can change without notice. No request was made to any of them today.

### Others found (not masi hosts; from third parties, not verified against vendor documentation)
- Pinpoint: `https://{company}.pinpointhq.com/postings.json` (JSON; no posted date). Breezy HR:
  `https://{company}.breezy.hr/json`. HireHive: `https://{company}.hirehive.com/api/v1/jobs`. Manatal:
  `https://api.careers-page.com/open/v1/career-pages/{client_slug}/job-posts`. Sources: TheirStack's and Cavuno's
  blog lists, read through WebFetch/WebSearch. A third-party list of this kind is the nearest thing to a maintained
  comparison of ATS endpoints (topic 10).

## 6. Remote-job feeds and APIs

Every host in this topic is one masi's investigation of 2026-11-10 (`docs/remote-sources-investigation.md`) read, so
today each got at most one request, to a documentation or terms page. Volumes and place fields below are that
investigation's measurements ("masi, 11-10"), not today's. Country coverage is by the job's "open to" field, not by
board: a remote job is open to an EU country when its restriction field says so.

### Himalayas
- Publisher: Himalayas (himalayas.app).
- Documentation: https://himalayas.app/api (page says "Current as of Jul 15, 2026" in a search listing); OpenAPI
  spec and examples on GitHub (`Himalayas-App`).
- Data or endpoint: `GET https://himalayas.app/jobs/api` (whole feed, cursor), `GET /jobs/api/search` (keyword,
  `country` as ISO alpha-2, `exclude_worldwide`, seniority, type, timezone; 20 a page), a per-job status endpoint
  (410 when closed, masi), an RSS feed of the 100 newest, an MCP server.
- Holds: title, company, `locationRestrictions` (country names; empty = worldwide), `timezoneRestrictions`,
  seniority, employment type, salary range, description, `pubDate`, `expiryDate`, `applicationLink`, `guid`.
- Access: API, RSS. Registration or key: "No API key is required. Every endpoint works without one"; a free key
  (account) gives "60 requests per minute and 10,000 per day". Cost: free.
- Licence or terms (exact wording, https://himalayas.app/api): "You can show Himalayas jobs on your own job board,
  website or app without asking us first. Follow our API terms: Use the applicationLink for every Apply button,
  unchanged. Show a visible link to the job on Himalayas or to himalayas.app as the source. Show the jobs only on
  sites and apps you operate. Do not pass them on to other job boards, aggregators, Google Jobs or LinkedIn Jobs,
  including through feeds or JobPosting structured data. Remove jobs once they expire."
- Volume: 119,569 jobs in the whole feed; 3,904 open to Estonia (masi, 11-10).
- Update cycle: "Responses are cached for an hour or more".
- Seen on 2026-11-28: the documentation page -> 200, 41 kB. No data request.
- Caveats: `totalCount` "is an estimate that can be up to a day old"; no redistribution.

### Jobicy
- Publisher: Jobicy (jobicy.com).
- Documentation: https://jobicy.com/jobs-rss-feed (`jobi.cy/apidocs` redirects there).
- Data or endpoint: the page read today documents `GET https://jobicy.com/api/jobs?count=100&geo=...&industry=...&tag=...`
  with `nextCursor` pages, and `/api/jobs/status?ids=...` to check stored jobs; plus RSS and an MCP server.
  (masi's investigation of 11-10 used `/api/v2/remote-jobs` - **the documented path has changed or been renamed
  since**; not tested.)
- Holds: title, company, `jobGeo` (regions or country lists), industry, type, level, excerpt and description,
  salary where given, `pubDate`, `url` (the Jobicy page; the original ATS link only with a paid key).
- Access: API, RSS. Registration or key: "No API key" for the public API; an optional paid key ("each job with an
  available direct application URL costs $0.01"). Cost: free.
- Licence or terms (exact wording): "You may use Jobicy listings in your own products and user experiences without
  requesting individual permission. Clearly credit Jobicy as the original source when displaying listings." "You may
  store, cache, process, and retain Jobicy API data without a fixed retention period." "You may use AI models to
  analyze job data". FAQ: "You can store, cache, process, and redistribute job data as needed, keeping Jobicy
  credited as the source"; "keep apply links from the free API pointing to the original job pages on Jobicy"; "Start
  a new automated pass no more than once per hour"; limit "30 requests per second per IP address".
- Volume: about 100 Estonia-eligible jobs in four days (masi, 11-10); "listings published in the last 7 days" only,
  with "a three-hour publication delay".
- Seen on 2026-11-28: the documentation page -> 200, 88 kB. No data request.
- Caveats: **the most permissive terms of any source in this file** (store, redistribute, analyse), but a 7-day
  window and remote jobs only.

### We Work Remotely
- Publisher: We Work Remotely (weworkremotely.com).
- Documentation: https://weworkremotely.com/remote-job-rss-feed ; terms
  https://weworkremotely.com/terms-and-conditions
- Data or endpoint: RSS `https://weworkremotely.com/remote-jobs.rss` and one feed per category (masi).
- Holds: title, company, `<region>`, `<country>`, category, type, HTML description, `pubDate`, `expires_at` (masi).
- Access: RSS. Registration or key: none. Cost: free.
- Licence or terms: "Anyone can use the feed, all we ask is that you attribute the links back to We Work Remotely"
  (search-result text of the RSS page; the page itself was refused today). masi, 11-10: the terms ("Updated October
  23, 2026") contain no scraping or automation clause.
- Volume: 100 items in the all-jobs feed, 27 IT jobs open to Estonia (masi, 11-10).
- Seen on 2026-11-28: `GET https://weworkremotely.com/remote-job-rss-feed` -> **HTTP 403**, `cf-mitigated: challenge`
  (Cloudflare "Just a moment..." page) for curl; the host was not asked again.
- Caveats: **contradiction** - masi's investigation read this site on 11-10 with a browser-like User-Agent; a client
  that names itself is challenged today. Whether the RSS feeds themselves are challenged too was not tested.

### Remotive
- Publisher: Remotive (remotive.com).
- Documentation: https://github.com/remotive-com/remote-jobs-api
- Data or endpoint: `https://remotive.com/api/remote-jobs` (`category`, `company_name`, `search`, `limit`).
- Holds: title, company, category, job type, `publication_date`, `candidate_required_location`, salary text,
  description, URL.
- Access: API. Registration or key: none. Cost: free; "We offer a private, paid-for API".
- Licence or terms (exact wording, the README): "Please do not submit Remotive jobs to third Party websites,
  including but not limited to: Jooble, Neuvoo, Google Jobs, LinkedIn Jobs. Please link back to the URL found on
  Remotive AND mention Remotive as a source ... If you don't do that, we'll terminate your API access"; "Jobs
  displayed are delayed by 24 hours"; "we advise max. 4 times a day ... excessive requests (more than 2x per minute)
  will be blocked."
- Volume: the free API served 13 jobs in total (masi, 11-10); robots.txt `Disallow: /api/*` (masi).
- Seen on 2026-11-28: the README from GitHub -> 200, 2 kB. No request to remotive.com.
- Caveats: too small to matter; no passing on.

### Remote OK
- Publisher: Remote OK (remoteok.com).
- Documentation: none beyond the API's own first element (a "legal" notice).
- Data or endpoint: `https://remoteok.com/api` (JSON).
- Holds: position, company, tags, location (often blank), salary range, description, date, `apply_url` back to the
  site (masi).
- Access: API. Registration or key: none. Cost: free.
- Licence or terms (as recorded by masi, 11-10): "Please link back ... and mention Remote OK as a source ... If you
  do not we'll have to suspend API access."; robots `Content-Signal: search=yes,ai-train=no`.
- Volume: 99 jobs (masi, 11-10).
- Seen on 2026-11-28: no request (its only documentation is the data endpoint itself).

### Working Nomads
- Publisher: Working Nomads (workingnomads.com).
- Documentation: an "API" link in the site footer; terms https://www.workingnomads.com/terms-and-conditions
- Data or endpoint: `https://www.workingnomads.com/api/exposed_jobs/` (one JSON, masi).
- Holds: title, company, category, tags, `location` (free text), description, date, URL (masi).
- Access: API. Registration or key: none. Cost: free.
- Licence or terms: the terms read today contain no clause on scraping, automated access, feeds or reuse of
  listings (searched for scrap, robot, automat, crawl, harvest, republish); no API terms page was found.
- Volume: 36 jobs (masi, 11-10).
- Seen on 2026-11-28: the terms page -> 200, 19 kB.

### Hacker News "Ask HN: Who is hiring?"
- Publisher: Y Combinator (Hacker News); search API run by Algolia.
- Documentation: https://github.com/HackerNews/API (official Firebase API); https://hn.algolia.com/api (search API).
- Data or endpoint: official: `https://hacker-news.firebaseio.com/v0/item/<id>.json`; Algolia:
  `https://hn.algolia.com/api/v1/search_by_date?tags=story,author_whoishiring` then `/api/v1/items/{id}` (masi).
- Holds: one free-text comment per employer, monthly thread; by convention a header line "Company | Role | Location
  | REMOTE ...". No structured fields.
- Access: API. Registration or key: none. Cost: free.
- Licence or terms: the official README: "There is currently no rate limit." No reuse licence is stated there.
- Volume: 220 postings in November 2026, about 44 remote and open to Europe; 136 links to ATS boards (masi, 11-10).
- Seen on 2026-11-28: the official README from GitHub -> 200, 5.7 kB; `GET https://hn.algolia.com/api` -> 200, 2.4 kB
  (a JavaScript page with no readable text for a plain client).
- Caveats: mostly US employers; the value is the ATS links (topic 5).

### Others (from masi's investigation of 2026-11-10; not requested today)
- EU Remote Jobs (euremotejobs.com): feed and WordPress REST answer 401 "Not available". Landing.jobs, Welcome to
  the Jungle / Otta, Wellfound, Arc.dev: terms forbid automated reading. No Fluff Jobs and JustJoin.it (Polish
  market): robots.txt disallows `/api/`. 4dayweek.io: RSS of 50 jobs without a place field. Remote.co: no
  connection. europeremotely.com: parked. No further remote-job feed with usable terms turned up in today's search.

## 7. Sector portals with EU-wide reach

### EURAXESS - research jobs
- Publisher: European Commission (DG Research and Innovation).
- Documentation: https://euraxess.ec.europa.eu/jobs
- Data or endpoint: web search https://euraxess.ec.europa.eu/jobs/search. No RSS, API or export link is on the search
  page (its HTML was searched for rss, feed, xml, api, export, json).
- Holds: research and academic vacancies posted by institutions in 40-odd countries or imported from partner boards
  (seen today: "Talentech", "myScience", "Delft University of Technology via AcademicTransfer"). Per offer: title,
  organisation, country, posting date, department, work location (address), research field, researcher profile
  (R1-R4), funding programme, application deadline, description.
- Access: web pages only. Registration or key: none to read. Cost: free.
- Licence or terms: the site footer links the Commission's legal notice (CC BY 4.0 for content owned by the EU, "To use
  or reproduce content that is not owned by the EU, you may need to seek permission directly from the rightholders" -
  https://commission.europa.eu/legal-notice_en); the offers are the institutions' own. The EURAXESS-specific
  notice was not read.
- Volume: **6,947** offers on 28 November 2026 (all countries, the counter on the search page).
- Update cycle: daily (offers "Posted on: 28 November 2026" were on the first page).
- Seen on 2026-11-28: `GET https://euraxess.ec.europa.eu/jobs/search` -> 200, text/html, 21 kB: ten offers, the count,
  two `application/ld+json` blocks (not examined).
- Caveats: third-party scrapers exist (Apify); no official machine route was found. Country filter is a search
  facet, not a feed.

### EU Careers (EPSO) - EU institutions' and agencies' vacancies
- Publisher: European Personnel Selection Office, for the institutions, bodies and agencies ("the job vacancies
  published on this webpage are the sole responsibility of the EU institutions, bodies and agencies concerned" -
  search-result text of the site).
- Documentation: https://eu-careers.europa.eu/jobs_en
- Data or endpoint: **RSS feed** `https://eu-careers.europa.eu/node/244/rss_en` (linked from the jobs page as "RSS").
- Holds: per item: reference as title (e.g. "TRADE/COM/2026/2405"), link to the vacancy page, a short description,
  `pubDate`, and categories: institution (with the Publications Office corporate-body authority as domain), job
  field, city, contract type. The web list also shows grade and deadline.
- Access: RSS feed and web pages. Registration or key: none. Cost: free.
- Licence or terms: the feed says "(c) European Union, 1995-2026"; the site falls under the europa.eu legal notice
  (reuse allowed with credit, CC BY 4.0, for EU-owned content).
- Volume: 132 open vacancies on the jobs page; 30 items in the feed.
- Update cycle: continuous (newest item 27 November 2026 19:00).
- Seen on 2026-11-28: jobs page (`/en/job-opportunities/open-vacancies` redirects to `/jobs_en`) -> 200, 20 kB;
  the feed -> 200, application/rss+xml, 6.7 kB, 30 items.
- Caveats: the feed is the newest 30, not the whole list; workplaces are mostly Brussels, Luxembourg and the agency
  seats. Each agency also lists vacancies on its own site.

### Europass - "Find jobs"
- Publisher: European Commission.
- Documentation: https://europass.europa.eu/en/find-jobs
- Holds: nothing of its own: "Search results are provided by EURES - the European Job Mobility Portal."
- Access: web search only; the page offers no API, feed or download of jobs (its developer pages concern CV and
  profile interoperability, not vacancies - from the page's link titles, not read).
- Seen on 2026-11-28: one WebFetch of the page.
- Caveats: adds no vacancies beyond EURES (topic 1).

### Academic job feeds
- jobs.ac.uk (UK, with European posts): RSS feeds per subject area and per location, listed at
  https://www.jobs.ac.uk/feeds ("RSS links provide the raw RSS (XML) files, useful for feed syndication" -
  search-result text). The feeds page answered **404** to the fetch tool today, and its terms were not read.
- EURAXESS already carries the offers of several national academic boards (AcademicTransfer for the Netherlands was
  seen in today's results).
- AcademicTransfer, Academic Positions, Times Higher Education Unijobs, Nature Careers: no public feed or API was
  found in one search; not examined further (see Gaps).
