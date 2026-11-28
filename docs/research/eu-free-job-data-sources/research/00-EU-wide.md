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
