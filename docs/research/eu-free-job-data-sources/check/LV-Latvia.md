# Latvia (LV) - check of the research

The research file has no section on the employer route; it is added in a later pass.

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent, one capped GET per URL, one at a time;
web search for leads. No account, key or login. At most three requests per job-board host; the open data portal
`data.gov.lv` got six (record, search, two table queries, one 305 kB file). The statistics office was not
requested: out of purpose. The second table has one verdict per source, as the brief was simplified during
the check.

## Corrections and unverified claims (apply these first)

- No claim was found wrong. ADDITION (claim 3): what the NVA dataset covers, measured on today's file - 1 248 rows from 292 employers;
  715 rows carry an employer number beginning 90 (the series of public bodies), 532 a number beginning 4 or 5
  (the enterprise register's series); the three largest categories are "Veselības aprūpe / Sociālā aprūpe" 430,
  "Izglītība / Zinātne" 313, "Valsts pārvalde" 152. That fits the description "valsts sektorā" with public
  companies such as hospitals included; it does not prove that no private employer is in it.
- ADDITION: rows are not all fresh - `Aktualizacijas_datums` runs from 2025-06-02 to 2026-11-27.
- UNVERIFIED: cv.lv's terms of use - the terms page is again a script shell (200, 534 383 bytes, interface
  strings only); one guess at the sister host (`https://hr.cv.lv/noteikumi`) answered 404.
- UNVERIFIED: the outcome of the cv.lv court case (first-instance order not to link; the Senate sending the
  question back). Seen today on WIPO Lex: the Senate's decision of 4 June 2024, case C30638718, SKA-23/2024, SIA
  "CV-Online Latvia" (SIA "Alma Career Latvia") v SIA "Melons", on a cassation appeal against the Riga Regional
  Court's judgment of 25 February 2022. The outcome is not on the pages read.
- UNVERIFIED: whether NVA sends its vacancies to EURES - `www.nva.gov.lv` answered the one request with an HTTP/2
  stream error (curl 92, "INTERNAL_ERROR"); not retried. A search summary found no statement either.
- UNVERIFIED: that civil-service competitions are published on CVVP - a LETA notice with that title appears in
  today's search results; not opened.
- UNVERIFIED: the data.europa.eu copy of the dataset (stale date 2020-04-07, no licence) - not re-requested.
- UNVERIFIED: the statistics office block (PxWeb, CC0, limits) and its unreachable host - not requested:
  statistics.
