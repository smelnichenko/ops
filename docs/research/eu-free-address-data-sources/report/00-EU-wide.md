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
