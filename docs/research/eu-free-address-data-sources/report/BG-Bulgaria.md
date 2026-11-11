## Bulgaria (BG)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | AGKK cadastre open data (KAIS): building polygons with address fields, numbering incomplete | Shapefile zips per settlement, no registration, no national file | None printed; open reuse known only second-hand | Yes, polygons in BGS2005; EPSG code not stated | No | Each province about every 28 days |

**In short.** No open national address register was found. The substitute is the cadastre agency's open-data file tree: per-settlement shapefiles of buildings, parcels and dwelling units that carry street, number, block, entrance, floor and flat, free without login. There is no national file, so an import must walk the tree settlement by settlement, and in the one town sampled only 62% of buildings had a street number. The page prints no licence. For Sofia alone there is a proper official address register under CC BY.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Отворени данни (Open Data) on the KAIS cadastre portal | Агенция по геодезия, картография и кадастър (AGKK, Geodesy, Cartography and Cadastre Agency) | https://kais.cadastre.bg/bg/OpenData ; English page: https://kais.cadastre.bg/en/OpenData | A file tree: 28 provinces, then municipalities, then settlements labelled with their EKATTE code. Up to six zips per settlement: land parcels, buildings, self-contained units (flats) and three ownership files. Polygons with address attributes | Zips download by plain GET, no login. No single national file | None printed on the page; see caveats | One province regenerated each night in rotation; each about every 28 days | confirmed; licence corrected |
| Адреси на територията на Столична община (addresses in Sofia Municipality) | „Географска информационна система – София" ЕООД (GIS Sofia, wholly owned by the municipality) | Dataset page: https://urbandata.sofia.bg/dataset/address_sofia-zip ; record as JSON: https://urbandata.sofia.bg/api/3/action/package_show?id=address_sofia-zip | The official addresses approved by order of the mayor, with coordinates; 125,245 addresses (publisher's figure, from the file header). Sofia only | GeoJSON (39,917,874 bytes) and CSV zip (1,863,178 bytes), no login | "Creative Commons Признание" (CC BY); no version number stated | Created 2026-08-28, record updated 2026-11-06; "current as of 28.08.2026" | confirmed |
| НКНПА, Национален класификатор на настоящите и постоянните адреси (national classifier of current and permanent addresses) | Not shown in the EU record; its keywords are "НКНПА", "ГРАО", "МРРБА" | Latest record: https://data.europa.eu/api/hub/search/datasets/22309 ; search: https://data.europa.eu/api/hub/search/search?q=%D0%B0%D0%B4%D1%80%D0%B5%D1%81%D0%B8&filter=dataset&facets=%7B%22country%22%3A%5B%22bg%22%5D%7D | Nine yearly editions in the EU catalogue: 2016, 2017, 2018, 2020, 2021, 2022, 2023, 2024, 2025. No 2019 and no 2026 edition. Content not seen | The EU record lists no downloads; the national portal data.egov.bg returns HTTP 403 | Not seen | 2025 record issued 2025-02-27 | corrected (editions); content unverified |
| Намерете пощенски код (find a postcode) | Български пощи (Bulgarian Posts) | https://www.bgpost.bg/postal-services/po-codes | Postcode look-up by quarter, housing estate, boulevard, street or square | Web form behind reCAPTCHA; no downloadable file | Not stated | Not stated | confirmed |
| Пощенски кодове на населените места в България 2020 (postcodes of settlements in Bulgaria, 2020) | On the national open-data portal; publisher not seen | https://data.europa.eu/api/hub/search/datasets/14117 | A postcode list per settlement, by its title; content not seen | The EU record lists no downloads; data.egov.bg returns HTTP 403 | Not seen | Record issued 2022-01-14 | confirmed (existence only) |
| ЕКАТТЕ (EKATTE, unified classifier of administrative-territorial units) | Национален статистически институт (National Statistical Institute, NSI) | https://www.nsi.bg/nrnm/ekatte/archive | Administrative units down to settlement level; no streets, no addresses | Yearly zips in Excel and JSON, 2022 to 2025 | None stated; the page says "© 2026 Национален статистически институт. Всички права запазени." | Yearly; no 2026 archive yet | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Bulgaria | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Bulgarian sources | OpenAddresses | Countrywide: https://github.com/openaddresses/openaddresses/blob/master/sources/bg/countrywide.json ; Sofia: https://github.com/openaddresses/openaddresses/blob/master/sources/bg/city_of_sofia.json ; downloads: https://batch.openaddresses.io | Countrywide: the KAIS buildings data from a cached copy uploaded 2025-01-07 (settlement, street, number). Sofia: the municipal register | Free download; needs a logged-in account | Countrywide: none recorded. Sofia: recorded as CC-BY-4.0 | Countrywide copy dates from 2025-01-07 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- No documented API for the KAIS open data. In practice: the tree is listed by a POST to `/bg/OpenData/Read`, which needs the page's session cookie and anti-forgery token (HTTP 400 without them). Files download with a plain GET to `/bg/OpenData/Download?path=<url-encoded path>`, which works without cookies.
- Sofia's portal exposes its record through the CKAN API: https://urbandata.sofia.bg/api/3/action/package_show?id=address_sofia-zip .
- Bulgarian Posts' postcode search is a web form behind reCAPTCHA, not an API.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.

### Caveats and recent changes

