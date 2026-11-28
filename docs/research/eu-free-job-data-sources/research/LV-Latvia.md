# Latvia (LV) - free online job data sources: research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (one capped GET per URL), the Claude Code
WebFetch tool with its own default client, and web search. No account, key or login was used.

## Takeaway

The best free source is the State Employment Agency's dataset "Vakances" on the national open data portal: a
daily CSV, also queryable through the portal's API, under CC0, with no key. But it is narrower than its name:
its description says it holds current vacancies "in the Latvian state sector", it had 1 248 rows today, and each
row carries title, category, salary range, workload, deadline, place and a link to the advert on the agency's
portal - not the advert text and not the employer's name (only its registration number). The agency's full
vacancy portal (CVVP) is a web application with no documented feed; its terms ask for a source credit when
republishing. Monthly vacancy counts are open (XLSX, CC0). The commercial boards offer no read feed; cv.lv's
terms could not be read, and its operator has taken an aggregator to court over its database. The statistics
office's API could not be reached from this address.

## Sources

### NVA "Vakances" - open dataset of current vacancies
- Publisher: Nodarbinātības valsts aģentūra, NVA (State Employment Agency).
- Documentation: https://data.gov.lv/dati/lv/dataset/vakances ; on data.europa.eu
  https://data.europa.eu/data/datasets/cb6831cb-1d89-44a3-b889-b43c411df4fe
- Data or endpoint: daily file, e.g.
  `https://data.gov.lv/dati/dataset/cb6831cb-1d89-44a3-b889-b43c411df4fe/resource/7f68f6fc-a0f9-4c31-b43c-770e97a06fda/download/vakances-2026-11-28.csv`
  (the file name carries the date); API
  `https://data.gov.lv/dati/api/3/action/datastore_search?resource_id=7f68f6fc-a0f9-4c31-b43c-770e97a06fda`
- Holds: Vakances_Nr (number), Aktualizacijas_datums (update date), Iestades_registracijas_numurs (employer's
  registration number), Vakances_nosaukums (title), Vakances_kategorija (category), Alga_no / Alga_lidz (salary
  from / to), Slodzes_tips (workload), Darba_laika_veids (working-time type), Darba_stundas_nedela (hours a
  week), Pieteiksanas_termins (deadline), Attels (image), Vieta (place: street, town, municipality),
  Vakances_paplasinats_apraksts (a link to the advert, `https://cvvp.nva.gov.lv/#/pub/vakances/<id>`). No
  description text, no employer name, no occupation code.
- Access: bulk CSV (304 782 bytes); CKAN datastore API.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): the portal's record gives `license_id` "CC0-1.0"
  (https://data.gov.lv/dati/api/3/action/package_search?q=vakances).
- Volume: 1 248 rows on 2026-11-28.
- Update cycle: declared daily; the file was last modified 2026-11-27T23:02.
- Seen on 2026-11-28: GET package_search?q=vakances&rows=10 -> 200, application/json, 28 678 bytes, 4
  datasets; GET datastore_search ... &limit=2 -> 200, 2 296 bytes, 2 records (a janitor post in Lielvārde, a
  client-service post in Ādaži, each with salary and a CVVP link).
- Caveats: the description reads "Uzņēmumu un organizāciju izsludinātās aktuālās vakances Latvijas valsts
  sektorā" (current vacancies announced by enterprises and organisations in the Latvian state sector), and the
  row count fits a public-sector subset, not the whole vacancy bank. The data.europa.eu copy shows a stale
  modification date (2020-04-07) and no licence; the national portal is the one to trust.

### NVA CV and vacancy portal (CVVP)
- Publisher: NVA.
- Documentation: terms https://cvvp.nva.gov.lv/pielikumi/CVVP_lietosanas_noteikumi.pdf
- Data or endpoint: https://cvvp.nva.gov.lv (web application; adverts at `#/pub/vakances/<id>`).
- Holds: all vacancies registered with the agency; civil-service competitions are published here too (a LETA
  notice and the State Chancellery's proposal, seen in search results).
- Access: web only; no documented API or feed found.
- Registration or key: none to browse; authentication through latvija.lv for accounts.
- Cost: free.
- Licence or terms (exact wording, with URL): terms, clause 4.7: "citējot vai atsaucoties uz Portālā iegūto
  informāciju, norādīt informācijas avotu - pārpublicēšanas gadījumā atsauce uz autortiesību īpašnieku ir
  obligāta" (when quoting or referring to information obtained in the Portal, state the source - when
  republishing, a reference to the copyright owner is mandatory). Clause 4.5 forbids unauthorised actions
  against the portal's speed and security. Nothing on automated reading. robots.txt
  (https://cvvp.nva.gov.lv/robots.txt): "User-agent: * Content-Signal: search=yes,ai-train=no,use=reference
  Allow: /", then "Disallow: /" for named AI and crawler agents (Amazonbot, Bytespider, CCBot, ClaudeBot,
  GPTBot, Google-Extended, anthropic-ai, Baiduspider, PetalBot and others).
- Volume: not read.
- Update cycle: continuous.
- Seen on 2026-11-28: GET of the terms PDF -> 200, application/pdf, 86 135 bytes; GET /robots.txt -> 200,
  text/plain, 2 676 bytes. No data request.
- Caveats: the robots file opens with a statement that accessing the site means agreeing to its content
  signals; training use is refused.

### NVA monthly vacancy statistics
- Publisher: NVA.
- Documentation: https://data.gov.lv/dati/lv/dataset/registreto-brivo-darba-vietu-skaits-parskata-perioda and
  https://data.gov.lv/dati/lv/dataset/brivo-darba-vietu-skaits-parskata-perioda-beigas
- Data or endpoint: one XLSX per year 2021-2026 in each dataset, e.g.
  `https://data.gov.lv/dati/lv/dataset/f1c93b35-6f6e-4729-9e8a-e662012ab338/resource/90e7d4c7-b7ee-4c2c-b26d-9d863f7a846e/download/reg_vak_2026.xlsx`
  (registered in the period) and
  `https://data.gov.lv/dati/lv/dataset/5f5a8e1a-f1f5-498a-8dfe-739425d17ec4/resource/86419721-13f4-4222-b0a5-401730472824/download/aktualas_vakances_mb_2026.xlsx`
  (open at month end).
- Holds: numbers of registered vacancies in the period and of vacancies open at the end of the period.
  Breakdown not examined (files not downloaded).
- Access: bulk XLSX, about 1.0-1.9 MB each.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): `license_id` "CC0-1.0" on both records.
- Volume: six yearly files each.
- Update cycle: monthly (both last modified 2026-11-12).
- Seen on 2026-11-28: the records in the package_search answer above; no file requested.
- Caveats: none.

