## Slovenia (SI)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes (per publisher; download not confirmed) | Register naslovov (GURS) | JGP portal, WFS, OGC API; no registration per GURS | CC BY 4.0 | Yes, EPSG:3794 | Yes, as postal-district code | Event-driven; no schedule published |

**In short.** Slovenia's *Register naslovov* (Register of Addresses), kept by the surveying authority GURS, is by GURS's own documents free, registration-free and under CC BY 4.0, through the download portal JGP, a WFS, an OGC API Features service and a REST address search. None of that could be confirmed on the live host: `ipi.eprostor.gov.si` answered every anonymous request with HTTP 407 on 11 Nov 2026, and OpenAddresses has not managed to pull the national file since 14 June 2024. Everything below about file format, columns, size and record count therefore comes from GURS documents, catalogue records and OpenAddresses' 2024 description, not from a download. Test the host from the network the import will run on before building on it.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Register naslovov, national file from JGP (*Javni geodetski podatki*, public geodetic data) | Geodetska uprava Republike Slovenije (GURS) | Portal https://ipi.eprostor.gov.si/jgp/ ; file URL as recorded by OpenAddresses: https://ipi.eprostor.gov.si/jgp-service-api/display-views/groups/121/composite-products/141/file?filterParam=DRZAVA&filterValue=1 | Per OpenAddresses' 2024 source definition: zipped CSV, UTF-8, EPSG:3794, columns `E`, `N`, `HS_STEVILKA` (house number), `HS_DODATEK` (suffix), `ULICA_NAZIV` (street), `NASELJE_NAZIV` (settlement), `OBCINA_NAZIV` (municipality), `STATISTICNA_REGIJA_NAZIV`, `POSTNI_OKOLIS_SIFRA` (postcode), `EID_HISNA_STEVILKA`. 573,634 rows in OpenAddresses' run of 14 June 2024 | Per GURS: free, no registration. Host answered HTTP 407 on 11 Nov 2026 | CC BY 4.0 | No schedule published; OpenAddresses labels the product "weekly" | unverified (live host refused; documents and third-party record only) |
| Register naslovov, register description | GURS | https://www.e-prostor.gov.si/podrocja/prostorske-enote-in-naslovi/register-naslovov/ | States the content: address number (identifier given by GURS), address (municipality, settlement, street, house number, suffix, apartment or business-premises number), address centroid inside the building footprint, and the spatial units containing it | Web page | - | - | confirmed |
| Public access rules and service list | GURS | https://www.e-prostor.gov.si/dostopi/javni-dostop/ and technical document https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx | Says public data are free and available without registration; names the services and field names | Web page and document | - | - | confirmed |
| General terms of use | GURS | https://www.e-prostor.gov.si/fileadmin/struktura/Preberi_me.docx (English, older: https://www.e-prostor.gov.si/fileadmin/struktura/EGP/General_terms.pdf) | CC BY 4.0 for GURS data; the list of covered data names "Register prostorskih enot" and "Register naslovov" | Document | - | Slovenian file replaced on 11 Nov 2026; English PDF last modified 1 Aug 2022 | corrected |
| "Register naslovov" on the national open data portal podatki.gov.si | GURS | Seen only as data.europa.eu record `register-naslovov`; podatki.gov.si answered HTTP 407 | Catalogue record with links to JGP (https://ipi.eprostor.gov.si/jgp/data), the WFS and the OGC API. No licence field filled | Not reached | Not filled in the record | Not recorded | corrected (catalogue record only) |
| Postcode list "Seznam poštnih številk za naslavljanje" | Pošta Slovenije | https://www.posta.si/zasebno-site/Documents/Seznami/Seznam%20po%C5%A1tnih%20%C5%A1tevilk%20za%20naslavljanje.pdf | PDF, 10 pages, 309,284 bytes: postcode and post office name, about 460 codes. No streets, no coordinates | Anonymous download | None stated | File last modified 7 Jun 2021 | corrected |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Slovenia | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/si/countrywide.json) | Register naslovov, countrywide: 573,634 addresses, each with number, street, city, district, region and postcode, no unit values (https://batch.openaddresses.io/api/job/399702). A buildings layer from a 2022 extract of the GURS building cadastre | Free download, needs a logged-in account | CC BY 4.0, attribution to GURS | Last successful address run 2024-06-14; the run of 2026-10-30 failed | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 580,213 Slovenian addresses in release 2026-10-21.0 (publisher's figure); not labelled as taken from OpenAddresses | GeoParquet, no account | GURS, CC BY 4.0 | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

All GURS services below are on `ipi.eprostor.gov.si`. They are documented by GURS or listed in catalogue records; none answered on 11 Nov 2026 (HTTP 407), so none was tested.

- **Register naslovov WFS:** https://ipi.eprostor.gov.si/wfs-si-gurs-rn/wfs?request=getCapabilities (GeoServer workspace SI.GURS.RN).
- **Register naslovov OGC API Features:** https://ipi.eprostor.gov.si/wfs-si-gurs-rn/ogc/features/collections .
- **REST address search:** `https://ipi.eprostor.gov.si/search-api/v1/external/iskanje/naslovi/?vir=Naslovi stavb&filter=trnje 10 4220` for building addresses including postcode, and the same call with `?vir=Naslovi stanovanj&filter=ziherlova 40b 202` for apartment-level addresses. Both examples are from the GURS technical document.
- **Cadastre WFS:** https://ipi.eprostor.gov.si/wfs-si-gurs-kn/wfs . The technical document's examples query house numbers there (feature types `NASLOVI_HS`, `HISNE_STEVILKE_H`) with fields `HS_STEVILKA`, `HS_DODATEK`, `ULICA_NAZIV`, `OBCINA_SIFRA`, `NASELJE_SIFRA`, `POSTNI_OKOLIS_SIFRA`, `POSTNI_OKOLIS_NAZIV`, `EID_HISNA_STEVILKA`.
- **Spatial units (RPE) services:** WMS https://ipi.eprostor.gov.si/wms-si-gurs-rpe/wms with a postal-district layer `SI.GURS.RPE:POSTNI_OKOLISI`; OGC API https://ipi.eprostor.gov.si/wfs-si-gurs-rpe/ogc/features/collections/ .
- **Service conditions per the technical document:** no registration or special rights needed; data are kept in SI-D96/TM and published as EPSG:3794, with output also in EPSG:4326, 3912, 3857 and 3035. One call returns at most a maximum set in the server configuration (no number given), and GURS reserves the right to limit this further. There is no uptime guarantee and no dedicated user support (general contact gurs@assist.si).
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- Access from the checking network failed on 11 Nov 2026: `ipi.eprostor.gov.si` (JGP pages, address WFS, OGC API) and `podatki.gov.si` answered HTTP 407 Proxy Authentication Required from an Apache front end; the GURS metadata catalogue `eprostor.gov.si/imps` reset the connection. Nothing was retried by another path.
- OpenAddresses' automated pull of the national file last succeeded on 14 June 2024; its run of 30 October 2026 failed. Overture nevertheless lists Slovenian addresses pulled on 15 October 2026.
- The register is new. GURS announced on 5 March 2024 that the Register naslovov was in use and the Register prostorskih enot (RPE, Register of Spatial Units) renewed: from 4 March 2024 house numbers left the RPE and are kept in the real-estate cadastre linked to buildings, and the old MID identifiers gave way to 18-digit EID keys (https://www.gov.si/novice/2024-03-05-izvedena-informacijska-prenova-registra-prostorskih-enot-in-v-uporabo-dan-register-naslovov/). The same notice says everyone can download RPE data in the new structure from JGP.
- Material written for the earlier route does not match the current one: the old EGP portal (`egp.gu.gov.si`) required registration and delivered Windows-1250 shapefiles (`RPE_PE.ZIP`, `RPE_PUL.ZIP`), and the Slovenian OpenStreetMap tooling still describes it (https://github.com/openstreetmap-si/GursAddressesForOSM).
- Licence terms: CC BY 4.0, commercial and non-commercial use, sharing and adaptation allowed. The required credit is "Geodetska uprava Republike Slovenije", the type of data, and the time the data refer to or the date of the database. The right of use ends at once if data are processed against the terms, and GURS may change data structure, services and terms at any time.
- The Slovenian terms file was replaced on the day of the check (dated "Ljubljana: 11. 11. 2026"). The points above are in the new text; it was not compared with the earlier version.
- The register holds apartment numbers and the REST search has an apartment-level source, but the national file OpenAddresses processed in 2024 had no unit values.
- Postcodes: postal districts (*poštni okoliši*) are spatial units in the RPE, and address features carry the postal-district code and name.
- Updates are event-driven (new address number, change in cadastral data, change in spatial-unit boundaries, names or codes). No schedule is published.
- High-value datasets: data.europa.eu shows none of 9,719 Slovenian datasets with the high-value flag. The register's INSPIRE metadata record (`728e9d6a-46d0-4242-b8ef-255317da2ff3`) and its open-data-portal record both carry "high value datasets" only as a keyword.
- Pošta Slovenije's addressing handbook (https://www.posta.si/zasebno-site/Documents/Priro%C4%8Dniki/Prirocnik-za-pravilno-naslavljanje-postnih-posiljk.pdf , January 2026) does not contain the postcode list; it links to the separate PDF listed above.

### Not free or not available

- **Postcode list as a spreadsheet or data file from Pošta Slovenije:** none found; only the PDF.

### Could not be verified

- The JGP portal itself and the national address file: whether the file URL still works, its format, file names, size, exact columns and current record count. The host answered HTTP 407. The only descriptions are OpenAddresses' 2024 source definition and its June 2024 count.
- The address WFS and OGC API: capabilities, feature-type names, paging limits and any throttling. Same refusal.
- The REST address search: documented, not requested.
- Why the host refuses: whether it rejects some automated or foreign clients, or whether this is policy, is not known.
- That an address number is never reused: this wording is not on the register page.
- A gov.si notice of 13 February 2025 about fixing deficient residence addresses: not located.
- Terms of use for Pošta Slovenije's postcode lists: none appear in the handbook or the list. A second linked PDF with special postcodes was not opened.
- The EU INSPIRE Geoportal record for the register: the site presented an expired TLS certificate and was not opened; its content was read from data.europa.eu's copy.
