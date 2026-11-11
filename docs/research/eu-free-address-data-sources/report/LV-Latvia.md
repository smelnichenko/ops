## Latvia (LV)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Valsts adrešu reģistrs open data on data.gov.lv (VZD) | Bulk CSV and shapefile, no registration | CC BY 4.0 | Yes, LKS-2020 TM plus decimal degrees | Yes | Daily |

**In short.** Download the open data of the Valsts adrešu reģistrs (State Address Register) from data.gov.lv: full CSV and shapefile dumps, anonymous, refreshed every day, CC BY 4.0, with a postcode column and coordinates. The trap is a fresh breaking change: on 7 October 2026 the projected coordinates (`KOORD_X`, `KOORD_Y`) switched from LKS-92 TM to LKS-2020 TM. A second, smaller one: the CSV metadata declares ISO-8859-1, but the file is UTF-8 with a byte-order mark.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| "Valsts adrešu reģistra atvērtie dati" (State Address Register open data; the register's information system is abbreviated VARIS) | Valsts zemes dienests (VZD, State Land Service) | Dataset: https://data.gov.lv/dati/lv/dataset/varis-atvertie-dati ; portal API record: https://data.gov.lv/dati/api/3/action/package_show?id=varis-atvertie-dati ; building addresses: https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/a510737a-18ce-400f-ad4b-04fce5228272/download/aw_eka.csv ; spatial data: https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/b643b1b3-223f-4394-9beb-18524f8b0b82/download/aw_shp.zip ; column metadata: https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/27ab50ae-95ae-46be-88c8-d54d4b4c70b5/download/aw_eka_metadata.json | Denormalised register data, 41 resources. Sizes on 2026-11-11: `aw_eka.csv` (addresses of buildings and of parcels intended for building) 141,795,733 bytes; `aw_dziv.csv` (premises groups, the apartment-level file) 142,907,077; `aw_iela.csv` (streets) 3,337,988; `aw_ciems.csv` (villages) 1,676,792; historic files `aw_eka_his.csv` 192,426,240 and `aw_dziv_his.csv` 215,129,843; `aw_shp.zip` (spatial data, including administrative boundaries) 52,584,597; document-metadata files `aw_doc_nl.csv` 127,554,609 and `aw_doc_tg.csv` 95,137,603. Also cities, municipalities, parishes, historic districts, the link of Riga addresses to city districts, place centroids. `aw_eka.csv` has 611,370 rows (researcher's count, not recounted) | Anonymous. Direct URL pattern `https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/{resource-id}/download/{file}`; HTTP 200 without login | CC BY 4.0 | Daily. Every data resource was stamped 2026-11-11 04:41-04:42 | confirmed |
| "Adreses (INSPIRE)" on geolatvija.lv | VZD | Portal record: https://data.gov.lv/dati/api/3/action/package_show?id=adreses-inspire ; product page: https://geolatvija.lv/main?geoproduct=open&geoProductId=291 ; ATOM feed: https://geolatvija.lv/api/v1/atom/c38d1733-cbc0-48d2-b5d2-1a906a0b9570/serviceatoma ; bulk file: https://geolatvija.lv/api/v1/atom/24650aed-1f3b-4090-81de-aa4346c0ca44/file | INSPIRE Annex I addresses as a WFS download service, a WMS view service and a bulk ATOM feed. The feed offers `adAddressesLV.zip`, 66,096,373 bytes, CRS category EPSG:4258 | ATOM feed and bulk file: no key, no login. WFS and WMS: access not tested | CC BY 4.0 per the portal record. The feed's own rights line is boilerplate: "(c) COPYRIGHTS 2014, INSPIRE; all rights reserved" | Weekly per the portal record; the feed itself is stamped 2024-06-07 | confirmed |
| Official postcode file from Latvijas Pasts (the postal operator) | - | - | None found. A data.gov.lv search for "pasta indeksi" returned 0 datasets; Latvijas Pasts' own site was not checked. Postcodes are inside the VZD data (column `ATRIB`) | - | - | - | none found |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Latvia | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Latvia countrywide | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lv/countrywide.json | Built from the official `aw_shp.zip` | Free download, needs a logged-in account | CC-BY 4.0, attribution "Valsts zemes dienests" | Not stated | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Latvia is among the 19 EU countries covered | No account, GeoParquet | Per country | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **data.gov.lv portal API** (https://data.gov.lv/dati/api/3/action/package_show?id=varis-atvertie-dati): keyless. It lists every resource with its size and `last_modified` stamp, so a script can find the current file URLs and see when they changed.
- **INSPIRE WFS, WMS and ATOM on geolatvija.lv** (https://geolatvija.lv/main?geoproduct=open&geoProductId=291): the ATOM feed and its bulk zip answered without a key. The WFS and WMS endpoints were not tested.
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.
- A national address-search or geocoding API: none identified; it was not specifically searched for.

### Caveats and recent changes

- **Coordinate system changed on 7 October 2026.** The dataset's change log reads "07.10.2026 – transformētas koordinātas no LKS-92 TM uz LKS -2020 TM" (coordinates transformed from LKS-92 TM to LKS-2020 TM). `KOORD_X` and `KOORD_Y` are now the object's centroid in LKS-2020. Code that still treats them as LKS-92 TM now reads a different reference system, and nothing in the file format signals it. The file also carries decimal degrees in `DD_N` and `DD_E`.
- **Encoding.** The CSV metadata declares `ISO-8859-1`, but `aw_eka.csv` starts with a UTF-8 byte-order mark (`EF BB BF`) and decodes as UTF-8 with Latvian diacritics intact. Read it as UTF-8.
- Columns of `aw_eka.csv`: `KODS` (object code), `TIPS_CD`, `STATUSS`, `APSTIPR`, `APST_PAK`, `VKUR_CD` and `VKUR_TIPS` (parent object), `NOSAUKUMS` (name or number), `SORT_NOS`, `ATRIB` (postcode, for example LV-4211), `PNOD_CD` (post office service-area code), `DAT_SAK`, `DAT_MOD`, `DAT_BEIG`, `FOR_BUILD`, `PLAN_ADR` (planned address), `STD` (full address string), `KOORD_X`, `KOORD_Y`, `DD_N`, `DD_E`.
- The file is not only live addresses. It has a status column (`STATUSS`, value `EKS` seen for existing objects) and includes parcels intended for building (`FOR_BUILD`). Filter before import.
- Other entries in the change log: 24.07.2025, three document-metadata resources added; 13.06.2025, new columns in the Riga district link file (`PPILS.csv`).
- The portal record was issued on 2021-12-27 and last modified on 2026-10-07.
- High-value dataset: the CSV metadata carries the keyword "Augstvērtīga datu kopa" (high-value dataset), data.europa.eu flags the dataset `is_hvd: true`, and the portal record names Implementing Regulation (EU) 2023/138 as applicable legislation.
- The INSPIRE bulk file on geolatvija.lv may be old: the portal record says weekly, but the feed is stamped 2024-06-07. Prefer the daily data.gov.lv files.
- File sizes move from day to day as the register changes (by under 1 KB between 2026-11-10 and 2026-11-11).

### Not free or not available

- A free official bulk postcode file from Latvijas Pasts: none found (data.gov.lv search for "pasta indeksi": 0 results; Latvijas Pasts' site not checked). Postcodes come with each address in the VZD data.
- No paid address product was found; the full register is free and anonymous.

### Could not be verified

- Everything that rests only on VZD's own site, because www.vzd.gov.lv timed out on every attempt:
  - the dates of the open-data page https://www.vzd.gov.lv/lv/VAR-atversana (first published 07.12.2021, updated 08.10.2026);
  - the sentence there that the portal data is updated once a day (the daily refresh itself is confirmed from the portal);
  - the specifications for the text data (https://www.vzd.gov.lv/lv/media/9209/download?attachment, said to be updated 07.10.2026) and the spatial data (https://www.vzd.gov.lv/lv/media/5020/download?attachment);
  - the layer list of the shapefile archive (boundary polygons, address points of hamlets and of buildings and buildable parcels, street and road centre lines), and that the former districts were valid to 30 June 2009;
  - the wording of the licence conditions on https://www.vzd.gov.lv/lv/par-datu-izmantosanas-noteikumiem (cite the source, for example "Izmantoti Valsts adrešu reģistra informācijas sistēmas dati", link the licence, describe changes, do not imply VZD's approval). The licence identifier CC-BY-4.0 is confirmed on the portal.
- The row counts of `aw_eka.csv` (researcher's count: 611,370 rows, of which 551,086 existing, 32,507 liquidated, 27,777 erroneous; 457,195 buildings and 154,175 parcels intended for building; every existing row with a postcode and all but one with coordinates; newest `DAT_MOD` 2026.11.09): not recounted, since that needs the full 142 MB file. The first rows are consistent with the description.
- The content and row count of the apartment-level file `aw_dziv.csv`: the file exists (142.9 MB) but was not opened.
- The EPSG code of LKS-2020 TM: not stated in the portal record or the CSV metadata.
- The weekly refresh and the GML format of the geolatvija.lv bulk file: the zip was not opened.
- Who owns the postcode system.
- The OpenAddresses `city_of_riga` source: not opened.
