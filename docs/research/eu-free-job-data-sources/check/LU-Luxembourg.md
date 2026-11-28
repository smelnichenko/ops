# Luxembourg (LU) - check of the research

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent (`curl/8.14.1`), no added headers, no
`-L`, every transfer capped (`--max-filesize 2000000 -m 30`), one request at a time. Web search (run by the
search service, not from this address) only to find page addresses. No account, key or login.
Requests per host: data.public.lu 5, adem.public.lu 3, govjobs.public.lu 3, data.europa.eu 2, and 1 each to
gouvernement.lu, download.data.public.lu (a 4,000-byte range), catalog.inspire.geoportail.lu, www.lbr.lu,
e-justice.europa.eu, www.jobs.lu (301), en.jobs.lu (404), www.jobfinder.lu, www.monster.lu (301),
www.skeeled.com. No request to moovijob.com (it refused the researcher). Indeed and LinkedIn were read once
today for the France check. No employer's board, no vendor data endpoint and none of the JobBoard's own data
addresses was requested.

The research file has the section "Through the employers"; it is checked below (claims 18-27).

## Corrections and unverified claims (apply these first)

- CORRECTED (claim 1): **the JobBoard is not a separate application; it is a component of the page
  https://adem.public.lu/fr/jobboard.html itself.** The HTML holds `<div class="cmp-jobboard" data-config=...>`
  whose configuration names three same-site addresses - `/ctie/jobboard?id=...`, `/ctie/jobboard/offer?id=...`,
  `/ctie/jobboard/search?id=...` - 20 items a page, a detail page `/fr/jobboard/offre.html`, and the filters
  `offerType`, `duration`, `time`, `domain`, `canton`, `languages`. None of them was requested. They are not
  documented anywhere that was read.
- CORRECTED (claim 4): what the robots.txt rule means here - "User-agent: * / Disallow: /*?*" closes to every
  robot each address that carries a query string, and all three JobBoard data addresses carry one. So the
  verdict for reading the JobBoard by program is "no", not "unclear".
- CORRECTED (claim 6): the closed-vacancy dataset's six files are 61-147 MB, not 97-147 MB (2015-2016:
  61,421,772 bytes; 2017-2018: 97,317,719; 2019-2020: 99,575,921; 2021-2022: 146,764,770; 2023-2024:
  134,802,258; 2025-2026: 130,986,979).
- CORRECTED (claim 7): the research's verdict "no" for that dataset is withdrawn - an archive of past adverts
  counts as usable. It is CC0; it covers vacancies published from 2015 on; per its own description it carries no
  employer name or number, and it does carry an occupation (ROME code and label), a skill (ESCO label and URI),
  a sector (NACE code and label), the canton, the number of positions and the month and year of publication.
- UNVERIFIED (blocked): Moovijob - its robots.txt rules and the 403 challenge. No request made.
- UNVERIFIED: that jobs.lu belongs to the Stepstone group (from memory in the research; not on a page read);
  Monster Luxembourg's liquidation (third party); the closure of the beneficial-owner register (third party);
  the EURES count of 3,223 (EU-wide file).
- UNVERIFIED: GovJobs' list of open posts and the way to apply - not requested (three requests spent on the home
  page, the legal notice and robots.txt).
- UNVERIFIED: the employer directories named from memory (Luxinnovation, Chamber of Commerce, Editus, Paperjam)
  - not requested.
- UNVERIFIED: that Skeeled is Luxembourg-based - its own home page was read and does not say so; it documents no
  feed or API there.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | The JobBoard is reached from https://adem.public.lu/fr/jobboard.html; the application's own address was not found in the page's HTML (78,189 bytes; no offer and no link to the application) | CORRECTED | GET https://adem.public.lu/fr/jobboard.html -> 200, text/html, 78,191 bytes, "Dernière modification le 26.11.2026": a `cmp-jobboard` element with `endpoint` `/ctie/jobboard?id=<base64 of the page's content path>`, `offerEndpoint` `/ctie/jobboard/offer?id=...`, `searchEndpoint` `/ctie/jobboard/search?id=...`, `itemsPerPage` 20, `detailUrl` `/fr/jobboard/offre.html`, six filters. No offer in the HTML | The JobBoard is embedded in that page and filled by script from three same-site addresses with a query string. |
