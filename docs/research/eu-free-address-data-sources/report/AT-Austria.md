## Austria (AT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | BEV Adressregister, "Adresse Relationale Tabellen - Stichtagsdaten" | Bulk zip of CSV tables, no registration | CC BY 4.0 with a dated credit | Yes; MGI Gauss-Krüger, EPSG:31254, 31255 or 31256 per row | Yes | Twice a year (1 April, 1 October) |

**In short.** Use the BEV Adressregister (address register) extract "Adresse Relationale Tabellen - Stichtagsdaten" (address relational tables, reference-date data): one nationwide zip, free, no login, CC BY 4.0, with coordinates and postcodes. It is relational, so street and municipality names must be joined from separate tables, and each row names one of three Gauss-Krüger zones in its EPSG column; the INSPIRE edition of the same data in EPSG:3035 avoids the zones. The main limit is age: the extract is made twice a year and published two weeks later, so the free data can be about six and a half months old, and anything fresher is paid. The newest extract lives only at an undated URL whose content is replaced in place.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Adresse Relationale Tabellen - Stichtagsdaten, current extract | BEV | File: <https://data.bev.gv.at/download/Adressregister/Adresse_Relationale_Tabellen_Stichtagsdaten.zip>; catalogue record: <https://data.bev.gv.at/geonetwork/srv/api/records/040eebd0-d462-4eb0-b2a6-9ed778b83ac8> | Eight CSV tables for all of Austria: ADRESSE.csv (addresses with postcode and coordinates; 2,529,222 rows, researcher's count), GEBAEUDE.csv (buildings), ADRESSE_GST.csv, GEBAEUDE_FUNKTION.csv, STRASSE.csv (streets, 138,112 rows), ORTSCHAFT.csv (17,022), ZAEHLSPRENGEL.csv (8,843), GEMEINDE.csv (municipalities, 2,092); plus the interface description V1.5 | Direct zip, 118.5 MB, no login | CC BY 4.0; credit "© Österreichisches Adressregister, Stichtagsdaten vom TT.MM.JJJJ" | Reference date 01.10.2026, published 16 Oct 2026; twice a year | confirmed (the four large tables were not recounted) |
| Same product, previous extract | BEV | <https://data.bev.gv.at/download/Adressregister/Archiv_Adressregister/Adresse_Relationale_Tabellen_Stichtagsdaten_20260401.zip>; catalogue record: <https://data.bev.gv.at/geonetwork/srv/api/records/69980a2b-a223-40cf-897f-b9c24ec4a99e> | The extract of 01.04.2026 | Direct zip, 98.2 MB, no login | CC BY 4.0 | Archive file per past extract | confirmed |
| Adressregister INSPIRE, reference date 01.10.2026 | BEV | GeoPackage: <https://data.bev.gv.at/download/Adressregister/AT-INSPIRE_AD_Address_20261001.gpkg>; CSV: <https://data.bev.gv.at/download/Adressregister/AT-INSPIRE_AD_Address_CSV_20261001.zip>; catalogue record: <https://data.bev.gv.at/geonetwork/srv/api/records/bed08735-6342-49a2-8eae-6247363187c3> | The same register in the INSPIRE address model, EPSG:3035 | Direct files, GeoPackage 1.66 GB, CSV zip 218 MB | CC BY 4.0 | Same reference date as the relational extract | confirmed |
| Vienna address points (layer ogdwien:ADRESSENOGD, catalogue title "Adressen Standorte Wien") | Stadt Wien | <https://data.wien.gv.at/daten/geo?service=WFS&request=GetFeature&version=1.1.0&typeName=ogdwien:ADRESSENOGD&srsName=EPSG:4326&outputFormat=csv&maxFeatures=3> | Address points for Vienna with postcode and point geometry | WFS that returns CSV, no key | CC BY 4.0 (City of Vienna's data.gv.at record) | not stated | confirmed (licence corrected) |
| Tirol addresses | Tirol (regional), as recorded by OpenAddresses | <https://github.com/openaddresses/openaddresses/blob/master/sources/at/tirol.json> | Regional address source for Tirol | Through OpenAddresses; the publisher's own page was not read | CC BY, with the addition that the licensor has to be informed when the data is used; OpenAddresses gives the version as 3.0 AT in one field and 4.0 AT in another | not stated | unverified at the publisher |
| Postleitzahlen (postcode directory) | RTR | <https://data.rtr.at/api/v1/tables/plz.json>; field description: <https://www2.rtr.at/de/inf/odPLZ/Beschreibung_Postleitzahlen.pdf> | 2,731 postcode rows with fields plz, ort, bezirk, bundesland, gueltigab, gueltigbis, plztyp, internextern, adressierbar, postfach | REST endpoint, JSON, no key | Free official work under § 7 UrhG, no usage restriction, per RTR; the data.gv.at record labels it CC BY 4.0 | Monthly; version published 2026-11-04 | corrected (licence) |
| Gemeinde-, Ortschafts-, Straßen- und PLZ-Verzeichnis (directory of municipalities, localities, streets and postcodes) | Statistik Austria | <https://www.statistik.at/verzeichnis/strassenliste/gemplzstr.csv>; zipped: <https://www.statistik.at/verzeichnis/strassenliste/gemplzstr.zip> | Streets with municipality, locality, postcode and delivery place; no house numbers, no coordinates | Direct CSV, 13.5 MB, semicolon, UTF-8 without BOM | not found | File created 05.11.2026 | corrected (encoding); licence unverified |
| GISCO Address API | Eurostat | <https://gisco-services.ec.europa.eu/addressapi> | Address lookup for Austria; its data credit reads "Stichtagsdaten vom 05.05.2022" | No key; lookup only, 1,000-row cap, no bulk download | None stated | Snapshot credited 2022 | confirmed |
| OpenAddresses | OpenAddresses | <https://batch.openaddresses.io> | A cached copy of the BEV extract of 01.04.2026, plus Vienna and Tirol sources | Free download, needs a logged-in account | CC BY 4.0 for the BEV data | Run of 2026-10-30 on the April 2026 extract | confirmed |
| Overture Maps addresses | Overture Maps Foundation | <https://docs.overturemaps.org/guides/addresses/> | 2,523,030 Austrian addresses (publisher's figure), source Austrian Address Register | GeoParquet, no account | CC BY 4.0 | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | <https://download.geonames.org/export/zip/> | Postcode centroids only, no addresses | Bulk file | CC BY 4.0 | not stated | confirmed |

