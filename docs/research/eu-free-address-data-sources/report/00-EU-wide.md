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

- Croatia: one ATOM file, `https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_(AD).zip` (89,997,286 bytes). The recorded terms, "no limitations to public access", are an INSPIRE access-limitation code, not a reuse licence.
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