| 2 | Press release of 29.10.2026: a first version of the new JobBoard is online; it shows "l'ensemble des offres d'emploi pour lesquelles les employeurs ont autorisé une candidature directe"; "2.500 offres d'emploi sont actuellement disponibles"; open to "Toutes les personnes à la recherche d'un emploi, qu'elles soient inscrites ou non à l'ADEM"; the old JobBoard is offline for good after an incident; a second version is due "début décembre 2026" | CONFIRMED | GET https://gouvernement.lu/fr/actualites/toutes_actualites/communiques/2026/10-octobre/29-jobboard.html -> 200, text/html, 90,893 bytes ("Crée le 29.10.2026"): every passage word for word; also "accessible depuis le site www.adem.lu" and "L'accès des employeurs aux profils des candidats sera possible dans une troisième version du JobBoard" | - |
| 3 | ADEM legal notice: "aucune reproduction des informations ou Services, totale ou partielle [...] n'est permise sans l'autorisation écrite préalable de l'Organisme. Sauf indication contraire, l'usager est autorisé à consulter, télécharger et imprimer les documents et informations disponibles aux conditions suivantes : Les documents ne peuvent être utilisés qu'à titre personnel, pour information et dans un cadre strictement privé ; [...] Les documents et informations ne peuvent être diffusés en dehors du site." | CONFIRMED | GET https://adem.public.lu/fr/support/aspects-legaux.html -> 200, text/html, 96,139 bytes: word for word; no word robot, automatis, extraction or scrap | - |
| 4 | ADEM robots.txt: several SEO bots shut out; all agents "Disallow: /*?*" with "Allow: /*?b=*", and search paths disallowed; the research reads the site as "unclear" for programs | CORRECTED | GET https://adem.public.lu/robots.txt -> 200, text/plain, 529 bytes: eight named bots with "Disallow: /"; "User-agent: *", "Disallow: /*?*", "Allow: /*?b=*", "Disallow: /*?b=*&*", "Disallow: /*?*&b=*", "Disallow: /*?*&r=*", "Disallow: /*?*&q=*", "Disallow: /*?r=*", "Disallow: /*?q=*", "Disallow: /*support/shopping*", "Disallow: /*support/recherche*" | The rule covers the JobBoard's own data addresses (claim 1): a robot may not fetch them. |
| 5 | The JobBoard is a web application only: no API, feed or dump | NOT DISPROVED | No documented one found: portal search (claim 8), EU portal search (claim 9). The page's own script addresses exist but are undocumented and closed by robots.txt | - |
| 6 | "Skills required in ADEM job vacancies": CC0 (`cc-zero`), quarterly, last update 2026-11-20, six files of 97-147 MB, one of 130,986,979 bytes; "Each row of the dataset corresponds to a vacancy-skill combination"; "Active job ads (i.e., vacancies that are currently open) are not displayed."; no title text, employer or link | CORRECTED | GET https://data.public.lu/api/1/datasets/skills-required-in-adem-job-vacancies/ -> 200, application/json, 10,579 bytes: `license` cc-zero, `frequency` quarterly, `last_modified` 2026-11-20, publisher ADEM, both sentences; variables Vacancy_id, Skill, Skill_uri, Positions, Month, Year, Canton, Occupation_code, Occupation_label, NACE_code, NACE_label; six CSV files of 61,421,772 to 146,764,770 bytes | Six files of 61-147 MB. The rest stands. |
| 7 | That dataset is not usable for a job search ("no"), because it leaves out open vacancies and names no employer | CORRECTED | Same record: vacancies since 2015 ("transferred to ADEM's database between 2015 and now"), licence CC0, occupation and skill fields, no employer field | Usable as an archive (CC0): which occupations, skills and sectors were advertised, by canton and month; no employer. |
| 8 | A search of the national portal for "ADEM" returns this dataset only; employers must declare vacancies to ADEM | CONFIRMED | GET `https://data.public.lu/api/1/datasets/?q=ADEM&page_size=30` -> 200, total 1. Record description: "Employers in Luxembourg are legally obliged to transfer their open job vacancies to ADEM." A second search, `q=offres d'emploi vacancies` -> total 0 | - |
| 9 | Luxembourg has no open feed or dataset of live vacancies | NOT DISPROVED | EU portal: GET `https://data.europa.eu/api/hub/search/search?q=job vacancies offres d'emploi&filter=dataset&facets={"country":["lu"]}&limit=15` -> 200, 97,460 bytes, 156 matches, 15 read: the skills dataset, STATEC tables, and one ADEM entry "Offres d'emploi" in another catalogue that is marked non-public (see "Found beyond the research") | - |
| 10 | GovJobs: "Nous avons 253 offres d'emploi"; "Depuis le 15 septembre 2026, le parcours de recrutement dans la Fonction publique a évolué" | CONFIRMED | GET https://govjobs.public.lu/fr.html -> 200, text/html, 45,038 bytes: both sentences; links to `/fr/postuler/postes-ouverts.html` and `/fr/secteur-communal/postes-ouverts.html` | - |
| 11 | GovJobs carries the same State legal text as ADEM and an identical robots.txt | CONFIRMED | GET https://govjobs.public.lu/fr/support/aspects-legaux.html -> 200, 49,236 bytes: the same two sentences ("aucune reproduction [...]", "à titre personnel, pour information et dans un cadre strictement privé"). GET https://govjobs.public.lu/robots.txt -> 200, 529 bytes, byte for byte the same as ADEM's | - |
| 12 | GovJobs is web-only: no feed or API on the home page | NOT DISPROVED | Home page: no link to a feed, an XML file or an API | - |
| 13 | jobs.lu has no robots.txt at the address its redirect names | CONFIRMED | GET https://www.jobs.lu/robots.txt -> 301 to https://en.jobs.lu/robots.txt -> 404, text/html, 103 bytes | - |
| 14 | Moovijob's robots.txt rules; its terms address answered 403 (Cloudflare challenge) | UNVERIFIED | No request made (blocked host) | - |
| 15 | Jobfinder.lu robots.txt, whole file: "User-agent: * Disallow: /backoffice/*" and "User-agent: * Allow: /" | CONFIRMED | GET https://www.jobfinder.lu/robots.txt -> 200, text/plain, 117 bytes, exactly that (with two comment lines) | - |
| 16 | monster.lu redirects to https://www.monster.com/fr/ | CONFIRMED | GET https://www.monster.lu/ -> 301, `location: https://www.monster.com/fr/` (not followed) | - |
| 17 | Indeed and LinkedIn forbid automated reading; STATEC and ADEM labour-market tables are on the portal | CONFIRMED | Indeed and LinkedIn terms read once today for the France check (200, 665,417 and 184,070 bytes; clauses as quoted). EU portal search (claim 9): STATEC "Population et emploi - Marché du travail" tables. Their licence was not checked: statistics | - |
| 18 | LBR's site https://www.lbr.lu redirects to `/mjrcs-web-front/` (619 bytes) | CONFIRMED | GET https://www.lbr.lu/ -> 200, text/html, 619 bytes: a meta refresh and script to `https://www.lbr.lu/mjrcs-web-front/` (not followed) | - |
| 19 | e-Justice: "Public searches are done by registration number or by name"; "Documents filed with the Trade and Companies Register are available free of charge"; extracts and certificates are paid; viewing filed documents needs a login "with or without creating a personal account" | CONFIRMED | GET https://e-justice.europa.eu/topics/registers-business-insolvency-land/business-registers-eu-countries/lu_en -> 200, text/html, 75,077 bytes: all four ("Extracts, certificates or certified copies issued by the Trade and Companies Register administrator are available for a fee") | - |
| 20 | Fact sheet: "Basic company information: LBR", "Company documents and accounts: "Centrale des bilans" / STATEC" | CONFIRMED | GET https://data.public.lu/en/pages/fact-sheets/hvd/ -> 200, text/html, 115,316 bytes: both; "All the HVD data are inventoried in the HVD Catalog" | - |
| 21 | The 15 datasets tagged `companies-and-company-ownership` are all STATEC's "HVD - Annex 5 Companies and Company Ownership - Annual deposits <year>" (2012-2026), `cc-by`, files of 143-272 MB dated 2026-10-25 | CONFIRMED | GET `https://data.public.lu/api/1/datasets/?tag=companies-and-company-ownership&page_size=30` -> 200, 98,254 bytes: total 15, all STATEC, `license` cc-by, one file each, 143,492,514 (2012) to 271,857,287 bytes (2017); the 2026 file dated 2026-10-25T04:26:31; the records themselves modified 2026-11-09 | - |
| 22 | A record of the 2026 file holds `RcsNumber`, `LegalUnitName` and the filed accounts; no status, address, legal form, activity code, website or head count | CONFIRMED | GET of `.../20261025-042629/hvd.annualdeposits2026.json`, bytes 0-3999 -> 206, application/json, `Content-Range: bytes 0-3999/198049355`: two records, each `RcsNumber`, `LegalUnitName`, then `Declaration` (language, model, type, StartDate, EndDate, YearRef, RCSDepositDate, ID_Doc, Currency) and balance-sheet fields; nothing else | - |
| 23 | No free bulk file of basic company data exists; the HVD catalogue was not opened and might list a service from LBR | NOT DISPROVED | The catalogue was searched: GET `https://catalog.inspire.geoportail.lu/geonetwork/hvd/eng/csw?...constraint=AnyText like '%compan%'` -> 200, application/xml, 48,684 bytes, 17 records: the 15 annual-deposits datasets, their "ATOM Download Service" and one unrelated record. Nothing from LBR | The catalogue lists no basic-information dataset or service of LBR. |
| 24 | Teamtailor, Greenhouse, Lever, SmartRecruiters, Workable, Recruitee, Personio, Workday: international vendors, documentation in the EU-wide file; none established for Luxembourg | CONFIRMED | One documentation page per vendor read today for the France check (claims 54-61 there). Use in Luxembourg: no source | - |
| 25 | Skeeled is a Luxembourg-based recruiting-software vendor (from memory; nothing read) | UNVERIFIED | GET https://www.skeeled.com/ -> 200, text/html, 48,958 bytes: "All-in-one talent acquisition software", "Branded careers pages", "2000+ pre-contracted and ready-to-use job boards & media channels"; no word Luxembourg, API, feed or XML | The vendor exists and documents no public feed on the page read; its Luxembourg base is not on that page. |
| 26 | No source gives links to employers' own pages | NOT DISPROVED | The skills dataset has no employer or link (claim 6); the JobBoard was not read at offer level | - |
| 27 | Employer directories: none verified; candidates known from memory only | UNVERIFIED | Not requested | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (the deciding clause if "no") |
|---|---|---|
| ADEM JobBoard | no | robots.txt, every agent: "Disallow: /*?*" - the JobBoard's offers are served only from addresses with a query string (`/ctie/jobboard?id=...`). The legal notice itself allows consulting and downloading "à titre personnel [...] dans un cadre strictement privé" and is silent on programs |
| "Skills required in ADEM job vacancies" (past adverts) | yes | CC0; vacancies published since 2015, six files of 61-147 MB; no employer name or number; occupation (ROME), skill (ESCO), sector (NACE), canton, month |
| ADEM "Offres d'emploi" (entry in the national single information point) | unclear | Marked "non-public" on the EU portal; conditions of access not read; daily, from 2015 |
| GovJobs | unclear | Personal, private use allowed in so many words; silent on programs; same robots.txt (addresses with a query string closed); list of posts not read |
| jobs.lu | unclear | Terms not read; no robots.txt (404) |
| Moovijob | unclear | Could not be read (blocked host) |
| Jobfinder.lu | unclear | Terms not read; robots.txt closes only `/backoffice/*` |
| Monster.lu | unclear | Site gone: 301 to monster.com/fr/; terms there not read |
| Indeed | no | Forbidden: "Utiliser un système automatisé (bots, agrégateurs (« scrapers »), « spiders », IA ou IA agentique) pour accéder, extraire des données" |
| LinkedIn | no | "Use bots or other unauthorized automated methods to access the Services" |
| STATEC and ADEM labour-market tables | no | Counts only, no adverts |
| STATEC annual-accounts files (company high-value datasets) | yes | CC BY, no key; each filer's name and RCS number with its accounts; no address, activity or website |
| LBR - register search on lbr.lu | unclear | Terms not read; one entity at a time |
| LBR - extracts and certificates | no | Paid: "Extracts, certificates or certified copies [...] are available for a fee" |

