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
