## Greece (GR)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | Hellenic Cadastre declared street points: 2023 snapshot, no municipality, no postcode | Bulk shapefile zip, no registration | CC BY 4.0; the Cadastre's own terms unread | Yes, Greek Grid GGRS87 (EPSG:2100) | No | None; "as needed", file dated 2023-11 |

**In short.** No national address register was found. The best free source is one national point file from the Ελληνικό Κτηματολόγιο (Hellenic Cadastre): 2,292,989 points with a street name and a house number as property owners declared them, CC BY 4.0, no login. The file has only those two fields, so every point must be joined to municipality polygons before it is an address, and no open file supplies the postcode. OpenAddresses already publishes that join.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Στοιχεία οδών δηλώσεων Ελληνικού Κτηματολογίου ("Street names and numbers according to cadastral surveying declarations") | Ελληνικό Κτηματολόγιο (Hellenic Cadastre), a public-law body under the Ministry of Digital Governance | Dataset page: https://data.gov.gr/dataset/stoicheia-odon-diloseon-ellinikoy-ktimatologioy ; direct download: https://data.gov.gr/dataset/16068541-970c-4d1a-8047-b95fd4d261ba/resource/946e2a6a-8ab8-4c62-89e3-e14ecd9868a1/download/ogp_hc_regstreets_egsa87.zip ; record as JSON: https://data.gov.gr/api/3/action/package_show?id=stoicheia-odon-diloseon-ellinikoy-ktimatologioy | Shapefile `HC_RegStreets_EGSA87`: 2,292,989 points (count read from the file header), two fields: `ADDRESS` (declared street name) and `NUM` (declared number). UTF-8. No municipality, postcode or identifier | Zip of 64,396,519 bytes, no login. The link redirects to a time-limited signed link on cloud storage. The dbf is 607 MB unpacked | CC BY 4.0, set on the two resources; the resource also points to the Cadastre's terms at https://www.ktimatologio.gr/oroi-xrisis , which could not be read | Shapefile parts dated 2023-11-20; portal record created 2026-02-03, modified 2026-05-11; stated frequency "as needed" | confirmed |
| Street numbering of the Municipality of Kalamaria ("Αρίθμηση οδών του Δήμου Καλαμαριάς") | Municipality of Kalamaria, on data.gov.gr | OpenAddresses source file: https://github.com/openaddresses/openaddresses/blob/master/sources/gr/b/municipality_of_kalamaria.json | Shapefile with street (`Odos`) and number (`Arithmos`); one municipality | Listed on data.gov.gr; file not opened | Not stated; OpenAddresses marks it "presumed" | Not known | confirmed (listing only) |
| Other municipal address layers: Ilion, Papagou-Cholargou, Chalandri, Egaleo ("Διευθύνσεις", addresses), Piraeus ("Ταχυδρομικές Διευθύνσεις", postal addresses), Keratsini-Drapetsona ("Διευθύνσεις Κτηρίων", building addresses), Agrinio ("Αρίθμηση Διευθύνσεων ΚΑΕΚ", address numbering by cadastral code) | The municipalities, on data.gov.gr | Catalogue search: https://data.europa.eu/api/hub/search/search?q=%CE%B4%CE%B9%CE%B5%CF%85%CE%B8%CF%8D%CE%BD%CF%83%CE%B5%CE%B9%CF%82&filter=dataset&facets=%7B%22country%22%3A%5B%22gr%22%5D%7D | Municipal address layers. More exist under "Αρίθμηση Οδών" (street numbering) for Agia Paraskevi, Piraeus, Ilion, Chania, for Vari-Voula-Vouliagmeni, and Thessaloniki's "Ενδεικτική Αρίθμηση" (indicative numbering) | Each record lists CSV, GeoJSON, KML, SHAPE-ZIP and WMS; files not opened | Not checked | Not checked | confirmed (listing only) |
| Αναζήτηση Ταχυδρομικών Κωδικών & Διευθύνσεων (postcode and address search) | ΕΛΤΑ (Hellenic Post) | https://postalcodes.elta.gr/ | Postcode look-up | Web search form behind Google reCAPTCHA; no file download | "Copyright © Ελληνικά Ταχυδρομεία (ΕΛΤΑ)" | Not stated | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Greece | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Greek countrywide source | OpenAddresses | Source file: https://github.com/openaddresses/openaddresses/blob/master/sources/gr/countrywide.json ; method: https://github.com/openaddresses/openaddresses/blob/master/scripts/gr/README.md ; downloads: https://batch.openaddresses.io | The Cadastre points joined to the 326 "Kallikratis" municipality polygons of the Ministry of Environment and Energy. Columns `STREET, NUMBER, CITY, MUN_CODE, LON, LAT`; about 2.29 million rows (publisher's figure) | Free download; needs a logged-in account | CC BY 4.0 | Source added 2026-09-29 in a single commit | confirmed |

