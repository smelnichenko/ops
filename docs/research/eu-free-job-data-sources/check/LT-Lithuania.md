# Lithuania (LT) - check of the research

The research file has no section on the employer route; it is added in a later pass.

Checked on 2026-11-28. Client: curl 8.14.1 with its default User-Agent, one capped GET per URL, one at a time;
web search for leads. No account, key or login. At most three requests per job-board host. The open data API
`get.data.gov.lt` got 21 small requests (two single records, three short selections, the rest `count()`
queries of under 40 bytes each); no bulk file. `data.gov.lt` answered 429 on its third request; one more request
to it was already under way in the same command (answered 302) and the host was then left alone. `uzt.lt` and
`dirbuvalstybei.vva.lt` each answered 403 with a challenge page to one request and were left alone. No person's
details were read out of the data: contact fields were checked by name and by `count()` only. Statistics were
not requested: out of purpose. The second table has one verdict per source, as the brief was simplified.

## Corrections and unverified claims (apply these first)

- WRONG: the dataset as "the best free source", from which "live vacancies must be picked by status and validity
  dates". It is an archive. On 2026-11-28, of 3 254 974 records, 3 254 766 have `statusas` "archyvuota" and 206
  "sukurta"; 145 have `galioja_iki` on or after 2026-11-28; 115 carry the "current today" flag. Records by load
  date (`ikelimo_data`): 97 375 in 2026, of them 6 647 since 1 September, 1 470 since 1 October, 483 since
  1 November, 54 since 20 November. Status and validity dates find about 150-200 live records, not the live
  stock of a national employment service.
- ADDITION (claim 10, confirmed): the "current today" flag is not far off the validity dates as a count (115 against 145); it is still
  wrong on single records (the three newest, valid into December, carry "0"). The real fault is that current
  vacancies are mostly not in the dataset yet.
- ADDITION (claim 3, confirmed; a gap closed): the licence IS stated on data.gov.lt itself: "Licencija Creative Commons Attribution 4.0"
  (`https://creativecommons.org/licenses/by/4.0/deed.lt`), with "Atnaujinama Kasdien" and "Prieigos teisės Vieši".
- CORRECTED: on data.gov.lt the organisation assigned to the dataset is "Duomenų rengėjas: Užimtumo tarnyba prie
  Lietuvos Respublikos socialinės apsaugos ir darbo ministerijos"; "Valstybės duomenų agentūra" is the publisher
  only in the data.europa.eu copy.
- CORRECTED: data.europa.eu does list other Lithuanian job advert datasets: "Aktualūs darbo skelbimai viešajame
  sektoriuje" (data.gov.lt 1241) and "Vilniaus miesto savivaldybės darbo skelbimai" (3851), both CC BY 4.0.
  Neither is live today (see "Found beyond the research").
- CONFIRMED, with numbers (the point asked about): the dataset holds employers' contact data. Fields
  `darbdavio_kontaktinis_asmuo`, `susisiekimo_budas`, `darbdavio_tel_nr`, `darbdavio_mob_nr`,
  `darbdavio_el_pastas`; filled in 2 711 784 (contact person), 1 613 227 (telephone) and 1 875 104 (e-mail)
  records.
- UNVERIFIED: Užimtumo tarnyba's website, its terms and robots.txt - 403 with a Cloudflare "Just a moment..."
  page; not tried further.
- UNVERIFIED: Dirbu valstybei (publisher, content, feed, terms) - 403 with the same challenge page.
- UNVERIFIED: whether Užimtumo tarnyba sends its vacancies to EURES - its site is closed to this client and a web
  search found no statement of its own.
- UNVERIFIED: the publishers of cvonline.lt and cv.lt and their terms - only robots.txt was requested.
- UNVERIFIED: the content of the older file (dataset 241) - not requested.
- UNVERIFIED: the official statistics block (osp.stat.gov.lt, 403) - not requested: statistics.

## Claims

