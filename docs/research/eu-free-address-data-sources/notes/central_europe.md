# Free online address data sources — Poland, Czechia, Slovakia, Hungary, Slovenia (state as of 11 November 2026)

Method note for the report writer: "checked 2026-11-11" means I requested the URL myself on that date (HTTP status, size, headers, or file contents). File inspections were done on the downloaded files (Slovak national CSV, Czech national CSV archive, Polish Opolskie shapefile package, Hungarian postcode spreadsheet, Czech postal CSVs). Counts marked "my count" or "my calculation" are derived from those files, not from a publisher statement. Anything I could not open is marked UNVERIFIED. One host matters here: `ipi.eprostor.gov.si` (the Slovenian download portal and services) answered HTTP 403 to every request from my network, so Slovenia's download step is documented from the publisher's own pages and documents, not from a download I performed.

## Poland — what is the authoritative register, how is it obtained, on what terms, and what are the secondary sources?

### Takeaway
Poland has a fully open national address-point dataset: the address part of the State Register of Borders (PRG), published by GUGiK as no-login bulk downloads (SHP 564 MB, GML 805 MB, regenerated 10 Nov 2026) with about 8.64 million address points carrying house number, postcode, TERYT identifiers and EPSG:2180 coordinates, free "for any use" under the geodesy law rather than a named licence. GUGiK also runs a keyless geocoding/reverse-geocoding API (UUG) and, since September 2026, an OGC API Features service; Poczta Polska's official postcode list is a copyrighted commercial product, but postcodes are already inside the PRG address points.

### Cited Findings

**Authoritative register and publisher**
- The register is the *Państwowy Rejestr Granic i Powierzchni Jednostek Podziałów Terytorialnych Kraju* (PRG, State Register of Borders and Areas of Territorial Division Units), which per GUGiK's page includes "adresów i ich lokalizacji przestrzennej" (addresses and their spatial location); publisher is Główny Urząd Geodezji i Kartografii (GUGiK); legal basis cited is the Council of Ministers regulation of 16 July 2021 (Dz.U. 2021 poz. 1373) — [geoportal.gov.pl PRG page](https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/)
- Address data in PRG originate from the gminas' address registers: the page says address data are "aktualizowane na bieżąco" in line with changes made by gmina offices — [geoportal.gov.pl PRG page](https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/)