### Free APIs and services

- None for the Cadastre street file. Its portal record lists only the shapefile zip and a "Download All" zip (60,775,528 bytes); no API and no WFS.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.
- The municipal address layers on data.gov.gr list a WMS each, next to file downloads. None was called.
- ELTA's postcode search at https://postalcodes.elta.gr/ is a web form behind reCAPTCHA, not an API.

### Caveats and recent changes

- The Cadastre file is not an address register. It holds what owners declared when the National Cadastre was compiled. It has no municipality, no settlement, no postcode and no identifier.
- The data is older than the portal record suggests. The record dates from 2026-02-03, the shapefile parts from 2023-11-20, the embedded metadata from 2025-04-11.
- Coverage by region was not measured. The file's bounding box spans the whole country.
- House number: in the first 400,000 records `NUM` is filled in 344,555 (86.1%). About 1% of those 400,000 (3,971) carry a number of 8 or more digits, such as "0165493431". OpenAddresses reports the same defect ("anomalously long numeric strings") and reads it as another identifier leaked into the field. Filter these out.
- Street names are in Greek capitals, often abbreviated ("ΕΘΝ.ΑΝΤΙΣΤΑΣΗΣ", "ΤΡΙΚΟΥΠΗ Χ."). There is no Latin transliteration.
- Coordinate system: the `.prj` names Greek Grid on GGRS 1987 (ΕΓΣΑ87) and carries no EPSG number. That system is EPSG:2100.
- The portal's link checker marks the shapefile resource "broken: 401 UNAUTHORIZED". The mark dates from 2026-02-03, the day of publication, and was not re-run. The download worked on 2026-11-11.
- Licence: CC BY 4.0 sits on the resources; the dataset-level licence field is empty. The embedded metadata refers to the Cadastre's terms of use and also says "no limitations on public access". The data.gov.gr terms (https://data.gov.gr/en/pages/terms-of-use , text in Greek) give free access without registration, fee or justification, and allow reuse for any lawful purpose, including commercial use.
- The file is flagged as an EU High-Value Dataset under the top category "Geospatial", not under "Addresses". data.europa.eu lists no Greek dataset under HVD "Addresses" (count 0 on 2026-11-11).
- Background: a Eurostat document on the 2011 census says there was no registry of buildings or addresses (https://ec.europa.eu/eurostat/statistics-explained/SEPDF/cache/75998.pdf). A 2020 EU factsheet says only one location register, cadastral parcels, had been implemented (https://interoperable-europe.ec.europa.eu/collection/elise-european-location-interoperability-solutions-e-government/solution/lifo-location-interoperability-framework-observatory/document/lifo-2020-greece-country-factsheet).
- A third-party article of 2018 says ELTA, as universal service provider, processes and manages the country's postcodes (https://www.odigostoupoliti.eu/taxydromikoi-kodikes-epexergasia-diaxeirisi-axiopoiisi/). The ministerial decision itself was not read.

### Not free or not available

- National address register: none found. Searched: data.gov.gr for "διευθύνσεις" (2,430 hits) and "αρίθμηση οδών" (8 hits), which list only municipal layers and the Cadastre file; data.europa.eu for Greek "INSPIRE Addresses"; one web search in Greek for a national address register or a project to build one. Not searched: geodata.gov.gr (connection timed out) and ELSTAT, the statistics office.
- INSPIRE Addresses dataset: none found in the same searches.
- Open postcode file: none found. ELTA offers only the look-up form. OpenAddresses' maintainers report "no open national postal-code dataset" after checking GeoNames, DataHub and the Greek and EU catalogues; no further search for one was made. GeoNames (https://download.geonames.org/export/zip/) has no postcode file for Greece.
- Overture Maps addresses (release 2026-10-21.0): no Greek data.

### Could not be verified

- The Hellenic Cadastre's own terms of use, https://www.ktimatologio.gr/oroi-xrisis , and its open-data portal, https://data.ktimatologio.gr/ : both return HTTP 403. The CC BY 4.0 licence on data.gov.gr is confirmed; whether the Cadastre's terms add conditions is not known.
- Whether INSPIRE data from the Cadastre needs an application: the gov.gr page said to state this, https://www.gov.gr/en/org/ktimanet/ktematographese/geopule-geokhorikon-dedomenon-inspire-ellenikou-ktematologiou , returns HTTP 403.
- Which regions are thin or missing in the Cadastre file: not measured.
- Content, licence and age of the municipal address layers: the files were not opened.