| # | Claim | Verdict | Evidence (URL, status, what was seen) | Corrected statement |
|---|---|---|---|---|
| 1 | The dataset "Užimtumo Tarnybos skelbiamos laisvos darbo vietos" is dataset 2894 on data.gov.lt, served at `https://get.data.gov.lt/datasets/gov/uzt/ldv/Vieta` | CONFIRMED | GET `https://data.gov.lt/datasets/2894/` -> 302 to `?resource_version=211` -> 200, text/html, 59 140 bytes; resources "uzt - Saugyklos API", "ldv - JSON", "ldv - JSONL", "ldv - RDF", "Vieta - CSV" (published 2026-04-03, updated 2026-10-26) | - |
| 2 | It answers without a key | CONFIRMED | GET `https://get.data.gov.lt/datasets/gov/uzt/ldv/Vieta?limit(1)` -> 200, application/json, 1 825 bytes, no credentials sent; so did every query below | - |
| 3 | Licence CC BY 4.0 (taken from the data.europa.eu copy) | CONFIRMED | data.gov.lt page: "Licencija Creative Commons Attribution 4.0", link `https://creativecommons.org/licenses/by/4.0/deed.lt`; "Prieigos teisės Vieši" | Stated on data.gov.lt itself |
| 4 | Listed publisher Valstybės duomenų agentūra; source Užimtumo tarnyba | CORRECTED | data.gov.lt: "Priskirtos organizacijos ... Duomenų rengėjas Užimtumo tarnyba prie Lietuvos Respublikos socialinės apsaugos ir darbo ministerijos"; questions go to atverimas@stat.gov.lt. data.europa.eu shows publisher "Valstybės duomenų agentūra" | The portal names the Employment Service as the data's preparer |
| 5 | One record per vacancy with the fields listed (status, load date, salary, occupation, description, validity, flags, address, employer, requirements, target groups) | CONFIRMED | The record has 57 fields, among them every one named in the research | - |
| 6 | The records carry employers' contact persons, telephone numbers and e-mail addresses | CONFIRMED | Field names `darbdavio_kontaktinis_asmuo`, `susisiekimo_budas`, `darbdavio_tel_nr`, `darbdavio_mob_nr`, `darbdavio_el_pastas` (empty in the one record read, of 1996). `?darbdavio_kontaktinis_asmuo!=null&count()` -> 2 711 784; `?darbdavio_tel_nr!=null&count()` -> 1 613 227; `?darbdavio_el_pastas!=null&count()` -> 1 875 104. The portal's description: "2026-02-10: Į rinkinį įtraukti nauji laukai apie darbo užmokestį, darbo skelbimo statusą ir darbdavio kontaktiniai duomenys." | - |
| 7 | ISCO-08 fields added on 2026-04-24; salary, status and contact fields on 2026-02-10 | CONFIRMED | Description on data.gov.lt, both dated notes | - |
| 8 | 3 254 957 records; "nuo 1990m. iki šių dienų"; oldest seen from 1995-1996 | CONFIRMED | `?count()` -> `{"_data":[{"count()":3254974}]}`; description "nuo 1990m. iki šių dienų"; the first record: `ikelimo_data 1996-04-10`, `valiuta LTL`, `statusas archyvuota` | 3 254 974 at the time of this check |
| 9 | Declared daily; the three newest records carry ikelimo_data 2026-11-25 | CONFIRMED | "Atnaujinama Kasdien"; `?select(...)&sort(-ikelimo_data)&limit(3)` -> three records with `ikelimo_data 2026-11-25`, `statusas sukurta`, valid to 2026-12-07 and 2026-12-03, average salary 1154.0 and 576.5 EUR | - |
| 10 | The "current today" flag counted 114 and was "0" on fresh posts valid into December | CONFIRMED | `?ar_aktuali_siandien="1"&count()` -> 115; the three newest records all have `ar_aktuali_siandien "0"` | - |
| 11 | The flag cannot be trusted, so live vacancies must be picked by status and validity dates | WRONG | `?galioja_iki>="2026-11-28"&count()` -> 145; `?statusas="sukurta"&count()` -> 206; `?statusas="archyvuota"&count()` -> 3 254 766 | Status and validity dates find no more live records than the flag does: about 150-200 |
| 12 | Every vacancy the Employment Service has registered; the best free source | WRONG | `?ikelimo_data>="2026-01-01"&count()` -> 97 375; `>="2026-09-01"` -> 6 647; `>="2026-10-01"` -> 1 470; `>="2026-11-01"` -> 483; `>="2026-11-20"` -> 54. January-August average about 11 300 a month; September 5 177; October 987; November 483 | A historical archive: recent months are thin and almost nothing in it is live |
| 13 | The record's metadata date (2026-05-06) is older than the data | CONFIRMED | "Paskutinio metaduomenų atnaujinimo data 2026-05-06"; resources "Atnaujinta 2026-10-26" | - |
| 14 | Bulk forms `.../Vieta/:format/csv`, `.../:all/:format/jsonl`, `/json`, `/rdf` | CONFIRMED | Listed as download addresses in the data.europa.eu record and as resources on data.gov.lt; not requested (size) | - |
| 15 | https://uzt.lt/robots.txt -> 403, 5 317 bytes, Cloudflare "Just a moment..." | CONFIRMED | GET -> 403, text/html, 5 317 bytes, title "Just a moment..." | - |
| 16 | The service announced 172.4 thousand vacancies in 2024 (third-hand) | UNVERIFIED | Not re-read | - |
| 17 | Older file, dataset 241 "Darbdavio Lietuvos Respublikoje (numatoma darbo vieta) duomenys": CSV, CC BY 4.0, monthly, issued 2020-05-18 | CONFIRMED | data.europa.eu record `https-data-gov-lt-datasets-241-`: publisher Užimtumo tarnyba, that licence, "monthly", issued 2020-05-18, address `.../45.csv`. Content not examined | - |
| 18 | https://dirbuvalstybei.vva.lt/ -> 403, 5 358 bytes, Cloudflare challenge | CONFIRMED | GET -> 403, text/html, 5 358 bytes, title "Just a moment..." | - |
| 19 | Dirbu valstybei is VVA's public-sector job portal, successor of portalas.vtd.lt | UNVERIFIED | Blocked. The open dataset 1241 still points to `https://portalas.vtd.lt` and stopped on 2024-02-05 | - |
| 20 | CVbankas: publisher UAB "Diginet LTU"; terms "Naudojimosi cvbankas.lt portalu taisyklės (REDAKCIJA 2026-09-03)" | CONFIRMED | GET `https://www.cvbankas.lt/naudojimosi-taisykles.html` -> 200, text/html, 430 926 bytes: that title; "Mes esame UAB Diginet LTU, juridinio asmens kodas 126222639" | - |
| 21 | CVbankas terms forbid text and data mining, AI training and automated means (bots, scraping, indexing programs) | CONFIRMED | "Jūs įsipareigojate: ... neatgaminti, nekopijuoti ir nenaudoti Svetainių turinio tekstų ir duomenų gavybos, dirbtinio intelekto sistemų kūrimo, apmokymo, tobulinimo, testavimo, analizės bei panašiais tikslais; nenaudoti automatizuotų priemonių, įskaitant interneto robotais (angl. bots), duomenų nuskaitymo (angl. scraping), indeksavimo ar bet kokio kito tipo kompiuterinėmis programomis, skirtomis kopijuoti, apdoroti, analizuoti, saugoti ar perkelti Svetainių turinį"; community rules: "Naudojantis Svetainėmis, draudžiama: ... naudoti automatizuotas priemones („botus“, „scraping“ ir kt.); naudoti Svetainių turinį dirbtinio intelekto sistemoms apmokyti" | - |
| 22 | All intellectual property rights in the sites, their content and databases belong to the operator | CONFIRMED | "Visos intelektinės nuosavybės teisės į Svetaines, jų turinį, duomenų bazes, pavadinimus, prekės ženklus ... priklauso mums arba yra naudojamos teisėtai pagal trečiųjų asmenų suteiktas licencijas." | - |
| 23 | CVbankas robots.txt: only account and apply paths disallowed for all agents; "#Block AI bots" with "Disallow: /" for named agents | CONFIRMED | GET `https://www.cvbankas.lt/robots.txt` -> 200, text/plain, 2 744 bytes; ten path rules under "User-agent: *"; "#Block AI bots" and 19 agents with "Disallow: /" | - |
| 24 | The site calls itself the most visited job portal in Lithuania | CONFIRMED | Page header: "Nr.1 LANKOMIAUSIAS DARBO PORTALAS" | - |
| 25 | cvmarket.lt falls under the CV Keskus terms, whose clause 2.10 forbids automated queries, 10 000 EUR per breach | CONFIRMED | Read today on `https://www.cvkeskus.ee/kasutustingimused` (see the Estonia check): clause 1.1 names www.cvmarket.lt; 2.10 as quoted there | - |
| 26 | robots.txt of cvonline.lt (45 bytes, sitemap only), cv.lt (95 bytes) and cvmarket.lt (723 bytes) | CONFIRMED | Each GET -> 200: cvonline.lt "Sitemap: https://www.cvonline.lt/sitemap.xml"; cv.lt "User-agent: * / Disallow: /cv/*/pdf / Disallow: /login* / Sitemap: https://www.cv.lt/sitemap_cvl.xml"; cvmarket.lt account, login and CV paths, listing sitemaps and `rss-listings.xml` | - |
| 27 | cvonline.lt is Alma Career's; cv.lt's operator not confirmed | UNVERIFIED | No page of either read beyond robots.txt | - |
| 28 | Official statistics on osp.stat.gov.lt; API page refused with 403 | UNVERIFIED | Not requested: statistics | - |
| 29 | No statistical vacancy table on the open data portal, only the Employment Service dataset | CORRECTED | data.europa.eu, country lt, "laisvos darbo vietos darbo skelbimai konkursai": the first results are datasets 2894, 1241 ("Aktualūs darbo skelbimai viešajame sektoriuje"), 3851 ("Vilniaus miesto savivaldybės darbo skelbimai") and 241 | Two more advert datasets exist |
| 30 | No paid vacancy data product was found on any page read | NOT DISPROVED | None on the pages read today | - |
| 31 | Whether Užimtumo tarnyba sends its vacancies to EURES: not established | UNVERIFIED | uzt.lt blocked; search results held only general EURES pages | - |