**Bulk download (no registration, no key)**
- National SHP package: `https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/POLSKA.zip` — HTTP 200, 564,312,601 bytes, Last-Modified 10 Nov 2026 08:04 GMT (checked 2026-11-11, anonymous request) — [POLSKA.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/POLSKA.zip)
- National GML package: `https://opendata.geoportal.gov.pl/prg/adresy/PRG-punkty_adresowe.zip` — HTTP 200, 804,643,553 bytes, Last-Modified 10 Nov 2026 12:21 GMT; the archive holds 16 per-voivodeship GML files time-stamped 10.11.2026, about 10.8 GB uncompressed (my calculation from the zip directory) (checked 2026-11-11) — [PRG-punkty_adresowe.zip](https://opendata.geoportal.gov.pl/prg/adresy/PRG-punkty_adresowe.zip)
- Per-voivodeship SHP packages follow the pattern `.../PunktyAdresowe/<TERYT 2-digit>/<code>.zip`: Mazowieckie `14/14.zip` 86.7 MB (Last-Modified 10 Nov 2026), Opolskie `16/16.zip` 15.9 MB — both HTTP 200 (checked 2026-11-11) — [14.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/14/14.zip); [16.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/16/16.zip)
- Older "integracja" links still work as redirects: `https://integracja.gugik.gov.pl/PRG/pobierz.php?adresy_zbiorcze_gml` → 302 → the GML zip above; `...?adresy_zbiorcze_shp` → 302 → `https://opendata.geoportal.gov.pl/prg/adresy/PRG-punkty_adresowe_shp.zip` (same 564 MB size) (checked 2026-11-11) — [pobierz.php GML](https://integracja.gugik.gov.pl/PRG/pobierz.php?adresy_zbiorcze_gml)
- Formats offered are SHP and GML only; GeoPackage and CSV are not mentioned on the page; there is no archive of address data (archives 2005–2025 cover boundaries only) — [geoportal.gov.pl PRG page](https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/)
- Gmina/powiat/voivodeship packages can also be picked from the geoportal map ("Dane do pobrania") or via WMS GetFeatureInfo at `https://integracja.gugik.gov.pl/cgi-bin/PanstwowyRejestrGranic` — [geoportal.gov.pl PRG page](https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/)

**Size and record count**
- The national SHP archive contains four layers: `PRG_PunktyAdresowe_POLSKA` (address points), `PRG_Ulice_POLSKA` (streets), `PRG_Place_POLSKA` (squares etc.), `PRG_Miejscowosci_POLSKA` (localities). From the `.shx` index sizes in the zip directory: 8,640,975 address points, 297,609 street features, 8,619 squares, 68,403 localities (my calculation, file dated 10 Nov 2026) — [POLSKA.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/POLSKA.zip)
- The national address `.dbf` is 7.07 GB uncompressed, i.e. above the classic 2 GB dBase limit (my observation from the zip directory) — [POLSKA.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/POLSKA.zip)
- Opolskie alone: 230,984 address points, 9,728 streets, 1,437 localities (read from the DBF headers of the downloaded package) — [16.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/16/16.zip)

**Content**
- Address-point attributes (from the downloaded Opolskie package): `ID_IIP` (e.g. `PL.PZGIK.200_<uuid>_<timestamp>`), `NUMER_PORZ` (house number), `KOD_POCZT` (postcode, e.g. `48-200`), `DATA_NAD`, `NAZWA_ULC` (street name, empty in street-less villages), `ID_ULIC` (TERYT ULIC code), `NAZWA_GMI`, `TERYT_GMI` (7-digit), `NAZWA_MSC` (locality), `ID_SIMC` (TERYT SIMC code). Encoding UTF-8 (`.cpg`), CRS "ETRS_1989_Poland_CS92" = EPSG:2180 (`.prj`). One point per house number; no flat/unit level — [16.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/16/16.zip)

**APIs and services**
- Geocoder "UUG" (documented as *Usługa Usług Geokodowania*; landing page calls it *Uniwersalna Usługa Geokodowania*): base `https://services.gugik.gov.pl/uug/`, plain HTTP GET, JSON output. Requests: `GetAddress` (free-text address), `GetAddressReverse` (WKT point + `srid`, 4326 or 2180), `GetAddresses` (all points on a street / in a locality by SIMC+ULIC), `GetCity`, `GetStreet`, `GetRoadMarker`, `GetLevelCrossing`, `GetLocation` (PRNG names), `GetRoads`. Optional `accuracy` (0.5–1.0, default 0.6) and `exact_number` (default 1) — [UUG documentation](https://services.gugik.gov.pl/uug/opis.html)
- Live test without any key (checked 2026-11-11): `?request=GetAddress&address=Marki, Andersa 1` returned city, street, number, `teryt`, `simc`, `ulic`, postcode `05-270`, and x/y in EPSG:2180, with `"max results limit":15`; `?request=GetAddressReverse&location=POINT(21.020 52.229)&srid=4326` returned the nearest address with `"radius":100` and distance in metres. Note the service redirects `/uug?...` to `/uug/?...` (301) — [UUG endpoint](https://services.gugik.gov.pl/uug/?request=GetAddressReverse&location=POINT(21.020%2052.229)&srid=4326)
- The UUG pages state no API key, no rate limit and no terms of use; the landing page shows usage statistics 2019–2026 with a cumulative total of 259,334,239 calls; contact is uslugi.iip@gugik.gov.pl — [UUG landing page](https://services.gugik.gov.pl/uug/); [UUG documentation](https://services.gugik.gov.pl/uug/opis.html)
- OGC API Features for PRG streets and address points, announced by GUGiK on 2026-09-25: `https://ogcapi.geoportal.gov.pl/res/ims/maps/prg_ad/apiFeatures`, collections *Punkt adresowy* and *Ulica*, HTML and JSON — [GUGiK news](https://www.geoportal.gov.pl/aktualnosci/nowe-uslugi-ogc-api-features-dla-danych-prg-i-prng/)
- The endpoint answers without authentication (HTTP 200); `/collections?f=json` lists `PunktAdresowy` and `Ulica` with CRS84 and storage CRS EPSG:2180 (checked 2026-11-11) — [OGC API collections](https://ogcapi.geoportal.gov.pl/res/ims/maps/prg_ad/apiFeatures/collections?f=json)
- WMS "Krajowa Integracja Numeracji Adresowej" (layers address points, streets): `https://mapy.geoportal.gov.pl/wss/ext/KrajowaIntegracjaNumeracjiAdresowej`; capabilities state Fees "no conditions apply", AccessConstraints "otherRestrictions" (checked 2026-11-11) — [KIN WMS capabilities](https://mapy.geoportal.gov.pl/wss/ext/KrajowaIntegracjaNumeracjiAdresowej?SERVICE=WMS&REQUEST=GetCapabilities)
- The PRG page says address data can also be pulled for a drawn area with the geoportal's "Pobierz dane z usługi WFS" tool (service "Krajowej Integracji Numeracji Adresowej") but gives no standalone address WFS URL — [geoportal.gov.pl PRG page](https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/)

**Licence**
- GUGiK's wording: "Dane PRG są dostępne bezpłatnie i do dowolnego wykorzystania" (PRG data are available free of charge and for any use) — no CC licence is named — [geoportal.gov.pl PRG page](https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/)
- Statutory basis: Art. 40a(2)(1)(a) of the Geodetic and Cartographic Law — no fee is charged for making available the datasets of "państwowego rejestru granic i powierzchni jednostek podziałów terytorialnych kraju" (consolidated text Dz.U. 2024 poz. 1151) — [Sejm ELI consolidated text](https://api.sejm.gov.pl/eli/acts/DU/2024/1151/text.html)
- OpenAddresses records the licence as "Polish Law on Geodesy and Cartography of 17 May 1989", attribution: false, share-alike: false, and pulls the per-voivodeship zips (16 source files, one per voivodeship) — [OpenAddresses pl/mazowieckie.json](https://github.com/openaddresses/openaddresses/blob/master/sources/pl/mazowieckie.json)

**Update frequency**
- Address data: continuous at source ("na bieżąco"); the published national and voivodeship files were all last modified on 10 Nov 2026, the day before my check — [geoportal.gov.pl PRG page](https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/); [POLSKA.zip](https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/POLSKA.zip)

**Caveats**
- Quality depends on each gmina: the OSM wiki says supply "may range from excellent to 'no data supplied, despite legal obligation'" and lists malformed/outdated entries and addresses without buildings (wiki page last edited 29 January 2023, so dated) — [OSM wiki: Państwowy Rejestr Granic](https://wiki.openstreetmap.org/wiki/Pa%C5%84stwowy_Rejestr_Granic)
- Poland-specific OSM tooling: the community's processed import set is at budynki.openstreetmap.org.pl (code `openstreetmap-polska/gugik2osm`) — [OSM wiki: Państwowy Rejestr Granic](https://wiki.openstreetmap.org/wiki/Pa%C5%84stwowy_Rejestr_Granic)

**Secondary sources**
- GUS TERYT (statistical office): TERC (territorial units), SIMC (localities) and ULIC (streets) full files are downloadable from eTERYT in "podstawowa / adresowa / statystyczna" versions; these are identifier catalogues with no house numbers and no coordinates (page HTTP 200, checked 2026-11-11) — [eTERYT full-file download page](https://eteryt.stat.gov.pl/eTeryt/rejestr_teryt/udostepnianie_danych/baza_teryt/uzytkownicy_indywidualni/pobieranie/pliki_pelne.aspx)
- TERYT web service "ws1": "Service and data are available free of charge", XML, covers TERC/SIMC/ULIC, address verification "down to street level"; an account is required and is requested by e-mail to teryt_ws1@stat.gov.pl; the page reports 5,370 registered users and 550+ million queries since 2015 — [api.stat.gov.pl TERYT API](https://api.stat.gov.pl/Home/TerytApi?lang=en)
- Poczta Polska PNA (postcodes): the page lists a PDF "Official List of Postal Address Numbers" (`spispna.pdf`, HTTP 200, 7.9 MB, URL path dated 2024/05, checked 2026-11-11), an electronic version sold in the online shop, and an annual subscription in PDF/TXT/XLS with quarterly updates; postal operators get access only under a written agreement and price list — [Poczta Polska PNA page](https://www.poczta-polska.pl/en/dla-biznesu/oferta/uslugi-pozostale/pocztowe-numery-adresowe/); [spispna.pdf](https://www.poczta-polska.pl/wp-content/uploads/2024/05/spispna.pdf)
- A third-party licensing review states the official PNA register is a commercial product whose terms limit use to the customer's own purposes with no resale, and excludes it as an open source (third-party assessment, not Poczta Polska's own text) — [DataHub licensing notes, postal-codes-pl](https://datahub.io/logistics/postal-codes-pl/.licensing-notes)

**High-Value Datasets (Regulation (EU) 2023/138)**
- On data.europa.eu, a query for Polish datasets flagged as HVD returned 0 (of 25,899 Polish datasets), and 0 in the HVD category "Addresses" (API queries run 2026-11-11) — [data.europa.eu search API, PL + is_hvd](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22country%22%3A%5B%22pl%22%5D%2C%22is_hvd%22%3A%5B%22true%22%5D%7D)
- GUGiK's September 2026 OGC API announcement does not mention high-value datasets — [GUGiK news](https://www.geoportal.gov.pl/aktualnosci/nowe-uslugi-ogc-api-features-dla-danych-prg-i-prng/)

### Inferences
- The identical 10 Nov 2026 modification dates across national and regional files, plus time-stamped GML members, indicate the download packages are regenerated daily; GUGiK's page does not state a regeneration schedule.
- Because `KOD_POCZT` is an attribute of every PRG address point, a free address-to-postcode mapping exists without Poczta Polska's product; how completely gminas fill that field was not measured.
- "For any use" plus OpenAddresses' reading (no attribution, no share-alike) implies commercial reuse is permitted; this rests on GUGiK's statement and the statute, not on a published licence text.
- The September 2026 OGC API launch is the kind of API access the HVD regulation asks for, but I found no GUGiK statement linking the two.

### Gaps
- No current official figure for address-point count or for gminas with missing/incomplete data was found; the 8.64 million figure is my calculation from the 10 Nov 2026 file.
- dane.gov.pl (national open data portal) and its API timed out or refused connections from my network on 2026-11-11, so I could not check whether the PRG address dataset is listed there or tagged "dane o wysokiej wartości". The zero HVD count on data.europa.eu may reflect missing metadata flags rather than non-publication.
- UUG and OGC API rate limits and terms of use: none are published on the pages I read; whether undocumented throttling exists is unknown.
- TERYT ws1 endpoint URLs, test credentials and terms are in a technical manual I did not open. Whether the TERYT building-level catalogue (NOBC) is publicly downloadable was not established; it is not on the download page I read.
- Poczta Polska's own licence wording for the free PDF was not found on its page.

## Czechia — what is the authoritative register, how is it obtained, on what terms, and what are the secondary sources?

### Takeaway
Czechia's RÚIAN (ČÚZK) is fully open: a monthly national CSV of all address points (63 MB zip, 3,023,585 addresses with postcode and S-JTSK coordinates at 31 Oct 2026) downloads from a stable URL with no registration under CC BY 4.0, alongside the full register in the VFR/GML exchange format and a keyless ArcGIS geocoding service. Česká pošta separately publishes free monthly postcode CSVs, but with no stated licence.

### Cited Findings

**Authoritative register and publisher**
- The register is RÚIAN — *Registr územní identifikace, adres a nemovitostí* (Registry of Territorial Identification, Addresses and Real Estate), run by ČÚZK (Český úřad zeměměřický a katastrální / Czech Office for Surveying, Mapping and Cadastre); legal basis Act 111/2009 Coll. and Decree 359/2011 Coll.; launched 1 July 2012 from UIR-ADR, RSO and ISKN — [ČÚZK metadata record for the address CSV](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng)
- Public access application is VDP (*Veřejný dálkový přístup*), now at `vdp.cuzk.gov.cz`; `vdp.cuzk.cz` URLs answer with a 302 redirect to the `.gov.cz` host (checked 2026-11-11) — [VDP exchange-format page](https://vdp.cuzk.gov.cz/vdp/ruian/vymennyformat)

**Bulk download (no registration, no key)**
- National address-point CSV: `https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_OB_ADR_csv.zip` — HTTP 200, 63,371,330 bytes, Last-Modified 1 Nov 2026 (checked and downloaded 2026-11-11). URL pattern is `YYYYMMDD_OB_ADR_csv.zip` with the last day of the previous month — [20261031_OB_ADR_csv.zip](https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_OB_ADR_csv.zip)
- Contents of that archive: 6,258 CSV files (one per municipality), 351 MB unzipped, 3,023,585 address rows, of which 3,022,681 have coordinates (904 without) and none lack a postcode (my count); encoding Windows-1250, semicolon-separated — [20261031_OB_ADR_csv.zip](https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_OB_ADR_csv.zip)
- A second national file, the address hierarchy list: `https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_strukt_ADR.csv.zip` — HTTP 200, 34,233,458 bytes (checked 2026-11-11; contents not inspected) — [20261031_strukt_ADR.csv.zip](https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_strukt_ADR.csv.zip)
- ATOM download feed for the same CSV: `https://atom.cuzk.gov.cz/RUIAN-CSV-ADR-ST/RUIAN-CSV-ADR-ST.xml` (HTTP 200, updated 2026-11-01); the feed describes the service as "veřejně dostupná, bezúplatná" (public, free of charge), one file for the whole state — [ATOM feed](https://atom.cuzk.gov.cz/RUIAN-CSV-ADR-ST/RUIAN-CSV-ADR-ST.xml)
- Human download page for the CSV lists: `https://nahlizenidokn.cuzk.gov.cz/StahniAdresniMistaRUIAN.aspx` (HTTP 200, checked 2026-11-11; page body not readable by my client) — [StahniAdresniMistaRUIAN](https://nahlizenidokn.cuzk.gov.cz/StahniAdresniMistaRUIAN.aspx)
- Full register (all RÚIAN elements incl. buildings, parcels, streets, boundaries): the VDP "Výměnný formát" form offers standard / historical / special variants, full copy or increments since a date, state-to-ZSJ or municipality-level sets, basic or complete datasets, and an "addresses" special selection; the page showed "Platnost dat ISÚI k: 10.11.2026 23:46" — [VDP exchange-format page](https://vdp.cuzk.gov.cz/vdp/ruian/vymennyformat)
- ČÚZK's RÚIAN information pages say the CSV files are split by municipality and generated monthly from the state VFR, that VFR files are GML 3.2.1, and that VDP is free with no registration (as reported in search-result extracts of the page, which I did not open in full) — [ČÚZK RÚIAN/ISÚI information page](https://cuzk.gov.cz/ruian/RUIAN-(1)/Informace-o-RUIAN/RUIAN_ISUI.aspx)

**Content**
- CSV columns (header of the downloaded file): Kód ADM (address-point code), Kód obce, Název obce, Kód MOMC, Název MOMC, Kód obvodu Prahy, Název obvodu Prahy, Kód části obce, Název části obce, Kód ulice, Název ulice, Typ SO (č.p./č.ev.), Číslo domovní, Číslo orientační, Znak čísla orientačního, PSČ, Souřadnice Y, Souřadnice X, Platí Od. Sample row: `11925850;578011;Chodov;...;č.p.;8;;;36464;853663.51;1028459.43;2022-11-01T00:00:00` — [20261031_OB_ADR_csv.zip](https://vdp.cuzk.gov.cz/vymenny_format/csv/20261031_OB_ADR_csv.zip)
- Coordinates are S-JTSK (positive Y/X values in the CSV); the ATOM feed's index link is labelled "S-JTSK" under code 5513 — [ATOM feed](https://atom.cuzk.gov.cz/RUIAN-CSV-ADR-ST/RUIAN-CSV-ADR-ST.xml)
- The metadata describes the content as one record per address point with building type, house number, orientation number and letter, postcode and validity date; spatial resolution "corresponding scale 1:1000"; postcodes "are maintained by ČÚZK based on data from Česká pošta" — [ČÚZK metadata record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng)

**APIs and services**
- ArcGIS REST service "Prohlížecí a vyhledávací služba nad daty RÚIAN": `https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/Vyhledavaci_sluzba_nad_daty_RUIAN/MapServer` — layers include 1 `AdresniMisto`, 2/3 building objects, 4 `Ulice`, 5 `Parcela`; capabilities "Map,Query,Data"; extensions GeocodeSOE and WMSServer; `maxRecordCount` 1,000,000; copyright "© ČÚZK" (checked 2026-11-11) — [RÚIAN MapServer](https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/Vyhledavaci_sluzba_nad_daty_RUIAN/MapServer?f=json)
- Geocoding verified live without key: `.../MapServer/exts/GeocodeSOE/findAddressCandidates?SingleLine=Pod sídlištěm 1800/9 Praha&f=json` returned "Pod sídlištěm 1800/9, Kobylisy, 18200 Praha 8", score 100, type AdresniMisto, coordinates in wkid 102067 / latestWkid 5514 (checked 2026-11-11) — [findAddressCandidates](https://ags.cuzk.gov.cz/arcgis/rest/services/RUIAN/Vyhledavaci_sluzba_nad_daty_RUIAN/MapServer/exts/GeocodeSOE/findAddressCandidates?SingleLine=Pod+s%C3%ADdli%C5%A1t%C4%9Bm+1800%2F9+Praha&f=json)
- A map-based ATOM file picker is linked from the metadata: `https://ags.cuzk.gov.cz/geoprohlizec/?atom=ruian` — [ČÚZK metadata record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng)

**Licence**
- ČÚZK provides open spatial data "bezúplatně na základě licence Creative Commons CC-BY 4.0"; listed qualifying data include "RÚIAN data in the RÚIAN exchange format"; commercial and non-commercial use allowed; attribution "ČÚZK, [rok]" on viewing services and prints, data to be shared with metadata, adaptations described, licence terms made available (e.g. by link); page last updated 30.06.2023 — [ČÚZK conditions for providing spatial data](https://cuzk.gov.cz/Predpisy/Podminky-poskytovani-prostor-dat-a-sitovych-sluzeb/Podminky-poskytovani-prostorovych-dat-CUZK.aspx)
- The address CSV's own metadata record states licence Creative Commons BY 4.0, "no limitations to public access", marked as open data — [ČÚZK metadata record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng)
- Conflict to note: the ATOM feed for the same file carries `<rights>žádné podmínky neplatí</rights>` ("no conditions apply"), which is looser than the CC BY 4.0 stated in the metadata and conditions page — [ATOM feed](https://atom.cuzk.gov.cz/RUIAN-CSV-ADR-ST/RUIAN-CSV-ADR-ST.xml)
- OpenAddresses lists the source as CC-BY 4.0, attribution name "ČÚZK"; its source file still points at a cached August 2024 copy (`20240831_OB_ADR_csv.zip`) rather than the live monthly URL — [OpenAddresses cz/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/cz/countrywide.json)

**Update frequency**
- CSV state file: "created on the first day of each month, with data valid to the last day of the previous month"; change files are generated daily; metadata last revised 14.08.2026 — [ČÚZK metadata record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng)

**Caveats and recent changes**
- ČÚZK's RÚIAN news archive showed no news items for 2026 ("V roce 2026 nebyly publikovány prozatím žádné novinky") when read on 2026-11-11 — [RÚIAN news archive 2026](https://cuzk.gov.cz/ruian/Novinky-RUIAN/Archiv-novinek-RUIAN/2026.aspx)
- ČÚZK's operations log lists RÚIAN 4.3 and 4.3.2 releases installed in June and July 2026 with production downtime (from a search-result extract; page not opened) — [ISÚI operations archive](https://cuzk.gov.cz/ruian/Editacni-agendovy-system-ISUI/Provozni-informace-a-odstavky/Archiv-PROD.aspx)
- Many Czech addresses have no street (villages use only a house number, "č.p." / "č.ev."), which OpenAddresses documents with examples — [OpenAddresses cz/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/cz/countrywide.json)

**Secondary sources**
- Česká pošta "zákaznické výstupy" (customer outputs): three postcode datasets as zipped CSV with a certificate document each — "Seznam PSČ částí obcí a obcí bez částí" (`db_pcobc-zip`), "Seznam adresních PSČ" (`csv_psc_a-zip`), "Seznam částí obcí a obcí s adresním PSČ" (`csv_cobce_psc-zip`); outputs are updated on the first working day of each month (selected ones every Monday); the page states no licence or terms — [Česká pošta download page](https://www.ceskaposta.cz/ke-stazeni/zakaznicke-vystupy)
- Verified files (checked and downloaded 2026-11-11, both dated 1 Nov 2026): `zv_pcobc.csv` 16,152 data rows with columns NAZCOBCE;PSC;NAZPOST;KODOKRESU;NAZOKRESU;NAZOBCE (municipality part → postcode → delivering post office → district); `zv_psc_adr.csv` 20,135 data rows with columns PSC;TYP_PSC. Neither contains streets, house numbers or coordinates — [db_pcobc zip](https://www.ceskaposta.cz/documents/d/guest/db_pcobc-zip?download=true); [csv_psc_a zip](https://www.ceskaposta.cz/documents/d/guest/csv_psc_a-zip?download=true)
- Czech Statistical Office register of census districts and buildings (RSO) page exists at `csu.gov.cz/rso/registr_scitacich_obvodu` (redirect from czso.cz, HTTP 200, checked 2026-11-11); RSO was one of RÚIAN's three founding inputs — [ČSÚ RSO page](https://csu.gov.cz/rso/registr_scitacich_obvodu); [ČÚZK metadata record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng)

**High-Value Datasets**
- data.europa.eu lists 249 Czech datasets flagged HVD; exactly one is in the HVD category "Addresses": ČÚZK's "INSPIRE theme Addresses (AD)" (dataset id `https-atom-cuzk-cz-api-responses-cz-00025712-cuzk_ad-jsonld`, harvested from the Czech national catalogue) (API queries run 2026-11-11) — [data.europa.eu search API, CZ + Addresses category](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=20&facets=%7B%22country%22%3A%5B%22cz%22%5D%2C%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)
- The metadata record of the monthly address CSV itself does not carry an HVD flag — [ČÚZK metadata record](https://geoportal.gov.cz/php/micka/record/basic/CZ-00025712-CUZK_SERIES-MD_RUIAN-CSV-ADR-ST?dlang=eng)

### Inferences
- RÚIAN was already free, bulk-downloadable and CC BY 4.0 before the HVD regulation applied (conditions page dated June 2023), so the regulation appears to have changed metadata tagging (the INSPIRE AD set is flagged) rather than access or price.
- The positive-valued S-JTSK coordinates in the CSV correspond to the south/west-oriented Křovák axes (code 5513 in the feed), whereas the ArcGIS geocoder returns negative East-North values (5514); users must convert sign/axis order when combining the two.
- Since ČÚZK maintains PSČ inside RÚIAN from Česká pošta data and every one of the 3.02 million rows has a postcode, the RÚIAN CSV is the practical free source for address-level postcodes; Česká pošta's files add only municipality-part-level lists.
- `maxRecordCount` of 1,000,000 on the public ArcGIS layer suggests large queries are technically possible, but ČÚZK publishes no usage limits for it, so heavy use is at the user's risk.

### Gaps
- No published rate limits or terms specific to the ArcGIS geocoding/query service were found.
- I did not find an official public REST/JSON "RÚIAN API" beyond the ArcGIS services and file downloads; search results surfaced only third-party APIs built on RÚIAN and web services reserved for public authorities.
- The VFR file naming, exact sizes and the daily change-file URLs were not individually checked.
- Česká pošta licence terms for the PSČ files: none stated on the page; the certificate documents were not opened.
- ČSÚ RSO content and download options were not examined.

## Slovakia — what is the authoritative register, how is it obtained, on what terms, and what are the secondary sources?

### Takeaway
Slovakia's Register adries (Ministry of Interior) is open under CC0: a national CSV (162 MB, 1,739,536 addresses, 98% with coordinates, postcode included) downloads without registration from data.slovensko.sk, and a public GeoServer WFS serves the live register (1,750,730 address points on 11 Nov 2026) in CSV/GeoJSON/Shapefile. The datasets are explicitly flagged as EU High-Value Datasets; the weak spots are a CSV that lags the live register and change batches that appear to stop at January 2025.

### Cited Findings

**Authoritative register and publisher**
- *Register adries* (Address Register), established by Act 125/2015 Coll., kept by the Ministry of Interior (Ministerstvo vnútra SR, MV SR); municipalities enter building numbers and mark address-point positions; the register holds a postcode for each address and its geographic part holds "polohu každého adresného bodu a geografické osi ulíc" — [Act 125/2015, version effective 1 April 2024](https://static.slov-lex.sk/static/SK/ZZ/2015/125/20240401.html)
- National catalogue entry for the series "Register adries" (publisher MV SR, described as containing all addresses in Slovakia, declared frequency DAILY, typed as HVD) with parts including "Adresy podľa krajov (csv)", change batches, and registers of regions, districts, municipalities, municipality parts, streets, buildings (súpisné čísla), entrances (orientačné čísla) and flats — [data.slovensko.sk SPARQL endpoint](https://data.slovensko.sk/api/sparql)
- The old portal data.gov.sk now redirects (302) to data.slovensko.sk (checked 2026-11-11) — [data.gov.sk register-adries URL](https://data.gov.sk/dataset/register-adries-register-vchodov)

**Bulk download (no registration, no key)**
- Dataset "Adresy podľa krajov (csv)": landing page `https://data.slovensko.sk/datasety/b27f57f1-7e76-45e0-8968-631f9176b2e9`, issued 2019-08-27, modified 2026-08-21, declared frequency QUARTERLY; nine CSV distributions — one for all regions plus one per region (Bratislavský, Trnavský, Trenčiansky, Nitriansky, Žilinský, Banskobystrický, Prešovský, Košický) — [data.slovensko.sk dataset page](https://data.slovensko.sk/datasety/b27f57f1-7e76-45e0-8968-631f9176b2e9)
- National file: `https://data.slovensko.sk/download?id=d22c42f3-82b5-450d-b8fb-4245d50a31ec` — HTTP 200, 162,404,526 bytes, served as `Adresy podľa krajov UTF8_04_2026.csv` (checked and downloaded 2026-11-11, anonymous) — [national CSV download](https://data.slovensko.sk/download?id=d22c42f3-82b5-450d-b8fb-4245d50a31ec)
- Contents: 1,739,536 address rows; 1,704,346 (97.98%) have coordinates, 35,190 do not; 401 lack a postcode; 973,318 have no street name and 973,158 no orientation number (my count) — [national CSV download](https://data.slovensko.sk/download?id=d22c42f3-82b5-450d-b8fb-4245d50a31ec)
- OpenAddresses' run of 30 October 2026 on the same URL independently reports 1,739,536 rows, 35,190 geometry failures and 1,739,135 postcodes — [OpenAddresses job 946657](https://batch.openaddresses.io/api/job/946657)
- Change batches: dataset "Register adries - Zmenové dávky od 27.5.2024 do 31.01.2025" (XML files, declared WEEKLY, modified 2025-02-04, HVD-flagged) — [change-batch dataset](https://data.slovensko.sk/datasety/de3dd18f-9124-4acb-ae00-705555332256)

**Content**
- CSV header: `IDENTIFIKATOR;KRAJ;OKRES;OBEC;CAST_OBCE;ULICA;SUPISNE_CISLO;ORIENTACNE_CISLO_CELE;PSC;ADRBOD_X;ADRBOD_Y`; semicolon-separated, UTF-8, decimal comma; sample `4320536;Banskobystrický;Banská Bystrica;Badín;;Banská;150;2;97632;19,121502;48,6661543` (X = longitude, Y = latitude in degrees) — [national CSV download](https://data.slovensko.sk/download?id=d22c42f3-82b5-450d-b8fb-4245d50a31ec)
- The dataset description gives the same structure: address identifier, region, district, municipality, municipality part, street, súpisné číslo (registration number), orientačné číslo (orientation number), postcode, address point x, y — [data.slovensko.sk SPARQL endpoint](https://data.slovensko.sk/api/sparql)
- WFS feature attributes (sample feature): `identifier`, `uri_identifier` (`https://data.gov.sk/id/physical-address/<id>`), `fulladdress`, `streetname`, `street_id`, `postalcode`, `orientationnumber`, `propertyregistrationnumber`, `district_name`/`district_id` (municipality part), `lau2_*`, `lau1_*`, `nuts3_*`, `validfrom`, point geometry in EPSG:4258 — [rageo WFS sample request](https://rageo.minv.sk/geoserver/ra/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=ra:address&count=1&outputFormat=application/json)

**APIs and services**
- WFS "Mapová služba registra adries": `https://rageo.minv.sk/geoserver/ra/wfs` — provider MV SR, Fees NONE, AccessConstraints NONE, feature type `ra:address` ("Adresne body"), default CRS EPSG:4258, default count limit 1,000,000, output formats include GML, GeoJSON, CSV, KML and SHAPE-ZIP (checked 2026-11-11) — [rageo ra WFS capabilities](https://rageo.minv.sk/geoserver/ra/wfs?service=WFS&version=2.0.0&request=GetCapabilities)
- Live count: `resultType=hits` on `ra:address` returned numberMatched = 1,750,730 (checked 2026-11-11) — [rageo WFS hits request](https://rageo.minv.sk/geoserver/ra/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=ra:address&resultType=hits)
- INSPIRE download service: `https://rageo.minv.sk/geoserver/ad/wfs` — "INSPIRE ukladacia služba pre tému Adresy", feature types `ad:Address`, `ad:AddressAreaName`, `ad:AdminUnitName`, `ad:PostalDescriptor`, `ad:ThoroughfareName`, Fees NONE, AccessConstraints NONE (checked 2026-11-11); WMS endpoints exist at `/ra/wms` and `/ad/wms` — [rageo ad WFS capabilities](https://rageo.minv.sk/geoserver/ad/wfs?service=WFS&version=2.0.0&request=GetCapabilities)
- The catalogue itself has a public SPARQL endpoint (`https://data.slovensko.sk/api/sparql`), which is how the metadata above was read — [data.slovensko.sk SPARQL endpoint](https://data.slovensko.sk/api/sparql)
- Statutory route (separate from open data): the ministry provides register data on request as an electronic extract (single or bulk) or "automatizovaným spôsobom", the automated mode being conditional on an agreement with the ministry; "Register je verejne prístupný aj prostredníctvom webového sídla ministerstva", with data so published being of informative character (§ 10) — [Act 125/2015, § 10](https://static.slov-lex.sk/static/SK/ZZ/2015/125/20240401.html)

**Licence**
- The national CSV distribution's terms-of-use metadata give CC0 for all three rights categories (author's work, original database, sui generis database right), author "MVSR" — [data.slovensko.sk SPARQL endpoint](https://data.slovensko.sk/api/sparql)
- OpenAddresses records CC0 1.0, attribution not required, attribution name "Ministerstvo vnútra Slovenskej republiky / Ministry of Interior of the Slovak Republic" — [OpenAddresses sk/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/sk/countrywide.json)
- The OSM import wiki likewise states the MV SR data are under CC0 — [OSM wiki Sk:MinvSKAddress](https://wiki.openstreetmap.org/wiki/Sk:MinvSKAddress)

**Update frequency**
- CSV: declared quarterly, dataset modified 2026-08-21, but the file served on 2026-11-11 is named `..._04_2026.csv` — [national CSV download](https://data.slovensko.sk/download?id=d22c42f3-82b5-450d-b8fb-4245d50a31ec); [data.slovensko.sk dataset page](https://data.slovensko.sk/datasety/b27f57f1-7e76-45e0-8968-631f9176b2e9)
- WFS: serves 11,194 more addresses than the CSV (1,750,730 vs 1,739,536) on the same day — [rageo WFS hits request](https://rageo.minv.sk/geoserver/ra/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=ra:address&resultType=hits)

**Caveats**
- More than half the addresses have no street name because many municipalities have no named streets; such addresses carry only the súpisné číslo (my count above; OpenAddresses' Slovak test cases cover the "address without conscription number" variants) — [OpenAddresses sk/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/sk/countrywide.json)
- Historic quality notes from the OSM community (undated older import): about 1,112,000 address points of which 574,000 were approximate ("orientačných"), roughly 9,000 points with swapped latitude/longitude, some municipalities without address points — [OSM wiki Sk:MinvSKAddress](https://wiki.openstreetmap.org/wiki/Sk:MinvSKAddress)
- In the catalogue, the component datasets "Register budov", "Register vchodov", "Register ulíc", "Register bytov", "Register obcí" etc. (modified April 2024) and "Zmenové dávky registra adries" returned no distributions in my query — [data.slovensko.sk SPARQL endpoint](https://data.slovensko.sk/api/sparql)

**Secondary sources**
- Slovenská pošta: a postcode lookup tool at `https://www.posta.sk/psc` (HTTP 200, checked 2026-11-11); the page has a "Súbory na stiahnutie" heading but I could not extract any bulk postcode file link from it; several older guessed URLs return 404 — [posta.sk PSČ lookup](https://www.posta.sk/psc)
- ÚGKK / ZBGIS: the English geoportal page says ordering ZBGIS data requires filling out an order form (page updated 03.02.2026, per search-result extract; not opened) — [skgeodesy.sk ZBGIS order page](https://www.skgeodesy.sk/geoportal-en/zbgis/order)
- Municipal address datasets also exist in the national catalogue (e.g. Prešov, Banská Bystrica, Trebišov, Trnava, Levice, Svidník, Myjava, Vranov nad Topľou) — [data.slovensko.sk SPARQL endpoint](https://data.slovensko.sk/api/sparql)

**High-Value Datasets**
- "Adresy podľa krajov (csv)" is typed `dataset-type/HVD`, with applicable legislation `http://data.europa.eu/eli/reg_impl/2023/138/oj` and HVD category `c_c3de25e4` (Addresses); the "INSPIRE - Adresy" dataset (WFS/WMS at rageo.minv.sk) and the change-batch dataset carry the same flag — [data.slovensko.sk SPARQL endpoint](https://data.slovensko.sk/api/sparql)
- data.europa.eu shows 315 Slovak HVD-flagged datasets, 9 of them in the "Addresses" category, all from MV SR (addresses by region, INSPIRE addresses, change batches, and road-section datasets) (API query run 2026-11-11) — [data.europa.eu search API, SK + Addresses category](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=20&facets=%7B%22country%22%3A%5B%22sk%22%5D%2C%22hvdCategory%22%3A%5B%22c_c3de25e4%22%5D%7D)

### Inferences
- The CSV dates from before the HVD regulation (issued 2019); what the regulation visibly added is the HVD tagging, the INSPIRE-model WFS record (dated December 2024) and the change-batch series that begins 27 May 2024, shortly before the 9 June 2024 application date. I found no publisher statement making that link.
- The CSV served in November 2026 is probably the April 2026 extract (file name) despite the "quarterly" label; anyone needing current data should page the WFS (two requests of up to 1,000,000 features) instead.
- Change batches appear to have stopped after 31 January 2025: the only batch dataset with files ends there and the generic one has no files. This is an inference from the catalogue, not a statement by MV SR.
- The per-table datasets (buildings, entrances, streets, flats) seem to have lost their distributions in the move from data.gov.sk (CKAN) to data.slovensko.sk, so flat-level data is effectively not available as open data now; the CSV and WFS are entrance-level.
- CC0 with no attribution requirement means commercial reuse is unrestricted.

### Gaps
- Coordinate reference system is not stated inside the CSV; values look like ETRS89/WGS84 degrees and the WFS declares EPSG:4258, but the CSV's CRS is unconfirmed by the publisher.
- No usage limits or terms for the rageo.minv.sk services were found beyond "Fees NONE / AccessConstraints NONE".
- Whether Slovenská pošta still publishes a downloadable PSČ file, and under what terms, is UNVERIFIED.
- Whether ZBGIS building/address-point layers are freely downloadable in bulk, and their licence, is UNVERIFIED.
- The MV SR web page for the register (`minv.sk/?register-adries`) returned only general ministry news to my client, so the ministry's own description of open-data provision was not read.

## Hungary — is there any open national address register, and what is realistically the best free source?

### Takeaway
Hungary has no open national address dataset: the Central Address Register (KCR) exists and holds coordinates, but the governing decree allows transfer only to enumerated public bodies, and I found no public download, API, or open-data listing for it. The only official free files are Magyar Posta's postcode spreadsheet (settlement-level, plus street ranges for Budapest and five cities, no coordinates) and the KSH gazetteer, so house-number-level open data comes only from the pan-European community sources covered elsewhere.

### Cited Findings

**The register and its legal status**
- KCR — *Központi Címregiszter* (Central Address Register). Its original decree, 345/2014. (XII. 23.) Korm. rendelet, was repealed with effect from 7 November 2024 by § 153 point 1 of 322/2024. (XI. 6.) Korm. rendelet — [Nemzeti Jogszabálytár, 345/2014](https://njt.jog.gov.hu/jogszabaly/2014-345-20-22)
- The rules now sit in Chapter XIX "Központi címregiszter" (§ 122 onward) of 322/2024. (XI. 6.) Korm. rendelet on the technical requirements of digital services — [Nemzeti Jogszabálytár, 322/2024](https://njt.jog.gov.hu/jogszabaly/2024-322-20-22)
- Content per § 126: country, county, settlement, postcode, settlement part, district, public-space name and type, house number, building, staircase, floor and door identifiers, plus address coordinates, the land-registry identifier, a unique ID code and whether the entry denotes a plot, building or public space — so the register is unit-level with coordinates — [Nemzeti Jogszabálytár, 322/2024](https://njt.jog.gov.hu/jogszabaly/2024-322-20-22)
- Access per § 127: address data "automatikus adatátvétellel továbbítható" (may be transferred by automatic data transfer) to the personal-data and address registry, the land authority, the state public-building cadastre operator, the Smart City platform operator, the tax authority and the Central Statistical Office (KSH), and — § 127(4) — to bodies obliged to provide digital services; the postal operator may see addresses for its address-handling tasks but supporting bodies "önálló adatszolgáltatást és önálló adattovábbítást nem teljesíthetnek" (may not provide or forward the data independently) — [Nemzeti Jogszabálytár, 322/2024](https://njt.jog.gov.hu/jogszabaly/2024-322-20-22)
- The only publication duty is local: the address-forming authority publishes addresses affected by an address procedure on the municipality's website or notice board for at least one month (§ 129(6)) — [Nemzeti Jogszabálytár, 322/2024](https://njt.jog.gov.hu/jogszabaly/2024-322-20-22)
- Lechner Knowledge Centre describes the 2012–2015 project that replaced overlapping administrative address databases with the unified register — [Lechner Tudásközpont project page](https://lechnerkozpont.hu/en/node/568)

**What I checked for open publication (all negative)**
- National open data portal (Nemzeti Közadatportál, kozadatportal.hu, operated by NAVÜ Kft., the National Data Asset Agency): its CKAN API reports 2,283 datasets; searches for "cím", "címek", "címregiszter", "irányítószám", "házszám", "utca" and "address" each returned 0 datasets, while a control search for "KSH" returned 605 (queries run 2026-11-11) — [kozadatportal.hu package_search API](https://kozadatportal.hu/api/3/action/package_search?q=c%C3%ADmregiszter)
- data.europa.eu: 0 Hungarian datasets flagged as HVD (of 2,283) and 0 in the HVD "Addresses" category (API queries run 2026-11-11) — [data.europa.eu search API, HU + is_hvd](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22country%22%3A%5B%22hu%22%5D%2C%22is_hvd%22%3A%5B%22true%22%5D%7D)
- OpenAddresses has no Hungary source directory at all (`sources/hu` returns "Not Found", while pl, cz, sk and si exist) (checked 2026-11-11) — [GitHub API, openaddresses sources/hu](https://api.github.com/repos/openaddresses/openaddresses/contents/sources/hu)
- Hungarian OSM mailing-list threads from December 2014–February 2015 discuss whether KCR (with coordinates) would be published; the threads do not record any release — [talk-hu, December 2014](https://lists.openstreetmap.org/pipermail/talk-hu/2014-December/005956.html)
- A web search for a Hungarian INSPIRE "Addresses" dataset or download service found Lechner INSPIRE records for other themes (administrative units, orthoimagery, grids, GPS network) but none for addresses — [INSPIRE Geoportal, Hungary administrative units record](https://inspire-geoportal.ec.europa.eu/srv/api/records/6f267d6b-3ea2-44ad-9eae-04bd55836a2e)

**Free official files that do exist**
- Magyar Posta postcode file: `https://www.posta.hu/static/internet/download/Iranyitoszam-Internet_uj.xlsx` — HTTP 200, 1,019,747 bytes, Last-Modified 12 Oct 2026, no login (checked and downloaded 2026-11-11) — [Iranyitoszam-Internet_uj.xlsx](https://www.posta.hu/static/internet/download/Iranyitoszam-Internet_uj.xlsx)
- Its sheets: "Települések" (11,160 rows: IRSZ postcode, settlement, settlement part), "Jelek" (coding notes), "Bp.u." (9,701 Budapest rows: postcode, street name, street type, city part, house-number range fields 1.SZÁM/1.JEL/2.SZÁM/2.JEL, district), and street lists for Miskolc (1,315), Debrecen (2,213), Szeged (1,687), Pécs (1,464) and Győr (1,022). No coordinates and no individual house numbers — only number ranges per postcode (my inspection) — [Iranyitoszam-Internet_uj.xlsx](https://www.posta.hu/static/internet/download/Iranyitoszam-Internet_uj.xlsx)
- Magyar Posta's postcode search page redirects to an interactive lookup at `net.posta.hu/dashboard/public/dashboard-ui/iranyitoszam-kereso` (checked 2026-11-11) — [posta.hu irányítószám-kereső](https://www.posta.hu/szolgaltatasok/iranyitoszam-kereso)
- A third-party licensing note cites this xlsx as the official source and says it is listed among Magyar Posta's public-interest data; a 2019 OSM list post gives one participant's opinion that it is usable as public data (neither is a licence statement by Magyar Posta) — [DataHub licensing notes, postal-codes-hu](https://datahub.io/logistics/postal-codes-hu/.licensing-notes); [talk-hu, January 2019](https://lists.openstreetmap.org/pipermail/talk-hu/2019-January/012039.html)
- KSH (Central Statistical Office) gazetteer "Helységnévtár": application at `https://www.ksh.hu/apps/hntr.main` and downloadable workbook `https://www.ksh.hu/docs/helysegnevtar/hnt_letoltes_2026.xlsx` (HTTP 200, 1,377,826 bytes; the 2025 edition also resolves) (checked 2026-11-11; contents not inspected) — [KSH Helységnévtár](https://www.ksh.hu/apps/hntr.main); [hnt_letoltes_2026.xlsx](https://www.ksh.hu/docs/helysegnevtar/hnt_letoltes_2026.xlsx)
- KSH states it publishes statistical high-value datasets under Regulation 2023/138 via APIs — these are statistics, not addresses — [KSH HVD page](https://www.ksh.hu/hvd_eng)

**Other leads examined**
- National Election Office (valasztas.hu): a 2018 OSM thread discusses how one might extract a street list from the site and notes an xls of polling stations; my search found no confirmation that a downloadable address or street list is currently published, and voter-register address data are released only to entitled applicants — [talk-hu, April 2018](https://lists.openstreetmap.org/pipermail/talk-hu/2018-April/010623.html); [valasztas.hu data request page](https://www.valasztas.hu/en/szavazokori-nevjegyzeki-adatok-igenylese-jeloltek-partok-reszere)
- The national portal was profiled by data.europa.eu on 23 October 2026 as the central starting point for Hungarian public data; the article mentions no address or geospatial register — [data.europa.eu news](https://data.europa.eu/en/news-events/news/making-public-data-easier-find-discover-hungarys-national-data-portal)

### Inferences
- Plainly: there is no open, free, bulk or API access to Hungary's national address register. The law frames KCR as an inter-agency register with a closed list of recipients, and nothing on the national portal, the EU portal or OpenAddresses contradicts that.
- Hungary has not published addresses as a High-Value Dataset as far as the EU portal's flags show; I found no announcement of plans to do so. Absence of a flag is not proof of non-compliance, but no address dataset exists to be flagged.
- The realistic free options are (a) community data from the pan-European aggregators handled by the other researcher, for house-number points, and (b) Magyar Posta's xlsx for settlement→postcode and big-city street→postcode ranges, with the KSH gazetteer for settlement names and codes. None of these is an authoritative house-number dataset.
- Because § 127(3) forbids the postal operator from passing KCR data on, Magyar Posta's file is the postcode system only and cannot become a back door to KCR addresses.

### Gaps
- I could not find any official page describing a public KCR lookup or a paid data-supply service; the operator's own site was not located (guessed hosts did not resolve). Whether individual address verification is offered to the public somewhere is UNVERIFIED.
- Magyar Posta's licence/terms for the xlsx were not found on a page I could read (the lookup is a JavaScript app).
- KSH gazetteer contents (whether it carries postcodes or settlement parts) and licence were not inspected.
- Municipal open address datasets (e.g. Budapest districts) were not systematically searched; none surfaced on the national portal searches above.
- Hungary's INSPIRE Addresses obligation: I found no dataset, but did not query the Hungarian INSPIRE catalogue directly.

## Slovenia — what is the authoritative register, how is it obtained, on what terms, and what are the secondary sources?

### Takeaway
Slovenia's Register naslovov (Register of Addresses, GURS, in use since March 2024) is published free under CC BY 4.0 with no registration through the JGP download portal and public WFS / OGC API / REST address-search services, in EPSG:3794, with about 574 thousand addresses in the last independently processed copy (June 2024). I could not complete a download myself because the portal host returned HTTP 403 to my requests, and OpenAddresses' automated pull has not succeeded since 14 June 2024, so treat automated access as unconfirmed.

### Cited Findings

**Authoritative register and publisher**
- *Register naslovov* (Register of Addresses), kept by Geodetska uprava Republike Slovenije (GURS, Surveying and Mapping Authority) in the Kataster information system; established by the Real Estate Cadastre Act (ZKN), with address format defined by the Residence Registration Act (ZPPreb-1) — [e-prostor: Register naslovov](https://www.e-prostor.gov.si/podrocja/prostorske-enote-in-naslovi/register-naslovov/)
- On 5 March 2024 GURS announced the full IT renewal of the Register prostorskih enot (RPE, Register of Spatial Units) and the entry into use of the Register naslovov; from 4 March 2024 house numbers left the RPE and are kept in the real-estate cadastre linked to buildings; old MID identifiers were replaced by 18-digit EID keys; 22 institutions and 97 secondary systems were affected — [gov.si news, 5 March 2024](https://www.gov.si/novice/2024-03-05-izvedena-informacijska-prenova-registra-prostorskih-enot-in-v-uporabo-dan-register-naslovov/)

**Bulk download**
- Download application: *Javni geodetski podatki* (JGP) at `https://ipi.eprostor.gov.si/jgp/`; the official page defines public access as available without registration and all public data as free of charge — [e-prostor: Javni dostop](https://www.e-prostor.gov.si/dostopi/javni-dostop/)
- GURS's 2024 announcement says all users can download RPE data in the new structure from JGP — [gov.si news, 5 March 2024](https://www.gov.si/novice/2024-03-05-izvedena-informacijska-prenova-registra-prostorskih-enot-in-v-uporabo-dan-register-naslovov/)
- The direct national address file used by OpenAddresses: `https://ipi.eprostor.gov.si/jgp-service-api/display-views/groups/121/composite-products/141/file?filterParam=DRZAVA&filterValue=1` (zip), website `https://ipi.eprostor.gov.si/jgp/data`, frequency noted as "weekly" — [OpenAddresses si/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/si/countrywide.json)
- My own requests to `ipi.eprostor.gov.si` (the JGP pages and that file URL) all returned HTTP 403 Forbidden on 2026-11-11, so the link, format and size are NOT verified by me — [JGP data page](https://ipi.eprostor.gov.si/jgp/data)
- OpenAddresses' last successful run of this source is dated 14 June 2024: 573,634 address rows, every row with number, street, city, district, region and postcode, no unit values, output 29.7 MB — [OpenAddresses job 399702](https://batch.openaddresses.io/api/job/399702)
- The older EGP portal (`egp.gu.gov.si`) required user registration and delivered shapefiles in Windows-1250 (`RPE_PE.ZIP`, `RPE_PUL.ZIP`, house numbers), per the Slovenian OSM community's tooling, which still describes that pre-2024 route — [GursAddressesForOSM README](https://github.com/openstreetmap-si/GursAddressesForOSM)

**Content**
- Register content: address number (identifier assigned by GURS, never reused), address = municipality, settlement, street, house number, house-number suffix, and apartment/business-premises number where applicable; address centroid = a point inside the building footprint; plus the spatial units containing the centroid — [e-prostor: Register naslovov](https://www.e-prostor.gov.si/podrocja/prostorske-enote-in-naslovi/register-naslovov/)
- Spatial data are kept in SI-D96/TM and published under EPSG:3794 — [GURS technical documentation (docx)](https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx)
- Service examples in the documentation show house-number features with `HS_STEVILKA`, `HS_DODATEK`, `ULICA_NAZIV`, `OBCINA_SIFRA`, `NASELJE_SIFRA`, and postal-district fields `POSTNI_OKOLIS_SIFRA` / `POSTNI_OKOLIS_NAZIV`, and an `EID_HISNA_STEVILKA` identifier — [GURS technical documentation (docx)](https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx)

**APIs and services**
- Public services need no registration or special rights; they run on GeoServer; a dedicated workspace exists for the address register: "Register naslovov — SI.GURS.RN — WFS — `wfs-si-gurs-rn`"; WFS and OGC API services broadly follow the structure of the open data in JGP — [GURS technical documentation (docx)](https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx)
- INSPIRE metadata for the register lists the WFS `https://ipi.eprostor.gov.si/wfs-si-gurs-rn/wfs?request=getCapabilities` and an OGC API Features endpoint `https://ipi.eprostor.gov.si/wfs-si-gurs-rn/ogc/features/collections` (as reported in a search-result extract of the record; I could not open the record or the endpoints) — [INSPIRE Geoportal record 728e9d6a](https://inspire-geoportal.ec.europa.eu/srv/api/records/728e9d6a-46d0-4242-b8ef-255317da2ff3)
- Public REST address search ("Servis za iskanje naslova po nazivu naslova"): `https://ipi.eprostor.gov.si/search-api/v1/external/iskanje/naslovi/?vir=Naslovi stavb&filter=trnje 10 4220` (building address incl. postcode) and `...?vir=Naslovi stanovanj&filter=ziherlova 40b 202` (apartment-level) — [GURS technical documentation (docx)](https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx)
- Other public endpoints named by GURS: cadastre WFS `https://ipi.eprostor.gov.si/wfs-si-gurs-kn/wfs`, RPE WMS (incl. postal districts) `https://ipi.eprostor.gov.si/wms-si-gurs-rpe/wms`, RPE OGC API `https://ipi.eprostor.gov.si/wfs-si-gurs-rpe/ogc/features/collections/` — [e-prostor: Javni dostop](https://www.e-prostor.gov.si/dostopi/javni-dostop/)
- GURS gives no uptime guarantee and no dedicated user support for the public services (general support gurs@assist.si); no rate limits are stated — [GURS technical documentation (docx)](https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx)

**Licence**
- General terms of use dated Ljubljana, 17.06.2026: GURS data "imajo status informacij javnega značaja in so na voljo pod pogoji mednarodne licence Creative Commons 4.0 (priznanje avtorstva)"; anyone may use the data "nekomercialno in komercialno" on condition of naming the source; sharing and adaptation allowed; the list of covered data explicitly includes "Register prostorskih enot" and "Register naslovov" — [GURS general terms (Preberi_me.docx)](https://www.e-prostor.gov.si/fileadmin/struktura/Preberi_me.docx)
- Required attribution: »Geodetska uprava Republike Slovenije, vrsta podatka in čas, na katerega se podatki nanašajo oziroma datum stanja zbirke podatkov« (GURS, type of data, and the time the data refer to or the database date) — [GURS general terms (Preberi_me.docx)](https://www.e-prostor.gov.si/fileadmin/struktura/Preberi_me.docx)
- The right to use ends immediately if data are processed contrary to the terms; GURS may change data structure, access services and terms at any time, announcing changes on the Portal Prostor — [GURS general terms (Preberi_me.docx)](https://www.e-prostor.gov.si/fileadmin/struktura/Preberi_me.docx)
- English version of the terms and the older Slovenian PDF also resolve (HTTP 200, checked 2026-11-11; not re-read) — [General_terms.pdf](https://www.e-prostor.gov.si/fileadmin/struktura/EGP/General_terms.pdf)
- OpenAddresses records CC BY 4.0 with attribution "Geodetska uprava Republike Slovenije / Surveying and Mapping Authority of the Republic of Slovenia, Register naslovov / Register of addresses, 2024" — [OpenAddresses si/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/si/countrywide.json)

**Update frequency**
- The register page gives no schedule: updates are event-driven (new address number, change in cadastral data used for the address, change in spatial-unit boundaries, names or codes) — [e-prostor: Register naslovov](https://www.e-prostor.gov.si/podrocja/prostorske-enote-in-naslovi/register-naslovov/)
- OpenAddresses' source file labels the JGP product "weekly" (a third-party label) — [OpenAddresses si/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/si/countrywide.json)

**Secondary sources**
- Postcodes: postal districts (*poštni okoliši*) are spatial units in the RPE — GURS lists the RPE WMS as covering postal districts and address features carry the postal-district code and name — so postcodes come with the GURS data under the same CC BY 4.0 terms — [e-prostor: Javni dostop](https://www.e-prostor.gov.si/dostopi/javni-dostop/); [GURS technical documentation (docx)](https://www.e-prostor.gov.si/fileadmin/Storitve/Javni_dostop/Spletni_servisi/GU_DO2_SIST_TD_dostopDo_podatkov_servisi_in_baza.docx)
- Pošta Slovenije: the addressing handbook "Priročnik za pravilno naslavljanje poštnih pošiljk" (PDF, dated Maribor, January 2026 per search-result extract) contains a list of postcodes and post offices; no spreadsheet download was found (PDF not opened by me) — [Pošta Slovenije handbook PDF](https://www.posta.si/zasebno-site/Documents/Priro%C4%8Dniki/Prirocnik-za-pravilno-naslavljanje-postnih-posiljk.pdf)
- Building register: OpenAddresses' Slovenian buildings layer uses GURS "Kataster stavb / Building Cadastre" under CC BY 4.0, from a 2022 extract — [OpenAddresses si/countrywide.json](https://github.com/openaddresses/openaddresses/blob/master/sources/si/countrywide.json)

**High-Value Datasets**
- data.europa.eu shows 0 Slovenian datasets flagged as HVD (of 9,719) and 0 in the HVD "Addresses" category (API queries run 2026-11-11) — [data.europa.eu search API, SI + is_hvd](https://data.europa.eu/api/hub/search/search?filter=dataset&limit=0&facets=%7B%22country%22%3A%5B%22si%22%5D%2C%22is_hvd%22%3A%5B%22true%22%5D%7D)
- The INSPIRE Geoportal record for the Slovenian address register is tagged "High value datasets; Addresses" (as shown in a search-result extract; the record itself could not be opened — the EU geoportal presented an expired certificate and the Slovenian catalogue reset the connection) — [INSPIRE Geoportal record 728e9d6a](https://inspire-geoportal.ec.europa.eu/srv/api/records/728e9d6a-46d0-4242-b8ef-255317da2ff3)

### Inferences
- The decisive recent change is national, not EU-driven: the March 2024 migration created the Register naslovov, moved house numbers out of the RPE, replaced MID with EID identifiers and replaced the registration-gated EGP portal with the no-login JGP portal. Pre-2024 instructions (OSM wiki, community scripts, old `RPE_*.ZIP` names) are obsolete.
- Slovenia appears to tag the address register as an HVD in INSPIRE metadata but not on the open-data portal feed that data.europa.eu harvests, which explains the zero count there.
- The 403 responses I received and OpenAddresses' 29-month gap since its last successful pull both point to the `ipi.eprostor.gov.si` host rejecting some automated or foreign clients. The publisher's pages still describe access as open and registration-free, so this may be network filtering rather than policy; I did not try to work around it.
- The register is unit-aware (apartment numbers, apartment-level search source "Naslovi stanovanj"), but the bulk product processed by OpenAddresses had no unit values, so the downloadable national file is probably building/house-number level.
- Because postal districts are GURS spatial units, Slovenian postcodes are not locked up by the postal operator in the way Polish or Hungarian ones are.

### Gaps
- Not verified by direct download: the JGP file formats (CSV / SHP / GeoPackage), file names, sizes, exact attribute list, current record count, and whether the national address file URL still works. The 573,634 figure is from June 2024.
- WFS / OGC API capabilities, feature-type names, paging limits and any throttling for `wfs-si-gurs-rn` could not be read.
- Whether podatki.gov.si (national open data portal) lists the register: the site returned HTTP 407 to my client.
- A gov.si notice of 13 February 2025 about fixing deficient residence addresses surfaced in search but was not opened; its relevance to data completeness is unknown.
- Pošta Slovenije terms of use for its postcode list were not examined.
