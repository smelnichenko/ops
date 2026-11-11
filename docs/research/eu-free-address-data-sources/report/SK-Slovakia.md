## Slovakia (SK)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Register adries (Ministry of Interior) | Bulk CSV or WFS, no registration | CC0 | Yes; WFS EPSG:4258, CSV in degrees | Yes | CSV declared quarterly; served file is April 2026 |

**In short.** Use the *Register adries* (Address Register) of the Ministry of Interior, published under CC0 without registration: a national CSV of 162 MB with about 1.74 million addresses, or a public WFS that serves 1,750,730 address points as CSV, GeoJSON or Shapefile. The CSV lags: it is declared quarterly, but the file served on 11 Nov 2026 is named for April 2026 and holds 11,194 fewer addresses than the WFS. Expect decimal commas, about 2% of rows without coordinates and more than half without a street name. Flat-level and entrance-level tables are also published, but they date from March-May 2024.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| "Adresy podľa krajov (csv)" (addresses by region), national file | Ministerstvo vnútra SR (MV SR, Ministry of Interior) | https://data.slovensko.sk/download?id=d22c42f3-82b5-450d-b8fb-4245d50a31ec (dataset page https://data.slovensko.sk/datasety/b27f57f1-7e76-45e0-8968-631f9176b2e9) | Columns `IDENTIFIKATOR;KRAJ;OKRES;OBEC;CAST_OBCE;ULICA;SUPISNE_CISLO;ORIENTACNE_CISLO_CELE;PSC;ADRBOD_X;ADRBOD_Y`: region, district, municipality, municipality part, street, registration number, orientation number, postcode, longitude, latitude. 1,739,536 rows, 35,190 of them without coordinates (OpenAddresses' processing record of 30 Oct 2026, not recounted). The dataset also has one CSV per region (eight) | Anonymous download, 162,404,526 bytes | CC0 | Declared quarterly; dataset modified 2026-08-21; file served as `Adresy podľa krajov UTF8_04_2026.csv` | confirmed |
| Flat and entrance tables ("Byty - konsolidované dáta", "Vchody - konsolidované dáta") | MV SR | Child datasets of the series "Register bytov" and "Register vchodov" in the national catalogue (query endpoint https://data.slovensko.sk/api/sparql); full download URLs not recorded | Flats CSV, 48,614,084 bytes, columns include `unitNumber`, `floor`, `buildingNumberIdentifier`. Entrances CSV, 1,097,609,571 bytes. Also an initial flats file of 21.5.2024 (`DI_BBP_09_Byt_20240521.zip`, 5,689,821 bytes). The same pattern exists for buildings, streets, municipalities, districts, regions and municipality parts | Anonymous download | Not recorded | Catalogue dates them March-May 2024 | corrected |
| Change batches "Register adries - Zmenové dávky od 27.5.2024 do 31.01.2025" | MV SR | https://data.slovensko.sk/datasety/de3dd18f-9124-4acb-ae00-705555332256 | 87 XML change files. A second, generic series holds an initial batch of 6.4.2018 and numbered batches from March 2024 | Anonymous download | Not recorded | Declared weekly; modified 2025-02-04; nothing newer found | confirmed |
| Municipal address datasets (Prešov, Vranov nad Topľou) | Municipalities, in the national catalogue | Catalogue endpoint https://data.slovensko.sk/api/sparql ; dataset URLs not recorded | "Register adries a stavieb v meste Prešov (k aktuálnemu dátumu)"; "Register adries v meste Vranov nad Topľou" | Not tested | Not recorded | Vranov nad Topľou record modified 2026-07-22 | confirmed (titles only) |
| Postcode file ("Poštové smerovacie čísla") | Slovenská pošta | http://www.posta.sk/subory/322/psc-obci-a-ulic.zip , which redirects to https://www.posta.sk/files/6811e10125b182cd7cd9e3a9/postove-smerovacie-cisla-na-stiahnutie.zip | `PSC-2026-10-29.zip`, 731,703 bytes: `OBCE.xlsx` (municipalities), `ULICE.xlsx` (streets), `POBoxy.xlsx` (PO boxes). The spreadsheets were not opened | Anonymous download | CC0 per the national catalogue record; no statement by Slovenská pošta itself | Files dated 2026-10-29 | corrected |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Slovakia | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/sk/countrywide.json) | The national CSV above, read from its live URL | Free download, needs a logged-in account | CC0 1.0, attribution not required | Processed 2026-10-30 (https://batch.openaddresses.io/api/job/946657) | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 1,704,346 Slovak addresses in release 2026-10-21.0 (publisher's figure) | GeoParquet, no account | Ministry of Interior, CC0 1.0 | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **Address register WFS, no key:** https://rageo.minv.sk/geoserver/ra/wfs (capabilities: https://rageo.minv.sk/geoserver/ra/wfs?service=WFS&version=2.0.0&request=GetCapabilities). Title "Mapová služba registra adries WFS", provider MV SR, fees NONE, access constraints NONE. Feature type `ra:address` ("Adresne body"), default CRS EPSG:4258, output as GML, GeoJSON, CSV, KML or zipped Shapefile. The default count limit is 1,000,000 features per request; the layer held 1,750,730 on 11 Nov 2026. A second feature type, `ra:mv_address_ui`, exists.
- **Fields returned by the WFS:** `identifier`, `uri_identifier` (`https://data.gov.sk/id/physical-address/<id>`), `fulladdress`, `streetname`, `street_id`, `postalcode`, `orientationnumber`, `propertyregistrationnumber`, municipality-part, LAU2, LAU1 and NUTS3 names and codes, `validfrom`, point geometry.
- **INSPIRE Addresses WFS:** https://rageo.minv.sk/geoserver/ad/wfs . Feature types `ad:Address`, `ad:AddressAreaName`, `ad:AdminUnitName`, `ad:PostalDescriptor`, `ad:ThoroughfareName`; fees NONE, access constraints NONE.
- **WMS:** on the same host at `/ra/wms` and `/ad/wms`.
- **Catalogue SPARQL endpoint:** https://data.slovensko.sk/api/sparql , anonymous. It is the practical way to read dataset metadata, because the dataset landing pages return only a JavaScript shell.
- **Postcode lookup page:** https://www.posta.sk/psc (interactive; the download link is not in the page's static HTML).
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- The CSV is behind the WFS: 1,739,536 rows against 1,750,730 address points on the same day. The WFS count was identical about ten hours apart, so how often the WFS itself is refreshed is not known.
- The CSV is semicolon-separated UTF-8 with decimal commas, for example `4320536;Banskobystrický;Banská Bystrica;Badín;;Banská;150;2;97632;19,121502;48,6661543`. Identifiers are not always numeric (`432057A` occurs).
- No coordinate reference system is stated in the CSV or its catalogue record. The values are degrees; the WFS declares EPSG:4258.
- Per OpenAddresses' processing record: 973,318 rows (56%) have no street name, 401 have no postcode, 35,190 have no coordinates. Many municipalities have no named streets, so those addresses carry only the registration number (*súpisné číslo*).
- `data.slovensko.sk` ignores HTTP `Range` requests and streams the whole file.
- The old portal `data.gov.sk` redirects (302) to `data.slovensko.sk`.
- The per-table registers (buildings, entrances, streets, flats and others) show no files at the series level; the files hang on child datasets of each series.
- No change batch later than 31 January 2025 was found in a title search of the catalogue.
- Legal basis: Act 125/2015 Coll. (https://static.slov-lex.sk/static/SK/ZZ/2015/125/20240401.html). The register holds a postcode for every address and the position of every address point. The Act says data published on the ministry's website are of informative character.
- High-value datasets: the national CSV dataset is typed as a high-value dataset under Regulation (EU) 2023/138, category "Addresses". data.europa.eu lists 315 Slovak high-value datasets, nine of them in "Addresses", all from MV SR: addresses by region, "INSPIRE - Adresy" (modified 2024-12-05), the change batches and six road-section sets.
- The ministry's register page https://www.minv.sk/?register-adries describes the register but says nothing about open data.
- An older OpenStreetMap import page (https://wiki.openstreetmap.org/wiki/Sk:MinvSKAddress , last edited 19 March 2021) reports about 9,000 points with latitude and longitude swapped and some municipalities without address points at that time. It also states that the ministry's data are under CC0.

### Not free or not available

- **Current flat-level data:** only the March-May 2024 tables were found.
- **Change files after 31 January 2025:** none found in the national catalogue.
- **Statutory data supply:** the ministry provides register extracts on request; automated supply requires an agreement with the ministry (Act 125/2015, § 10).
- **ZBGIS (national topographic database, ÚGKK):** ordering data requires an order form (https://www.skgeodesy.sk/geoportal-en/zbgis/order/).

### Could not be verified

- The CSV row counts were not recounted: they come from OpenAddresses' processing record for the same URL. The figure of 973,158 rows without an orientation number has no source that could be checked.
- A licence statement from Slovenská pošta itself for the postcode file: the CC0 comes from a catalogue record made by the transport ministry in 2015-2020.
- Whether ZBGIS address or building layers are in ÚGKK's free download: the site shows "Download" entries, but they were not examined.
- Municipal address datasets named for Banská Bystrica, Trebišov, Trnava, Levice, Svidník and Myjava: several records titled "Register adries v meste" exist, but their publishers were not resolved.
- Licence of the flat, entrance and change-batch files: not recorded.
- Usage limits for the `rageo.minv.sk` services: none were found beyond "Fees NONE / AccessConstraints NONE", and the search was not repeated.