## For a personal job search and applications

| Source | Usable for own job search | Why (deciding clause if "no") |
|---|---|---|
| Užimtumo tarnyba open dataset (get.data.gov.lt) | no | Not for its terms (CC BY 4.0, no key) but for its content: an archive - 206 records with status "sukurta" and 145 valid today or later among 3.25 million; 483 loaded in November. It also carries contact persons' details |
| Užimtumo tarnyba website (uzt.lt) | unclear | Could not be read: 403 with a Cloudflare challenge page to a plain client |
| Dirbu valstybei (dirbuvalstybei.vva.lt) | unclear | Could not be read: 403 with a Cloudflare challenge page |
| Open dataset "Aktualūs darbo skelbimai viešajame sektoriuje" (1241) | no | Stale: 211 records, the newest `atnaujinimas` is 2024-02-05 (licence CC BY 4.0, no key) |
| Open dataset "Vilniaus miesto savivaldybės darbo skelbimai" (3851) | no | 9 581 records since 2021, none with `galiojimo_pabaiga` on or after 2026-11-28 (licence CC BY 4.0, no key, declared weekly) |
| CVbankas.lt | no | Terms of 2026-09-03: "nenaudoti automatizuotų priemonių, įskaitant interneto robotais (angl. bots), duomenų nuskaitymo (angl. scraping), indeksavimo ar bet kokio kito tipo kompiuterinėmis programomis, skirtomis kopijuoti, apdoroti, analizuoti, saugoti ar perkelti Svetainių turinį" |
| CVMarket.lt | no | CV Keskus terms 2.10: "Kasutajal on keelatud kasutada Veebikeskkonda tarkvara või vahendite abil, mis võimaldavad teha ilma inimese sekkumiseta automaatseid päringuid." (10 000 EUR per breach) |
| cvonline.lt | unclear | Terms not read; robots.txt has no rules |
| cv.lt | unclear | Terms not read; robots.txt disallows only `/cv/*/pdf` and `/login*` |
| Older Employment Service file (dataset 241) | unclear | Content not examined; by its title it is about employers of intended workplaces, not adverts |
| Official statistics | no | Counts only, no adverts |

