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

- The live behaviour of adressevaelger.dk: the test request could not be made in the checking session. Everything stated about it comes from KDS documentation.
- The coordinate reference system and the file sizes of the DAR file downloads: these need a login. EPSG:25832 was seen only in the official metadata record and in the INSPIRE service.
- How current the data in the keyless INSPIRE API is.
- The listing text of the Dataforsyningen product page "INSPIRE - Adresser" (https://dataforsyningen.dk/data/3937): the page is a JavaScript shell and was not re-read.
- An earlier closure notice for DAWA with the date 1 July 2026: not re-found. Only the 1 October 2026 date is established.
- A service-catalogue line saying the Datafordeler DAR REST service ends on 30 June 2026: the catalogue record was not re-read. The KDS news of 26 February 2026 confirms that a 30 June 2026 plan was moved to the end of 2026, and the KDS documentation now says 15 January 2027.
