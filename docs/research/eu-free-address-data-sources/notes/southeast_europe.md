# Free online address data sources in Greece, Cyprus, Croatia, Romania and Bulgaria (state on 11 November 2026)

Method note for the report writer: every "probed" statement below is something I requested myself on 2026-11-11 (HTTP status, file sizes, record counts, field names). Statements taken only from a search-result summary or a third party are marked "(secondary, not opened)" or "unverified". Three official sites refused my automated client with HTTP 403 and were NOT read: `data.egov.bg` (Bulgaria), `www.ktimatologio.gr/oroi-xrisis` and `data.ktimatologio.gr` (Greece). I did not try to get around those refusals.

Ranking of the five countries by what is really available for free:

| Country | Open national address register? | Best free source | House numbers | Coordinates | Postcodes in the data | Licence | Registration |
|---|---|---|---|---|---|---|---|
| Croatia | Yes (RPJ, via INSPIRE GML) | DGU ATOM zip, 1,683,548 addresses, weekly | yes | yes (EPSG:3035) | yes | Otvorena dozvola (open, commercial OK, attribution) | none |
| Bulgaria | No register; cadastre open data carries addresses | AGKK KAIS open data shapefiles per settlement | partly (street no. / block / entrance) | polygons (BGS2005) | no | none stated (unclear) | none |
| Greece | No register | Hellenic Cadastre "declared streets" points, 2,292,989 | mostly | yes (EPSG:2100) | no | CC BY 4.0 | none |
| Cyprus | No usable one (INSPIRE set = 4% of country, no numbers) | Cyprus Post street-to-postcode CSV (no coordinates) | no (ranges for 857 rows) | no | yes | CC BY 4.0 | none (API: yes) |
| Romania | RENNS exists but was never open bulk data; ANCPI geoportal offline since July 2026 cyberattack | Poșta Română postcode file (2016) / municipal street lists | no | no | street-level postcodes | OGL-ROU-1.0 / CC BY 4.0 | none |

---

## Croatia (Hrvatska)

### Takeaway
Croatia is the only one of the five with a complete, open, bulk-downloadable national address dataset: the INSPIRE "Adrese" set derived from DGU's Register of Spatial Units, 1,683,548 house-number addresses with coordinates and postcodes, refreshed weekly, no registration, under the Croatian Open Licence. The catch is format and access path: one 2.6 GB INSPIRE GML file in EPSG:3035 via ATOM only; the public WFS is switched off and the working WFS is reserved for public bodies with a signed protocol.

### Cited Findings

**Register and maintainer**
- The authoritative register is the Registar prostornih jedinica (RPJ, Register of Spatial Units) kept by Državna geodetska uprava (DGU, State Geodetic Administration). The open "Adrese – INSPIRE" dataset is produced by harmonising RPJ source data (house number, street, settlement) through an ETL into INSPIRE GML; RPJ is described as "the official basis" and is maintained from official acts of the competent bodies — [NIPP metadata record d3104048-688a-4305-9471-77288cc6e350](https://geoportal.nipp.hr/geonetwork/srv/api/records/d3104048-688a-4305-9471-77288cc6e350/formatters/xml)
- National open-data portal entry "Adrese INSPIRE" (slug `adrese-inspire`), publisher DGU, created 2026-10-14, modified 2026-10-22, `data_refresh_frequency: weekly`, `access_rights: public` — [data.gov.hr CKAN API](https://data.gov.hr/ckan/api/3/action/package_show?id=adrese-inspire)
- The older portal URL used by third parties, `https://data.gov.hr/ckan/en/dataset/adrese`, returned HTTP 404 on 2026-11-11 (the record was re-created in October 2026 under the new slug) — [old URL](https://data.gov.hr/ckan/en/dataset/adrese); [new record](https://data.gov.hr/ckan/api/3/action/package_show?id=adrese-inspire)

**Bulk download (probed)**
- ATOM service feed: `https://geoportal.dgu.hr/services/atom/xml`; address sub-feed `https://geoportal.dgu.hr/services/atom/ad/xml` (feed `updated` 2026-11-09, dataset entry `updated` 2026-11-08) — [DGU ATOM feed](https://geoportal.dgu.hr/services/atom/xml); [Address feed](https://geoportal.dgu.hr/services/atom/ad/xml)
- Direct file: `https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_(AD).zip` — HTTP 200, `application/zip`, 89,997,286 bytes on 2026-11-11, no login, no key — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip)
- Zip contents (files dated 2026-11-08): `Address.gml` 2,614,426,484 bytes, `ThoroughfareName.gml` 53,410,780 bytes, `AdminUnitName.gml` 7,216,776 bytes, `PostalDescriptor.gml` 793,078 bytes (2.68 GB unpacked) — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip)
- Record counts I counted in that file: 1,683,548 `ad:Address` (matches the file's own `numberMatched="1683548"`), 54,465 `ThoroughfareName`, 900 `PostalDescriptor`, 6,760 `AdminUnitName` — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip)
- Format: INSPIRE Addresses GML 3.2.1 (schema `ad/4.0`), a WFS 2.0 FeatureCollection written to disk as a single line of XML; geometry in ETRS89/LAEA, EPSG:3035 — [Address feed](https://geoportal.dgu.hr/services/atom/ad/xml)

**Content (probed)**
- Each address: point coordinate (EPSG:3035), house number in `LocatorDesignator` (type addressNumber), `validFrom`, `beginLifespanVersion`, and links to one street, one postal descriptor and two admin-unit names; `inspireId` is `localId` like `KB.0000000135` with namespace `HR.DGU.RPJ` — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip)
- All 1,683,548 addresses carry locator level `siteLevel`: one record per house number, no entrance or dwelling-unit level — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip)
- `ad:alternativeIdentifier` holds the whole address as one string, e.g. "Brežna ulica 33 Andraševec 49243 Oroslavje" (street, number, settlement, 5-digit postcode, post town), which is what OpenAddresses parses with regular expressions — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip); [OpenAddresses hr/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/hr/countrywide.json)
- `ad:specification` and `ad:method` of the position are nil ("unpopulated"), so the file does not say whether a point is on the building, entrance or parcel — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip)
- Script is Latin with Croatian diacritics, UTF-8; no transliteration issue — [download](https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip)