- KAIS licence. The open-data page prints no licence or reuse terms. Its footer reads "© 2025 Агенция по геодезия, картография и кадастър. Всички права запазени!" (all rights reserved). The only statement of reuse terms is second-hand: a post of 19 August 2025 in an OpenStreetMap community thread (https://community.openstreetmap.org/t/use-of-cadastral-data-from-on-osm/113018) reports AGKK's reply that the open data may be used for any purpose without restriction, that naming AGKK as the source is recommended, that the data are under an "open licence" in the sense of Directive (EU) 2019/1024, and that AGKK does not plan to add an explicit licence text. This is a community report of the reply, not AGKK's own page. The ordinance the post cites was not read in an official text.
- KAIS general terms (https://kais.cadastre.bg/bg/Terms) allow use "само за собствени нужди" (for own needs only) and forbid commercial use or passing data to third parties without a contract. These terms are written for remote-access services to registered clients and do not mention the open data.
- Addresses are attributes of cadastral objects, not address points. The geometry is polygons.
- Completeness, from one sample (town of Vidin, EKATTE 10971, files dated 2026-10-17): 14,197 buildings, of which 12,736 have a street name (`strename`), 8,812 a street number (`strnum`, 62%) and 1,448 a quarter name (`quarname`). All 14,197 have a full address text (`immaddr`), for example "гр. Видин, ул. Янтра №36". The same town has 28,441 units and 11,373 parcels.
- Fields. Buildings: `immaddr`, `strename`, `strnum`, `quarname`, `ekatte`, `ekattefn` (settlement), `cadnum` (cadastral identifier), `functype`, `flrcount`. The units file adds `blocknum`, `entrance`, `flrnum` (floor) and `appnum` (flat), with text such as "гр. Видин, ж.к. "Панония", бл. 3, вх. В, ет. 1, ап. 51".
- No postcode field and no Latin transliteration in any of the three files. Text is Cyrillic, UTF-8.
- Coordinate system: the `.prj` reads `PROJCS["BGS2005" … Lambert_Conformal_Conic …]` and carries no EPSG code.
- Refresh: on 2026-11-11 the 28 province folders were dated from 2026-10-14 (Плевен) to 2026-11-10 (Перник), one per night at about 22:00, with no gaps.
- Size of a harvest: the number of settlement folders was not counted. For scale, Vidin province has 11 municipalities and Vidin municipality has 34 settlement folders. The Vidin town zips are 2.2 MB (buildings), 4.7 MB (units) and 2.2 MB (parcels).
- The KAIS platform with this page went live in mid-December 2024, after services were suspended on 11 to 15 December 2024. This comes from community posts quoting AGKK notices.
- OpenAddresses' countrywide Bulgarian source reads a cached copy uploaded on 2025-01-07, not the live tree.
- Sofia file: fields are `street`, `streetnum`, `block`, `entrance`, `lareaunit` (housing estate), `settlement`, `region`, `rn`. Block-addressed buildings in housing estates have no street or house number. The server labels the GeoJSON `Content-Type: application/zip` although it is plain GeoJSON.
- Sofia's open licence is a change. In 2021 GIS Sofia treated the address data as copyrighted and not to be shared without its consent, according to a post in the same community thread.
- Planned national register: a 2020 e-government project document (https://projectregister.egov.bg/wp-content/uploads/2020/06/ИСУН2020-ЦАИСГР-ЦАИСАР.pdf) specifies ЦАИС „Адресен регистър" (a central "Address Register" system) with a unique address identifier (УАИ), with the stated goal of "an open and free register of addresses". A community post of 10 May 2024 says the enabling law had not reached parliament, that the system cannot be built before the law passes, and that municipalities are the original source of address data.
- Postcodes: a draft document on the regulator's site (https://www.crc.bg/files/_bg/System_for_postal_codes.pdf , headed "ПРОЕКТ!") says the Communications Regulation Commission (КРС) maintains and publishes a postcode directory, and that the national postcode is a four-digit number.
- High-value-dataset status: no Bulgarian dataset of any HVD category is flagged in data.europa.eu.

### Not free or not available

- Open national address register: none found. Searched: the EU catalogue data.europa.eu, which harvests the national portal (search "адреси": 19 datasets, none an address register; HVD "Addresses" and "Geospatial" counts both 0). The national portal data.egov.bg itself could not be searched (HTTP 403).
- A single national download of the KAIS data: none; the tree's root lists only province folders.
- KAIS view services (WMS): paid. A community post of May 2024 quotes the tariff as 80 lv per layer per month or 800 lv per year; the tariff itself was not read.
- Postcode file from Bulgarian Posts: none on its postcode page.
- Overture Maps addresses (release 2026-10-21.0): no Bulgarian data.

### Could not be verified

- AGKK's reuse terms in AGKK's own words: only the community report of its reply was seen.
- The EPSG code of the KAIS files (EPSG:7801 was suggested): the `.prj` has no authority tag and no official statement was found.
- How many settlement folders a national harvest covers ("about 5,000" was estimated): the tree was not walked. National record counts were not computed either.
- Licence, formats and content of the НКНПА classifier, of the 2020 postcode list and of any AGKK entries on data.egov.bg: the portal returns HTTP 403 to page and API requests. This includes whether НКНПА is a street code list or geocoded points.
- Status of ЦАИС „Адресен регистър" in 2025 and 2026 (law passed or not, system built or not): one web search in Bulgarian found no law and no launch announcement.
- Whether Bulgaria publishes an INSPIRE Addresses dataset: the former EU INSPIRE Geoportal host serves an expired TLS certificate (record https://inspire-geoportal.ec.europa.eu/srv/api/records/5a796a38-d909-47c5-929e-704963cb604f unread), and `https://inspireportal.egov.bg/geonetwork/srv/api/search/records/_search` returns HTTP 403. The data.europa.eu search for "адреси" shows none.
- Whether КРС publishes its postcode directory today: one web search did not find it.
