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