## Found beyond the research

- **ADEM lists a daily dataset of all declared vacancies - but not as open data.** On data.europa.eu, in the
  catalogue `nsip-lu` ("National Single Information Point Luxembourg"): "Offres d'emploi", publisher ADEM,
  "Informations sur les offres d'emplois déclarés à l'ADEM par les employeurs", frequency "daily", from
  2015-01-01, `access_right` "non-public" (GET
  https://data.europa.eu/api/hub/search/datasets/2deb97de-9787-11f0-ab9c-bee5960d250d -> 200, 10,075 bytes).
  The same catalogue lists "Demandeurs d'emploi - caractéristiques". How access is asked for was not read.
- **The JobBoard's structure** (claim 1): offers load from `/ctie/jobboard...` on adem.public.lu, 20 a page, with
  six filters. The second version due in early December 2026 may change this.
- **The press release names three stages**: offers with direct application now, a second version in early
  December 2026, employers' access to candidates' profiles in a third.
- **The skills dataset's record gives its coverage** as 2015-01-01 to 2025-04-07 (`temporal_coverage`) although
  the newest file is named 2025-2026, and says the last two to three months are incomplete.
- **GovJobs and ADEM share one robots.txt** (529 bytes, identical): every address with a query string is closed
  to all robots on both.
