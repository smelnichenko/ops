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
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Sweden | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Sweden | OpenAddresses | https://batch.openaddresses.io ; source definitions: https://github.com/openaddresses/openaddresses/tree/master/sources/se | 18 municipal sources, no countrywide source. Example: Stockholm, from a 2016 cache (https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/se/municipality_of_stockholm.json) | Free download, needs a logged-in account | Stockholm source: no licence recorded | Stockholm: 2016 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **Lantmäteriet STAC catalogue** (https://api.lantmateriet.se/stac-vektor/v1/collections/belagenhetsadresser): open without credentials. It lists the 290 files with size, `created` and `updated` stamps, so a script can see what changed. Only the file fetch needs the Geotorget credentials.
- **Belägenhetsadress Direkt** (the address query API): access point https://api.lantmateriet.se/distribution/produkter/belagenhetsadress/v4.2 ; product page https://geotorget.lantmateriet.se/geodataprodukter/belagenhetsadress-direkt-api . A bare GET on the access point answers HTTP 405. Its terms and rate limits could not be read.
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap. It is the only keyless countrywide lookup found for Sweden.

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
