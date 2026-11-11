# Pan-European and cross-border sources of free online address data (EU-27) - state as of 11 November 2026

*Verification note: items marked "queried 2026-11-11" are live API/HTTP checks made for these notes on 11 Nov 2026 (about 00:15-00:30 UTC); the linked URL is the endpoint that was called. Items marked "search summary only" come from a search-engine summary of the linked page and were not read in full.*

## 1. EU legal framework: High-Value Datasets Implementing Regulation (EU) 2023/138 and addresses

### Takeaway
Since 9 June 2024 every Member State must publish national-coverage address data (identifier, geometry, house number, street name, admin units, postcode, last-update date) free of charge under CC BY 4.0 or a less restrictive licence, via both API and bulk download. No official per-country compliance table for addresses was found; the only machine-checkable evidence (data.europa.eu HVD tags) shows just 8 of 27 Member States tagging any dataset as HVD "Addresses", and that tag is clearly under-used rather than a true compliance measure.

### Cited Findings

**What the Regulation requires for addresses**
- "Addresses" is one of the datasets of the Geospatial category (Annex, section 1.1), alongside administrative units, geographical names, buildings and cadastral parcels, all defined by reference to the INSPIRE themes of Directive 2007/2/EC — [EUR-Lex, Reg. (EU) 2023/138](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- Key attributes listed for Addresses: "Unique identifier; Geometry; Address locator (e.g. house number); Thoroughfare (street) name; Administrative units (e.g. municipality, province, country); Postal descriptor (e.g. post code); Date of last update" — [EUR-Lex, Reg. (EU) 2023/138, Annex 1.1](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- Granularity for Addresses is "N/A" in the Annex table; geographical coverage is "Single or multiple datasets that shall cover the entire Member State when combined" — [EUR-Lex, Reg. (EU) 2023/138, Annex 1.1](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- Publication arrangements (Annex 1.2(a)): datasets must be available "under the conditions of the Creative Commons BY 4.0 licence or any equivalent or less restrictive open licence", "in a publicly documented, Union or internationally recognised open, machine-readable format", through APIs **and** bulk download, and in their most up-to-date version — [EUR-Lex, Reg. (EU) 2023/138, Annex 1.2](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- Metadata for INSPIRE-theme datasets must contain at least the elements of Commission Regulation (EC) No 1205/2008 (Annex 1.2(b)); Article 3(3) requires API documentation in an open, human- and machine-readable format — [EUR-Lex, Reg. (EU) 2023/138](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- The Commission summarises the HVD rules as: free of charge, machine-readable, via APIs and, where relevant, bulk download; HVDs may be re-used for any purpose — [European Commission, HVD Q&A (page last updated 20 Dec 2023)](https://digital-strategy.ec.europa.eu/en/faqs/high-value-datasets-questions-and-answers)

**Dates**
- Article 6: entry into force on the twentieth day after publication in the Official Journal; application "from 16 months after entry into force". The text gives no calendar dates; OJ publication was 20.1.2023 — [EUR-Lex, Reg. (EU) 2023/138, Art. 6](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- The Commission states public authorities must make all listed datasets available "from 9 June 2024" — [European Commission, HVD Q&A](https://digital-strategy.ec.europa.eu/en/faqs/high-value-datasets-questions-and-answers)
- The regulation was "adopted in December 2022 and published in January 2023" and is "effective since June 2024" — [Open Data Maturity Report 2025, pp. 11 and 36](https://data.europa.eu/sites/default/files/2025-12/2025_odm_report_7.pdf)

**Exemptions / derogations**
- Recital 6: the free-of-charge requirement does not apply to libraries (including university libraries), museums and archives; Member States "may exempt individual public sector bodies, upon their request" for "a period not exceeding two years" from entry into force (Article 14(5) of Directive (EU) 2019/1024) — [EUR-Lex, Reg. (EU) 2023/138, recital 6](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- Article 4(1): any exemption granted under Article 14(5) of the Directive "shall be published online" — [EUR-Lex, Reg. (EU) 2023/138, Art. 4](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- Recital 7: data held by public undertakings is outside the Regulation's scope — [EUR-Lex, Reg. (EU) 2023/138, recital 7](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- HVDs "in principle do not cover personal data"; where Member State law excludes data from access on data-protection grounds it falls outside the Open Data Directive — [European Commission, HVD Q&A](https://digital-strategy.ec.europa.eu/en/faqs/high-value-datasets-questions-and-answers)

**Reporting and monitoring**
- Article 5: Member States report to the Commission "by 2 years after entry into force" and then on request (intended every 2 years); reports must list the datasets with metadata references, persistent links to licences and to APIs, guidance documents, DPIAs where available, and the number of bodies exempted under Article 14(5) — [EUR-Lex, Reg. (EU) 2023/138, Art. 5](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32023R0138)
- All 27 Member States self-report that they are "working towards applying" the Regulation; 25 (93 %) report that public bodies denote HVDs in metadata (most recent additions: DK, ES, MT, RO) — [ODM Report 2025, Table 8, p. 36](https://data.europa.eu/sites/default/files/2025-12/2025_odm_report_7.pdf)
- Self-reported maturity by category: statistics 82 %, geospatial 79 %, earth observation/environment 77 %, mobility 75 %, companies 72 %, meteorological 70 %; by requirement: machine-readable formats via APIs 73 %, bulk download 73 % (the lowest-scoring requirements) — [ODM Report 2025, pp. 11 and 37](https://data.europa.eu/sites/default/files/2025-12/2025_odm_report_7.pdf)
- Denmark, Estonia, France, Latvia, Lithuania and Finland self-report an HVD implementation maturity of 95 % or higher; Bulgaria, Croatia and Hungary each score below 50 % — [ODM Report 2025, p. 37](https://data.europa.eu/sites/default/files/2025-12/2025_odm_report_7.pdf)
- The ODM 2025 report is internally inconsistent on the DCAT-AP HVD tag: p. 11 says 17 Member States (63 %) implemented it, Table 41 says 21 (78 %) — [ODM Report 2025, pp. 11 and 90-91](https://data.europa.eu/sites/default/files/2025-12/2025_odm_report_7.pdf)

**Per-country evidence for addresses (data.europa.eu HVD tags)**
- The DCAT-AP HVD category code for "Addresses" is `http://data.europa.eu/bna/c_c3de25e4`; "Geospatial" is `c_ac64a52d` (labels resolved via the portal's SPARQL endpoint, queried 2026-11-11) — [data.europa.eu SPARQL endpoint](https://data.europa.eu/sparql)
- 79 dataset records on data.europa.eu carry the HVD category "Addresses", from only 8 Member States: AT 45, ES 18, SK 9, BE 3, CZ 1, HR 1, LT 1, LU 1 (queried 2026-11-11) — [data.europa.eu search API, hvdCategory=c_c3de25e4](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- Those records include: AT - BEV "Address register INSPIRE" and "Address Relational tables" half-yearly snapshots (hence 45 records; latest reference date 01.10.2026); BE - "BeStAddress" / "Addresses BeSt, full download XML"; CZ - "INSPIRE theme Addresses (AD)" (ČÚZK); HR - "Addresses INSPIRE"; LT - "Annex I. INSPIRE Dataset for Addresses Theme"; LU - "INSPIRE - Annex I Theme Addresses - Addresses"; SK - "INSPIRE - Addresses", "Addresses by region (csv)", "Address Register - Change batches"; ES - DG Cadastre addresses, CartoCiudad postal addresses, Navarre, Gipuzkoa, Bizkaia, Andalusia, Madrid, La Rioja (queried 2026-11-11) — [data.europa.eu search API, hvdCategory=c_c3de25e4, limit=60](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=60&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- Several Slovak records tagged "Addresses" are actually "Road sections" datasets, i.e. the tag is not always applied correctly (queried 2026-11-11) — [data.europa.eu search API, hvdCategory=c_c3de25e4, limit=60](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=60&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- 3,621 records carry the top-level HVD category "Geospatial"; country facet: ES 992, DE 985, LV 544, AT 303, GR 234, IE 127, IT 85, LT 68, BE 65, SE 61, FI 48, EE 23, LU 22, FR 12, PT 12, DK 7, MT 4, NL 3, HR 1 (plus non-EU). No "Geospatial"-tagged records appear for BG, CY, CZ, HU, PL, RO, SI, SK (CZ and SK tag the "Addresses" sub-category only) (queried 2026-11-11) — [data.europa.eu search API, hvdCategory=c_ac64a52d](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_ac64a52d%22%5D%7D)
- An independent census of data.europa.eu dated 3 Oct 2026 found 27,972 HVD-flagged records (27,909 from Member States), zero HVD-flagged records for 7 Member States (BG, CY, HU, PL, RO, SI, SK), 2,275 "geospatial" records, 61.1 % of records with a licence meeting the Regulation under the authors' own rules, and only 18.4 % with a modelled Data Service (API). Reliability caveat: self-described "working draft" by a small Madrid software cooperative, with data collection, analysis and drafting done by AI agents — [EasyxLab study S17](https://easybyte.es/lab/studies/s17/paper/); partly contradicted by the live query above, which on 11 Nov 2026 returns 9 Slovak records with an HVD "Addresses" category and 3,621 "Geospatial" records — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)

**Why HVD matters relative to INSPIRE**
- The INSPIRE Directive itself does not force open address data: only discovery and view services must be free to the public (Art. 14(1)); download services may be charged for (Art. 14(4)), and metadata only has to state access conditions and fees (Art. 5(2)(b)) — [EUR-Lex, Directive 2007/2/EC](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32007L0002)

**Pending changes to the framework**
- The Commission's Data Union Strategy (COM(2025) 835, 19 Nov 2025) says: "In 2026, the Commission will propose to expand the list of high-value datasets to cover legal, judicial, administrative and other data" (action scheduled Q4 2026), and that rules "now split between the DGA and the Open Data Directive will be kept and merged into one Data Act chapter" — [EUR-Lex, COM(2025) 835 final](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=CELEX:52025DC0835)
- The Digital Omnibus proposal (COM(2025) 837) would repeal the Open Data Directive and move its re-use rules into the Data Act (search summary only) — [Kennedys, "Repeals in the Digital Omnibus Regulation Proposal" (2026)](https://www.kennedyslaw.com/en/thought-leadership/article/2026/repeals-effected-by-the-digital-omnibus-regulation-proposal/)
- As far as could be established the Omnibus was not adopted by Nov 2026: Council did not adopt a compromise text at the end of June 2026, and the file (2025/0360(COD)) was still awaiting a committee decision in Parliament in September 2026 (search summary only, advocacy source) — [EDRi, "The Digital Omnibus is going on summer break"](https://edri.org/our-work/the-digital-omnibus-is-going-on-summer-break-your-rights-are-not/)

### Inferences
- Publication in OJ L 19 of 20.1.2023 gives entry into force on 9 February 2023, application on 9 June 2024, the first Article 5 reports due around 9 February 2025 (next round around February 2027), and the latest possible end of any Article 14(5) two-year exemption around 9 February 2025. All such temporary exemptions should therefore have lapsed well before November 2026 (dates derived from the Regulation's text, not stated in it).
- The HVD "Addresses" tag on data.europa.eu is a floor, not a compliance list: countries known from other sections of these notes to publish open national address data under CC BY 4.0/CC0 (e.g. NL, DK, EE, FI, FR, LV, PL, SI) have no record with this tag, while AT alone accounts for 45 of 79 records because it tags each half-yearly snapshot.
- Self-reported ODM scores (geospatial 79 %, API/bulk 73 %) imply that as of late 2025 a material share of Member States had not finished the technical HVD requirements; BG, HR and HU are the named laggards overall, but the report gives no address-specific data.
- Because the Annex demands postcode ("postal descriptor") and geometry as key attributes, an HVD-compliant national address file should in principle be a full address-point dataset; whether each country's file actually contains postcodes has to be checked country by country (see OpenAddresses section for cases where no postcode is mapped).

### Gaps
- No Commission report, dashboard or study was found that lists, per Member State, whether the *Addresses* HVD is published and compliant (licence, API, bulk). The Article 5 Member State reports (due Feb 2025) were not found in published form.
- No infringement procedure concerning HVD (non-)publication was found; the searches only surfaced older Open Data Directive transposition cases.
- The current status of the Digital Omnibus (trilogue, adoption) on 11 Nov 2026 was not confirmed from an official source (EUR-Lex/Legislative Observatory not checked directly).
- The exact wording of Article 14(3)-(5) of Directive (EU) 2019/1024 was not re-read; the exemption description relies on the Implementing Regulation's recitals.
- The data.europa.eu "best practices" HVD report (7 Member States interviewed) and the Sept 2024 metadata findability study were seen only as search summaries — [best practices report](https://data.europa.eu/en/publications/reports/high-value-datasets-best-practices-europe), [findability study](https://data.europa.eu/en/publications/reports/high-value-datasets-cross-country-findability-and-comparability-metadata).

## 2. INSPIRE Addresses (AD) theme: finding and downloading national datasets

### Takeaway
INSPIRE defines a common Addresses model and obliges countries to run download services, but it neither mandates an open licence nor a postcode on every address, and the default GML encoding is awkward to use. On 11 Nov 2026 the central INSPIRE Geoportal could not be used over a valid HTTPS connection (its TLS certificate expired on 30 Oct 2026), so a per-country count of downloadable AD datasets could not be produced.

### Cited Findings

**Legal and model basics**
- Annex I definition of the theme: "Location of properties based on address identifiers, usually by road name, house number, postal code" — [EUR-Lex, Directive 2007/2/EC, Annex I](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32007L0002)
- Member States must operate discovery, view and download services (Art. 11); public access may be limited on grounds such as international relations, public security or national defence (Art. 13); only discovery and view are guaranteed free of charge (Art. 14) — [EUR-Lex, Directive 2007/2/EC](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32007L0002)
- Current data specification: document D2.8.I.5_v3.2.0, published 2024-07-31 (body text still labels itself version 3.1rc1) — [INSPIRE Data Specification on Addresses - Technical Guidelines](https://inspire-mif.github.io/technical-guidelines/data/ad/dataspecification_ad.html)
- Address object: `inspireId` (1), `position` (1..*) and `locator` (1..*) and `component` (1..*) are mandatory; `alternativeIdentifier`, `status`, `validFrom`, `validTo`, lifespan dates and the links to `parcel`, `building` and `parentAddress` are all «voidable» — [INSPIRE AD Technical Guidelines, feature catalogue 5.3.2.1.1](https://inspire-mif.github.io/technical-guidelines/data/ad/dataspecification_ad.html)
- Street name, postcode, municipality etc. are not attributes of the address but separate "address component" objects (AdminUnitName, AddressAreaName, ThoroughfareName, PostalDescriptor) that the address references — [INSPIRE AD Technical Guidelines](https://inspire-mif.github.io/technical-guidelines/data/ad/dataspecification_ad.html)
- The only component the schema explicitly requires is the country: "An address shall have an admin unit address component spatial object whose level is 1 (Country)". A PostalDescriptor is not mandatory; if one exists it needs a post code or a post name ("If no post name exists, a post code is required") — [INSPIRE AD Technical Guidelines, constraints AddressCountry / PostNameEmpty / PostCodeEmpty](https://inspire-mif.github.io/technical-guidelines/data/ad/dataspecification_ad.html)
- GML (ISO 19136) is the default encoding; the schema uses only point (0-dimensional) geometries — [INSPIRE AD Technical Guidelines](https://inspire-mif.github.io/technical-guidelines/data/ad/dataspecification_ad.html)

**INSPIRE Geoportal access (state on 11 Nov 2026)**
- The TLS certificate of inspire-geoportal.ec.europa.eu was valid from 14 Apr 2026 to 30 Oct 2026 13:46:18 GMT and had not been renewed on 11 Nov 2026 00:20 UTC; standard clients refuse the connection ("certificate has expired"). Verified with `openssl s_client`; the catalogue could therefore not be queried for these notes — [INSPIRE Geoportal](https://inspire-geoportal.ec.europa.eu/srv/eng/catalog.search#/home)
- Geoportal records are addressed as `https://inspire-geoportal.ec.europa.eu/srv/api/records/{id}`, and a per-country, per-theme view exists under `catalog.search#/datasetdetails?country=xx&view=themeOverview...` (URL pattern as used in an OpenAddresses source definition) — [OpenAddresses source pt/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/pt/countrywide.json)

**National AD download services that could be confirmed indirectly**
- Croatia: the State Geodetic Administration serves the whole theme as one ATOM file, `https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_(AD).zip`, with access constraint "no limitations to public access" — [OpenAddresses source hr/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/hr/countrywide.json)
- Portugal: Statistics Portugal (INE) runs an ATOM download service for AD, recorded as CC BY 4.0 — [INE INSPIRE AD ATOM service](https://inspire.ine.pt/AD/atom/downloadservice_en.html); [OpenAddresses source pt/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/pt/countrywide.json)
- Czechia: ČÚZK offers an INSPIRE ATOM download service (GML 3.2.1) and a separate WFS for the AD theme (search summary only) — [ČÚZK ATOM record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_ATOM-MD_AD?dlang=eng); [ČÚZK WFS record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_WFS-MD_AD?dlang=eng)
- Luxembourg: "INSPIRE - Annex I Theme Addresses - Addresses" as GML/zip on the national open data portal (search summary only) — [data.public.lu](https://data.public.lu/en/datasets/inspire-annex-i-theme-addresses-addresses/)
- Lithuania: national Annex I Addresses dataset as zip with WMS and ATOM, based on Centre of Registers data published Nov 2024 (search summary only) — [INSPIRE Geoportal record](https://inspire-geoportal.ec.europa.eu/srv/api/records/876e6fc9-827d-40e1-a479-f5365b3d9ea2)
- Spain: DG Cadastre publishes a national AD dataset covering all regions except the Basque Country and Navarre; Navarre, Gipuzkoa and Bizkaia publish their own (search summary only, plus data.europa.eu listing) — [INSPIRE Geoportal record ES_SDGC_AD](https://inspire-geoportal.ec.europa.eu/srv/api/records/ES_SDGC_AD); [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=60&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- Austria and Slovakia publish datasets literally named "Address register INSPIRE" / "INSPIRE - Addresses" (queried 2026-11-11) — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=60&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- Sweden: Lantmäteriet lists a product "Address download, INSPIRE" (existence only; price/licence not checked) — [Lantmäteriet](https://lantmateriet.se/en/geodata/geodata-products/product-list/address-download-inspire)
- Rough proxy for which countries expose AD metadata: a data.europa.eu search for "INSPIRE addresses" restricted to keyword "addresses" returns 216 records - DE 56, ES 48, CZ 23, FI 12, PL 7, EE 6, LT 4, SE 4, LU 3, NL 2, FR 1, IT 1, LV 1, SI 1 (plus GB, NO, CH); distribution formats are dominated by WMS (45) over WFS (21), GML (14), ATOM (8) and GeoPackage (6) (queried 2026-11-11) — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?q=INSPIRE%20addresses&filter=dataset&limit=0&facets=%7B%22keywords%22%3A%5B%22addresses%22%5D%7D)

**Practical caveats**
- GDAL's plain GML driver has to resolve `xlink` references and the application-schema-driven GMLAS driver (GDAL 2.2+) is the route recommended for INSPIRE-style GML (search summary only) — [GDAL GML driver documentation](https://gdal.org/en/stable/drivers/vector/gml.html)
- A worked INSPIRE GML conversion with `ogr2ogr -f GPKG output.gpkg GMLAS:input.gml` is documented in a QGIS ticket (cadastral parcels, same pattern) (search summary only) — [QGIS feature request 20066](https://issues.qgis.org/issues/20066)

### Inferences
- Because components are separate referenced objects, an INSPIRE AD GML file has to be joined (address -> thoroughfare, postal descriptor, admin unit) before it yields flat "street, number, postcode, city" rows; this, not licensing, is the main practical barrier to using INSPIRE AD downloads directly.
- A fully INSPIRE-conformant national dataset can legally omit postcodes (PostalDescriptor is optional) and can void building/parcel links, so "INSPIRE AD available" does not guarantee the attributes the HVD Regulation lists.
- Where both exist, the national register's native bulk file (CSV/GeoPackage) is usually the easier source and the INSPIRE service mainly useful as a harmonised fallback; OpenAddresses uses the INSPIRE AD download as its source only for Croatia and Portugal.
- WMS-only publication (the most common format in the proxy search) satisfies INSPIRE "view" but gives no usable address data.

### Gaps
- A per-country list of EU Member States with a working, downloadable INSPIRE AD dataset (and its licence) could not be compiled: the INSPIRE Geoportal was unreachable over valid TLS on 11 Nov 2026 and no published overview was found.
- Whether the Geoportal currently offers a dedicated "High Value Datasets" or "priority datasets" view could not be checked for the same reason.
- No source was found documenting specific countries whose INSPIRE AD files lack postcodes or restrict access; the "missing postcode" caveat is established only at the level of the data model.
- OGC API Features availability for AD per country was not researched.

## 3. OpenAddresses (openaddresses.io)

### Takeaway
OpenAddresses has address sources for 24 of the 27 Member States (none for HU, IE, MT), with effectively national coverage for about 20; RO (Bucharest only), SE (18 municipalities), CY (no house numbers, ~4 % coverage) and DE (15 of 16 Länder, no Bavaria) are partial. Data stays under each source's own licence (mostly CC BY 4.0, CC0, Licence Ouverte, DL-DE), downloads are free but now require a logged-in account, and paid tiers (from USD 5) only add formats and S3 access.

### Cited Findings

**Project, licence, access**
- OpenAddresses describes itself as "the free and open global address collection"; "All data is openly licensed. Most sources only require attribution" — [openaddresses.io](https://openaddresses.io/)
- Repository code is BSD-3-Clause, the source definitions in `sources/` are CC0, and the data is "not relicensed from the original sources" (each source JSON summarises its licence); processing is a weekly batch run with output on batch.openaddresses.io; funding via Open Collective — [openaddresses/openaddresses README](https://github.com/openaddresses/openaddresses)
- The batch service lists 5,329 source-layer rows from 3,231 distinct sources worldwide: 3,148 address layers, 1,388 parcels, 581 buildings, 212 centerlines (queried 2026-11-11) — [batch.openaddresses.io/api/data](https://batch.openaddresses.io/api/data)
- Downloads require authentication: an anonymous request for a job output (`/api/job/946822/output/source.geojson.gz`, Luxembourg) and for a collection (`/api/collections/1/data`) both return HTTP 403 "Authentication Required" (queried 2026-11-11) — [batch.openaddresses.io](https://batch.openaddresses.io/api/job/946822/output/source.geojson.gz)
- The site's own explanation: "Only logged in users can perform downloads. One of our largest costs is S3 egress, authenticated downloads allow us to prevent abuse and keep the project running and the data free! Financial backers of the project can also export in CSV & Shapefile, and sponsors receive access to our validated data as well as direct AWS S3 access." (text in the site's JavaScript bundle, read 2026-11-11) — [batch.openaddresses.io](https://batch.openaddresses.io/)
- Account levels are "basic", "Backer" (>= $5, adds "300 Custom Format Exports per Month") and "Sponsor" (>= $100, adds "Direct AWS S3 Access" and "Validated Data"); basic accounts get "GeoJSON Format" and "CDN Data Access"; contributions are monthly and handled through OpenCollective (profile page bundle, read 2026-11-11) — [batch.openaddresses.io](https://batch.openaddresses.io/); [OpenCollective - OpenAddresses](https://opencollective.com/openaddresses/contribute)
- Pre-built collections exist only for: Global (76.8 GB raw / 19.4 GB processed, built 2026-11-09), four US regions and Canada. There is no Europe or per-EU-country collection, so EU data is fetched per source or from the global file (queried 2026-11-11) — [batch.openaddresses.io/api/collections](https://batch.openaddresses.io/api/collections)

**Per-EU-country coverage** (source definitions from the repository `sources/` tree, downloaded 2026-11-11; "last run" = date of the last successful batch job from [batch.openaddresses.io/api/data](https://batch.openaddresses.io/api/data); "postcode" = whether the source maps a postcode field)

| MS | Address coverage in OpenAddresses | Upstream source and licence as recorded | Postcode | Last run / data vintage | Source files |
|---|---|---|---|---|---|
| AT | Countrywide (+ Vienna, Tirol, 3 older zone files) | Österreichisches Adressregister (BEV), CC BY 4.0 | yes | run 2026-10-30; register record date 01.04.2026 (uploaded snapshot 2026-09-30) | [sources/at](https://github.com/openaddresses/openaddresses/tree/master/sources/at) |
| BE | Countrywide via 3 regions (Brussels, Flanders, Wallonia; per-language files) | BeSt Address via BOSA (`opendata.bosa.be/download/best/`), CC BY 4.0 | yes | run 2026-10-30; live URL | [sources/be](https://github.com/openaddresses/openaddresses/tree/master/sources/be) |
| BG | Countrywide (+ Sofia) | Cadastre open data (kais.cadastre.bg); licence field empty; Sofia CC BY 4.0 | no | run 2026-10-30; uploaded snapshot 2025-01-07 | [sources/bg](https://github.com/openaddresses/openaddresses/tree/master/sources/bg) |
| HR | Countrywide | DGU INSPIRE Addresses ATOM; "no limitations to public access" | yes | run 2026-10-30; live URL | [sources/hr](https://github.com/openaddresses/openaddresses/tree/master/sources/hr) |
| CY | Nominally countrywide, but unusable as address points | Department of Lands and Surveys, CC BY 4.0. Source note: "Current source data contains no house numbers... only street name and point geometry are populated. Coverage is also partial, about 4% of Cyprus per the publisher." | no | run 2026-10-30; snapshot 2026-09-29 | [sources/cy](https://github.com/openaddresses/openaddresses/tree/master/sources/cy) |
| CZ | Countrywide | ČÚZK (RÚIAN), CC BY 4.0 | yes | run 2026-10-30; cached upload, source page cited is the 2024-08-31 export | [sources/cz](https://github.com/openaddresses/openaddresses/tree/master/sources/cz) |
| DK | Countrywide | Danmarks Adresseregister (DAR) via Datafordeler GraphQL, CC BY 4.0 | yes | run 2026-10-16; snapshot 2026-03-27 | [sources/dk](https://github.com/openaddresses/openaddresses/tree/master/sources/dk) |
| EE | Countrywide | Land and Spatial Development Board ADS extract (via a mirror); national open-data licence: free, commercial use allowed, attribution required | no | run 2026-10-23; continuously mirrored | [sources/ee](https://github.com/openaddresses/openaddresses/tree/master/sources/ee) |
| FI | Countrywide (2 active files, fi/sv; 38 regional files are marked skipped) | Syke, CC BY 4.0 | yes | run 2026-10-30; snapshot 2026-09-30 | [sources/fi](https://github.com/openaddresses/openaddresses/tree/master/sources/fi) |
| FR | Countrywide: 104 files (101 départements + Saint-Barthélemy, Saint-Martin, Saint-Pierre-et-Miquelon) | Base Adresse Nationale (`adresse.data.gouv.fr/data/ban/adresses/latest`), Licence Ouverte Etalab 2.0 | yes | runs 2026-10-16 to 2026-11-10; live URL | [sources/fr](https://github.com/openaddresses/openaddresses/tree/master/sources/fr) |
| DE | 15 of 16 Länder statewide (BB, BE, BW, HB, HE, HH, MV, NI, NW, RP, SH, SL, SN, ST, TH) plus some cities; **Bavaria has building footprints only, no address layer** | DL-DE BY 2.0 (BB, BW, HH, RP, SL, SN, ST, TH); DL-DE Zero 2.0 (Berlin, HE, NW); CC BY 4.0 (HB, MV, NI, SH) | yes for BB, BE, HB, HH, RP, SH, SL, SN, TH; no for BW, HE, MV, NI, NW, ST | runs 2026-10-16 to 2026-10-30; mix of live URLs and snapshots from 2026-08/09 | [sources/de](https://github.com/openaddresses/openaddresses/tree/master/sources/de) |
| GR | Countrywide (+ Kalamaria; parcels per region) | Hellenic Cadastre "declared streets" points joined to Kallikratis municipality boundaries, CC BY 4.0 | no | run 2026-10-30; snapshot 2026-09-29 | [sources/gr](https://github.com/openaddresses/openaddresses/tree/master/sources/gr) |
| HU | none | - | - | - | [sources/](https://github.com/openaddresses/openaddresses/tree/master/sources) |
| IE | none | - | - | - | [sources/](https://github.com/openaddresses/openaddresses/tree/master/sources) |
| IT | Countrywide (+ ~38 regional/municipal files) | ANNCSU (Istat / Agenzia delle Entrate), CC BY 4.0 | no (countrywide file) | run 2026-08-14; file dated 2026-07-03 | [sources/it](https://github.com/openaddresses/openaddresses/tree/master/sources/it) |
| LV | Countrywide (+ Riga) | Valsts zemes dienests, CC BY 4.0 | yes | run 2026-10-30; live URL | [sources/lv](https://github.com/openaddresses/openaddresses/tree/master/sources/lv) |
| LT | Countrywide (+ Vilnius) | Registrų centras, CC BY 4.0 | yes | run 2026-10-30; live URL | [sources/lt](https://github.com/openaddresses/openaddresses/tree/master/sources/lt) |
| LU | Countrywide | data.public.lu, CC0 | yes | run 2026-10-30; live URL | [sources/lu](https://github.com/openaddresses/openaddresses/tree/master/sources/lu) |
| MT | none | - | - | - | [sources/](https://github.com/openaddresses/openaddresses/tree/master/sources) |
| NL | Countrywide | BAG (Kadaster), CC0 1.0 | yes | run 2026-10-30; snapshot 2026-06-03 | [sources/nl](https://github.com/openaddresses/openaddresses/tree/master/sources/nl) |
| PL | Countrywide via 16 voivodeship files | PRG address points (`opendata.geoportal.gov.pl`); "Polish Law on Geodesy and Cartography of 17 May 1989", no attribution required | yes | run 2026-10-30; live URL | [sources/pl](https://github.com/openaddresses/openaddresses/tree/master/sources/pl) |
| PT | Countrywide | INE INSPIRE AD service, CC BY 4.0 | yes | run 2026-10-30; snapshot 2026-02-23 | [sources/pt](https://github.com/openaddresses/openaddresses/tree/master/sources/pt) |
| RO | Bucharest only (2 map-service layers) | Esri Romania map service, no licence recorded | one of two layers | one layer last updated 2020-08-21 (no output size recorded), the other has no row in the batch API | [sources/ro](https://github.com/openaddresses/openaddresses/tree/master/sources/ro) |
| SK | Countrywide | Ministry of Interior register of addresses (data.slovensko.sk), CC0 1.0 | yes | run 2026-10-30; live URL | [sources/sk](https://github.com/openaddresses/openaddresses/tree/master/sources/sk) |
| SI | Countrywide | GURS Register of addresses, CC BY 4.0 | yes | **last successful address run 2024-06-14** | [sources/si](https://github.com/openaddresses/openaddresses/tree/master/sources/si) |
| ES | Countrywide (+ Navarre; 4 old Catastro zone caches last run 2021) | CNIG/SCNE provincial packages, CC BY 4.0 (IGN licence) | yes | run 2026-09-18; snapshot 2026-06-03 | [sources/es](https://github.com/openaddresses/openaddresses/tree/master/sources/es) |
| SE | 18 municipalities only (e.g. Stockholm, Göteborg, Malmö, Uppsala); no countrywide source | mixed: CC0, CC BY 4.0, several with no licence recorded | mixed | most 2026-10-30; four last succeeded 2020-08-21 | [sources/se](https://github.com/openaddresses/openaddresses/tree/master/sources/se) |

### Inferences
- Roughly 20 Member States have a usable national address-point set in OpenAddresses (AT, BE, BG, HR, CZ, DK, EE, FI, FR, GR, IT, LV, LT, LU, NL, PL, PT, SK, SI, ES) plus DE without Bavaria; coverage is absent or token for HU, IE, MT, RO, SE and CY.
- "Last run" overstates freshness for many countries: where the data URL is a manually uploaded cache file (AT, BG, CY, CZ, DK, FI, GR, IT, NL, PT, ES and several German Länder) the weekly run simply re-processes that snapshot; only live-URL sources (BE, HR, EE, FR, LV, LT, LU, PL, SK and some Länder) track the register weekly.
- For EU use the paid tiers are unnecessary: a free account gives per-source GeoJSON; the only real cost of staying free is that there is no single EU download - one must fetch about 200 address files or the 19 GB global collection.
- The licence mix is permissive (attribution at most; no share-alike source was seen among the EU national sources), but BG's national source has no recorded licence and should be treated as unverified for reuse.

### Gaps
- Record counts per country are not exposed by the batch API fields used here (only file sizes), so OpenAddresses address counts per EU country were not obtained.
- Whether account registration itself is still free and open to anyone was inferred from the site text ("keep ... the data free") and the "basic" level; the registration flow was not exercised.
- The vintage of the Czech cached file is inferred from the linked 2024-08-31 export name, not confirmed.

## 4. OpenStreetMap as an address source

### Takeaway
OSM is free to bulk-download for every Member State, but it is ODbL (attribution plus share-alike on derived databases) and its house-number coverage is extremely uneven: near-register completeness where official data was imported (NL, PL, AT, CZ, LT, LU, SK) versus roughly 10-20 % of the official address count in PT, ES, HR, IT and EE. The public Nominatim and Overpass services are rate-limited and explicitly not for bulk address extraction.

### Cited Findings

**Licence**
- OSM extracts are "licensed under ODbL 1.0", created by OpenStreetMap contributors — [Geofabrik download server, Europe](https://download.geofabrik.de/europe.html)
- OSMF geocoding guideline: "Individual Geocoding Results are insubstantial database extracts" and can be stored and combined with other data without share-alike, but "systematically reverse engineering the whole or a substantial part of the OSM database through Geocoding" creates a Derivative Database (share-alike applies); geocoders using OSM must attribute OpenStreetMap as per ODbL section 4.3 — [OSMF Geocoding Guideline](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Geocoding_-_Guideline)
- Under the same guideline a collection of results is not a substantial extract only if it is not "a systematic attempt to aggregate all or substantially all" features of a type over a city-sized or larger area — [OSMF Geocoding Guideline](https://osmfoundation.org/wiki/Licence/Community_Guidelines/Geocoding_-_Guideline)

**Completeness: objects tagged `addr:housenumber` per Member State** (Geofabrik taginfo, data as of 2026-11-09, queried 2026-11-11; per-country page pattern `https://taginfo.geofabrik.de/europe:{country}/keys/addr:housenumber`)

| MS | OSM objects with addr:housenumber | of which nodes | Source |
|---|---|---|---|
| AT | 2,513,790 | 404,355 | [taginfo AT](https://taginfo.geofabrik.de/europe:austria/keys/addr:housenumber) |
| BE | 4,159,902 | 182,662 | [taginfo BE](https://taginfo.geofabrik.de/europe:belgium/keys/addr:housenumber) |
| BG | 182,314 | 16,032 | [taginfo BG](https://taginfo.geofabrik.de/europe:bulgaria/keys/addr:housenumber) |
| HR | 274,757 | 106,447 | [taginfo HR](https://taginfo.geofabrik.de/europe:croatia/keys/addr:housenumber) |
| CY | 30,818 | 7,257 | [taginfo CY](https://taginfo.geofabrik.de/europe:cyprus/keys/addr:housenumber) |
| CZ | 3,095,104 | 2,958,174 | [taginfo CZ](https://taginfo.geofabrik.de/europe:czech-republic/keys/addr:housenumber) |
| DK | 2,616,365 | 2,616,202 | [taginfo DK](https://taginfo.geofabrik.de/europe:denmark/keys/addr:housenumber) |
| EE | 437,793 | 12,018 | [taginfo EE](https://taginfo.geofabrik.de/europe:estonia/keys/addr:housenumber) |
| FI | 1,111,284 | 153,310 | [taginfo FI](https://taginfo.geofabrik.de/europe:finland/keys/addr:housenumber) |
| FR | 12,463,346 | 11,215,007 | [taginfo FR](https://taginfo.geofabrik.de/europe:france/keys/addr:housenumber) |
| DE | 20,842,272 | 4,062,328 | [taginfo DE](https://taginfo.geofabrik.de/europe:germany/keys/addr:housenumber) |
| GR | 172,631 | 89,258 | [taginfo GR](https://taginfo.geofabrik.de/europe:greece/keys/addr:housenumber) |
| HU | 780,563 | 202,376 | [taginfo HU](https://taginfo.geofabrik.de/europe:hungary/keys/addr:housenumber) |
| IE (extract includes Northern Ireland) | 491,670 | 23,024 | [taginfo IE+NI](https://taginfo.geofabrik.de/europe:ireland-and-northern-ireland/keys/addr:housenumber) |
| IT | 4,670,917 | 4,549,674 | [taginfo IT](https://taginfo.geofabrik.de/europe:italy/keys/addr:housenumber) |
| LV | 361,889 | 142,269 | [taginfo LV](https://taginfo.geofabrik.de/europe:latvia/keys/addr:housenumber) |
| LT | 1,074,693 | 301,193 | [taginfo LT](https://taginfo.geofabrik.de/europe:lithuania/keys/addr:housenumber) |
| LU | 171,824 | 55,006 | [taginfo LU](https://taginfo.geofabrik.de/europe:luxembourg/keys/addr:housenumber) |
| MT | 4,636 | 2,452 | [taginfo MT](https://taginfo.geofabrik.de/europe:malta/keys/addr:housenumber) |
| NL | 9,955,334 | 9,871,083 | [taginfo NL](https://taginfo.geofabrik.de/europe:netherlands/keys/addr:housenumber) |
| PL | 8,606,089 | 3,204,885 | [taginfo PL](https://taginfo.geofabrik.de/europe:poland/keys/addr:housenumber) |
| PT | 605,316 | 479,896 | [taginfo PT](https://taginfo.geofabrik.de/europe:portugal/keys/addr:housenumber) |
| RO | 1,096,579 | 904,374 | [taginfo RO](https://taginfo.geofabrik.de/europe:romania/keys/addr:housenumber) |
| SK | 1,626,830 | 65,797 | [taginfo SK](https://taginfo.geofabrik.de/europe:slovakia/keys/addr:housenumber) |
| SI | 446,637 | 67,911 | [taginfo SI](https://taginfo.geofabrik.de/europe:slovenia/keys/addr:housenumber) |
| ES | 2,262,107 | 1,600,312 | [taginfo ES](https://taginfo.geofabrik.de/europe:spain/keys/addr:housenumber) |
| SE | 1,008,635 | 375,021 | [taginfo SE](https://taginfo.geofabrik.de/europe:sweden/keys/addr:housenumber) |

- Belgium, municipality-level comparison (OSM extract of 24 Apr 2025): 3,900,105 OSM addresses against 4,454,017 official BeSt address positions (7,004,321 official records before merging points within 1 m to remove box numbers) = 87.6 % count completeness; address quality was not assessed — [juminet's OSM diary, 28 Apr 2025](https://www.openstreetmap.org/user/juminet/diary/406654)
- Countries where official address data is imported or synced into OSM: Netherlands (BAG import), Denmark (government address data, imported since 2009), Czechia (RÚIAN import, approx. monthly), Latvia (bot-managed daily updates from the State Address Register, open since Jan 2022), France (BANO composite, ODbL) — [OSM wiki, Addresses](https://wiki.openstreetmap.org/wiki/Addresses)
- A 2023 peer-reviewed paper proposes an ISO 19157-based algorithm to evaluate address datasets, comparing open/SDI and VGI (OSM) addresses with commercial geocoders in urban areas; a search summary attributes to it house-number null rates of 27.13 % (OpenAddresses) vs 30.15 % (OSM) for European city samples, but the full text could not be opened (HTTP 403), so those figures are unverified — [Sierra-Requena et al., ISPRS Int. J. Geo-Inf. 12(10):407, abstract via Semantic Scholar](https://api.semanticscholar.org/graph/v1/paper/DOI:10.3390/ijgi12100407?fields=title,abstract,year,authors,venue); [publisher page](https://www.mdpi.com/2220-9964/12/10/407)

**Getting address extracts**
- Geofabrik: `.osm.pbf` extracts for all 27 Member States (Ireland combined with Northern Ireland), no account needed, daily change files; `.gpkg.zip` for most countries but "not available" for CZ, FR, DE, IT, NL, PL, ES; public files omit user names/IDs and changeset IDs, full-metadata files sit on an internal server for OSM contributors — [Geofabrik download server, Europe](https://download.geofabrik.de/europe.html)
- Photon (komoot/GraphHopper) dumps: planet database for Photon 1.x is 63.1 GB (updated 2026-11-03), planet JSON dump 27.1 GB (updated 2026-11-09); older 0.5-0.7 dumps were last updated Jan/Feb 2026 (queried 2026-11-11) — [Photon download service](https://download1.graphhopper.com/public/)
- Photon country extracts under `/public/europe/`: a ready-made "DB dump" is flagged available for Austria, Denmark, France-Monaco, Germany, Luxemburg, Netherlands, Slovakia and Spain and not available for the other EU entries (Baltics, Belgium, Bulgaria, Croatia, Cyprus, Czech Republic, Finland, Greece, Hungary, Ireland, Italy, Malta, Poland, Portugal, Romania, Slovenia, Sweden) (queried 2026-11-11) — [Photon download service, Europe](https://download1.graphhopper.com/public/europe/)
- The pre-built Photon database supports only English, German, French and local language and has "no support for structured search or full geometries"; the JSON dump is needed for those — [Photon download service](https://download1.graphhopper.com/public/)
- OSMNames (place names plus a house-number file, GeoNames-like TSV): latest release v2.2.0 dated 2022-12-09, repository last pushed 2024-08-07, code GPL-2.0 (queried 2026-11-11) — [OSMNames GitHub releases](https://github.com/OSMNames/OSMNames/releases)
- Overpass API (main instance overpass-api.de): no key; safe-use guideline "less than 10,000 queries per day" and "download less than 1 GB data per day"; for country-sized regions "it's better to use planet.osm mirrors"; commercial use should self-host or pay — [OSM wiki, Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API)

**Nominatim public API limits**
- "an absolute maximum of 1 request per second"; identifying User-Agent or Referer required; results must be cached; autocomplete forbidden; systematic queries (grid reverse-geocoding, enumerating postcodes or towns) forbidden; bulk geocoding discouraged (single thread, one machine; scripts running longer than a day or at regular intervals limited to 4 requests per minute); for complete datasets use the OSM planet or an extract, for large needs install your own instance — [OSMF Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/)

### Inferences
- Ratio of OSM `addr:housenumber` objects (table above) to the address counts Overture publishes from official registers (section 5; [Overture addresses guide](https://docs.overturemaps.org/guides/addresses/)): NL 99.7 %, PL 99.7 %, AT 99.6 %, CZ 102 %, LU 96 %, SK 95 %, LT 95 %, SI 77 %, DK 67 %, LV 66 %, BE 59 %, FR 48 %, FI 30 %, EE 19 %, IT 17 %, HR 16 %, ES 14 %, PT 11 % (DE not comparable: Overture's 19.3 M excludes Bavaria while OSM has 20.8 M). These are indicative only: OSM counts tagged objects, registers may count units, entrances or (EE) all address objects, and Belgium's 59 % becomes about 88-93 % once box numbers are merged as in the Belgian study.
- For BG, CY, GR, HU, IE, MT, RO and SE there is no Overture/official denominator in these notes; the small absolute OSM counts for BG (182k), GR (173k), CY (31k) and MT (4.6k) indicate very low coverage.
- ODbL makes OSM a poor base for a proprietary or CC BY-licensed consolidated address database (a derived database must be shared alike), whereas official registers under CC BY 4.0/CC0 carry no such condition; in the well-covered countries OSM addresses are largely a copy of that official data anyway.
- Nominatim and Overpass public endpoints cannot lawfully or practically be used to harvest national address sets; the only supported route is a Geofabrik/planet extract filtered locally (e.g. for `addr:*` tags) or a Photon/Nominatim instance built from it.

### Gaps
- No multi-country quantitative study comparing OSM address completeness with official registers across the EU was found; Belgium is the only country with a dated, methodical comparison located.
- What the "not available" flag on Photon country pages means in practice (JSON dump only, or no extract at all) was not verified per country.
- Nominatim does not publish address dumps as far as could be determined; no "Nominatim data dump" product was found.
- The German regio-osm house-number evaluation and French BANO statistics were not checked.

## 5. Overture Maps Foundation - addresses theme

### Takeaway
Overture's addresses theme (still "Alpha") is the easiest single free download of official EU address points: 19 of 27 Member States, monthly GeoParquet releases on public cloud storage with no account, each country under its original open licence. It is essentially a normalised redistribution of the sources OpenAddresses carries, and it omits BG, CY, GR, HU, IE, MT, RO and SE.

### Cited Findings
- The theme holds "over 475 million" address points for 41 countries, is "currently in Alpha", is released monthly as GeoParquet, and is documented for release 2026-10-21.0 (page updated 21 Oct 2026) — [Overture addresses guide](https://docs.overturemaps.org/guides/addresses/)
- Most address points are distributed via two community aggregators, OpenAddresses and AddressForAll, plus public agencies; several large countries (US, Germany, Taiwan) have only partial coverage — [Overture addresses guide](https://docs.overturemaps.org/guides/addresses/)
- EU address counts in release 2026-10-21.0: AT 2,523,030; BE 7,001,489; CZ 3,021,471; DE 19,299,493; DK 3,933,282; EE 2,277,177; ES 15,627,615; FI 3,670,323; FR 26,052,116; HR 1,682,868; IT 26,841,754; LT 1,130,062; LU 179,635; LV 550,686; NL 9,988,169; PL 8,628,514; PT 5,607,450; SI 580,213; SK 1,704,346 — [Overture addresses guide](https://docs.overturemaps.org/guides/addresses/)
- Schema fields include street number, street name, unit, address levels, postal code and country (query examples use `number`, `street`, `unit`, `postcode`, `country`) — [Overture addresses guide](https://docs.overturemaps.org/guides/addresses/)
- There is no single licence for the theme: "All carry permissive open licenses. Some have special terms or require attribution." — [Overture attribution and licensing](https://docs.overturemaps.org/attribution/)
- Per-EU-country sources and licences as listed by Overture: Austria - Austrian Address Register, CC BY 4.0; Belgium - ICAR (Wallonia), Adressenregister (Flanders), UrbIS (Brussels), CC BY 4.0; Croatia - Državna geodetska uprava, "Open License"; Czechia - ČÚZK, CC BY 4.0; Denmark - Danish Agency for Data Supply and Infrastructure, "Terms of use for free geographic data"; Estonia - Land Board, CC0; Finland - Syke, CC BY 4.0; France - Base Adresse Nationale, Licence Ouverte 2.0; Germany - BW, BB, HH, RP, SL, SN, ST, TH under DL-DE BY 2.0, Berlin, HE, NW under DL-DE Zero 2.0, HB, MV, NI, SH under CC BY 4.0; Italy - ANNCSU, CC BY 4.0; Latvia - VZD, CC BY 4.0; Lithuania - Centre of Registers, CC BY 4.0; Luxembourg - open data platform, CC0; Netherlands - BAG via PDOK/Kadaster, CC0 1.0; Poland - "No conditions to access and use"; Portugal - INE, no licence listed; Slovenia - GURS, CC BY 4.0; Slovakia - Ministry of Interior, CC0 1.0; Spain - scne.es, CC BY 4.0 — [Overture attribution and licensing](https://docs.overturemaps.org/attribution/)
- Latest release per the STAC catalogue is 2026-10-21.0 (previous: 2026-09-23.0 and 2026-09-23.1); address data path `s3://overturemaps-us-west-2/release/2026-10-21.0/theme=addresses/type=address/*.parquet` (queried 2026-11-11) — [Overture STAC catalogue](https://stac.overturemaps.org/catalog.json)
- Access: `pip install overturemaps` then `overturemaps download --bbox ... --type ...`, or DuckDB with `httpfs`/`spatial` against the S3 path; the browser Explorer needs "No installation, no account" — [Overture, Getting data](https://docs.overturemaps.org/getting-data/)

### Inferences
- EU coverage is 19 of 27: AT, BE, CZ, DE (15 Länder, no Bavaria), DK, EE, ES, FI, FR, HR, IT, LT, LU, LV, NL, PL, PT, SI, SK. Missing: BG, CY, GR, HU, IE, MT, RO, SE.
- The German Länder list in Overture's attribution matches OpenAddresses' statewide sources exactly (Bavaria absent in both), and the country/licence list matches OpenAddresses source by source, so Overture inherits OpenAddresses' vintage and gaps; it does not carry OpenAddresses' BG, GR and CY sources, which are the weakest ones (no licence recorded, no postcode, no house numbers respectively).
- Anonymous S3 access plus one schema makes Overture preferable to OpenAddresses for an EU-wide pull (no login, no per-source files), at the price of an "Alpha" schema and monthly rather than weekly refresh.
- Licence obligations are per country: attribution for CC BY 4.0, Licence Ouverte and DL-DE BY sources; none for CC0/DL-DE Zero/PL. Portugal has no licence listed by Overture although OpenAddresses records the same INE source as CC BY 4.0, so the Portuguese licence should be confirmed at the source.

### Gaps
- Whether anonymous (unsigned) S3/Azure access works without any cloud account was not tested directly; the documentation implies it.
- Retention policy for old releases and the Azure paths were not found on the pages read.
- The data vintage per country inside release 2026-10-21.0 is not stated by Overture.

## 6. EuroGeographics (Open Maps for Europe, Open Gazetteer, EuroRegionalMap, Open Cadastral Map)

### Takeaway
EuroGeographics offers no free pan-European address-point dataset. Its open products are small-scale topographic maps and a place-name gazetteer; the only address-related item, the prototype Open Cadastral Map, compiles INSPIRE open data and points users to national geoportals for download.

### Cited Findings
- Open Maps for Europe products: EuroRegionalMap (1:250 000 topographic), EuroGlobalMap (1:1 000 000), EuroDEM, Open Gazetteer, Pan-European Imagery, and a prototype Open Cadastral Map; all described as free-to-use open data "under a single licence" (licence not named on the page) — [EuroGeographics, Open Maps for Europe](https://eurogeographics.org/open-maps-for-europe/)
- Open Gazetteer is a service of authoritative multilingual geographical names from 36 national mapping, cadastral and land registration authorities - place names, not addresses — [EuroGeographics, Open Maps for Europe](https://eurogeographics.org/open-maps-for-europe/)
- The Open Cadastral Map lists four data types - administrative units, cadastral parcels/zones, buildings/building parts and addresses - drawn from INSPIRE open data; first iteration covered Poland, the Netherlands, the Czech Republic and Spain — [EuroGeographics, Open Maps for Europe](https://eurogeographics.org/open-maps-for-europe/)
- By July 2025 the Open Cadastral Map covered 15 national authorities after adding Belgium, Estonia, Ireland, Croatia and Switzerland; it "compiles and harmonises INSPIRE open data" and gives links for "direct download from national geoportals"; OME2 ran until the end of 2025, co-funded by the EU — [GeoConnexion, 29 July 2025](https://www.geoconnexion.com/news/ome2-adds-five-new-countries-to-final-release-of-open-cadastral-map)
- The final OME2 "high-value large-scale prototype" (17 Dec 2025) covers 10 countries (AT, BE, CZ, DK, FI, FR, LU, ES, CH, NL) at 1:10 000 with three themes - administrative boundaries, transport and hydrography; addresses are not among them — [GeoConnexion, 17 Dec 2025](https://www.geoconnexion.com/news/open-maps-for-europe-2-ome2-adds-five-new-countries-and-hydrography-theme-to-final-release-of-high-value-data-prototype)
- Some GISCO datasets derived from EuroGeographics data carry the note that commercial users should contact EuroGeographics for licence agreements (search summary only) — [Eurostat GISCO geodata](https://ec.europa.eu/eurostat/web/gisco/geodata)

### Inferences
- For address data EuroGeographics adds nothing beyond the national INSPIRE/open-data downloads it links to; it is a discovery aid at best, and only for the 15 participating authorities.
- With OME2 funding ended on 31 Dec 2025 and the address-bearing product still labelled a prototype, long-term maintenance of the Open Cadastral Map is uncertain.

### Gaps
- The name and terms of the "single open licence" could not be verified: the licence PDF URL returned 404 and mapsforeurope.org pages render only via JavaScript.
- Whether the Open Cadastral Map serves address features itself (e.g. via WFS) or only displays them, and the full list of 15 authorities, was not confirmed.
- No EuroGeographics "Open Addresses" pilot or pan-European address product was found; absence is based on the pages read, not on a statement by EuroGeographics.
- Service status of mapsforeurope.org in November 2026 (after project end) was not verified.

## 7. European Commission / Eurostat GISCO: Address API and postal code points

### Takeaway
Eurostat runs a free, key-less "GISCO Address API" over a pan-European database assembled from national authoritative sources for 26 Member States (all except Ireland), but it is a lookup service (max. 1,000 results per call, no bulk download, no stated licence) and some national snapshots date from 2021-2022. The only GISCO bulk product is a postcode *point* dataset under CC BY-SA 4.0.

### Cited Findings

**GISCO Address API**
- Self-description: "RESTful API which allows developers to carry out both geocoding and reverse geocoding using a pan-european address database. The data comes from authoritative data sources in the participating countries and are their responsibility." — [GISCO Address API swagger](https://gisco-services.ec.europa.eu/addressapi/swagger/)
- Endpoints: `/search`, `/reverse`, `/bbox`, `/most-populated-cell`, `/countries`, `/provinces`, `/cities`, `/roads`, `/housenumbers`, `/postcodes`, `/copyright`; no bulk-download endpoint is defined — [GISCO Address API swagger.yaml](https://gisco-services.ec.europa.eu/addressapi/swagger.yaml)
- Countries served (31): AT, BE, BG, CH, CY, CZ, DE, DK, EE, EL, ES, FI, FO, FR, HR, HU, IS, IT, LI, LT, LU, LV, MT, NL, NO, PL, PT, RO, SE, SI, SK - i.e. every Member State except Ireland (queried 2026-11-11) — [GISCO Address API /countries](https://gisco-services.ec.europa.eu/addressapi/countries)
- Per-country copyright strings name the national suppliers, some with a vintage: AT "© Österreichisches Adressregister, Stichtagsdaten vom 05.05.2022"; DE "© GeoBasis-DE / BKG (2021)"; HR "© State Geodetic Administration,2022"; BE National Geographic Institute; BG AGKK; CY Department of Lands and Surveys; CZ ČÚZK; DK Styrelsen for Dataforsyning og Effektivisering; EE Land Board; EL Hellenic Cadastre; ES Dirección General del Catastro; FI Digi- ja väestötietovirasto; FR Direction interministérielle du numérique; HU Lechner Tudásközpont; IT Geoportale nazionale; LT Registrų centras (and the road directorate); LU Administration du cadastre et de la topographie; LV Valsts zemes dienests; MT National Statistics Office; NL BAG; PL "Urzędy centralne"; PT Instituto Nacional de Estatística; RO ANCPI; SE Lantmäteriet; SI Surveying and Mapping Authority; SK NASES; IE and UK are listed with a null copyright (queried 2026-11-11) — [GISCO Address API /copyright](https://gisco-services.ec.europa.eu/addressapi/copyright)
- No API key or login is needed: unauthenticated calls returned data, e.g. a structured search for 5 Rue Alcide de Gasperi, Luxembourg returned house number, street, city, province, postcode 1615, NUTS codes, coordinates and an Open Location Code (queried 2026-11-11) — [GISCO Address API /search example](https://gisco-services.ec.europa.eu/addressapi/search?country=LU&city=Luxembourg&road=Rue%20Alcide%20de%20Gasperi&housenumber=5)
- Documented limits (from the R client): search returns at most 1,000 addresses; roads, house numbers and postcodes lists are capped at 1,000; reverse geocoding returns at most five results; autocomplete via `/search?suggest=` is not implemented in the client — [giscoR, GISCO Address API reference](https://ropengov.github.io/giscoR/reference/gisco_address_api.html)
- The documentation front-end is version 2.2.1 with build date 28/04/2026 (read from the docs bundle 2026-11-11) — [GISCO Address API docs](https://gisco-services.ec.europa.eu/addressapi/docs/)
- Oddity observed: `/postcodes?country=LU` returned an empty list although search results for Luxembourg contain postcodes (queried 2026-11-11) — [GISCO Address API /postcodes](https://gisco-services.ec.europa.eu/addressapi/postcodes?country=LU)

**GISCO postal codes (postcode-only)**
- A *point* dataset giving postcode locations with NUTS codes and degree-of-urbanisation class, for EU, EFTA and candidate countries; versions 2024 and 2020; formats GeoPackage, SHP, CSV in EPSG:3035/4326/3857 — [Eurostat GISCO, Postal codes](https://ec.europa.eu/eurostat/web/gisco/geodata/administrative-units/postal-codes)
- Licence CC-BY-SA-4.0 with required acknowledgement "© European Union - GISCO, 2024, postal code point dataset, Licence CC-BY-SA 4.0"; non-geographical postcodes (PO boxes, large organisations) are excluded and "not all postal codes may be included or correctly located" — [Eurostat GISCO, Postal codes](https://ec.europa.eu/eurostat/web/gisco/geodata/administrative-units/postal-codes)
- Main purpose is the postcode-to-NUTS correspondence tables under the TERCET regulation, published as flat files — [GISCO TERCET flat files](https://gisco-services.ec.europa.eu/tercet/flat-files)

### Inferences
- The `/copyright` list is the best available evidence that authoritative address data from 26 Member States has been delivered to the Commission, including countries with no open national download visible in OpenAddresses/Overture (HU, MT, RO, SE, BG, CY, EL). It does not show that those national datasets are openly downloadable.
- The API is suitable for free, low-volume geocoding or validation against official data across the EU but not as a data source: no bulk endpoint, 1,000-row caps, and enumerating it country-wide would amount to scraping a service with unstated terms.
- Data currency is uneven and partly old (AT snapshot of May 2022 versus the register's half-yearly releases), so the API can lag national registers by years.
- CC BY-SA 4.0 on the postcode points imposes share-alike on derived datasets, which is more restrictive than GeoNames' CC BY 4.0 for a comparable product.

### Gaps
- No licence or terms-of-use statement for the Address API or its underlying data was found on the API itself; the R client's metadata points to Eurostat's general copyright/reuse policy, which was not read (search summary only) — [giscoR COPYRIGHTS](https://stat.ethz.ch/CRAN/web/packages/giscoR/COPYRIGHTS)
- No rate limit is documented; none was probed.
- Why Ireland is absent, the reference dates for most countries, and total address counts are not published by the API.
- Sources of the GISCO postcode points ("various sources") were not identified; the methodological notes file was not opened.
- No downloadable pan-European GISCO address dataset was found.

## 8. Other free multi-country sources (postcode-only vs address-point)

### Takeaway
Beyond OpenAddresses, Overture and OSM there is no further free multi-country source of house-number-level address points; the remaining free resources are postcode-centroid files (GeoNames, GISCO, Geoapify, Who's On First), geocoder inputs derived from the same upstream data (Pelias, Photon, libpostal), or reference material (UPU, whose actual postcode database is a paid licence).

### Cited Findings

**Postcode-only**
- GeoNames postal code dump: CC BY 4.0 (credit/link to geonames.org suffices); tab-delimited fields country code, postal code, place name, three admin levels, latitude, longitude, accuracy (1 = estimated, 4 = geonameid, 6 = centroid of addresses or shape); coordinates for many countries are derived by matching place names, or averaged from neighbouring postcodes; about 120 countries — [GeoNames postal codes readme](https://download.geonames.org/export/zip/readme.txt)
- GeoNames per-country files exist for 26 Member States (AT, BE, BG, HR, CY, CZ, DK, EE, FI, FR, DE, HU, IE, IT, LV, LT, LU, MT, NL, PL, PT, RO, SK, SI, ES, SE); **no `GR.zip` (Greece) is in the directory**; files were regenerated 2026-11-10; `NL_full.csv.zip` (3.5 MB) carries full Dutch postcodes while `allCountries.zip` (19 MB) has only the first part for NL (queried 2026-11-11) — [GeoNames postal code directory](https://download.geonames.org/export/zip/)
- GeoNames limitations for EU states: Ireland and Malta contain "only the first letters of full postal codes" — [GeoNames postal codes readme](https://download.geonames.org/export/zip/readme.txt)
- GISCO postal code points: CC BY-SA 4.0, EU/EFTA/candidate countries, 2024 and 2020 versions (details in section 7) — [Eurostat GISCO, Postal codes](https://ec.europa.eu/eurostat/web/gisco/geodata/administrative-units/postal-codes)
- Geoapify offers free per-country postcode and locality downloads with licences varying by country (e.g. France ODbL, Germany derived from OSM under ODbL, Norway CC BY 4.0); localities are OSM-derived NDJSON (search summary only) — [Geoapify downloads](https://www.geoapify.com/downloads/); [Geoapify postal code downloads](https://geoapify.com/download-postal-codes)
- Who's On First: data under the Who's On First licence ("Crediting Who's On First is recommended and linking back to the License is required"), with some upstream sources requiring their own attribution; in the Pelias stack it supplies administrative places (countries, regions, counties, localities, neighbourhoods), not addresses — [Who's On First licences](https://whosonfirst.org/docs/licenses/); [Pelias data sources](https://github.com/pelias/documentation/blob/master/data-sources.md)
- UPU Universal POST*CODE DataBase: "A world postcode database containing the postcodes of 192 member countries", distributed under a licence package (contract, non-disclosure agreement, data use declaration, rates document) - i.e. not free; prices are not published on the page; update 2026.1 dated 02.03.2026 — [UPU Addressing Solutions](https://www.upu.int/en/postal-solutions/programmes-services/addressing-solutions)
- Free UPU material is limited to sample extracts by region, Postal Addressing System country sheets, Addressing Knowledge Centre documents and the S42 standard PDF; some countries additionally require a national licence for their data (latter point: search summary only) — [UPU Addressing Solutions](https://www.upu.int/en/postal-solutions/programmes-services/addressing-solutions); [UPU POST*CODE DataBase product sheet](https://www.upu.int/UPU/media/upu/documents/PostCode/UniversalPostcodesDatabaseProductSheetEnglish.pdf)

**Address-level, but derivative of sources already covered**
- Pelias (open-source geocoder) imports OpenAddresses ("address records only"; licence varies by source), OpenStreetMap (venues and addresses; ODbL), Who's On First (admin hierarchy) and GeoNames (places; CC BY) — [Pelias data sources](https://github.com/pelias/documentation/blob/master/data-sources.md)
- libpostal's parser training data is built from OpenStreetMap (addresses, places, streets), "most of the address data sets" of OpenAddresses, and Yahoo GeoPlanet postal codes; "over 1 billion addresses and address-like strings"; hosted on archive.org, "over 100GB unzipped"; per-file licences (ODbL for OSM files, "various licenses, mostly CC-BY" for OpenAddresses); examples are synthetically altered (abbreviations added, components dropped at random), so it is not a clean address dataset — [libpostal README](https://github.com/openvenues/libpostal)
- Photon dumps are OSM data pre-processed for the Photon geocoder (details in section 4) — [Photon download service](https://download1.graphhopper.com/public/)

**Not an address register**
- Wikidata has properties P6375 "street address", P669 "located on street" with qualifier P670 "house number", and P281 "postal code" (queried 2026-11-11) — [Wikidata API: P6375, P281, P669, P670](https://www.wikidata.org/w/api.php?action=wbgetentities&ids=P6375%7CP281%7CP669%7CP670&props=labels%7Cdescriptions&languages=en&format=json)
- "All structured data ... is released into the public domain under Creative Commons Zero" — [Wikidata:Licensing](https://www.wikidata.org/wiki/Wikidata:Licensing)

### Inferences
- Postcode-only, free, EU-wide: GeoNames (CC BY 4.0; 26 of 27 states, none for Greece; partial codes for IE and MT; estimated centroids) and GISCO (CC BY-SA 4.0). Neither is authoritative; neither gives street or house number.
- Full address points, free, multi-country: only OpenAddresses, Overture (same upstream), and OSM. Pelias, Photon and libpostal add no new address data.
- Wikidata's address properties describe notable items (buildings, organisations) and cannot serve as address coverage for a country.
- A complete, authoritative EU-wide postcode file with all delivery points remains a paid product (UPU, national posts); free alternatives are approximations.

### Gaps
- Who's On First postal-code coverage per EU country, its current licence text and download format were not verified (the licence page read did not name the licence type; a 2018 blog post about moving from CC BY to CDLA-Permissive was seen only as a search summary) — [Who's On First licence change post](https://whosonfirst.org/blog/2018/08/21/license-change/)
- Geoapify's download terms and country list were not read directly.
- UPU prices were not found. The date of the latest libpostal training set was not checked.
- National postal operators' free postcode files were not surveyed (out of scope; covered by country researchers if at all).

## 9. Maintained public comparison lists of open address data per country

### Takeaway
No maintained, authoritative per-country overview of open address data for the EU-27 was found. The most useful living "lists" are by-products: the OpenAddresses source tree and coverage API, Overture's attribution table, the GISCO Address API `/copyright` list, the data.europa.eu HVD "Addresses" filter and the OSM wiki's address page.

### Cited Findings
- OpenAddresses' `sources/` tree is organised by ISO country code and each JSON records data URL, licence, attribution and field mapping; a "coverage report" is linked from the home page — [openaddresses/openaddresses sources](https://github.com/openaddresses/openaddresses/tree/master/sources); [openaddresses.io](https://openaddresses.io/)
- The batch API exposes every source/layer with its last successful run and output size as machine-readable JSON (queried 2026-11-11) — [batch.openaddresses.io/api/data](https://batch.openaddresses.io/api/data)
- Overture publishes a per-country address count table and a per-country source/licence table, refreshed with each monthly release — [Overture addresses guide](https://docs.overturemaps.org/guides/addresses/); [Overture attribution and licensing](https://docs.overturemaps.org/attribution/)
- The GISCO Address API lists participating countries and the national data owner for each — [GISCO Address API /copyright](https://gisco-services.ec.europa.eu/addressapi/copyright)
- data.europa.eu can be filtered by HVD category "Addresses" (code c_c3de25e4), giving a live list of datasets Member States have themselves tagged (8 Member States on 2026-11-11) — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- The OSM wiki "Addresses" page links per-country address import/sync projects (DK, CZ, FR/BANO, LV, NL, BE and others) and QA tools (Nominatim Data Analyser, OSM Inspector address view) — [OSM wiki, Addresses](https://wiki.openstreetmap.org/wiki/Addresses)
- The OSM wiki "Potential Datasources" page (last edited 16 June 2026) carries out-of-date and cleanup notices and contains no EU address-data entries; country material is delegated to a "Local data" subpage and "Category:Data sources by country" — [OSM wiki, Potential Datasources](https://wiki.openstreetmap.org/wiki/Potential_Datasources)
- The annual Open Data Maturity report gives per-country HVD maturity only as aggregate self-reported scores, not per dataset — [ODM Report 2025](https://data.europa.eu/sites/default/files/2025-12/2025_odm_report_7.pdf)
- The INSPIRE AD data specification was developed drawing on the EURADIN (European Address Infrastructure) project (search summary only) — [INSPIRE AD Technical Guidelines](https://inspire-mif.github.io/technical-guidelines/data/ad/dataspecification_ad.html)

### Inferences
- Combining the four machine-readable lists gives a workable EU-27 matrix: Overture/OpenAddresses show where an open national file demonstrably exists (19-20 states), GISCO `/copyright` shows where authoritative data exists at all (26 states), and the gap between them (BG, CY, GR, HU, MT, RO, SE, plus IE which is in neither) identifies the countries where open availability must be checked against the national register directly.
- Because OpenAddresses' and Overture's lists are maintained by volunteers/aggregators, absence there does not prove that no open national dataset exists (it may simply not have been added), and presence does not prove HVD compliance (API, licence, currency).

### Gaps
- No JRC or Commission study comparing national address registers' openness was located; the searches returned only general INSPIRE documents (e.g. a JRC INSPIRE implementation summary) — [JRC109035](https://publications.jrc.ec.europa.eu/repository/bitstream/JRC109035/jrc109035_jrc109035_jrc_inspire_eu_summaryreport_online.pdf)
- The European Location Framework (ELF) project outputs and any UN-GGIM: Europe core-data recommendation on addresses were not researched.
- No "awesome list" or similar community-curated catalogue specific to European open address data was found (not searched exhaustively).
- The INSPIRE Geoportal's theme overview, which could serve as such a list for the AD theme, was unreachable on 11 Nov 2026 (expired TLS certificate).
