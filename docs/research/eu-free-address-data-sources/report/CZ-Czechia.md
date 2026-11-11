## Czechia (CZ)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | RÚIAN address-point CSV (ČÚZK) | Bulk CSV zip, no registration | CC BY 4.0 | Yes, S-JTSK (EPSG:5513) | Yes | Monthly; change files daily |

**In short.** Use the national address-point CSV of RÚIAN (*Registr územní identifikace, adres a nemovitostí*, Registry of Territorial Identification, Addresses and Real Estate) from the cadastral office ČÚZK: one 63 MB zip a month, no login, CC BY 4.0, every address with postcode and coordinates. The file name carries the date of the last day of the previous month, so the URL changes monthly; the ATOM feed gives the current one. Most likely to trip an import: the CSV is Windows-1250, not UTF-8, and its coordinates are positive S-JTSK Y/X values (labelled EPSG:5513), while ČÚZK's ArcGIS services return negative values in EPSG:5514. ČÚZK's human download page is behind a bot check, so automate against the file URL or the feed.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| RÚIAN address points, national CSV | Český úřad zeměměřický a katastrální (ČÚZK) | https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_OB_ADR_csv.zip | 6,258 CSV files, one per municipality, 354.7 MB uncompressed. 19 columns: address-point code, municipality, city district, Prague district, municipality part, street, building type (č.p. / č.ev.), house number, orientation number and letter, postcode (PSČ), Y, X, valid-from date. 3,023,585 rows at 31 Oct 2026 (researcher's count, not recounted) | Anonymous download, 63,371,330 bytes | CC BY 4.0 (dataset's metadata record) | Monthly; file last modified 1 Nov 2026 | confirmed |
| ATOM feed for that CSV | ČÚZK | https://atom.cuzk.gov.cz/RUIAN-CSV-ADR-ST/RUIAN-CSV-ADR-ST.xml | Feed entry for the one national file; describes the service as public and free of charge | Anonymous | Feed says "žádné podmínky neplatí" (no conditions apply) | Feed updated 2026-11-01 | confirmed |
| Address hierarchy file | ČÚZK | https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_strukt_ADR.csv.zip | Seven CSV files linking each address point to street, municipality part, municipality, district, region and other units. Codes only: no names, coordinates or postcodes | Anonymous download, 34,233,458 bytes | Not recorded for this file | File last modified 1 Nov 2026 | confirmed |
| Full register in the VFR exchange format (GML 3.2) | ČÚZK | https://services.cuzk.gov.cz/vfr/ (monthly directories `https://services.cuzk.gov.cz/vfr/<YYYYMM>/`); request form at https://vdp.cuzk.gov.cz/vdp/ruian/vymennyformat | All RÚIAN elements: addresses, buildings, parcels, streets, boundaries. Each monthly directory has 6,258 per-municipality files and state files, for example `20260903_ST_UADS.xml.zip` (addresses, 87.0 MB) and `20260930_ST_UKSH.xml.zip` (34.1 MB). Monthly state files go back to August 2015 | Anonymous download; the form also offers increments since a date | CC BY 4.0 (ČÚZK conditions for open spatial data) | Monthly state files; newest directory 202609 on 11 Nov 2026 | corrected |
| INSPIRE theme Addresses (AD) | ČÚZK | ATOM https://atom.cuzk.gov.cz/AD/AD.xml ; WFS https://services.cuzk.gov.cz/wfs/inspire-AD-wfs.asp | Addresses in the INSPIRE model. The only Czech dataset in the high-value category "Addresses" on data.europa.eu | Listed as public and free; the two endpoints were not requested | Not recorded | Catalogue record says files are created daily | confirmed (catalogue record only) |
| Postcode lists ("zákaznické výstupy", customer outputs) | Česká pošta | Page https://www.ceskaposta.cz/ke-stazeni/zakaznicke-vystupy ; files https://www.ceskaposta.cz/documents/d/guest/db_pcobc-zip?download=true and https://www.ceskaposta.cz/documents/d/guest/csv_psc_a-zip?download=true ; third file `csv_cobce_psc-zip` linked from the page | `zv_pcobc.csv`: 16,152 rows, municipality part to postcode, delivering post office and district. `zv_psc_adr.csv`: 20,135 rows, postcode and type. `zv_cobce_psc.csv`: 16,205 rows, with RÚIAN codes of municipality part and municipality. No streets, house numbers or coordinates | Anonymous download, zipped CSV | None stated | Monthly, first working day; files dated 1 Nov 2026 | confirmed |
| Register of census districts and buildings (RSO) | Český statistický úřad (ČSÚ) | https://csu.gov.cz/rso/registr_scitacich_obvodu | Page exists; content and downloads not examined | Not examined | Not recorded | Not recorded | confirmed (page exists only) |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Czechia | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/cz/countrywide.json) | RÚIAN address points, countrywide, from a copy cached by OpenAddresses; the source page it names is the export of 31 Aug 2024 | Free download, needs a logged-in account | CC-BY 4.0, attribution "ČÚZK" | Processed 2026-10-30 from the cached copy | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 3,021,471 Czech addresses in release 2026-10-21.0 (publisher's figure) | GeoParquet, no account | ČÚZK, CC BY 4.0 | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **ArcGIS REST service over RÚIAN, no key:** https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/Vyhledavaci_sluzba_nad_daty_RUIAN/MapServer . Layers include 1 `AdresniMisto` (address points), 2 and 3 building objects, 4 `Ulice` (streets), 5 `Parcela` (parcels). Capabilities "Map,Query,Data", `maxRecordCount` 1,000,000, spatial reference wkid 102067 (EPSG:5514). The address layer counted 3,024,015 points on 11 Nov 2026.
- **Geocoder on the same service, no key:** `.../MapServer/exts/GeocodeSOE/findAddressCandidates`, for example https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/Vyhledavaci_sluzba_nad_daty_RUIAN/MapServer/exts/GeocodeSOE/findAddressCandidates?SingleLine=Pod+s%C3%ADdli%C5%A1t%C4%9Bm+1800%2F9+Praha&f=json . The test returned one candidate with score 100, postcode and coordinates x -739810.37, y -1039209.69.
- **WMS:** the same MapServer lists a `WMSServer` extension.
- **INSPIRE Addresses WFS:** https://services.cuzk.gov.cz/wfs/inspire-AD-wfs.asp , listed in the catalogue as public and free; not requested.
- **Map-based file picker:** https://ags.cuzk.gov.cz/geoprohlizec/?atom=ruian , linked from the CSV's metadata record; not opened.
- **Address verification form:** the public access application VDP (*Veřejný dálkový přístup*) at https://vdp.cuzk.gov.cz has an "Ověření adresy" web form. It is a form, not an API.
- **Other official REST or JSON API for RÚIAN:** none found on the ČÚZK pages read.
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- The CSV file name is `YYYYMMDD_OB_ADR_csv.zip`, dated the last day of the previous month; the file is created on the first day of each month. Only the October 2026 URL was requested.
- The CSV is Windows-1250 and semicolon-separated. A row looks like `4192575;500011;Želechovice nad Dřevnicí;;;;;195901;…;č.p.;1;;;76311;515561.05;1166540.03;2014-02-12T00:00:00`.
- Coordinates in the CSV are S-JTSK with positive Y and X; the ATOM feed labels them EPSG:5513. The ArcGIS service and geocoder return negative values in EPSG:5514.
- Many addresses have no street: villages use only a house number of type "č.p." or "č.ev.".
- Postcodes in RÚIAN are maintained by ČÚZK from Česká pošta data.
- Licence statements differ by place. The CSV's metadata record says CC BY 4.0, open data, "no limitations to public access" (https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng). The ATOM feed for the same file says no conditions apply. ČÚZK's conditions page (https://cuzk.gov.cz/Predpisy/Podminky-poskytovani-prostor-dat-a-sitovych-sluzeb/Podminky-poskytovani-prostorovych-dat-CUZK.aspx , last updated 30.06.2023) gives CC BY 4.0 for RÚIAN in the exchange format, allows commercial and non-commercial use, and asks for the credit "ČÚZK, [year]".
- The human download page https://nahlizenidokn.cuzk.gov.cz/StahniAdresniMistaRUIAN.aspx sits behind a bot-manager challenge: a plain client gets a 303 or 302 redirect, not the page.
- Old `vdp.cuzk.cz` addresses redirect (302) to `vdp.cuzk.gov.cz`.
- Inside the zip the files are named `CSV/20261031_OB_<municipality code>_ADR.csv`.
- Announced on 16.9.2026: from 1.1.2027 senate electoral districts enter RÚIAN, with a new special VFR file `ST_UVOH` (first file 4.1.2027). Announced on 20.3.2026: all monthly state VFR files since August 2015 are at https://services.cuzk.gov.cz/vfr .
- RÚIAN software releases in 2026 with downtime: 4.3 on 26-27 June, 4.3.2 on 23 July, 4.3.4 on 15 October (VDP down 16:30-20:00).
- High-value datasets: data.europa.eu lists 249 Czech datasets with the high-value flag, one of them in the category "Addresses" (ČÚZK's INSPIRE theme Addresses). The record of the monthly CSV does not carry the flag.
- OpenAddresses does not read the live monthly file; it processes its own cached upload.

### Not free or not available

- **Česká pošta postcode files:** free to download, but they carry no licence or terms. The "certificate" document that accompanies each file is a data dictionary, not a licence. They hold no addresses.

### Could not be verified

- The CSV's exact row counts (3,023,585 rows; 3,022,681 with coordinates and 904 without; none without a postcode): recounting needs the whole file, which was not downloaded for the check. The live ArcGIS count of 3,024,015 on 11 Nov 2026 is consistent with them.
- The content of ČÚZK's human download page: the bot-manager challenge was not passed.
- URLs of the daily change files: not checked.
- Per-municipality RÚIAN address sets in CSV and SHP listed on data.europa.eu ("Data RÚIAN o adresách poskytovaná po obcích ve formátu CSV", "Vybraná data RÚIAN poskytovaná po obcích ve formátu SHP"): the records were seen, the endpoints were not requested.
- The date of the copy OpenAddresses holds: the 31 Aug 2024 file name appears only in its "website" field.
- Usage limits or terms for the ArcGIS services: none were found in a first search, and the search was not repeated.
- Content and download options of the ČSÚ census-district and building register.
- Web services reserved for public authorities and third-party APIs built on RÚIAN: they surfaced in searches and were not examined.