### State institutions' websites - vacancy table (TVP)
- Publisher: Valsts kanceleja (State Chancellery).
- Documentation: https://data.gov.lv/dati/lv/dataset/tvp-saturs
- Data or endpoint:
  `https://data.gov.lv/dati/dataset/5b2f8783-05b7-4ee9-8426-6d8b4e48f810/resource/01abba21-3025-48be-935b-e5d4909299be/download/vacancy.csv`
- Holds: vacancies posted on the websites of the unified state web platform: title, salary, form, category,
  NVA id, deadline, apply type, external link, description, place, institution registration number, domain,
  page link, language.
- Access: bulk CSV (524 455 bytes); CKAN datastore API.
- Registration or key: none.
- Cost: free.
- Licence or terms (exact wording, with URL): `license_id` "CC0-1.0".
- Volume: 974 rows in the datastore (one of them a header row repeated as data).
- Update cycle: declared daily, but the files were last modified 2026-07-18: stale by four months.
- Seen on 2026-11-28: GET datastore_search ... &limit=1 -> 200, application/json, 2 121 bytes.
- Caveats: not refreshed since July 2026, so its deadlines are likely past (not checked row by row); the first
  record is the column names.

### CV.lv (CV-Online Latvia)
- Publisher: SIA Alma Career Latvia (the operator of cv.ee's sister site; same platform).
- Documentation: none found for reading vacancies. Terms page https://www.cv.lv/lv/terms
- Data or endpoint: https://www.cv.lv
- Holds: job adverts (not examined).
- Access: web only. The site's interface texts mention an API key that an employer creates "lai integrētu
  ārējās sistēmas ar savu CV.lv kontu" (to integrate external systems with its own CV.lv account) - an
  employer-side integration, not a public read feed.
- Registration or key: none to browse.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): NOT READ - the terms page loads its text by script and the
  three-request limit was reached. robots.txt (https://www.cv.lv/robots.txt), whole file: "Sitemap:
  https://www.cv.lv/sitemap.xml" (no rules).
- Volume: not read.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 39 bytes; GET /lv -> 200, text/html, 1 149 774 bytes;
  GET /lv/terms -> 200, text/html, 534 383 bytes (application shell and interface strings, no terms text).
- Caveats: the operator enforces its database right. Third-party sources (a Supreme Court summary on
  at.gov.lv, ifinanses.lv, the WIPO Lex record, all seen in search results) describe its case against SIA
  "Melons", operator of the job search site kurdarbs.lv, over reuse of cv.lv's advert database; a
  first-instance judgment ordered the defendant not to link into the database, and the Senate sent the question
  of sui generis protection back in 2024. The Estonian sister site's terms forbid extracts and copies of the
  database (see the Estonia file).

### CVMarket.lv
- Publisher: CV Keskus OÜ (Estonia).
- Documentation: none for reading. Terms: the CV Keskus terms, which state in clause 1.1 that they govern
  www.cvkeskus.ee, www.cvmarket.lv and www.cvmarket.lt (https://www.cvkeskus.ee/kasutustingimused).
- Data or endpoint: https://www.cvmarket.lv ; sitemaps of listings named in robots.txt.
- Holds: job adverts (not examined).
- Access: web only.
- Registration or key: none to browse.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): clause 2.10 of those terms (Estonian original, read today on the
  Estonian site): "Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või vahendite abil, mis võimaldavad
  teha ilma inimese sekkumiseta automaatseid päringuid. Käesoleva punkti rikkumisel on CV Keskusel õigus nõuda
  igalt rikkujalt leppetrahvi 10 000 eurot iga rikkumise eest." (automated queries without human intervention
  are forbidden; contractual penalty 10 000 euros per breach). robots.txt
  (https://www.cvmarket.lv/robots.txt) disallows account, login and CV paths only and lists listing sitemaps.
- Volume: not read.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 961 bytes. No other request.
- Caveats: the Latvian-language version of the terms on cvmarket.lv was not read.

### Visidarbi.lv
- Publisher: not confirmed on a page read (a job aggregator and board).
- Documentation: none found.
- Data or endpoint: https://www.visidarbi.lv
- Holds: job adverts gathered from several sites (not examined).
- Access: web only as far as checked.
- Registration or key: none to browse.
- Cost: free to browse.
- Licence or terms (exact wording, with URL): https://www.visidarbi.lv/robots.txt, whole file: "User-agent: *
  Disallow: Sitemap: https://www.visidarbi.lv/sitemap.xml Crawl-Delay: 10 crawl-delay: 10". Terms not read.
- Volume: not read.
- Update cycle: continuous.
- Seen on 2026-11-28: GET /robots.txt -> 200, text/plain, 104 bytes.
- Caveats: none.

### Official statistics - occupied posts and job vacancies
- Publisher: Centrālā statistikas pārvalde (Central Statistical Bureau), Official Statistics Portal.
- Documentation: https://stat.gov.lv/en/api-and-code-list-registry/api ; metadata
  https://stat.gov.lv/en/metadata/2878-occupied-posts-and-job-vacancies (neither fetched).
- Data or endpoint: PxWeb database at data.stat.gov.lv (tables under START / EMP / DV); API v2 described at
  api.stat.gov.lv/api/v2/index.html.
- Holds: quarterly and annual numbers of occupied posts and job vacancies from the employer survey.
- Access: API and web tables (XLSX, CSV, JSON, JSON-stat, PX per a search summary of the API page).
- Registration or key: none, per the same summary.
- Cost: free.
- Licence or terms (exact wording, with URL): not read directly. A search summary of the API page says the API
  uses the Creative Commons Zero (CC0) licence and limits a request to 10 000 data cells and an address to 30
  requests per 10 seconds.
- Volume: not read.
- Update cycle: quarterly.
- Seen on 2026-11-28: GET https://data.stat.gov.lv/api/v1/en/OSP_PUB?query=vacancies -> no connection ("Failed
  to connect to data.stat.gov.lv port 443"), twice, a few minutes apart. Not tried further.
- Caveats: everything in this block except the failed connection comes from search summaries.

## Not free or not allowed

- CVMarket.lv: automated queries forbidden, 10 000 € per breach (CV Keskus terms, clause 2.10).
- cv.lv: no read feed; the operator has sued an aggregator over reuse of its advert database (third-party
  reports). Its terms were not read.
- CVVP: training use refused by its robots.txt content signal ("ai-train=no"); republishing needs a source
  credit.
- No paid vacancy data product was found described on any page read.

## Gaps

- Whether NVA's "Vakances" dataset is meant to be the whole vacancy bank or the public-sector part only: the
  description says state sector and the row count agrees, but no page read says so in terms.
- The number of live vacancies on CVVP, cv.lv, CVMarket.lv and Visidarbi.lv: not read.
- cv.lv's terms of use: not read (client-rendered page; request limit reached).
- The statistics office's vacancy tables, their ids and the licence wording: host unreachable from this
  address; described from search summaries only.
- Whether NVA sends its vacancies to EURES: not established.
- A separate civil-service vacancy portal: search results say competitions are published on NVA's CVVP; no
  other portal was found, and none was looked for further.
- ss.lv job classifieds, LinkedIn, prakse.lv and other boards: not checked.
