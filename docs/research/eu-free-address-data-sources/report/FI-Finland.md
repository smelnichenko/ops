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
