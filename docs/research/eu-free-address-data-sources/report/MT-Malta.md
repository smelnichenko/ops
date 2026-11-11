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