### Free APIs and services

- BEV INSPIRE view service (WMS), <https://data.bev.gv.at/geoserver/INSdataAD/wms>: map layers of the address and building geometries; answers without a key.
- BEV ATOM download feed, <https://data.bev.gv.at/geonetwork/srv/atom/describe/service?uuid=68cb9fac-e9ca-4366-b41f-79195fd31360>: the INSPIRE download service ("AT.BEV ATOM Downloaddienst"); answers without a key.
- RTR postcode endpoint, <https://data.rtr.at/api/v1/tables/plz.json>: the whole postcode directory in one JSON response, no key.
- Vienna address WFS, <https://data.wien.gv.at/daten/geo?service=WFS&request=GetFeature&version=1.1.0&typeName=ogdwien:ADRESSENOGD&srsName=EPSG:4326&outputFormat=csv&maxFeatures=3>: no key, CSV output, Vienna only.
- Vienna address geocoder ("Adressservice Wien"), <https://data.wien.gv.at/daten/OGDAddressService.svc/GetAddressInfo?Address=Stephansplatz%201&crs=EPSG:4326>: official, no key, CC BY 4.0, address search with geocoding and reverse geocoding, Vienna only.
- OpenPLZ API, <https://openplzapi.org/>: a community street and postcode directory that names Austria as covered; no house numbers, no key, ODbL. Its Austrian endpoints were not called.
- GISCO Address API (Eurostat), <https://gisco-services.ec.europa.eu/addressapi>: covers Austria, no key, lookup only with a 1,000-row cap, no licence stated.
- Two community tools build on the BEV file and must be self-hosted: a reverse geocoder with conversion script (<https://www.github.com/thomaskonrad/bev-reverse-geocoder>, last change 2020) and a search API (<https://www.github.com/the42/bevaddressapi>, last change 2018). Both are unmaintained.

### Caveats and recent changes

- The newest extract exists only at the undated URL. The dated archive name for 20261001 returns 404; the archive holds the 20260401 file. A pipeline must expect the undated file to change in place twice a year.
- Extracts are made at the start of the second and fourth quarter and offered 14 days later. The current one has the reference date 01.10.2026 and was published on 16 Oct 2026.
- File format: semicolon-separated CSV, UTF-8 with BOM, text fields quoted and numbers not. The ADRESSE columns are `ADRCD;GKZ;OKZ;PLZ;SKZ;ZAEHLSPRENGEL;HAUSNRTEXT;HAUSNRZAHL1;HAUSNRBUCHSTABE1;HAUSNRVERBINDUNG1;HAUSNRZAHL2;HAUSNRBUCHSTABE2;HAUSNRBEREICH;HNR_ADR_ZUSAMMEN;GNRADRESSE;HOFNAME;RW;HW;EPSG;QUELLADRESSE;BESTIMMUNGSART`. Street names are in STRASSE.csv (join on SKZ) and municipality names in GEMEINDE.csv (join on GKZ).
- Coordinates are in the RW and HW columns in MGI Gauss-Krüger; the EPSG column names the zone per row (31254, 31255 or 31256). Researcher's count for the 01.10.2026 extract: 1,292,757 rows in 31256, 998,255 in 31255 and 238,210 in 31254, and no address row without coordinates or postcode.
- BEV warns that the coordinate fields of an address can be empty ("NULL", not "0"). An import must handle that even though none was seen in the first 7,178 rows.
- Buildings: each building at an address has a 3-digit subcode; the 7-digit address code plus the subcode form the address number. GEBAEUDE.csv carries its own coordinates per building.
- The geocoding accuracy stated by BEV is one metre.
- The licence text files inside the 01.10.2026 zip (dated 1 June 2026) still name the reference date 01.04.2026. The file Aktualitaetsstand.txt in the same zip gives 01.10.2026. The licence asks for a credit with the reference date of the data ("Stichtagsdaten vom TT.MM.JJJJ").
- Municipalities maintain the addresses continuously through "Adress-GWR-online", the shared reporting channel of the address register and the buildings and dwellings register. The postcodes in the register are taken over quarterly (01.03., 01.06., 01.09., 01.12.) from postcode areas supplied by Österreichische Post AG.
- BEV's page for free products, <https://www.bev.gv.at/Services/Downloads/Produktbezogene-Downloads/Unentgeltliche-Produkte/Adressregister.html>, is stale (it still refers to April 2022). The catalogue records are the reliable place to find the current file. Both the October and the April record contain one link with a malformed "httpss://" scheme.
- The data.gv.at record "Adressen Relationale Tabellen - Stichtagsdaten" links archive files only up to 2023.
- The Statistik Austria street list is UTF-8, not Latin-1.
- OpenAddresses and GISCO serve older copies: OpenAddresses the extract of 01.04.2026, GISCO a state credited 05.05.2022.
- High-value dataset (HVD) marking is inconsistent between portals: data.gv.at shows `is_hvd: false` on the BEV address records, while data.europa.eu lists BEV address records under the HVD category "Addresses".

### Not free or not available

- Data fresher than the half-yearly extracts is paid. BEV sells "Adresse" geocoded at 1 m for EUR 0.045 per object. Update contracts cost 120% of the annual standard fee for monthly delivery, 60% for quarterly, 55% for half-yearly, 50% for yearly and 45% for two-yearly, with a minimum term of three years plus transfer costs per delivery (<https://www.bev.gv.at/Services/Produkte/Adressregister/Oesterreichisches-Adressregister.html>).
- BEV Adresssuch-Service (address search service, updated daily, returns coordinates): not free. It needs registration and a security certificate and costs EUR 10 per month for internal use and EUR 480 per year per application for external use (<https://www.bev.gv.at/Services/Geoinformationsdienste/Services/BEV-Adresssuch-Service.html>).
- Free nationwide official geocoding API: none found. Searched: data.gv.at for "Geocoder" (no hits) and "Adresssuche" (two hits, both from the City of Vienna). The only free official geocoder found covers Vienna.

### Could not be verified

- Row counts of the four large tables (ADRESSE.csv 2,529,222; GEBAEUDE.csv 2,538,894; ADRESSE_GST.csv 3,161,178; GEBAEUDE_FUNKTION.csv 822,118): researcher's counts, not recounted, because that needs the full 118 MB download. The file sizes are consistent with them.
- The per-zone totals and the statement that no address row lacks coordinates or a postcode: seen only in a sample of the first 7,178 rows, not over the whole file.
- Licence of the Statistik Austria street list: no catalogue record was found and the file carries no licence line.
- The endpoint kataster.bev.gv.at/api/all4map did not respond within 30 seconds; whether it is a free geocoder and on what terms is unknown. The address search of basemap.at and geoland.at was not checked.
- A postcode download page of Österreichische Post was not found; the RTR table is the confirmed free postcode source.
- An official statement on whether Austria's address data complies with the HVD regulation was not found.
- Tirol's own terms page was not read; the notification condition and the licence version rest on what OpenAddresses records.
- Rate limits for the services above: none was found published.