## Found beyond the research

- The dataset's make-up, by `count()` queries: 3 254 766 archived, 206 "sukurta", 145 valid today or later; load
  dates thin out from September 2026 (5 177 in September, 987 in October, 483 in November) against about 11 300 a
  month earlier in the year. Vacancies seem to reach the open data mostly after they have closed.
- "Aktualūs darbo skelbimai viešajame sektoriuje" (data.gov.lt 1241, CC BY 4.0, declared daily) at
  `https://get.data.gov.lt/datasets/gov/ird/vataras_vatis/DarboSkelbimas` answers without a key: 211 records, 20
  fields (validity dates, type of position, title, gross pay, town, institution, registry code, an information
  e-mail field, advert number, `https://portalas.vtd.lt`); newest update 2024-02-05. Its description promises only
  valid adverts, updated daily; it stopped with the old civil-service portal.
- "Vilniaus miesto savivaldybės darbo skelbimai" (data.gov.lt 3851, CC BY 4.0, declared weekly) at
  `https://get.data.gov.lt/datasets/gov/vilniaus_m_sav/laisvos_darbo_vietos/Skelbimas` answers without a key:
  9 581 records with title, description, requirements, pay, institution, address, a contact field and an advert
  address field; none valid on or after 2026-11-28.
- CVbankas's candidate terms say applying runs through the site: "Darbo skelbimų naršymas ir paieška, CV kūrimas
  ir talpinimas bei kandidatavimas per Svetainės sistemą - Jums yra neatlygintinas."
- CVMarket.lt's robots.txt lists `https://www.cvmarket.lt/rss-listings.xml` (not requested; clause 2.10 forbids
  automated queries regardless).
- Still unchecked, as in the research: darbo.lt, skelbiu.lt jobs, LinkedIn.