- UNVERIFIED: `https://www.cv.lv/lv` (1 149 774 bytes) - not re-requested (request limit).

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | NVA publishes the dataset "Vakances" on data.gov.lv, id cb6831cb-1d89-44a3-b889-b43c411df4fe | CONFIRMED | GET `https://data.gov.lv/dati/api/3/action/package_show?id=cb6831cb-1d89-44a3-b889-b43c411df4fe` -> 200, application/json, 3 353 bytes: name `vakances`, organisation "Nodarbinātības Valsts Aģentūra" | - |
| 2 | Description: "Uzņēmumu un organizāciju izsludinātās aktuālās vakances Latvijas valsts sektorā" | CONFIRMED | `notes`: "Uzņēmumu un organizāciju izsludinātās aktuālās vakances Latvijas valsts sektorā."; the resource is described "Aktuālās NVA vakances" | - |
| 3 | It holds state-sector vacancies only, not the whole vacancy bank | NOT DISPROVED | The description says state sector. In the file: 715 rows with employer numbers beginning 90, 485 beginning 4, 47 beginning 5, 1 beginning 2; 292 distinct employers; health and social care 430, education and science 313, state administration 152 rows | Consistent with the public sector including public companies; not proof |
| 4 | Licence `license_id` "CC0-1.0" | CONFIRMED | `license_id: CC0-1.0`, `license_title: CC0-1.0` | - |
| 5 | Daily CSV, 304 782 bytes, file name carries the date; no key | CONFIRMED | Resource `7f68f6fc-...`, format CSV, size 304782, url `.../download/vakances-2026-11-28.csv`; GET of it -> 200, text/csv, 304 782 bytes, no key | - |
| 6 | Declared daily; last modified 2026-11-27T23:02 | CONFIRMED | `frequency: .../frequency/DAILY`; `last_modified: 2026-11-27T23:02:02` | - |
| 7 | Columns: Vakances_Nr, Aktualizacijas_datums, Iestades_registracijas_numurs, Vakances_nosaukums, Vakances_kategorija, Alga_no, Alga_lidz, Slodzes_tips, Darba_laika_veids, Darba_stundas_nedela, Pieteiksanas_termins, Attels, Vieta, Vakances_paplasinats_apraksts | CONFIRMED | The CSV header has exactly these 14 columns | - |
| 8 | No description text, no employer name, no occupation code; the last column is a link `https://cvvp.nva.gov.lv/#/pub/vakances/<id>` | CONFIRMED | No such columns; all 1 248 rows have a link beginning `https://cvvp.nva.gov.lv/#/pub/vakances`; the employer appears only as a registration number | - |
| 9 | 1 248 rows on 2026-11-28 | CONFIRMED | 1 248 data rows in the CSV; datastore `total: 1248` | - |
| 10 | Queryable through the portal's API | CONFIRMED | GET `https://data.gov.lv/dati/api/3/action/datastore_search?resource_id=7f68f6fc-a0f9-4c31-b43c-770e97a06fda&limit=2` -> 200, application/json, 2 296 bytes | - |
| 11 | package_search?q=vakances -> 4 datasets | CONFIRMED | GET `...package_search?q=vakances&rows=10` -> 200, 28 678 bytes, count 4: vakances; two NVA monthly statistics; "TVP tīmekļvietņu saturs" | - |
| 12 | CVVP terms at https://cvvp.nva.gov.lv/pielikumi/CVVP_lietosanas_noteikumi.pdf; clause 4.7 as quoted | CONFIRMED | GET -> 200, application/pdf, 86 135 bytes: "4.7. citējot vai atsaucoties uz Portālā iegūto informāciju, norādīt informācijas avotu – pārpublicēšanas gadījumā atsauce uz autortiesību īpašnieku ir obligāta." | - |
| 13 | Clause 4.5 forbids unauthorised actions against the portal's speed and security; nothing on automated reading | CONFIRMED | "4.5. neveikt nesankcionētas darbības, kas vērstas pret Portāla ātrdarbību un Portāla drošību, ietekmējot tā konfidencialitāti, integritāti, pieejamību un darbības stabilitāti." The whole text (seven points) was read: no clause on robots, programs or automated queries. "Lietotājs – jebkura persona, kura atbilstoši šiem noteikumiem lieto Portālu"; 4.1 gives the right "iepazīties ar Portālā esošo informāciju" | - |
| 14 | CVVP robots.txt: "User-agent: * Content-Signal: search=yes,ai-train=no,use=reference Allow: /", then "Disallow: /" for named AI and crawler agents | CONFIRMED | GET `https://cvvp.nva.gov.lv/robots.txt` -> 200, text/plain, 2 676 bytes; those three lines, then 32 named agents (Amazonbot, Bytespider, CCBot, ClaudeBot, GPTBot, Google-Extended, anthropic-ai, Baiduspider, PetalBot ...) each "Disallow: /" | - |
| 15 | CVVP: web application, no documented API or feed; accounts through latvija.lv | NOT DISPROVED | Terms 5.1: "Nodrošināt Lietotājam pieeju Portālam, izmantojot www.latvija.lv autentifikācijas līdzekļus". No feed or API named in the terms or found by search | - |
| 16 | CVVP holds all vacancies registered with the agency; civil-service competitions are published there | UNVERIFIED | Not on a page read; a LETA notice titled "Turpmāk ierēdņu amata konkursi tiks publicēti NVA vakanču portālā" is in today's search results | - |
| 17 | NVA monthly vacancy statistics: two datasets, one XLSX per year 2021-2026, CC0-1.0, both modified 2026-11-12 | CONFIRMED | In the package_search answer: both `CC0-1.0`, MONTHLY, six XLSX each (1.0-1.9 MB), 2026 files modified 2026-11-12 | Statistics: of no use for the purpose |
| 18 | TVP vacancy table: State Chancellery, `vacancy.csv` 524 455 bytes, CC0-1.0 | CONFIRMED | package_search: "TVP tīmekļvietņu saturs", Valsts kanceleja, `CC0-1.0`, `vacancy.csv` size 524455 | - |
| 19 | TVP fields: title, salary, form, category, NVA id, deadline, apply type, external link, description, place, institution registration number, domain, page link, language | CONFIRMED | GET `...datastore_search?resource_id=01abba21-3025-48be-935b-e5d4909299be&limit=2` -> 200, 3 105 bytes: `field_vacancy_salary`, `_image`, `_form`, `_category`, `_nva_id`, `_deadline`, `_apply_type`, `_external_link`, `_weight_value`, `_description`, `field_easy_to_read`, `field_vacancy_place`, `field_institution_reg_number`, `title`, `domain`, `view_node`, `language` | - |
| 20 | TVP: 974 rows, the first one the column names; declared daily but last modified 2026-07-18 | CONFIRMED | `total: 974`; record 1 repeats the field names; frequency DAILY; every resource `last_modified 2026-07-18T23:5x`. Record 2 has deadline "01.08.2026" | - |
| 21 | cv.lv is operated by SIA Alma Career Latvia | CONFIRMED | WIPO Lex record (GET `https://www.wipo.int/wipolex/en/judgments/details/3253` -> 200): "Plaintiff/Appellant SIA "CV-Online Latvia" (SIA "Alma Career Latvia”)"; summary: "Website www.cv.lv contains a database, which includes job advertisements published by employers". The cv.lv page itself says only "We are a member of Alma Career family" | - |
| 22 | cv.lv robots.txt, whole file: "Sitemap: https://www.cv.lv/sitemap.xml" | CONFIRMED | GET -> 200, text/plain, 39 bytes, that line | - |
| 23 | cv.lv terms page loads its text by script; not read | CONFIRMED | GET `https://www.cv.lv/lv/terms` -> 200, text/html, 534 383 bytes: page data with interface strings only; no terms text | Terms still unread |
| 24 | Interface text about an API key an employer creates "lai integrētu ārējās sistēmas ar savu CV.lv kontu" | CONFIRMED | In the page data: "Izveidojiet API atslēgu (lietojumprogrammu saskarnes atslēgu), lai integrētu ārējās sistēmas ar savu CV.lv kontu." | - |
| 25 | The operator sued SIA "Melons" (kurdarbs.lv) over reuse of its advert database; first instance ordered no linking; the Senate sent the question back in 2024 | UNVERIFIED | The case and the Senate's decision of 4 June 2024 are on WIPO Lex (keywords "Database extraction, Web scraping, Job search websites"); the outcome was not on the pages read | The case is confirmed; its outcome is not |
| 26 | CVMarket.lv is governed by the CV Keskus terms (clause 1.1), whose clause 2.10 forbids automated queries, 10 000 EUR per breach | CONFIRMED | Read today on `https://www.cvkeskus.ee/kasutustingimused` (see the Estonia check): "1.1. ... reguleerivad veebikeskkonna www.cvkeskus.ee, www.cvmarket.lv ja www.cvmarket.lt (Veebikeskkond) kasutamist."; 2.10 as quoted; "Viimati muudetud: 18.10.2021" | - |
| 27 | CVMarket.lv robots.txt (961 bytes) disallows account, login and CV paths only and lists listing sitemaps | CONFIRMED | GET `https://www.cvmarket.lv/robots.txt` -> 200, text/plain, 961 bytes; also "Sitemap: https://www.cvmarket.lv/rss-listings.xml" | - |
| 28 | Visidarbi.lv robots.txt, whole file: "User-agent: * Disallow: Sitemap: ... Crawl-Delay: 10 crawl-delay: 10" | CONFIRMED | GET `https://www.visidarbi.lv/robots.txt` -> 200, text/plain, 104 bytes, those lines | - |
| 29 | Official statistics (CSB): PxWeb, CC0, limits; host unreachable | UNVERIFIED | Not requested: statistics | - |
| 30 | Whether NVA sends its vacancies to EURES: not established | UNVERIFIED | `https://www.nva.gov.lv/sites/nva/files/data_content/nva-pakalpojumi-darba-devejiem.pdf` -> curl 92, HTTP/2 stream error, no body; not retried | - |
| 31 | No paid vacancy data product was found on any page read | NOT DISPROVED | None on the pages read today | - |
| 32 | No other open vacancy dataset for Latvia | NOT DISPROVED | data.gov.lv search "vakances": the 4 datasets above. data.europa.eu, country lv, "vakances darba sludinājumi brīvās darba vietas": 609 loose matches, the first 15 hold no vacancy listing beyond NVA's statistics | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (deciding clause if "no") |
|---|---|---|
| NVA "Vakances" open dataset | yes | CC0-1.0, no key, daily file and API; title, salary, place, deadline and a link to the advert on CVVP. Public-sector part only; no advert text |
| NVA CV and vacancy portal (CVVP) | unclear | Terms silent on automated reading: any person may read the information (4.1), no unauthorised actions against speed and security (4.5), source credit when republishing (4.7). robots.txt allows all paths to unnamed agents. A script application with no documented feed |
| State institutions' vacancy table (TVP) | no | Not for its licence (CC0-1.0) but for its state: not refreshed since 2026-07-18, deadlines past |
| cv.lv | unclear | Terms could not be read (script shell); robots.txt has no rules; the operator has gone to court against an aggregator over its database |
| CVMarket.lv | no | CV Keskus terms 2.10: "Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või vahendite abil, mis võimaldavad teha ilma inimese sekkumiseta automaatseid päringuid." (10 000 EUR per breach) |
| Visidarbi.lv | unclear | Terms not read; robots.txt disallows nothing and asks "Crawl-Delay: 10" |
| NVA monthly statistics; statistics office | no | Counts only, no adverts |

## Found beyond the research

- The NVA file can be measured: 292 employers, 57 % of rows from numbers of the public-body series; the TVP
  table carries the same NVA vacancy numbers (`field_vacancy_nva_id`, e.g. "260707-112"), so the dataset looks
  like the feed behind the vacancy pages of state and municipal websites.
- CVMarket.lv's robots.txt lists `https://www.cvmarket.lv/rss-listings.xml` among its sitemaps (not requested;
  clause 2.10 forbids automated queries regardless).
- WIPO Lex holds the Senate's 2024 decision in the cv.lv database case, with an English summary
  (`https://www.wipo.int/wipolex/en/text/596504`).
- CVVP's terms define the user as "jebkura persona" and carry no date.
- Still unchecked, as in the research: ss.lv job classifieds, prakse.lv, LinkedIn and other boards; a separate
  civil-service portal.
