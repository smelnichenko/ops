# Free online address data sources in the EU, country by country

State as of 11 November 2026. Question: for each of the 27 EU member states, which address data
(house-number level, ideally with coordinates and postcodes) can be downloaded or queried online
at no cost, and on what terms?

## Key findings

- **17 countries publish a free national address dataset with house numbers and coordinates:**
  Austria, Belgium, Croatia, Czechia, Denmark, Estonia, Finland, France, Italy, Latvia, Lithuania,
  Luxembourg, the Netherlands, Poland, Slovakia, Slovenia, Spain. Slovenia is counted on the
  publisher's statement: its download host refused the check.
- **7 countries have free official data with a serious limit:**
  - Germany: free per state for most states, no nationwide file, Bavaria sells its data.
  - Sweden: free, but behind a login and an approved application per product.
  - Portugal: the national address base is free but its files date from 2018.
  - Greece: a 2023 cadastre snapshot of street points, with no municipality or postcode.
  - Bulgaria: cadastre building polygons with address fields, numbering incomplete, no licence printed.
  - Hungary and Malta: official addresses only through Eurostat's lookup API, no national download found.
- **3 countries have no free source of residential addresses with coordinates:** Ireland (the
  national products are paid), Cyprus (the open service covers about 4% of the country and has no
  house numbers) and Romania (the register was never open in bulk and its geoportal has been
  offline since July 2026).
- **Postcodes are not always in the free data.** Italy's national file has none, several German
  states leave them out of the bulk file, and Greece and Malta have none in their best source.
- **Italy's coordinates are incomplete:** 67% of civic numbers have them (official figure, March 2026).
- **Older descriptions are often wrong, because services moved in 2025-2026:**
  - Denmark's DAWA closed on 1 October 2026.
  - Finland's open building-address file stopped in March 2025.
  - France's address API moved to `data.geopf.fr`.
  - Estonia's In-ADS search is being replaced by In-AKS.
  - Belgium's federal files switched coordinate system on 18 October 2026, and Latvia's on 7 October 2026.
- **EU law already requires this data to be free.** Regulation (EU) 2023/138 has applied since
  9 June 2024, but no official per-country compliance table was found.
- **Cross-border sources fill some gaps, with limits:**
  - Eurostat's GISCO Address API covers every country except Ireland; it is lookup only.
  - OpenAddresses covers 24 countries and needs a free account.
  - Overture covers 19 countries and needs none.

## How to read the overview table

- **Yes**: a national dataset with house numbers and coordinates can be downloaded or queried free.
- **Partly**: free official house-number data exists for all or most of the country, with the
  limit named in the next cell (stale, per region, lookup only, approval needed, incomplete).
- **No**: nothing free with house numbers and coordinates for more than a small part of the
  country; the best substitute is named.

## How this was made, and how far to trust it

- **Two passes.** Seven research passes (six groups of countries plus the EU-wide layer) collected
  the sources. Then an independent second reader re-requested every link and re-read licence, cost,
  registration and update cycle on the publisher's own page, claim by claim.
- **Result of the second pass:** 1,205 claims checked. 966 confirmed, 78 corrected, 10 wrong,
  126 could not be verified, 17 negative claims not disproved, 8 other (first-pass estimates and
  one cross-reference). This report uses the checked values.
- **What "could not be verified" means.** The site refused a plain client, needed a login, timed
  out, had an invalid certificate, or the file was too large to recount. Nothing was bypassed.
  Those items are listed at the end of each country section and are not stated as fact anywhere.
- **What "none found" means.** A search of the national open data portal and the EU catalogue
  found nothing. It is not proof that nothing exists.
- **Record counts** are the publisher's figure or a first-pass count ("researcher's count") unless
  a section says they were recounted. National files were not downloaded in full for the check.
- **Links and services change.** Every link here answered, or failed as described, on
  11 November 2026.

The claim-by-claim evidence is in the ops repository under
`docs/research/eu-free-address-data-sources/`: `by-country/<code>-<country>.md` holds each
country's research notes and its check table.

## Overview by country

Free national address data: 17 yes, 7 partly, 3 no (as each country section defines it).

| Country | Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|---|
| [Austria](#austria-at) | Yes | BEV Adressregister, "Adresse Relationale Tabellen - Stichtagsdaten" | Bulk zip of CSV tables, no registration | CC BY 4.0 with a dated credit | Yes; MGI Gauss-Krüger, EPSG:31254, 31255 or 31256 per row | Yes | Twice a year (1 April, 1 October) |
| [Belgium](#belgium-be) | Yes | BeSt Address (FPS BOSA) | Three regional CSV zips, no registration | CC BY 4.0 | Yes; WGS84 and Lambert 2008 (EPSG:3812) | Yes | Weekly |
| [Bulgaria](#bulgaria-bg) | Partly | AGKK cadastre open data (KAIS): building polygons with address fields, numbering incomplete | Shapefile zips per settlement, no registration, no national file | None printed; open reuse known only second-hand | Yes, polygons in BGS2005; EPSG code not stated | No | Each province about every 28 days |
| [Croatia](#croatia-hr) | Yes | DGU "Adrese - INSPIRE", from the Register of Spatial Units | Bulk GML zip from an ATOM feed, no registration | Otvorena dozvola (Croatian Open Licence); commercial use allowed | Yes, EPSG:3035 | Yes | Weekly |
| [Cyprus](#cyprus-cy) | No | Substitute: Cyprus Post street-to-postcode directory; no house numbers, no coordinates | Bulk CSV, no registration | CC BY 4.0 | No; the official street points cover 4% (EPSG:4258) | Yes, per street | Stated annual; newest CSV is September 2021 |
| [Czechia](#czechia-cz) | Yes | RÚIAN address-point CSV (ČÚZK) | Bulk CSV zip, no registration | CC BY 4.0 | Yes, S-JTSK (EPSG:5513) | Yes | Monthly; change files daily |
| [Denmark](#denmark-dk) | Yes | Danmarks Adresseregister (DAR) on Datafordeleren | Bulk JSON/CSV with free account and API key; INSPIRE API keyless | CC BY 4.0 | Yes, EPSG:25832 (not confirmed for the bulk files) | Yes | Full files weekly, deltas daily |
| [Estonia](#estonia-ee) | Yes | Aadressiandmete süsteem (ADS) extracts, Maa- ja Ruumiamet | Bulk CSV, no registration; keyless search API | Open data, no licence agreement; credit the Board | Yes, L-EST97 (EPSG:3301) | Yes | Monthly |
| [Finland](#finland-fi) | Yes | Ryhti building addresses (Syke) | Keyless OGC API Features, paged; no bulk file found | CC BY 4.0 | Yes, building points; EPSG:3067, served as WGS84 | Yes | Not documented; same-day changes observed |
| [France](#france-fr) | Yes | Base Adresse Nationale (BAN) | Bulk CSV, no registration | Licence Ouverte 2.0 | Yes; WGS84 lon/lat plus local projected x/y | Yes | Daily |
| [Germany](#germany-de) | Partly | Per-Land cadastre address files; regional only, Bavaria missing | One bulk file or service per Land, no key | dl-de/zero-2-0, dl-de/by-2-0 or CC BY 4.0, by Land | Yes; ETRS89/UTM zone 32 or 33 (EPSG:25832, EPSG:25833) | Partly; in the free data of 8 Länder | Varies by Land: monthly to yearly, some not stated |
| [Greece](#greece-gr) | Partly | Hellenic Cadastre declared street points: 2023 snapshot, no municipality, no postcode | Bulk shapefile zip, no registration | CC BY 4.0; the Cadastre's own terms unread | Yes, Greek Grid GGRS87 (EPSG:2100) | No | None; "as needed", file dated 2023-11 |
| [Hungary](#hungary-hu) | Partly | GISCO Address API (Eurostat; data credited to Lechner Tudásközpont) | Keyless lookup API; GeoPackage on GISCO, contents unchecked | None stated; reuse terms unchecked | Yes; degrees, CRS not stated | Yes | Not known; GeoPackage dated 7 Mar 2026 |
| [Ireland](#ireland-ie) | No | None national; Tailte Valuation API covers rateable property only | API with CSV, JSON or GeoJSON output | CC BY 4.0 (Valuation API) | Valuation API only; ITM X/Y | Eircode, on rateable property only | Continuous (Valuation API) |
| [Italy](#italy-it) | Yes | ANNCSU (ISTAT and Agenzia delle Entrate) | bulk CSV in ZIP, no registration | CC BY 4.0 | yes, lon/lat ETRF2000, on 67.0% of rows (31/03/2026) | no | monthly |
| [Latvia](#latvia-lv) | Yes | Valsts adrešu reģistrs open data on data.gov.lv (VZD) | Bulk CSV and shapefile, no registration | CC BY 4.0 | Yes, LKS-2020 TM plus decimal degrees | Yes | Daily |
| [Lithuania](#lithuania-lt) | Yes | Adresų registras files on registrucentras.lt (Registrų centras) | Bulk CSV and GeoJSON, no registration | CC BY 4.0 | Yes, in a separate file; EPSG:3346 not rechecked there | Yes | Monthly |
| [Luxembourg](#luxembourg-lu) | Yes | BD-Adresses (ACT) | Bulk CSV, GeoJSON or SHP, no registration | CC0 | Yes; WGS84 and LUREF | Yes | Weekly |
| [Malta](#malta-mt) | Partly | GISCO Address API (Eurostat); lookup only, no download | keyless REST lookup, 1,000-row cap | none stated | yes, lon/lat, not door-precise | no | not stated |
| [Netherlands](#netherlands-nl) | Yes | BAG (Kadaster), distributed by PDOK | Bulk GeoPackage or XML zip, no registration | Public domain (CC0 / Public Domain Mark 1.0) | Yes; EPSG:28992 (Amersfoort / RD New) | Yes | Monthly files; daily services |
| [Poland](#poland-pl) | Yes | PRG address points (GUGiK) | Bulk SHP or GML zip, no registration | No named licence; "free of charge and for any use" | Yes, EPSG:2180 | Yes | Continuous at source; file schedule not stated |
| [Portugal](#portugal-pt) | Partly | Base Nacional de Moradas (INE); stale, files from 2018 | GML per municipality from an ATOM feed, no registration | CC BY 4.0 | yes, EPSG:4258, 4326 and 3763 (islands 5014-5016) | yes | none seen since 2018 |
| [Romania](#romania-ro) | No | Substitute: Poșta Română postcode file of 2016; no house-number points | Bulk XLS, no registration | OGL-ROU-1.0 | No | Yes, to street level per the publisher | None; newest file is from 2016 |
| [Slovakia](#slovakia-sk) | Yes | Register adries (Ministry of Interior) | Bulk CSV or WFS, no registration | CC0 | Yes; WFS EPSG:4258, CSV in degrees | Yes | CSV declared quarterly; served file is April 2026 |
| [Slovenia](#slovenia-si) | Yes (per publisher; download not confirmed) | Register naslovov (GURS) | JGP portal, WFS, OGC API; no registration per GURS | CC BY 4.0 | Yes, EPSG:3794 | Yes, as postal-district code | Event-driven; no schedule published |
| [Spain](#spain-es) | Yes | CartoCiudad (IGN / CNIG) | OGC API Features, paged, no key | CC BY 4.0 | yes, ETRS89 lon/lat (REGCAN95 in the Canaries) | yes | every four months |
| [Sweden](#sweden-se) | Partly | Belägenhetsadress (Lantmäteriet); login-gated, application must be approved | GeoPackage per municipality, Geotorget account plus approved application | CC BY 4.0 plus personal-data conditions | Yes, EPSG:3006 | Not verified for the bulk product | Daily |

## EU-wide sources and the legal framework

State as of 2026-11-11. All sources below were requested on that day unless a different date is given.

**In short.** Since 9 June 2024, Regulation (EU) 2023/138 requires every member state to publish address data for its whole territory free of charge, under CC BY 4.0 or a less restrictive licence, through both an API and a bulk download; no official table of which countries comply was found. Two cross-border sources deliver downloadable address points: OpenAddresses (sources for 24 of the 27 countries, free account needed) and Overture Maps (19 of 27, no account). Eurostat's GISCO Address API answers lookups for 26 countries (all but Ireland) but offers no bulk download and states no licence. OpenStreetMap can be downloaded for all 27, but it is under ODbL and its house-number coverage is very uneven. Main limits: Hungary, Ireland and Malta are in neither download source, licences differ per country, and several OpenAddresses copies are partial or old (Germany without Bavaria, Sweden 18 municipalities, Cyprus without house numbers, Slovenia last built in 2024).

### What EU law requires (Regulation (EU) 2023/138)

The High-Value Datasets (HVD) Implementing Regulation lists "Addresses" as one dataset of its Geospatial category. Text: [EUR-Lex, Regulation (EU) 2023/138](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138).

| Point | Requirement | Where in the Regulation |
|---|---|---|
| Dataset | Addresses, within the scope of the INSPIRE theme of the same name (Directive 2007/2/EC). The same category holds administrative units, geographical names, buildings, cadastral parcels, reference parcels and agricultural parcels. | Annex, 1.1 |
| Coverage | "Single or multiple datasets that shall cover the entire Member State when combined" | Annex, 1.1 |
| Key attributes (paraphrased; the Official Journal text has broken punctuation) | Unique identifier; geometry; address locator (e.g. house number); thoroughfare (street) name; administrative units (e.g. municipality, province, country); postal descriptor (e.g. post code); date of last update | Annex, 1.1 |
| Granularity | "N/A" | Annex, 1.1 |
| Licence | "under the conditions of the Creative Commons BY 4.0 licence or any equivalent or less restrictive open licence" | Annex, 1.2(a) |
| Format | "in a publicly documented, Union or internationally recognised open, machine-readable format" | Annex, 1.2(a) |
| Access | "through application programming interfaces ('APIs') and bulk download" - both | Annex, 1.2(a) |
| Currency | "in their most up-to-date version" | Annex, 1.2(a) |
| Metadata | At least the metadata elements of Commission Regulation (EC) No 1205/2008 | Annex, 1.2(b) |
| API documentation | API terms of use come with documentation "in a Union or internationally recognised open, human-readable and machine-readable format" | Article 3(3) |

**Price and reuse.** The Commission summarises the rules as: "free of charge, in machine-readable format, via Application Programming Interfaces (APIs) and, where relevant, as a bulk download", and "HVDs will be re-usable for any purpose" ([European Commission, HVD questions and answers, last updated 20 December 2023](https://digital-strategy.ec.europa.eu/en/faqs/high-value-datasets-questions-and-answers)).

**Dates.**

- Published in the Official Journal on 20.1.2023 (L 19/43).
- Entered into force on 09/02/2023 and applies from 09/06/2024. Article 6 gives the rule (twentieth day after publication; application 16 months later). The calendar dates are on the EUR-Lex document-information page for the Regulation (path `/legal-content/EN/ALL/?uri=CELEX:32023R0138`).
- The Commission's wording: "Public authorities must ensure that all the datasets from the list of HVDs are available from 9 June 2024 under reuse-friendly conditions" ([HVD questions and answers](https://digital-strategy.ec.europa.eu/en/faqs/high-value-datasets-questions-and-answers)).

**Exemptions.**

- The free-of-charge requirement does not apply to libraries (including university libraries), museums and archives (recital 6).
- Member States "may exempt individual public sector bodies, upon their request" from free availability for "a period not exceeding two years" (recital 6). The basis is Article 14(5) of Directive (EU) 2019/1024 (CELEX:32019L1024): "for a period of no more than two years following the entry into force of the relevant implementing act".
- Any such exemption "shall be published online" (Article 4(1)).
- Estimate: every such exemption ended by about 9 February 2025. This rests only on adding two years to the entry-into-force date of 09/02/2023. No source states the date.
- "data held by public undertakings are not included in the scope of this Implementing Regulation" (recital 7).
- Personal data: "In principle, the list of high-value datasets does not refer to personal data." Data that national law excludes from access on data-protection grounds falls outside the Open Data Directive ([HVD questions and answers](https://digital-strategy.ec.europa.eu/en/faqs/high-value-datasets-questions-and-answers)).

**Reporting.** Article 5 obliges each Member State to report to the Commission "by 2 years after entry into force", and again on the Commission's request, "which should be made every 2 years". A report lists the datasets with a metadata reference, persistent links to the licences and to the APIs, guidance documents, data protection impact assessments, and the number of bodies exempted under Article 14(5). Estimate: the first reports were due about 9 February 2025 and the next round falls about February 2027. This is the same two-year arithmetic and is stated nowhere. No published Article 5 report was found.

**What INSPIRE requires and does not require.** The Regulation defines the address dataset by reference to INSPIRE, but INSPIRE alone does not make address data open ([EUR-Lex, Directive 2007/2/EC](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32007L0002)).

- Theme definition (Annex I, point 5): "Location of properties based on address identifiers, usually by road name, house number, postal code".
- Member States must run discovery, view and download services (Article 11). Public access can be limited on grounds such as international relations, public security or national defence (Article 13).
- Only discovery and view services must be free to the public (Article 14(1)). Article 14(2) allows charges for view services in some cases. Download services may be charged for (Article 14(4)). Metadata must state the "conditions applying to access to, and use of, spatial data sets and services and, where applicable, corresponding fees" (Article 5(2)(b)).
- No open licence is required by INSPIRE. The free-of-charge and CC BY 4.0 obligations come from the HVD Regulation.

The INSPIRE address data model ([INSPIRE Data Specification on Addresses - Technical Guidelines](https://inspire-mif.github.io/technical-guidelines/data/ad/dataspecification_ad.html), document D2.8.I.5_v3.2.0, published 2024-07-31; its body text still says version 3.1rc1):

- Mandatory on every address: `inspireId` (1), `position` (1..*), `locator` (1..*), `component` (1..*). Voidable: `alternativeIdentifier`, `status`, `validFrom`, `validTo`, the lifespan dates, and the links to `parcel`, `building` and `parentAddress`.
- Street name, postcode and municipality are not attributes of the address. They are separate objects (AdminUnitName, AddressAreaName, ThoroughfareName, PostalDescriptor) that the address points to through `component`.
- One constraint names a required component: "An address shall have an admin unit address component spatial object whose level is 1 (Country)". For a postal descriptor the constraints say: "If no post code exists, a post name is required." and "If no post name exists, a post code is required."
- GML is the default encoding. The schema uses only point (0-dimensional) geometries.
- Reading INSPIRE GML: the GDAL GML driver has a "gml:xlink resolving" section and names a second driver: "Another driver, GMLAS, for GML driven by application schemas, is also available. Both GML and GMLAS drivers have their use cases." ([GDAL GML driver](https://gdal.org/en/stable/drivers/vector/gml.html)). A worked command for INSPIRE GML (cadastral parcels) is in [QGIS feature request 20066](https://issues.qgis.org/issues/20066): `ogr2ogr -f GPKG A.ES.SDGC.CP.33013.cadastralzoning.gpkg GMLAS:A.ES.SDGC.CP.33013.cadastralzoning.gml -oo XSD:https://inspire.ec.europa.eu/schemas/cp/3.0/CadastralParcels.xsd`.

National INSPIRE address downloads that were confirmed at their source (details belong to the country sections):

- Croatia: one ATOM file, `https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_(AD).zip` (89,997,286 bytes). The terms OpenAddresses records for it, "no limitations to public access", are an INSPIRE access-limitation code, not a reuse licence.
- Portugal: [INE INSPIRE ATOM download service for Addresses](https://inspire.ine.pt/AD/atom/downloadservice_en.html), 8 datasets, rights field "No restrictions", feed entries dated 2019-11-11.
- Czechia: ČÚZK [ATOM service](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_ATOM-MD_AD?dlang=eng) (GML 3.2.1, files created daily, "publicly available and free-of-charge") and [WFS](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_WFS-MD_AD?dlang=eng).
- Luxembourg: ["INSPIRE - Annex I Theme Addresses - Addresses"](https://data.public.lu/en/datasets/inspire-annex-i-theme-addresses-addresses/), GML and zip, licence CC0, updated 9 November 2026.
- Austria ("Address register INSPIRE"), Slovakia ("INSPIRE - Addresses") and Spain (DG Cadastre, Navarre, Gipuzkoa, Bizkaia) list such datasets on data.europa.eu.

**What is known about compliance per country.** No official per-country table for the Addresses dataset was found: no Commission report, dashboard or study that says, per Member State, whether address data is published with the required licence, API and bulk download. The evidence that exists is indirect.

*Self-reported scores, all HVD categories together* ([Open Data Maturity Report 2025](https://data.europa.eu/sites/default/files/2025-12/2025_odm_report_7.pdf), PDF pages 11, 36 and 37). The report has no per-country table for address data.

- All 27 Member States report that they are "working towards applying" the Regulation. 25 (93 %) report that public bodies mark HVDs in metadata; the latest to do so are Denmark, Spain, Malta and Romania (Table 8).
- Denmark, Estonia, France, Latvia, Lithuania and Finland report 95 % or more. Bulgaria, Croatia and Hungary score below 50 %.
- By category: statistics 82 %, geospatial 79 %, earth observation and environment 77 %, mobility 75 %, companies 72 %, meteorological 70 %. The lowest-scoring requirements are metadata 74 %, standardised access 74 %, APIs 73 % and bulk download 73 %.
- The report contradicts itself on one figure: page 11 says 17 Member States (63 %) implemented the DCAT-AP HVD tag; Table 41 (PDF page 91) says 21 (78 %).

*Datasets tagged as HVD "Addresses" on data.europa.eu* ([search API, category `c_c3de25e4`](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D); the category URI is `http://data.europa.eu/bna/c_c3de25e4`, resolved through [the portal's SPARQL endpoint](https://data.europa.eu/sparql)).

- 79 records from 8 Member States: Austria 45, Spain 18, Slovakia 9, Belgium 3, Czechia 1, Croatia 1, Lithuania 1, Luxembourg 1.
- The tag is not a compliance list. Austria's 45 records are half-yearly snapshots of the same register (latest reference date 01.10.2026). 6 of Slovakia's 9 records are titled "Road sections". The Netherlands, Denmark, Estonia, Finland, France, Latvia, Poland and Slovenia have no tagged record, although OpenAddresses carries a national address source for each of them (see the coverage table below).
- The parent category "Geospatial" (`c_ac64a52d`) has 3,621 records ([search API](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_ac64a52d%22%5D%7D)): Spain 992, Germany 985, Latvia 544, Austria 303, Greece 234, Ireland 127, Italy 85, Lithuania 68, Belgium 65, Sweden 61, Finland 48, Estonia 23, Luxembourg 22, France 12, Portugal 12, Denmark 7, Malta 4, Netherlands 3, Croatia 1. None for Bulgaria, Cyprus, Czechia, Hungary, Poland, Romania, Slovenia and Slovakia.

*INSPIRE address metadata on data.europa.eu* ([search for "INSPIRE addresses" with keyword "addresses"](https://data.europa.eu/api/hub/search/search?q=INSPIRE%20addresses&filter=dataset&limit=0&facets=%7B%22keywords%22%3A%5B%22addresses%22%5D%7D)): 216 records. Germany 56, Spain 48, Czechia 23, Finland 12, Poland 7, Estonia 6, Lithuania 4, Sweden 4, Luxembourg 3, Netherlands 2, France 1, Italy 1, Latvia 1, Slovenia 1; the rest are non-EU. Formats: WMS 45, WFS 21, GML 14, ATOM 8, GeoPackage 6. This is a rough indicator only. The central INSPIRE Geoportal could not be used (see "Could not be verified").

**Pending changes to the framework.**

- The Commission's Data Union Strategy of 19 November 2025 says: "In 2026, the Commission will propose to expand the list of high-value datasets to cover legal, judicial, administrative and other data", scheduled for Q4 2026 ([EUR-Lex, COM(2025) 835 final](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=CELEX:52025DC0835)).
- The Digital Omnibus proposal COM(2025) 837 (CELEX:52025PC0837) would repeal Directive (EU) 2019/1024 and consolidate its rules in Regulation (EU) 2023/2854 (Data Act).
- It is not adopted. On 11 November 2026 the Parliament's file 2025/0360(COD) shows "Status: Awaiting committee decision" ([Legislative Observatory](https://oeil.europarl.europa.eu/oeil/en/procedure-file?reference=2025/0360(COD))). "At the end of June 2026, Member States did not adopt the Council's compromise text." ([EDRi](https://edri.org/our-work/the-digital-omnibus-is-going-on-summer-break-your-rights-are-not/)).

### Cross-border sources compared

Country codes are ISO codes. GISCO writes Greece as EL.

| Source | Link | What it holds | EU countries covered (and which are missing) | Access (account, key, bulk or lookup) | Licence | Freshness | Check |
|---|---|---|---|---|---|---|---|
| OpenAddresses | [batch.openaddresses.io](https://batch.openaddresses.io/); source definitions: [sources/](https://github.com/openaddresses/openaddresses/tree/master/sources) | Address points gathered from public sources, one output file per source. Also parcel, building and centerline layers. | 24 of 27. Missing: HU, IE, MT. Partial: DE (15 of 16 Länder, no Bavaria), SE (18 municipalities), RO (Bucharest and four nearby towns, no output since 2020), CY (no house numbers). Stale: SI. | Free account and login needed; anonymous download returns HTTP 403. Bulk, per source, as GeoJSON. No Europe file: about 200 files (estimate) or the global collection of 19.4 GB. | Each source keeps its own licence; nothing is relicensed. | Weekly batch run. 11 national EU sources are cached copies, not live reads; the oldest dated upload is 2025-01-07 (BG). | confirmed; Romania corrected |
| Overture Maps, addresses theme | [addresses guide](https://docs.overturemaps.org/guides/addresses/); [attribution and licensing](https://docs.overturemaps.org/attribution/) | "over 475 million" address points, 41 countries, one schema. The theme is "currently in Alpha". | 19 of 27. Missing: BG, CY, GR, HU, IE, MT, RO, SE. Partial: DE (15 Länder, no Bavaria). | No account, no key. Bulk GeoParquet on public S3 and Azure storage. | Per country, mostly CC BY 4.0 or CC0; no single licence. | Monthly. Latest release 2026-10-21.0; every EU source "Accessed: 2026-10-15". | confirmed; three details corrected |
| GISCO Address API (Eurostat) | [swagger.yaml](https://gisco-services.ec.europa.eu/addressapi/swagger.yaml); [docs](https://gisco-services.ec.europa.eu/addressapi/docs/) | Geocoding and reverse geocoding over "a pan-european address database" from "authoritative data sources in the participating countries". | 26 of 27. Missing: IE. | No account, no key. Lookup only: no bulk endpoint; the publisher's documentation shows a limit of 1,000 house numbers. | None stated. | Dated for three countries only: AT 05.05.2022, DE 2021, HR 2022. | confirmed |
| OpenStreetMap, Geofabrik extracts | [download.geofabrik.de/europe.html](https://download.geofabrik.de/europe.html) | The whole OSM database per country, including objects tagged `addr:housenumber`. | All 27 (Ireland in one file with Northern Ireland). House-number coverage very uneven. | No account. Bulk `.osm.pbf`. | "License: ODbL 1.0" | Change files (`.osc.gz`) per region. Tag statistics dated 2026-11-10. | confirmed |
| INSPIRE Geoportal | [inspire-geoportal.ec.europa.eu](https://inspire-geoportal.ec.europa.eu/srv/eng/catalog.search#/home) | Central catalogue of national INSPIRE datasets and services. | Not established. | Not usable: TLS certificate expired on 30 October 2026. | Set per dataset by each country. | - | unverified |
| data.europa.eu, HVD "Addresses" filter | [search API](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D) | Catalogue records that link to national datasets. Metadata only. | 8 of 27 have a tagged record: AT, BE, CZ, ES, HR, LT, LU, SK. | No account, no key. Search API. | Per dataset. | Live catalogue. | confirmed |
| EuroGeographics, Open Cadastral Map (prototype) | [Open Maps for Europe](https://eurogeographics.org/open-maps-for-europe/) | A map that shows national INSPIRE open data (administrative units, parcels, buildings, addresses) and links to the national download. No address download of its own was found. | 15 national authorities by July 2025, among them PL, NL, CZ, ES, BE, EE, IE, HR. Full list not confirmed. | Links "for direct download from national geoportals". | "a single licence", not named on the page. | The funding project ran "until the end of 2025". | confirmed; licence unverified |
| GeoNames postal codes | [download.geonames.org/export/zip/](https://download.geonames.org/export/zip/) | Postcode, place name, estimated centre point. No streets, no house numbers. | 26 of 27 have a country file. Missing: GR. Partial codes: IE, MT. | No account. Bulk, one zip per country. | CC BY 4.0 | Regenerated daily; files dated 2026-11-11. | confirmed; date corrected |
| GISCO postal code points (Eurostat) | [Postal codes](https://ec.europa.eu/eurostat/web/gisco/geodata/administrative-units/postal-codes) | One point per postcode with NUTS code and degree of urbanisation. No addresses. | "EU, EFTA and candidate countries"; no per-country list was collected. | Bulk: GeoPackage, SHP or CSV. | CC-BY-SA-4.0 | Versions 2024 and 2020. | confirmed |
| UPU Universal POST*CODE DataBase | [UPU addressing solutions](https://www.upu.int/en/postal-solutions/programmes-services/addressing-solutions) | "A world postcode database containing the postcodes of 192 member countries". | Not listed per country. | Licence contract, non-disclosure agreement, data use declaration and a rates document. Sample extracts by region are on the page. | UPU's own licence contract. | Update 2026.1, dated 02.03.2026. | confirmed; price not seen |

#### OpenAddresses in detail

- It describes itself as "The free and open global address collection": "All data is openly licensed. Most sources only require attribution." ([openaddresses.io](https://openaddresses.io/)).
- The data "is not relicensed from the original sources. Individual sources will have their own licenses". The source definitions in `sources/` are CC0 and the code is BSD 3-Clause ([repository README](https://github.com/openaddresses/openaddresses)).
- Size: 5,329 source layers from 3,231 sources worldwide, of which 3,148 are address layers ([batch.openaddresses.io/api/data](https://batch.openaddresses.io/api/data)). That API lists each source and layer with the date of its last successful run and its output size. It gives no record counts.
- Login: an anonymous request for [a job output](https://batch.openaddresses.io/api/job/946822/output/source.geojson.gz) returns HTTP 403 "Authentication Required". The site says: "Only logged in users can perform downloads." A self-service registration form exists.
- Account levels: basic ("GeoJSON Format", "CDN Data Access"); Backer, >= $5 a month ("300 Custom Format Exports per Month"); Sponsor, >= $100 a month ("Direct AWS S3 Access", "Validated Data"). Payments run through [OpenCollective](https://opencollective.com/openaddresses/contribute).
- Collections ([api/collections](https://batch.openaddresses.io/api/collections)): Global (76.8 GB raw, 19.4 GB processed, built 2026-11-09), four US regions and Canada. There is no Europe or per-country collection.
- Estimate: an EU import needs about 200 source files. The repository holds 279 EU address-layer definitions, 241 of them not marked `skip`; that count includes city files and stale ones, so "about 200" is a round figure for the national and regional files.
- Freshness: the run date is not the data date. These national sources are cached uploads, as old as the upload: AT (register date 01.04.2026), BG (2025-01-07), CY (2026-09-29), CZ (age of the cached file not known; the source page names the 2024-08-31 export), DK (2026-03-27), FI (2026-09-30; the Swedish-language file 2026-06-03), GR (2026-09-29), IT (file dated 2026-07-03; last successful run 2026-08-14), NL (2026-06-03), PT (2026-02-23), ES (2026-06-03; last successful run 2026-09-18). These read the publisher's live URL: BE, HR, FR, LV, LT, LU, PL, SK, and EE through a third-party mirror. SI also reads a live URL, but its address run has failed since 2024-06-14. The German Länder last ran between 2026-10-16 and 2026-10-30.
- Postcodes: mapped for AT, BE, HR, CZ, DK, FI, FR, LV, LT, LU, NL, PL, PT, SK, SI, ES and nine German Länder (BB, Berlin, HB, HH, RP, SH, SL, SN, TH). Not mapped for BG, CY, EE, GR, the Italian countrywide file and six German Länder (BW, HE, MV, NI, NW, ST). Mixed in SE.
- Licences as recorded per source: CC BY 4.0 for AT, BE, CY, CZ, DK, FI, GR, IT, LV, LT, PT, SI, ES; CC0 for LU, NL, SK; Licence Ouverte Etalab 2.0 for FR; the Estonian open-data licence (attribution required) for EE; "Polish Law on Geodesy and Cartography of 17 May 1989", no attribution, for PL; "no limitations to public access" for HR. Germany: DL-DE BY 2.0 (BB, BW, HH, RP, SL, SN, ST, TH), DL-DE Zero 2.0 (Berlin, HE, NW), CC BY 4.0 (HB, MV, NI, SH). No licence is recorded for the Bulgarian countrywide source, for Romania and for several Swedish municipalities. No EU address source is flagged share-alike (0 of 279; many leave the flag unset).
- At national level only Croatia and Portugal are built from the INSPIRE address download. Portugal's file is a cached upload derived from the INE service, not a live read.

#### Overture addresses in detail

- Built "from over 175 sources. Most address points are distributed through community aggregators — chiefly OpenAddresses and AddressForAll — supplemented by authoritative open datasets published by public agencies" ([addresses guide](https://docs.overturemaps.org/guides/addresses/)).
- 15 of the 19 EU countries are labelled "Distributed by OpenAddresses". Belgium, Czechia, the Netherlands and Slovenia are not. Slovenia shows the difference: OpenAddresses last built it on 2024-06-14, while Overture lists 580,213 Slovenian addresses accessed 2026-10-15.
- The access date is the day Overture pulled the source. It is not the register's own reference date.
- Schema: "street number, street name, unit, address levels, postal code, and/or country"; the query examples use `number`, `street`, `unit`, `postcode`, `country`.
- Paths for release 2026-10-21.0: `s3://overturemaps-us-west-2/release/2026-10-21.0/theme=addresses/type=address/*.parquet` and `https://overturemapswestus2.blob.core.windows.net/release/2026-10-21.0/theme=addresses/type=address/*`. An unsigned S3 listing and an unsigned HEAD on one part file (396,310,089 bytes) both returned HTTP 200. The Azure path was not requested.
- Releases are listed in the [STAC catalogue](https://stac.overturemaps.org/catalog.json): 2026-09-23.0, 2026-09-23.1 and 2026-10-21.0 (latest).
- Tools ([Getting data](https://docs.overturemaps.org/getting-data/)): `pip install overturemaps`, then `overturemaps download --bbox=... -f geojson --type=...`; or DuckDB with `LOAD spatial; LOAD httpfs; SET s3_region = 'us-west-2'`.
- Licence, from the [attribution page](https://docs.overturemaps.org/attribution/): "All carry permissive open licenses. Some have special terms or require attribution." Per country: CC BY 4.0 for AT, BE, CZ, FI, IT, LV, LT, SI, ES; CC0 for EE, LU, NL, SK; Licence Ouverte 2.0 for FR; "Open License" for HR; "Terms of use for free geographic data" for DK; "No conditions to access and use" for PL; no licence named for PT. Germany as in OpenAddresses: DL-DE BY 2.0 (BW, BB, HH, RP, SL, SN, ST, TH), DL-DE Zero 2.0 (Berlin, HE, NW), CC BY 4.0 (HB, MV, NI, SH).
- Two licence labels need a check at the national source. Estonia: Overture says CC0, OpenAddresses records the Estonian open-data licence with attribution required. Portugal: Overture names no licence, OpenAddresses records CC BY 4.0, and INE's own download page says "No restrictions".

#### GISCO Address API in detail

- Endpoints: `/search`, `/reverse`, `/bbox`, `/most-populated-cell`, `/countries`, `/provinces`, `/cities`, `/roads`, `/housenumbers`, `/postcodes`, `/copyright`. The definition contains no bulk or download endpoint.
- [/countries](https://gisco-services.ec.europa.eu/addressapi/countries) returns 31 codes: 26 Member States plus CH, FO, IS, LI, NO.
- A worked call: [5 Rue Alcide de Gasperi, Luxembourg](https://gisco-services.ec.europa.eu/addressapi/search?country=LU&city=Luxembourg&road=Rue%20Alcide%20de%20Gasperi&housenumber=5) returns house number, street, city, province, postcode 1615, NUTS codes, coordinates and an Open Location Code.
- Limits: the publisher's own documentation shows only a 1,000 house-number limit. A third-party R client documents more: `/search` at most 1,000 addresses; `/roads`, `/housenumbers`, `/postcodes` 1,000 each; `/reverse` five ([giscoR reference](https://ropengov.github.io/giscoR/reference/gisco_address_api.html)). No rate limit is documented; none was tested.
- Licence: no licence, terms of use or rate limit appear in the API definition or its documentation. Eurostat's general reuse notice (CC BY 4.0 for Commission-owned content, with exceptions for third-party content) says nothing specific about this API ([copy in the giscoR package](https://stat.ethz.ch/CRAN/web/packages/giscoR/COPYRIGHTS)).
- Data owners named by [/copyright](https://gisco-services.ec.europa.eu/addressapi/copyright): AT Österreichisches Adressregister; BE National Geographic Institute; BG АГКК; CY Department of Lands and Surveys; CZ State Administration of Land Surveying and Cadastre; DE GeoBasis-DE / BKG; DK Styrelsen for Dataforsyning og Effektivisering; EE Land Board; EL Hellenic Cadastre; ES Dirección General del Catastro; FI Digi- ja väestötietovirasto; FR Direction interministérielle du numérique; HR State Geodetic Administration; HU Lechner Tudásközpont; IT Geoportale nazionale; LT Registrų centras and Lietuvos automobilių kelių direkcija; LU Administration du cadastre et de la topographie; LV Valsts zemes dienests; MT National Statistics Office; NL Basisregistraties Adressen en Gebouwen; PL "Urzędy centralne"; PT Instituto Nacional de Estatística; RO ANCPI; SE Lantmäteriet; SI Surveying and Mapping Authority; SK Národná agentúra pre sieťové a elektronické služby. Ireland is listed with a null copyright.
- Estimate: these strings suggest that national authorities of all 26 countries supplied data, including BG, CY, GR, HU, MT, RO and SE, which Overture lacks. This is a reading of a copyright string, nothing more. It does not show that the same data can be downloaded openly in that country.
- The documentation front end is version 2.2.1, built 28/04/2026. One oddity: [/postcodes?country=LU](https://gisco-services.ec.europa.eu/addressapi/postcodes?country=LU) returns an empty list although Luxembourg search results carry postcodes.

### Coverage by country

"yes" means: OpenAddresses or Overture holds a countrywide address set; the GISCO API lists the country; GeoNames has a postcode file for the country. It does not mean the set is current or complete; the words in brackets say what is known. Overture figures are the publisher's address counts for release 2026-10-21.0. Dates in the OpenAddresses column are the age of the cached copy it serves.

| Country | OpenAddresses | Overture addresses | GISCO Address API | GeoNames postcodes |
|---|---|---|---|---|
| AT Austria | yes (register date 01.04.2026) | yes (2,523,030) | yes (data of 05.05.2022) | yes |
| BE Belgium | yes (three regional sets, live) | yes (7,001,489) | yes | yes |
| BG Bulgaria | yes (no postcodes; no licence recorded; copy of 2025-01-07) | no | yes | yes |
| CY Cyprus | partial - no house numbers; about 4 % coverage by the source's own note | no | yes | yes |
| CZ Czechia | yes (cached copy, age not known) | yes (3,021,471) | yes | yes |
| DE Germany | partial - 15 of 16 Länder; Bavaria has building footprints only | partial - the same 15 Länder (19,299,493) | yes (data of 2021) | yes |
| DK Denmark | yes (copy of 2026-03-27) | yes (3,933,282) | yes | yes |
| EE Estonia | yes (no postcodes; live, through a mirror) | yes (2,277,177) | yes | yes |
| ES Spain | yes (copy of 2026-06-03) | yes (15,627,615) | yes | yes |
| FI Finland | yes (copy of 2026-09-30) | yes (3,670,323) | yes | yes |
| FR France | yes (104 files, live) | yes (26,052,116) | yes | yes |
| GR Greece | yes (no postcodes; copy of 2026-09-29) | no | yes (as EL) | no - no country file |
| HR Croatia | yes (live) | yes (1,682,868) | yes (data of 2022) | yes |
| HU Hungary | no | no | yes | yes |
| IE Ireland | no | no | no | partial - first letters of the codes only |
| IT Italy | yes (no postcodes; file of 2026-07-03; last good run 2026-08-14) | yes (26,841,754) | yes | yes |
| LT Lithuania | yes (live) | yes (1,130,062) | yes | yes |
| LU Luxembourg | yes (live) | yes (179,635) | yes | yes |
| LV Latvia | yes (live) | yes (550,686) | yes | yes |
| MT Malta | no | no | yes | partial - first letters of the codes only |
| NL Netherlands | yes (copy of 2026-06-03) | yes (9,988,169) | yes | yes (full codes only in `NL_full.csv.zip`) |
| PL Poland | yes (16 regional files, live) | yes (8,628,514) | yes | yes |
| PT Portugal | yes (copy of 2026-02-23) | yes (5,607,450) | yes | yes |
| RO Romania | partial - Bucharest and four nearby towns; no output since 2020 | no | yes | yes |
| SE Sweden | partial - 18 municipalities, five of them stale | no | yes | yes |
| SI Slovenia | partial - stale, last built 2024-06-14 | yes (580,213) | yes | yes |
| SK Slovakia | yes (live) | yes (1,704,346) | yes | yes |

Notes on the table:

- Romania in OpenAddresses: two source definitions and no licence. `ro/bucharest.json` (Bucharest, with postcode) has no batch output at all. `ro/bucharest-metro.json` covers "Otopeni, Sinaia, Voluntari, and Chitila"; its last update is 2020-08-21, with no output size.
- Sweden in OpenAddresses: 18 municipal sources, no countrywide one. Gislaved, Kristinehamn, Vaxholm and Växjö last succeeded on 2020-08-21. Helsingborg last succeeded on 2025-02-07.
- Cyprus in OpenAddresses, from the source definition: "Current source data contains no house numbers."
- Germany: OpenAddresses and Overture list the same 15 Länder (BB, Berlin, BW, HB, HE, HH, MV, NI, NW, RP, SH, SL, SN, ST, TH). Overture's guide names Germany among the countries with "only partial coverage".
- Greece in GeoNames: the download directory holds no `GR.zip` and no `EL.zip`. The combined file `allCountries.zip` was not opened.
- Estimate of where a national check matters most. GISCO serves 26 countries and Overture 19. The seven in GISCO but not in Overture are BG, CY, GR, HU, MT, RO and SE; Ireland is in neither. For these eight, Overture has nothing and OpenAddresses has nothing or a limited set, so open availability has to be established at the national register. This rests on comparing the two country lists, both confirmed.
- The table shows what the aggregators carry. A country missing from an aggregator can still publish open address data; the country sections answer that.

### OpenStreetMap as an address source

**Licence consequences.**

- Geofabrik's extracts carry the line "Data processed by Geofabrik GmbH and created by OpenStreetMap Contributors | License: ODbL 1.0" ([Geofabrik, Europe](https://download.geofabrik.de/europe.html)).
- The OpenStreetMap Foundation's guideline on geocoding ([OSMF Geocoding Guideline](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Geocoding_-_Guideline)) draws the line between single lookups and bulk extraction:
  - "Individual Geocoding Results are insubstantial database extracts".
  - "systematically reverse engineering the whole or a substantial part of the OSM database through Geocoding would result in creation of a Derivative Database".
  - A collection of results stays insubstantial only if "the collection is not a systematic attempt to aggregate all or substantially all Primary Features of a given type ... within a geographic area city-sized or larger".
  - Users "must provide attribution to OpenStreetMap as described in Section 4.3 of the ODbL".
- Reading for an import, not a quoted rule: a national address table built from an OSM extract is such a systematic collection, so it is a Derivative Database and ODbL's share-alike terms apply to it. This follows from the guideline's wording above; no source in this research states it for address imports specifically.
- Two products derived from OSM were seen to carry ODbL. Geoapify's postcode file for Germany is "Compiled by Geoapify from OpenStreetMap | ODbL" ([Geoapify downloads](https://www.geoapify.com/downloads/)). The French BANO composite described on the OSM wiki is "available under ODbL" ([OSM wiki, Addresses](https://wiki.openstreetmap.org/wiki/Addresses)).

**How complete house numbers are.** The table counts OSM objects tagged `addr:housenumber` per country extract (Geofabrik taginfo, data up to 2026-11-10; each country code links to its page; API pattern `https://taginfo.geofabrik.de/europe:{country}/api/4/key/stats?key=addr:housenumber`). The last column is an estimate: the OSM count divided by the address count Overture publishes for the same country from official registers. It was computed on the 2026-11-09 counts, which differ from those shown by under 0.06 %.

| Country | OSM objects with `addr:housenumber` | of which nodes | OSM count as share of Overture's register count (estimate) |
|---|---|---|---|
| [AT](https://taginfo.geofabrik.de/europe:austria/keys/addr:housenumber) | 2,513,835 | 404,388 | 99.6 % |
| [BE](https://taginfo.geofabrik.de/europe:belgium/keys/addr:housenumber) | 4,160,102 | 182,737 | 59 % (see below) |
| [BG](https://taginfo.geofabrik.de/europe:bulgaria/keys/addr:housenumber) | 182,317 | 16,034 | no register count to compare |
| [CY](https://taginfo.geofabrik.de/europe:cyprus/keys/addr:housenumber) | 30,820 | 7,257 | no register count to compare |
| [CZ](https://taginfo.geofabrik.de/europe:czech-republic/keys/addr:housenumber) | 3,095,114 | 2,958,182 | 102 % |
| [DE](https://taginfo.geofabrik.de/europe:germany/keys/addr:housenumber) | 20,845,744 | 4,062,817 | not comparable: Overture's 19.3 million leaves out Bavaria |
| [DK](https://taginfo.geofabrik.de/europe:denmark/keys/addr:housenumber) | 2,616,362 | 2,616,200 | 67 % |
| [EE](https://taginfo.geofabrik.de/europe:estonia/keys/addr:housenumber) | 437,832 | 12,014 | 19 % |
| [ES](https://taginfo.geofabrik.de/europe:spain/keys/addr:housenumber) | 2,262,964 | 1,600,415 | 14.5 % |
| [FI](https://taginfo.geofabrik.de/europe:finland/keys/addr:housenumber) | 1,111,499 | 153,332 | 30 % |
| [FR](https://taginfo.geofabrik.de/europe:france/keys/addr:housenumber) | 12,467,384 | 11,218,739 | 48 % |
| [GR](https://taginfo.geofabrik.de/europe:greece/keys/addr:housenumber) | 172,686 | 89,298 | no register count to compare |
| [HR](https://taginfo.geofabrik.de/europe:croatia/keys/addr:housenumber) | 274,842 | 106,463 | 16 % |
| [HU](https://taginfo.geofabrik.de/europe:hungary/keys/addr:housenumber) | 781,018 | 202,445 | no register count to compare |
| [IE, with Northern Ireland](https://taginfo.geofabrik.de/europe:ireland-and-northern-ireland/keys/addr:housenumber) | 491,868 | 23,064 | no register count to compare |
| [IT](https://taginfo.geofabrik.de/europe:italy/keys/addr:housenumber) | 4,671,280 | 4,550,005 | 17 % |
| [LT](https://taginfo.geofabrik.de/europe:lithuania/keys/addr:housenumber) | 1,074,718 | 301,141 | 95 % |
| [LU](https://taginfo.geofabrik.de/europe:luxembourg/keys/addr:housenumber) | 171,828 | 55,010 | 96 % |
| [LV](https://taginfo.geofabrik.de/europe:latvia/keys/addr:housenumber) | 361,894 | 142,270 | 66 % |
| [MT](https://taginfo.geofabrik.de/europe:malta/keys/addr:housenumber) | 4,636 | 2,452 | no register count to compare |
| [NL](https://taginfo.geofabrik.de/europe:netherlands/keys/addr:housenumber) | 9,956,110 | 9,871,860 | 99.7 % |
| [PL](https://taginfo.geofabrik.de/europe:poland/keys/addr:housenumber) | 8,606,626 | 3,205,275 | 99.7 % |
| [PT](https://taginfo.geofabrik.de/europe:portugal/keys/addr:housenumber) | 605,409 | 479,964 | 11 % |
| [RO](https://taginfo.geofabrik.de/europe:romania/keys/addr:housenumber) | 1,096,598 | 904,390 | no register count to compare |
| [SE](https://taginfo.geofabrik.de/europe:sweden/keys/addr:housenumber) | 1,008,652 | 375,025 | no register count to compare |
| [SI](https://taginfo.geofabrik.de/europe:slovenia/keys/addr:housenumber) | 446,653 | 67,880 | 77 % |
| [SK](https://taginfo.geofabrik.de/europe:slovakia/keys/addr:housenumber) | 1,626,980 | 65,797 | 95 % |

How to read the estimates:

- They compare unlike things. OSM counts tagged objects. A register can count units, entrances or, in Estonia, every address object. Treat the shares as a rough ranking, not as completeness figures.
- On these estimates OSM is close to the register count in NL, PL, AT, CZ, LU, SK and LT, and at roughly 10 to 20 % in PT, ES, HR, IT and EE.
- Belgium is the one country with a dated, methodical comparison. An OSM extract of 24 April 2025 held 3,900,105 addresses against 4,454,017 official positions, "a nice rate of 87.6 %". The official file had 7,004,321 records before points within 1 metre of each other were merged. The author adds: "We don't check the address quality here" ([juminet's OSM diary, 28 April 2025](https://www.openstreetmap.org/user/juminet/diary/406654)). The 59 % in the table divides by Overture's 7,001,489, which is close to that unmerged figure.
- In several countries OSM addresses come from official data. The OSM wiki records imports or syncs for the Netherlands (BAG import), Denmark ("All Danish address nodes have since February 2009 been imported"), Czechia (RÚIAN, "updated approximately every month") and Latvia (State Address Register, open data since January 2022, daily bot updates since 24 December 2024) ([OSM wiki, Addresses](https://wiki.openstreetmap.org/wiki/Addresses)).
- No study comparing OSM address completeness with official registers across several EU countries was found.

**Getting the data in bulk.**

- Geofabrik has an `.osm.pbf` extract for every Member State, without login; Ireland comes combined with Northern Ireland. `.gpkg.zip` is missing for Czechia, France, Germany, Italy, the Netherlands, Poland and Spain. The public files "do not contain the user names, user IDs and changeset IDs" ([Geofabrik, Europe](https://download.geofabrik.de/europe.html)).
- Photon geocoder dumps ([download1.graphhopper.com/public/](https://download1.graphhopper.com/public/)): planet database for Photon 1.x, 63.2 GB, updated 2026-11-10; planet JSON dump, 27.1 GB, updated 2026-11-09. The database supports only English, German, French and the local language and has "no support for structured search or full geometries". [Country extracts](https://download1.graphhopper.com/public/europe/) flag a ready database for Austria, Denmark, France-Monaco, Germany, Luxemburg, the Netherlands, Slovakia and Spain, and none for the other EU entries.
- OSMNames is stale: latest release v2.2.0 of 2022-12-09, last push 2024-08-07, code GPL-2.0 ([OSMNames releases](https://github.com/OSMNames/OSMNames/releases)).

**Usage limits of the public services.** Neither public service is a way to collect a country's addresses.

- Nominatim ([OSMF Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/)):
  - "an absolute maximum of 1 request per second";
  - a Referer or User-Agent that identifies the application ("stock User-Agents as set by http libraries will not do");
  - "Results must be cached on your side";
  - no autocomplete;
  - no systematic queries: "This includes reverse queries in a grid, searching for complete lists of postcodes, towns etc.";
  - bulk geocoding on a single thread; "Scripts running longer than a day and scripts that are run at regular intervals are restricted to 4 requests per minute";
  - for complete data the policy says to "get it from the OSM planet or an extract", and for heavy use to "install your own instance".
- Overpass API, main instance ([OSM wiki, Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API)): no key. The guideline for one-off use is "less than 10,000 queries per day and download less than 1 GB data per day"; for regular use the wiki divides those numbers by 100. For country-sized areas "it's better to use planet.osm mirrors". "Commercial use should use self-hosted or paid Overpass servers".

### Postcode-only sources

None of these holds addresses. Each gives a postcode with a place name or a point, and no street or house number.

**GeoNames postal codes.**

- What: a tab-delimited dump of country code, postal code, place name, three administrative levels, latitude, longitude and an accuracy code (1 = estimated, 4 = geonameid, 6 = centroid of addresses or shape). "about 120 countries are currently supported" ([readme](https://download.geonames.org/export/zip/readme.txt)).
- Licence: "This work is licensed under a Creative Commons Attribution 4.0 License. This means you can use the dump as long as you give credit to geonames (a link on your website to www.geonames.org is ok)".
- Coordinates are often estimates: "For many countries lat/lng are determined with an algorithm that searches the place names in the main geonames database"; otherwise "an average lat/lng of 'neighbouring' postal codes is calculated".
- EU coverage ([download directory](https://download.geonames.org/export/zip/)): a country file for 26 Member States; none for Greece. The files are regenerated daily; the listing showed 2026-11-11 03:53-03:54.
- Limits: "For Ireland we have only the first letters of the full postal codes (for copyright reasons)"; the readme says the same of Malta. For the Netherlands the combined `allCountries.zip` (19 MB) has "only the first part of the codes"; the full Dutch codes are in `NL_full.csv.zip` (3.5 MB).

**GISCO postal code points (Eurostat).**

- What: "The postal code point dataset shows the location of postal codes, NUTS codes and the degree of urbanisation classification across EU, EFTA and candidate countries from various sources" ([Eurostat GISCO, Postal codes](https://ec.europa.eu/eurostat/web/gisco/geodata/administrative-units/postal-codes)). Versions 2024 and 2020. Formats GeoPackage, SHP and CSV, in EPSG 3035, 4326 or 3857.
- Licence: "The dataset is released under the CC-BY-SA-4.0 licence and requires the following acknowledgement whenever used: © European Union - GISCO, 2024, postal code point dataset, Licence CC-BY-SA 4.0." This is a share-alike licence, unlike GeoNames' CC BY 4.0.
- Limits stated by the publisher: "'Non-geographical' postal codes (e.g. post boxes and postal codes used by large organisations) are not included", and "all existing postal codes might not be included or correctly located".
- Purpose: "to create correspondence tables for the NUTS classification" (TERCET). The tables are offered on the [TERCET flat files page](https://gisco-services.ec.europa.eu/tercet/flat-files).

**UPU Universal POST*CODE DataBase.**

- What: "A world postcode database containing the postcodes of 192 member countries" ([UPU addressing solutions](https://www.upu.int/en/postal-solutions/programmes-services/addressing-solutions)). Update 2026.1 is dated 02.03.2026.
- Licence: not open. It is supplied under UPU licence documents: a contract, a non-disclosure agreement, exhibits, a data use declaration and a rates document. No price is on the page, and the rates document was not opened.
- Also listed on the same page: sample extracts for five regions (Africa, Asia, Central-America, Eastern-Europe, Western-Europe), Postal Addressing Systems (PAS) country sheets, the Addressing knowledge centre and "Standard S42: International postal address components and templates".

**Other postcode or place files, in one line each.**

- Geoapify: "You can download these Postcodes Dataset for Free!", with a licence per country, for example France "Compiled by Geoapify from Géoclip | ODbL" and Germany from OpenStreetMap under ODbL. The direct-download table lists only DE, FR, GB and US ([Geoapify downloads](https://www.geoapify.com/downloads/); [Geoapify postal code downloads](https://geoapify.com/download-postal-codes)).
- Who's On First: administrative places (countries, regions, counties, localities, neighbourhoods), not addresses. "Crediting Who's On First is recommended and linking back to the License is required" ([Who's On First licences](https://whosonfirst.org/docs/licenses/); [Pelias data sources](https://github.com/pelias/documentation/blob/master/data-sources.md)).

### What does not exist

Each item is "none found" in the places named. None is a statement by the organisation concerned.

**No free EuroGeographics address-point product was found.**

- Searched: the [Open Maps for Europe page](https://eurogeographics.org/open-maps-for-europe/), EuroGeographics' licensing page `https://eurogeographics.org/activities/licensing/` (it covers paid licensing only), the front page of `https://www.mapsforeurope.org/`, and two trade-press reports.
- The open products are EuroRegionalMap (1:250 000), EuroGlobalMap (1:1 million), EuroDEM, Pan-European Imagery, the Open Gazetteer and a prototype Open Cadastral Map, "released as open data under a single licence". The Open Gazetteer holds "authoritative multilingual geographical names" from 36 national authorities: place names, not addresses.
- The Open Cadastral Map is the only product that touches addresses. It "takes INSPIRE open data and allows the user to find out what is available from national sources in one place before obtaining the data from the official provider". Its four data types are administrative units, cadastral parcels, buildings and addresses. It started with Poland, the Netherlands, the Czech Republic and Spain; by 29 July 2025 it had data from 15 national authorities after adding Belgium, Estonia, Ireland, Croatia and Switzerland ([GeoConnexion, 29 July 2025](https://www.geoconnexion.com/news/ome2-adds-five-new-countries-to-final-release-of-open-cadastral-map)).
- The final large-scale prototype of 17 December 2025 covers 10 countries with "administrative boundary, transport and hydrographic data". Addresses are not among its themes ([GeoConnexion, 17 December 2025](https://www.geoconnexion.com/news/open-maps-for-europe-2-ome2-adds-five-new-countries-and-hydrography-theme-to-final-release-of-high-value-data-prototype)).
- The funding project behind both (OME2) "runs until the end of 2025". Estimate: upkeep of the Open Cadastral Map after that date is uncertain. This rests only on the project end date and the "prototype" label.
- A related licence note: Eurostat's administrative-boundary files are "© EuroGeographics", and "If you intend to use the data commercially, please contact EuroGeographics for information about their licence agreements" ([Eurostat GISCO, administrative units](https://ec.europa.eu/eurostat/web/gisco/geodata/administrative-units)).

**No bulk download of the GISCO address database was found.** The API definition ([swagger.yaml](https://gisco-services.ec.europa.eu/addressapi/swagger.yaml)) has eleven paths and no bulk or download endpoint. The only GISCO bulk product seen in this area is the postal code point dataset.

**No Europe-wide or per-country file in OpenAddresses.** The [collections list](https://batch.openaddresses.io/api/collections) holds only Global, four US regions and Canada.

**No other free multi-country source of house-number address points was found** beyond OpenAddresses, Overture and OpenStreetMap. This is an estimate from the sources looked at; a lookup cannot prove it. The other projects seen reuse the same data:

- Pelias, an open-source geocoder, imports OpenAddresses ("it only contains address data"), OpenStreetMap ("licensed under the ODbL"), Who's On First and GeoNames ([Pelias data sources](https://github.com/pelias/documentation/blob/master/data-sources.md)).
- libpostal's training data is built from OSM addresses, "most of the address data sets from OpenAddresses" and Yahoo GeoPlanet postal codes. It is "over 100GB unzipped", and the examples are altered ("We also add abbreviations, drop out components at random, etc."), so it is not a clean address file ([libpostal README](https://github.com/openvenues/libpostal)).
- Photon dumps: see the OpenStreetMap section.
- Wikidata has address properties: P6375 "street address", P669 "located on street" with qualifier P670 "house number", P281 "postal code" ([Wikidata API](https://www.wikidata.org/w/api.php?action=wbgetentities&ids=P6375%7CP281%7CP669%7CP670&props=labels%7Cdescriptions&languages=en&format=json)). Its structured data is "released into the public domain under Creative Commons Zero" ([Wikidata:Licensing](https://www.wikidata.org/wiki/Wikidata:Licensing)). No per-country coverage of these properties was measured.

**No maintained comparison list of open address data for the 27 countries was found.**

- The OSM wiki page [Potential Datasources](https://wiki.openstreetmap.org/wiki/Potential_Datasources) (last edited 16 June 2026) carries the notices "This page is being considered for cleanup" and "may contain out-of-date information". The word "address" does not occur in it.
- The Open Data Maturity Report 2025 gives only aggregate, self-reported HVD scores per country and no address-dataset table.
- No Commission or JRC study comparing the openness of national address registers was found by web search.
- No community-curated catalogue of European open address data was found. The search for one was not exhaustive.
- The INSPIRE Geoportal's per-theme overview could serve as such a list, but it was unreachable.
- Working substitutes, each a by-product of something else and each machine-readable:
  - the OpenAddresses [source tree](https://github.com/openaddresses/openaddresses/tree/master/sources), organised by ISO country code, with data URL, licence and field mapping per source, and its [batch API](https://batch.openaddresses.io/api/data);
  - Overture's per-country count table in the [addresses guide](https://docs.overturemaps.org/guides/addresses/) and source and licence table on the [attribution page](https://docs.overturemaps.org/attribution/), refreshed with each release;
  - the GISCO Address API's [/countries](https://gisco-services.ec.europa.eu/addressapi/countries) and [/copyright](https://gisco-services.ec.europa.eu/addressapi/copyright);
  - the data.europa.eu [HVD "Addresses" filter](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D);
  - the OSM wiki [Addresses](https://wiki.openstreetmap.org/wiki/Addresses) page, which links per-country import projects and quality tools (Nominatim Data Analyser, OSM Inspector).

**No official record of compliance with the HVD Regulation for addresses was found.**

- No per-country compliance table, dashboard or study from the Commission (web search; the Open Data Maturity Report 2025 was read and has none).
- No published Article 5 report from a Member State (web search).
- No infringement procedure about HVD publication. The searches returned only older cases on the transposition of the Open Data Directive.

**Smaller negative findings.**

- No address dump published by the Nominatim project was found.
- No licence or terms of use for the GISCO Address API were found in its definition or documentation.

### Could not be verified

**INSPIRE Geoportal.**

- The whole catalogue at [inspire-geoportal.ec.europa.eu](https://inspire-geoportal.ec.europa.eu/srv/eng/catalog.search#/home). Its TLS certificate was valid from 14 April 2026 to 30 October 2026 13:46:18 GMT and had not been renewed on 11 November 2026. Standard clients refuse the connection ("certificate has expired"). Consequences:
  - no per-country list of working, downloadable INSPIRE address datasets and their licences could be compiled;
  - whether the Geoportal has a view for high-value or priority datasets could not be checked;
  - the record address form `https://inspire-geoportal.ec.europa.eu/srv/api/records/{id}` could not be tried.
- Lithuania's INSPIRE address record, `https://inspire-geoportal.ec.europa.eu/srv/api/records/876e6fc9-827d-40e1-a479-f5365b3d9ea2` (said to offer a zip, WMS and ATOM from Centre of Registers data of November 2024): not fetched, same certificate.
- Spain's record `https://inspire-geoportal.ec.europa.eu/srv/api/records/ES_SDGC_AD` and the statement that the DG Cadastre dataset covers every region except the Basque Country and Navarre: not fetched, same certificate. The separate datasets of Navarre, Gipuzkoa and Bizkaia are confirmed on data.europa.eu.
- Sweden, Lantmäteriet's product "Address download, INSPIRE": the page `https://lantmateriet.se/en/geodata/geodata-products/product-list/address-download-inspire` and its parent product list both returned HTTP 404.
- Whether any national INSPIRE address file actually lacks postcodes or restricts access: no source was found. The data model's constraints are quoted above; nothing more is established.
- Which countries offer addresses through OGC API Features: not researched.

**HVD compliance.**

- An independent count of HVD records on data.europa.eu dated 3 October 2026 (EasyxLab study S17, `https://easybyte.es/lab/studies/s17/paper/`): the site returned HTTP 403, so none of its figures is used here.
- The dates derived by arithmetic (end of exemptions and first Article 5 reports about 9 February 2025, next reports about February 2027) are stated in no source.

**OpenAddresses.**

- Whether a basic account is free: a self-service "Create An Account" form exists, and nothing seen contradicts it, but no account was created.
- The age of the Czech cached file: the source page names the export of 2024-08-31; the date of the cached file itself was not established.
- Address counts per country: the batch API gives file sizes only.
- House-number null rates of 27.13 % (OpenAddresses) and 30.15 % (OSM) attributed to a 2023 paper (Sierra-Requena et al., ISPRS Int. J. Geo-Inf. 12(10):407, `https://www.mdpi.com/2220-9964/12/10/407`): the publisher returned HTTP 403 and the abstract has no such figures. The paper exists and proposes an ISO 19157-based quality check of address data.

**Overture.**

- How long old releases stay available: no policy text was seen. The STAC catalogue lists only three releases.
- The licence for Estonia (CC0 at Overture, attribution required at OpenAddresses) and for Portugal (none named at Overture, CC BY 4.0 at OpenAddresses, "No restrictions" at INE): the labels disagree. OpenAddresses' licence link for Portugal points to the unreachable INSPIRE Geoportal.

**GISCO.**

- The licence of the Address API's data: not stated by the publisher.
- Rate limits: none documented, none tested.
- The limits of 1,000 results for `/search`, `/roads` and `/postcodes` and of five for `/reverse`: documented only by a third-party client.
- Reference dates for 23 of the 26 Member States, total address counts, and why Ireland is absent: not published by the API.
- The file list on the [TERCET flat files page](https://gisco-services.ec.europa.eu/tercet/flat-files): the page is a JavaScript shell and showed no list to a plain HTTP client.
- The sources behind the GISCO postal code points ("various sources"): not identified.

**EuroGeographics.**

- The name and terms of the "single licence" for its open products: not on the pages read.
- Whether the Open Cadastral Map serves address features itself or only displays them, and the full list of its 15 authorities: not confirmed.
- Whether the services behind `https://www.mapsforeurope.org/` still work after the project end: only the front page was fetched (HTTP 200, a JavaScript shell).

**Postcode sources.**

- GeoNames and Greece: there is no country file, but `allCountries.zip` was not opened, so Greek rows inside it are not excluded.
- UPU: the claim that some countries also require a national licence. The product sheet `https://www.upu.int/UPU/media/upu/documents/PostCode/UniversalPostcodesDatabaseProductSheetEnglish.pdf` exists (904,812 bytes) but was not read. Prices were not seen. Whether the S42 standard can be downloaded free was not checked.
- Who's On First: whether the licence change proposed in 2018 (from CC BY to "Community Data License Agreement – Permissive, Version 1.0", [announcement](https://whosonfirst.org/blog/2018/08/21/license-change/)) took effect, and its postcode coverage per EU country.

**OpenStreetMap tooling.**

- What the "not available" flag on Photon's country pages means in practice (no database dump only, or no extract at all).
- The German regio-osm house-number evaluation and the French BANO statistics: not checked.

**Comparison studies.**

- The content of the JRC report JRC109035, `https://publications.jrc.ec.europa.eu/repository/bitstream/JRC109035/jrc109035_jrc109035_jrc_inspire_eu_summaryreport_online.pdf`: the file exists (1,343,607 bytes) but was not read.
- Outputs of the European Location Framework project and any UN-GGIM: Europe recommendation on addresses: not researched.

# Countries

## Austria (AT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | BEV Adressregister, "Adresse Relationale Tabellen - Stichtagsdaten" | Bulk zip of CSV tables, no registration | CC BY 4.0 with a dated credit | Yes; MGI Gauss-Krüger, EPSG:31254, 31255 or 31256 per row | Yes | Twice a year (1 April, 1 October) |

**In short.** Use the BEV Adressregister (address register) extract "Adresse Relationale Tabellen - Stichtagsdaten" (address relational tables, reference-date data): one nationwide zip, free, no login, CC BY 4.0, with coordinates and postcodes. It is relational, so street and municipality names must be joined from separate tables, and each row names one of three Gauss-Krüger zones in its EPSG column; the INSPIRE edition of the same data in EPSG:3035 avoids the zones. The main limit is age: the extract is made twice a year and published two weeks later, so the free data can be about six and a half months old, and anything fresher is paid. The newest extract lives only at an undated URL whose content is replaced in place.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Adresse Relationale Tabellen - Stichtagsdaten, current extract | BEV | File: <https://data.bev.gv.at/download/Adressregister/Adresse_Relationale_Tabellen_Stichtagsdaten.zip>; catalogue record: <https://data.bev.gv.at/geonetwork/srv/api/records/040eebd0-d462-4eb0-b2a6-9ed778b83ac8> | Eight CSV tables for all of Austria: ADRESSE.csv (addresses with postcode and coordinates; 2,529,222 rows, researcher's count), GEBAEUDE.csv (buildings), ADRESSE_GST.csv, GEBAEUDE_FUNKTION.csv, STRASSE.csv (streets, 138,112 rows), ORTSCHAFT.csv (17,022), ZAEHLSPRENGEL.csv (8,843), GEMEINDE.csv (municipalities, 2,092); plus the interface description V1.5 | Direct zip, 118.5 MB, no login | CC BY 4.0; credit "© Österreichisches Adressregister, Stichtagsdaten vom TT.MM.JJJJ" | Reference date 01.10.2026, published 16 Oct 2026; twice a year | confirmed (the four large tables were not recounted) |
| Same product, previous extract | BEV | <https://data.bev.gv.at/download/Adressregister/Archiv_Adressregister/Adresse_Relationale_Tabellen_Stichtagsdaten_20260401.zip>; catalogue record: <https://data.bev.gv.at/geonetwork/srv/api/records/69980a2b-a223-40cf-897f-b9c24ec4a99e> | The extract of 01.04.2026 | Direct zip, 98.2 MB, no login | CC BY 4.0 | Archive file per past extract | confirmed |
| Adressregister INSPIRE, reference date 01.10.2026 | BEV | GeoPackage: <https://data.bev.gv.at/download/Adressregister/AT-INSPIRE_AD_Address_20261001.gpkg>; CSV: <https://data.bev.gv.at/download/Adressregister/AT-INSPIRE_AD_Address_CSV_20261001.zip>; catalogue record: <https://data.bev.gv.at/geonetwork/srv/api/records/bed08735-6342-49a2-8eae-6247363187c3> | The same register in the INSPIRE address model, EPSG:3035 | Direct files, GeoPackage 1.66 GB, CSV zip 218 MB | CC BY 4.0 | Same reference date as the relational extract | confirmed |
| Vienna address points (layer ogdwien:ADRESSENOGD, catalogue title "Adressen Standorte Wien") | Stadt Wien | <https://data.wien.gv.at/daten/geo?service=WFS&request=GetFeature&version=1.1.0&typeName=ogdwien:ADRESSENOGD&srsName=EPSG:4326&outputFormat=csv&maxFeatures=3> | Address points for Vienna with postcode and point geometry | WFS that returns CSV, no key | CC BY 4.0 (City of Vienna's data.gv.at record) | not stated | confirmed (licence corrected) |
| Tirol addresses | Tirol (regional), as recorded by OpenAddresses | <https://github.com/openaddresses/openaddresses/blob/master/sources/at/tirol.json> | Regional address source for Tirol | Through OpenAddresses; the publisher's own page was not read | CC BY, with the addition that the licensor has to be informed when the data is used; OpenAddresses gives the version as 3.0 AT in one field and 4.0 AT in another | not stated | unverified at the publisher |
| Postleitzahlen (postcode directory) | RTR | <https://data.rtr.at/api/v1/tables/plz.json>; field description: <https://www2.rtr.at/de/inf/odPLZ/Beschreibung_Postleitzahlen.pdf> | 2,731 postcode rows with fields plz, ort, bezirk, bundesland, gueltigab, gueltigbis, plztyp, internextern, adressierbar, postfach | REST endpoint, JSON, no key | Free official work under § 7 UrhG, no usage restriction, per RTR; the data.gv.at record labels it CC BY 4.0 | Monthly; version published 2026-11-04 | corrected (licence) |
| Gemeinde-, Ortschafts-, Straßen- und PLZ-Verzeichnis (directory of municipalities, localities, streets and postcodes) | Statistik Austria | <https://www.statistik.at/verzeichnis/strassenliste/gemplzstr.csv>; zipped: <https://www.statistik.at/verzeichnis/strassenliste/gemplzstr.zip> | Streets with municipality, locality, postcode and delivery place; no house numbers, no coordinates | Direct CSV, 13.5 MB, semicolon, UTF-8 without BOM | not found | File created 05.11.2026 | corrected (encoding); licence unverified |
| GISCO Address API | Eurostat | <https://gisco-services.ec.europa.eu/addressapi> | Address lookup for Austria; its data credit reads "Stichtagsdaten vom 05.05.2022" | No key; lookup only, 1,000-row cap, no bulk download | None stated | Snapshot credited 2022 | confirmed |
| OpenAddresses | OpenAddresses | <https://batch.openaddresses.io> | A cached copy of the BEV extract of 01.04.2026, plus Vienna and Tirol sources | Free download, needs a logged-in account | CC BY 4.0 for the BEV data | Run of 2026-10-30 on the April 2026 extract | confirmed |
| Overture Maps addresses | Overture Maps Foundation | <https://docs.overturemaps.org/guides/addresses/> | 2,523,030 Austrian addresses (publisher's figure), source Austrian Address Register | GeoParquet, no account | CC BY 4.0 | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | <https://download.geonames.org/export/zip/> | Postcode centroids only, no addresses | Bulk file | CC BY 4.0 | not stated | confirmed |

### Free APIs and services

- BEV INSPIRE view service (WMS), <https://data.bev.gv.at/geoserver/INSdataAD/wms>: map layers of the address and building geometries; answers without a key.
- BEV ATOM download feed, <https://data.bev.gv.at/geonetwork/srv/atom/describe/service?uuid=68cb9fac-e9ca-4366-b41f-79195fd31360>: the INSPIRE download service ("AT.BEV ATOM Downloaddienst"); answers without a key.
- RTR postcode endpoint, <https://data.rtr.at/api/v1/tables/plz.json>: the whole postcode directory in one JSON response, no key.
- Vienna address WFS, <https://data.wien.gv.at/daten/geo?service=WFS&request=GetFeature&version=1.1.0&typeName=ogdwien:ADRESSENOGD&srsName=EPSG:4326&outputFormat=csv&maxFeatures=3>: no key, CSV output, Vienna only.
- Vienna address geocoder ("Adressservice Wien"), <https://data.wien.gv.at/daten/OGDAddressService.svc/GetAddressInfo?Address=Stephansplatz%201&crs=EPSG:4326>: official, no key, CC BY 4.0, address search with geocoding and reverse geocoding, Vienna only.
- OpenPLZ API, <https://openplzapi.org/>: a community street and postcode directory that names Austria as covered; no house numbers, no key, ODbL. Its Austrian endpoints were not called.
- GISCO Address API (Eurostat), <https://gisco-services.ec.europa.eu/addressapi>: covers Austria, no key, lookup only with a 1,000-row cap, no licence stated.
- Two community tools build on the BEV file and must be self-hosted: a reverse geocoder with conversion script (<https://www.github.com/thomaskonrad/bev-reverse-geocoder>, last change 2020) and a search API (<https://www.github.com/the42/bevaddressapi>, last change 2018). Both are unmaintained.

### Caveats and recent changes

- The newest extract exists only at the undated URL. The dated archive name for 20261001 returns 404; the archive holds the 20260401 file. A pipeline must expect the undated file to change in place twice a year.
- Extracts are made at the start of the second and fourth quarter and offered 14 days later. The current one has the reference date 01.10.2026 and was published on 16 Oct 2026.
- File format: semicolon-separated CSV, UTF-8 with BOM, text fields quoted and numbers not. The ADRESSE columns are `ADRCD;GKZ;OKZ;PLZ;SKZ;ZAEHLSPRENGEL;HAUSNRTEXT;HAUSNRZAHL1;HAUSNRBUCHSTABE1;HAUSNRVERBINDUNG1;HAUSNRZAHL2;HAUSNRBUCHSTABE2;HAUSNRBEREICH;HNR_ADR_ZUSAMMEN;GNRADRESSE;HOFNAME;RW;HW;EPSG;QUELLADRESSE;BESTIMMUNGSART`. Street names are in STRASSE.csv (join on SKZ) and municipality names in GEMEINDE.csv (join on GKZ).
- Coordinates are in the RW and HW columns in MGI Gauss-Krüger; the EPSG column names the zone per row (31254, 31255 or 31256). Researcher's count for the 01.10.2026 extract: 1,292,757 rows in 31256, 998,255 in 31255 and 238,210 in 31254, and no address row without coordinates or postcode.
- BEV warns that the coordinate fields of an address can be empty ("NULL", not "0"). An import must handle that even though none was seen in the first 7,178 rows.
- Buildings: each building at an address has a 3-digit subcode; the 7-digit address code plus the subcode form the address number. GEBAEUDE.csv carries its own coordinates per building.
- The geocoding accuracy stated by BEV is one metre.
- The licence text files inside the 01.10.2026 zip (dated 1 June 2026) still name the reference date 01.04.2026. The file Aktualitaetsstand.txt in the same zip gives 01.10.2026. The licence asks for a credit with the reference date of the data ("Stichtagsdaten vom TT.MM.JJJJ").
- Municipalities maintain the addresses continuously through "Adress-GWR-online", the shared reporting channel of the address register and the buildings and dwellings register. The postcodes in the register are taken over quarterly (01.03., 01.06., 01.09., 01.12.) from postcode areas supplied by Österreichische Post AG.
- BEV's page for free products, <https://www.bev.gv.at/Services/Downloads/Produktbezogene-Downloads/Unentgeltliche-Produkte/Adressregister.html>, is stale (it still refers to April 2022). The catalogue records are the reliable place to find the current file. Both the October and the April record contain one link with a malformed "httpss://" scheme.
- The data.gv.at record "Adressen Relationale Tabellen - Stichtagsdaten" links archive files only up to 2023.
- The Statistik Austria street list is UTF-8, not Latin-1.
- OpenAddresses and GISCO serve older copies: OpenAddresses the extract of 01.04.2026, GISCO a state credited 05.05.2022.
- High-value dataset (HVD) marking is inconsistent between portals: data.gv.at shows `is_hvd: false` on the BEV address records, while data.europa.eu lists BEV address records under the HVD category "Addresses".

### Not free or not available

- Data fresher than the half-yearly extracts is paid. BEV sells "Adresse" geocoded at 1 m for EUR 0.045 per object. Update contracts cost 120% of the annual standard fee for monthly delivery, 60% for quarterly, 55% for half-yearly, 50% for yearly and 45% for two-yearly, with a minimum term of three years plus transfer costs per delivery (<https://www.bev.gv.at/Services/Produkte/Adressregister/Oesterreichisches-Adressregister.html>).
- BEV Adresssuch-Service (address search service, updated daily, returns coordinates): not free. It needs registration and a security certificate and costs EUR 10 per month for internal use and EUR 480 per year per application for external use (<https://www.bev.gv.at/Services/Geoinformationsdienste/Services/BEV-Adresssuch-Service.html>).
- Free nationwide official geocoding API: none found. Searched: data.gv.at for "Geocoder" (no hits) and "Adresssuche" (two hits, both from the City of Vienna). The only free official geocoder found covers Vienna.

### Could not be verified

- Row counts of the four large tables (ADRESSE.csv 2,529,222; GEBAEUDE.csv 2,538,894; ADRESSE_GST.csv 3,161,178; GEBAEUDE_FUNKTION.csv 822,118): researcher's counts, not recounted, because that needs the full 118 MB download. The file sizes are consistent with them.
- The per-zone totals and the statement that no address row lacks coordinates or a postcode: seen only in a sample of the first 7,178 rows, not over the whole file.
- Licence of the Statistik Austria street list: no catalogue record was found and the file carries no licence line.
- The endpoint kataster.bev.gv.at/api/all4map did not respond within 30 seconds; whether it is a free geocoder and on what terms is unknown. The address search of basemap.at and geoland.at was not checked.
- A postcode download page of Österreichische Post was not found; the RTR table is the confirmed free postcode source.
- An official statement on whether Austria's address data complies with the HVD regulation was not found.
- Tirol's own terms page was not read; the notification condition and the licence version rest on what OpenAddresses records.
- Rate limits for the services above: none was found published.

## Belgium (BE)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | BeSt Address (FPS BOSA) | Three regional CSV zips, no registration | CC BY 4.0 | Yes; WGS84 and Lambert 2008 (EPSG:3812) | Yes | Weekly |

**In short.** Use BeSt Address ("Belgian Streets and Addresses"), the federal aggregate of the three regional registers: three CSV zips (Flanders, Brussels, Wallonia) with one schema, downloadable without an account under CC BY 4.0. The trap is the switch of 18 October 2026 from Lambert 72 to Lambert 2008: the CSV columns `EPSG:31370_x/_y` became `EPSG:3812_x/_y`, and the regional registers' own downloads are still in Lambert 72. Flanders and Wallonia also publish their registers directly and freely; nothing on the Brussels publisher's own hosts could be reached, so for Brussels rely on the federal file.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| BeSt Address, CSV per region | FPS BOSA | Page: https://opendata.bosa.be/index.fr.html ; Flanders: https://opendata.bosa.be/download/best/openaddress-bevlg.zip ; Brussels: https://opendata.bosa.be/download/best/openaddress-bebru.zip ; Wallonia: https://opendata.bosa.be/download/best/openaddress-bewal.zip | Addresses down to box (unit) number. 20 columns: Lambert 2008 x/y, WGS84 lat/lon, address id, box number, house number, municipality id and names (de/fr/nl), postcode, postal names, street id and names, region code, status | Bulk download, no login. On 11 Nov 2026: Flanders 153,229,244 bytes (CSV 621,964,649), Brussels 18,162,025 (CSV 127,464,055), Wallonia 59,408,159 (CSV 312,521,293) | CC BY 4.0 | Weekly; all three regenerated 11 Nov 2026 about 10:40 GMT | corrected (file sizes and dates); row counts unverified |
| BeSt Address, full XML | FPS BOSA | https://opendata.bosa.be/download/best/best-full-latest.zip | Municipalities, street names, addresses, parts of municipalities (Wallonia only), postal info. Coordinates in Lambert 2008 only | Bulk download, no login; 310,469,883 bytes on 11 Nov 2026 (the page says "+/- 290 MB") | CC BY 4.0 | Weekly | confirmed |
| BeSt postal streets | FPS BOSA | https://opendata.bosa.be/index.nl.html (files `postalstreets-latest.zip` and `postalstreets-empty-latest.zip`) | Streets with at least one address per postcode (2,189,068 bytes); streets without addresses (222,588 bytes) | Bulk download, no login | CC BY 4.0 | Both dated 11 Nov 2026 | confirmed |
| Adressenregister ("address register", part of the Gebouwen- en Adressenregister), Flanders | Digitaal Vlaanderen | Full extract: https://api.basisregisters.vlaanderen.be/v2/extract ; download product: https://download.vlaanderen.be/product/11065 ; catalogue: https://www.vlaanderen.be/datavindplaats/catalogus/gebouwen-en-adressenregister-adressen | The authentic address source for Flanders. Product 11065: addresses as GeoPackage and Shapefile, each in Lambert 72 and Lambert 2008, 286-386 MB | Full extract: no login or key, redirects to a zip of 1,659,876,794 bytes. Product 11065 is open data; its files are fetched through an order in a web app | Modellicentie voor gratis hergebruik v1.0 ("model licence for free reuse"), https://data.vlaanderen.be/id/licentie/modellicentie-gratis-hergebruik/v1.0 | Extract rebuilt daily; catalogue says "Continu geactualiseerd" (continuously updated) | corrected |
| ICAR - Points d'adresses (Inventaire Centralisé des Adresses et des Rues, "central inventory of addresses and streets"), Wallonia | Service public de Wallonie | Record: https://geoportail.wallonie.be/catalogue/2998bccd-dae4-49fb-b6a5-867e6c37680f.html ; CSV: https://geoservices.wallonie.be/geotraitement/spwdatadownload/results/2998bccd-dae4-49fb-b6a5-867e6c37680f/icar_adpt_csv.zip ; SHP: https://geoservices.wallonie.be/geotraitement/spwdatadownload/results/2998bccd-dae4-49fb-b6a5-867e6c37680f/icar_adpt_shp.zip | Address points in Lambert 72 (EPSG:31370). Only addresses matched to a PICC building point have X,Y | Bulk download, no login: CSV 59,212,719 bytes, SHP 111,073,360 bytes | CC BY 4.0 | Extracted daily; last update shown 10/11/2026 | confirmed |
| Brussels address register (UrbIS) | Paradigm | https://datastore.brussels/web/data/dataset/a8c9ccde-5c2b-11ed-913a-900f0cda5d5c#access | BOSA states that Paradigm publishes the Brussels register there as CSV, GeoPackage and GeoJSON | Not reached: every Brussels host timed out | Not established | Weekly, per BOSA | unverified |
| BeSt address as GeoPackage and WMS (NGI/IGN derivative on geo.be) | NGI/IGN | https://www.geo.be/catalog/details/ca0fd5c0-8146-11e9-9012-482ae30f98d9?l=nl ; listing: https://transportdata.be/dataset/address-points-belgium-best-address | BeSt addresses repackaged as GeoPackage and WMS | Not exercised | Non-commercial use only | Not stated | corrected |
| bpost postcode lists | bpost | Page: https://www.bpost.be/nl/postcodevalidatie-tool ; file: https://www.bpost.be/sites/default/files/zipcodes/zipcodes_alpha_nl_2025.xls (also `zipcodes_num_nl_2025.xls` and `zipcodes_alpha_fr_2025.xls` in the same folder) | Postcode lists as XLS, 328,192 bytes each. No addresses | Download, no login | None stated; footer only "Copyright © 2026 Bpost" | Files dated 16 Mar 2026 | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Belgium | API, no key; 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definitions: https://github.com/openaddresses/openaddresses/tree/master/sources/be | Copies of the three BOSA CSVs (`be/bru`, `be/vlg`, `be/wal`) | Free download, needs a logged-in account | CC BY 4.0 (from the source) | Follows the BOSA files | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Address points for Belgium | GeoParquet, no account | Set per country; not recorded here | Per release | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **BeSt REST API (BOSA).** "For companies: free (but without guarantee)". OpenAPI file: https://best.pr.fedservices.be/api/opendata/best/v1/belgianAddress/v2/doc/openapi.yaml ("v2 Belgian Streets and Addresses REST API", version 1.12.10). The file declares OAuth2, yet an anonymous call such as https://best.pr.fedservices.be/api/opendata/best/v1/belgianAddress/v2/addresses?postCode=1000&streetName=Wetstraat&houseNumber=16 returned HTTP 200 with data. Positions come in WGS84, Lambert 72 and Lambert 2008. Public administrations go through the BOSA service integrator.
- **Rate limit of the BOSA endpoint:** none found. The BOSA page and the OpenAPI file say nothing about limits or quotas, and the responses carry no rate-limit headers.
- **Best-in-a-box.** A stand-alone Docker image with web service and database (`bosa/opendata-best-webapi`), described by BOSA as a test version with its own terms-of-use PDF.
- **Flanders REST API.** https://api.basisregisters.vlaanderen.be/v2/adressen?postcode=9000&limit=1 answers without a key (JSON-LD). Use GET; a HEAD request gets 403.
- **Flanders WFS.** https://geo.api.vlaanderen.be/Adressenregister/wfs?service=WFS&request=GetCapabilities , no key, feature type `Adressenregister:Adres`, default CRS EPSG:31370. The capabilities say use of the service is free.
- **Flanders OGC API Features.** https://geo.api.vlaanderen.be/Adressenregister/ogc/features/v1/collections?f=json , no key, one collection `Adres`.
- **Flanders geolocation (geocoding).** https://geo.api.vlaanderen.be/geolocation/v4/Location?q=Havenlaan%2088%20Brussel , no key; returns WGS84, Lambert 72 and Lambert 2008 coordinates. Register changes show there the next day; in the WMS "near realtime".
- **Wallonia.** ESRI REST at `geoservices.wallonie.be/arcgis/rest/services/DONNEES_BASE/ICAR_ADR_PT/MapServer`, a WMS and an ATOM feed. A custom extract is sent by e-mail within 48 hours. The record lists no WFS and no geocoding API.

### Caveats and recent changes

- **18 October 2026: Lambert 72 replaced by Lambert 2008 in the BeSt downloads.** XML: coordinates are now only in Lambert 2008 and file names no longer contain "L72". CSV: columns `EPSG:31370_x/_y` were replaced by `EPSG:3812_x/_y`. BOSA says differences of up to 20 cm are possible in extreme cases. Code that reads the old column or file names must be changed. The REST API still returns all three systems.
- **Last Lambert 72 files** (7 Oct 2026) are kept under `/download/best/archive/lambert72/` on opendata.bosa.be. The page link labelled "Full Download XML (07/10/2026)" points by mistake to the Flanders CSV; the XML archive is `archive/lambert72/best-full-20261007.zip`.
- **Mixed coordinate systems.** Wallonia's own download is in Lambert 72 (EPSG:31370) while the federal files are in Lambert 2008 (EPSG:3812). Do not mix them without reprojection. Flanders offers both.
- **BOSA's own quality warning.** For some applications the address information is not good enough to rely on the regional registers alone; the user must judge. Errors are reported to the regional partner.
- **Missing coordinates in Wallonia.** In ICAR, only addresses with a geometric match to a PICC building point carry X,Y.
- **Empty postal names for Brussels.** In a sample of the Brussels CSV the `postname_fr` and `postname_nl` columns were empty; the `postcode` column is filled.
- **Notices in the BOSA page source, not displayed on the page.** September 2025: Brussels reset all version numbers to 1, dropped postal-zone names from the postalInfo XML and removed many duplicate addresses and streets. January 2025: 28 Flemish municipalities merged and Flanders published old-to-new id mapping files ("verschilbestanden").
- **Flanders has two product ids.** Product 11065 (metadata record `ba7351f0-2a69-403f-9833-6be00ee93a54`) is current. Product 10145 (record https://metadata.vlaanderen.be/srv/api/records/9c8b57a1-3c9a-4813-926e-38bb0bd387a7) is the old "adressen in afbouw" (being phased out). Both carry the same free-reuse licence. Product 11065 has daily versions and difference files since 2026-08-13.
- **High-Value Dataset status.** BOSA's DCAT-AP file (`/download/best/dcat.rdf`) flags the BeSt API and the full XML download as High-Value Datasets, category Geospatial, under Regulation 2023/138. The derived CSV entry carries no such flag, and none was found on the Flemish, Walloon or Brussels records.
- **The weekly BOSA files change size from run to run;** the sizes above are those of 11 Nov 2026.

### Not free or not available

- **NGI/IGN derivative on geo.be (GeoPackage and WMS): non-commercial use only,** per BOSA and per transportdata.be. Transportdata.be adds that commercial use falls under the regional licences: the UrbIS licence for Brussels data, the free reuse licence for Flemish data, CC-BY 4.0 for Walloon data.
- **bpost postcode files:** free to download, but no licence or reuse terms are stated. The BeSt files already carry postcodes under CC BY 4.0.

### Could not be verified

- **Everything on the Brussels publisher's side.** `datastore.brussels`, `urbisdownload.datastore.brussels`, `geoservices-urbis.irisnet.be`, `geobru-geonetwork.irisnet.be` and `be.brussels` all timed out after 30 seconds on 11 Nov 2026. Whether the hosts were down or unreachable only from the test network is unknown. Unverified as a result: the UrbIS licence name and the statement that UrbIS has an open data licence allowing free and unrestricted use (https://be.brussels/en/about-region/urbis-data); the WFS at `geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs`; the download links; and a note that the older "UrbIS - Addresses" dataset does not follow the BeSt specification (https://geobru-geonetwork.irisnet.be/geonetwork/srv/api/records/a8a807b0-6b0b-11ed-8e3b-010101010000).
- **Brussels, second-hand only.** The data.europa.eu copy of the Brussels record (https://data.europa.eu/api/hub/search/datasets/a8c9ccde-5c2b-11ed-913a-900f0cda5d5c , modified 2026-10-21) lists zipped GeoPackage, XML and JSON files in Lambert 72 (for example `https://urbisdownload.datastore.brussels/LastVersion/BeStBrussels_31370_GPKG_04000_lastversion.zip`), ATOM feeds and a geocoding API (`https://geoservices.irisnet.be/geocoding/swagger-ui/index.html`), updated weekly in the night from Tuesday to Wednesday. It says the dataset is "freely downloadable for private individuals" and states no licence. None of these links was requested.
- **A new Paradigm geocoding API for all Belgian addresses "from mid-November":** year and URL not established.
- **BeSt row counts.** A count of 4,223,588 rows (Flanders), 849,246 (Brussels) and 2,109,079 (Wallonia), total 7,181,913, was made on the previous weekly run and not repeated. The Flanders and Brussels CSV byte sizes have not changed since; the Wallonia file has been replaced and grew by 59,168 bytes.
- **Flanders download app.** Whether the order step in the app at `download.vlaanderen.be` asks for a login was not exercised. The full extract at `/v2/extract` needs none. The internal format of that 1.66 GB extract zip was not examined.
- **Flanders API-key rules and rate limits.** The "Gebruik API key" guide returned an empty page; the API responses carry no rate-limit headers.
- **geo.be's own record for the NGI derivative** is a JavaScript page and was not read; the non-commercial condition rests on BOSA's and transportdata.be's wording.
- **Statbel page "Open data - Address files and statistical sectors - 2024"** (https://statbel.fgov.be/en/news/open-data-address-files-and-statistical-sectors-2024): the site served a CAPTCHA, as did `bosa.belgium.be`.
- **Best-in-a-box:** the Docker Hub image and its terms-of-use PDF were not opened.

## Bulgaria (BG)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | AGKK cadastre open data (KAIS): building polygons with address fields, numbering incomplete | Shapefile zips per settlement, no registration, no national file | None printed; open reuse known only second-hand | Yes, polygons in BGS2005; EPSG code not stated | No | Each province about every 28 days |

**In short.** No open national address register was found. The substitute is the cadastre agency's open-data file tree: per-settlement shapefiles of buildings, parcels and dwelling units that carry street, number, block, entrance, floor and flat, free without login. There is no national file, so an import must walk the tree settlement by settlement, and in the one town sampled only 62% of buildings had a street number. The page prints no licence. For Sofia alone there is a proper official address register under CC BY.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Отворени данни (Open Data) on the KAIS cadastre portal | Агенция по геодезия, картография и кадастър (AGKK, Geodesy, Cartography and Cadastre Agency) | https://kais.cadastre.bg/bg/OpenData ; English page: https://kais.cadastre.bg/en/OpenData | A file tree: 28 provinces, then municipalities, then settlements labelled with their EKATTE code. Up to six zips per settlement: land parcels, buildings, self-contained units (flats) and three ownership files. Polygons with address attributes | Zips download by plain GET, no login. No single national file | None printed on the page; see caveats | One province regenerated each night in rotation; each about every 28 days | confirmed; licence corrected |
| Адреси на територията на Столична община (addresses in Sofia Municipality) | „Географска информационна система – София" ЕООД (GIS Sofia, wholly owned by the municipality) | Dataset page: https://urbandata.sofia.bg/dataset/address_sofia-zip ; record as JSON: https://urbandata.sofia.bg/api/3/action/package_show?id=address_sofia-zip | The official addresses approved by order of the mayor, with coordinates; 125,245 addresses (publisher's figure, from the file header). Sofia only | GeoJSON (39,917,874 bytes) and CSV zip (1,863,178 bytes), no login | "Creative Commons Признание" (CC BY); no version number stated | Created 2026-08-28, record updated 2026-11-06; "current as of 28.08.2026" | confirmed |
| НКНПА, Национален класификатор на настоящите и постоянните адреси (national classifier of current and permanent addresses) | Not shown in the EU record; its keywords are "НКНПА", "ГРАО", "МРРБА" | Latest record: https://data.europa.eu/api/hub/search/datasets/22309 ; search: https://data.europa.eu/api/hub/search/search?q=%D0%B0%D0%B4%D1%80%D0%B5%D1%81%D0%B8&filter=dataset&facets=%7B%22country%22%3A%5B%22bg%22%5D%7D | Nine yearly editions in the EU catalogue: 2016, 2017, 2018, 2020, 2021, 2022, 2023, 2024, 2025. No 2019 and no 2026 edition. Content not seen | The EU record lists no downloads; the national portal data.egov.bg returns HTTP 403 | Not seen | 2025 record issued 2025-02-27 | corrected (editions); content unverified |
| Намерете пощенски код (find a postcode) | Bulgarian Posts | https://www.bgpost.bg/postal-services/po-codes | Postcode look-up by quarter, housing estate, boulevard, street or square | Web form behind reCAPTCHA; no downloadable file | Not stated | Not stated | confirmed |
| Пощенски кодове на населените места в България 2020 (postcodes of settlements in Bulgaria, 2020) | On the national open-data portal; publisher not seen | https://data.europa.eu/api/hub/search/datasets/14117 | A postcode list per settlement, by its title; content not seen | The EU record lists no downloads; data.egov.bg returns HTTP 403 | Not seen | Record issued 2022-01-14 | confirmed (existence only) |
| EKATTE (unified classifier of administrative-territorial units) | Национален статистически институт (National Statistical Institute, NSI) | https://www.nsi.bg/nrnm/ekatte/archive | Administrative units down to settlement level; no streets, no addresses | Yearly zips in Excel and JSON, 2022 to 2025 | None stated; the page says "© 2026 Национален статистически институт. Всички права запазени." | Yearly; no 2026 archive yet | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Bulgaria | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Bulgarian sources | OpenAddresses | Countrywide: https://github.com/openaddresses/openaddresses/blob/master/sources/bg/countrywide.json ; Sofia: https://github.com/openaddresses/openaddresses/blob/master/sources/bg/city_of_sofia.json ; downloads: https://batch.openaddresses.io | Countrywide: the KAIS buildings data from a cached copy uploaded 2025-01-07 (settlement, street, number). Sofia: the municipal register | Free download; needs a logged-in account | Countrywide: none recorded. Sofia: recorded as CC-BY-4.0 | Countrywide copy dates from 2025-01-07 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- No documented API for the KAIS open data. In practice: the tree is listed by a POST to `/bg/OpenData/Read`, which needs the page's session cookie and anti-forgery token (HTTP 400 without them). Files download with a plain GET to `/bg/OpenData/Download?path=<url-encoded path>`, which works without cookies.
- Sofia's portal exposes its record through the CKAN API: https://urbandata.sofia.bg/api/3/action/package_show?id=address_sofia-zip .
- Bulgarian Posts' postcode search is a web form behind reCAPTCHA, not an API.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.

### Caveats and recent changes

- KAIS licence. The open-data page prints no licence or reuse terms. Its footer reads "© 2025 Агенция по геодезия, картография и кадастър. Всички права запазени!" (all rights reserved). The only statement of reuse terms is second-hand: a post of 19 August 2025 in an OpenStreetMap community thread (https://community.openstreetmap.org/t/use-of-cadastral-data-from-on-osm/113018) reports AGKK's reply that the open data may be used for any purpose without restriction, that naming AGKK as the source is recommended, that the data are under an "open licence" in the sense of Directive (EU) 2019/1024, and that AGKK does not plan to add an explicit licence text. This is a community report of the reply, not AGKK's own page. The ordinance the post cites was not read in an official text.
- KAIS general terms (https://kais.cadastre.bg/bg/Terms) allow use "само за собствени нужди" (for own needs only) and forbid commercial use or passing data to third parties without a contract. These terms are written for remote-access services to registered clients and do not mention the open data.
- Addresses are attributes of cadastral objects, not address points. The geometry is polygons.
- Completeness, from one sample (town of Vidin, EKATTE 10971, files dated 2026-10-17): 14,197 buildings, of which 12,736 have a street name (`strename`), 8,812 a street number (`strnum`, 62%) and 1,448 a quarter name (`quarname`). All 14,197 have a full address text (`immaddr`), for example "гр. Видин, ул. Янтра №36". The same town has 28,441 units and 11,373 parcels.
- Fields. Buildings: `immaddr`, `strename`, `strnum`, `quarname`, `ekatte`, `ekattefn` (settlement), `cadnum` (cadastral identifier), `functype`, `flrcount`. The units file adds `blocknum`, `entrance`, `flrnum` (floor) and `appnum` (flat), with text such as "гр. Видин, ж.к. "Панония", бл. 3, вх. В, ет. 1, ап. 51".
- No postcode field and no Latin transliteration in any of the three files. Text is Cyrillic, UTF-8.
- Coordinate system: the `.prj` reads `PROJCS["BGS2005" … Lambert_Conformal_Conic …]` and carries no EPSG code.
- Refresh: on 2026-11-11 the 28 province folders were dated from 2026-10-14 (Плевен) to 2026-11-10 (Перник), one per night at about 22:00, with no gaps.
- Size of a harvest: the number of settlement folders was not counted. For scale, Vidin province has 11 municipalities and Vidin municipality has 34 settlement folders. The Vidin town zips are 2.2 MB (buildings), 4.7 MB (units) and 2.2 MB (parcels).
- The KAIS platform with this page went live in mid-December 2024, after services were suspended on 11 to 15 December 2024. This comes from community posts quoting AGKK notices.
- OpenAddresses' countrywide Bulgarian source reads a cached copy uploaded on 2025-01-07, not the live tree.
- Sofia file: fields are `street`, `streetnum`, `block`, `entrance`, `lareaunit` (housing estate), `settlement`, `region`, `rn`. Block-addressed buildings in housing estates have no street or house number. The server labels the GeoJSON `Content-Type: application/zip` although it is plain GeoJSON.
- Sofia's open licence is a change. In 2021 GIS Sofia treated the address data as copyrighted and not to be shared without its consent, according to a post in the same community thread.
- Planned national register: a 2020 e-government project document (https://projectregister.egov.bg/wp-content/uploads/2020/06/ИСУН2020-ЦАИСГР-ЦАИСАР.pdf) specifies ЦАИС „Адресен регистър" (a central "Address Register" system) with a unique address identifier (УАИ), with the stated goal of "an open and free register of addresses". A community post of 10 May 2024 says the enabling law had not reached parliament, that the system cannot be built before the law passes, and that municipalities are the original source of address data.
- Postcodes: a draft document on the regulator's site (https://www.crc.bg/files/_bg/System_for_postal_codes.pdf , headed "ПРОЕКТ!") says the Communications Regulation Commission (КРС) maintains and publishes a postcode directory, and that the national postcode is a four-digit number.
- High-value-dataset status: no Bulgarian dataset of any HVD category is flagged in data.europa.eu.

### Not free or not available

- Open national address register: none found. Searched: the EU catalogue data.europa.eu, which harvests the national portal (search "адреси": 19 datasets, none an address register; HVD "Addresses" and "Geospatial" counts both 0). The national portal data.egov.bg itself could not be searched (HTTP 403).
- A single national download of the KAIS data: none; the tree's root lists only province folders.
- KAIS view services (WMS): paid. A community post of May 2024 quotes the tariff as 80 lv per layer per month or 800 lv per year; the tariff itself was not read.
- Postcode file from Bulgarian Posts: none on its postcode page.
- Overture Maps addresses (release 2026-10-21.0): no Bulgarian data.

### Could not be verified

- AGKK's reuse terms in AGKK's own words: only the community report of its reply was seen.
- The EPSG code of the KAIS files (EPSG:7801 was suggested): the `.prj` has no authority tag and no official statement was found.
- How many settlement folders a national harvest covers ("about 5,000" was estimated): the tree was not walked. National record counts were not computed either.
- Licence, formats and content of the НКНПА classifier, of the 2020 postcode list and of any AGKK entries on data.egov.bg: the portal returns HTTP 403 to page and API requests. This includes whether НКНПА is a street code list or geocoded points.
- Status of ЦАИС „Адресен регистър" in 2025 and 2026 (law passed or not, system built or not): one web search in Bulgarian found no law and no launch announcement.
- Whether Bulgaria publishes an INSPIRE Addresses dataset: the former EU INSPIRE Geoportal host serves an expired TLS certificate (record https://inspire-geoportal.ec.europa.eu/srv/api/records/5a796a38-d909-47c5-929e-704963cb604f unread), and `https://inspireportal.egov.bg/geonetwork/srv/api/search/records/_search` returns HTTP 403. The data.europa.eu search for "адреси" shows none.
- Whether КРС publishes its postcode directory today: one web search did not find it.

## Croatia (HR)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | DGU "Adrese - INSPIRE", from the Register of Spatial Units | Bulk GML zip from an ATOM feed, no registration | Otvorena dozvola (Croatian Open Licence); commercial use allowed | Yes, EPSG:3035 | Yes | Weekly |

**In short.** Use the weekly zip from the State Geodetic Administration (DGU): about 1.68 million house-number addresses with coordinates and postcodes, no login, under the Croatian Open Licence. The catch is the format. The download was found only as INSPIRE GML: one 2.6 GB XML file written as a single line, in EPSG:3035, with no CSV and no open WFS. Street, settlement and postcode come either from the linked component files or from one free-text string per address.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Adrese - INSPIRE, derived from the Registar prostornih jedinica (RPJ, Register of Spatial Units) | Državna geodetska uprava (DGU, State Geodetic Administration) | Zip: https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip ; address feed: https://geoportal.dgu.hr/services/atom/ad/xml ; service feed: https://geoportal.dgu.hr/services/atom/xml ; portal record: https://data.gov.hr/ckan/api/3/action/package_show?id=adrese-inspire ; metadata: https://geoportal.nipp.hr/geonetwork/srv/api/records/d3104048-688a-4305-9471-77288cc6e350/formatters/xml | 1,683,548 addresses (publisher's figure, from the file's `numberMatched` attribute), each with a point, a house number, and links to street, postal descriptor and two admin-unit names. Counted: 54,465 street names, 900 postal descriptors, 6,760 admin-unit names | Zip of 89,997,286 bytes, no login, no key. Four GML files, 2.68 GB unpacked; `Address.gml` alone is 2,614,426,484 bytes | Otvorena dozvola (OD), https://data.gov.hr/id/licence/otvorena-dozvola-rh | Weekly. The zip served on 2026-11-11 was generated on 2026-11-08 | confirmed (total address count not recounted) |
| Zagreb: Registar naziva ulica - adresna prostorna jedinica (street-name register) | Grad Zagreb, on data.gov.hr | https://data.gov.hr/ckan/api/3/action/package_search?q=registar+prostornih+jedinica&rows=10 | Street names only; file not opened | CSV and XLSX | Otvorena dozvola | Not checked | confirmed (listing only) |
| Rijeka: adrese po MO s ukupnim brojem stanova po adresi (addresses per local board with the number of flats) | Grad Rijeka, on data.gov.hr | https://data.gov.hr/ckan/api/3/action/package_search?q=adrese&rows=15 | Addresses per local board with flat counts; file not opened | XLS | CC BY 4.0 | Not checked | confirmed (listing only) |
| Preuzimanje podataka o poštanskim uredima (post office data downloads) | Hrvatska pošta (Croatian Post) | Page: https://www.posta.hr/preuzimanje-podataka-o-postanskim-uredima ; settlements: https://www.posta.hr/mjestaRh.aspx?vrsta=xml ; Zagreb streets: https://www.posta.hr/zagrebulice.aspx?vrsta=xml | Settlements with postcode (6,787 records: `brojPu` postcode, `nazivPu` post office, `naselje` settlement, `zupanija` county); Zagreb streets with delivery post office (5,378 rows, some with house-number ranges); post offices; parcel lockers | Excel and XML, no login | None stated on the page | Not stated | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Croatia | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Croatian countrywide source | OpenAddresses | Source file: https://github.com/openaddresses/openaddresses/blob/master/sources/hr/countrywide.json ; downloads: https://batch.openaddresses.io | The same DGU zip, parsed from the one-string address field with regular expressions | Free download; needs a logged-in account | Recorded there as "no limitations to public access" | Marked weekly; source added 2024-04-25 | confirmed |
| Overture Maps addresses | Overture Maps | No link recorded | Croatia is among the 19 EU countries covered | GeoParquet, no account | Set per country; Croatia's not recorded | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- INSPIRE WMS, view only, anonymous: https://geoportal.dgu.hr/services/inspire/ad/wms?service=WMS&version=1.3.0&request=GetCapabilities . Layers `AD.Address` and `AD.Address.Default`.
- A second WMS, listed as "registrirani korisnici" (registered users): `https://geoportal.dgu.hr/services/auth/inspire/ad/wms`. It answered GetCapabilities without credentials.
- No open WFS. https://geoportal.dgu.hr/services/inspire/ad/wfs?service=WFS&version=2.0.0&request=GetCapabilities answers with the exception "Service WFS is disabled". So does `/services/auth/inspire/ad/wfs`.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.

### Caveats and recent changes

- Format: INSPIRE Addresses GML 3.2.1 (schema `ad/4.0`), a WFS 2.0 FeatureCollection saved as a single line of XML. It must be stream-parsed. The root element says `numberMatched="1683548"` but also `numberReturned="10000"` with a `next` link: the file is built from 10,000-record WFS pages.
- Coordinates are ETRS89/LAEA, EPSG:3035, and need reprojecting for most uses.
- Reading an address: each record has a house number (`LocatorDesignator`, type `addressNumber`), `validFrom`, `beginLifespanVersion` and four component links. The identifier is a `localId` such as `KB.0000000135` in namespace `HR.DGU.RPJ`. `ad:alternativeIdentifier` holds the whole address as one string, for example "Brežna ulica 33 Andraševec 49243 Oroslavje" (street, number, settlement, 5-digit postcode, post town).
- What the point marks is not stated. `ad:specification` and `ad:method` are nil ("unpopulated") in all 9,030 records sampled, so the file does not say whether a point is on the building, the entrance or the parcel.
- Text is Latin script with Croatian diacritics, UTF-8.
- Licence terms, read in the official gazette NN 67/2017 (https://narodne-novine.nn.hr/clanci/sluzbeni/2017_07_67_1577.html): the Open Licence allows commercial and non-commercial use, free of charge, without limit in space or time. The user must name or link the source and give the date of last change. A ban on commercial use cannot be added. The licence page itself, https://data.gov.hr/otvorena-dozvola , is JavaScript-only.
- Contradictory label: the metadata, both ATOM feeds (`rights`) and the WMS (`AccessConstraints`) also carry "ograničenje javnog pristupa prema članku 13 stavku 1 točki (e) INSPIRE Direktive" (a limit on public access under Article 13(1)(e) of the INSPIRE Directive). The portal record, the metadata's use constraint and the WMS `Fees` element all state the Open Licence, and the file downloads anonymously.
- No charge: NN 39/22, Article 1(3) (https://narodne-novine.nn.hr/clanci/sluzbeni/2022_03_39_477.html) says real costs are not charged for access through network services or other electronic access points. Paragraph (4) says data issued in other ways are charged.
- The portal record is new. `adrese-inspire` was created on 2026-10-14 and modified on 2026-10-22. The older address https://data.gov.hr/ckan/en/dataset/adrese returns HTTP 404. The record also carries a stale `temporal_end` of 2019-12-05.
- The ATOM feed's `length` attribute (84,406,413) does not match the served file (89,997,286 bytes). Do not validate the download against it.
- High-value-dataset status: the record is flagged as an HVD in category "Addresses" (`http://data.europa.eu/bna/c_c3de25e4`) under Regulation (EU) 2023/138. On data.europa.eu it is the only Croatian dataset in that category.
- Hrvatska pošta files carry no licence or reuse terms. An OpenStreetMap mailing-list post quotes a 2014 e-mail from Hrvatska pošta giving the OSM community permission (https://lists.openstreetmap.org/pipermail/talk-hr/2015-January/002317.html). That is not a published licence.
- Hrvatska pošta's Zagreb street list gives ranges, for example "ALEJA GRADA BOLONJE 2 - 68" with post office "10090 ZAGREB-SUSEDGRAD".

### Not free or not available

- A download in another format (CSV, GeoPackage) or split by region: none found. The zip holds four GML files. Looked at: the ATOM feed and the portal record only.
- Working address WFS: by agreement only. "Adrese - WFS INSPIRE (sporazum)", `https://geoportal.dgu.hr/services/sla/inspire/wfs_ad/wfs?authKey=…`, is open to public-law bodies with special user status that sign a data-use protocol with DGU (https://registri.nipp.hr/api/izvori/452/pdf/).

### Could not be verified

- That every address is at locator level `siteLevel` (one record per house number, no entrance or dwelling level): true for the first 9,030 records; the whole file was not read.
- Whether DGU offers a free geocoding or address-autocomplete API: one web search with Croatian keywords found none. The geoportal's own search box was not tested.
- Whether the RPJ source data are offered in another form, such as a SOAP service: the document said to mention it, https://www.bib.irb.hr:8443/1091653/download/1091653.HKOIG-Zbornik-radova-2019-web-81-86.pdf , returns HTTP 403.
- Whether the 900 postal descriptors cover every delivery postcode: not compared with Hrvatska pošta's 6,787-row list.
- Content of the Zagreb and Rijeka city files: not opened.

## Cyprus (CY)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| No | Substitute: Cyprus Post street-to-postcode directory; no house numbers, no coordinates | Bulk CSV, no registration | CC BY 4.0 | No; the official street points cover 4% (EPSG:4258) | Yes, per street | Stated annual; newest CSV is September 2021 |

**In short.** No open dataset with house numbers was found. The official INSPIRE address service of the Department of Lands and Surveys is open (CC BY 4.0, WFS and REST, no key), but it holds 80,934 points covering 4% of the country and every house-number field is empty. The realistic substitute is Cyprus Post's street-to-postcode table: 32,819 rows, Greek and Latin street names, CC BY 4.0, no login. It has no coordinates and no single house numbers, and its two street-name column labels are swapped.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Διευθύνσεις - Addresses (INSPIRE) | Τμήμα Κτηματολογίου και Χωρομετρίας (Department of Lands and Surveys, DLS) | Dataset page: https://data.gov.cy/en/dataset/543 ; REST: https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer ; WFS: https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/exts/InspireFeatureDownload/service?VERSION=2.0.0&SERVICE=WFS&REQUEST=GetCapabilities ; WMS: https://eservices.dls.moi.gov.cy/inspire/services/INSPIRE/AD_Addresses/MapServer/WMSServer?request=GetCapabilities&service=WMS | 80,934 address points placed on parcels. Street names in Latin capitals. No house numbers, no postcode. The publisher says the data cover 4% of Cyprus | WFS 2.0, ArcGIS REST (JSON and GeoJSON, 1,000 records per query), WMS; no key | CC BY 4.0. The WFS states fees "no conditions apply" and access constraints "None" | Released 15/01/2018, modified 16/03/2026, frequency "Irregularly"; the data refer to 12/11/2015 | confirmed; WMS address corrected |
| Ταχυδρομικός Κώδικας ανά Δρόμο σε Αστικές και Αγροτικές Περιοχές (postcode per street, urban and rural areas) | Τμήμα Ταχυδρομικών Υπηρεσιών (Department of Postal Services, Cyprus Post) | Dataset page: https://data.gov.cy/en/dataset/1037 ; latest CSV: https://data.gov.cy/en/resource/3104/download/file | 32,819 rows, 1,117 distinct 4-digit postcodes (both counted from the file). Street name in Greek and Latin, street limit "FROM - TO", postcode, municipality or community, district, serving post office | CSV of 6,880,847 bytes, no login. Three editions: August 2019, July 2020, September 2021 | CC BY 4.0 | Page modified 16/01/2024; stated frequency "Annually"; newest edition September 2021 | confirmed |
| Οδηγός Ταχυδρομικού Κώδικα - Post Code Directory | Cyprus Post | https://data.gov.cy/en/dataset/385 | Postcode directory as XLSX (3,263,480 bytes); content not parsed | XLSX download answers without login | CC BY 4.0 | Modified 18/09/2024; frequency "Annually"; temporal coverage 01/01/2024 | confirmed (file not opened) |
| Ταχυδρομικοί Κώδικες ανά Δήμο/Κοινότητα και Επαρχία (postcodes per municipality or community and district) | Cyprus Post | https://data.gov.cy/en/dataset/1134 | Postcodes per municipality or community and district (CSV, 74,463 bytes), plus an XLSX mapping to LAU codes (2021) | File downloads | CC BY 4.0 | Modified 16/01/2024 | confirmed |
| ΑΡΙ Κυπριακών Ταχυδρομείων για Ταχυδρομικούς Κώδικες (Cyprus Post postcode API) | Cyprus Post | Dataset page: https://data.gov.cy/en/dataset/1061 ; resource: https://data.gov.cy/el/resource/cyprus-postal-codes-api ; documentation: https://documenter.getpostman.com/view/6477303/RztmtUjG?version=latest | Postcode search API | Registration required, requested through a contact form; not called | CC BY 4.0 | Frequency "Continuously"; page modified 16/01/2024 | confirmed (listing only) |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Cyprus | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Cyprus source | OpenAddresses | Source file: https://github.com/openaddresses/openaddresses/blob/master/sources/cy/countrywide.json ; downloads: https://batch.openaddresses.io | The DLS points: street name and point only, no house numbers, about 4% coverage | Free download; needs a logged-in account | Not checked | Source added 2026-09-29 in a single commit | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- DLS ArcGIS REST service, https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer?f=json : ArcGIS 10.91, one point layer "Addresses" plus 13 INSPIRE tables, EPSG:4258 (ETRS89 geographic), capabilities "Map,Query,Data", formats JSON and GeoJSON, at most 1,000 records per query, no key.
- DLS INSPIRE WFS 2.0, https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/exts/InspireFeatureDownload/service?VERSION=2.0.0&SERVICE=WFS&REQUEST=GetCapabilities : feature type `ad:Address`, default CRS EPSG:4258. Only the capabilities document was requested.
- DLS WMS 1.3.0 (view only), https://eservices.dls.moi.gov.cy/inspire/services/INSPIRE/AD_Addresses/MapServer/WMSServer?request=GetCapabilities&service=WMS .
- Cyprus Post postcode API: needs registration through a contact form; documentation at https://documenter.getpostman.com/view/6477303/RztmtUjG?version=latest .
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.

### Caveats and recent changes

- DLS house numbers are absent. The locator table has 80,934 rows of type `addressNumber`, and none has a value. The component table is empty, so there is no postcode either.
- DLS coverage: the service extent is 32.3378 to 34.0672°E and 34.6370 to 35.2003°N. Positions are parcel-based (`specification: parcel`, `method: byAdministrator`). Identifiers are `AD.<n>` in namespace `CY.0001-DLS.AD` with status "current"; they sit in table 8 (`adAddress`), not in layer 0. `validFrom` and `beginLifespanVersion` are void.
- DLS WMS address: the WMS link printed on data.gov.cy (https://data.gov.cy/en/resource/1504) returns an HTML page, not WMS capabilities. Use the address given above, which has no `/rest` in its path.
- Cyprus Post CSV, swapped labels: the column whose name ends in `_EN` holds the Greek street name and the one ending in `_GR` holds the Latin one. There is also a serial-number column `SN`.
- Cyprus Post CSV, house numbers: one row normally means a whole street in one community. Only 857 rows carry a street limit; 839 of them contain digits and 18 hold text only. Example: the Limassol street "1ης Απριλίου" / "1 Apriliou" is split as "1 - 39, 2 - 18" for postcode 3116 and "41 - τ. 20 - τ." for 3117.
- Cyprus Post CSV, age: the page says "Annually", but the newest per-street edition is September 2021. Two older datasets (urban only, rural only) are marked "ΑΝΕΝΕΡΓΟ" (inactive).
- The Post Code Directory dataset has a second resource, a website link, that answers HTTP 403.
- High-value-dataset status: the national portal tags the DLS dataset "High Value Data". The EU catalogue does not: the record has `is_hvd: false` (https://data.europa.eu/api/hub/search/datasets/585d9407-05d2-4348-a9d6-0d0191d2dcdb), and no Cypriot dataset of any HVD category is flagged there. The national HVD page (https://data.gov.cy/en/high-value-datasets-hvds) gives the legal basis as Law 143(I)/2021, Article 21, with the harmonisation period ending June 2024.
- OpenAddresses added Cyprus on 2026-09-29 with the note "Current source data contains no house numbers … only street name and point geometry are populated. Coverage is also partial, about 4% of Cyprus per the publisher."

### Not free or not available

- National address register with house numbers: none found. Searched: data.gov.cy for "διευθύνσεις" (3 datasets, only the DLS one is about addresses) and the EU catalogue data.europa.eu (HVD "Addresses" and "Geospatial" counts for Cyprus are both 0). No project to build a register was found in the same searches.
- Cyprus Post postcode API: not open without registration.
- Overture Maps addresses (release 2026-10-21.0): no Cyprus data.

### Could not be verified

- Cyprus Post API: its behaviour, rate limits, and whether registration is free. It needs registration and was not called.
- Whether the 2024 Post Code Directory XLSX holds the same per-street content as the 2021 CSV: the file was not parsed.
- Whether a full download through the DLS WFS works: no GetFeature request was made.
- Whether the DLS points cover the areas not under government control: not examined. The Cyprus Post CSV does have rows for the districts Ammochostos (1,494) and Keryneia (58).

## Czechia (CZ)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | RÚIAN address-point CSV (ČÚZK) | Bulk CSV zip, no registration | CC BY 4.0 | Yes, S-JTSK (EPSG:5513) | Yes | Monthly; change files daily |

**In short.** Use the national address-point CSV of RÚIAN (*Registr územní identifikace, adres a nemovitostí*, Registry of Territorial Identification, Addresses and Real Estate) from the cadastral office ČÚZK: one 63 MB zip a month, no login, CC BY 4.0, every address with postcode and coordinates. The file name carries the date of the last day of the previous month, so the URL changes monthly; the ATOM feed gives the current one. Most likely to trip an import: the CSV is Windows-1250, not UTF-8, and its coordinates are positive S-JTSK Y/X values (labelled EPSG:5513), while ČÚZK's ArcGIS services return negative values in EPSG:5514. ČÚZK's human download page is behind a bot check, so automate against the file URL or the feed.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| RÚIAN address points, national CSV | Český úřad zeměměřický a katastrální (ČÚZK) | https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_OB_ADR_csv.zip | 6,258 CSV files, one per municipality, 354.7 MB uncompressed. 19 columns: address-point code, municipality, city district, Prague district, municipality part, street, building type (č.p. / č.ev.), house number, orientation number and letter, postcode (PSČ), Y, X, valid-from date. 3,023,585 rows at 31 Oct 2026 (researcher's count, not recounted) | Anonymous download, 63,371,330 bytes | CC BY 4.0 (dataset's metadata record) | Monthly; file last modified 1 Nov 2026 | confirmed |
| ATOM feed for that CSV | ČÚZK | https://atom.cuzk.gov.cz/RUIAN-CSV-ADR-ST/RUIAN-CSV-ADR-ST.xml | Feed entry for the one national file; describes the service as public and free of charge | Anonymous | Feed says "žádné podmínky neplatí" (no conditions apply) | Feed updated 2026-11-01 | confirmed |
| Address hierarchy file | ČÚZK | https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_strukt_ADR.csv.zip | Seven CSV files linking each address point to street, municipality part, municipality, district, region and other units. Codes only: no names, coordinates or postcodes | Anonymous download, 34,233,458 bytes | Not recorded for this file | File last modified 1 Nov 2026 | confirmed |
| Full register in the VFR exchange format (GML 3.2) | ČÚZK | https://services.cuzk.gov.cz/vfr/ (monthly directories `https://services.cuzk.gov.cz/vfr/<YYYYMM>/`); request form at https://vdp.cuzk.gov.cz/vdp/ruian/vymennyformat | All RÚIAN elements: addresses, buildings, parcels, streets, boundaries. Each monthly directory has 6,258 per-municipality files and state files, for example `20260903_ST_UADS.xml.zip` (addresses, 87.0 MB) and `20260930_ST_UKSH.xml.zip` (34.1 MB). Monthly state files go back to August 2015 | Anonymous download; the form also offers increments since a date | CC BY 4.0 (ČÚZK conditions for open spatial data) | Monthly state files; newest directory 202609 on 11 Nov 2026 | corrected |
| INSPIRE theme Addresses (AD) | ČÚZK | ATOM https://atom.cuzk.gov.cz/AD/AD.xml ; WFS https://services.cuzk.gov.cz/wfs/inspire-AD-wfs.asp | Addresses in the INSPIRE model. The only Czech dataset in the high-value category "Addresses" on data.europa.eu | Listed as public and free; the two endpoints were not requested | Not recorded | Catalogue record says files are created daily | confirmed (catalogue record only) |
| Postcode lists ("zákaznické výstupy", customer outputs) | Česká pošta | Page https://www.ceskaposta.cz/ke-stazeni/zakaznicke-vystupy ; files https://www.ceskaposta.cz/documents/d/guest/db_pcobc-zip?download=true and https://www.ceskaposta.cz/documents/d/guest/csv_psc_a-zip?download=true ; third file `csv_cobce_psc-zip` linked from the page | `zv_pcobc.csv`: 16,152 rows, municipality part to postcode, delivering post office and district. `zv_psc_adr.csv`: 20,135 rows, postcode and type. `zv_cobce_psc.csv`: 16,205 rows, with RÚIAN codes of municipality part and municipality. No streets, house numbers or coordinates | Anonymous download, zipped CSV | None stated | Monthly, first working day; files dated 1 Nov 2026 | confirmed |
| Register of census districts and buildings (RSO) | Český statistický úřad (ČSÚ) | https://csu.gov.cz/rso/registr_scitacich_obvodu | Page exists; content and downloads not examined | Not examined | Not recorded | Not recorded | confirmed (page exists only) |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Czechia | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/cz/countrywide.json) | RÚIAN address points, countrywide, from a copy cached by OpenAddresses; the source page it names is the export of 31 Aug 2024 | Free download, needs a logged-in account | CC-BY 4.0, attribution "ČÚZK" | Processed 2026-10-30 from the cached copy | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 3,021,471 Czech addresses in release 2026-10-21.0 (publisher's figure) | GeoParquet, no account | ČÚZK, CC BY 4.0 | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **ArcGIS REST service over RÚIAN, no key:** https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/Vyhledavaci_sluzba_nad_daty_RUIAN/MapServer . Layers include 1 `AdresniMisto` (address points), 2 and 3 building objects, 4 `Ulice` (streets), 5 `Parcela` (parcels). Capabilities "Map,Query,Data", `maxRecordCount` 1,000,000, spatial reference wkid 102067 (EPSG:5514). The address layer counted 3,024,015 points on 11 Nov 2026.
- **Geocoder on the same service, no key:** `.../MapServer/exts/GeocodeSOE/findAddressCandidates`, for example https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/Vyhledavaci_sluzba_nad_daty_RUIAN/MapServer/exts/GeocodeSOE/findAddressCandidates?SingleLine=Pod+s%C3%ADdli%C5%A1t%C4%9Bm+1800%2F9+Praha&f=json . The test returned one candidate with score 100, postcode and coordinates x -739810.37, y -1039209.69.
- **WMS:** the same MapServer lists a `WMSServer` extension.
- **INSPIRE Addresses WFS:** https://services.cuzk.gov.cz/wfs/inspire-AD-wfs.asp , listed in the catalogue as public and free; not requested.
- **Map-based file picker:** https://ags.cuzk.gov.cz/geoprohlizec/?atom=ruian , linked from the CSV's metadata record; not opened.
- **Address verification form:** the public access application VDP (*Veřejný dálkový přístup*) at https://vdp.cuzk.gov.cz has an "Ověření adresy" web form. It is a form, not an API.
- **Other official REST or JSON API for RÚIAN:** none found on the ČÚZK pages read.
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- The CSV file name is `YYYYMMDD_OB_ADR_csv.zip`, dated the last day of the previous month; the file is created on the first day of each month. Only the October 2026 URL was requested.
- The CSV is Windows-1250 and semicolon-separated. A row looks like `4192575;500011;Želechovice nad Dřevnicí;;;;;195901;…;č.p.;1;;;76311;515561.05;1166540.03;2014-02-12T00:00:00`.
- Coordinates in the CSV are S-JTSK with positive Y and X; the ATOM feed labels them EPSG:5513. The ArcGIS service and geocoder return negative values in EPSG:5514.
- Many addresses have no street: villages use only a house number of type "č.p." or "č.ev.".
- Postcodes in RÚIAN are maintained by ČÚZK from Česká pošta data.
- Licence statements differ by place. The CSV's metadata record says CC BY 4.0, open data, "no limitations to public access" (https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng). The ATOM feed for the same file says no conditions apply. ČÚZK's conditions page (https://cuzk.gov.cz/Predpisy/Podminky-poskytovani-prostor-dat-a-sitovych-sluzeb/Podminky-poskytovani-prostorovych-dat-CUZK.aspx , last updated 30.06.2023) gives CC BY 4.0 for RÚIAN in the exchange format, allows commercial and non-commercial use, and asks for the credit "ČÚZK, [year]".
- The human download page https://nahlizenidokn.cuzk.gov.cz/StahniAdresniMistaRUIAN.aspx sits behind a bot-manager challenge: a plain client gets a 303 or 302 redirect, not the page.
- Old `vdp.cuzk.cz` addresses redirect (302) to `vdp.cuzk.gov.cz`.
- Inside the zip the files are named `CSV/20261031_OB_<municipality code>_ADR.csv`.
- Announced on 16.9.2026: from 1.1.2027 senate electoral districts enter RÚIAN, with a new special VFR file `ST_UVOH` (first file 4.1.2027). Announced on 20.3.2026: all monthly state VFR files since August 2015 are at https://services.cuzk.gov.cz/vfr .
- RÚIAN software releases in 2026 with downtime: 4.3 on 26-27 June, 4.3.2 on 23 July, 4.3.4 on 15 October (VDP down 16:30-20:00).
- High-value datasets: data.europa.eu lists 249 Czech datasets with the high-value flag, one of them in the category "Addresses" (ČÚZK's INSPIRE theme Addresses). The record of the monthly CSV does not carry the flag.
- OpenAddresses does not read the live monthly file; it processes its own cached upload.

### Not free or not available

- **Česká pošta postcode files:** free to download, but they carry no licence or terms. The "certificate" document that accompanies each file is a data dictionary, not a licence. They hold no addresses.

### Could not be verified

- The CSV's exact row counts (3,023,585 rows; 3,022,681 with coordinates and 904 without; none without a postcode): recounting needs the whole file, which was not downloaded for the check. The live ArcGIS count of 3,024,015 on 11 Nov 2026 is consistent with them.
- The content of ČÚZK's human download page: the bot-manager challenge was not passed.
- URLs of the daily change files: not checked.
- Per-municipality RÚIAN address sets in CSV and SHP listed on data.europa.eu ("Data RÚIAN o adresách poskytovaná po obcích ve formátu CSV", "Vybraná data RÚIAN poskytovaná po obcích ve formátu SHP"): the records were seen, the endpoints were not requested.
- The date of the copy OpenAddresses holds: the 31 Aug 2024 file name appears only in its "website" field.
- Usage limits or terms for the ArcGIS services: none were found in a first search, and the search was not repeated.
- Content and download options of the ČSÚ census-district and building register.
- Web services reserved for public authorities and third-party APIs built on RÚIAN: they surfaced in searches and were not examined.

## Denmark (DK)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Danmarks Adresseregister (DAR) on Datafordeleren | Bulk JSON/CSV with free account and API key; INSPIRE API keyless | CC BY 4.0 | Yes, EPSG:25832 (not confirmed for the bulk files) | Yes | Full files weekly, deltas daily |

**In short.** Use the file download of Danmarks Adresseregister (DAR, the Danish Address Register) on Datafordeleren (the Danish Data Distributor): it is free and CC BY 4.0, but it needs a free account and an API key or OAuth credential. For access with no account at all, the INSPIRE address API on api.dataforsyningen.dk answered without a token on 2026-11-11, but how current its data is was not established. The trap: DAWA, the keyless API that older code and guides point to, closed on 1 October 2026 and now answers HTTP 410.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| DAR file download ("Fildownload") on Datafordeleren | Klimadatastyrelsen (KDS, Danish Agency for Climate Data) | Documentation: https://confluence.kds.dk/pages/viewpage.action?pageId=148452334 ; register overview: https://datafordeler.dk/dataoversigt/danmarks-adresseregister-dar/ ; URL pattern: `https://api.datafordeler.dk/FileDownloads/GetFile?Register=DAR&LatestTotalForEntity=Husnummer&type=current&format=JSON&apikey=...` | The authoritative register of road names and addresses with postcode and supplementary town name. About 3.8 million addresses and about 110,000 road names (publisher's figure). Nine entities: Adresse, Adressepunkt, Husnummer, NavngivenVej, NavngivenVejKommunedel, NavngivenVejPostnummer, NavngivenVejSupplerendeBynavn, Postnummer, SupplerendeBynavn | Free account (e-mail or MitID), then an "IT-system" with an API key or OAuth. Without a key the service answers HTTP 401. Total and delta downloads, JSON and CSV, also per municipality | CC BY 4.0, credit Klimadatastyrelsen | Total files weekly (night to Saturday, 03:00-06:00, kept 7 days); delta files daily (03:00-06:00, kept 14 days) | confirmed |
| INSPIRE Addresses, OGC API Features `ad_inspire` | Klimadatastyrelsen, on Dataforsyningen | https://api.dataforsyningen.dk/ogcapi/features/ad_inspire ; items: https://api.dataforsyningen.dk/ogcapi/features/ad_inspire/collections/address/items?limit=1 | 2,616,159 access-level address features (count returned by the service on 2026-11-11). Collections: address, addressareaname, administrativeboundary, adminunitname, postaldescriptor, thoroughfarename. Storage CRS EPSG:25832, output CRS84 | No token, no account. GeoJSON | CC BY 4.0 (per the data.europa.eu record "INSPIRE - Adresser") | Not established. One sample feature had `validfrom` 2025-08-14 | corrected |
| INSPIRE ATOM feed "DK INSPIRE Addresses" | SDFE (KDS's former name) | https://www2.sdfe.dk/INSPIRE/feeds/Addresses.xml | One GeoPackage link, declared length 4,291,699 bytes | No key | CC BY 4.0 | Stale: feed updated 2020-12-24. Not a current source | corrected |
| Postcodes in DAR and DAGI | Postcodes are set by Trafikstyrelsen (the transport authority); the postcode map is part of KDS's DAGI dataset (Danmarks Administrative Geografiske Inddeling, the administrative divisions) | https://danmarksadresser.dk/om-adresser/postnumre | DAR carries a Postnummer entity and links each house number to its postcode. The postcode map is in DAGI, which has its own entity-based file download on Datafordeleren since 28 April 2025 | Datafordeleren file download, which requires authentication | The Address Act requires postcode information to be available digitally free of charge | Not stated | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Denmark | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Denmark countrywide | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/dk/countrywide.json | A cached copy of DAR, "sourced from Datafordeler DAR GraphQL API", EPSG:25832 | Free download, needs a logged-in account | CC BY 4.0, attribution Klimadatastyrelsen | Cached upload dated 2026-03-27 | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Denmark is among the 19 EU countries covered | No account, GeoParquet | Per country | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **INSPIRE Addresses OGC API** (https://api.dataforsyningen.dk/ogcapi/features/ad_inspire): the only Danish address service found that answers with no token. See the table above.
- **Datafordeler GraphQL and WMS for DAR**: GraphQL includes entity-based events and flexible lookup logic. Needs the same free account and API key or OAuth as the file download. Documentation index: https://confluence.kds.dk/pages/viewpage.action?pageId=10616849 ; account set-up: https://datafordeler.dk/vejledning/brugeradgang/
- **Adressevælger** (the autocomplete service that replaces DAWA Autocomplete): `https://adressevaelger.dk/husnumre/soeg?tekst=...&token=...` and `https://adressevaelger.dk/adresser/soeg?tekst=...&token=...`. A `token` parameter of at least 10 arbitrary characters is mandatory; there is no user management yet, and KDS recommends that everyone uses the token `adressevaelger123`. KDS states: no rate limit, no reverse geocoding, returns DAR UUIDs, data refreshed once a day, delivered as an API endpoint plus a JavaScript GUI component, responses not 1:1 with DAWA. Documentation: https://confluence.kds.dk/pages/viewpage.action?pageId=244318431 , https://confluence.kds.dk/display/ADV/FAQ , https://confluence.kds.dk/display/ADV/Brugerstyring . This is confirmed from the documentation only; the live service was not called.
- **Adressevask** (address cleansing, replaces DAWA "datavask"): `https://adressevaelger.dk/vask/?token=...&adresse=...`. Documentation: https://confluence.kds.dk/display/ADV/Adressevask
- **GSearch** (Dataforsyningen REST search over DAR, DAGI, cadastre and place names), base `https://api.dataforsyningen.dk/rest/gsearch/v2.0/`: needs a Dataforsyningen token. Without one, https://api.dataforsyningen.dk/rest/gsearch/v2.0/husnummer?q=Rentemestervej%208 answers HTTP 400 "Authentication token must only be lowercase (token) or uppercase (TOKEN)!".
- **Bifrost** (search in addresses, road names, property data, place names and DAGI divisions): not in production yet. Expected "ultimo Q4" (no year printed; page updated October 2026); production start is tied to Dataforsyningen's move to a new platform. Page: https://confluence.kds.dk/display/Bifrost/Bifrost
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.

### Caveats and recent changes

- **DAWA is closed.** "DAWA er lukket den 1. oktober 2026" (https://dataforsyningen.dk/data/4924). All DAWA web services and the old address WFS services stopped that day. https://api.dataforsyningen.dk/adresser and https://dawa.aws.dk/adresser answer HTTP 410 "The requested resource is no longer available and will not be available again." https://dawadocs.dataforsyningen.dk/ redirects to the closure page. The closure date of 1 October 2026 is given in news item https://dataforsyningen.dk/news/5117 (first published 16 December 2025, updated 12 June 2026).
- DAWA also carried DAGI (postcodes, parishes and more), GeoDanmark buildings, the cadastre and place names; all of these services closed with it. Earlier removals from DAWA: BBR building data 3 April 2024, zone data 11 September 2024, the DAWA WMS 14 January 2025, large-recipient postcodes 28 February 2025.
- The replacement for DAWA replication is the entity-based file download on Datafordeleren, offered since 28 April 2025 for DAR, the cadastre, GeoDanmark, DAGI and place names.
- Full files are generated only once a week. A daily-current copy needs the weekly total plus the daily deltas; deltas are kept 14 days, totals 7 days.
- The file download comes in three flavours: `current`, `temporal` and `bitemporal` (full history). Identifiers are `id_lokalId` keys (DAR UUIDs). Husnummer is the access address (house number, link to road, municipality, parish, postcode, supplementary town name, building); Adresse is the unit level (floor and door); Adressepunkt holds the position and a "teknisk standard" field describing how the point was placed.
- **Legacy Datafordeler interfaces are ending.** REST, Hændelser (events), Filudtræk (FTP extracts) and their schemas for DAR are marked "udfases 15. januar 2027". For access with a web user or service user the official pages disagree: end of 2026 on https://datafordeler.dk/vejledning/brugeradgang/ , 15 January 2027 in the KDS documentation (https://confluence.kds.dk/pages/viewpage.action?pageId=151999753, the later page). New integrations should use an API key or OAuth.
- The modernised Datafordeler went live on 4 December (year not printed; KDS news of 26 February 2026, https://www.klimadatastyrelsen.dk/om-klimadatastyrelsen/nyheder/nyhedsarkiv/2026/feb/newspage).
- **Dataforsyningen moves to a new hosting platform on 30 November 2026** (postponed from 2 November). Service window: 26 November 16:00 to 30 November 08:00 (https://dataforsyningen.dk/news/5199). The keyless INSPIRE API and GSearch are served from api.dataforsyningen.dk.
- The INSPIRE API holds access-level addresses (2,616,159 features). It is not the full DAR model with unit-level addresses and history, and its currency is not established.
- Adressevælger cannot be self-hosted, unlike DAWA. Real user management is expected "ultimo 2026 eller primo 2027", so the shared placeholder token is temporary.
- Quality, from the official metadata record "Danmarks adresser og vejnavne" (geodata-info.dk, record id 99c7068b-d6e8-4090-add7-b7c6f7562927, dated 2026-11-10): completeness above 99 %; about 0.02 % of address points are placed approximately at the centre of the cadastral parcel, the rest are placed by hand by the municipal address authorities. Address data has been free since 2013. The record gives EPSG:25832 as the reference system.
- Licence terms: "Vilkår for brug af Danmarks Adresseregister (DAR) - (16.05.2024)", CC BY 4.0, "Du skal kreditere Klimadatastyrelsen på et passende sted" (https://datafordeler.dk/vejledning/brugervilkaar/danmarks-adresseregister-dar/). Datafordeleren and the registers may change the terms at any time, with e-mail notice to registered users (https://datafordeler.dk/vejledning/brugervilkaar/).
- High-value datasets: https://datafordeler.dk/vejledning/inspire/ states that all INSPIRE datasets on Datafordeleren are covered by the HVD rules and that DAR is free through GraphQL, WFS and bulk download. On data.europa.eu the two records ("Danmarks adresser og vejnavne" and "INSPIRE - Adresser", publisher Klimadatastyrelsen) both show `is_hvd: false`.
- The Address Act requires address data to be available without payment (https://confluence.kds.dk/pages/viewpage.action?pageId=10616849). Addresses and road names are set by the municipal address authorities; KDS runs the system and the distribution.
- The documentation page for the DAR file download carries two dates: its info box says changed 18 March 2026, the Confluence stamp says last modified 27 July 2026.
- The OpenAddresses copy is a single cached upload dated 2026-03-27, not a live harvest.

### Not free or not available

- DAWA and everything on dawa.aws.dk and dawadocs.dataforsyningen.dk: closed for good.
- Anonymous bulk download of the full DAR: not available. Datafordeleren's file download requires authentication.
- Self-hosting of the autocomplete service: not possible for Adressevælger.
- Reverse geocoding: not offered by Adressevælger.
- Large-recipient postcodes ("stormodtagerpostnumre"): phased out by Trafikstyrelsen on 1 January 2025.
- No paid address product was found; the register is free by law.

### Could not be verified

- The live behaviour of adressevaelger.dk: no test request to it went through. Everything stated about it comes from KDS documentation.
- The coordinate reference system and the file sizes of the DAR file downloads: these need a login. EPSG:25832 was seen only in the official metadata record and in the INSPIRE service.
- How current the data in the keyless INSPIRE API is.
- The listing text of the Dataforsyningen product page "INSPIRE - Adresser" (https://dataforsyningen.dk/data/3937): the page is a JavaScript shell and was not re-read.
- An earlier closure notice for DAWA with the date 1 July 2026: not re-found. Only the 1 October 2026 date is established.
- A service-catalogue line saying the Datafordeler DAR REST service ends on 30 June 2026: the catalogue record was not re-read. The KDS news of 26 February 2026 confirms that a 30 June 2026 plan was moved to the end of 2026, and the KDS documentation now says 15 January 2027.

## Estonia (EE)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Aadressiandmete süsteem (ADS) extracts, Maa- ja Ruumiamet | Bulk CSV, no registration; keyless search API | Open data, no licence agreement; credit the Board | Yes, L-EST97 (EPSG:3301) | Yes | Monthly |

**In short.** Use the monthly CSV extracts of the Aadressiandmete süsteem (ADS, the Estonian Address Data System) from Maa- ja Ruumiamet (the Estonian Land and Spatial Development Board). The simplest is one keyless zip of all valid addresses with postcode and coordinates; lookups go to a keyless search API. The trap is that everything is moving host in 2026: ADS is being folded into the new Aadresside ja kohanimede süsteem (AKS, Addresses and Place Names System), the search API In-ADS is replaced by In-AKS, and the old host `inaadress.maaamet.ee` is announced to close towards the end of 2026.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| ADS monthly extracts (now in the AKS application) | Maa- ja Ruumiamet (the former Maa-amet, Land Board) | Extracts page: https://aks.geoportaal.ee/aks/valjavotted ; description: https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html ; SFTP server `aksfailid.maaruum.ee`, port 22 | Complete extracts of all ADS data. About 2.4 million address objects (publisher's figures): cadastral parcels ~772,000, residential buildings ~305,000, non-residential buildings ~679,000, dwellings and flats ~559,000, other building parts ~68,000. Extract no. 9 "Addresses with components and history" has ADR_ID, code address, full address, proximate address, status (K valid; V and T invalid), valid-from and valid-to, reference point X/Y, and code and name for eight component levels. A readme.pdf in English is in the extracts folder | No account. The extracts page is a JavaScript application. The SFTP server uses the username `public` and a password printed on the official page; "The access is limited for foreign IP addresses" | "ADS data is open data, so there is no license agreement"; name the Estonian Land and Spatial Development Board as the provider | Monthly: full extracts at the beginning of every month, "once in every 30 days" | confirmed |
| Addresses with postcodes, "Sihtnumbrid" | Maa- ja Ruumiamet | File: https://geoportaal.maaruum.ee/docs/aadress/sihtnumbrid.zip ; page: https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed/aadressid-ja-posti-sihtnumbrid-p582.html | CSV of valid address versions only: ADR_ID, SIHTNUMBER (postcode), LAHIAADRESS (proximate address), TAISAADRESS (full address), VIITEPUNKT_X, VIITEPUNKT_Y (reference point). 29,591,636 bytes zipped on 2026-11-11 | Direct download, HTTP 200, no login | Same as above | On the 5th of each month | confirmed |
| INSPIRE Addresses WFS | Maa- ja Ruumiamet | https://inspire.geoportaal.ee/geoserver/AD_Address/wfs | 730,682 features (count returned by the service on 2026-11-11). Feature types include AD.Address, AD.Address_ThoroughfareName, AD.Address_PostalDescriptor. EPSG:3301 | Keyless. Capabilities state fees "puudub" (none) and access constraints "puudub" (none) | Not stated beyond the above | Service stamp "Last update: 2026-11-08" | confirmed |
| AKS OGC WFS | Maa- ja Ruumiamet | `https://aks.geoportaal.ee/aks-ogc?service=WFS` | Layers such as `aks:ads_hoone_p`, `aks:ads_sihn_alad` (postcode areas), `aks:ads_lp` | Keyless. Capabilities state fees "none" | Not stated beyond the above | Not stated | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Estonia | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Estonia countrywide | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/ee/countrywide.json | Built from a third-party mirror of the official extract (`https://address.dev.peatus.ee/`), because the official download moved into the JavaScript AKS application | Free download, needs a logged-in account | Not stated in the material read | Not stated | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Estonia is among the 19 EU countries covered | No account, GeoParquet | Per country | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **In-AKS** (the address search API that replaces In-ADS), in use since 27 April 2026: API `https://aks.geoportaal.ee/inaks/inaadress/`, JSON gazetteer `https://aks.geoportaal.ee/inaks/inaadress/gazetteer`, for example https://aks.geoportaal.ee/inaks/inaadress/gazetteer?address=Vesilennuki+12&results=2 . No key. On 2026-11-11 it returned the same fields and values as the old endpoint. A generator for an embeddable search box is at https://aks.geoportaal.ee/aks/inaks/generaator . No terms of use were found for In-AKS.
- **In-ADS** (the old host, closing): `https://inaadress.maaamet.ee/inaadress`, JSON gazetteer `https://inaadress.maaamet.ee/inaadress/gazetteer?address=...` or `?adrid=...`, XML through `/inaadress/service`. No key. A query returns full address, ADS_OID, ADR_ID, component codes, `sihtnumber` (postcode), L-EST coordinates (`viitepunkt_x/y`), WGS84 coordinates (`viitepunkt_l/b`) and a bounding box. Terms of Use v1.3 of 03.01.2024 (https://geoportaal.maaruum.ee/docs/aadress/In-ADS_terms_of_use.pdf): free of charge; automated use up to 3,000 queries per 10 minutes and 10,000 per hour per IP; from IPs outside Estonia 2,000 per 10 minutes and 6,000 per hour; for more, install the In-ADS container solution in one's own infrastructure; autocomplete must start after the fourth character with a pause of at least 500 ms; no personal data is processed; the data is open data. Do not build new code against this host.
- **Geocoder**: single and mass geocoding (input CSV, XLS or XLSX; output CSV, XLSX, GeoJSON, GeoPackage) and a Geocoder API with Swagger under `https://inaadress.maaamet.ee/geocoder-api/...`. Description: https://geoportaal.maaruum.ee/eng/services/address-data-geocoding-p873.html
- **Address search in the AKS application**: https://aks.geoportaal.ee/aks/search/address
- **WFS and WMS**: the INSPIRE Addresses WFS and the AKS OGC WFS in the table above, both keyless; also an address WMS and a WMS and WFS of residential buildings derived from address data, listed on https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed-p112.html
- **X-tee (X-Road) services**: new aks-ads REST services are open by default to all X-tee consumers, but a legal person must first join X-tee. X-tee returns at most 100 answers per query. Page: https://geoportaal.maaruum.ee/index.php?lang_id=1&page_id=266
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.

### Caveats and recent changes

- **In-ADS is being replaced by In-AKS.** The official notice (https://geoportaal.maaruum.ee/est/teenused/in-ads-in-aks/nb-muudatused-in-adsis-p1038.html, last changed 10.11.2026) says the new service has been in use since 27 April 2026. The old `https://inaadress.maaamet.ee/` was first planned to stay open until the end of July 2026; the deadline has now moved "towards the end of the year". After it closes, requests will be redirected for some time. Both hosts answered keyless on 2026-11-11.
- **ADS is being folded into AKS.** The public application and the extracts moved: `https://xgis.maaamet.ee/adsavalik/extracts` redirects to `https://aks.geoportaal.ee/aks`, a JavaScript application, and `https://aks.maaruum.ee/aks/valjavotted` redirects to `https://aks.geoportaal.ee/aks/valjavotted`. The publisher states that the data composition stays the same: all earlier identifiers and field names are kept.
- The old X-tee SOAP services close at the end of 2026 ("suletakse 2026. aasta lõpus").
- The English address page still links the old "ADS public service" URLs on xgis.maaamet.ee; the Estonian page (https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed-p112.html) is more current.
- The old domain geoportaal.maaamet.ee redirects to geoportaal.maaruum.ee.
- The OpenAddresses source definition notes that as of 2026-09 the extract's column headers are all lowercase. Scripts written for the old extracts need checking.
- The SFTP server limits access from foreign IP addresses; the page says to contact the ADS help e-mail if blocked.
- Licence: the address page says there is no licence agreement and asks for the Board to be named as provider. The Board also has a general open data licence dated 01.01.2025 (https://geoportaal.maaruum.ee/opendata-licence, which redirects to https://geoportaal.maaruum.ee/docs/Avaandmed/ETAK_open_data_licence.pdf): free use for an unspecified term, derivatives, commercial and non-commercial use, redistribution; the reference must give the licensor's name, the title of the data and its date.
- Content: eight component levels (county, municipality, settlement or city district, address area, thoroughfare, object name, address number, building-part number). Identifiers: ADR_ID (address version), ADS_OID (object, stable), ADOB_ID (object version). About 99.9 % of addresses have a reference point. The data includes dwellings and flats, and extract no. 9 includes history.
- ADS holds only official addresses: "no address in Estonia is valid before the address is registered in ADS". It also holds some unofficial data: neighbourhoods, quarters and commonly used building names. Local governments are responsible for the accuracy of official addresses.
- Postcodes were added to ADS in 2019. They are managed by Omniva (the postal operator) and applied to ADS addresses by Omniva's postcode areas.
- High-value datasets: on data.europa.eu the record "Estonian Address Data System Information System" in catalogue `ng-ee` is flagged `is_hvd: true`; the same dataset's record from the national open data portal (catalogue `avaandmete-portaal`) shows `is_hvd: false`.
- The `last-modified` header of sihtnumbrid.zip echoes the request time, so it does not show the file's age.

### Not free or not available

- No paid address product was found. The address data is free with no account.
- X-tee services are not open to the general public: a legal person must first join X-tee.
- The official extract download as a plain, scriptable link: only sihtnumbrid.zip was confirmed as a direct file URL. The other extracts are behind the JavaScript AKS application or on the SFTP server.

### Could not be verified

- The SFTP server and the AKS extract downloads (current file names, sizes, and whether foreign IPs are really blocked): the application is JavaScript-only and no SFTP login was made. The SFTP port answered a connection test, which says nothing about foreign IPs.
- Terms of use and rate limits for In-AKS: none found. The published limits are in the In-ADS terms.
- What happens to the Geocoder API on the old host `inaadress.maaamet.ee` when that host closes: not stated in the material read.
- KML and SHP as geocoder output formats: those two lines were not re-read; CSV, XLSX, GeoJSON and GeoPackage were.
- Statistics Estonia and municipal portals: not checked.

## Finland (FI)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Ryhti building addresses (Syke) | Keyless OGC API Features, paged; no bulk file found | CC BY 4.0 | Yes, building points; EPSG:3067, served as WGS84 | Yes | Not documented; same-day changes observed |

**In short.** Page the keyless Ryhti OGC API of Suomen ympäristökeskus (Syke, the Finnish Environment Institute): 3,870,989 building addresses with street, number, postcode and post office in Finnish and Swedish, under CC BY 4.0. No official one-click bulk file was found, so an import means paging the API and then following changes by timestamp. The trap: the well-known open "building addresses" file of DVV (the Digital and Population Data Services Agency) ended on 14 March 2025, and its portal pages now answer 404.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Ryhti building addresses, collection `open_address` (Ryhti = Rakennetun ympäristön tietojärjestelmä, Built Environment Information System) | Syke | API: https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1 ; items: https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1/collections/open_address/items?f=application/json&limit=2 ; portal record: https://avoindata.suomi.fi/data/fi/dataset/rakennetun-ympariston-tietojarjestelman-rakennusten-osoitetiedot | 3,870,989 address features (count returned by the service on 2026-11-11). Fields include `address_key`, `building_key`, `address_fin`, `address_swe`, `address_name_fin/swe` (street), `address_number`, `number_part_of_address_number`, subdivision letters, `postal_code`, `postal_office_fin/swe`, `municipality_number`, `modified_timestamp_utc`. Storage CRS EPSG:3067 (ETRS-TM35FIN), GeoJSON returned in WGS84. Other collections: `open_address_deleted`, `open_building`, `avoimet_rakennukset`, `avoimet_lupa_rakennukset` | No key, no account | CC BY 4.0 | Newest `modified_timestamp_utc` on 2026-11-11 was 2026-11-11T08:50Z | confirmed |
| Ryhti INSPIRE addresses, collection `AD.Address` | Syke | API: https://paikkatiedot.ymparisto.fi/geoserver/ryhti_inspire_ad/ogc/features/v1 ; items: https://paikkatiedot.ymparisto.fi/geoserver/ryhti_inspire_ad/ogc/features/v1/collections/AD.Address/items?f=application/json&limit=1 | The same 3,870,989 features in the INSPIRE model. Adds the permanent building identifier and the parcel identifier (`building`, `parcel`). Locator level "siteLevel", position specification "building" | No key, no account | CC BY 4.0 | Not stated | confirmed |
| Last DVV extract "Rakennusten osoitetiedot ja äänestysalue" (building addresses and voting district), mirrored by Funet | DVV; mirror by Funet | https://www.nic.funet.fi/index/geodata/dvv/osoitteet/2025/ ; readme: https://www.nic.funet.fi/index/geodata/dvv/osoitteet/2025/rakennukset_readme.txt | 3,872,156 buildings with coordinates and at least a postcode (publisher's figure in the readme). Shapefile set: `osoiteet_2025.shp` 105 MB, `.dbf` 832 MB. Older snapshots in sibling folders 2016, 2018, 2020, 2022 | Open directory | Not stated in the material read | Frozen. Extract taken 3 February 2025; files dated 23 May 2025 | confirmed |
| City address datasets on the national portal: Helsinki ("Helsingin osoitteet"), capital region ("Pääkaupunkiseudun osoiteluettelo"), Espoo, Vantaa, Turku and Kaarina address points, Oulu, Salo, Hyvinkää, Raisio, Vihti, Kauniainen, and an Uusimaa address API ("Uudenmaan osoiterajapinta") | The cities | https://avoindata.suomi.fi/data/api/3/action/package_search?q=osoitteet&rows=40 | Municipal or regional address lists and points. Contents were not examined | Listed on avoindata.suomi.fi | CC BY 4.0 (portal licence tag) | Not stated | confirmed |
| Posti postcode files: PCF (Postcode File), BAF (Basic Address File, "Perusosoitteisto"), POM (postcode changes of the previous month) | Posti (the postal operator) | Files: https://www.posti.fi/webpcode/ ; description: https://www.posti.fi/fi/yrityksille/asiakastuki/postinumerotiedostot ; terms and record layouts: https://assets.ctfassets.net/dvxpcmq06s7e/1eKbwM2WAEY5AuGi5TrSZ7/3550dd7d56837b39126cf8c1b15e9b0a/posti-postinumeropalvelut-palvelukuvaus-ja-kayttoehdot-20150101.pdf | BAF: valid postcodes, streets and municipalities for Finland excluding Åland; street names in Finnish and Swedish (30 characters each); where a street spans several postcodes, house numbers pick the right one. PCF: postcode-level file, no street data. On 2026-11-11 the directory held `BAF_20261107.zip` (4,371,208 bytes), `PCF_20261111.zip`, `POM_20261102.zip`, and uncompressed copies under `unzip/` | No login | Posti's own terms (document dated 1 January 2015). Free of charge. Redistribution allowed if the current service description and terms are passed along | PCF daily except Sunday; BAF weekly on Saturdays; POM monthly on the 3rd | corrected |
| Paavo postcode-area statistics ("Paavo-postinumeroaluetilastot") | Tilastokeskus (Statistics Finland) | https://avoindata.suomi.fi/data/api/3/action/package_search?q=postinumero&rows=40 | Statistics by postcode area. No addresses | Listed on avoindata.suomi.fi | CC BY 4.0 (portal licence tag) | Not stated | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Finland | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Finland | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/fi/countrywide-fi.json | A cached copy of the Ryhti data, file `open_address.csv.zip` | Free download, needs a logged-in account | CC BY 4.0, attribution Syke | Cached upload dated 2026-09-30 | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Finland is among the 19 EU countries covered | No account, GeoParquet | Per country | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **Ryhti OGC API Features** (https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1 and the INSPIRE flavour https://paikkatiedot.ymparisto.fi/geoserver/ryhti_inspire_ad/ogc/features/v1): keyless, free, CC BY 4.0. WMS services are also listed on the portal record. Syke recommends using timestamps in requests to fetch only the data updated since the last query (https://ryhti.syke.fi/en/front-page/services/).
- **National Land Survey geocoding** (Maanmittauslaitos, NLS; REST, Pelias-based): forward `/geocoding/v1/pelias/search`, reverse `/geocoding/v1/pelias/reverse`. Sources include building addresses and interpolated road addresses from the Topographic Database. Supports EPSG:3067 fully and WGS84 partly. Needs a free API key, created in the NLS "My Account" service after registering with an e-mail address. Description: https://www.maanmittauslaitos.fi/en/maps-and-spatial-data/expert-users/kartta-ja-paikkatietojen-rajapintapalvelut/geokoodauspalvelu ; API key instructions: https://www.maanmittauslaitos.fi/en/rajapinnat/api-avaimen-ohje
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.

### Caveats and recent changes

- **The source changed hands.** Maintenance of building data moved from DVV to Syke's Ryhti system, and with it the INSPIRE obligations for addresses and buildings (NLS service message of 28 February 2025, https://www.maanmittauslaitos.fi/en/service-messages/changes-inspire-services-concerning-buildings-and-addresses).
- **The old DVV open file is gone.** Its distribution ended on 14 March 2025. The former portal entry https://www.avoindata.fi/data/fi/dataset/rakennusten-osoitetiedot-koko-suomi answers 404, and DVV's open-data page (https://dvv.fi/avoin-data) no longer lists any building or address dataset.
- The NLS INSPIRE WMS and WFS services for addresses and buildings went out of use after 30 May 2025. The replacement is Syke's OGC API Features.
- Finland has no stand-alone address register in this data. Addresses are building addresses: "in the first phase, the addresses do not have their own location points, and are instead linked to building objects". The coordinates are building positions.
- Addresses reach Ryhti with building permit data from the municipalities. Addresses created before Ryhti came from DVV's Population Information System. During a transition period (2025-2028) municipalities may still deliver permit data to the Population Information System, which forwards it to Ryhti.
- No refresh interval and no rate limit are published for the Ryhti API. What was observed: modification stamps from the same day.
- A collection named `open_address_deleted` sits beside `open_address`; its content was not examined.
- Syke's data content description of 27 May 2026 (https://geoportal.ymparisto.fi/meta/julkinen/dokumentit/Ryhti_rakennustiedot_EN.pdf) lists four open interfaces, among them "Addresses of completed buildings" and "Addresses of project buildings", plus two contractual interfaces.
- High-value datasets: the national portal record carries `highvalue: false`, and data.europa.eu shows `is_hvd: false` for the Ryhti address dataset.
- The NLS geocoder's documentation still names the Population Information System as its building-address source.
- NLS changed the terms of its open interface on 29 September 2026: it "is intended for testing and production use in services where performance is not critical", and NLS may block a user (https://www.maanmittauslaitos.fi/en/service-messages/changes-terms-use-open-interface-national-land-survey-finland). The data licence is the NLS open data CC BY 4.0 licence.
- Posti's page says in its introduction that the files hold no street names. That sentence fits the postcode file (PCF). The BAF does contain street names: fields 8 and 9 of its record layout, Finnish and Swedish.
- Posti's page says older files stay about three months in `./arch`; on 2026-11-11 the directory held about a year of BAF files (back to `BAF_20251115.zip`).
- The Funet shapefile is a frozen February 2025 snapshot, not a maintained source.
- The OpenAddresses copy is a cached upload dated 2026-09-30, not a live harvest.

### Not free or not available

- An official one-click bulk file of all addresses: none found. The portal record has exactly four resources (two OGC API Features URLs and two WMS URLs), and the data.europa.eu records list the same service URLs only.
- DVV building and address data: after 14 March 2025 DVV refers users to its chargeable information services.
- NLS geocoding for heavier production use: needs a paid agreement, with a fee based on the number of queries.
- Ryhti products other than the open ones: need a data permit and/or a usage agreement.
- Posti's files do not cover Åland.

### Could not be verified

- The refresh interval and any rate limit of the Ryhti API: no official statement exists on the pages read.
- Whether Finland has formally reported addresses as a high-value dataset: not checked beyond the portal flags.
- Digiroad (Finnish Transport Infrastructure Agency), said to carry road address ranges: not opened.
- The licence wording for Paavo beyond the portal's CC BY 4.0 tag: not opened.
- Whether the open Ryhti data has any apartment or unit level: not checked.
- Whether Posti's BAF carries coordinates: not checked. The checked content is streets, house-number ranges, postcodes and municipalities.
- Which building-address source the NLS geocoder uses today: not established.
- The per-region and Swedish-language OpenAddresses sources for Finland: only the countrywide Finnish source file was opened.

## France (FR)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Base Adresse Nationale (BAN) | Bulk CSV, no registration | Licence Ouverte 2.0 | Yes; WGS84 lon/lat plus local projected x/y | Yes | Daily |

**In short.** Use the Base Adresse Nationale (BAN, "National Address Base"): one national CSV of about 945 MB, rebuilt every day, downloadable without an account under Licence Ouverte 2.0. For geocoding, call the Géoplateforme at `data.geopf.fr/geocodage`; the old host `api-adresse.data.gouv.fr` still answers but is past its announced sunset of 31 January 2026 and must not be used for new work. The likeliest trap is the `x`/`y` columns: they are Lambert-93 only in metropolitan France and local UTM overseas, so load `lon`/`lat` instead.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Base Adresse Nationale (BAN), national and per-département CSV | IGN operates and distributes it, under the responsibility of DINUM; data.gouv.fr organisation "Base Adresse Nationale" | Download page: https://adresse.data.gouv.fr/outils/telechargements ; file listing: https://adresse.data.gouv.fr/data/ban/adresses/latest ; national file: https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/adresses-france.csv.gz ; dataset record: https://www.data.gouv.fr/datasets/base-adresse-nationale | 26,122,628 addresses in 35,011 communes (publisher's live counter, 11 Nov 2026). Per row: house number, suffix, street, postcode, INSEE commune code, x/y, lon/lat, position type, postal delivery label, certification flag, cadastral parcel ids. One position per address | Bulk download, no login. National file 945,276,393 bytes on 11 Nov 2026. Folders `csv`, `csv-with-ids` (1.83 GB), `csv-bal` (1.43 GB), `csv-bal-with-lang`, `addok` | Licence Ouverte / Open Licence 2.0 | Daily; one archive per week kept for a year, one per month before that | confirmed |
| Bases Adresses Locales (BAL, "local address bases"), the communes' source files | Communes, through adresse.data.gouv.fr | https://adresse.data.gouv.fr/outils/telechargements (the files sit on each commune's page) | The file each commune publishes in BAL format; the BAN is built from these | Per-commune download, as stated on the download page | Not stated separately | Not stated | confirmed (statement on the page; no commune page was opened) |
| BAN PLUS | IGN | https://cartes.gouv.fr/rechercher-une-donnee/dataset/IGNF_BAN-PLUS | Link tables: address to building, address to parcel, building to parcel, address to road support, plus the BAN points. Replaces the former "Adresse PREMIUM" offer | Shapefile; no public access restriction stated in the catalogue record | Licence Ouverte (compatible ODC-BY, CC-BY 2.0) | Quarterly, with BD TOPO; publication dates from 2022-12-15 to 2026-09-15 | corrected |
| Référentiel National des Bâtiments (RNB, "national building register") | Publisher not named in the material read; listed on data.gouv.fr | Record: https://www.data.gouv.fr/api/1/datasets/referentiel-national-des-batiments/ ; national export: https://rnb-opendata.s3.fr-par.scw.cloud/files/RNB_nat.csv.zip ; documentation: https://rnb-fr.gitbook.io/documentation/api-et-outils/export-national-et-departemental | Buildings, not addresses: `rnb_id`, point and shape (WGS84, EWKT), status, external ids, the list of known addresses (each with at least the BAN interoperability key), parcels | CSV, one export per département plus a national file of about 11.7 GB zipped | Licence Ouverte 2.0 | Declared weekly; the national file was dated 2026-10-19 on 11 Nov 2026 | confirmed |
| Base officielle des codes postaux ("official postcode base", Hexasmal) | La Poste | Record: https://www.data.gouv.fr/datasets/base-officielle-des-codes-postaux ; CSV: https://data.laposte.fr/data-fair/api/v1/datasets/laposte-hexasmal/metadata-attachments/base-officielle-codes-postaux.csv ; portal record: https://data.laposte.fr/data-fair/api/v1/datasets/laposte-hexasmal | Commune-to-postcode table, 39,192 rows (publisher's figure): INSEE code, commune name, postcode, delivery label, line 5. The CSV export adds a commune centroid. No addresses | CSV, no login, 4,146,942 bytes | Licence Ouverte / Open Licence 2.0 | Portal data updated 8 Nov 2026 | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for France | API, no key; 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definitions: https://github.com/openaddresses/openaddresses/tree/master/sources/fr | Copy of the BAN, one source folder per département (104 entries) | Free download, needs a logged-in account | Follows the source | The BAN is pushed to it once a week (publisher's statement) | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Address points for France | GeoParquet, no account | Set per country; not recorded here | Per release | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **Géoplateforme geocoding (IGN).** `https://data.geopf.fr/geocodage/search` and, under the same base, `/reverse`, `/getCapabilities`, `/openapi` and `/openapi.yaml`. No key. Documented limit: 50 requests per second per IP address. Guide: https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/geocodage/
- A keyless call such as https://data.geopf.fr/geocodage/search?q=8+bd+du+port+amiens&limit=1 returns a house-number feature with `banId`, `postcode`, `citycode`, `x`/`y` and lon/lat. The service has three indexes: `address`, `poi`, `parcel`.
- **Batch geocoding.** A CSV of less than 50 MB or 200,000 lines is geocoded synchronously. Larger files, up to 1 GB, go through an asynchronous project that needs a Géoplateforme account and OAuth2 credentials (contact geoplateforme@ign.fr).
- **WFS.** Layer `BAN.DATA.GOUV:ban` at `https://data.geopf.fr/wfs/ows`, no key; it reported 26,120,609 features on 11 Nov 2026. The download page says the WFS and WMS are updated "bi-hebdomadaire" (twice a week).
- **WMS.** Layer `BAN.DATA.GOUV`, same update rhythm.
- **Vector tiles (MVT).** Updated in real time; listed on https://adresse.data.gouv.fr/outils/telechargements
- **BAN statistics.** https://plateforme.adresse.data.gouv.fr/ban/stats returns the live counters as JSON.

### Caveats and recent changes

- **The geocoding API moved from DINUM to IGN.** A data.gouv.fr post of 3 April 2025 (https://www.data.gouv.fr/posts/lapi-adresse-de-la-base-adresse-nationale-est-transferee-a-lign-10) set 30 June 2025 as the target for the full traffic transfer and kept the old domain "jusqu'à janvier 2026". The new service is described as "iso fonctionnel" and adds POI and cadastral-parcel search.
- **The old host is still alive, past its sunset.** On 11 Nov 2026 `https://api-adresse.data.gouv.fr/search/` still returned HTTP 200 with JSON. Its headers carry `deprecation` and `sunset: Sat, 31 Jan 2026 22:59:59 GMT`, `x-api-deprecated: true`, `x-infra: gpf` and a notice that the URL will be decommissioned. Use `data.geopf.fr` only.
- **`x`/`y` are not one projection.** They are in the local legal projection: Lambert-93 in metropolitan France, local UTM overseas (a Réunion address has x 338805.95, y 7690488.36). The CSV does not name the projection. `lon`/`lat` are uniform.
- **Quality is uneven.** 23,263,076 addresses come from the BALs of 29,018 communes. 2,859,552 addresses (10.9%) in 5,993 communes are still "assemblage", computed from other sources, and only 72,650 of those are certified. In total 19,576,730 addresses are certified by their commune (publisher's live counters, 11 Nov 2026).
- **Directory URLs.** Use listing paths without a trailing slash; the form with a slash answers 308.
- **CSV details.** The separator is a semicolon; the "CSV historique" file has 23 columns. The download page offers CSV and Addok JSON only; no GeoPackage or shapefile of the BAN itself.
- **A stale folder.** `https://adresse.data.gouv.fr/data/adresses-locales/latest/csv` still resolves, but its files are dated 17/10/2023. Do not import from it.
- **Old IGN documentation links** under `geoservices.ign.fr` redirect to cartes.gouv.fr (geocoding guide and BAN PLUS).
- **La Poste.** The old portal host `datanova.laposte.fr` fails TLS with an expired certificate. The data.gouv.fr record of the postcode base shows a last update of 2023-07-09 and a half-yearly rhythm, while the file on data.laposte.fr was updated on 8 Nov 2026; take the file from data.laposte.fr.
- **Rate-limit headers.** Both geocoding hosts send `x-ratelimit-limit-second: 1` next to `ratelimit-limit: 50`. Only the 50 per second is documented.
- **Maintenance notice.** On 11 Nov 2026 the download page announced a service interruption for security maintenance on "mercredi 11 novembre"; requests made that day were served.
- **High-Value Dataset tags.** The BAN, the RNB and BAN PLUS are flagged `hvd`; the BAN is also tagged as reference data (`spd`).

### Not free or not available

- **Postcode boundaries.** La Poste states that the geographic contours of postcodes are not provided as open data.
- **Geocoding files over 50 MB or 200,000 lines** need a Géoplateforme account and OAuth2 credentials; the keyless service does not take them.
- **Cadastre address extract.** `https://cadastre.data.gouv.fr/datasets/adresses-cadastre` returns 404; no current cadastre-derived address file was found.

### Could not be verified

- **A CNIG document of June 2026** (https://cnig.gouv.fr/IMG/pdf/cnig_gt_assurances_19062026.pdf) is said to carry the heading "URL API Adresse décommissionnée fin janvier 2026". The PDF exists (5,009,213 bytes) but its text was not read.
- **Which rate limit is enforced.** The meaning of the `x-ratelimit-limit-second: 1` header is undocumented and was not tested with a burst of requests.
- **Effect of the EU High-Value Datasets regulation on the BAN** beyond the tag: no publisher statement was looked for.
- **Postcodes inside the BAN.** That the postcode column carries no licensing condition of its own, separate from the BAN licence, was not checked.

## Germany (DE)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | Per-Land cadastre address files; regional only, Bavaria missing | One bulk file or service per Land, no key | dl-de/zero-2-0, dl-de/by-2-0 or CC BY 4.0, by Land | Yes; ETRS89/UTM zone 32 or 33 (EPSG:25832, EPSG:25833) | Partly; in the free data of 8 Länder | Varies by Land: monthly to yearly, some not stated |

**In short.** Germany has no free nationwide address file; the national product, Hauskoordinaten Deutschland (HK-DE, "house coordinates Germany"), is sold. A developer has to build the country from the Länder (federal states): 14 of 16 state that their address points are free, Niedersachsen offers only open cadastre packages, and Bayern (Bavaria, about 16% of the records in the national file) sells its data. The most likely trap is the postcode: six Länder publish their bulk file without postal fields, and only one of them (Nordrhein-Westfalen) is known to add the postcode for free through its INSPIRE service. Layouts, coordinate zones, licences and link behaviour differ per Land, and three official bulk downloads (Saarland, Schleswig-Holstein, Thüringen) could not be fetched on 2026-11-11.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Länder cadastre address files: Hauskoordinaten ("house coordinates") or Gebäudereferenzen ("building references") | The surveying agency of each Land | See "By Land" below; catalogue search <https://www.govdata.de/ckan/api/3/action/package_search?q=title:Hauskoordinaten> | One point per house number with street, municipality and ETRS89/UTM coordinates; postcode only in some Länder | Bulk file, ATOM feed, WFS or OGC API per Land; no key or login where the download worked | dl-de/zero-2-0, dl-de/by-2-0 or CC BY 4.0, by Land | By Land | confirmed for 11 Länder with current data; see "By Land" |
| Frankfurt am Main Hauskoordinaten | Stadt Frankfurt am Main | <https://offenedaten.frankfurt.de/dcat/dataset/de-he-frankfurtam-hauskoordinaten/content.csv> | City address points as CSV; a postcode column is recorded by OpenAddresses | Direct link; the content was not fetched (a HEAD request reported length 0) | dl-de/by-2-0 (GovData record) | not verified | confirmed (catalogue only) |
| Rostock addresses | Hanse- und Universitätsstadt Rostock | <https://geo.sv.rostock.de/download/opendata/adressen/adressen.csv> | CSV, 7.6 MB, with latitude, longitude, house number and postcode columns | Direct file, no login | CC0 1.0 as recorded by OpenAddresses; not seen on a Rostock page | File dated 10 Nov 2026 | confirmed (licence unverified) |
| Köln and Wesel addresses | Stadt Köln; Stadt Wesel | Köln, OpenAddresses source definition: <https://github.com/openaddresses/openaddresses/blob/master/sources/de/nw/city_of_cologne.json>; Wesel file: <https://geoportal.wesel.de/opendata/Adressen/Adressen.csv> | City address files with a postcode column, as recorded by OpenAddresses | Files not requested | dl-de/zero-2-0 as recorded by OpenAddresses | not verified | unverified at the publisher |
| Essen and Bielefeld Hauskoordinaten | Stadt Essen; Stadt Bielefeld | <https://www.govdata.de/ckan/api/3/action/package_search?q=title:Hauskoordinaten> | City house coordinates listed on GovData | Catalogue records; files not requested | Essen: dl-de/by-2-0. Bielefeld: dl-de/zero-2-0, with some resources marked "other-closed" | not verified | corrected |
| Münchner Adressen ("Munich addresses") | Landeshauptstadt München | <https://karten.muenchen.de/resources/gsm/__docs/adressen_aktuell.txt> | Street, house number and city district; no coordinates, no postcode; 4.1 MB | Direct file, no login | dl-de/by-2-0 | File dated 21 Oct 2026 | confirmed |
| OpenPLZ API | OpenPLZ API project (community) | <https://openplzapi.org/> | Street names, postcodes, localities and municipalities; no house numbers | REST API, no key | ODbL | Aims at half-yearly | corrected |
| GISCO Address API | Eurostat | <https://gisco-services.ec.europa.eu/addressapi> | Address lookup for Germany; its data credit reads "GeoBasis-DE / BKG (2021)" | No key; lookup only, 1,000-row cap, no bulk download | None stated | Snapshot credited 2021 | confirmed |
| OpenAddresses | OpenAddresses | <https://batch.openaddresses.io> | Statewide address sources for 15 Länder plus some cities; Bavaria has building outlines only | Free download, needs a logged-in account | Per source, as in "By Land" | Runs of 2026-10-16 to 2026-10-30; five Länder from copies cached in August and September 2026 | confirmed |
| Overture Maps addresses | Overture Maps Foundation | <https://docs.overturemaps.org/guides/addresses/> | 19,299,493 German addresses (publisher's figure) from the same 15 Länder; no Bavaria | GeoParquet, no account | Per Land | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | <https://download.geonames.org/export/zip/> | Postcode centroids only, no addresses | Bulk file | CC BY 4.0 | not stated | confirmed |

### By Land

Values are the state on 2026-11-11. "Sample" means only the first few thousand rows of a file were read.

| Land | Free address points? | Link | Format | Postcodes in the free data? | Licence | Update cycle | Check |
|---|---|---|---|---|---|---|---|
| Baden-Württemberg | Yes: "Hauskoordinaten ohne Informationen der Post" (without postal data). The variant with postal data is paid. | <https://opengeodata.lgl-bw.de/data/hk/hk_bw.zip>; product page <https://www.lgl-bw.de/Produkte/Liegenschaftskataster/Hauskoordinaten/> | Zipped TXT, 73.2 MB, semicolon, header row, 26 HK-DE columns; EPSG:25832 | No. The postal columns are empty (sample; the publisher says fields 21 to 25 are not filled). | dl-de/by-2-0; credit "Datenquelle: LGL, www.lgl-bw.de, dl-de/by-2-0" | "At least monthly" per the publisher; the GovData record says semi-annual. File and rows dated 8 Oct 2026. | corrected (licence is stated by the publisher) |
| Bayern (Bavaria) | No; none found at Land level. The open-data product list (35 products) has no address product. Hauskoordinaten are sold: EUR 0.15 per object, minimum EUR 100. | Paid product: <https://www.ldbv.bayern.de/produkte/liegenschaftsinformationen/hauskoordinaten.html>; open-data list: <https://geodaten.bayern.de/opengeodata/json/opengeodata_produkte.json> | No free file. The paid product is ASCII text in ETRS89/UTM zone 32 and 33. | No free data. The paid product includes Deutsche Post postal data. | None for addresses. The other open products are CC BY 4.0. | The paid product is updated daily. | none found |
| Berlin | Yes | File: <https://gdi.berlin.de/data/adressen_berlin/atom/HKO_EPSG25833.zip> (from the feed <https://gdi.berlin.de/data/adressen_berlin/atom/>); WFS: <https://gdi.berlin.de/services/wfs/adressen_berlin> | File: zipped TXT, 9.8 MB, semicolon, no header, 26 HK-DE fields. WFS: GML 3.2. Both EPSG:25833. | File: no (postal columns empty, sample). WFS: yes (field plz). | dl-de/zero-2-0 | Semi-annual per the GovData record. File of 3 Nov 2026, rows dated 2026-10-01. | confirmed |
| Brandenburg | Yes: "Georeferenzierte Adresse" (georeferenced address). No static file link exists; the data is reachable anonymously through the OGC API. | OGC API: <https://ogc-api.geobasis-bb.de/datasets/gaz/collections/Hauskoordinaten/items>; WFS: <https://isk.geobasis-bb.de/ows/gaz_wfs>; shop: <https://geobroker.geobasis-bb.de/gbss.php?MODE=GetProductInformation&PRODUCTID=51600a1d-c7a3-4211-aff8-e94fb7dc166d> | API: GeoJSON; stored in EPSG:25833, default output CRS84, EPSG:4326 also served. Shop (not inspected): ASCII UTF-8 in ZSHH format, Shape, GeoJSON, GeoPackage, FileGDB. | Yes (post_plz, post_ortsname and post_strname seen in a live API item) | dl-de/by-2-0; credit "© GeoBasis-DE/LGB, dl-de/by-2-0" | File product: half-yearly, April and October. The API item read was dated 2026-11-03. | corrected (API path); shop download unverified |
| Bremen | Yes, since 9 June 2024: "ALKIS - Gebäudeadressen Land Bremen" | File: <https://gdi2.geo.bremen.de/inspire/download/ALKIS_Gebaeudeadressen/data/GEBAEUDEADRESSEN_SHP_FHB.zip>; WFS: <https://geodienste.bremen.de/wfs_AX_GeoreferenzierteGebaeudeadresse> | Shapefile in a zip inside a zip, 11.0 MB, 176,374 records; ETRS89/UTM32 | Yes (plz and onm filled in the three records read), although the metadata says the data comes without postcode | CC BY 4.0; credit "Landesamt GeoInformation Bremen" | 6 months per the metadata, yearly per the product page. File of 28 Sep 2026, inner file named 2026_08. | confirmed |
| Hamburg | Yes: "ALKIS - Adressen Hamburg" | Latest dated file: <https://daten-hamburg.de/opendata/ALKIS_Adressen/ALKIS_Adressen_HH_2026-10-02.zip> (answers 301 to www.daten-hamburg.de); INSPIRE WFS: <https://geodienste.hamburg.de/HH_WFS_INSPIRE_Adressen> | Zipped GML (FME feature collection), 12.2 MB; EPSG:25832 | Yes (plz, portsname; sample) | dl-de/by-2-0; credit "Freie und Hansestadt Hamburg, Landesbetrieb Geoinformation und Vermessung (LGV)" | A new dated file each quarter in 2026 (01, 04, 07, 10); the metadata says "continuous" | corrected (host redirects) |
| Hessen | Yes: "Hauskoordinaten ohne Postalische Angaben" (without postal data) | <https://gds.hessen.de/downloadcenter/20261111/Liegenschaftskataster/Hauskoordinaten%20ohne%20Postalische%20Angaben%20(txt)/Hauskoordinaten%20ohne%20Postalische%20Angaben-2026-01.zip> (the date folder changes daily); Downloadcenter: <https://gds.hessen.de> | Zipped CSV, 28.7 MB, comma, header row, 20 columns, key and number fields quoted; EPSG:25832 | File: no (no postal columns). INSPIRE services: not verified. | dl-de/zero-2-0 | "Annually" per the publisher's metadata. File named 2026-01, dated 24 Jun 2026. | corrected (update cycle) |
| Mecklenburg-Vorpommern | Yes, the "Hauskoordinaten light" variant only (without postal data). The full Hauskoordinaten product has no download link. | Feed: <https://www.geodaten-mv.de/dienste/alkis_hklight_atom>; file: <https://www.geodaten-mv.de/dienste/alkis_hklight_download?index=0&dataset=b0828575-fe32-49bb-a703-d74e415a979c&file=HKlight.zip> | Zipped text, 9.1 MB, UTF-8, semicolon, no header, 26 HK-DE fields, 519,370 rows; EPSG:25833 | No (empty in every row of the file) | CC BY 4.0; credit "© GeoBasis-DE/M-V <Jahr der letzten Datenlieferung>" | Half-yearly. File of 2026-09-29. | corrected (licence) |
| Niedersachsen | No Hauskoordinaten product found in open data. Open ALKIS (cadastre) packages per Landkreis exist; that they hold house numbers is not verified. | STAC: <https://alkis.stac.lgln.niedersachsen.de>; hub: <https://ni-lgln-opengeodata.hub.arcgis.com> | Zipped GeoPackage per Landkreis (the one checked was 63 MB); EPSG:25832 | not verified (the address file OpenAddresses derives from ALKIS maps no postcode) | CC BY 4.0; credit "© GeoBasis-DE/LGLN <year>" | not verified (no cycle stated; the package checked was 5 days old) | none found (address product); ALKIS content unverified |
| Nordrhein-Westfalen | Yes: "Gebäudereferenzen" (building references, without postal address) | File: <https://www.opengeodata.nrw.de/produkte/geobasis/lk/akt/gebref_txt/gebref_EPSG25832_ASCII.zip>; INSPIRE WFS: <https://www.wfs.nrw.de/geobasis/wfs_nw_inspire-adressen_gebref> | File: zipped ASCII, 97.0 MB, semicolon, no header, 21 columns. WFS: GML 3.2.1. Both EPSG:25832. | File: no. INSPIRE WFS: yes, as PostalDescriptor objects linked from the addresses. | dl-de/zero-2-0 | File: quarterly per the metadata; data state 01.07.2026. WFS: data state 01.10.2026. | corrected (postcodes are free through the WFS) |
| Rheinland-Pfalz | Yes: "Amtliche Gebäudereferenz" (official building reference; Hauskoordinaten without postal data) | <https://geobasis-rlp.de/data/hk/current/zip/HAUSKOORDINATEN_RP.zip>; page <https://geoshop.rlp.de/opendata-hk.html> | Zipped CSV, 26.6 MB, semicolon, header row, 20 columns; EPSG:25832. The zip also holds the format description PDF. | No (the file has no postal columns) | dl-de/by-2-0; credit "©GeoBasis-DE / LVermGeoRP<Jahr des Datenbezugs>, dl-de/by-2-0, www.lvermgeo.rlp.de [Daten bearbeitet]" | not verified (file dated 26 Aug 2026) | confirmed; update cycle unverified |
| Saarland | Listed as open data, but the bulk file could not be fetched: the link redirects to a share-authentication page. The INSPIRE WFS answers without a key. | File link: <https://www.shop.lvgl.saarland.de/cloud/index.php/s/hauskoordinaten/download>; INSPIRE WFS: <https://geoportal.saarland.de/gdi-sl/inspirewfs_Adressen_Hauskoordinaten> | File: ASCII txt per the metadata, not seen. WFS: GML. | INSPIRE WFS: yes (a PostalDescriptor with postcode 66564 was returned). File: not verified. | dl-de/by-2-0; credit "© GeoBasis DE/LVGL-SL (Jahr), dl-de/by-2-0, www.lvgl.saarland.de" | File record: weekly per the metadata. INSPIRE record: quarterly. | confirmed (download blocked); file content unverified |
| Sachsen | Yes: Hauskoordinaten | File: <https://geocloud.landesvermessung.sachsen.de/public.php/dav/files/B3HnXbDDgAkw69a/hk_sn_ascii.zip>; page <https://www.geodaten.sachsen.de/downloadbereich-hauskoordinaten-4172.html> | Zipped CSV text, 22.2 MB, semicolon, header row, 24 columns; EPSG:25833 | Yes (postplz and postonm filled; sample) | dl-de/by-2-0; credit "Quelle: GeoSN" (seen in the GovData record only) | Quarterly per the download page; the GovData record says semi-annual. Inner file dated 2026-10-22. | confirmed |
| Sachsen-Anhalt | Yes: "Gebäudereferenzen" (without postal address). The full "Amtliche Hauskoordinaten" are paid. | <https://www.lvermgeo.sachsen-anhalt.de/datei/anzeigen/id/258997,501/gebaeudereferenzen.zip> | Zipped TXT, 17.5 MB, UTF-8, semicolon, no header, 26 HK-DE fields, 664,766 rows; EPSG:25832 | No (empty in every row of the file) | dl-de/by-2-0; credit "© GeoBasis-DE / LVermGeo ST" | Not stated for the free file; current state 09/2026 | corrected (no cycle stated for the free file) |
| Schleswig-Holstein | Yes per the publisher's product list, but the download page could not be fetched (the server's TLS certificate chain is incomplete). The INSPIRE WFS answers without a key. | Download page: <https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/dl-hk_alkis.html>; INSPIRE WFS: <https://service.gdi-sh.de/SH_INSPIREDOWNLOAD_AI_AD> | File: not verified. WFS: GML 3.2.1. | INSPIRE WFS: yes (1,768 postal descriptors). File: not verified. | CC BY 4.0; credit "© GeoBasis-DE/LVermGeo SH/CC BY 4.0" | not verified | confirmed (publisher statement and WFS); file unverified |
| Thüringen | Listed as open data. The Hauskoordinaten file link returns only a placeholder notice. An INSPIRE file downloads anonymously but holds an older state. | INSPIRE feed: <https://www.geoproxy.geoportal-th.de/inspire-dl/atom/Service/Service_318d592d-807b-47d4-8cbe-8be22cc6f12b.xml>; file: <https://www.geoproxy.geoportal-th.de/download-service/inspire/annex1/ad/ad_25832.zip>; WFS: <https://www.geoproxy.geoportal-th.de/geoproxy/services/INSPIREad_wfs>; dead link: <https://geoportal.geoportal-th.de/hausko_umr/HK-TH.zip> | INSPIRE GML, zip of 26.6 MB (1.45 GB unpacked); EPSG:25832 | No postcode among the first 313 addresses of the INSPIRE file; the metadata of the Hauskoordinaten file says "Postleitzahl (bisher noch ohne)" | CC BY 4.0; credit "© GDI-Th" | The metadata says "continuous", but the INSPIRE file is the 2025 Q1 state (file of 5 Jun 2025) | corrected (anonymous INSPIRE download exists) |

### Free APIs and services

- Berlin WFS, <https://gdi.berlin.de/services/wfs/adressen_berlin>: no key, GML 3.2, EPSG:25833, 403,303 address features with a postcode field (plz), dl-de/zero-2-0.
- Brandenburg OGC API Features, <https://ogc-api.geobasis-bb.de/datasets/gaz/collections/Hauskoordinaten/items>: no key, GeoJSON. The collection id is case-sensitive ("Hauskoordinaten"). The collection holds 1,264,629 addresses including Berlin; the filter `landschluessel=12` returns the 869,698 Brandenburg addresses. If Berlin data is used, the credit "© Geoportal Berlin, dl-de/zero-2-0" must be added. The same gazetteer is also a WFS: <https://isk.geobasis-bb.de/ows/gaz_wfs>.
- Bremen WFS, <https://geodienste.bremen.de/wfs_AX_GeoreferenzierteGebaeudeadresse>: no key, no access restrictions stated, CC BY 4.0.
- Hamburg INSPIRE WFS, <https://geodienste.hamburg.de/HH_WFS_INSPIRE_Adressen>: no key, no access restrictions stated.
- Hessen REST API, <https://www.geoportal.hessen.de/spatial-objects/706/api>: answers with an OpenAPI document for the INSPIRE address data, dl-de/zero-2-0. The matching WFS, <https://www.geoportal.hessen.de/registry/wfs/706?>, timed out.
- Nordrhein-Westfalen INSPIRE WFS, <https://www.wfs.nrw.de/geobasis/wfs_nw_inspire-adressen_gebref>: no key, dl-de/zero-2-0, data state 01.10.2026. It is the only free NRW source with postcodes.
- Saarland INSPIRE WFS, <https://geoportal.saarland.de/gdi-sl/inspirewfs_Adressen_Hauskoordinaten>: no key, no access restrictions stated, serves postcodes. A second Saarland WFS, <https://geoportal.saarland.de/mapbender/php/wfs.php?INSPIRE=1&FEATURETYPE_ID=2057&REQUEST=GetCapabilities&SERVICE=WFS&VERSION=2.0.0>, lists a Hauskoordinaten feature type, but its feature requests go through a per-session proxy.
- Schleswig-Holstein INSPIRE WFS, <https://service.gdi-sh.de/SH_INSPIREDOWNLOAD_AI_AD>: no key, CC BY 4.0, serves postcodes.
- Thüringen INSPIRE WFS, <https://www.geoproxy.geoportal-th.de/geoproxy/services/INSPIREad_wfs>: no key, no restrictions stated, CC BY 4.0.
- Mecklenburg-Vorpommern INSPIRE WFS, <https://www.geodaten-mv.de/dienste/inspire_ad_alkis_download>: answers without a key, but it is not openly licensed. Its terms make external use subject to permission and possibly a fee.
- OpenPLZ API, <https://openplzapi.org/> (for example `/de/Streets`, `/de/Localities`, `/de/FullTextSearch`): street-to-postcode lookup without a key, no house numbers. Data is ODbL, built from the Destatis municipality file GV100 and streets from OpenStreetMap. Commercial use is allowed by the project.
- GISCO Address API (Eurostat), <https://gisco-services.ec.europa.eu/addressapi>: covers Germany, no key, lookup only with a 1,000-row cap, no licence stated.
- No rate limits were found for any of these services. They were probed with capabilities and single-feature requests only, so paging limits for bulk extraction are not known.

### Caveats and recent changes

- Postcodes. The postal fields of the HK-DE format are Deutsche Post Direkt data, as the AdV's format description (version 5.2) states. Baden-Württemberg, Hessen, Mecklenburg-Vorpommern, Nordrhein-Westfalen, Rheinland-Pfalz and Sachsen-Anhalt publish their bulk file without them, and so does Berlin's Hauskoordinaten file. Postcodes are free in the files of Sachsen, Hamburg and Bremen, in the Berlin WFS, in the Brandenburg API, and through the INSPIRE WFS of Nordrhein-Westfalen, Saarland and Schleswig-Holstein.
- No common layout. Files have 20, 21, 24 or 26 columns, with or without a header row, with semicolon or (Hessen) comma. Hamburg ships GML and Bremen a Shapefile. The full 26-column header, as shipped by Baden-Württemberg, is `nba;oid;qua;landschl;land;regbezschl;regbez;kreisschl;kreis;gmdschl;gmd;ottschl;ott;strschl;str;hnr;adz;zone;ostwert;nordwert;postplz;postonm;postonmzus;postott;poststr;aud`.
- Two coordinate zones. Berlin, Brandenburg, Mecklenburg-Vorpommern and Sachsen use UTM zone 33 (EPSG:25833). Baden-Württemberg, Hessen, Nordrhein-Westfalen, Rheinland-Pfalz, Sachsen-Anhalt, Hamburg, Bremen, Niedersachsen and the Thüringen INSPIRE file use zone 32 (EPSG:25832). The zone of the Saarland and Schleswig-Holstein files was not seen.
- Fragile links. Hessen's link contains the current date; only the folders of the current and the previous day answered, and a HEAD request gets 405. Hamburg's file names carry the release date, and the host answers 301. Sachsen answers a HEAD request with 401 although GET works. The servers of Mecklenburg-Vorpommern and Sachsen-Anhalt ignore byte-range requests.
- Data quirks documented by the AdV for HK-DE (<https://sg.geodatenzentrum.de/public/gdz/dokumentation/deu/hk-de_info.pdf>): quality "C" marks cadastre-internal pseudo house numbers (290,952 in Baden-Württemberg and 49,271 in Nordrhein-Westfalen, publisher's figures). Rheinland-Pfalz resolves ranges such as "2-6" into 2, 4 and 6, which can give duplicate coordinates. Schleswig-Holstein keeps range numbers as single addresses with identical coordinates. Saarland lists streets without buildings with house number "00".
- Nordrhein-Westfalen's bulk file lags its service: on 2026-11-11 the file still held the 01.07.2026 state, while the INSPIRE WFS held the 01.10.2026 state.
- Bremen's metadata says the data comes without postcode, but the file has it.
- Thüringen changed its licence to CC BY 4.0 (metadata of 2026-10-09). OpenAddresses still records dl-de/by-2-0 for Thüringen and still points at the dead file link.
- The placeholder notice behind Thüringen's dead file link is itself dated 2016, which points to a retired link, not a short outage. Schleswig-Holstein's broken certificate chain is recent: the certificate was issued on 29 Sep 2026.
- OpenAddresses serves Brandenburg, Mecklenburg-Vorpommern, Niedersachsen, Schleswig-Holstein and Saarland from copies cached on its own storage in August and September 2026, not from live official links. Its Mecklenburg-Vorpommern and Niedersachsen files are derived from ALKIS, not from an official address file. Its source note for Schleswig-Holstein says the Land's live ArcGIS address service stopped updating.
- Licences fall into three groups: dl-de/zero-2-0 without attribution (Berlin, Hessen, Nordrhein-Westfalen), dl-de/by-2-0 (Baden-Württemberg, Brandenburg, Hamburg, Rheinland-Pfalz, Saarland, Sachsen, Sachsen-Anhalt) and CC BY 4.0 (Bremen, Mecklenburg-Vorpommern, Niedersachsen, Schleswig-Holstein, Thüringen).
- Bremen opened its address data on 9 June 2024 (<https://www.geo.bremen.de/produkte/open-data-produktuebersicht-15654>).
- The AdV fee directive 4.0.1 took effect on 9 June 2024 and lowered the prices of the nationwide products; it did not make them free (<https://www.laiv-mv.de/static/LAIV/Geoinformation/Dateien/Blickpunkte/PM-Daten_der_Zentralen_Stellen_OD.pdf>).
- Hamburg has captured its cadastre data in the AdV reference version 7.1 since December 2024.
- High-value dataset (HVD) tags under Regulation (EU) 2023/138 are set on the GovData records of the address datasets of Brandenburg, Baden-Württemberg, Sachsen-Anhalt, Rheinland-Pfalz and Berlin, and on the INSPIRE address records of Schleswig-Holstein, Hessen, Saarland, Hamburg, Thüringen, Nordrhein-Westfalen, Sachsen and Brandenburg. The tag is missing on the file records of Nordrhein-Westfalen, Sachsen, Hamburg, Thüringen and Saarland and on both INSPIRE records of Rheinland-Pfalz.
- Legal dispute over the nationwide data. In 2021 house-coordinate data that originated from the ZSHH (Zentrale Stelle für Hauskoordinaten, the central office for house coordinates) and had been published on a federal website was mirrored on GitHub, extended by a third person to about 20 million records, and taken down on the demand of the Bavarian surveying agency LDBV (<https://netzpolitik.org/2021/offene-geodaten-bayern-geht-gegen-open-data-aktivistinnen-vor/>). On 30 July 2026 the Oberlandesgericht München dismissed Bavaria's civil suit against the activist as inadmissible and held that the Datennutzungsgesetz (data use act) applies. The judgment was unpublished when this was reported (<https://netzpolitik.org/2026/mit-urheberrecht-gegen-offene-daten-bayern-verliert-gegen-open-data-aktivisten/>).

### Not free or not available

- Free nationwide official address dataset: none found. Searched: all 106 products on the BKG open-data page (<https://gdz.bkg.bund.de/index.php/default/open-data.html>), the BKG shop search for "Adressen" (nine items, all paid, restricted to federal users or licence-bound), the BKG page for HK-DE, and GovData title searches, which list only Länder and municipal records.
- Hauskoordinaten Deutschland (HK-DE), bundled by the ZSHH at the Bavarian LDBV on behalf of the Länder: sold. A nationwide delivery costs a flat EUR 6,000 net under the AdV fee directive 4.0.1, charged again with every delivery but only once a year (<https://sg.geodatenzentrum.de/web_public/gdz/lizenz/eng/adv_gbr_eng.pdf>). Release 04-2026 holds 23,126,517 records (publisher's figure), of which Bavaria has 3,767,086, about 16%. The Länder deliver on 1 April and 1 October; the merged file is available from 1 July and 1 February. Pages: <https://www.ldbv.bayern.de/vermessung/zshh/>, <https://www.adv-online.de/de/produkte/hauskoordinaten-deutschland-hk-de>.
- BKG "Georeferenzierte Adressdaten (GA)" (georeferenced address data): only for federal authorities and users entitled under V GeoBund; copyright-protected; half-yearly, data state 10.2025 (<https://gdz.bkg.bund.de/index.php/default/georeferenzierte-adressdaten-ga.html>).
- National geocoder of the AdV and BKG: free only for federal and Länder authorities. For others the BKG shop lists the location search service (results may not be stored) from EUR 300 and the geocoding service (results may be stored) from EUR 6,000 (<https://gdz.bkg.bund.de/index.php/default/catalogsearch/result/?q=Adressen>; terms: <https://sg.geodatenzentrum.de/public/gdz/lizenz/deu/nutzungsbedingungen_geokodierungsdienst_adv.pdf>).
- BKG "Postleitzahlgebiete Deutschland" (postcode areas): free only for federal authorities and V GeoBund users; credit "© Deutsche Post Direkt GmbH" (<https://sg.geodatenzentrum.de/public/gdz/lizenz/deu/nutzungsbedingungen_plz.pdf>).
- Federal users who pass on applications that contain Hauskoordinaten may not extract the postal address data or make it public (<https://sg.geodatenzentrum.de/web_public/gdz/lizenz/deu/nutzungsbedingungen_hk-de.pdf>).
- Bayern: Hauskoordinaten cost EUR 0.15 per object, minimum EUR 100, with volume discounts, ordered from the LDBV customer service by e-mail, fax or letter (<https://www.ldbv.bayern.de/produkte/liegenschaftsinformationen/hauskoordinaten.html>). A free Land-wide address product: none found. Searched: the Land's open-data product list and GovData, which has no record from the Land. The only free Bavarian address data found is the City of Munich's list without coordinates.
- Variants with postal data are paid in Baden-Württemberg and Sachsen-Anhalt. Sachsen-Anhalt's full "Amtliche Hauskoordinaten" cost EUR 68 per started 200 objects, at most EUR 1,300, and are issued on application (<https://www.lvermgeo.sachsen-anhalt.de/de/gdp-amtliche-hauskoordinaten-lsa.html>). Mecklenburg-Vorpommern's full product has no download link (<https://laiv.geodaten-mv.de/afgvk/Liegenschaftskataster/Beschreibung?produkt=HK>).
- Niedersachsen: a Hauskoordinaten product in open data: none found. Searched: the OpenGeoData.NI hub (40 items; a search for "hauskoordinaten" returns only "ALKIS Hausumringe", building outlines), the ALKIS STAC catalogue (six collections) and GovData.
- The GovData record of Hagen's Hauskoordinaten and an older Essen record carry the licence "other-closed": listed, but not openly licensed.
- Official street and postcode directory: the OpenPLZ API project states that Germany has no freely accessible database of all postcodes and street names (<https://www.openplzapi.org/de/sources/>). Deutsche Post's own product could not be read; see below.

### Could not be verified

- Saarland bulk file: its content, its postcode columns and whether a password or another file route is published. The share link leads to an authentication page; no password was tried.
- Schleswig-Holstein bulk file: its exact URL, layout, postcode content, update cycle and opening date. The download host sends its certificate without the intermediate certificate, and verification was not bypassed. OpenAddresses describes the file as semicolon text without header, 24 columns, with the postcode in column 21.
- Thüringen Hauskoordinaten text file: its content and opening date. The file link is dead and the portal page <https://geoportal.thueringen.de/gdi-th/download-offene-geodaten> is behind a CAPTCHA.
- Brandenburg: whether the shop download needs an account. The first order step opens anonymously; the rest is a script-driven dialogue that was not completed.
- Niedersachsen: that the ALKIS packages hold buildings with house numbers (only OpenAddresses' processing note says so; the 63 MB package was not opened in full), the format of the street-name file, and the ALKIS update cycle.
- Update cycle of Rheinland-Pfalz: not stated on any official page that could be read.
- Hessen INSPIRE WFS: the capabilities request timed out after 60 seconds. Whether the Hessen INSPIRE services carry postcodes is not known.
- Saarland's second WFS (mapbender): no feature could be fetched without a session.
- Sachsen: a geocoding interface is listed under dl-de/by-2-0 at <https://geowebdienste.sachsen.de/services/oas/>; the page answers, but no geocoding call was made, so whether it works without a key is not known. The Sachsen licence itself was seen only in the GovData record, not on the publisher's pages.
- Postcode findings marked "sample" (Baden-Württemberg, Berlin file, Hamburg, Sachsen) rest on the first 2,000 to 4,000 rows, not on the whole file. In Nordrhein-Westfalen the share of addresses that link to a postcode in the WFS was not checked.
- Deutsche Post Direkt "Datafactory" (street and postcode data): the product page <https://www.deutschepost.de/de/d/deutsche-post-direkt/datafactory.html> answered 404 to a script client, so its content, its figures and its price could not be read. No Deutsche Post price list was found.
- Bavarian INSPIRE address service: GovData has no Bavarian INSPIRE address record, and the national geodata catalogue gdk.gdi-de.org refused the request with HTTP 400.
- That all three licences permit commercial reuse and that none is share-alike: the licence texts were not re-read. Only single publisher statements were seen (Nordrhein-Westfalen: any use is allowed without restrictions or conditions; Niedersachsen: free internal and external use).
- Rate limits: none is published in any capabilities document or page that was read; absence cannot be proven.
- Municipal licences: Frankfurt's is confirmed in the catalogue only, Rostock's, Köln's and Wesel's only as OpenAddresses records them.
- Opening dates of the open data in Baden-Württemberg, Brandenburg, Hessen, Mecklenburg-Vorpommern, Niedersachsen, Rheinland-Pfalz and Sachsen: not stated on the pages read. Catalogue "issued" dates are metadata dates, not opening dates.
- Prices and terms of the full Hauskoordinaten products with postal data in Niedersachsen, Nordrhein-Westfalen and Mecklenburg-Vorpommern: not found.
- Whether Germany reports HK-DE as compliant with the HVD regulation: no official statement was located. The text of Regulation (EU) 2023/138 could not be opened (EUR-Lex returned an empty response); that addresses fall under it rests on the tags the publishers set.
- The current ZSHH terms (<https://ldbv.bayern.de/mam/ldbv/dateien/2024-06-09_agnb_zshh_5_0.pdf>, valid from 09.06.2024) were not read beyond heading and scope.
- Statistical-office sources (for example a Destatis municipality directory with postcodes) and a QGIS plugin that claims to download the open data of all 16 Länder were not researched.

## Greece (GR)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | Hellenic Cadastre declared street points: 2023 snapshot, no municipality, no postcode | Bulk shapefile zip, no registration | CC BY 4.0; the Cadastre's own terms unread | Yes, Greek Grid GGRS87 (EPSG:2100) | No | None; "as needed", file dated 2023-11 |

**In short.** No national address register was found. The best free source is one national point file from the Ελληνικό Κτηματολόγιο (Hellenic Cadastre): 2,292,989 points with a street name and a house number as property owners declared them, CC BY 4.0, no login. The file has only those two fields, so every point must be joined to municipality polygons before it is an address, and no open file supplies the postcode. OpenAddresses already publishes that join.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Στοιχεία οδών δηλώσεων Ελληνικού Κτηματολογίου ("Street names and numbers according to cadastral surveying declarations") | Ελληνικό Κτηματολόγιο (Hellenic Cadastre), a public-law body under the Ministry of Digital Governance | Dataset page: https://data.gov.gr/dataset/stoicheia-odon-diloseon-ellinikoy-ktimatologioy ; direct download: https://data.gov.gr/dataset/16068541-970c-4d1a-8047-b95fd4d261ba/resource/946e2a6a-8ab8-4c62-89e3-e14ecd9868a1/download/ogp_hc_regstreets_egsa87.zip ; record as JSON: https://data.gov.gr/api/3/action/package_show?id=stoicheia-odon-diloseon-ellinikoy-ktimatologioy | Shapefile `HC_RegStreets_EGSA87`: 2,292,989 points (count read from the file header), two fields: `ADDRESS` (declared street name) and `NUM` (declared number). UTF-8. No municipality, postcode or identifier | Zip of 64,396,519 bytes, no login. The link redirects to a time-limited signed link on cloud storage. The dbf is 607 MB unpacked | CC BY 4.0, set on the two resources; the resource also points to the Cadastre's terms at https://www.ktimatologio.gr/oroi-xrisis , which could not be read | Shapefile parts dated 2023-11-20; portal record created 2026-02-03, modified 2026-05-11; stated frequency "as needed" | confirmed |
| Street numbering of the Municipality of Kalamaria ("Αρίθμηση οδών του Δήμου Καλαμαριάς") | Municipality of Kalamaria, on data.gov.gr | OpenAddresses source file: https://github.com/openaddresses/openaddresses/blob/master/sources/gr/b/municipality_of_kalamaria.json | Shapefile with street (`Odos`) and number (`Arithmos`); one municipality | Listed on data.gov.gr; file not opened | Not stated; OpenAddresses marks it "presumed" | Not known | confirmed (listing only) |
| Other municipal address layers: Ilion, Papagou-Cholargou, Chalandri, Egaleo ("Διευθύνσεις", addresses), Piraeus ("Ταχυδρομικές Διευθύνσεις", postal addresses), Keratsini-Drapetsona ("Διευθύνσεις Κτηρίων", building addresses), Agrinio ("Αρίθμηση Διευθύνσεων ΚΑΕΚ", address numbering by cadastral code) | The municipalities, on data.gov.gr | Catalogue search: https://data.europa.eu/api/hub/search/search?q=%CE%B4%CE%B9%CE%B5%CF%85%CE%B8%CF%8D%CE%BD%CF%83%CE%B5%CE%B9%CF%82&filter=dataset&facets=%7B%22country%22%3A%5B%22gr%22%5D%7D | Municipal address layers. More exist under "Αρίθμηση Οδών" (street numbering) for Agia Paraskevi, Piraeus, Ilion, Chania, for Vari-Voula-Vouliagmeni, and Thessaloniki's "Ενδεικτική Αρίθμηση" (indicative numbering) | Each record lists CSV, GeoJSON, KML, SHAPE-ZIP and WMS; files not opened | Not checked | Not checked | confirmed (listing only) |
| Αναζήτηση Ταχυδρομικών Κωδικών & Διευθύνσεων (postcode and address search) | ΕΛΤΑ (Hellenic Post) | https://postalcodes.elta.gr/ | Postcode look-up | Web search form behind Google reCAPTCHA; no file download | "Copyright © Ελληνικά Ταχυδρομεία (ΕΛΤΑ)" | Not stated | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Greece | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Greek countrywide source | OpenAddresses | Source file: https://github.com/openaddresses/openaddresses/blob/master/sources/gr/countrywide.json ; method: https://github.com/openaddresses/openaddresses/blob/master/scripts/gr/README.md ; downloads: https://batch.openaddresses.io | The Cadastre points joined to the 326 "Kallikratis" municipality polygons of the Ministry of Environment and Energy. Columns `STREET, NUMBER, CITY, MUN_CODE, LON, LAT`; about 2.29 million rows (publisher's figure) | Free download; needs a logged-in account | CC BY 4.0 | Source added 2026-09-29 in a single commit | confirmed |

### Free APIs and services

- None for the Cadastre street file. Its portal record lists only the shapefile zip and a "Download All" zip (60,775,528 bytes); no API and no WFS.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.
- The municipal address layers on data.gov.gr list a WMS each, next to file downloads. None was called.
- ELTA's postcode search at https://postalcodes.elta.gr/ is a web form behind reCAPTCHA, not an API.

### Caveats and recent changes

- The Cadastre file is not an address register. It holds what owners declared when the National Cadastre was compiled. It has no municipality, no settlement, no postcode and no identifier.
- The data is older than the portal record suggests. The record dates from 2026-02-03, the shapefile parts from 2023-11-20, the embedded metadata from 2025-04-11.
- Coverage by region was not measured. The file's bounding box spans the whole country.
- House number: in the first 400,000 records `NUM` is filled in 344,555 (86.1%). About 1% of those 400,000 (3,971) carry a number of 8 or more digits, such as "0165493431". OpenAddresses reports the same defect ("anomalously long numeric strings") and reads it as another identifier leaked into the field. Filter these out.
- Street names are in Greek capitals, often abbreviated ("ΕΘΝ.ΑΝΤΙΣΤΑΣΗΣ", "ΤΡΙΚΟΥΠΗ Χ."). There is no Latin transliteration.
- Coordinate system: the `.prj` names Greek Grid on GGRS 1987 (ΕΓΣΑ87) and carries no EPSG number. That system is EPSG:2100.
- The portal's link checker marks the shapefile resource "broken: 401 UNAUTHORIZED". The mark dates from 2026-02-03, the day of publication, and was not re-run. The download worked on 2026-11-11.
- Licence: CC BY 4.0 sits on the resources; the dataset-level licence field is empty. The embedded metadata refers to the Cadastre's terms of use and also says "no limitations on public access". The data.gov.gr terms (https://data.gov.gr/en/pages/terms-of-use , text in Greek) give free access without registration, fee or justification, and allow reuse for any lawful purpose, including commercial use.
- The file is flagged as an EU High-Value Dataset under the top category "Geospatial", not under "Addresses". data.europa.eu lists no Greek dataset under HVD "Addresses" (count 0 on 2026-11-11).
- Background: a Eurostat document on the 2011 census says there was no registry of buildings or addresses (https://ec.europa.eu/eurostat/statistics-explained/SEPDF/cache/75998.pdf). A 2020 EU factsheet says only one location register, cadastral parcels, had been implemented (https://interoperable-europe.ec.europa.eu/collection/elise-european-location-interoperability-solutions-e-government/solution/lifo-location-interoperability-framework-observatory/document/lifo-2020-greece-country-factsheet).
- A third-party article of 2018 says ELTA, as universal service provider, processes and manages the country's postcodes (https://www.odigostoupoliti.eu/taxydromikoi-kodikes-epexergasia-diaxeirisi-axiopoiisi/). The ministerial decision itself was not read.

### Not free or not available

- National address register: none found. Searched: data.gov.gr for "διευθύνσεις" (2,430 hits) and "αρίθμηση οδών" (8 hits), which list only municipal layers and the Cadastre file; data.europa.eu for Greek "INSPIRE Addresses"; one web search in Greek for a national address register or a project to build one. Not searched: geodata.gov.gr (connection timed out) and ELSTAT (census building data).
- INSPIRE Addresses dataset: none found in the same searches.
- Open postcode file: none found. ELTA offers only the look-up form. OpenAddresses' maintainers report "no open national postal-code dataset" after checking GeoNames, DataHub and the Greek and EU catalogues; no further search for one was made. GeoNames (https://download.geonames.org/export/zip/) has no postcode file for Greece.
- Overture Maps addresses (release 2026-10-21.0): no Greek data.

### Could not be verified

- The Hellenic Cadastre's own terms of use, https://www.ktimatologio.gr/oroi-xrisis , and its open-data portal, https://data.ktimatologio.gr/ : both return HTTP 403. The CC BY 4.0 licence on data.gov.gr is confirmed; whether the Cadastre's terms add conditions is not known.
- Whether INSPIRE data from the Cadastre needs an application: the gov.gr page said to state this, https://www.gov.gr/en/org/ktimanet/ktematographese/geopule-geokhorikon-dedomenon-inspire-ellenikou-ktematologiou , returns HTTP 403.
- Which regions are thin or missing in the Cadastre file: not measured.
- Content, licence and age of the municipal address layers: the files were not opened.

## Hungary (HU)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | GISCO Address API (Eurostat; data credited to Lechner Tudásközpont) | Keyless lookup API; GeoPackage on GISCO, contents unchecked | None stated; reuse terms unchecked | Yes; degrees, CRS not stated | Yes | Not known; GeoPackage dated 7 Mar 2026 |

**In short.** No Hungarian portal offers an address download: the national register, the *Központi Címregiszter* (KCR, Central Address Register), may by law be passed only to listed public bodies. The one free route to official house-number data is Eurostat's GISCO: its Address API returns Hungarian addresses with house number, postcode and coordinates, credited to the state body Lechner Tudásközpont, and GISCO's public directory holds a 146 MB GeoPackage of Hungarian addresses. The trip-up is that the GeoPackage's contents and date, and any terms for reusing the Hungarian data, were not checked, and the API is lookup-only. For postcodes alone, Magyar Posta's spreadsheet and the statistical office's gazetteer are free downloads.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Központi Címregiszter (KCR) | State register; operator's website not located | Rules: https://njt.jog.gov.hu/jogszabaly/2024-322-20-22 (Chapter XIX, § 122 onward) | By law: country, county, settlement, postcode, settlement part, district, street name and type, house number, building, staircase, floor and door, plus address coordinates, land-registry identifier and a unique ID | No public download, API or catalogue listing | Not open | - | none found |
| Postcode spreadsheet | Magyar Posta | https://www.posta.hu/static/internet/download/Iranyitoszam-Internet_uj.xlsx | Sheet "Települések": 11,160 rows of postcode, settlement, settlement part. Sheet "Bp.u.": 9,701 Budapest rows of postcode, street name and type, city part, house-number range, district. Street sheets for Miskolc (1,315), Debrecen (2,213), Szeged (1,687), Pécs (1,464), Győr (1,022). No coordinates, no single house numbers | Anonymous download, 1,019,747 bytes | None found | File last modified 12 Oct 2026 | confirmed |
| Gazetteer "Helységnévtár" | Központi Statisztikai Hivatal (KSH, statistical office) | https://www.ksh.hu/docs/helysegnevtar/hnt_letoltes_2026.xlsx (application: https://www.ksh.hu/apps/hntr.main) | Sheet "Helységek 2026.01.01.": 3,182 rows with settlement name, KSH code, legal status, county, district, area, population, dwellings. Sheet "Településrészek 2026.01.01.": 13,723 rows of settlement parts with a postcode column. No streets or house numbers | Anonymous download, 1,377,826 bytes | Not checked | File last modified 7 Oct 2026; state of 1 Jan 2026 | confirmed |
| GISCO Address API | Eurostat; Hungarian data credited "© Lechner Tudásközpont" | https://gisco-services.ec.europa.eu/addressapi (credits: https://gisco-services.ec.europa.eu/addressapi/copyright) | Hungarian addresses with house number, street, settlement, postcode and coordinates. A search for country HU, postcode 2000 returned 100 records | No key; lookup only, 1,000-row cap, no bulk download | None stated | Not known | confirmed |
| GISCO-hosted Hungarian address file | Eurostat (GISCO public directory) | https://gisco-services.ec.europa.eu/pub/Inspire/ANNEX-1/Addresses/HU/Derived/2026/HU_MST_PC_A.gpkg | GeoPackage, 145,772,544 bytes. A 2023 edition of 505 MB sits beside it. The directory's metadata sheet for Hungary (`Addresses/Metadata/HU.pdf`, dated 12 May 2023) maps source fields for street name, house number from/to, postcode and settlement | Anonymous download (file not opened) | Not checked | File last modified 7 Mar 2026 | confirmed that the file exists; contents and terms unverified |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key. Its `search` call with `country=HU&postcode=2000` returned records such as house number 2, street "ÁBRÁNYI EMIL", settlement "SZENTENDRE", postcode 2000, coordinates [19.0769792, 47.6745707]. Lookup only.
- **Magyar Posta postcode lookup:** https://www.posta.hu/szolgaltatasok/iranyitoszam-kereso redirects to an interactive page at `net.posta.hu/dashboard/public/dashboard-ui/iranyitoszam-kereso`. It is a web application, not a documented API.
- **KSH gazetteer application:** https://www.ksh.hu/apps/hntr.main .
- **KSH high-value dataset APIs:** https://www.ksh.hu/hvd_eng . These serve statistics, not addresses.
- **Public lookup or API for KCR:** none found.

### Caveats and recent changes

- KCR's original decree, 345/2014. (XII. 23.) Korm. rendelet, was repealed with effect from 7 November 2024. The rules are now Chapter XIX of 322/2024. (XI. 6.) Korm. rendelet.
- § 127 of that decree lets address data go by automatic transfer to the population and address registry, the land authority, the public-building cadastre operator, the Smart City platform operator, the tax authority, KSH and bodies obliged to provide digital services. The postal operator may see addresses for its own tasks but may not pass them on. The chapter has no wording on public access, public queries or fees.
- The only publication duty is local: addresses affected by an address procedure are posted on the municipality's website or notice board for at least one month (§ 129(6)).
- The GISCO route is official-source data, but it is not published by any Hungarian portal. Check the reuse terms and the date of the data before relying on it.
- Magyar Posta's spreadsheet gives street-level postcodes only for Budapest and five cities, as house-number ranges.
- Magyar Posta publishes no licence for the spreadsheet that could be found. A third-party note says the file is listed on Magyar Posta's site under public-interest data and treats the licence as unresolved (https://datahub.io/logistics/postal-codes-hu/.licensing-notes).
- High-value datasets: on data.europa.eu, none of the 2,283 Hungarian datasets carries the high-value flag, and none is in the category "Addresses" (11 Nov 2026).
- The register was built in a 2012-2015 project that replaced overlapping address databases; Lechner Tudásközpont's predecessor and Magyar Posta were in the consortium (https://lechnerkozpont.hu/en/node/568).

### Not free or not available

- **KCR itself:** no public download, API or open-data listing found. Searched: the governing decree; the national open data portal kozadatportal.hu (2,283 datasets; searches for "cím", "címek", "címregiszter", "irányítószám", "házszám", "utca", "address", "KCR" and wildcard title searches found no address dataset); data.europa.eu; and Lechner's national INSPIRE catalogue.
- **INSPIRE Addresses dataset or service:** none found in the national INSPIRE catalogue (https://inspire.lechnerkozpont.hu/geonetwork/srv/eng/csw , 308 records). An ATOM feed exists for administrative units; the matching address feed name returns 404.
- **OpenAddresses:** no Hungarian source.
- **Overture Maps addresses:** Hungary is not covered.
- **Voter-register address data (National Election Office):** released only to candidates and nominating organisations, for campaigning, for a fee (https://www.valasztas.hu/en/szavazokori-nevjegyzeki-adatok-igenylese-jeloltek-partok-reszere).

### Could not be verified

- The GISCO GeoPackage: its contents, the date of the data in it, and GISCO's reuse terms for the Hungarian data. Only the file's existence, size and date were checked.
- Whether a public KCR lookup or a paid data-supply service exists: one web search found only legal texts, a 2015 project leaflet and municipal notices. The search was not exhaustive.
- Magyar Posta's terms of use for the spreadsheet: no terms page was found.
- The licence of the KSH gazetteer: not checked.
- Municipal open address datasets: not searched beyond the national portal, where none appeared.
- Whether the election office currently publishes a downloadable street list: not checked.
- The EU INSPIRE Geoportal's record for Hungary: the site presented an expired TLS certificate and was not opened.

## Ireland (IE)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| No | None national; Tailte Valuation API covers rateable property only | API with CSV, JSON or GeoJSON output | CC BY 4.0 (Valuation API) | Valuation API only; ITM X/Y | Eircode, on rateable property only | Continuous (Valuation API) |

**In short.** No free national address dataset was found for Ireland. The two national address databases, Eircode (products ECAF and ECAD) and GeoDirectory, are paid, licensed products. What is free and official is partial: the Tailte Éireann Valuation API (address text, Eircode and ITM coordinates for rateable, mostly commercial, property in every county), the Eircode Finder web lookup (15 searches a day, non-commercial), and a national building-outline layer with no address fields. The trap is to expect the EU-wide collections to fill the gap: the GISCO Address API, OpenAddresses and Overture all have nothing for Ireland.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| ECAF (Eircode Address File) and ECAD (Eircode Address Database) | Eircode | https://www.eircode.ie/business/products-and-services | ECAF: "over 2.2 million address points with their Eircode and USP Postal Address" (publisher's figure). ECAD adds alias addresses, geo-coordinates, boundary and building information | Paid annual licence; not free | Eircode Provider Licence or Direct End User Licence | Not stated | confirmed |
| GeoDirectory | An Post and Tailte Éireann (jointly developed) | https://www.geodirectory.ie/knowledge-centre/faqs | "Over 1.9 million buildings and 2.3 million addresses" (publisher's figure) | Paid; no free trial | Commercial | Not stated | confirmed |
| Valuation API | Tailte Éireann | Publisher page: https://tailte.ie/home/api/ ; catalogue record: https://data.gov.ie/dataset/valuation-office-api | Per rateable property: county or local authority, category, use, floor areas and uses, address, Eircode, publication date, valuation figures, property number, X ITM and Y ITM. Covers 28 named rating authority areas plus limited data for Cork City and County, which together is every county | API Explorer; output CSV, JSON or GeoJSON | CC BY 4.0 | Continuous | corrected |
| High Value Dataset - Buildings | Tailte Éireann | Dataset: https://data-osi.opendata.arcgis.com/datasets/osi::high-value-dataset-buildings ; layer: https://services-eu1.arcgis.com/FH5XCsx8rYXqnjF5/arcgis/rest/services/Buildings/FeatureServer/0?f=json | 3,785,414 building polygons with the fields `GUID`, `OBJECTID`, `Shape__Area`, `Shape__Length` only. No address, Eircode or use attribute | Download as CSV, GeoJSON, KML, File Geodatabase, GeoPackage and more; REST API | CC BY 4.0 | Issued 9 Jan 2026 | confirmed |
| Tailte Éireann open data portal | Tailte Éireann | Portal: https://data-osi.opendata.arcgis.com/ ; feed: https://data-osi.opendata.arcgis.com/api/feed/dcat-us/1.1.json ; terms: https://tailte.ie/services/open-data/ | 178 datasets; 15 are titled "High Value Dataset - ..." (buildings, cadastral parcels, sites, locales, ways, rail, water, land cover). None is an address dataset | Open download | CC BY 4.0; free to use with attribution to Tailte Éireann | 14 of the 15 issued 2026-01-09; "National Land Cover 2018" issued 2023-05-25 | confirmed |
| Point-of-interest lists with an Eircode column | Various public bodies, on data.gov.ie | https://data.gov.ie/dataset?q=eircode | 17 small lists (enterprise centres, Garda and fire stations, schools, recycling centres, polling stations). Not an address register | Open download | Per dataset | Per dataset | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses; the Irish file is partial | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **Tailte Éireann Valuation API.** https://tailte.ie/home/api/ . Returns address text, Eircode and ITM X/Y for each rateable property, as CSV, JSON or GeoJSON. Coverage is national for rateable property; Cork City and County return fewer fields. The data.gov.ie record flags it as a High-Value Dataset under Regulation 2023/138. This describes the publisher's page; the API itself was not called.
- **Eircode Finder.** https://finder.eircode.ie . A web lookup, not a dataset. Limited to 15 searches a day and not for commercial use, per Eircode's FAQ (https://www.eircode.ie/faqs).
- **HVD Buildings feature service.** https://services-eu1.arcgis.com/FH5XCsx8rYXqnjF5/arcgis/rest/services/Buildings/FeatureServer/0/query?where=1%3D1&returnCountOnly=true&f=json returns the count; geometry only.
- **GeoFindIT.** GeoDirectory's free app; an app, not data.

### Caveats and recent changes

- **The Valuation API is not an address register.** It lists rateable, mostly commercial, property. Residential addresses are not in it.
- **Not every property has an Eircode.** Tailte notes that "some property categories are not assigned an Eircode as properties must have a postal address". Errors in a record's X and Y or Eircode are reported to opendata@tailte.ie.
- **The High-Value Dataset release of January 2026 did not include addresses.** It covers building polygons, cadastral parcels and other topographic layers. A search of all 178 portal datasets for address, eircode, geodirectory, postal and postcode matched only four "Small Areas" boundary sets whose text mentions GeoDirectory.
- **The Eircode Finder limit of 50 a day seen in older texts was a Christmas 2019 promotion.** The standing limit is 15.
- **Requests to open the Eircode database have not succeeded.** A data.gov.ie suggestion for a "Database of valid Eircodes and / or a validation API" (https://data.gov.ie/ga/dataset/suggest/40acc585-4ca5-4b4f-9332-f2d954c935ab) is closed without a release.
- **No free national address register: none found.** Searched: the data.gov.ie catalogue (queries "eircode", "geodirectory", "address register", "addresses", "address points", "postal address"), the Tailte portal feed, data.europa.eu for Ireland (including INSPIRE addresses), OpenAddresses and the GISCO Address API.

### Not free or not available

- **Eircode ECAF and ECAD.** Sold under annual licence, either directly (Direct End User: internal use only, no sharing or resale) or through approved Eircode Providers. ECAF must be bought before ECAD. All licences and data fees are one-year contracts with monthly usage returns.
- **Eircode prices.** The only price list Eircode links from its product page is https://www.eircode.ie/files/eircode-pricing-information.pdf , headed "Pricing effective from March 2015" (PDF file last modified 15 Nov 2022). ECAF: EUR 60 per user for 1-83 users, EUR 5,000 single fee for 84 or more; EUR 4 per block of 100 transactions; website use EUR 3,000; group EUR 25,000. ECAD: annual data access fee EUR 1,000 (Eircode Provider) or EUR 500 (Direct End User), plus EUR 180 per user (1-10 users) falling to EUR 100 (101-262 users), capped at EUR 30,000, or EUR 0.050 down to EUR 0.010 per transaction; website fee EUR 30,000; group fee EUR 50,000.
- **GeoDirectory.** "We do not currently offer a free trial." No published prices were found: its FAQ page gives only a contact address for "pricing packages"; other GeoDirectory pages were not searched.
- **GISCO Address API (Eurostat), https://gisco-services.ec.europa.eu/addressapi :** does not serve Ireland.
- **OpenAddresses, https://batch.openaddresses.io :** has no Ireland source.
- **Overture Maps addresses (release 2026-10-21.0):** no Irish addresses.

### Could not be verified

- **Two parliamentary answers.** One of April 2025 (https://www.oireachtas.ie/en/debates/question/2025-04-29/257) is said to state that new Eircodes are published on the free Eircode Finder while licensed businesses receive the database files. One of December 2023 (https://www.oireachtas.ie/en/debates/question/2023-12-12/122/) is said to state a three-year extension of the Eircode contract with Capita, notified in March 2023. Both pages refused the request.
- **Who operates Eircode and GeoDirectory, and Tailte Éireann's predecessors.** That Eircode is operated by Capita, that GeoDirectory is operated by An Post GeoDirectory DAC, and that Tailte Éireann succeeded OSi, the Valuation Office and the Property Registration Authority do not appear on the publisher pages read.
- **The live allowance the Eircode Finder app applies.** The 15 a day comes from Eircode's FAQ; the app's own session value was not read.
- **Prices actually quoted by Eircode in 2026.** Only the published March 2015 list was read.
- **Valuation API in practice.** Field content and coverage come from the publisher's page; no API call was made, so key requirements, limits and data quality are not established.
- **Property Price Register.** It holds sale records with addresses; on data.gov.ie only a Dublin extract (CC-BY-4.0) was seen and it was not examined.
- **Logainm and CSO sources:** not checked.
- **Why addresses are absent from Ireland's High-Value Dataset release,** and any plan to open Eircode: no official statement was looked for.
- **How many data.gov.ie suggestions ask for open Eircode data:** only one was opened.
- **OpenStreetMap as a fallback for house-number addresses:** Irish coverage was not measured.

## Italy (IT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | ANNCSU (ISTAT and Agenzia delle Entrate) | bulk CSV in ZIP, no registration | CC BY 4.0 | yes, lon/lat ETRF2000, on 67.0% of rows (31/03/2026) | no | monthly |

**In short.** Use ANNCSU (Archivio Nazionale dei Numeri Civici delle Strade Urbane, the national archive of urban street civic numbers): one national CSV of civic numbers, rebuilt monthly, CC BY 4.0, plain download without registration. Two things trip up an import. Coordinates exist only where the municipality entered them, officially 67.0% of accesses at 31/03/2026 and very uneven between municipalities. And the file has no postcode (CAP): bulk CAP data remain a paid Poste Italiane product. Regional and municipal datasets exist for several areas; Bologna's also carries postcodes.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| ANNCSU indirizzario (address list), national file | ISTAT and Agenzia delle Entrate | https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/getds.php?INDIR_ITA ; description: https://www.anncsu.gov.it/it/consultazione-dellarchivio/open-data/ | Every civic number ("access") in the archive: municipality codes, national street id, street name (also bilingual), national access id, civic number, exponent, lon/lat where present, coordinate method. No postcode | `indirizzarioItalia.zip`, 336,334,007 bytes, holding `INDIR_ITA_20261102.csv` (2,206,534,790 bytes). Plain GET, no registration, key or referer | CC BY 4.0 (stated in the catalogue record https://data.europa.eu/api/hub/search/datasets/age-strad_ind_italia~~1 , not on the ANNCSU pages) | Monthly. File dated 2026-11-02 | confirmed; row count unverified |
| ANNCSU stradario (street directory), national file | ISTAT and Agenzia delle Entrate | https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/getds.php?STRAD_ITA | Streets with their national id and the number of accesses per street (`TOTALE_ACCESSI`) | `stradarioItalia.zip`, 13,920,082 bytes, holding `STRAD_ITA_20261102.csv`. Plain GET | CC BY 4.0 | Monthly | confirmed |
| ANNCSU regional files | ISTAT and Agenzia delle Entrate | https://www.anncsu.gov.it/it/consultazione-dellarchivio/open-data/Accedi-ai-servizi-di-dowload-massivo-in-Open-data/ ; example: https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/getds.php?INDIR_VALL | The same address and street files cut per region: 20 pairs with the codes ABRU, BASI, CALA, CAMP, EMIL, FRIU, LAZI, LIGU, LOMB, MARC, MOLI, PIEM, PUGL, SARD, SICI, TOSC, TREN, UMBR, VALL, VENE | Plain GET. Lombardia address file: 36,906,989 bytes | CC BY 4.0 | Monthly | confirmed |
| CAP (postcode) database | Poste Italiane | https://business.poste.it/business/files/1473808238165/banchedati-faq-cap.pdf | Complete postcode files | Not free. Only lookup tools are free; CAP Professional (MS Access) and CAP Zone (shapefile) are sold | Proprietary | - | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Forward and reverse lookup of Italian addresses: house number, street, city, postcode, coordinates. Declared source: "© Geoportale nazionale" | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Not stated | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/it/countrywide.json | Countrywide layer from ANNCSU without postcodes, plus about 38 further Italian source files | Free download, needs a logged-in account | CC-BY 4.0, attribution "Istat e dall'Agenzia delle Entrate" | Cached file `INDIR_ITA_20260703_GEO.csv`; last successful run 2026-08-14 | confirmed |
| Overture Maps addresses, release 2026-10-21.0 | Overture Maps | https://docs.overturemaps.org/guides/addresses/ | 26,841,754 Italian addresses (publisher's figure), from ANNCSU | GeoParquet, no account | CC BY 4.0 (ANNCSU) | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | ZIP file per country | CC BY 4.0 | Regenerated daily | confirmed |

### Regional sources

| Region | Source | Link | Access | Licence | Check |
|---|---|---|---|---|---|
| Alto Adige / Südtirol | Address layer `gvcc-Address:Addresses`, Provincia di Bolzano | https://geoservices3.civis.bz.it/geoserver/gvcc-Address/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=gvcc-Address:Addresses&SRSNAME=EPSG:4326&outputFormat=JSON&count=1 | WFS, no key. 145,190 address points with German and Italian street and municipality names, house number, ISTAT and Belfiore codes; EPSG:4326 output | CC0 as recorded by OpenAddresses (https://github.com/openaddresses/openaddresses/blob/master/sources/it/32/south-tyrol-it.json); the publisher's own statement was not checked | corrected |
| Toscana | ITER.NET road graph, SHP, v. 4.48 of June 2022, Regione Toscana | https://www502.regione.toscana.it/geoscopio/download/grafo_stradale/ | Single ZIP `iternet.zip`. The page does not say whether the package contains civic numbers; the ZIP was not opened | CC BY 4.0 | confirmed |
| Emilia-Romagna | DBTR - Civico (NCV_GPT), civic numbers of the regional topographic database | https://data.europa.eu/api/hub/search/search?q=civici%20DBTR&filter=dataset&limit=14 ; download page: https://geoportale.regione.emilia-romagna.it/download/download-data?type=dbtopo | Catalogue record with six distributions, modified 2025-08-31. The geoportal download page returned HTTP 500 on 2026-11-11 | CC BY 4.0 | confirmed (catalogue); download page unverified |
| Friuli Venezia Giulia | Numeri Civici Ascot 2024 (civic numbers) | https://www.dati.friuliveneziagiulia.it/Regioni-e-citt-/Numeri-Civici-Ascot-2024/fcre-uegn | Regional open data portal. Rows last updated 2024-09-30 | Italian Open Data License 2.0 (IODL 2.0) | confirmed |
| Liguria | `civici.zip`, Regione Liguria | https://srvcarto.regione.liguria.it/geoservices/data/open_addresses/civici.zip | Direct ZIP, 412,780 bytes, last modified 6 December 2017. Too small for a region-wide file; content not inspected, treat as stale or partial | CC BY 3.0 IT as recorded by OpenAddresses (https://github.com/openaddresses/openaddresses/blob/master/sources/it/42/statewide.json) | confirmed (file exists) |
| Sicilia | Carta tecnica numerica scala 1:2.000 - numeri civici (civic numbers of urban areas from the 1:2,000 technical map) | https://dati.regione.sicilia.it/dataset/carta-tecnica-numerica-scala-1-2-000-numeri-civici | GeoJSON in ZIP. Last updated 11 May 2022 | Creative Commons Attribution, version not stated | confirmed |
| Piemonte | BDTRE (Banca Dati Territoriale di Riferimento degli Enti) addresses | https://github.com/openaddresses/openaddresses/blob/master/sources/it/21/statewide.json | Known through the OpenAddresses source, whose cached copy dates from 2024-11-03. No publisher page was read | CC BY 4.0 as recorded by OpenAddresses; the national metadata record says "conditionsUnknown" | unverified |
| Lombardia | Per-province packages on the regional geoportal | https://github.com/openaddresses/openaddresses/blob/master/sources/it/25/mi.json ; package URL: https://www.geoportale.regione.lombardia.it/rlregis_download/service/package?dbId=323&cod=15 | The package URL timed out on 2026-11-11 | IODL 2.0 as recorded by OpenAddresses | unverified |
| Umbria | ArcGIS service "ECOGRAFICO_CATASTALE1_WGS84" | https://github.com/openaddresses/openaddresses/blob/master/sources/it/55/statewide.json | The host answers with a TLS certificate issued for another name; not read | Not known | unverified |
| Sardegna | Regional geoportal page | https://www.sardegnageoportale.it/index.php?xsl=1598&s=291551&v=2&c=8831&t=1 ; OpenAddresses source: https://github.com/openaddresses/openaddresses/blob/master/sources/it/88/statewide.json | The page gave an empty reply on 2026-11-11. OpenAddresses holds a cached copy from 2016 (`sardegna20160804.zip`) | IODL 2.0 as recorded by OpenAddresses | unverified (page); confirmed (OpenAddresses copy) |
| Veneto; Province of Trento | Region-wide address dataset | none | None found. Searched: data.europa.eu for civic numbers of the Veneto region and of the autonomous province of Trento. Only per-municipality datasets turned up; Regione del Veneto publishes per-municipality "Numeri civici" sets | CC BY 4.0 for the Veneto per-municipality sets | none found |
| Bologna (city) | Civic numbers `rifter_civici_pt`, Comune di Bologna | https://opendata.comune.bologna.it/api/explore/v2.1/catalog/datasets/rifter_civici_pt/records?limit=1 | API. 77,614 civic numbers with coordinates, a postcode field `cap` and an ANNCSU code `codice_ann` | Not confirmed | confirmed; licence unverified |
| Torino (city) | Civic numbers in WGS84, Comune di Torino | http://geoportale.comune.torino.it/geodati/civici_WGS84_EPSG4326_csv.csv | Direct CSV, 9,721,244 bytes, last modified 7 October 2026 | Not recorded | confirmed |
| Firenze (city) | `civici.zip`, Comune di Firenze | https://datigis.comune.fi.it/shp/civici.zip | Direct ZIP, 6,135,739 bytes, last modified 9 November 2026 | Not recorded | confirmed |
| Verona (city) | Numerazione civica Comune di Verona (civic numbering), on the Veneto portal | https://dati.veneto.it/opendata/Numerazione_civica_Comune_di_Verona | Portal page. It also says "Al momento non è possibile visualizzare il dato" (the data cannot be displayed at the moment) | CC BY 4.0 | confirmed |
| Palermo (city) | Indirizzario e stradario del Comune di Palermo - numeri civici georeferenziati (georeferenced civic numbers) | https://opendata.comune.palermo.it/js/server/uploads/dataset/csv/_01042026064924.csv | Direct CSV, 16,316,611 bytes, dated 1 April 2026 | CC BY 4.0 | confirmed |

### Free APIs and services

- **ANNCSU query API**, https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/querydata.php : JSON, no key. `?resource=odonimi&codicecomune=H501&denominazione=VIA%20MILANO` returns the street with its national id (`Progressivo_nazionale` 917411). `?resource=accessi&progressivoodonimo=917411&accesso=1` returns the matching civic numbers with `Civico`, `CoordX`, `CoordY` and `Metodo`. It works as a street-and-number lookup for one municipality at a time.
- **ANNCSU bulk download**, `getds.php` (see the table): plain GET works; `HEAD` is answered with HTTP 403.
- **Alto Adige WFS** (Provincia di Bolzano) and the **Bologna open data API**: see the regional table.
- **GISCO Address API (Eurostat)**, https://gisco-services.ec.europa.eu/addressapi : no key, lookup only. `/reverse?x=12.4894668&y=41.8997245` returned, for example, house number 3, "VIA PIACENZA", Roma, postcode "184". The postcode comes without its leading zeros (CAP 00184). The Italian data are attributed to the "Geoportale nazionale", not to ANNCSU, and their date is not given.

### Caveats and recent changes

- ANNCSU became open recently. Its open data page says Implementing Regulation (EU) 2023/138 placed addresses among the high-value datasets, and that ISTAT and the Agenzia delle Entrate adopted new technical specifications on 12 December 2024. A press report of 26/02/2025 (https://www.lavoripubblici.it/news/stampa/35094) describes the services as active, with monthly lists and point services that take up changes daily. Older descriptions of ANNCSU as not downloadable or without coordinates no longer hold.
- Coordinates are present only where the municipality entered them. Official figures at 31/03/2026 (https://www.anncsu.gov.it/export/sites/anncsu/.allegati/Georeferenziazione-accessi-ANNCSU_31-MARZO.xlsx): 7,894 municipalities, 27,487,263 accesses, 18,417,502 with coordinates (67.0%), 4,304 municipalities fully georeferenced, 5,046 with at least one coordinate. The same file gives the figures per municipality.
- Coverage is uneven. In the Valle d'Aosta file of 2026-11-02, 19,248 of 94,256 rows (20.42%) have coordinates; 20 of 74 municipalities have at least one and 9 have all.
- Rows without coordinates stay in the file, so a row count is not a count of address points.
- No postcode field exists in the ANNCSU files.
- File format: semicolon-separated, decimal comma in the coordinates (for example `13,9961659;42,219746`), `COORD_X_COMUNE` is longitude. Coordinates are decimal degrees with 7 decimals in ETRF2000 at epoch 2008.0 (an ETRS89 realisation).
- The address file has 19 columns: `CODICE_COMUNE` (Belfiore code), `CODICE_ISTAT`, `PROGRESSIVO_NAZIONALE`, `CODICE_COMUNALE`, `ODONIMO`, `LOCALITA'`, `DIZIONE_LINGUA1`, `DIZIONE_LINGUA2`, `PROGRESSIVO_ACCESSO`, `CODICE_COMUNALE_ACCESSO`, `CIVICO`, `ESPONENTE`, `SPECIFICITA`, `METRICO`, `PROGRESSIVO_SNC`, `COORD_X_COMUNE`, `COORD_Y_COMUNE`, `QUOTA`, `METODO`. The published description (https://www.anncsu.gov.it/.allegati/metadata_indirizzario.json) documents only 18: it omits `LOCALITA'`, which is described in https://www.anncsu.gov.it/.allegati/metadata_stradario.json .
- `METODO` gives the coordinate method: 1 field survey with accuracy under 5 m, 2 field survey at 5 m or worse, 3 indirect derivation from a territorial database under 5 m, 4 indirect derivation at 5 m or worse, 5 derived through the municipalities' portal. The query API's help text gives an estimated accuracy of 2 m or worse for code 5.
- The national access id never changes, even when the civic number or street name does. Coordinates are not kept historically.
- The files include "SNC" accesses (senza numero civico, without a standard civic number) that municipalities entered in 2014-2016.
- The file name carries the creation date (`INDIR_ITA_20261102.csv`).
- The regional code `TREN` is the whole Trentino-Alto Adige region, not the Province of Trento.
- Licence: CC BY 4.0 is stated in the catalogue record (publisher Agenzia delle Entrate, 42 distributions, flagged high-value dataset, monthly) and in the press report, with citation of the source required. The ANNCSU site's own open data and download pages carry no licence statement.
- A third-party slide of July 2025 gives "4.9% with coordinates" without a reference date. It does not fit the official 67.0% at March 2026, so no growth rate should be read from it.
- OpenAddresses' Italian layer rests on the ANNCSU file of 2026-07-03; its later runs did not succeed.
- Bologna's municipal file carries both a postcode and the ANNCSU code, so it can be joined to the national file.
- The Poste Italiane statement on CAP data dates from June 2019; current prices and terms were not examined.
- Lombardia: data.europa.eu lists per-municipality datasets "Rete stradale - Numeri civici esterni georeferenziati" (road network - georeferenced external civic numbers) by Regione Lombardia under CC0.

### Not free or not available

- Bulk postcode (CAP) data: not free. Poste Italiane states that the CAP database is its property and cannot be downloaded free of charge. No open bulk CAP dataset was found; the GISCO Address API returns a CAP per address, as a lookup only.
- Coordinates for about a third of ANNCSU accesses (official figure at 31/03/2026): not in the file.
- Region-wide open address datasets for Veneto and the Province of Trento: none found (see the regional table).
- The list of municipalities that have not finished loading streets and civic numbers into ANNCSU: the site fills it in by script and it was not read.

### Could not be verified

- Counts in the national file of 2026-11-02: 27,413,752 rows, 20,728,959 (75.62%) with coordinates, 818,455 SNC rows, 7,891 municipality codes (5,502 with at least one coordinate, 4,454 with all), and the split by method (10,892,898 method 4; 7,118,388 method 3; 1,721,955 method 1; 705,060 method 5; 290,658 method 2). These are a researcher's count; the 336 MB file was not downloaded a second time. The official March 2026 figures above are consistent with the trend.
- Rate limits or terms of use for `querydata.php`: none were found, and the question was not examined a second time.
- Emilia-Romagna: that the DBTR civic numbers can be downloaded from the geoportal page, which returned HTTP 500.
- Piemonte: the publisher's licence for BDTRE addresses. CC BY 4.0 is OpenAddresses' record only.
- Lombardia: the per-province packages; the URL timed out after 45 s.
- Umbria: the ArcGIS service; the certificate does not match the host name.
- Sardegna: the geoportal page; empty reply from the server.
- Bologna: the licence (given as CC BY 4.0) is not in the API response.
- Alto Adige: the publisher's own licence statement; CC0 is OpenAddresses' record.
- Toscana: whether the ITER.NET package contains civic numbers.
- Liguria: what `civici.zip` contains.

## Latvia (LV)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Valsts adrešu reģistrs open data on data.gov.lv (VZD) | Bulk CSV and shapefile, no registration | CC BY 4.0 | Yes, LKS-2020 TM plus decimal degrees | Yes | Daily |

**In short.** Download the open data of the Valsts adrešu reģistrs (State Address Register) from data.gov.lv: full CSV and shapefile dumps, anonymous, refreshed every day, CC BY 4.0, with a postcode column and coordinates. The trap is a fresh breaking change: on 7 October 2026 the projected coordinates (`KOORD_X`, `KOORD_Y`) switched from LKS-92 TM to LKS-2020 TM. A second, smaller one: the CSV metadata declares ISO-8859-1, but the file is UTF-8 with a byte-order mark.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| "Valsts adrešu reģistra atvērtie dati" (State Address Register open data; the register's information system is abbreviated VARIS) | Valsts zemes dienests (VZD, State Land Service) | Dataset: https://data.gov.lv/dati/lv/dataset/varis-atvertie-dati ; portal API record: https://data.gov.lv/dati/api/3/action/package_show?id=varis-atvertie-dati ; building addresses: https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/a510737a-18ce-400f-ad4b-04fce5228272/download/aw_eka.csv ; spatial data: https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/b643b1b3-223f-4394-9beb-18524f8b0b82/download/aw_shp.zip ; column metadata: https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/27ab50ae-95ae-46be-88c8-d54d4b4c70b5/download/aw_eka_metadata.json | Denormalised register data, 41 resources. Sizes on 2026-11-11: `aw_eka.csv` (addresses of buildings and of parcels intended for building) 141,795,733 bytes; `aw_dziv.csv` (premises groups, the apartment-level file) 142,907,077; `aw_iela.csv` (streets) 3,337,988; `aw_ciems.csv` (villages) 1,676,792; historic files `aw_eka_his.csv` 192,426,240 and `aw_dziv_his.csv` 215,129,843; `aw_shp.zip` (spatial data, including administrative boundaries) 52,584,597; document-metadata files `aw_doc_nl.csv` 127,554,609 and `aw_doc_tg.csv` 95,137,603. Also cities, municipalities, parishes, historic districts, the link of Riga addresses to city districts, place centroids. `aw_eka.csv` has 611,370 rows (researcher's count, not recounted) | Anonymous. Direct URL pattern `https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/{resource-id}/download/{file}`; HTTP 200 without login | CC BY 4.0 | Daily. Every data resource was stamped 2026-11-11 04:41-04:42 | confirmed |
| "Adreses (INSPIRE)" on geolatvija.lv | VZD | Portal record: https://data.gov.lv/dati/api/3/action/package_show?id=adreses-inspire ; product page: https://geolatvija.lv/main?geoproduct=open&geoProductId=291 ; ATOM feed: https://geolatvija.lv/api/v1/atom/c38d1733-cbc0-48d2-b5d2-1a906a0b9570/serviceatoma ; bulk file: https://geolatvija.lv/api/v1/atom/24650aed-1f3b-4090-81de-aa4346c0ca44/file | INSPIRE Annex I addresses as a WFS download service, a WMS view service and a bulk ATOM feed. The feed offers `adAddressesLV.zip`, 66,096,373 bytes, CRS category EPSG:4258 | ATOM feed and bulk file: no key, no login. WFS and WMS: access not tested | CC BY 4.0 per the portal record. The feed's own rights line is boilerplate: "(c) COPYRIGHTS 2014, INSPIRE; all rights reserved" | Weekly per the portal record; the feed itself is stamped 2024-06-07 | confirmed |
| Official postcode file from Latvijas Pasts (the postal operator) | - | - | None found. A data.gov.lv search for "pasta indeksi" returned 0 datasets; Latvijas Pasts' own site was not checked. Postcodes are inside the VZD data (column `ATRIB`) | - | - | - | none found |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Latvia | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Latvia countrywide | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lv/countrywide.json | Built from the official `aw_shp.zip` | Free download, needs a logged-in account | CC-BY 4.0, attribution "Valsts zemes dienests" | Not stated | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Latvia is among the 19 EU countries covered | No account, GeoParquet | Per country | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **data.gov.lv portal API** (https://data.gov.lv/dati/api/3/action/package_show?id=varis-atvertie-dati): keyless. It lists every resource with its size and `last_modified` stamp, so a script can find the current file URLs and see when they changed.
- **INSPIRE WFS, WMS and ATOM on geolatvija.lv** (https://geolatvija.lv/main?geoproduct=open&geoProductId=291): the ATOM feed and its bulk zip answered without a key. The WFS and WMS endpoints were not tested.
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.
- A national address-search or geocoding API: none identified; it was not specifically searched for.

### Caveats and recent changes

- **Coordinate system changed on 7 October 2026.** The dataset's change log reads "07.10.2026 – transformētas koordinātas no LKS-92 TM uz LKS -2020 TM" (coordinates transformed from LKS-92 TM to LKS-2020 TM). `KOORD_X` and `KOORD_Y` are now the object's centroid in LKS-2020. Code that still treats them as LKS-92 TM now reads a different reference system, and nothing in the file format signals it. The file also carries decimal degrees in `DD_N` and `DD_E`.
- **Encoding.** The CSV metadata declares `ISO-8859-1`, but `aw_eka.csv` starts with a UTF-8 byte-order mark (`EF BB BF`) and decodes as UTF-8 with Latvian diacritics intact. Read it as UTF-8.
- Columns of `aw_eka.csv`: `KODS` (object code), `TIPS_CD`, `STATUSS`, `APSTIPR`, `APST_PAK`, `VKUR_CD` and `VKUR_TIPS` (parent object), `NOSAUKUMS` (name or number), `SORT_NOS`, `ATRIB` (postcode, for example LV-4211), `PNOD_CD` (post office service-area code), `DAT_SAK`, `DAT_MOD`, `DAT_BEIG`, `FOR_BUILD`, `PLAN_ADR` (planned address), `STD` (full address string), `KOORD_X`, `KOORD_Y`, `DD_N`, `DD_E`.
- The file is not only live addresses. It has a status column (`STATUSS`, value `EKS` seen for existing objects) and includes parcels intended for building (`FOR_BUILD`). Filter before import.
- Other entries in the change log: 24.07.2025, three document-metadata resources added; 13.06.2025, new columns in the Riga district link file (`PPILS.csv`).
- The portal record was issued on 2021-12-27 and last modified on 2026-10-07.
- High-value dataset: the CSV metadata carries the keyword "Augstvērtīga datu kopa" (high-value dataset), data.europa.eu flags the dataset `is_hvd: true`, and the portal record names Implementing Regulation (EU) 2023/138 as applicable legislation.
- The INSPIRE bulk file on geolatvija.lv may be old: the portal record says weekly, but the feed is stamped 2024-06-07. Prefer the daily data.gov.lv files.
- File sizes move from day to day as the register changes (by under 1 KB between 2026-11-10 and 2026-11-11).

### Not free or not available

- A free official bulk postcode file from Latvijas Pasts: none found (data.gov.lv search for "pasta indeksi": 0 results; Latvijas Pasts' site not checked). Postcodes come with each address in the VZD data.
- No paid address product was found; the full register is free and anonymous.

### Could not be verified

- Everything that rests only on VZD's own site, because www.vzd.gov.lv timed out on every attempt:
  - the dates of the open-data page https://www.vzd.gov.lv/lv/VAR-atversana (first published 07.12.2021, updated 08.10.2026);
  - the sentence there that the portal data is updated once a day (the daily refresh itself is confirmed from the portal);
  - the specifications for the text data (https://www.vzd.gov.lv/lv/media/9209/download?attachment, said to be updated 07.10.2026) and the spatial data (https://www.vzd.gov.lv/lv/media/5020/download?attachment);
  - the layer list of the shapefile archive (boundary polygons, address points of hamlets and of buildings and buildable parcels, street and road centre lines), and that the former districts were valid to 30 June 2009;
  - the wording of the licence conditions on https://www.vzd.gov.lv/lv/par-datu-izmantosanas-noteikumiem (cite the source, for example "Izmantoti Valsts adrešu reģistra informācijas sistēmas dati", link the licence, describe changes, do not imply VZD's approval). The licence identifier CC-BY-4.0 is confirmed on the portal.
- The row counts of `aw_eka.csv` (researcher's count: 611,370 rows, of which 551,086 existing, 32,507 liquidated, 27,777 erroneous; 457,195 buildings and 154,175 parcels intended for building; every existing row with a postcode and all but one with coordinates; newest `DAT_MOD` 2026.11.09): not recounted, since that needs the full 142 MB file. The first rows are consistent with the description.
- The content and row count of the apartment-level file `aw_dziv.csv`: the file exists (142.9 MB) but was not opened.
- The EPSG code of LKS-2020 TM: not stated in the portal record or the CSV metadata.
- The weekly refresh and the GML format of the geolatvija.lv bulk file: the zip was not opened.
- Who owns the postcode system.
- The OpenAddresses `city_of_riga` source: not opened.

## Lithuania (LT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Adresų registras files on registrucentras.lt (Registrų centras) | Bulk CSV and GeoJSON, no registration | CC BY 4.0 | Yes, in a separate file; EPSG:3346 not rechecked there | Yes | Monthly |

**In short.** Download the files of the Lietuvos Respublikos adresų registras (Address Register of the Republic of Lithuania) straight from registrucentras.lt: anonymous, CC BY 4.0, monthly. House numbers and postcodes are in one file and coordinates in another; the two join on the address code `AOB_KODAS`, and street names come from a third file. The trap is the copies: on data.gov.lt one attached spatial file dates from 2021, the address-point model in the portal's API is empty, and the INSPIRE copy carries a no-derivatives licence tag. Use the registrucentras.lt files.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Addresses given to land parcels and buildings, text file `adr_stat_lr.csv` | Valstybės įmonė Registrų centras (State Enterprise Centre of Registers) | File: https://www.registrucentras.lt/aduomenys/?byla=adr_stat_lr.csv ; catalogue record: https://data.gov.lt/datasets/1342/ | Pipe-delimited, UTF-8. Columns `SAV_KODAS\|AOB_KODAS\|GYV_KODAS\|GAT_KODAS\|NR\|KORPUSO_NR\|PASTO_KODAS\|AOB_NUO`: among them the address code (`AOB_KODAS`), settlement code (`GYV_KODAS`), street code (`GAT_KODAS`), house number (`NR`), block number (`KORPUSO_NR`) and postcode (`PASTO_KODAS`, format LT-85113). 1,132,892 rows (researcher's count, not recounted) | Anonymous, HTTP 200 | CC BY 4.0 | Monthly per the catalogue record | confirmed |
| Address points, spatial file `adr_gra_adresai_LT.zip` | Registrų centras | File: https://www.registrucentras.lt/aduomenys/?byla=adr_gra_adresai_LT.zip ; catalogue record: https://data.gov.lt/datasets/1351/ | The spatial address data (GeoJSON in a zip). The download answers HTTP 200 as `application/zip`; the archive's content was not rechecked | Anonymous, HTTP 200 | CC BY 4.0 | Catalogue record says yearly ("Kasmet"); the sibling streets file on the same server was generated 2026-11-03 | confirmed (content unverified) |
| Premises addresses `adr_pat_lr.csv` | Registrų centras | https://www.registrucentras.lt/aduomenys/?byla=adr_pat_lr.csv | Apartment-level file. Columns `SAV_KODAS\|PAT_KODAS\|AOB_KODAS\|PATALPOS_NR\|PAT_NUO`. 1,190,947 rows (researcher's count, not recounted) | Anonymous, HTTP 200 | CC BY 4.0 | Monthly | confirmed |
| Streets `adr_gatves.csv` and street centre lines `adr_gra_gatves.json` | Registrų centras | https://www.registrucentras.lt/aduomenys/?byla=adr_gatves.csv ; https://www.registrucentras.lt/aduomenys/?byla=adr_gra_gatves.json | `adr_gatves.csv`: columns `GAT_KODAS\|TIPAS\|TIPO_SANTRUMPA\|VARDAS_K\|GYV_KODAS\|GAT_NUO`, 2,736,369 bytes, 60,444 rows, newest `GAT_NUO` 2026-10-29. `adr_gra_gatves.json`: GeoJSON LineString features with GAT_KODAS, GAT_PAV, GYV_KODAS; CRS EPSG:3346; `formav_dat` 2026-11-03 | Anonymous, HTTP 200 | CC BY 4.0 | Monthly | confirmed |
| Copy on the national geoportal | Statybos sektoriaus vystymo agentūra (catalogue record data.gov.lt dataset 3160) | https://www.geoportal.lt/download/opendata/RC/RC_adresai_atviri_duomenys.zip | A zip of the Registrų centras open address data. Not opened | Anonymous, HTTP 200 | Not stated in the material read | Catalogue record modified 2026-11-08 | confirmed |
| INSPIRE Annex I Addresses, download service | Viešoji įstaiga Statybos sektoriaus vystymo agentūra | Catalogue record: https://data.gov.lt/datasets/3516/ ; file: https://inspire-geoportal.lt/resources/atom/ad/data/AnnexI_Addresses.zip (redirects to https://www.inspire-geoportal.lt/resources/atom/ad/data/AnnexI_Addresses.zip) | INSPIRE addresses, 111,435,789 bytes zipped. Not opened | Anonymous, HTTP 200 after the redirect | Creative Commons Attribution-NoDerivatives 4.0 | Monthly per the record; file last modified 2026-10-12. The record says to contact Registrų centras for the most current data | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Lithuania | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Lithuania countrywide | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lt/countrywide.json | Built from the geoportal.lt zip. A separate Vilnius city source also exists | Free download, needs a logged-in account | CC BY 4.0, attribution "Registrų centras" | Not stated | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Lithuania is among the 19 EU countries covered | No account, GeoParquet | Per country | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **data.gov.lt open data store** ("Saugyklos API", get.data.gov.lt), output as JSON, JSONL, RDF and CSV. The building-address model https://get.data.gov.lt/datasets/gov/rc/ar/pastatas/Pastatas returns records with `nr`, `korpuso_nr`, `pasto_kodas`, `aob_nuo` and references to street, settlement and municipality; `?count()` gives 1,123,119. No key. The address-point model https://get.data.gov.lt/datasets/gov/rc/ar/adresotaskas/AdresoTaskas?count() returns 0, so the store has no coordinates for addresses.
- **INSPIRE download file** (https://www.inspire-geoportal.lt/resources/atom/ad/data/AnnexI_Addresses.zip): keyless, but see the licence tag below.
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.
- A keyless national address-search or geocoding API: none identified. The register's own real-time service is restricted (see "Not free or not available").

### Caveats and recent changes

- **Three files make one address table.** `adr_stat_lr.csv` has the house number, block number and postcode; the address-point file has the coordinates; they join on `AOB_KODAS`. Street names come from `adr_gatves.csv` on `GAT_KODAS`. Apartments come from `adr_pat_lr.csv`, also on `AOB_KODAS`. Settlement, municipality and county files exist in the catalogue but were not probed.
- **Use the registrucentras.lt files, not the portal copies.** The file attached directly to the portal's spatial dataset (https://data.gov.lt/datasets/1351/, 373,858,286 bytes) is dated 2021-08-25. The store's building-address count did not change although its distribution is marked updated 2026-08-20, so the store copy is not refreshed monthly. The address-point model in the store is empty.
- The catalogue entry for the spatial address dataset says it is updated yearly, while the text datasets say monthly. The streets file on registrucentras.lt carried the generation date 2026-11-03.
- **Licence tags differ between copies.** The Registrų centras datasets are Creative Commons Attribution 4.0, access "Vieši" (public), status "Atvertas" (opened). The INSPIRE Addresses entry, published by another body, is tagged Attribution-NoDerivatives 4.0.
- The INSPIRE zip (last modified 2026-10-12) is older than the registrucentras.lt files seen (generated 2026-11-03).
- The download server `www.registrucentras.lt/aduomenys/` sends no `Content-Length` and ignores `Range` requests. A download cannot be resumed or sized in advance.
- registrucentras.lt itself is a JavaScript application; old open-data pages such as https://www.registrucentras.lt/p/1186 return an empty shell to a plain HTTP client. The file URLs above work directly.
- data.gov.lt answered HTTP 429 to a request that followed redirects automatically; one request per call worked. The portal's CSV link https://data.gov.lt/datasets/1342/distribution/14759/download/ only redirects to the registrucentras.lt file.
- The register is catalogued on data.gov.lt as about twenty datasets (counties, municipalities, elderships, settlements, streets, historic streets and settlements, parcel and building addresses, premises addresses, as text and as spatial data, plus monthly statistics): https://data.gov.lt/datasets/?q=Adres%C5%B3+registro
- High-value datasets: the address datasets sit in the portal group "Didelės vertės rinkiniai" (high-value datasets), and data.europa.eu flags them `is_hvd: true`.
- The register's open data dates from October 2020; the spatial dataset's period field starts on 20 October 2020.
- Contact for the open data: atviriduomenys@registrucentras.lt

### Not free or not available

- The continuously updated web service that returns addresses with coordinates (`https://www.registrucentras.lt/adrws/rest/get`, XML; catalogue record https://data.gov.lt/datasets/4085/, created 2026-01-16): access rights are marked "Apriboti" (restricted). Who may use it and at what cost was not found.
- A current address-point dataset through the data.gov.lt store API: not available (count 0).
- No paid address product was found; the register dumps are free and anonymous.

### Could not be verified

- Sizes and row counts of the large files, because the server gives no `Content-Length` and ignores `Range`:
  - `adr_stat_lr.csv`: 56,992,530 bytes, 1,132,892 rows, 1,132,710 with a postcode, newest registration date 2026-10-30 (researcher's count);
  - `adr_pat_lr.csv`: 43,834,598 bytes, 1,190,947 rows (researcher's count); `adr_gra_gatves.json`: 49 MB.
- The content of `adr_gra_adresai_LT.zip`: 62,555,111 bytes, holding `adr_gra_adresai_LT.json` (444,173,555 bytes, dated 2026-11-03), CRS EPSG:3346, about 1,132,891 point features with AOB_KODAS, GYV_KODAS, GAT_KODAS, X_KOORD, Y_KOORD, PASTO_KODA and E_KOORD/N_KOORD (WGS84 degrees). The archive cannot be inspected without downloading it in full, and it was not re-opened. Indirect support only: the sibling streets file declares EPSG:3346 and the generation date 2026-11-03.
- The figure of 1.13 million address points. A related live count was seen: 1,123,119 building-address records in the data.gov.lt store.
- The licence wording on registrucentras.lt itself: the site is JavaScript-only. CC BY 4.0 is taken from the data.gov.lt records.
- Other files under `/aduomenys/`: there is no directory listing and they were not enumerated.
- Postcode ownership (Lietuvos paštas, the postal operator) and any separate postal file: not checked. Postcodes are in the register data.
- A historic address-point file in the open data: none was seen, but the files were not enumerated. Historic streets and settlements are published.
- Figures for the 2020 opening (over 2.1 million unique addresses, over 1 million address points, data as of 1 October 2020): not in the source cited for them.
- The contents of the geoportal.lt zip and of the INSPIRE file: neither was opened.

## Luxembourg (LU)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | BD-Adresses (ACT) | Bulk CSV, GeoJSON or SHP, no registration | CC0 | Yes; WGS84 and LUREF | Yes | Weekly |

**In short.** Use "Adresses géoréférencées (BD-Adresses)" ("georeferenced addresses") from the Administration du cadastre et de la topographie (ACT) on data.public.lu: 179,784 address points as CSV, GeoJSON or shapefile, CC0, no account. The download URLs contain a dated folder that changes every week, so resolve the current file from the dataset page or its API record instead of hard-coding the link. The points are parcel or building centroids, not entrances, and ACT says not every official address is georeferenced yet.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Adresses géoréférencées (BD-Adresses) | Administration du cadastre et de la topographie (ACT) | Page: https://data.public.lu/fr/datasets/adresses-georeferencees-bd-adresses/ ; API record: https://data.public.lu/api/1/datasets/adresses-georeferencees-bd-adresses/ ; CSV of 9 Nov 2026: https://download.data.public.lu/resources/adresses-georeferencees-bd-adresses/20261109-033120/addresses.csv | 179,784 address points. 13 columns: street, number, locality, postcode, CACLR street and building ids, WGS84 lat/lon, LUREF east/north, geoportail id, commune, LAU2 code. No unit (apartment) column. A subset of the national register, enriched with coordinates | Bulk download, no login: `addresses.csv` 28,212,250 bytes, `addresses.geojson` 80,908,855 bytes, `addresses-shp.zip` 19,703,541 bytes | CC0 | Weekly; last update 9 Nov 2026 | confirmed |
| Registre national des localités et des rues ("national register of localities and streets", CACLR) | ACT | Page: https://data.public.lu/fr/datasets/registre-national-des-localites-et-des-rues/ ; file of 9 Nov 2026: https://download.data.public.lu/resources/registre-national-des-localites-et-des-rues/20261109-033002/caclr.zip ; online lookup: https://www.services-publics.lu/caclr/index.action | The authoritative register. `caclr.zip` holds 13 fixed-width files, among them IMMEUBLE (248,702 lines), RUE (9,964 lines) and CODEPT (4,430 lines). Also offered as `caclr.xlsx` | Bulk download, no login: `caclr.zip` 1,956,389 bytes, `caclr.xlsx` 43,103,641 bytes | CC0 | Weekly; last modified 9 Nov 2026 | confirmed |
| INSPIRE - Annex I Theme Addresses - Addresses | Géoportail | Page: https://data.public.lu/fr/datasets/inspire-annex-i-theme-addresses-addresses/ ; API record: https://data.public.lu/api/1/datasets/inspire-annex-i-theme-addresses-addresses/ | Addresses in the INSPIRE model; the WFS layer `ad:AD_Address` holds 187,942 features | Bulk download, no login: `ad.address.gml` 469,407,600 bytes, `ad.address.zip` 13,220,811 bytes; also WMS and WFS | CC0 | Last modified 9 Nov 2026; the record gives the frequency as unknown | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Luxembourg | API, no key; 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lu/countrywide.json | Copy of BD-Adresses; the source reads `https://data.public.lu/fr/datasets/r/2a17ddc2-b961-45ce-83a2-be751d3af9b8` | Free download, needs a logged-in account | "CC 0", attribution not required | Follows the source | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Address points for Luxembourg | GeoParquet, no account | Set per country; not recorded here | Per release | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **Geoportail geocoding.** The BD-Adresses record lists a "Geocode REST API" at `https://apiv3.geoportail.lu/geocode/search` and a "Reverse geocode REST API" at `https://apiv3.geoportail.lu/geocode/reverse`. No key.
- Both the `apiv3` and `apiv4` hosts answered keyless requests on 11 Nov 2026: https://apiv3.geoportail.lu/geocode/search?queryString=1+rue+du+Fort+Thungen+Luxembourg , https://apiv4.geoportail.lu/geocode/search?queryString=54+avenue+Gaston+Diderich+Luxembourg and https://apiv4.geoportail.lu/geocode/reverse?easting=75980&northing=75098
- A search result carries LUREF easting and northing, a lon/lat geometry, the postcode, and `id_caclr_street`, `id_caclr_building` and `id_caclr_locality`.
- **INSPIRE WFS.** https://wms.inspire.geoportail.lu/geoserver/ad/wfs?service=WFS&request=GetCapabilities , no key, feature type `ad:AD_Address`.
- **INSPIRE WMS.** `https://wms.inspire.geoportail.lu/geoserver/ad/wms`
- **CACLR.** An online lookup at https://www.services-publics.lu/caclr/index.action ; the dataset record also links "Webservices 'CACLR'".

### Caveats and recent changes

- **Dated download folders.** The file URLs carry a folder such as `20261109-033120` that changes with every weekly export. The stable entry points are the dataset page and the API record.
- **The CSV starts with a UTF-8 byte-order mark** and is semicolon-separated.
- **Points are not entrances.** ACT states that georeferencing rests on the cadastral parcel and the digital cadastral plan, which can be offset from LUREF; that coordinates come from manual placement or an automatic centroid of the parcel or of the largest building on it; and that "les points d'adresses ne représentent pas l'entrée réelle des bâtiments". Several points can share the same coordinates.
- **Coverage is incomplete by the publisher's own account.** Not all official addresses are georeferenced yet, and "l'exhaustivité des données ne peut être garantie".
- **Three different totals.** BD-Adresses has 179,784 points, the INSPIRE layer 187,942 features (8,158 more), and the register's IMMEUBLE file 248,702 lines. The reasons for the differences are not established.
- **No unit level.** The CSV has no apartment or box column.
- **Tags.** The INSPIRE address dataset is tagged `hvd` (High-Value Dataset) and `inspire`. Both ACT datasets carry the portal badges `spd` and `pivotal-data`.

### Not free or not available

- None.

### Could not be verified

- **Terms of use and rate limits of the geoportail.lu geocoding API.** The terms page (https://www.geoportail.lu/en/about-us/terms-conditions/) says nothing specific about the geocoding API or limits, and the responses carry no rate-limit headers.
- **The CACLR data model.** The description PDF was not read, so the meaning of each of the 13 files, the share of active records and whether the register itself carries coordinates are not established.
- **Whether the High-Value Dataset tag on the INSPIRE dataset came with any change:** not pursued.
- **Postcode licensing.** That no separate POST Luxembourg licence applies to the postcodes in the ACT datasets was not checked; both datasets are published as CC0.

## Malta (MT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | GISCO Address API (Eurostat); lookup only, no download | keyless REST lookup, 1,000-row cap | none stated | yes, lon/lat, not door-precise | no | not stated |

**In short.** Malta publishes no downloadable address-point dataset. The national Address Register offers only reference lists through an open API: 8,502 streets with their locality, region and local council, without door numbers, coordinates or postcodes. Door-level lookups with coordinates come only from Eurostat's GISCO Address API, which has no postcodes for Malta and places several doors on one identical coordinate. Postcodes stay with MaltaPost: a free single-address finder, and a full database on request whose terms are not published.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Address Register, open reference lists | Office of the Address Registrar | https://address.gov.mt/ ; API index: https://address.gov.mt/wp-json/gov/v1 ; streets: https://address.gov.mt/wp-json/gov/v1/streets ; localities: https://address.gov.mt/wp-json/gov/v1/localities | 8,502 streets (`street_name`, `street_code`, `locality`, `region`, `local_council`), 85 localities, 6 regions, 68 local councils. No door numbers, coordinates or postcodes | JSON API, GET only, no key | CC BY 4.0 (catalogue records; the API's own description carries no licence field) | Catalogue records modified 2026-09-14 (local councils 2026-09-16) | confirmed |
| Postcode Finder | MaltaPost | https://www.maltapost.com/PostCode/ | Postcode of a single residence or business | Free web application, one address at a time | Not stated | Not stated | confirmed |
| Full postcode database | MaltaPost, under a decision of the Malta Communications Authority (MCA) | https://www.mca.org.mt/sites/default/files/Postcodes%20Decision_1.pdf | The whole postcode database | On request, at no cost, to third parties that need it (in particular bulk mail senders). Not a public download | Licence, format and procedure: none found | Not stated | confirmed (decision); published terms none found |
| Large Scale Topography Buildings | Planning Authority | https://haleconnect.com/ows/services/org.1261.af1f626c-3200-4fb6-8ae0-a3426b6b4a6e_wfs?SERVICE=WFS&Request=GetCapabilities | Buildings, not addresses. Flagged as a high-value dataset | WFS and WMS | Contradictory: the catalogue says CC BY 4.0; the WFS capabilities say "Conditions apply - contact mappingshop@pa.org.mt to inquire regarding costs and licence of use" | Not stated | corrected |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Forward and reverse lookup of Maltese addresses: door number, street, locality, coordinates. No postcode. Declared source: "© National Statistics Office (NSO)" | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Not stated | corrected |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses. For Malta only the first letters of the full postcodes | ZIP file per country | CC BY 4.0 | Regenerated daily | confirmed |

### Free APIs and services

- **Address Register API**, https://address.gov.mt/wp-json/gov/v1 : routes `/gov/v1/regions`, `/gov/v1/localities`, `/gov/v1/local-councils`, `/gov/v1/streets` and `/gov/v1/openapi.json`. The OpenAPI document ("Government Registers API" v1.1.0) says all endpoints are GET, need no authentication and return JSON arrays. Requests for `/addresses` or `/doors` return HTTP 404 "rest_no_route".
- **Address Register website**, https://address.gov.mt/ : "Locate a Street" and "Research Spot" (search of official door-numbering and street-naming publications from 1997 to date), plus registers of local councils, localities and regions. The home page describes no address-level download.
- **GISCO Address API (Eurostat)**, https://gisco-services.ec.europa.eu/addressapi : no key. `/reverse?x=14.5146&y=35.8989` returned five results, for example door 3, "TRIQ SAN FEDERIKU", Valletta, with a null postcode. `/search?country=MT&city=VALLETTA` returned 100 results. `/cities?country=MT` lists 68 localities.
- **MaltaPost Postcode Finder**, https://www.maltapost.com/PostCode/ : a web application for single lookups.
- **Planning Authority buildings WFS and WMS**: see the table; buildings only, licence unclear.
- **National geocoding API**: none found.

### Caveats and recent changes

- The Address Register is new. The Office of the Address Registrar was set up under Legal Notice 205 of 2025 (Address Register and related Location (Geospatial) Registers Regulations, 2025; https://legislation.mt/eli/ln/2025/205/eng), published on 23 September 2025. It took over the Address Management Unit that had worked in the Electoral Office since 2016. The register is meant to be the authoritative registry of all streets and addresses in the Maltese archipelago, including spatial data.
- The regulations (https://legislation.mt/getpdf/6a0c1054c86ffc41401d4b2d) give a future open release a legal basis. Regulation 10 says the Registrar "shall endeavour to make specific data elements from the Register and subsidiary registers available as open data", under a licence the Registrar specifies and without personal data. Regulation 11 provides for publication on the national data portal. The subsidiary registers are Buildings, Streets, Localities, Post Codes and Regions, and the definition of an address includes geographic coordinates and a post code. So far only the reference lists are published.
- GISCO limits for Malta: the postcode is null in every Maltese record; several door numbers share one identical coordinate; the date of the data is not stated.
- The four Address Registrar datasets in the catalogue (Streets, Localities and Regions, issued 2026-03-27; Local Councils of Malta, issued 2026-06-23) are not flagged as high-value datasets. The one flagged geospatial dataset found is the Planning Authority's buildings.
- The MCA decision of 14 May 2018 sets the free full postcode database as a condition on the universal service provider, unless another entity makes an equivalent database available at no extra cost. MaltaPost said then that it was already giving entities access to the whole database.
- The national portals `portal.data.gov.mt` and `msdi.data.gov.mt` answer HTTP 403 to non-browser clients. What is known about Malta comes from address.gov.mt, legislation.mt and data.europa.eu.
- The older host `postcodes.maltapost.com` no longer resolves.

### Not free or not available

- Downloadable address points (door numbers with coordinates): none found. Searched: the Address Register API, data.europa.eu and OpenAddresses.
- Open postcode data: none found. A data.europa.eu search for Maltese datasets matching "postcode" returned zero results; the GISCO API has no Maltese postcodes; GeoNames has only the first letters. MaltaPost's full database is available on request, not as open data.
- INSPIRE Addresses dataset for Malta: none found. A data.europa.eu search for "AD.Address" returned zero results, and "Addresses INSPIRE" returned only unrelated layers.
- Identità: "Person Basic Details" and "Person Household Details" (latest known address of persons) are listed in the catalogue with no distributions, so they are not open.
- OpenAddresses and Overture Maps: no Maltese data.
- National geocoding API: none found.

### Could not be verified

- The national portals' own pages (https://portal.data.gov.mt/dataset/streets-dataset among them): HTTP 403 with a Cloudflare challenge. The catalogue facts above come from data.europa.eu.
- That no Maltese INSPIRE Addresses dataset exists in the EU INSPIRE Geoportal: its TLS certificate had expired on 2026-11-11, so only data.europa.eu was searched.
- Which licence governs the Planning Authority buildings service: the catalogue and the service contradict each other.
- Whether the Address Register already holds door-level points with coordinates that could be requested: address.gov.mt does not say.

## Netherlands (NL)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | BAG (Kadaster), distributed by PDOK | Bulk GeoPackage or XML zip, no registration | Public domain (CC0 / Public Domain Mark 1.0) | Yes; EPSG:28992 (Amersfoort / RD New) | Yes | Monthly files; daily services |

**In short.** Use the BAG (Basisregistratie Adressen en Gebouwen, "Key Register of Addresses and Buildings") from PDOK: a 7.83 GB GeoPackage without history or a 3.66 GB zip of XML with full history, both public domain and downloadable without an account. Build the import from the files, not from the PDOK query services: those carry only the main address of each object, so objects with secondary addresses are incomplete. Coordinates in the files are in the Dutch RD New grid (EPSG:28992), not WGS84.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| BAG full extract (XML in a zip) | Kadaster (data owner "Dienst voor het kadaster en de openbare registers"); distributed by PDOK | File: https://service.pdok.nl/kadaster/bag/atom/downloads/lvbag-extract-nl.zip ; feed: https://service.pdok.nl/lv/bag/atom/bag.xml ; Kadaster page: https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-extract | Full copy of the BAG for the whole country, including history, as XML files. EPSG:28992 | Bulk download, no login; 3,657,771,488 bytes | CC0 on the PDOK feed; Creative Commons Public Domain Mark 1.0 on the Kadaster page | Monthly: a new extract on the 8th; file dated 8 Nov 2026 | confirmed |
| BAG GeoPackage | Kadaster; distributed by PDOK | File: https://service.pdok.nl/kadaster/bag/atom/downloads/bag-light.gpkg ; feed: https://service.pdok.nl/lv/bag/atom/bag.xml | "The most important BAG data (without history)"; the feed says not all BAG data is included, to keep the file simple. EPSG:28992 | Bulk download, no login; 7,827,132,416 bytes | CC0 | Feed updated monthly; file dated 1 Nov 2026 | confirmed |
| Adressen (INSPIRE geharmoniseerd) ("addresses, INSPIRE-harmonised") | Kadaster; distributed by PDOK | https://service.pdok.nl/kadaster/ad/atom/index.xml | BAG addresses in the INSPIRE data model | ATOM download feed | CC0 | Feed updated 2 Sep 2026 | confirmed |
| BAG dataset record | Kadaster | https://data.overheid.nl/en/dataset/10491-bag | Catalogue record: licence "Publiek domein", access public, labelled "High Value Dataset - EU", category Geospatial | Web page | Public domain | Record updated 05-08-2026 | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for the Netherlands | API, no key; 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/nl/countrywide.json | A cached upload `verblijfsobject.csv.zip` dated 2026-06-03 | Free download, needs a logged-in account | CC0 1.0, no attribution required | Not automatic: the source reads the upload of 2026-06-03 | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Address points for the Netherlands | GeoParquet, no account | Set per country; not recorded here | Per release | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **PDOK Locatieserver ("location server"), geocoding.** "Een open en gratis geocodeerservice" with suggest, lookup, free and reverse APIs. No key. Documentation: https://api.pdok.nl/bzk/locatieserver/search/v3_1/ui/ ; page: https://www.pdok.nl/pdok-locatieserver
- A call such as https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=Hofweg+1+Den+Haag&rows=1&fq=type:adres returns `postcode`, `huis_nlt` (house number with suffix), `nummeraanduiding_id`, `centroide_ll` (WGS84 point) and `centroide_rd`, with source "BAG". The index held 10,085,895 documents of type `adres` on 11 Nov 2026 (https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=*:*&rows=0&fq=type:adres). That is a count of the BAG-derived index, not of the extract.
- **Fair-use limit of the Locatieserver:** none found. The Locatieserver page states no limit and the responses carry no rate-limit headers.
- **PDOK OGC API (Features and Vector Tiles).** `https://api.pdok.nl/kadaster/bag/ogc/v2`, no key, updated daily. Collections: `adres`, `ligplaats`, `pand`, `standplaats`, `verblijfsobject`, `woonplaats` (https://api.pdok.nl/kadaster/bag/ogc/v2/collections?f=json).
- **PDOK WFS and WMS.** `https://service.pdok.nl/lv/bag/wfs/v2_0` and `https://service.pdok.nl/lv/bag/wms/v2_0`, no key, fees "none", CC0. The WFS has the types pand, ligplaats, standplaats, verblijfsobject and woonplaats; it has no `adres` type.
- **Kadaster BAG API Individuele Bevragingen ("individual queries").** Free, but an API key must be requested by form; without a key the API returns 401. At most 50,000 requests per day and 50 per second. Not meant for bulk queries. Page: https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-api-individuele-bevragingen ; usage rules: https://www.kadaster.nl/-/richtlijnen-voor-het-gebruik-van-de-bag-api-individuele-bevragingen

### Caveats and recent changes

- **The PDOK services are incomplete for addresses.** PDOK states that only the main address is included, so objects with several addresses (main and secondary) are not complete and not all BAG addresses are present.
- **Two public-domain labels are in use:** CC0 on the PDOK feed and services, Public Domain Mark 1.0 on the Kadaster page. The data.overheid.nl record says "Publiek domein".
- **Kadaster's stated file size is out of date.** Its free-download page (https://www.kadaster.nl/-/gratis-download-bag-extract) says "ongeveer 2,8 GB" and links https://service.pdok.nl/kadaster/adressen/atom/v1_0/downloads/lvbag-extract-nl.zip ; that link serves the same 3,657,771,488-byte file as the PDOK feed.
- **Moved URLs.** The Kadaster page `.../bag-2.0-extract` now redirects to https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-extract . The earlier OGC API path `https://api.pdok.nl/lv/bag/ogc/v1` returns 404.
- **The SOAP retrieval method with username and password ends in Q1 2027.** The BAG Extract Ophaal API (API key) replaces it; a SOAP route with a PKI-O certificate is also listed and not marked as ending. This concerns the paid deliveries below.
- **OpenAddresses is behind the source:** its Dutch source reads an upload dated 2026-06-03.
- **Postcodes in the BAG are free to reuse.** A trade journal (Binnenlands Bestuur, https://www.binnenlandsbestuur.nl/digitaal/ondermijning/bag-met-postcodegegevens-wordt-vrij-herbruikbaar) reports that the ministry ended the "postcodeconvenant" with TNT Post (now PostNL) in February 2011, that PostNL lost its court case, and that the restriction ended on 1 February 2012. This is a press report, not an official source.

### Not free or not available

- **Mutation subscriptions (Kadaster, ordered through Mijn Kadaster).** National or municipal monthly mutations: EUR 14.50 per month plus EUR 219 one-time. National daily mutations: EUR 219 per month plus EUR 219 one-time. Government bodies get them free.
- **One-off extract for a single municipality:** EUR 219 per delivery. The national extract is free.

### Could not be verified

- **PostNL's own Postcodetabel as a paid product** (https://www.postnl.nl/zakelijke-oplossingen/slimme-dataoplossingen/postcodetabel/): the page returned an HTTP/2 stream error and no content.
- **Contents of the GeoPackage.** Its layers and columns were not opened, so whether it carries secondary addresses, and which address fields it holds, is not established. The same applies to the internal layout of the XML extract.
- **An Esri document said to date a government-PostNL covenant on BAG postcode use to early 2014,** which does not match the 2012 date above: not pursued.
- **Whether the EU High-Value Datasets regulation changed BAG distribution** beyond the label: not pursued.
- **CBS files linking postcode and house number to neighbourhoods:** not checked.

## Poland (PL)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | PRG address points (GUGiK) | Bulk SHP or GML zip, no registration | No named licence; "free of charge and for any use" | Yes, EPSG:2180 | Yes | Continuous at source; file schedule not stated |

**In short.** Use the address points of the *Państwowy Rejestr Granic* (PRG, State Register of Borders) from the surveying office GUGiK: one national zip in SHP (564 MB) or GML (805 MB), no login, about 8.64 million points with house number, postcode, TERYT codes and EPSG:2180 coordinates. The same data can be queried without a key through a WFS, an OGC API Features service and a geocoder. The likely trip-up is the national SHP zip itself: it is compressed with deflate64 (some unzip tools cannot open it), its attribute table is 7.07 GB (above the classic 2 GB dBase limit) and the national address layer has no `.cpg` encoding file. There is no licence text, only GUGiK's sentence that the data is free "for any use".

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| PRG address points, national SHP | Główny Urząd Geodezji i Kartografii (GUGiK) | https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/POLSKA.zip | Four layers: 8,640,975 address points, 297,609 streets, 8,619 squares, 68,403 localities (computed from the index files of the 10 Nov 2026 archive). Address fields: `ID_IIP`, `NUMER_PORZ` (house number), `KOD_POCZT` (postcode), `DATA_NAD`, `NAZWA_ULC` (street), `ID_ULIC`, `NAZWA_GMI`, `TERYT_GMI`, `NAZWA_MSC` (locality), `ID_SIMC`. CRS EPSG:2180 | Anonymous download, 564,312,601 bytes | No named licence; GUGiK: "free of charge and for any use" | File last modified 10 Nov 2026 | confirmed |
| PRG address points, national GML | GUGiK | https://opendata.geoportal.gov.pl/prg/adresy/PRG-punkty_adresowe.zip | 16 GML files, one per voivodeship, stamped 10.11.2026; 10.78 GB uncompressed | Anonymous download, 804,643,553 bytes | Same | File last modified 10 Nov 2026 | confirmed |
| PRG address points, per-voivodeship SHP | GUGiK | https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/14/14.zip (Mazowieckie) and https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/16/16.zip (Opolskie) | Same layers per voivodeship; the path uses the two-digit TERYT voivodeship code. Opolskie: 230,984 address points, 9,728 streets, 1,437 localities, 257 squares; `.cpg` says UTF-8 | Anonymous download; 86.7 MB and 15.9 MB | Same | Both last modified 10 Nov 2026 | confirmed (these two files) |
| PRG page (description, licence wording, download links) | GUGiK | https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/ | Says PRG includes addresses and their location, fed from the municipalities' address records; lists SHP and GML only | Web page | Carries the sentence "Dane PRG są dostępne bezpłatnie i do dowolnego wykorzystania" | - | confirmed |
| Municipal address datasets (Kielce "Punkty adresowe", "Adresy m.st. Warszawy") | Cities, on dane.gov.pl | dane.gov.pl datasets 4919 and 469; no file URL recorded | Kielce: GeoPackage, GeoJSON, Parquet. Warsaw: not recorded | Not tested; dane.gov.pl timed out | Not recorded | Not recorded | unverified (catalogue records only) |
| Official List of Postal Address Numbers (PNA), PDF | Poczta Polska | https://www.poczta-polska.pl/wp-content/uploads/2024/05/spispna.pdf (listed on https://www.poczta-polska.pl/en/dla-biznesu/oferta/uslugi-pozostale/pocztowe-numery-adresowe/) | Postcode list as a PDF, 7,894,567 bytes | Anonymous download | None stated on the page | File last modified 12 Oct 2026 | confirmed |
| TERYT full files (TERC, SIMC, ULIC) | GUS (statistical office) | https://eteryt.stat.gov.pl/eTeryt/rejestr_teryt/udostepnianie_danych/baza_teryt/uzytkownicy_indywidualni/pobieranie/pliki_pelne.aspx | Identifier catalogues of territorial units, localities and streets, in basic, address and statistical versions. No house numbers or coordinates by catalogue definition | Web form downloads (page post-backs) | Not recorded | Not recorded | confirmed (page only; no file opened) |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Poland | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definitions: https://github.com/openaddresses/openaddresses/blob/master/sources/pl/mazowieckie.json) | PRG address points, 16 sources, one per voivodeship, pulled from the live per-voivodeship zips | Free download, needs a logged-in account | Recorded as "Polish Law on Geodesy and Cartography of 17 May 1989", attribution not required, no share-alike | All 16 processed 2026-10-30 | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 8,628,514 Polish addresses in release 2026-10-21.0 (publisher's figure) | GeoParquet, no account | Listed as "No conditions to access and use" | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **Address WFS, no key:** https://mapy.geoportal.gov.pl/wss/ext/wfs/KrajowaIntegracjaNumeracjiAdresowej . Feature types `adresyUlice:A07_Punkty_adresowe` and `adresyUlice:A08_Ulice`, default CRS EPSG:2180, attributes include `KOD_POCZTOWY`. It reported 8,641,300 address points on 11 Nov 2026. Capabilities state fees "no conditions apply" and access constraints "otherRestrictions". GUGiK lists it at https://www.geoportal.gov.pl/pl/usluga/uslugi-pobierania-wfs/ .
- **INSPIRE Addresses WFS:** https://mapy.geoportal.gov.pl/wss/service/INSPIRE/Addresses . Feature type `ms:AD.Address`; capabilities state "No fees" and "No constraints". Only the capabilities document was read.
- **OGC API Features, no key, launched 2026-09-25:** https://ogcapi.geoportal.gov.pl/res/ims/maps/prg_ad/apiFeatures . Collections `PunktAdresowy` and `Ulica`, HTML and JSON, CRS84 with storage CRS EPSG:2180; 8,641,300 address points matched on 11 Nov 2026. The `self` and `next` links in replies point at the host `ogcapitest.geoportal.gov.pl`.
- **Geocoder UUG (*Uniwersalna Usługa Geokodowania*), no key:** https://services.gugik.gov.pl/uug/ , documentation https://services.gugik.gov.pl/uug/opis.html . HTTP GET, JSON. Requests: `GetAddress`, `GetAddressReverse` (WKT point with `srid` 4326 or 2180), `GetAddresses`, `GetCity`, `GetStreet`, `GetRoadMarker`, `GetLevelCrossing`, `GetLocation`, `GetRoads`. A test address returned city, street, number, TERYT, SIMC and ULIC codes, postcode and x/y in EPSG:2180, with `"max results limit":15`; a reverse lookup returned the nearest address within `"radius":100`. Requests to `/uug?...` are redirected (301) to `/uug/?...`.
- **WMS with address points and streets (map images):** https://mapy.geoportal.gov.pl/wss/ext/KrajowaIntegracjaNumeracjiAdresowej . Layers `A07_Punkty_adresowe`, `A08_Ulice`; fees "no conditions apply", access constraints "otherRestrictions".
- **Package links per municipality, county or voivodeship:** the PRG page says they are served through the geoportal map ("Dane do pobrania") and through WMS GetFeatureInfo at https://integracja.gugik.gov.pl/cgi-bin/PanstwowyRejestrGranic . No such request was made.
- **Old download links still redirect (302):** https://integracja.gugik.gov.pl/PRG/pobierz.php?adresy_zbiorcze_gml goes to the GML zip; the same script with `?adresy_zbiorcze_shp` goes to https://opendata.geoportal.gov.pl/prg/adresy/PRG-punkty_adresowe_shp.zip (564,312,601 bytes, same date as `POLSKA.zip`).
- **TERYT web service "ws1" (GUS):** https://api.stat.gov.pl/Home/TerytApi?lang=en . Free, XML, covers TERC, SIMC and ULIC and verifies addresses down to street level. It needs an account, requested by e-mail to teryt_ws1@stat.gov.pl.
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- The national SHP zip is a zip64 archive compressed with deflate64 (method 9), which some unzip tools cannot inflate. Its address `.dbf` is 7,068,317,904 bytes uncompressed. The national address layer has no `.cpg` file, although the other three national layers have one; the Opolskie package's `.cpg` says UTF-8.
- The address points have no flat or unit field: the ten attributes listed above are all there is.
- PRG addresses come from the municipalities (gminas) and are updated at source as municipalities change their records. GUGiK publishes no regeneration schedule for the download files; on 11 Nov 2026 every file checked was dated 10 Nov 2026.
- Counts differ slightly by route: 8,640,975 points in the 10 Nov 2026 file, 8,641,300 from the live WFS and OGC API on 11 Nov 2026.
- Quality varies by municipality. The OpenStreetMap wiki says supply "may range from excellent to 'no data supplied, despite legal obligation'" (https://wiki.openstreetmap.org/wiki/Pa%C5%84stwowy_Rejestr_Granic , page last edited 29 January 2023).
- Formats are SHP and GML only. There is no archive of past address data; the archives on the PRG page (2005-2025) hold boundaries only.
- Licence basis: GUGiK's sentence on the PRG page, and Art. 40a(2)(1)(a) of the Geodetic and Cartographic Law, which says no fee is charged for PRG datasets (https://api.sejm.gov.pl/eli/acts/DU/2024/1151/text.html). No Creative Commons or other named licence appears on the PRG page.
- The UUG and OGC API pages publish no key requirement, rate limit or terms of use: none found on the UUG landing and documentation pages, the OGC API landing page, the launch notice (https://www.geoportal.gov.pl/aktualnosci/nowe-uslugi-ogc-api-features-dla-danych-prg-i-prng/) or the WFS list page.
- UUG's documentation gives a default `accuracy` of 0.6 (range 0.5-1.0), but a live reply reported `"min accuracy limit":0.4`.
- The free Poczta Polska PDF sits under a `2024/05` path but was last modified on 12 Oct 2026.
- High-value datasets: on data.europa.eu, 0 of 26,701 Polish datasets carry the high-value flag (11 Nov 2026). GUGiK's PRG dataset (dane.gov.pl dataset 726) and "Adresy INSPIRE (AD)" (dataset 672; WFS, ATOM and WMS distributions; modified 2024-03-19) are listed, seen through data.europa.eu's copy of the dane.gov.pl catalogue, without the flag. The OGC API launch notice does not mention high-value datasets.

### Not free or not available

- **Poczta Polska postcode list in electronic form:** sold in its online shop and as an annual subscription (PDF, TXT, XLS, quarterly updates). Postal operators get access under a written agreement, for a fee set in a price list. A third-party review describes it as a commercial product for the customer's own use with no resale (https://datahub.io/logistics/postal-codes-pl/.licensing-notes). Only the PDF is free.
- **TERYT:** street and locality identifiers only, no house numbers. Its web service needs an account.
- **CSV or GeoPackage of PRG addresses:** not offered.
- **Flat or unit numbers:** not in the PRG address points.

### Could not be verified

- That PRG holds exactly one point per house number: this needs the full national file, which was not downloaded.
- That the download files are regenerated daily: the dates fit, but no schedule is published.
- How completely municipalities fill the postcode field: not measured.
- That commercial reuse is allowed without attribution: there is no licence text. It rests on GUGiK's "for any use" sentence, the statute, and the terms OpenAddresses and Overture record.
- Whether the TERYT building catalogue (NOBC) can be downloaded: it is not on the eTERYT full-files page and no other route was tried.
- Contents of the TERYT files, and the ws1 endpoint addresses and terms: no file or manual was opened.
- Poczta Polska's own licence wording for the free PDF: not on its PNA page.
- Anything on dane.gov.pl itself, including the Kielce and Warsaw address datasets: the portal and its API timed out on 11 Nov 2026, so only data.europa.eu's records of them were seen.
- Undocumented throttling on UUG, the WFS or the OGC API: unknown.

## Portugal (PT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | Base Nacional de Moradas (INE); stale, files from 2018 | GML per municipality from an ATOM feed, no registration | CC BY 4.0 | yes, EPSG:4258, 4326 and 3763 (islands 5014-5016) | yes | none seen since 2018 |

**In short.** The only national source is INE's Base Nacional de Moradas (BNM, National Address Base): door numbers, floor and unit designators, postcodes and coordinates for all 308 municipalities, CC BY 4.0, downloadable without registration. The files are a 2017 version generated in January 2018, although the metadata calls the update frequency "continuous". Addresses are at unit level, so one door number appears once per floor and unit. There is no national geocoding API; Eurostat's GISCO Address API covers Portugal from the same INE data.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Base Nacional de Moradas (BNM, National Address Base), INSPIRE Addresses | Instituto Nacional de Estatística (INE) | https://inspire.ine.pt/AD/atom/downloadservice.html ; portal record: https://dados.gov.pt/datasets/base-nacional-de-moradas | Addresses for 308 municipalities, built from the Ficheiro Nacional de Alojamentos (national dwellings file). Point per address, door number, floor and unit designators, postcode, street name, administrative units | Eight regional ATOM feeds; one zipped GML per municipality in four CRS. No registration or key | CC BY 4.0 (national portal and national catalogue records); the feeds say "Sem restrições" (no restrictions) | Version 2017, generated 2018-01-22; file probed last modified 17 April 2018. Metadata says "continuous" | confirmed |
| Números de Polícia (door numbers), Cascais | Municipality of Cascais | https://dados.gov.pt/datasets/geocascais-numerospolicia | Municipal door-number data | CSV, GeoJSON, JSON, SHP, KML, GeoPackage, DXF | CC BY | Last modified 2026-11-09 | confirmed |
| Toponímia: Números de Polícia (street names: door numbers), Oeiras | Municipality of Oeiras | https://dados.gov.pt/datasets/toponimia-numeros-de-policia | Municipal door-number data | WFS | CC BY | Last modified 2026-10-19 | confirmed |
| Toponímia da rede viária e numeração de polícia (street names and door numbering), Porto de Mós | Municipality of Porto de Mós | https://dados.gov.pt/datasets/toponimia-da-rede-viaria-e-numeracao-de-policia-porto-de-mos | Municipal street names and door numbers | WFS | Unknown | Modified 2025-10-17 | confirmed |
| Toponímia e numeração de polícia, Alto Tâmega e Barroso | Alto Tâmega e Barroso | https://dados.gov.pt/datasets/toponimia-e-numeracao-de-policia-no-alto-tamega-e-barroso | Street names and door numbers for the area | GeoPackage | CC BY | Modified 2023-03-17 | confirmed |
| Toponímia de Lisboa (Lisbon street names) | Municipality of Lisbon | https://dados.gov.pt/datasets/toponimia-de-lisboa | Street names only, no door numbers | GeoJSON | CC0 | Not stated | confirmed |
| CTT postcode file | CTT (postal operator) | https://www.ctt.pt/feapl_2/app/restricted/postalCodeSearch/postalCodeDownloadFiles.jspx | Postcode files | The page redirects to a login; an account is required | Terms not readable without logging in | Not known | confirmed (login required) |
| codigos_postais, a community conversion of the CTT file | centraldedados (third party) | https://github.com/centraldedados/codigos_postais | Postcodes for mainland and islands, more than 300,000 entries of three kinds (customers with their own postcode, localities, streets and street segments) | GitHub repository | PDDL, which the republisher itself calls a presumption that the data are public | Not stated | confirmed |
| Base Geográfica de Edifícios (BGE, Geographic Base of Buildings) | INE | https://snig.dgterritorio.gov.pt/rndg/srv/api/records/ad14e031-a2c1-4673-a85b-3b57b0df3767/formatters/xml | Building points georeferenced in the 2011 census, with residential buildings added or corrected in 2021 | Not open: limited public access, no download or service | - | Metadata dated 2026-06-17, maintenance "irregular" | corrected |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Forward and reverse lookup of Portuguese addresses: door number, street, city, postcode, coordinates. Declared source: "© Instituto Nacional de Estatística" | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Not stated | corrected |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/pt/countrywide.json | Countrywide layer converted from the INE service, with postcodes | Free download, needs a logged-in account | CC BY 4.0, attribution "Instituto Nacional de Estatística, I.P." | Cached conversion dated 2026-02-23 | confirmed |
| Overture Maps addresses, release 2026-10-21.0 | Overture Maps | https://docs.overturemaps.org/guides/addresses/ | 5,607,450 Portuguese addresses (publisher's figure), from INE as distributed by OpenAddresses | GeoParquet, no account | No licence named for Portugal | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | ZIP file per country | CC BY 4.0 | Regenerated daily | confirmed |

### Free APIs and services

- **GISCO Address API (Eurostat)**, https://gisco-services.ec.europa.eu/addressapi : no key, forward and reverse lookup, built on INE data. `/reverse?x=-9.1411&y=38.7128` returned five results, for example door 11, street "DUQUE", Lisboa, postcode 1200-158. `/search?country=PT&postcode=1100-048` returned two addresses on "AUGUSTA". Street names are stored without the type word: a search for road "Rua Augusta" returned nothing.
- **INE INSPIRE ATOM download service**, https://inspire.ine.pt/AD/atom/downloadservice.html : eight dataset feeds (Norte, Centro, Área Metropolitana de Lisboa, Alentejo, Algarve, Madeira, Açores central and eastern groups, Açores western group). Example feed: https://inspire.ine.pt/AD/atom/CDG_AD_BNM_pc_AML_Atom.xml . Example file: https://inspire.ine.pt/AD/atom/gml/Addresses_1106_EPSG4326.zip (Lisbon).
- **Municipal WFS**: Oeiras and Porto de Mós publish their door-number layers as WFS (see the table).
- **National geocoding API**: none found.

### Caveats and recent changes

- The data are old. The Lisbon file carries `versionId` 2017, `validFrom` 2018-01-01, a generation timestamp of 2018-01-22 and a server date of 17 April 2018. Feed entries are dated 2017-05-17 and the feeds 2019-11-11. The portal record gives frequency "continuous" and last modification 2025-01-08, but the files did not change.
- No newer BNM release and no other national address-point dataset: none found. Searched: data.europa.eu for "moradas" in Portugal (18 results, the BNM the only national address dataset).
- Addresses are at unit level. Each locator carries a door number (`buildingIdentifier`), a floor (`floorIdentifier`) and a unit (`unitIdentifier`, for example "ESQ"); the point is placed at the building. An import that wants one record per door number has to collapse them.
- Counts of "feature members" include component features such as postal descriptors alongside the addresses, so they are not address counts.
- The feeds are not clean. In the Norte, Centro, Lisbon-area and Alentejo feeds, 139 EPSG:3035 entries link to `Addresses_1007_EPSG3035.zip` instead of their own municipality's file, so the EPSG:3035 links cannot be trusted; the EPSG:3763, 4258 and 4326 links are consistent. Municipality 0914 is listed in both the Norte and Centro feeds, and Madeira lists 12 entries per CRS for 11 codes.
- CRS: mainland files come in EPSG:3763, 4258, 4326 and 3035. The islands replace 3763 with EPSG:5014 (Açores western group), 5015 (Açores central and eastern groups) or 5016 (Madeira).
- In the EPSG:4326 files `gml:pos` is latitude first.
- Files are large once unpacked: the Lisbon ZIP is 21,760,599 bytes and its GML 942,686,107 bytes.
- `HEAD` requests to the ZIP files get no HTTP response; `GET` (also ranged) works.
- The portal description speaks of addresses of mainland Portugal ("Portugal Continental"), but the service also has feeds for Madeira and the Azores.
- The portal record is tagged as a High-Value Dataset under Regulation (EU) 2023/138. INE's own HVD page (https://www.ine.pt/scripts/hvd/en/geo.html) shows the National Address Base only; its metadata link for the address base returned HTTP 404.
- INE gave the Portuguese OpenStreetMap community written permission to import the data (https://wiki.openstreetmap.org/wiki/Portugal/Projetos/Importa%C3%A7%C3%A3o_de_endere%C3%A7os).
- Overture names no licence for its Portuguese addresses, although the same data are CC BY 4.0 at the national portal.

### Not free or not available

- National geocoding API: none found. The GISCO Address API fills the gap for lookups.
- Base Geográfica de Edifícios (buildings base): not open. Its metadata record declares "Acesso público limitado de acordo com o Artigo 13(1)(f) da Diretiva INSPIRE" (limited public access) and offers no download or service.
- CTT postcode file: behind a login, and its terms of use could not be read. The only licence in circulation is a third party's presumption (PDDL), so it cannot be treated as open data.
- Open postcode dataset on the national portal: none found. A search of dados.gov.pt for "códigos postais" returned zero datasets. The same search for "moradas" (https://dados.gov.pt/api/1/datasets/?q=moradas&page_size=12) returned three, of which only the BNM is an address dataset.
- Door-number datasets for the municipalities of Lisbon and Porto: none found. Searched: dados.gov.pt and data.europa.eu for "números de polícia"; the municipal portals themselves were not searched.

### Could not be verified

- Total size of one CRS set, 471.7 MB zipped: researcher's count. The feeds carry no sizes and it would take 308 requests to recount.
- 6,475,977 feature members over the 308 files: researcher's count. Only Lisbon's 336,033 was re-read.
- 324,640 Lisbon addresses with a locator: researcher's count; it needs the full file.
- That every one of the 308 files dates from 2018: the dates were read on the Lisbon file only.
- That the BNM leaves out businesses and facilities: no such sentence was found on the OpenStreetMap wiki page cited for it.
- That the CTT account is free: only the login requirement was seen; no account was created. CTT's terms of use, update frequency and position on commercial reuse are unknown for the same reason.
- The INSPIRE Geoportal record for the buildings base: the Geoportal's TLS certificate had expired on 2026-11-11; the national catalogue record was used instead.

## Romania (RO)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| No | Substitute: Poșta Română postcode file of 2016; no house-number points | Bulk XLS, no registration | OGL-ROU-1.0 | No | Yes, to street level per the publisher | None; newest file is from 2016 |

**In short.** No free national source of house-number addresses with coordinates was found. The official register, RENNS, was reachable only through the cadastre agency's geoportal, and that geoportal has been offline since the cyberattack of 14 July 2026: on 2026-11-11 its host names no longer resolve, and no restart date is announced. What remains is a 2016 postcode table from Poșta Română and municipal street lists, none with address points. Any `geoportal.ancpi.ro` link in older documentation is dead.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| RENNS, Registrul Electronic Național al Nomenclaturilor Stradale (National Electronic Register of Street Nomenclatures) | Agenția Națională de Cadastru și Publicitate Imobiliară (ANCPI, the cadastre agency) | EU catalogue record: https://data.europa.eu/api/hub/search/datasets/-aa3a39d5-b7d6-4297-8cb9-6be9e470a1be- ; view service record: https://data.europa.eu/api/hub/search/datasets/-5dcafddb-7729-4655-8c5c-845ae8538bfc- ; download service record: https://data.europa.eu/api/hub/search/datasets/-d8d123a0-5f26-40af-bd73-b78ca7609c9c- | Per the catalogue: points with "the administrative numbers of urban-type localities", collected from 2009 on from town halls and prefectures | Offline. The WMS and the ATOM download feed sit on `geoportal.ancpi.ro`, which does not resolve | Not established; see "Could not be verified" | Download feed last updated 2019-09-12 | confirmed (services offline) |
| Municipal "nomenclator stradal" (street list) datasets: Cluj-Napoca (2020), Bucharest Sector 2 (2021), Copșa Mică, Săliștea, Bobicești, Puiești, Timișoara (2014) | The municipalities, on data.gov.ro | https://data.gov.ro/api/3/action/package_search?q=nomenclator+stradal&rows=12 | Street lists, not address points; files not opened | File downloads | CC BY 4.0; Timișoara OGL-ROU-1.0 | As dated | confirmed (listing only) |
| "Nomenclator strazi judetul …" (street list per county) | Ministerul Finanțelor Publice (Ministry of Public Finance), on data.gov.ro | https://data.gov.ro/api/3/action/package_search?q=strazi&rows=12 | Street lists per county; files not opened | File downloads | OGL-ROU-1.0 | 2016 | confirmed (listing only) |
| Coduri postale Romania (postcodes of Romania) | Poșta Română (Romanian Post), on data.gov.ro | Dataset page: https://data.gov.ro/dataset/coduri-postale-romania ; 2016 file: https://data.gov.ro/dataset/3eb7dc31-e53e-4c09-b2e2-87c909e68fb6/resource/29a5c89e-0f23-4a42-aa05-765ef04177b6/download/infocod-cu-siruta-mai-2016.xls | 6-digit postcodes, "detailed down to street level" per the dataset description. XLS files "infocod" of October 2013, May 2016 and September 2016 (with SIRUTA codes). Content not parsed | XLS download, no login; the 2016 file is 7,845,888 bytes | OGL-ROU-1.0 | Record last modified 2016-09-06 | confirmed (file not opened) |
| Caută cod poștal (postcode search) | Poșta Română | https://www.posta-romana.ro/cauta-cod-postal.html | Postcode look-up, described as updated periodically | Web look-up only; no file link on the page | Not stated | Not stated | confirmed |
| SIRUTA, register of administrative-territorial units | Institutul Național de Statistică (National Institute of Statistics), on data.gov.ro | https://data.gov.ro/api/3/action/package_search?q=SIRUTA&rows=12 | Administrative units down to settlement level; no streets, no addresses | File downloads | CC BY 4.0 | Latest "SIRUTA_s1 2026", modified 2026-08-11 | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Romania | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, two city sources | OpenAddresses | https://github.com/openaddresses/openaddresses/blob/master/sources/ro/bucharest.json ; https://github.com/openaddresses/openaddresses/blob/master/sources/ro/bucharest-metro.json ; downloads: https://batch.openaddresses.io | No countrywide source. Two source files: one for Bucharest, one noting Otopeni, Sinaia, Voluntari and Chitila. The output is four towns around Bucharest, frozen in 2020 | Free download; needs a logged-in account | None recorded | Frozen 2020 | confirmed; upstream server status corrected |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- None from a national publisher is working. The RENNS view service (WMS), `https://geoportal.ancpi.ro/inspireview/rest/services/AD/AD_View/MapServer/exts/InspireView/service?SERVICE=WMS&REQUEST=GetCapabilities`, is offline with its host.
- Poșta Română's postcode search, https://www.posta-romana.ro/cauta-cod-postal.html , is a web look-up, not an API.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.
- The Esri Romania server behind the two OpenAddresses sources, `https://maps-gisportal.esriro.ro/arcgis/rest/services/SureData/SureData/MapServer/1` and `/2`, resolves and answers, but with a self-signed TLS certificate. A client that checks certificates cannot use it. Its content was not read.

### Caveats and recent changes

- Outage timeline. All ANCPI systems went down on 14 July 2026; ANCPI announced the attack on 15 July (https://agerpres.ro/2026/07/15/agentia-nationala-de-cadastru---tinta-unui-atac-informatic-datele-sunt-in-siguranta-si-se-lucreaza-l--1576362). On 17 August the Government said e-Terra worked and the other systems, Geoportal included, were still down (https://startupcafe.ro/situatia-de-la-cadastru-aplicatia-e-terra-functioneaza-iar-volumul-ridicat-de-solicitari-este-in-curs-de-procesare-celelalte-sisteme-ancpi-sunt-tot-blocate-guvern-105217).
- ANCPI's own notice, dated 20 August 2026 and still the only page on https://www.ancpi.ro/ , says the restart concerns "exclusively" e-Terra. The other platforms "și Geoportal" will return in stages, each restart announced publicly. The notice names "Geoportal", not RENNS.
- State on 2026-11-11: `geoportal.ancpi.ro` and `renns.ancpi.ro` return NXDOMAIN from three public resolvers (1.1.1.1, 8.8.8.8, 9.9.9.9). No announcement of a return was found on ancpi.ro or in one web search in Romanian.
- A Digi24 headline of 2026-07-21 says ANCPI is moving its applications to the Government Cloud (https://www.digi24.ro/digieconomic/digital/ancpi-muta-aplicatiile-in-cloudul-guvernamental-dupa-atacul-cibernetic-cand-ar-putea-reveni-serviciile-110985). Only the headline was read.
- Forbes România (3 September 2026) reports that the attackers had access for 86 hours before detection, and quotes a ransom note that claims a copy of the source code of eTerra and RENNS (https://www.forbes.ro/hackerii-au-avut-acces-la-sistemele-ancpi-timp-de-86-de-ore-inainte-de-a-fi-detectati-519051). That is the attackers' claim, and it is about code, not data.
- What the download was before the outage. An archived copy of the ATOM feed (http://web.archive.org/web/20260212012623/http://geoportal.ancpi.ro/inspiredownload/rest/directories/arcgisforinspire/AD/AD_Download_MapServer/Main_ATOM_AD.xml) shows one dataset, `AD.RENNS` / `RO.ANCPI`, as a file geodatabase zip in EPSG:4258, last updated 2019-09-12. Its `rights` element reads "(a) the confidentiality of the proceedings of public authorities, where such confidentiality is provided for by law".
- That feed's extent element reads "23,6866 44,9372 23,7291 44,9611": two coordinate pairs with decimal commas, not a valid polygon. Read as a box it is about 0.04° by 0.02°. The dataset-level feed (`AD_Dataset.xml`) has no archived copy, so the size, date and extent of the old download are unknown.
- The EU catalogue gives EPSG:3844 (Stereo 70) as the dataset's reference system; the download feed gave EPSG:4258.
- Legal basis: Government Decision 777/2016 governs RENNS. A private copy of the gazette text (Monitorul Oficial 867/2016, on legeaz.net) says RENNS is built, updated and administered by ANCPI (Art. 1(2)) and that its information is public, "au caracter public" (Art. 1(3)). It was not read on an official legislation site.
- Other dead ends: Romania's INSPIRE portal host, https://geoportal.gov.ro/ , resolves but accepts no connection on ports 443 and 80. The former EU INSPIRE Geoportal was decommissioned on 1 July 2026; its host now serves an expired TLS certificate, so the RENNS metadata record there (https://inspire-geoportal.ec.europa.eu/srv/api/records/%7B5DCAFDDB-7729-4655-8C5C-845AE8538BFC%7D) cannot be read.
- Postcode file: the newest resource is labelled "Sept.2016" but its file name is `infocod-cu-siruta-mai-2016.xls`. The 6-digit postcode has been in force since 1 May 2003. The data is ten years old.
- High-value-dataset status: no Romanian dataset of any HVD category is flagged in data.europa.eu. The three RENNS records there have `is_hvd: false`.

### Not free or not available

- National house-number addresses with coordinates: none found. Searched: data.gov.ro ("RENNS": 0 results; "adrese": 4 unrelated results; "ANCPI": 121 datasets, none about addresses or streets; "nomenclator stradal" and "strazi": street lists only) and the EU catalogue data.europa.eu (three RENNS records, all pointing to offline services).
- RENNS view and download services: offline since 14 July 2026. The download feed was at `http://geoportal.ancpi.ro/inspiredownload/rest/directories/arcgisforinspire/AD/AD_Download_MapServer/Main_ATOM_AD.xml`.
- Postcode file newer than 2016: none found on data.gov.ro. Poșta Română's postcode page offers a look-up only, with no file link.
- Overture Maps addresses (release 2026-10-21.0): no Romanian data.

### Could not be verified

- The use terms in RENNS's INSPIRE metadata: a statement that the data "nu se comercializează" (are not sold), and a limit on public access under Article 13(1) of the INSPIRE Directive and its letter. The servers holding the metadata are offline or fail TLS, and the EU catalogue records lack the wording. Only the letter (a) text in the archived download feed was seen.
- Whether RENNS was ever open as a bulk download, and whether the downloadable file covered the country or a sample area: the file and its feed are offline and there is no archive copy.
- Content of the 2016 postcode XLS (columns, row count, whether it has house-number ranges): the file was not downloaded or parsed.
- Whether Poșta Română publishes a newer postcode file anywhere else: not searched beyond data.gov.ro and the look-up page.
- Content of the municipal and county street-list files: not opened.
- Content and licence of the Esri Romania "SureData" layers: the server's self-signed certificate was not bypassed.

## Slovakia (SK)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Register adries (Ministry of Interior) | Bulk CSV or WFS, no registration | CC0 | Yes; WFS EPSG:4258, CSV in degrees | Yes | CSV declared quarterly; served file is April 2026 |

**In short.** Use the *Register adries* (Address Register) of the Ministry of Interior, published under CC0 without registration: a national CSV of 162 MB with about 1.74 million addresses, or a public WFS that serves 1,750,730 address points as CSV, GeoJSON or Shapefile. The CSV lags: it is declared quarterly, but the file served on 11 Nov 2026 is named for April 2026 and holds 11,194 fewer addresses than the WFS. Expect decimal commas, about 2% of rows without coordinates and more than half without a street name. Flat-level and entrance-level tables are also published, but they date from March-May 2024.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| "Adresy podľa krajov (csv)" (addresses by region), national file | Ministerstvo vnútra SR (MV SR, Ministry of Interior) | https://data.slovensko.sk/download?id=d22c42f3-82b5-450d-b8fb-4245d50a31ec (dataset page https://data.slovensko.sk/datasety/b27f57f1-7e76-45e0-8968-631f9176b2e9) | Columns `IDENTIFIKATOR;KRAJ;OKRES;OBEC;CAST_OBCE;ULICA;SUPISNE_CISLO;ORIENTACNE_CISLO_CELE;PSC;ADRBOD_X;ADRBOD_Y`: region, district, municipality, municipality part, street, registration number, orientation number, postcode, longitude, latitude. 1,739,536 rows, 35,190 of them without coordinates (OpenAddresses' processing record of 30 Oct 2026, not recounted). The dataset also has one CSV per region (eight) | Anonymous download, 162,404,526 bytes | CC0 | Declared quarterly; dataset modified 2026-08-21; file served as `Adresy podľa krajov UTF8_04_2026.csv` | confirmed |
| Flat and entrance tables ("Byty - konsolidované dáta", "Vchody - konsolidované dáta") | MV SR | Child datasets of the series "Register bytov" and "Register vchodov" in the national catalogue (query endpoint https://data.slovensko.sk/api/sparql); full download URLs not recorded | Flats CSV, 48,614,084 bytes, columns include `unitNumber`, `floor`, `buildingNumberIdentifier`. Entrances CSV, 1,097,609,571 bytes. Also an initial flats file of 21.5.2024 (`DI_BBP_09_Byt_20240521.zip`, 5,689,821 bytes). The same pattern exists for buildings, streets, municipalities, districts, regions and municipality parts | Anonymous download | Not recorded | Catalogue dates them March-May 2024 | corrected |
| Change batches "Register adries - Zmenové dávky od 27.5.2024 do 31.01.2025" | MV SR | https://data.slovensko.sk/datasety/de3dd18f-9124-4acb-ae00-705555332256 | 87 XML change files. A second, generic series holds an initial batch of 6.4.2018 and numbered batches from March 2024 | Anonymous download | Not recorded | Declared weekly; modified 2025-02-04; nothing newer found | confirmed |
| Municipal address datasets (Prešov, Vranov nad Topľou) | Municipalities, in the national catalogue | Catalogue endpoint https://data.slovensko.sk/api/sparql ; dataset URLs not recorded | "Register adries a stavieb v meste Prešov (k aktuálnemu dátumu)"; "Register adries v meste Vranov nad Topľou" | Not tested | Not recorded | Vranov nad Topľou record modified 2026-07-22 | confirmed (titles only) |
| Postcode file ("Poštové smerovacie čísla") | Slovenská pošta | http://www.posta.sk/subory/322/psc-obci-a-ulic.zip , which redirects to https://www.posta.sk/files/6811e10125b182cd7cd9e3a9/postove-smerovacie-cisla-na-stiahnutie.zip | `PSC-2026-10-29.zip`, 731,703 bytes: `OBCE.xlsx` (municipalities), `ULICE.xlsx` (streets), `POBoxy.xlsx` (PO boxes). The spreadsheets were not opened | Anonymous download | CC0 per the national catalogue record; no statement by Slovenská pošta itself | Files dated 2026-10-29 | corrected |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Slovakia | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/sk/countrywide.json) | The national CSV above, read from its live URL | Free download, needs a logged-in account | CC0 1.0, attribution not required | Processed 2026-10-30 (https://batch.openaddresses.io/api/job/946657) | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 1,704,346 Slovak addresses in release 2026-10-21.0 (publisher's figure) | GeoParquet, no account | Ministry of Interior, CC0 1.0 | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **Address register WFS, no key:** https://rageo.minv.sk/geoserver/ra/wfs (capabilities: https://rageo.minv.sk/geoserver/ra/wfs?service=WFS&version=2.0.0&request=GetCapabilities). Title "Mapová služba registra adries WFS", provider MV SR, fees NONE, access constraints NONE. Feature type `ra:address` ("Adresne body"), default CRS EPSG:4258, output as GML, GeoJSON, CSV, KML or zipped Shapefile. The default count limit is 1,000,000 features per request; the layer held 1,750,730 on 11 Nov 2026. A second feature type, `ra:mv_address_ui`, exists.
- **Fields returned by the WFS:** `identifier`, `uri_identifier` (`https://data.gov.sk/id/physical-address/<id>`), `fulladdress`, `streetname`, `street_id`, `postalcode`, `orientationnumber`, `propertyregistrationnumber`, municipality-part, LAU2, LAU1 and NUTS3 names and codes, `validfrom`, point geometry.
- **INSPIRE Addresses WFS:** https://rageo.minv.sk/geoserver/ad/wfs . Feature types `ad:Address`, `ad:AddressAreaName`, `ad:AdminUnitName`, `ad:PostalDescriptor`, `ad:ThoroughfareName`; fees NONE, access constraints NONE.
- **WMS:** on the same host at `/ra/wms` and `/ad/wms`.
- **Catalogue SPARQL endpoint:** https://data.slovensko.sk/api/sparql , anonymous. It is the practical way to read dataset metadata, because the dataset landing pages return only a JavaScript shell.
- **Postcode lookup page:** https://www.posta.sk/psc (interactive; the download link is not in the page's static HTML).
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- The CSV is behind the WFS: 1,739,536 rows against 1,750,730 address points on the same day. The WFS count was identical about ten hours apart, so how often the WFS itself is refreshed is not known.
- The CSV is semicolon-separated UTF-8 with decimal commas, for example `4320536;Banskobystrický;Banská Bystrica;Badín;;Banská;150;2;97632;19,121502;48,6661543`. Identifiers are not always numeric (`432057A` occurs).
- No coordinate reference system is stated in the CSV or its catalogue record. The values are degrees; the WFS declares EPSG:4258.
- Per OpenAddresses' processing record: 973,318 rows (56%) have no street name, 401 have no postcode, 35,190 have no coordinates. Many municipalities have no named streets, so those addresses carry only the registration number (*súpisné číslo*).
- `data.slovensko.sk` ignores HTTP `Range` requests and streams the whole file.
- The catalogue declares the series "Register adries" as updated daily and the national CSV as quarterly; the CSV served in November 2026 is named for April 2026.
- The old portal `data.gov.sk` redirects (302) to `data.slovensko.sk`.
- The per-table registers (buildings, entrances, streets, flats and others) show no files at the series level; the files hang on child datasets of each series.
- No change batch later than 31 January 2025 was found in a title search of the catalogue.
- Legal basis: Act 125/2015 Coll. (https://static.slov-lex.sk/static/SK/ZZ/2015/125/20240401.html). The register holds a postcode for every address and the position of every address point. The Act says data published on the ministry's website are of informative character.
- High-value datasets: the national CSV dataset is typed as a high-value dataset under Regulation (EU) 2023/138, category "Addresses". data.europa.eu lists 315 Slovak high-value datasets, nine of them in "Addresses", all from MV SR: addresses by region, "INSPIRE - Adresy" (modified 2024-12-05), the change batches and six road-section sets.
- The ministry's register page https://www.minv.sk/?register-adries describes the register but says nothing about open data.
- An older OpenStreetMap import page (https://wiki.openstreetmap.org/wiki/Sk:MinvSKAddress , last edited 19 March 2021) reports about 9,000 points with latitude and longitude swapped and some municipalities without address points at that time. It also states that the ministry's data are under CC0.

### Not free or not available

- **Current flat-level data:** only the March-May 2024 tables were found.
- **Change files after 31 January 2025:** none found in the national catalogue.
- **Statutory data supply:** the ministry provides register extracts on request; automated supply requires an agreement with the ministry (Act 125/2015, § 10).
- **ZBGIS (national topographic database, ÚGKK):** ordering data requires an order form (https://www.skgeodesy.sk/geoportal-en/zbgis/order/).

### Could not be verified

- The CSV row counts were not recounted: they come from OpenAddresses' processing record for the same URL. The figure of 973,158 rows without an orientation number has no source that could be checked.
- A licence statement from Slovenská pošta itself for the postcode file: the CC0 comes from a catalogue record made by the transport ministry in 2015-2020.
- Whether ZBGIS address or building layers are in ÚGKK's free download: the site shows "Download" entries, but they were not examined.
- Municipal address datasets named for Banská Bystrica, Trebišov, Trnava, Levice, Svidník and Myjava: several records titled "Register adries v meste" exist, but their publishers were not resolved.
- Licence of the flat, entrance and change-batch files: not recorded.
- Usage limits for the `rageo.minv.sk` services: none were found beyond "Fees NONE / AccessConstraints NONE", and the search was not repeated.

## Slovenia (SI)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes (per publisher; download not confirmed) | Register naslovov (GURS) | JGP portal, WFS, OGC API; no registration per GURS | CC BY 4.0 | Yes, EPSG:3794 | Yes, as postal-district code | Event-driven; no schedule published |

**In short.** Slovenia's *Register naslovov* (Register of Addresses), kept by the surveying authority GURS, is by GURS's own documents free, registration-free and under CC BY 4.0, through the download portal JGP, a WFS, an OGC API Features service and a REST address search. None of that could be confirmed on the live host: `ipi.eprostor.gov.si` answered every anonymous request with HTTP 407 on 11 Nov 2026, and OpenAddresses has not managed to pull the national file since 14 June 2024. Everything below about file format, columns, size and record count therefore comes from GURS documents, catalogue records and OpenAddresses' 2024 description, not from a download. Test the host from the network the import will run on before building on it.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Register naslovov, national file from JGP (*Javni geodetski podatki*, public geodetic data) | Geodetska uprava Republike Slovenije (GURS) | Portal https://ipi.eprostor.gov.si/jgp/ ; file URL as recorded by OpenAddresses: https://ipi.eprostor.gov.si/jgp-service-api/display-views/groups/121/composite-products/141/file?filterParam=DRZAVA&filterValue=1 | Per OpenAddresses' 2024 source definition: zipped CSV, UTF-8, EPSG:3794, columns `E`, `N`, `HS_STEVILKA` (house number), `HS_DODATEK` (suffix), `ULICA_NAZIV` (street), `NASELJE_NAZIV` (settlement), `OBCINA_NAZIV` (municipality), `STATISTICNA_REGIJA_NAZIV`, `POSTNI_OKOLIS_SIFRA` (postcode), `EID_HISNA_STEVILKA`. 573,634 rows in OpenAddresses' run of 14 June 2024 | Per GURS: free, no registration. Host answered HTTP 407 on 11 Nov 2026 | CC BY 4.0 | No schedule published; OpenAddresses labels the product "weekly" | unverified (live host refused; documents and third-party record only) |
| Register naslovov, register description | GURS | https://www.e-prostor.gov.si/podrocja/prostorske-enote-in-naslovi/register-naslovov/ | States the content: address number (identifier given by GURS), address (municipality, settlement, street, house number, suffix, apartment or business-premises number), address centroid inside the building footprint, and the spatial units containing it | Web page | - | - | confirmed |
| Public access rules and service list | GURS | https://www.e-prostor.gov.si/dostopi/javni-dostop/ and technical document https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx | Says public data are free and available without registration; names the services and field names | Web page and document | - | - | confirmed |
| General terms of use | GURS | https://www.e-prostor.gov.si/fileadmin/struktura/Preberi_me.docx (English, older: https://www.e-prostor.gov.si/fileadmin/struktura/EGP/General_terms.pdf) | CC BY 4.0 for GURS data; the list of covered data names "Register prostorskih enot" and "Register naslovov" | Document | - | Slovenian file replaced on 11 Nov 2026; English PDF last modified 1 Aug 2022 | corrected |
| "Register naslovov" on the national open data portal podatki.gov.si | GURS | Seen only as data.europa.eu record `register-naslovov`; podatki.gov.si answered HTTP 407 | Catalogue record with links to JGP (https://ipi.eprostor.gov.si/jgp/data), the WFS and the OGC API. No licence field filled | Not reached | Not filled in the record | Not recorded | corrected (catalogue record only) |
| Postcode list "Seznam poštnih številk za naslavljanje" | Pošta Slovenije | https://www.posta.si/zasebno-site/Documents/Seznami/Seznam%20po%C5%A1tnih%20%C5%A1tevilk%20za%20naslavljanje.pdf | PDF, 10 pages, 309,284 bytes: postcode and post office name, about 460 codes. No streets, no coordinates | Anonymous download | None stated | File last modified 7 Jun 2021 | corrected |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Slovenia | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/si/countrywide.json) | Register naslovov, countrywide: 573,634 addresses, each with number, street, city, district, region and postcode, no unit values (https://batch.openaddresses.io/api/job/399702). A buildings layer from a 2022 extract of the GURS building cadastre | Free download, needs a logged-in account | CC BY 4.0, attribution to GURS | Last successful address run 2024-06-14; the run of 2026-10-30 failed | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 580,213 Slovenian addresses in release 2026-10-21.0 (publisher's figure); not labelled as taken from OpenAddresses | GeoParquet, no account | GURS, CC BY 4.0 | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

All GURS services below are on `ipi.eprostor.gov.si`. They are documented by GURS or listed in catalogue records; none answered on 11 Nov 2026 (HTTP 407), so none was tested.

- **Register naslovov WFS:** https://ipi.eprostor.gov.si/wfs-si-gurs-rn/wfs?request=getCapabilities (GeoServer workspace SI.GURS.RN).
- **Register naslovov OGC API Features:** https://ipi.eprostor.gov.si/wfs-si-gurs-rn/ogc/features/collections .
- **REST address search:** `https://ipi.eprostor.gov.si/search-api/v1/external/iskanje/naslovi/?vir=Naslovi stavb&filter=trnje 10 4220` for building addresses including postcode, and the same call with `?vir=Naslovi stanovanj&filter=ziherlova 40b 202` for apartment-level addresses. Both examples are from the GURS technical document.
- **Cadastre WFS:** https://ipi.eprostor.gov.si/wfs-si-gurs-kn/wfs . The technical document's examples query house numbers there (feature types `NASLOVI_HS`, `HISNE_STEVILKE_H`) with fields `HS_STEVILKA`, `HS_DODATEK`, `ULICA_NAZIV`, `OBCINA_SIFRA`, `NASELJE_SIFRA`, `POSTNI_OKOLIS_SIFRA`, `POSTNI_OKOLIS_NAZIV`, `EID_HISNA_STEVILKA`.
- **Spatial units (RPE) services:** WMS https://ipi.eprostor.gov.si/wms-si-gurs-rpe/wms with a postal-district layer `SI.GURS.RPE:POSTNI_OKOLISI`; OGC API https://ipi.eprostor.gov.si/wfs-si-gurs-rpe/ogc/features/collections/ .
- **Service conditions per the technical document:** no registration or special rights needed; data are kept in SI-D96/TM and published as EPSG:3794, with output also in EPSG:4326, 3912, 3857 and 3035. One call returns at most a maximum set in the server configuration (no number given), and GURS reserves the right to limit this further. There is no uptime guarantee and no dedicated user support (general contact gurs@assist.si).
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- Access from the checking network failed on 11 Nov 2026: `ipi.eprostor.gov.si` (JGP pages, address WFS, OGC API) and `podatki.gov.si` answered HTTP 407 Proxy Authentication Required from an Apache front end; the GURS metadata catalogue `eprostor.gov.si/imps` reset the connection. Nothing was retried by another path.
- OpenAddresses' automated pull of the national file last succeeded on 14 June 2024; its run of 30 October 2026 failed. Overture nevertheless lists Slovenian addresses pulled on 15 October 2026.
- The register is new. GURS announced on 5 March 2024 that the Register naslovov was in use and the Register prostorskih enot (RPE, Register of Spatial Units) renewed: from 4 March 2024 house numbers left the RPE and are kept in the real-estate cadastre linked to buildings, and the old MID identifiers gave way to 18-digit EID keys (https://www.gov.si/novice/2024-03-05-izvedena-informacijska-prenova-registra-prostorskih-enot-in-v-uporabo-dan-register-naslovov/). The same notice says everyone can download RPE data in the new structure from JGP.
- Material written for the earlier route does not match the current one: the old EGP portal (`egp.gu.gov.si`) required registration and delivered Windows-1250 shapefiles (`RPE_PE.ZIP`, `RPE_PUL.ZIP`), and the Slovenian OpenStreetMap tooling still describes it (https://github.com/openstreetmap-si/GursAddressesForOSM).
- Licence terms: CC BY 4.0, commercial and non-commercial use, sharing and adaptation allowed. The required credit is "Geodetska uprava Republike Slovenije", the type of data, and the time the data refer to or the date of the database. The right of use ends at once if data are processed against the terms, and GURS may change data structure, services and terms at any time.
- The Slovenian terms file was replaced on the day of the check (dated "Ljubljana: 11. 11. 2026"). The points above are in the new text; it was not compared with the earlier version.
- The register holds apartment numbers and the REST search has an apartment-level source, but the national file OpenAddresses processed in 2024 had no unit values.
- Postcodes: postal districts (*poštni okoliši*) are spatial units in the RPE, and address features carry the postal-district code and name.
- Updates are event-driven (new address number, change in cadastral data, change in spatial-unit boundaries, names or codes). No schedule is published.
- High-value datasets: data.europa.eu shows none of 9,719 Slovenian datasets with the high-value flag. The register's INSPIRE metadata record (`728e9d6a-46d0-4242-b8ef-255317da2ff3`) and its open-data-portal record both carry "high value datasets" only as a keyword.
- Pošta Slovenije's addressing handbook (https://www.posta.si/zasebno-site/Documents/Priro%C4%8Dniki/Prirocnik-za-pravilno-naslavljanje-postnih-posiljk.pdf , January 2026) does not contain the postcode list; it links to the separate PDF listed above.

### Not free or not available

- **Postcode list as a spreadsheet or data file from Pošta Slovenije:** none found; only the PDF.

### Could not be verified

- The JGP portal itself and the national address file: whether the file URL still works, its format, file names, size, exact columns and current record count. The host answered HTTP 407. The only descriptions are OpenAddresses' 2024 source definition and its June 2024 count.
- The address WFS and OGC API: capabilities, feature-type names, paging limits and any throttling. Same refusal.
- The REST address search: documented, not requested.
- Why the host refuses: whether it rejects some automated or foreign clients, or whether this is policy, is not known.
- That an address number is never reused: this wording is not on the register page.
- A gov.si notice of 13 February 2025 about fixing deficient residence addresses: not located.
- Terms of use for Pošta Slovenije's postcode lists: none appear in the handbook or the list. A second linked PDF with special postcodes was not opened.
- The EU INSPIRE Geoportal record for the register: the site presented an expired TLS certificate and was not opened; its content was read from data.europa.eu's copy.

## Spain (ES)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | CartoCiudad (IGN / CNIG) | OGC API Features, paged, no key | CC BY 4.0 | yes, ETRS89 lon/lat (REGCAN95 in the Canaries) | yes | every four months |

**In short.** Use CartoCiudad: 15,662,297 address points for the whole country, with postcodes, under CC BY 4.0, served without a key by an OGC API Features collection and a REST geocoder. The same data exists as 52 provincial GeoPackage files, but the download centre that holds them gave a plain HTTP client no response at all on 2026-11-11, so plan the bulk import on the paged API. The cadastre's own address feed is the fallback, but it leaves out the Basque Country and Navarra (both publish their own files) and carries three conflicting rights statements.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| CartoCiudad postal addresses (Direcciones postales de CartoCiudad), OGC API Features collection `address` | Instituto Geográfico Nacional (IGN) / Centro Nacional de Información Geográfica (CNIG) | https://api-features.idee.es/collections/address | 15,662,297 address features for all of Spain: street name, number, number extension, postcode, administrative unit names, data provider, lon/lat point | No key. GeoJSON, paged through a `next` link | CC BY 4.0, attribution "scne.es" | Every four months (publisher: "Cuatrimestral") | confirmed |
| CartoCiudad download files | CNIG download centre (Centro de Descargas) | https://centrodedescargas.cnig.es/CentroDescargas/cartociudad ; metadata: https://www.idee.es/csw-codsi-idee/srv/api/records/spaign_cartociudad_addresses/formatters/xml | 52 GeoPackage files, one per province and autonomous city, with portals (building entrances), kilometre points and cadastral blocks; also a national CSV in four tables | Through the download centre. Its host gave a plain HTTP client no response on 2026-11-11 | CC BY 4.0 | Every four months | confirmed from the publisher's metadata; the download page itself unverified |
| Cadastre INSPIRE Addresses, ATOM feed | Dirección General del Catastro (cadastre directorate) | https://www.catastro.hacienda.gob.es/INSPIRE/Addresses/ES.SDGC.AD.atom.xml ; service page: https://www.catastro.hacienda.gob.es/webinspire/index.html | Address points as GML, one ZIP per municipality under 52 territorial offices. Street name, postcode, municipality, point (EPSG:25830 in the file checked), identifier that embeds the cadastral parcel reference. No Basque Country, no Navarra | No login. Direct file download | Conflicting: CC BY 4.0 in the metadata; a 2016 licence PDF that forbids redistributing the original data; "all rights reserved" in the top feed | Twice a year. Top feed dated 2026-08-21 | confirmed |
| Callejero del Censo Electoral (street directory of the electoral census) | Instituto Nacional de Estadística (INE) | https://www.ine.es/dyngs/DAB/es/index.htm?cid=1390 | Streets, pseudo-streets, street segments with their postal district, population units, census sections. No coordinates | ZIP of ASCII files, national and per province | CC BY 4.0 (INE legal notice) | Twice a year (January and July). Latest: July 2026 | confirmed |
| Postcode file of the postal operator | Correos | none | No open Correos download was found | - | - | - | none found |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Forward and reverse lookup of Spanish addresses: house number, street, city, postcode, coordinates. Declared source: "© Dirección General del Catastro" | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Not stated | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/es/countrywide.json | Countrywide layer built from the 52 CartoCiudad GeoPackages, with postcodes; a Navarra layer; four Catastro caches from 2021 | Free download, needs a logged-in account | CC BY 4.0 (CNIG) | Snapshot 2026-06-03, last run 2026-09-18 | confirmed |
| Overture Maps addresses, release 2026-10-21.0 | Overture Maps | https://docs.overturemaps.org/guides/addresses/ | 15,627,615 Spanish addresses (publisher's figure), taken from scne.es | GeoParquet, no account | CC BY 4.0 (scne.es) | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | ZIP file per country | CC BY 4.0 | Regenerated daily | confirmed |

### Regional sources

| Region | Source | Link | Access | Licence | Check |
|---|---|---|---|---|---|
| Navarra | Direcciones postales de Navarra (postal addresses of Navarra), Gobierno de Navarra, in OpenAddresses layout | https://administracionelectronica.navarra.es/AccesoFicheros/DownloadFile.aspx?codigoAcceso=OpenData&fichero=GestorDireccionesPostales%5COpenAddresses.zip | ZIP (2,865,734 bytes) with one CSV dated 2026-11-09, no login. Columns `idportal;number;street;unit;lon;lat;city;postcode;district;region`. The `lon` and `lat` columns hold projected metres; OpenAddresses records the CRS as EPSG:25830 | CC-BY 4.0 as recorded by OpenAddresses; the publisher's own statement was not seen | confirmed; publisher licence unverified |
| Basque Country | Portals (Atariak / Portales) of the Callejero de la Comunidad Autónoma del País Vasco (Basque street directory), Eustat | https://es.eustat.eus/productosServicios/idioma_c/kale_formu.html ; file for Araba: https://es.eustat.eus/comun/ExtractorBlob.ashx?id=01_Atariak_Portales.csv (the same pattern with `20_` for Gipuzkoa and `48_` for Bizkaia, and `.xlsx`) | CSV or XLSX per historical territory, no registration. Columns include postcode, ETRS89 UTM x/y, ETRS89 lat/lon and a portal key | CC BY 3.0 (catalogue record https://datos.gob.es/es/catalogo/e0dat0002-callejero-de-la-comunidad-autonoma-del-pais-vasco and its metadata record) | corrected |
| Basque Country | NORA localisation service (REST API) | https://www.geo.euskadi.eus/api-rest-nora/webgeo00-content/es/ ; developer rules: https://www.euskadi.eus/contenidos/informacion/api_rest_nora/es_def/adjuntos/Nora_Normativa_Desarrollo_Ext.pdf | REST API. The documentation (dated 30/07/2025) was read; the API itself was not called | CC BY 4.0 with the mention "Eusko Jaurlaritza / Gobierno Vasco; Eustat; geoEuskadi" (https://www.euskadi.eus/web01-bopv/es/bopv2/datos/2024/06/2402884a.epub) | confirmed |
| Catalonia | Adreces simplificat (simplified addresses), an extract of the Database of Municipal Addresses of Catalonia, ICGC | https://www.icgc.cat/en/Geoinformation-and-Maps/Data-and-products/Cartographic-geoinformation/Simplified-addresses ; files: https://datacloud.icgc.cat/datacloud/adreces-simplificat/csv/ | ZIP of CSV files, UTF-8, ETRS89 UTM 31N, no registration. Latest: `adreces-simplificat-v1r0-20261009.zip` (48,621,862 bytes) with nine CSVs, among them the tables `adrecavia` and `adrecaedi` | CC BY 4.0 | confirmed; row counts unverified |
| Catalonia | Adreces INSPIRE de Catalunya (INSPIRE addresses of Catalonia) | https://datos.gob.es/es/catalogo/e0dat0002-direcciones-inspire-de-cataluna | INSPIRE ATOM download service and WMS | CC BY 4.0 | confirmed |
| Andalucía | Callejero Digital de Andalucía Unificado (CDAU, unified digital street directory), Instituto de Estadística y Cartografía de Andalucía | https://datos.gob.es/en/catalogo/e0dat0002-callejero-digital-de-andalucia-unificado ; download application: https://www.callejerodeandalucia.es/descargas/ (described at https://www.callejerodeandalucia.es/portal/aplicaci%C3%B3n-de-descarga) | Streets and building portals for every Andalusian municipality. Asynchronous download per province or for all provinces: streets, portals, segments (SHP) or all layers (GPKG). Also WFS and WMS. No login wording on the pages; no download job was run | CC BY 4.0 | confirmed |
| Madrid (city) | Callejero oficial del Ayuntamiento de Madrid (official street directory), with the resource "Relación de direcciones vigentes, con coordenadas" (current addresses with coordinates) | https://datos.madrid.es/en/dataset/213605-0-callejero-oficial-madrid | Open data portal download. Updated weekly; update date 10 November 2026 | CC BY 4.0 | confirmed |
| Barcelona, Donostia / San Sebastián, València, Cáceres, Terrassa | Municipal address datasets in the national catalogue: "Adreces postals elementals de la ciutat de Barcelona", "Direcciones postales activas de Donostia / San Sebastián", "Portales de las calles" (València), "Portales Cáceres", "Adreces de Terrassa (carrer-número)" | https://datos.gob.es/apidata/catalog/dataset/title/direcciones?_pageSize=60&_page=0 ; https://datos.gob.es/apidata/catalog/dataset/title/portales?_pageSize=60&_page=0 | Catalogue entries only; formats and download routes were not examined | Not examined | confirmed (existence only) |

### Free APIs and services

- **CartoCiudad OGC API Features**, https://api-features.idee.es/collections/address/items?f=json&limit=1 : no key. The collection ("AD Dirección") reported `numberMatched` 15,662,297. Each feature has `component_ThoroughfareName`, `locator_designator_addressNumber`, `locator_designator_addressNumberExtension`, `component_PostalDescriptor` (postcode), `component_AdminUnitName_2/3/4`, `component_AddressAreaName`, `dataProvider`, `beginLifespanVersion` and a lon/lat point. Storage CRS is CRS84; 17 CRS are offered, among them EPSG:4258, 4326, 3857, 3035 and 25828-25831. Paging uses a `next` link. The server accepts `limit=10000`.
- **CartoCiudad REST geocoder**, under https://www.cartociudad.es/geocoder/api/geocoder/ : operations `candidates` (search and autocomplete), `find` (returns geometry) and `reverseGeocode` (nearest portal or kilometre point within 350 m, EPSG:4326). No key. A test call (https://www.cartociudad.es/geocoder/api/geocoder/candidates?q=calle%20iglesia%205,%20madrid&limit=2) returned a portal with `postalCode`, `lat`, `lng`, `refCatastral`, `muniCode` and `provinceCode`. Code and documentation: https://github.com/IDEESpain/Cartociudad (EUPL-1.2). Services page: https://www.cartociudad.es/web/portal/servicios
- **CartoCiudad INSPIRE WFS 2.0**, https://www.cartociudad.es/wfs-inspire/direcciones?service=WFS&request=GetCapabilities : feature types Dirección (address), Nombre de vía (street name), Descriptor Postal (postal descriptor) and Nombre de Unidad Administrativa (administrative unit name). The capabilities state "CC BY 4.0 scne.es" and no fees.
- **CartoCiudad WMS**, https://www.cartociudad.es/wms-inspire/direcciones-ccpp ("Direcciones y códigos postales de España"), with a view-only postcode layer from Grupo Correos. **WPS**, http://www.cartociudad.es/wps/WebProcessingService (WPS 1.0.0). The services page also lists route and service-area REST operations.
- **Rate limits and terms of use for the CartoCiudad services**: none found. Searched: the services page and the WFS and WMS capabilities, which say "No se aplican condiciones" (no conditions apply).
- **ICGC geocoder (Catalonia)**, https://eines.icgc.cat/geocodificador/autocompletar?text=Carrer%20de%20Balmes%20100%20Barcelona&size=1 : REST with autocomplete and reverse endpoints, JSON, no key. The test call returned the portal, postcode 08008 and coordinates. Documentation: https://openicgc.github.io/geocodificador-doc_en
- **NORA (Basque Country)**: REST localisation API, see the regional table.
- **CDAU (Andalucía)**: WFS and WMS, listed in the catalogue record in the regional table.
- **GISCO Address API (Eurostat)**, https://gisco-services.ec.europa.eu/addressapi : no key, lookup only. A reverse request for a point in Madrid returned house number 5, street "CL IGLESIA", city Madrid, postcode 28019.

### Caveats and recent changes

- The CNIG download centre (`centrodedescargas.cnig.es`) completed the TLS handshake and then closed the connection without an HTTP response, four times, to a plain `curl` client on 2026-11-11. Everything known only from its pages is listed under "Could not be verified".
- CartoCiudad is an aggregate. Its May 2026 source list (https://www.idee.es/resources/documentos/Cartociudad/Fuentes_direcciones.pdf) names the IGN transport network, the Catastro, the Basque Government, CDAU, IDE Catalunya, La Rioja, Navarra, the Institut Cartogràfic Valencià, the Comunidad de Madrid, the Balearic Islands and 14 municipalities. Each API feature names its `dataProvider`.
- Point position varies by source. For Catastro-sourced points the publisher says the portal is placed at the building entrance where possible and otherwise at the centroid of the cadastral parcel. In one Catastro municipality file (Ajalvir, https://www.catastro.hacienda.gob.es/INSPIRE/Addresses/28/28002-AJALVIR/A.ES.SDGC.AD.28002.zip) 1,748 of 1,931 addresses are marked Entrance and 183 Parcel.
- The Catastro feed has three rights statements. The metadata record (https://www.idee.es/csw-codsi-idee/srv/api/records/ES_SDGC_AD) says "CC BY 4.0 DG Catastro" and no limits on public access. The licence PDF still linked from the Catastro INSPIRE page (version 1.0, July 2016, https://www.catastro.hacienda.gob.es/webinspire/documentos/Licencia.pdf) allows commercial use only of transformed information, forbids distributing the original data, forbids the label "cartografía catastral" on derived products and allows suspension for heavy downloading. The top ATOM feed says "all rights reserved", while the per-office feeds say the service is free in every instance if the Catastro is named as author and owner. Whether CC BY 4.0 has formally replaced the 2016 text is unresolved. CartoCiudad, by contrast, states CC BY 4.0 consistently.
- Catastro covers about 95% of the territory under its responsibility and excludes the Basque Country and Navarra. CartoCiudad does include them.
- Counts do not agree across CartoCiudad products. A CNIG paper (https://www.idee.es/resources/documentos/Cartociudad/JIIDE/2024_publicacion_datos_geoespaciales_alto_valor_cartociudad.pdf) gives 19 million postal addresses in the geocoder as of June 2024; the API collection held 15,662,297 in November 2026. No source explains the difference.
- The update frequency is "Cuatrimestral" (four-monthly) in the publisher's source list, but the metadata record codes it as `quarterly`.
- The catalogue record for CartoCiudad says Correos postcodes "no están disponibles para su descarga, solo se pueden visualizar" (not downloadable, view only). The postcode of each address is nonetheless delivered by the API and the geocoder.
- CartoCiudad's catalogue record carries the High-Value Dataset categories Geospatial and Addresses. The Catastro address metadata carries the keyword "High-value dataset". CDAU is tagged Addresses and Geospatial; the Basque street directory and the Catalan INSPIRE addresses are tagged Geospatial only.
- IGN's licence conditions (http://www.ign.es/resources/licencia/Condiciones_licenciaUso_IGN.pdf) say that use implies acceptance of a CC-BY 4.0 licence; the policy behind it is Orden FOM/2807/2015 (https://www.boe.es/boe/dias/2015/12/26/pdfs/BOE-A-2015-14129.pdf). Attribution is required.
- INE: the record layout of the street directory changed with the July 2025 publication, and INE's page is ambiguous about which layout the January 2025 files use. A file of changes for January-July 2026 is provided. The page footer tooltip says "CC BY-SA 4.0", but INE's legal notice (https://www.ine.es/dyngs/AYU/index.htm?cid=125) sets CC BY 4.0.
- Navarra: the columns named `lon` and `lat` hold projected metre values, not degrees.
- Catalonia: the ICGC page still shows "Publication date: April 2026" although an October 2026 file is in the download directory.
- Basque Country: the NORA developer document carries a confidentiality notice on its cover although it is served publicly.
- OpenAddresses' Spanish snapshot dates from 2026-06-03, so it trails the current CartoCiudad data.

### Not free or not available

- Correos postcode data: no open download found. Searched: the CartoCiudad pages and catalogue records only; Correos' own products and prices were not examined.
- Basque Country and Navarra are absent from the Catastro address feed; use the regional sources or CartoCiudad.
- Comunidad de Madrid: the download link given in CNIG's source list (http://www.madrid.org/nomecalles/DescargaBDTCorte.icm) returned HTTP 404 on 2026-11-11.
- Unattended download of the CartoCiudad GeoPackage and CSV files: not achieved; the download centre did not answer a plain HTTP client.
- GISCO Address API: lookup only, no bulk download, no licence stated.

### Could not be verified

- Known only from the CNIG download centre, which gave no HTTP response: the example GeoPackage sizes (A Coruña 51.24 MB, Barcelona 141.81 MB, Araba/Álava 2.84 MB, Ceuta 1.04 MB); that road geometries are left out of the files; the layer names `portalpk_publi` and `manzana` and the attribute list of specification v15 (PDF dated 2025-12-18), including that the postcode is mandatory; that each cycle regenerates the dataset completely; the release log (latest release 10-11-2026; switch to GeoPackage on 10-06-2024); that the download page cites Orden FOM/2807/2015; the `candidates` filters (`comunidad_autonoma_filter`, `provincia_filter`, `municipio_filter`, `poblacion_filter`).
- That file downloads from the download centre pass a reCAPTCHA v3 check and an automated-browser check, with an optional login: the page source could not be obtained. The total size and record count of the 52 GeoPackages were never measured.
- The date of the current CartoCiudad data. Only weak evidence was seen: the metadata record has revision date 2026-09-01, and the one API feature fetched has `beginLifespanVersion` 2026-09-11.
- That an API request with `limit=10000` returns 10,000 features: the server answered HTTP 200 but the body was not counted.
- Catastro address WFS (https://ovc.catastro.meh.es/INSPIRE/wfsAD.aspx?SERVICE=WFS&REQUEST=GetCapabilities&VERSION=2.0.0): answered HTTP 400 "No se puede procesar su petición" twice on 2026-11-11; no capabilities document was seen.
- Navarra: the row count of 181,197 is a researcher's count; only the first 2 MB of the file was re-read (about 183,600 rows by proportion). The publisher's licence statement was not seen because the dataset page (https://gobiernoabierto.navarra.es/es/open-data/datos/direcciones-postales-navarra) timed out.
- Catalonia: 1,673,367 rows in `adrecavia` (described as street-number addresses) and 57,228 in `adrecaedi` (named buildings), and the column names `codpostal`, `coor_utmx`, `coor_utmy`, are a researcher's count and reading; the 48.6 MB file was not downloaded again. Table names and sizes were confirmed.
- A Bilbao municipal address dataset: not present in either catalogue search.

## Sweden (SE)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | Belägenhetsadress (Lantmäteriet); login-gated, application must be approved | GeoPackage per municipality, Geotorget account plus approved application | CC BY 4.0 plus personal-data conditions | Yes, EPSG:3006 | Not verified for the bulk product | Daily |

**In short.** The national address data is "Belägenhetsadress" (location address) from Lantmäteriet, the Swedish mapping, cadastral and land registration authority. It costs nothing and is licensed CC BY 4.0, but it is not anonymous: a Geotorget account and an approved application per product are needed, and the application must state how personal data will be processed. The download server answers 401 without credentials. The trap is the approval step and the conditions that come with it (purpose limits, EU/EEA storage, revocable access); they sit on top of the CC BY 4.0 licence.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Belägenhetsadress Nedladdning, vektor (bulk download) | Lantmäteriet | Product page: https://geotorget.lantmateriet.se/geodataprodukter/belagenhetsadress-nedladdning-vektor-api ; STAC collection: https://api.lantmateriet.se/stac-vektor/v1/collections/belagenhetsadresser ; STAC items: https://api.lantmateriet.se/stac-vektor/v1/collections/belagenhetsadresser/items?limit=1000 ; file example: https://dl1.lantmateriet.se/adress/belagenhetsadresser/belagenhetsadresser_kn2584.zip | Addresses from the address part of the Real Property Register ("fastighetsregistrets adressdel"). 290 zipped GeoPackages, one per municipality; 324,550,419 bytes in total on 2026-11-11. EPSG:3006 (SWEREF 99 TM) | The STAC catalogue is open without credentials. The files answer `401 Unauthorized` (`WWW-Authenticate: Basic realm="Authorization Server"`). Needs a Geotorget account and an approved application for the product | CC BY 4.0, with the terms "Användningsvillkor för värdefulla datamängder som innehåller personuppgifter" (terms of use for high-value datasets containing personal data), version 1.1, 2025-03-04 | Daily; items refreshed around 11:24 UTC | confirmed |
| INSPIRE Addresses ATOM feed | Lantmäteriet | https://api.lantmateriet.se/belagenhetsadress/atom/v1.2/inspire/ad | 290 municipality entries, EPSG:3006 and EPSG:4258. The INSPIRE dataset gives location by street name, street number and postcode ("gatunamn, gatunummer och postnummer"), adapted to scale 1:10 000 | The feed is readable without credentials. The dataset files behind it answer 401 "Missing Credentials" | Feed rights text: "Avtal för användning krävs, avgifter för användning tas ut" (agreement required, fees charged) | Entries dated 30 September to 1 October 2024 | confirmed |
| Municipal open data: Helsingborg "Adresser" and "Postnummer" | Helsingborg municipality | Found through `https://data.europa.eu/api/hub/search/search?q=postnummer+postnummerområden&filter=dataset&limit=25&facets={"country":["se"]}` | Municipal addresses and postcodes. Contents were not examined | Listed on data.europa.eu | CC BY 4.0 | 2022 | confirmed |
| Official national postcode file | - | - | None found. Searched: data.europa.eu (no national postcode dataset from Lantmäteriet, PostNord, PTS or SCB) and the SCB open geodata page. PostNord's own site was not checked | - | - | - | none found |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Sweden | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Sweden | OpenAddresses | https://batch.openaddresses.io ; source definitions: https://github.com/openaddresses/openaddresses/tree/master/sources/se | 18 municipal sources, no countrywide source. Example: Stockholm, from a 2016 cache (https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/se/municipality_of_stockholm.json) | Free download, needs a logged-in account | Stockholm source: no licence recorded | Stockholm: 2016 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **Lantmäteriet STAC catalogue** (https://api.lantmateriet.se/stac-vektor/v1/collections/belagenhetsadresser): open without credentials. It lists the 290 files with size, `created` and `updated` stamps, so a script can see what changed. Only the file fetch needs the Geotorget credentials.
- **Belägenhetsadress Direkt** (the address query API): access point https://api.lantmateriet.se/distribution/produkter/belagenhetsadress/v4.2 ; product page https://geotorget.lantmateriet.se/geodataprodukter/belagenhetsadress-direkt-api . A bare GET on the access point answers HTTP 405. Its terms and rate limits could not be read.
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.

### Caveats and recent changes

- **Registration and review.** The steps (https://www.lantmateriet.se/sv/geodata/vara-produkter/avgiftsfria-produkter/): create a Geotorget account as a private person, or apply for an organisation account; organisation users also create a system account; then apply for authorisation, one per product. Some products need a purpose review under the Real Property Register Act; products with personal data need acceptance of terms and a statement of how the personal data will be processed.
- **No right of access.** Lantmäteriet states that the Open Data Act "does not give a right to access data from Lantmäteriet"; data protection law, the Real Property Register Act and secrecy law take precedence. For high-value datasets with personal data or property-register information, Lantmäteriet must judge that nothing prevents access, through an application form in Geotorget (https://www.lantmateriet.se/sv/geotorget-produktstod/om-tillhandahallandet/).
- **Conditions on top of CC BY 4.0** (https://www.lantmateriet.se/globalassets/geodata/geodataprodukter/anvandningsvillkor_for_vardefulla_datamangder_pu.pdf). Commercial use is allowed. When publishing, state the product name, "©Lantmäteriet", whether the data was processed, and that CC BY 4.0 applies. Clause 3.3: personal data may be processed only for the purposes stated in the application and approved by decision. Clause 3.4: take only the personal data that is necessary. Clause 3.5: process and store personal data only within the EU/EEA unless the decision says otherwise; US-owned cloud only under the EU-US Data Privacy Framework. Lantmäteriet may run spot checks and may revoke or change access.
- Free since early 2025: the STAC items carry `created` 2025-02-03 and the terms are dated 2025-03-04. No dated official announcement of the release was found.
- Lantmäteriet names addresses among the high-value datasets it holds. High-value datasets "ska vara avgiftsfria, tillgängliga för vidareutnyttjande enligt CC BY 4.0 eller lägre samt tillhandahållas i öppna format via API:er och för bulknedladdning" (free of charge, reusable under CC BY 4.0 or less, in open formats through APIs and bulk download). Legal basis as stated by Lantmäteriet: Directive (EU) 2019/1024, the Swedish Open Data Act (2022:818), Implementing Regulation (EU) 2023/138.
- On data.europa.eu the "Belägenhetsadress" record in catalogue `oppnadata` is flagged `is_hvd: true` (modified 2026-02-24). The same dataset's twin record in catalogue `geodata-se` shows `is_hvd: false`, and so do the INSPIRE dataset records.
- Lantmäteriet's "öppna data" (open data) are a separate group under CC0 with no attribution requirement (https://www.lantmateriet.se/sv/geodata/vara-produkter/avgiftsfria-produkter/oppna-data/). The product list has three filters: Öppna data, Värdefulla datamängder (high-value datasets), Avgiftsfria produkter (free products). The address data comes under the high-value-dataset terms, not CC0.
- The INSPIRE ATOM feed is stale (entries from autumn 2024), its rights text still speaks of fees, and its files need credentials. It is not a keyless way in.
- **Malmö withdrew its open address data.** Malmö stad stopped publishing address data on its open data portal from 2026-09-01: publication "is not compatible with current licence terms under the geodata cooperation with Lantmäteriet", which restrict reuse and sharing with third parties. Read on the data.europa.eu record, not on Malmö's own portal.
- Product pages on lantmateriet.se redirect to Geotorget, whose product pages are JavaScript-only.
- Community reports, not official (https://community.openstreetmap.org/t/lantmateriet-belagenhetsadress/127427): an applicant who stated an OpenStreetMap import as the purpose was approved and reported access to "alle 3.7 millioner adresser i Sverige" (15 March 2025); another contributor wrote that the download product lacks the building-entrance link that the Byggnad Direkt service has.

### Not free or not available

- Anonymous download of the national address data: not available. Every file request needs Geotorget credentials.
- A free official national postcode file: none found. Searched: data.europa.eu (query "postnummer postnummerområden", Sweden) returned no national postcode dataset from Lantmäteriet, PostNord, PTS or SCB, only municipal ones and a 2012 metadata record of the commercial "Postnummerservice Norden AB"; the SCB open geodata page (https://www.scb.se/vara-tjanster/oppna-data/oppna-geodata/) has no postcode entry. PostNord's own site was not checked.
- OpenAddresses has no countrywide Swedish source, only 18 municipalities.
- Overture Maps addresses (release 2026-10-21.0) does not include Sweden.
- Malmö's municipal open address dataset: withdrawn from 2026-09-01.

### Could not be verified

- The attribute list of the free bulk product, in particular whether it carries postcode and post town, entrance-level points and apartment numbers: the GeoPackage needs credentials and the Geotorget documentation is a JavaScript application. Postcodes are confirmed only in the description of the INSPIRE dataset.
- The exact release date: no dated official announcement was found. "February 2025" rests on the STAC `created` field (2025-02-03).
- The price before the change (LMFS 2023:2): the regulation was not opened.
- Rate limits and current terms of Belägenhetsadress Direkt: the documentation sits behind the JavaScript Geotorget page.
- Address or postcode products of Statistics Sweden (SCB): only its open geodata page was read.
- An official national address count: the 3.7 million figure is from a community forum post.