**Services: what is download and what is view-only (probed)**
- INSPIRE WMS (view only, anonymous): `https://geoportal.dgu.hr/services/inspire/ad/wms?service=WMS&version=1.3.0&request=GetCapabilities` — HTTP 200, layers `AD.Address` — [WMS capabilities](https://geoportal.dgu.hr/services/inspire/ad/wms?service=WMS&version=1.3.0&request=GetCapabilities)
- Anonymous INSPIRE WFS is not available: `https://geoportal.dgu.hr/services/inspire/ad/wfs?...GetCapabilities` answers with an OWS exception "Service WFS is disabled" (same for `/services/auth/inspire/ad/wfs`) — [WFS endpoint](https://geoportal.dgu.hr/services/inspire/ad/wfs?service=WFS&version=2.0.0&request=GetCapabilities)
- A working address WFS exists only "by agreement": "Adrese - WFS INSPIRE (sporazum)", `https://geoportal.dgu.hr/services/sla/inspire/wfs_ad/wfs?authKey=…`, open to public-law bodies with special user status that sign a data-use protocol with DGU — [NIPP register, source 452](https://registri.nipp.hr/api/izvori/452/pdf/)
- A second WMS for registered users is listed at `https://geoportal.dgu.hr/services/auth/inspire/ad/wms` — [data.gov.hr CKAN API](https://data.gov.hr/ckan/api/3/action/package_show?id=adrese-inspire)

**Licence**
- Licence on the portal record and on each resource: "Otvorena dozvola (OD)", `https://data.gov.hr/id/licence/otvorena-dozvola-rh` — [data.gov.hr CKAN API](https://data.gov.hr/ckan/api/3/action/package_show?id=adrese-inspire)
- The metadata's use constraint: "Uvjeti korištenja podataka za ponovnu uporabu u skladu su s otvorenom dozvolom dostupnom na poveznici: https://data.gov.hr/otvorena-dozvola" — [NIPP metadata record](https://geoportal.nipp.hr/geonetwork/srv/api/records/d3104048-688a-4305-9471-77288cc6e350/formatters/xml)
- The WMS capabilities `Fees` element repeats that the open licence applies to the service and the data — [WMS capabilities](https://geoportal.dgu.hr/services/inspire/ad/wms?service=WMS&version=1.3.0&request=GetCapabilities)
- Contradictory label in the same metadata and in the ATOM `rights` element: "ograničenje javnog pristupa prema članku 13 stavku 1 točki (e) INSPIRE Direktive" (limitation on public access for intellectual property rights) — [Address feed](https://geoportal.dgu.hr/services/atom/ad/xml); OpenAddresses, reading the record in 2024, recorded "no limitations to public access" — [OpenAddresses hr/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/hr/countrywide.json)
- What the Open Licence allows (secondary, summary of the Rulebook NN 67/2017, not the licence page itself, which is JavaScript-only and unreadable to my client): use for commercial and non-commercial purposes; a ban on commercial use cannot be added; the user must name or link the source and state the date of last change — [Pravilnik o vrstama i sadržaju dozvola (copy on sudovi.hr)](https://sudovi.hr/sites/default/files/dokumenti/2023-02/Pravilnik%20o%20vrstama%20i%20sadr%C5%BEaju%20dozvola%20kojima%20se%20ure%C4%91uju%20uvjeti%20ponovne%20uporabe%20informacija.pdf)
- No charge for DGU network services: under NN 39/22, Art. 1(3) (amendment of the State Survey and Real Estate Cadastre Act) "real costs are not charged" for access through network services or other electronic access points — [NIPP register, source 1326 (terms section)](https://registri.nipp.hr/api/izvori/1326/pdf/)

**Update frequency**
- Weekly: metadata maintenance "Tjedno. Podaci se ažuriraju jednom tjedno"; the zip I downloaded on Wednesday 2026-11-11 was generated Sunday 2026-11-08 — [NIPP metadata record](https://geoportal.nipp.hr/geonetwork/srv/api/records/d3104048-688a-4305-9471-77288cc6e350/formatters/xml); [Address feed](https://geoportal.dgu.hr/services/atom/ad/xml)

**HVD status**
- Flagged as a High-Value Dataset: `is_hvd: 1`, `applicable_legislation: http://data.europa.eu/eli/reg_impl/2023/138/oj`, `hvd_category: http://data.europa.eu/bna/c_c3de25e4` (EU vocabulary label "Addresses") — [data.gov.hr CKAN API](https://data.gov.hr/ckan/api/3/action/package_show?id=adrese-inspire); [EU HVD category c_c3de25e4](http://data.europa.eu/bna/c_c3de25e4)
- On data.europa.eu, a search restricted to HVD category "Addresses" returns exactly one dataset for Croatia (`adrese-inspire`) and zero for Greece, Cyprus, Romania and Bulgaria (queried 2026-11-11) — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?q=&filter=dataset&facets=%7B%22country%22%3A%5B%22hr%22%5D%2C%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)

**Secondary sources**
- Hrvatska pošta (postal operator) publishes free Excel and XML files without login on "Preuzimanje podataka o poštanskim uredima": settlements with their postcode, post offices, Zagreb streets with their delivery post office, parcel lockers — [posta.hr download page](https://www.posta.hr/preuzimanje-podataka-o-postanskim-uredima)
- Probed: `https://www.posta.hr/mjestaRh.aspx?vrsta=xml` returns 6,787 records (fields `brojPu` postcode, `nazivPu` post office name, `naselje` settlement, `zupanija` county); `https://www.posta.hr/zagrebulice.aspx?vrsta=xml` returns 5,378 Zagreb street rows, some with house-number ranges (e.g. "ALEJA GRADA BOLONJE 2 - 68" → 10090) — [mjestaRh XML](https://www.posta.hr/mjestaRh.aspx?vrsta=xml); [zagrebulice XML](https://www.posta.hr/zagrebulice.aspx?vrsta=xml)
- City portals on data.gov.hr: Zagreb "Registar naziva ulica - adresna prostorna jedinica" (street names only, XLSX/CSV, Otvorena dozvola); Rijeka "adrese po MO s ukupnim brojem stanova po adresi" (XLS, CC BY 4.0) — [data.gov.hr search](https://data.gov.hr/ckan/api/3/action/package_search?q=registar+prostornih+jedinica&rows=10); [data.gov.hr search "adrese"](https://data.gov.hr/ckan/api/3/action/package_search?q=adrese&rows=15)
- OpenAddresses has one countrywide Croatian source pointing at the same DGU zip, marked `frequency: weekly`, added 2024-04-25 — [OpenAddresses hr/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/hr/countrywide.json)

### Inferences
- The "Article 13(1)(e)" public-access limitation label is a metadata leftover: the same record, the WMS capabilities and the national portal all state the Open Licence, and the file downloads anonymously. A cautious reuser should cite the Open Licence and attribute DGU with the dataset date.
- HVD compliance looks partial. Regulation 2023/138 asks for both bulk download and API; Croatia gives bulk download (ATOM) but the anonymous WFS answers "disabled" and the working WFS needs a signed protocol. I found no official document calling this non-compliance; it is my reading of the probe results.
- Practical cost of use: there is no CSV, GeoPackage or regional split. A user must stream-parse a 2.6 GB single-line GML and reproject from EPSG:3035. Postcode, settlement and street can be taken either by resolving the `xlink` components or by parsing the `alternativeIdentifier` string.
- The ATOM feed's declared `length` (84,406,413) differs from the served file (89,997,286 bytes), so the feed's length attribute is not kept in step with the weekly regeneration.

### Gaps
- No free geocoding, reverse-geocoding or address-autocomplete API from DGU was found or verified; the geoportal's own search box was not tested.
- The text of the Open Licence page (`https://data.gov.hr/otvorena-dozvola`) could not be read (JavaScript-rendered); the terms above come from a secondary summary of the Rulebook.
- Hrvatska pošta's page shows no licence or reuse terms for its files; a 2014–2015 OpenStreetMap mailing-list exchange about permission exists (secondary, not opened) — [talk-hr 2015](https://lists.openstreetmap.org/pipermail/talk-hr/2015-January/002317.html)
- I did not check whether the RPJ source (non-INSPIRE) is offered in any other format (e.g. SOAP service for descriptive data mentioned in an older DGU document, secondary) — [DGU RPJ document (secondary)](https://www.bib.irb.hr:8443/1091653/download/1091653.HKOIG-Zbornik-radova-2019-web-81-86.pdf)
- Whether the PostalDescriptor objects (900) cover every delivery postcode was not compared with Hrvatska pošta's 6,787-row list.

---

## Bulgaria (България)

### Takeaway
Bulgaria has no open national address register; the planned central "Address Register" system (ЦАИС „Адресен регистър") is not confirmed as built. The realistic free source is the cadastre agency's open-data file tree on the KAIS portal: per-settlement shapefiles of parcels, buildings and dwelling units that carry address attributes (street, number, quarter, block, entrance, floor, flat), downloadable without login — but with no stated licence, polygons instead of address points, no postcodes, and incomplete numbering. Sofia alone publishes a proper official address register (CC BY).

### Cited Findings

**No open national address register**
- data.europa.eu shows no Bulgarian dataset in HVD category "Addresses" and none in the parent HVD category "Geospatial" (both queries count = 0 on 2026-11-11) — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?q=&filter=dataset&facets=%7B%22country%22%3A%5B%22bg%22%5D%2C%22hvdCategory%22%3A%5B%22c_ac64a52d%22%5D%7D)
- A central system "ЦАИС Адресен регистър" was specified as a project (addresses to carry a unique address identifier, УАИ) in a 2020 e-government project document (secondary, not opened) — [projectregister.egov.bg](https://projectregister.egov.bg/wp-content/uploads/2020/06/ИСУН2020-ЦАИСГР-ЦАИСАР.pdf)
- Community report of 10 May 2024: preparation of ЦАИС „Адресен регистър" under way, but the enabling law had not reached parliament and the system cannot be built before it passes; municipalities are the original source of address data; register data is meant to go to INSPIRE afterwards, no date — [OpenStreetMap community thread](https://community.openstreetmap.org/t/use-of-cadastral-data-from-on-osm/113018)

**Best free source: AGKK cadastre open data on KAIS (probed)**
- Publisher: Агенция по геодезия, картография и кадастър (AGKK, Geodesy, Cartography and Cadastre Agency). Page: `https://kais.cadastre.bg/bg/OpenData` ("Отворени данни"), HTTP 200, no login; English page `https://kais.cadastre.bg/en/OpenData` — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- Structure: a file tree of 28 provinces (област) → municipalities (община) → settlements labelled with their EKATTE code, e.g. "гр. Видин (10971)". Per settlement up to six zip files: "поземлени имоти" (land parcels), "сгради" (buildings), "самостоятелни обекти" (self-contained units, i.e. flats), and three "собственост …" (ownership-type) files — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- Access mechanics: the tree is listed by a POST to `/bg/OpenData/Read` that needs the page's session cookie and anti-forgery token; files download with a plain GET to `/bg/OpenData/Download?path=<url-encoded path>` and returned HTTP 200 `application/zip` even without cookies. There is no single national file and no documented API — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- Refresh: one province is regenerated each night in rotation; folder timestamps on 2026-11-11 ran from 2026-10-14 (Плевен) to 2026-11-10 (Перник), i.e. each province about every 28 days — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- Format: ESRI shapefile, polygons, `.cpg` UTF-8, Cyrillic attribute values; `.prj` = `PROJCS["BGS2005" … Lambert_Conformal_Conic …]` (the Bulgarian cadastral coordinate system) — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- Sample, town of Vidin (EKATTE 10971), files dated 2026-10-17: buildings 14,197 records (zip 2.2 MB, dbf 52 MB), units 28,441 records (zip 4.7 MB), parcels 11,373 records (zip 2.2 MB) — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- Address fields in the buildings file: `immaddr` (full address text, e.g. "гр. Видин, ул. Янтра №36"), `strename` (street, filled in 12,736 of 14,197), `strnum` (number, filled in 8,812 of 14,197), `quarname` (quarter / housing estate), `ekatte`, `ekattefn` (settlement), plus `cadnum` (cadastral identifier), `functype`, `flrcount` — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- The units file adds `blocknum` (block), `entrance`, `flrnum` (floor), `appnum` (flat), with full text like "гр. Видин, ж.к. "Вида", бл. 3, вх. А, ет. 6, ап. 16" — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- No postcode field and no Latin transliteration in any of the three files — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- History: the new KAIS platform with this open-data page went live in mid-December 2024 after a system migration (services suspended 11–15 December 2024), per community reports quoting AGKK notices — [OpenStreetMap community thread](https://community.openstreetmap.org/t/use-of-cadastral-data-from-on-osm/113018)

**Licence: none stated**
- The open-data page carries no licence or reuse terms; its footer reads "© 2025 Агенция по геодезия, картография и кадастър. Всички права запазени!" — [KAIS Open Data](https://kais.cadastre.bg/bg/OpenData)
- The portal's general terms say services and reports obtained through KAIS are "само за собствени нужди" (for own needs only) and may not be used "с търговска цел" (commercially) or passed to third parties unless a contract says otherwise — [KAIS general terms](https://kais.cadastre.bg/bg/Terms)
- Community members noted on 16–17 December 2024 that "никъде не се споменават условия на ползване, нито лиценз" (no terms of use or licence are mentioned anywhere) for the open data — [OpenStreetMap community thread](https://community.openstreetmap.org/t/use-of-cadastral-data-from-on-osm/113018)
- OpenAddresses uses this source without recording any licence, from a cached copy uploaded 2025-01-07 (fields `ekattefn`, `strename`, `strnum`) — [OpenAddresses bg/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/bg/countrywide.json)

**Sofia: an official municipal address register, open (probed)**
- "Адреси на територията на Столична община" on the Sofia data portal, publisher „Географска информационна система – София" ЕООД (GIS Sofia, wholly owned by the municipality): "the official addresses … approved by order of the mayor", with coordinates; created 2026-08-28, last updated 2026-11-06, "current as of 28.08.2026" — [urbandata.sofia.bg dataset](https://urbandata.sofia.bg/dataset/address_sofia-zip)
- Licence: "Creative Commons Признание" (`license_id: cc-by`); resources: GeoJSON (39,917,874 bytes, HTTP 200) and CSV zip (1,863,178 bytes) — [urbandata.sofia.bg CKAN API](https://urbandata.sofia.bg/api/3/action/package_show?id=address_sofia-zip)
- Fields used by OpenAddresses: `street`, `streetnum`, `block`, `entrance`, `lareaunit` (housing estate), `settlement`, `region`, `rn`; block-addressed buildings in housing estates have no street or house number — [OpenAddresses bg/city_of_sofia.json](https://github.com/openaddresses/openaddresses/blob/master/sources/bg/city_of_sofia.json)
- This is a change: in 2021 GIS-Sofia treated Sofia address data as copyrighted and not shareable without its consent (community report) — [OpenStreetMap community thread](https://community.openstreetmap.org/t/use-of-cadastral-data-from-on-osm/113018)

**Other secondary sources**
- GRAO national classifier of addresses (НКНПА, "Национален класификатор на настоящите и постоянните адреси", keywords ГРАО / МРРБ): yearly datasets 2016–2025 are harvested from data.egov.bg into data.europa.eu (ids 7481, 7482, 7476, 13019, 14925, 17994, 18844, 20063, 22309); the 2025 record was issued 2025-02-27; no 2026 edition appeared in the harvest; `is_hvd: false` — [data.europa.eu record 22309](https://data.europa.eu/api/hub/search/datasets/22309); [search](https://data.europa.eu/api/hub/search/search?q=%D0%B0%D0%B4%D1%80%D0%B5%D1%81%D0%B8&filter=dataset&facets=%7B%22country%22%3A%5B%22bg%22%5D%7D)
- EKATTE (unified classifier of administrative-territorial units, settlement level only) is downloadable from the National Statistical Institute as yearly zips in Excel and JSON, 2022–2025 — [NSI EKATTE archive](https://www.nsi.bg/nrnm/ekatte/archive)
- Bulgarian Posts offers only a postcode look-up form ("Намерете пощенски код", by quarter / estate / boulevard / street / square), protected by reCAPTCHA; no downloadable file on that page — [bgpost.bg postcodes](https://www.bgpost.bg/postal-services/po-codes)
- A dataset "Пощенски кодове на населените места в България 2020" exists on the national portal (harvested record issued 2022-01-14) — [data.europa.eu record 14117](https://data.europa.eu/api/hub/search/datasets/14117)
- Paid view services: WMS access for KAIS subscribers was reported in May 2024 as 80 lv per layer per month or 800 lv per year under the tariff (community report) — [OpenStreetMap community thread](https://community.openstreetmap.org/t/use-of-cadastral-data-from-on-osm/113018)

### Inferences
- The cadastre files are an address source by side effect: addresses are attributes of cadastral objects, so coverage follows the cadastral map, several objects share one address, and block-style addresses (ж.к. / бл. / вх.) sit in separate fields or only in the `immaddr` text. In the Vidin sample only 62% of buildings have a street number.
- Because no licence is stated and the only written terms on the portal forbid commercial use of "services and reports", commercial reuse of the KAIS open data is legally unclear; the cautious reading is "free to download, reuse rights not granted in writing".
- Getting national coverage means walking about 5,000 settlement folders with a session-bound listing call; there is no bulk national file, so a full harvest is slow and should be paced.
- The NKNPA classifier is, by its name and origin (civil registration), a code list of streets and localisation units per settlement rather than geocoded house-number points; I could not open it to confirm.
- The CRS is most likely EPSG:7801 (BGS2005 / CCS2005); the `.prj` gives parameters but no EPSG code — unverified.

### Gaps
- `data.egov.bg` refused my automated client (HTTP 403), so the licence, formats and content of the NKNPA classifier, of the 2020 postcode list and of any AGKK entries there are unverified. data.europa.eu holds only titles and keywords for these records.
- Status of ЦАИС „Адресен регистър" in 2025–2026 (law passed or not, system built or not): no source found.
- Whether Bulgaria publishes an INSPIRE Addresses dataset on `inspire.egov.bg`: not found; a search summary mentions only an INSPIRE "Buildings" record with "No conditions apply" (secondary, not opened) — [INSPIRE Geoportal record (secondary)](https://inspire-geoportal.ec.europa.eu/srv/api/records/5a796a38-d909-47c5-929e-704963cb604f)
- The official postcode index is said to be kept and published by the regulator КРС (crc.bg); the documents found were drafts (secondary, not opened) — [crc.bg](https://www.crc.bg/files/_bg/System_for_postal_codes.pdf)
- Total national record counts for the KAIS files were not computed (only Vidin was sampled).

---

## Greece (Ελλάδα)

### Takeaway
Greece has no national address register and no INSPIRE Addresses dataset. Since February 2026 the Hellenic Cadastre publishes one national point file of owner-declared street names and numbers (2,292,989 points, CC BY 4.0, no registration, flagged as a geospatial HVD) — the best free source, but it has only two attributes (street, number), no municipality, no postcode, no identifier, and is a 2023 snapshot of self-declared data. Postcodes stay with ELTA as a web look-up only.

### Cited Findings

**No register**
- data.europa.eu returns no Greek dataset in HVD category "Addresses" (count = 0, 2026-11-11) — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?q=&filter=dataset&facets=%7B%22country%22%3A%5B%22gr%22%5D%2C%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- OpenAddresses' maintainers describe the situation as: Greece "publishes national street-name/number points via the Hellenic Cadastre, but that dataset carries no city/municipality field" — [OpenAddresses scripts/gr/README.md](https://github.com/openaddresses/openaddresses/blob/master/scripts/gr/README.md)
- A Eurostat document states that Greek census information "did not include point data" and "there was not a registry of buildings/addresses" (secondary, not opened; may describe an older census round) — [Eurostat Statistics Explained PDF](https://ec.europa.eu/eurostat/statistics-explained/SEPDF/cache/75998.pdf)
- A 2020 EU factsheet (LIFO) recorded only one implemented location register, cadastral parcels (secondary, not opened) — [LIFO 2020 Greece factsheet](https://interoperable-europe.ec.europa.eu/collection/elise-european-location-interoperability-solutions-e-government/solution/lifo-location-interoperability-framework-observatory/document/lifo-2020-greece-country-factsheet)

**Best free source: Hellenic Cadastre declared streets (probed)**
- Dataset "Στοιχεία οδών δηλώσεων Ελληνικού Κτηματολογίου" (English title on the portal: "Street names and numbers according to cadastral surveying declarations"), publisher Ελληνικό Κτηματολόγιο (Hellenic Cadastre, a public-law body supervised by the Ministry of Digital Governance) — [data.gov.gr dataset page](https://data.gov.gr/dataset/stoicheia-odon-diloseon-ellinikoy-ktimatologioy)
- What it is: street name and numbering "as declared by property owners during the collection of declarations for the creation of the National Cadastre"; point data in the Greek Geodetic Reference System 1987 (ΕΓΣΑ87); fields `ADDRESS` (declared street name) and `NUM` (declared number) — [data.gov.gr dataset page](https://data.gov.gr/dataset/stoicheia-odon-diloseon-ellinikoy-ktimatologioy)
- Portal record created 2026-02-03, metadata modified 2026-05-11, frequency "as needed", access rights PUBLIC — [data.gov.gr CKAN API](https://data.gov.gr/api/3/action/package_show?id=stoicheia-odon-diloseon-ellinikoy-ktimatologioy)
- Direct download: `https://data.gov.gr/dataset/16068541-970c-4d1a-8047-b95fd4d261ba/resource/946e2a6a-8ab8-4c62-89e3-e14ecd9868a1/download/ogp_hc_regstreets_egsa87.zip` — redirects to cloud storage, HTTP 200, 64,396,519 bytes, no login — [download](https://data.gov.gr/dataset/16068541-970c-4d1a-8047-b95fd4d261ba/resource/946e2a6a-8ab8-4c62-89e3-e14ecd9868a1/download/ogp_hc_regstreets_egsa87.zip)
- Content I measured: shapefile `HC_RegStreets_EGSA87`, 2,292,989 point records, exactly two attribute fields (`ADDRESS` C254, `NUM` C10), UTF-8, CRS Greek Grid EPSG:2100; dbf 607 MB unpacked — [download](https://data.gov.gr/dataset/16068541-970c-4d1a-8047-b95fd4d261ba/resource/946e2a6a-8ab8-4c62-89e3-e14ecd9868a1/download/ogp_hc_regstreets_egsa87.zip)
- In the first 400,000 records `NUM` is filled in 344,555 (86%); street names are Greek capitals, often abbreviated (e.g. "ΕΘΝ.ΑΝΤΙΣΤΑΣΗΣ", "ΤΡΙΚΟΥΠΗ Χ."), no Latin transliteration — [download](https://data.gov.gr/dataset/16068541-970c-4d1a-8047-b95fd4d261ba/resource/946e2a6a-8ab8-4c62-89e3-e14ecd9868a1/download/ogp_hc_regstreets_egsa87.zip)
- Age of the data: the shapefile parts inside the zip are dated 2023-11-20 and the embedded metadata 2025-04-11, although the portal record is from 2026 — [download](https://data.gov.gr/dataset/16068541-970c-4d1a-8047-b95fd4d261ba/resource/946e2a6a-8ab8-4c62-89e3-e14ecd9868a1/download/ogp_hc_regstreets_egsa87.zip)
- Known defect reported by OpenAddresses: a subset of `NUM` values are "anomalously long numeric strings (e.g. 0630278511)", likely another identifier leaked into the field — [OpenAddresses scripts/gr/README.md](https://github.com/openaddresses/openaddresses/blob/master/scripts/gr/README.md)
- No free API or WFS for this dataset is listed; the portal record has only the SHP zip and an all-in-one zip (`datastore_active: False`) — [data.gov.gr CKAN API](https://data.gov.gr/api/3/action/package_show?id=stoicheia-odon-diloseon-ellinikoy-ktimatologioy)

**Licence**
- Resource licence: Creative Commons Attribution 4.0 International (`CC_BY_4_0`); the resource `rights` field also points to the Cadastre's terms `https://www.ktimatologio.gr/oroi-xrisis`, and the embedded metadata says the dataset "is subject to the terms of use of the Hellenic Cadastre" — [data.gov.gr CKAN API](https://data.gov.gr/api/3/action/package_show?id=stoicheia-odon-diloseon-ellinikoy-ktimatologioy)
- data.gov.gr portal terms: access is free "without obligation of registration, payment of fees or justification"; every user may reuse data "for any lawful purpose, including commercial exploitation"; the usual licences are CC0 and CC BY 4.0 — [data.gov.gr terms of use](https://data.gov.gr/en/pages/terms-of-use)

**HVD status**
- The dataset is flagged as a High-Value Dataset: `applicable_legislation` includes `http://data.europa.eu/eli/reg_impl/2023/138/oj` and `hvd_category` is `c_ac64a52d` (Geospatial, the top-level category — not the "Addresses" sub-category) — [data.gov.gr CKAN API](https://data.gov.gr/api/3/action/package_show?id=stoicheia-odon-diloseon-ellinikoy-ktimatologioy); [data.europa.eu record](https://data.europa.eu/api/hub/search/datasets/16068541-970c-4d1a-8047-b95fd4d261ba)

**Postcodes**
- ELTA (Hellenic Post) runs a look-up site "Αναζήτηση Ταχυδρομικών Κωδικών & Διευθύνσεων" at `https://postalcodes.elta.gr/`, behind Google reCAPTCHA, "Copyright © Ελληνικά Ταχυδρομεία (ΕΛΤΑ)"; it is a search form, no file download is offered — [postalcodes.elta.gr](https://postalcodes.elta.gr/)
- OpenAddresses' maintainers found "no open national postal-code dataset" for Greece after checking GeoNames, DataHub and the Greek/EU catalogues, and left postcode out — [OpenAddresses scripts/gr/README.md](https://github.com/openaddresses/openaddresses/blob/master/scripts/gr/README.md)
- ELTA, as universal service provider, processes and manages the country's postcodes under a 2018 ministerial decision (secondary, not opened) — [odigostoupoliti.eu](https://www.odigostoupoliti.eu/taxydromikoi-kodikes-epexergasia-diaxeirisi-axiopoiisi/)

**Municipal and derived sources**
- OpenAddresses' Greek countrywide source (added 2026-09-29) is a derived CSV: the Cadastre points spatially joined to the 326 "Kallikratis" municipality polygons from the Ministry of Environment and Energy GeoServer, columns `STREET, NUMBER, CITY, MUN_CODE, LON, LAT`, about 2.29 M rows, CC BY 4.0 — [OpenAddresses gr/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/gr/countrywide.json); [scripts/gr/README.md](https://github.com/openaddresses/openaddresses/blob/master/scripts/gr/README.md)
- Municipality of Kalamaria publishes a street-numbering shapefile (fields `Odos`, `Arithmos`) on data.gov.gr; licence "presumed" by OpenAddresses — [OpenAddresses gr/b/municipality_of_kalamaria.json](https://github.com/openaddresses/openaddresses/blob/master/sources/gr/b/municipality_of_kalamaria.json)
- Other municipalities list address layers on data.gov.gr, visible in the EU catalogue: Ilion, Papagou-Cholargou, Chalandri, Egaleo ("Διευθύνσεις"), Piraeus ("Ταχυδρομικές Διευθύνσεις"), Keratsini-Drapetsona ("Διευθύνσεις Κτηρίων"), Agrinio ("Αρίθμηση Διευθύνσεων ΚΑΕΚ"); the record ids contain "wms", content and download not checked — [data.europa.eu search](https://data.europa.eu/api/hub/search/search?q=%CE%B4%CE%B9%CE%B5%CF%85%CE%B8%CF%8D%CE%BD%CF%83%CE%B5%CE%B9%CF%82&filter=dataset&facets=%7B%22country%22%3A%5B%22gr%22%5D%7D)

### Inferences
- The Cadastre file is not an address register: points are positions of declared properties, the same street name repeats across municipalities, and there is no key. To be usable it must be joined to municipality (and ideally settlement) polygons, as OpenAddresses did; postcode cannot be attached from any open file.
- CC BY 4.0 on the portal plus the portal's own terms give a clear commercial-reuse basis; the extra reference to the Cadastre's terms of use is the one loose end, because that page was not readable.
- Tagging the file under HVD "Geospatial" rather than "Addresses" fits the facts: Greece is using it to show an HVD entry while having no address register. I found no official statement of non-compliance.
- Declarations in areas whose cadastral survey finished after 2023 are probably missing or thin, since the file is a November 2023 extract; coverage by region was not measured.

### Gaps
- `https://www.ktimatologio.gr/oroi-xrisis` and `https://data.ktimatologio.gr/` returned HTTP 403 to my client; the Cadastre's own terms and its open-data portal were not read.
- The portal's own link checker marks the SHP resource "broken: 401 UNAUTHORIZED", yet my direct download worked; stability of the link is therefore uncertain — [data.gov.gr CKAN API](https://data.gov.gr/api/3/action/package_show?id=stoicheia-odon-diloseon-ellinikoy-ktimatologioy)
- ELSTAT (census building data) and geodata.gov.gr were not opened; no address-level open file from either was found through search.
- Whether the Hellenic Cadastre's INSPIRE geoportal offers anything beyond cadastral parcels: a gov.gr page says INSPIRE data needs an application to the Cadastre (secondary, not opened) — [gov.gr](https://www.gov.gr/en/org/ktimanet/ktematographese/geopule-geokhorikon-dedomenon-inspire-ellenikou-ktematologiou)
- No announced national address-register project was found (search in Greek for "Εθνικό Μητρώο Διευθύνσεων" returned only property-registry items).

---

## Cyprus (Κύπρος)

### Takeaway
Cyprus has no usable open address register. The Department of Lands and Surveys publishes an INSPIRE "Addresses" service under CC BY 4.0 with open WFS and REST access, but it holds 80,934 points covering about 4% of the country, with street names only — every house-number field is empty. The practical free source is Cyprus Post's street-to-postcode directory (CSV/XLSX, CC BY 4.0, bilingual Greek/Latin), which has no coordinates and no individual house numbers.

### Cited Findings

**DLS INSPIRE Addresses (probed)**
- Dataset "Διευθύνσεις - Addresses (INSPIRE)", publisher Τμήμα Κτηματολογίου και Χωρομετρίας (Department of Lands and Surveys, DLS): created from Registration Branch data and parcel locations; "Τα δεδομένα καλύπτουν το 4% ολόκληρης της Κύπρου" (the data cover 4% of all Cyprus); licence CC BY 4.0; released 15/01/2018, modified 16/03/2026, frequency "Irregularly", temporal coverage 12/11/2015 — [data.gov.cy dataset 543](https://data.gov.cy/en/dataset/543)
- Access points listed: WFS, WMS, esriREST, JSON, SOAP — [data.gov.cy dataset 543](https://data.gov.cy/en/dataset/543)
- ArcGIS REST service `https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer`: ArcGIS 10.91, one point layer "Addresses" plus INSPIRE tables, CRS EPSG:4258 (ETRS89 geographic), capabilities "Map,Query,Data", query formats JSON and geoJSON, `maxRecordCount` 1000, no key — [DLS REST service](https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer?f=json)
- Count query on layer 0: 80,934 address points — [count query](https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/0/query?where=1%3D1&returnCountOnly=true&f=json)
- House numbers are absent: the locator-designator table has 80,934 rows of type `addressNumber`, and a query for `designator IS NOT NULL` returns 0 — [designator query](https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/3/query?where=designator+IS+NOT+NULL&returnCountOnly=true&f=json)
- Street names are stored in Latin transliteration, capitals (e.g. "IOANNI PSYCHARI", "GEORGIOU ANASTASIOU") — [name table sample](https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/4/query?where=1%3D1&outFields=*&resultRecordCount=2&f=json)
- Positions are parcel-based (`specification: parcel`, `method: byAdministrator`); identifiers are `AD.<n>` in namespace `CY.0001-DLS.AD`; status "current"; no postcode component — [layer sample](https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/0/query?where=1%3D1&outFields=*&resultRecordCount=3&f=json)
- INSPIRE WFS 2.0 (real data download): `https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/exts/InspireFeatureDownload/service?VERSION=2.0.0&SERVICE=WFS&REQUEST=GetCapabilities` — HTTP 200, feature type `ad:Address`, default CRS EPSG:4258, `Fees: no conditions apply`, `AccessConstraints: None` — [DLS WFS capabilities](https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/exts/InspireFeatureDownload/service?VERSION=2.0.0&SERVICE=WFS&REQUEST=GetCapabilities)
- WMS (view only): `https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/WMSServer?request=GetCapabilities&service=WMS` — [data.gov.cy resource 1504](https://data.gov.cy/en/resource/1504)
- OpenAddresses added a Cyprus source on 2026-09-29 with the note: "Current source data contains no house numbers … only street name and point geometry are populated. Coverage is also partial, about 4% of Cyprus per the publisher." — [OpenAddresses cy/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/cy/countrywide.json)

**Cyprus Post postcode data (probed)**
- "Ταχυδρομικός Κώδικας ανά Δρόμο σε Αστικές και Αγροτικές Περιοχές" (postcode per street, urban and rural areas), publisher Τμήμα Ταχυδρομικών Υπηρεσιών (Department of Postal Services): CC BY 4.0, frequency "Annually", modified 16/01/2024, temporal coverage 02/08/2019–01/09/2021; three CSV editions (Aug 2019, Jul 2020, Sep 2021) — [data.gov.cy dataset 1037](https://data.gov.cy/en/dataset/1037)
- Latest CSV (Sep 2021 edition) downloads without login from `https://data.gov.cy/en/resource/3104/download/file`: 6,880,847 bytes, 32,819 rows, 1,117 distinct postcodes — [download](https://data.gov.cy/en/resource/3104/download/file)
- Columns: street name in Greek and in Latin, street limit "FROM - TO", postcode (4 digits), municipality/community/area (GR, EN), district (GR, EN), serving post office or agency (GR, EN) — [data.gov.cy dataset 1037](https://data.gov.cy/en/dataset/1037)
- Only 857 of the 32,819 rows carry a house-number range (e.g. "1 - 39, 2 - 18" → 3116 and "41 - τ. 20 - τ." → 3117 for the same Limassol street); otherwise one row means a whole street in one community — [download](https://data.gov.cy/en/resource/3104/download/file)
- "Οδηγός Ταχυδρομικού Κώδικα - Post Code Directory": XLSX (3,263,480 bytes, HTTP 200), CC BY 4.0, frequency "Annually", modified 18/09/2024, temporal coverage 01/01/2024 — [data.gov.cy dataset 385](https://data.gov.cy/en/dataset/385)
- "Ταχυδρομικοί Κώδικες ανά Δήμο/Κοινότητα και Επαρχία": postcodes per municipality/community and district plus a mapping to LAU2 codes; CSV 74,463 bytes, CC BY 4.0, modified 16/01/2024 — [data.gov.cy dataset 1134](https://data.gov.cy/en/dataset/1134)
- "ΑΡΙ Κυπριακών Ταχυδρομείων για Ταχυδρομικούς Κώδικες" (Cyprus Post postcode search API): "Για την πρόσβαση στην υπηρεσία απαιτείται εγγραφή" (registration required, requested through a contact form); documentation at `https://documenter.getpostman.com/view/6477303/RztmtUjG?version=latest`; CC BY 4.0; frequency "Continuously"; modified 16/01/2024 — [data.gov.cy dataset 1061](https://data.gov.cy/en/dataset/1061); [API resource](https://data.gov.cy/el/resource/cyprus-postal-codes-api)
- Two older datasets (postcode per street, urban only and rural only) are marked "ΑΝΕΝΕΡΓΟ" (inactive) — [data.gov.cy search](https://data.gov.cy/en/search?s=%CF%84%CE%B1%CF%87%CF%85%CE%B4%CF%81%CE%BF%CE%BC%CE%B9%CE%BA%CE%BF%CE%AF+%CE%BA%CF%8E%CE%B4%CE%B9%CE%BA%CE%B5%CF%82&f%5B0%5D=content_type%3Adataset.dataset)

**HVD status**
- On the national portal the DLS address dataset is tagged "High Value Data / Δεδομένα Υψηλής Αξίας" — [data.gov.cy dataset 543](https://data.gov.cy/en/dataset/543)
- In the EU catalogue the same record has `is_hvd: false`, and Cyprus has no dataset in HVD category "Addresses" nor in "Geospatial" (both counts 0, 2026-11-11) — [data.europa.eu record](https://data.europa.eu/api/hub/search/datasets/585d9407-05d2-4348-a9d6-0d0191d2dcdb); [search API](https://data.europa.eu/api/hub/search/search?q=&filter=dataset&facets=%7B%22country%22%3A%5B%22cy%22%5D%2C%22hvdCategory%22%3A%5B%22c_ac64a52d%22%5D%7D)
- The national HVD page states the rule (free, machine-readable, API and where relevant bulk download) and the legal basis, Law 143(I)/2021 Art. 21, with the harmonisation period ending June 2024 — [data.gov.cy HVD page](https://data.gov.cy/en/high-value-datasets-hvds)

### Inferences
- The DLS set meets the form of an INSPIRE/HVD address publication (open licence, WFS, no fee) but not the substance: 4% coverage, a 2015 reference date, empty house numbers. For house-number geocoding it is not usable; it can serve only as geocoded street names inside the covered area (the layer's extent spans roughly 32.34–34.07°E, 34.64–35.20°N).
- The national "High Value Data" tag is not passed to the EU catalogue as an HVD flag, so Cyprus does not appear to report an addresses HVD in machine-readable DCAT terms.
- The best combination from free data is Cyprus Post's street/postcode table (complete for streets, bilingual, CC BY 4.0) joined to street geometry from another source; house-number points must come from elsewhere (e.g. community-mapped data, covered by another researcher).
- Cyprus Post data is the only source here with an official Greek-to-Latin street-name pairing, which solves the transliteration problem for streets.

### Gaps
- The Cyprus Post API was not tested (needs registration); its rate limits and terms beyond CC BY 4.0 are unknown.
- The newest per-street CSV on the portal is the September 2021 edition; whether the 2024 XLSX directory has the same per-street content was not checked (file downloaded, not parsed).
- No evidence was found of a project to build a national address register; DLS's portal search by address (view only) was not tested.
- Whether data cover the areas not under government control was not examined.

---

## Romania (România)

### Takeaway
Romania has an authoritative register on paper — RENNS, run by the cadastre agency ANCPI with data entered by town halls — but it has never been open bulk data: the metadata said the data "are not commercialised" and are available in a viewer, and the only INSPIRE download feed (last updated 2019) carried an access-restriction notice. Since the cyberattack on ANCPI of 14 July 2026 the whole ANCPI geoportal is offline: on 11 November 2026 `geoportal.ancpi.ro` and `renns.ancpi.ro` do not even resolve in DNS. What is left for free is postal and municipal: a 2016 street-level postcode file from Poșta Română and scattered municipal street lists; no national house-number points.

### Cited Findings

**Register**
- RENNS = Registrul Electronic Național al Nomenclaturilor Stradale (National Electronic Register of Street Nomenclatures), maintained by Agenția Națională de Cadastru și Publicitate Imobiliară (ANCPI); its structure and operation are governed by Government Decision 777/2016 (secondary: search summary of the former INSPIRE Geoportal record) — [INSPIRE Geoportal record](https://inspire-geoportal.ec.europa.eu/srv/api/records/%7B5DCAFDDB-7729-4655-8C5C-845AE8538BFC%7D)
- EU catalogue record "Addresses RENNS" (catalogue `inis`, issued 2017-05-15, contact ANCPI): "The class of spatial objects with point geometry contains the administrative numbers of urban-type localities"; vector data collected "2009–present" from town halls and prefectures via the county cadastre offices and field collection by local councils from 2011 — [data.europa.eu record](https://data.europa.eu/api/hub/search/datasets/-aa3a39d5-b7d6-4297-8cb9-6be9e470a1be-)
- Use restriction in the INSPIRE metadata: the data "nu se comercializează" (are not commercialised) and are available in the RENNS viewing application; public access limited under Article 13(1) of the INSPIRE Directive (secondary: search summary) — [INSPIRE Geoportal record](https://inspire-geoportal.ec.europa.eu/srv/api/records/%7B5DCAFDDB-7729-4655-8C5C-845AE8538BFC%7D)

**Services that existed before July 2026**
- View service (WMS): `https://geoportal.ancpi.ro/inspireview/rest/services/AD/AD_View/MapServer/exts/InspireView/service?SERVICE=WMS&REQUEST=GetCapabilities`, published 2020-01-22 — [data.europa.eu record](https://data.europa.eu/api/hub/search/datasets/-5dcafddb-7729-4655-8c5c-845ae8538bfc-)
- Download service (ATOM): `http://geoportal.ancpi.ro/inspiredownload/rest/directories/arcgisforinspire/AD/AD_Download_MapServer/Main_ATOM_AD.xml` — [data.europa.eu record](https://data.europa.eu/api/hub/search/datasets/-d8d123a0-5f26-40af-bd73-b78ca7609c9c-)
- Archived copy of that feed (snapshot 2026-02-12): title "Serviciu INSPIRE ATOM pentru descarcarea bazei de date a ANCPI, tema Adrese"; one dataset `AD.RENNS` / `RO.ANCPI`; summary "Baza de date in format FGDB ZIP" (file geodatabase zip); CRS EPSG:4258; `updated` 2019-09-12; `rights`: "(a) the confidentiality of the proceedings of public authorities, where such confidentiality is provided for by law" — [Wayback Machine snapshot](http://web.archive.org/web/20260212012623/http://geoportal.ancpi.ro/inspiredownload/rest/directories/arcgisforinspire/AD/AD_Download_MapServer/Main_ATOM_AD.xml)
- The feed's bounding polygon is "23,6866 44,9372 23,7291 44,9611" — a box of only about 0.04° × 0.02° — [Wayback Machine snapshot](http://web.archive.org/web/20260212012623/http://geoportal.ancpi.ro/inspiredownload/rest/directories/arcgisforinspire/AD/AD_Download_MapServer/Main_ATOM_AD.xml)

**State on 11 November 2026 (probed)**
- `geoportal.ancpi.ro` and `renns.ancpi.ro` return NXDOMAIN from three public resolvers (1.1.1.1, 8.8.8.8, 9.9.9.9); `www.ancpi.ro` is up and serves a single notice page — [ancpi.ro](https://www.ancpi.ro/)
- That notice (text dated 20 August 2026) says restart concerns "exclusively" e-Terra and that the other platforms — RTI, MyEterra, Registrul proprietarilor, Titluri de proprietate "și Geoportal" — "vor fi repuse în funcțiune etapizat, după finalizarea verificărilor necesare", with each restart to be announced publicly — [ancpi.ro](https://www.ancpi.ro/)
- Cause: a cyberattack on ANCPI on 14 July 2026 — [Agerpres, 15 July 2026](https://agerpres.ro/2026/07/15/agentia-nationala-de-cadastru---tinta-unui-atac-informatic-datele-sunt-in-siguranta-si-se-lucreaza-l--1576362)
- On 17 August 2026 the Government said e-Terra works and the other ANCPI systems, Geoportal included, were still down, with no restart date — [StartupCafe, 17 August 2026](https://startupcafe.ro/situatia-de-la-cadastru-aplicatia-e-terra-functioneaza-iar-volumul-ridicat-de-solicitari-este-in-curs-de-procesare-celelalte-sisteme-ancpi-sunt-tot-blocate-guvern-105217)
- A ransom note quoted by the press names RENNS among the affected ANCPI systems (attacker's claim, not an official statement; secondary, not opened) — [Forbes România](https://www.forbes.ro/hackerii-au-avut-acces-la-sistemele-ancpi-timp-de-86-de-ore-inainte-de-a-fi-detectati-519051)
- The national INSPIRE portal host `geoportal.gov.ro` resolves in DNS but gave my client no HTTP response on 2026-11-11 — [geoportal.gov.ro](https://geoportal.gov.ro/)

**National open-data portal (probed)**
- data.gov.ro has no RENNS or ANCPI address dataset: search "RENNS" → 0 results; "adrese" → 4 unrelated results — [data.gov.ro search RENNS](https://data.gov.ro/api/3/action/package_search?q=RENNS&rows=12); [search adrese](https://data.gov.ro/api/3/action/package_search?q=adrese&rows=12)
- "Coduri postale Romania", publisher Poșta Română, licence OGL-ROU-1.0: XLS files "infocod" October 2013 (6,238,720 bytes), May 2016, and "Infocod Sept. 2016 cu SIRUTA"; record last modified 2016-09-06; the 2016 download link returns HTTP 200 — [data.gov.ro dataset](https://data.gov.ro/dataset/coduri-postale-romania); [2016 file](https://data.gov.ro/dataset/3eb7dc31-e53e-4c09-b2e2-87c909e68fb6/resource/29a5c89e-0f23-4a42-aa05-765ef04177b6/download/infocod-cu-siruta-mai-2016.xls)
- Per that dataset's description, the 6-digit postcode in force since 1 May 2003 is "detailed down to street level" — [data.gov.ro dataset](https://data.gov.ro/dataset/coduri-postale-romania)
- Poșta Română's current postcode search page is online (HTTP 200) as a look-up tool — [posta-romana.ro](https://www.posta-romana.ro/cauta-cod-postal.html)
- Street lists (not address points): municipal "nomenclator stradal" datasets for Cluj-Napoca (2020), Bucharest Sector 2 (2021), Copșa Mică, Săliștea, Bobicești, Puiești under CC BY 4.0 and Timișoara (2014) under OGL-ROU-1.0; and per-county "Nomenclator strazi judetul …" files from the Ministry of Public Finance (2016, OGL-ROU-1.0) — [data.gov.ro search "nomenclator stradal"](https://data.gov.ro/api/3/action/package_search?q=nomenclator+stradal&rows=12); [search "strazi"](https://data.gov.ro/api/3/action/package_search?q=strazi&rows=12)
- SIRUTA (register of administrative-territorial units, settlement level) from the National Institute of Statistics, CC BY 4.0, latest "SIRUTA_s1 2026" modified 2026-08-11 — [data.gov.ro search SIRUTA](https://data.gov.ro/api/3/action/package_search?q=SIRUTA&rows=12)

**HVD status**
- The three RENNS records in the EU catalogue have `is_hvd: false`; Romania has no dataset in HVD category "Addresses" nor "Geospatial" (counts 0, 2026-11-11) — [data.europa.eu search API](https://data.europa.eu/api/hub/search/search?q=&filter=dataset&facets=%7B%22country%22%3A%5B%22ro%22%5D%2C%22hvdCategory%22%3A%5B%22c_ac64a52d%22%5D%7D)

**Other**
- OpenAddresses has no countrywide Romanian source, only two city sources on an Esri Romania server ("SureData" MapServer layers for Bucharest, and for Otopeni, Sinaia, Voluntari, Chitila), with no licence recorded; that server gave my client no response on 2026-11-11 — [OpenAddresses ro/bucharest.json](https://github.com/openaddresses/openaddresses/blob/master/sources/ro/bucharest.json); [ro/bucharest-metro.json](https://github.com/openaddresses/openaddresses/blob/master/sources/ro/bucharest-metro.json)

### Inferences
- Even before the attack, RENNS was a view-only source in practice: a WMS, a web viewer, a non-commercial statement and a download feed frozen in 2019 whose bounding box covers a few square kilometres — which suggests the downloadable "predefined dataset" was a sample area, not the country. I could not open the file itself to confirm.
- RENNS content was described as administrative numbers in urban-type localities; rural coverage was likely incomplete even inside the register.
- As of November 2026 there is no free national source of Romanian house-number addresses with coordinates from official publishers. The only official, licensed, national file with street-level granularity is the 2016 postcode table, now ten years old.
- Removing the DNS records (rather than showing a maintenance page) and the staged-restart wording mean the return date and the future URL of the geoportal are both uncertain; ANCPI said it moved applications to the government cloud (press headline, secondary) — [Digi24](https://www.digi24.ro/digieconomic/digital/ancpi-muta-aplicatiile-in-cloudul-guvernamental-dupa-atacul-cibernetic-cand-ar-putea-reveni-serviciile-110985)
- Romania shows no addresses HVD; with the register closed and offline this is a plain gap against Regulation 2023/138. I found no Commission document recording it.

### Gaps
- No announcement of the Geoportal or RENNS returning was found after 20 August 2026; the status between then and 11 November rests on my DNS and HTTP probes only.
- The archived dataset feed (`AD_Dataset.xml`) has no Wayback snapshot, so the size, date and extent of the old FGDB download are unknown.
- The exact wording and article letter of the access limitation differ between sources (search summary says Article 13(1)(e); the ATOM feed quotes letter (a)); the original metadata is on servers that are offline.
- Content of the 2016 postcode XLS (columns, row count, whether it has house-number ranges) was not parsed; only the link was checked.
- No newer official postcode file than 2016 was found on data.gov.ro; whether Poșta Română offers one elsewhere is unknown.

---

## Cross-country: HVD "Addresses" status and the end of the INSPIRE Geoportal

### Takeaway
Only Croatia has published addresses as a High-Value Dataset in the "Addresses" sub-category; Greece flags its cadastre street points as a generic geospatial HVD; Cyprus, Romania and Bulgaria show none in the EU catalogue. The EU INSPIRE Geoportal that third parties (including OpenAddresses) link to was shut down on 1 July 2026, so national portals and data.europa.eu are now the places to look.

### Cited Findings
- EU vocabulary: HVD category `c_c3de25e4` = "Addresses", a child of `c_ac64a52d` = "Geospatial" — [data.europa.eu/bna/c_c3de25e4](http://data.europa.eu/bna/c_c3de25e4)
- Datasets in HVD category "Addresses" per country on data.europa.eu (2026-11-11): HR 1 (`adrese-inspire`), GR 0, CY 0, RO 0, BG 0 — [data.europa.eu search API (HR example)](https://data.europa.eu/api/hub/search/search?q=&filter=dataset&facets=%7B%22country%22%3A%5B%22hr%22%5D%2C%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- Datasets in parent HVD category "Geospatial": CY 0, RO 0, BG 0; Greece has entries, among them the Hellenic Cadastre street points — [data.europa.eu search API (GR example)](https://data.europa.eu/api/hub/search/search?q=%CE%BF%CE%B4%CF%8E%CE%BD&filter=dataset&facets=%7B%22country%22%3A%5B%22gr%22%5D%2C%22hvdCategory%22%3A%5B%22c_ac64a52d%22%5D%7D)
- The INSPIRE Geoportal was decommissioned on 1 July 2026; data.europa.eu is now "the single European entry point for geospatial datasets"; datasets stay in their source systems and are linked through metadata (secondary: search summaries of the Commission and Publications Office pages, not opened) — [European Commission INSPIRE Knowledge Base, 1 July 2026](https://knowledge-base.inspire.ec.europa.eu/news-and-publications/news/european-commission-transitioning-inspire-infrastructure-eu-horizontal-services-ensure-long-term-2026-07-01_en); [Publications Office](https://op.europa.eu/en/web/eu-vocabularies/inspire)
- Croatia's NSDI reported the same change and that its metadata is harvested into data.europa.eu (secondary, not opened) — [nipp.hr](https://www.nipp.hr/default.aspx?id=4030)
- Member States must report on their HVDs to the Commission every two years starting February 2025, including links to licences and APIs (secondary, not opened) — [data.europa.eu news](https://data.europa.eu/en/news-events/news/high-value-datasets-what-has-changed-and-what-will-come-next)

### Inferences
- "HVD compliance for addresses" in this group is: Croatia substantially yes (bulk yes, open API no); Greece formally an entry, materially not an address register; Cyprus an open service that is nearly empty; Romania and Bulgaria nothing.
- Counts from the EU catalogue depend on national portals passing the HVD flag in their DCAT export; Cyprus tags its dataset nationally but the flag does not arrive, so a zero there may understate national intent while still being what an EU-level user sees.
- Links of the form `inspire-geoportal.ec.europa.eu/...` in older documentation (for example the `website` field of OpenAddresses' Croatian source) should be treated as dead or redirected.

### Gaps
- I found no Commission infringement notice or published national HVD report naming addresses for any of the five countries; the 2025 Open Data Maturity country factsheets were not opened — [2025 ODM factsheets](https://data.europa.eu/sites/default/files/2025-12/2025_odm_factsheets.pdf)
- The Commission and Publications Office pages on the Geoportal shutdown were not opened directly.
