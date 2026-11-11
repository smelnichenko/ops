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
