## Italy (IT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | ANNCSU (ISTAT and Agenzia delle Entrate) | bulk CSV in ZIP, no registration | CC BY 4.0 | yes, lon/lat ETRF2000, on 67.0% of rows (31/03/2026) | no | monthly |

**In short.** Use ANNCSU (Archivio Nazionale dei Numeri Civici delle Strade Urbane, the national archive of urban street civic numbers): one national CSV of civic numbers, rebuilt monthly, CC BY 4.0, plain download without registration. Two things trip up an import. Coordinates exist only where the municipality entered them, officially 67.0% of accesses at 31/03/2026 and very uneven between municipalities. And the file has no postcode (CAP): bulk CAP data remain a paid Poste Italiane product. Regional and municipal datasets exist for several areas; Bologna's also carries postcodes.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| ANNCSU indirizzario (address list), national file | ISTAT and Agenzia delle Entrate | https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/getds.php?INDIR_ITA ; description: https://www.anncsu.gov.it/it/consultazione-dellarchivio/open-data/ | Every civic number ("access") in the archive: municipality codes, national street id, street name (also bilingual), national access id, civic number, exponent, lon/lat where present, coordinate method. No postcode | `indirizzarioItalia.zip`, 336,334,007 bytes, holding `INDIR_ITA_20261102.csv` (2,206,534,790 bytes). Plain GET, no registration, key or referer | CC BY 4.0 (stated in the catalogue record https://data.europa.eu/api/hub/search/datasets/age-strad_ind_italia~~1 , not on the ANNCSU pages) | Monthly. File dated 2026-11-02 | confirmed; row count unverified |
| ANNCSU stradario (street directory), national file | ISTAT and Agenzia delle Entrate | https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/getds.php?STRAD_ITA | Streets with their national id and the number of accesses per street (`TOTALE_ACCESSI`) | `stradarioItalia.zip`, 13,920,082 bytes, holding `STRAD_ITA_20261102.csv`. Plain GET | CC BY 4.0 | Monthly | confirmed |
| ANNCSU regional files | ISTAT and Agenzia delle Entrate | https://www.anncsu.gov.it/it/consultazione-dellarchivio/open-data/Accedi-ai-servizi-di-dowload-massivo-in-Open-data/ ; example: https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/getds.php?INDIR_VALL | The same address and street files cut per region: 20 pairs with the codes ABRU, BASI, CALA, CAMP, EMIL, FRIU, LAZI, LIGU, LOMB, MARC, MOLI, PIEM, PUGL, SARD, SICI, TOSC, TREN, UMBR, VALL, VENE | Plain GET. Lombardia address file: 36,906,989 bytes | CC BY 4.0 | Monthly | confirmed |
| CAP (postcode) database | Poste Italiane | https://business.poste.it/business/files/1473808238165/banchedati-faq-cap.pdf | Complete postcode files | Not free. Only lookup tools are free; CAP Professional (MS Access) and CAP Zone (shapefile) are sold | Proprietary | - | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Forward and reverse lookup of Italian addresses: house number, street, city, postcode, coordinates. Declared source: "© Geoportale nazionale" | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Not stated | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/it/countrywide.json | Countrywide layer from ANNCSU without postcodes, plus about 38 further Italian source files | Free download, needs a logged-in account | CC-BY 4.0, attribution "Istat e dall'Agenzia delle Entrate" | Cached file `INDIR_ITA_20260703_GEO.csv`; last successful run 2026-08-14 | confirmed |
| Overture Maps addresses, release 2026-10-21.0 | Overture Maps | https://docs.overturemaps.org/guides/addresses/ | 26,841,754 Italian addresses (publisher's figure), from ANNCSU | GeoParquet, no account | CC BY 4.0 (ANNCSU) | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | ZIP file per country | CC BY 4.0 | Regenerated daily | confirmed |

### Regional sources

| Region | Source | Link | Access | Licence | Check |
|---|---|---|---|---|---|
| Alto Adige / Südtirol | Address layer `gvcc-Address:Addresses`, Provincia di Bolzano | https://geoservices3.civis.bz.it/geoserver/gvcc-Address/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=gvcc-Address:Addresses&SRSNAME=EPSG:4326&outputFormat=JSON&count=1 | WFS, no key. 145,190 address points with German and Italian street and municipality names, house number, ISTAT and Belfiore codes; EPSG:4326 output | CC0 as recorded by OpenAddresses (https://github.com/openaddresses/openaddresses/blob/master/sources/it/32/south-tyrol-it.json); the publisher's own statement was not checked | corrected |
| Toscana | ITER.NET road graph, SHP, v. 4.48 of June 2022, Regione Toscana | https://www502.regione.toscana.it/geoscopio/download/grafo_stradale/ | Single ZIP `iternet.zip`. The page does not say whether the package contains civic numbers; the ZIP was not opened | CC BY 4.0 | confirmed |
| Emilia-Romagna | DBTR - Civico (NCV_GPT), civic numbers of the regional topographic database | https://data.europa.eu/api/hub/search/search?q=civici%20DBTR&filter=dataset&limit=14 ; download page: https://geoportale.regione.emilia-romagna.it/download/download-data?type=dbtopo | Catalogue record with six distributions, modified 2025-08-31. The geoportal download page returned HTTP 500 on 2026-11-11 | CC BY 4.0 | confirmed (catalogue); download page unverified |
| Friuli Venezia Giulia | Numeri Civici Ascot 2024 (civic numbers) | https://www.dati.friuliveneziagiulia.it/Regioni-e-citt-/Numeri-Civici-Ascot-2024/fcre-uegn | Regional open data portal. Rows last updated 2024-09-30 | Italian Open Data License 2.0 (IODL 2.0) | confirmed |
| Liguria | `civici.zip`, Regione Liguria | https://srvcarto.regione.liguria.it/geoservices/data/open_addresses/civici.zip | Direct ZIP, 412,780 bytes, last modified 6 December 2017. Too small for a region-wide file; content not inspected, treat as stale or partial | CC BY 3.0 IT as recorded by OpenAddresses (https://github.com/openaddresses/openaddresses/blob/master/sources/it/42/statewide.json) | confirmed (file exists) |
| Sicilia | Carta tecnica numerica scala 1:2.000 - numeri civici (civic numbers of urban areas from the 1:2,000 technical map) | https://dati.regione.sicilia.it/dataset/carta-tecnica-numerica-scala-1-2-000-numeri-civici | GeoJSON in ZIP. Last updated 11 May 2022 | Creative Commons Attribution, version not stated | confirmed |
| Piemonte | BDTRE (Banca Dati Territoriale di Riferimento degli Enti) addresses | https://github.com/openaddresses/openaddresses/blob/master/sources/it/21/statewide.json | Known through the OpenAddresses source, whose cached copy dates from 2024-11-03. No publisher page was read | CC BY 4.0 as recorded by OpenAddresses; the national metadata record says "conditionsUnknown" | unverified |
| Lombardia | Per-province packages on the regional geoportal | https://github.com/openaddresses/openaddresses/blob/master/sources/it/25/mi.json ; package URL: https://www.geoportale.regione.lombardia.it/rlregis_download/service/package?dbId=323&cod=15 | The package URL timed out on 2026-11-11 | IODL 2.0 as recorded by OpenAddresses | unverified |
| Umbria | ArcGIS service "ECOGRAFICO_CATASTALE1_WGS84" | https://github.com/openaddresses/openaddresses/blob/master/sources/it/55/statewide.json | The host answers with a TLS certificate issued for another name; not read | Not known | unverified |
| Sardegna | Regional geoportal page | https://www.sardegnageoportale.it/index.php?xsl=1598&s=291551&v=2&c=8831&t=1 ; OpenAddresses source: https://github.com/openaddresses/openaddresses/blob/master/sources/it/88/statewide.json | The page gave an empty reply on 2026-11-11. OpenAddresses holds a cached copy from 2016 (`sardegna20160804.zip`) | IODL 2.0 as recorded by OpenAddresses | unverified (page); confirmed (OpenAddresses copy) |
| Veneto; Province of Trento | Region-wide address dataset | none | None found. Searched: data.europa.eu for civic numbers of the Veneto region and of the autonomous province of Trento. Only per-municipality datasets turned up; Regione del Veneto publishes per-municipality "Numeri civici" sets | CC BY 4.0 for the Veneto per-municipality sets | none found |
| Bologna (city) | Civic numbers `rifter_civici_pt`, Comune di Bologna | https://opendata.comune.bologna.it/api/explore/v2.1/catalog/datasets/rifter_civici_pt/records?limit=1 | API. 77,614 civic numbers with coordinates, a postcode field `cap` and an ANNCSU code `codice_ann` | Not confirmed | confirmed; licence unverified |
| Torino (city) | Civic numbers in WGS84, Comune di Torino | http://geoportale.comune.torino.it/geodati/civici_WGS84_EPSG4326_csv.csv | Direct CSV, 9,721,244 bytes, last modified 7 October 2026 | Not recorded | confirmed |
| Firenze (city) | `civici.zip`, Comune di Firenze | https://datigis.comune.fi.it/shp/civici.zip | Direct ZIP, 6,135,739 bytes, last modified 9 November 2026 | Not recorded | confirmed |
| Verona (city) | Numerazione civica Comune di Verona (civic numbering), on the Veneto portal | https://dati.veneto.it/opendata/Numerazione_civica_Comune_di_Verona | Portal page. It also says "Al momento non è possibile visualizzare il dato" (the data cannot be displayed at the moment) | CC BY 4.0 | confirmed |
| Palermo (city) | Indirizzario e stradario del Comune di Palermo - numeri civici georeferenziati (georeferenced civic numbers) | https://opendata.comune.palermo.it/js/server/uploads/dataset/csv/_01042026064924.csv | Direct CSV, 16,316,611 bytes, dated 1 April 2026 | CC BY 4.0 | confirmed |

### Free APIs and services

- **ANNCSU query API**, https://anncsu.open.agenziaentrate.gov.it/age-inspire/opendata/anncsu/querydata.php : JSON, no key. `?resource=odonimi&codicecomune=H501&denominazione=VIA%20MILANO` returns the street with its national id (`Progressivo_nazionale` 917411). `?resource=accessi&progressivoodonimo=917411&accesso=1` returns the matching civic numbers with `Civico`, `CoordX`, `CoordY` and `Metodo`. It works as a street-and-number lookup for one municipality at a time.
- **ANNCSU bulk download**, `getds.php` (see the table): plain GET works; `HEAD` is answered with HTTP 403.
- **Alto Adige WFS** (Provincia di Bolzano) and the **Bologna open data API**: see the regional table.
- **GISCO Address API (Eurostat)**, https://gisco-services.ec.europa.eu/addressapi : no key, lookup only. `/reverse?x=12.4894668&y=41.8997245` returned, for example, house number 3, "VIA PIACENZA", Roma, postcode "184". The postcode comes without its leading zeros (CAP 00184). The Italian data are attributed to the "Geoportale nazionale", not to ANNCSU, and their date is not given.

### Caveats and recent changes

- ANNCSU became open recently. Its open data page says Implementing Regulation (EU) 2023/138 placed addresses among the high-value datasets, and that ISTAT and the Agenzia delle Entrate adopted new technical specifications on 12 December 2024. A press report of 26/02/2025 (https://www.lavoripubblici.it/news/stampa/35094) describes the services as active, with monthly lists and point services that take up changes daily. Older descriptions of ANNCSU as not downloadable or without coordinates no longer hold.
- Coordinates are present only where the municipality entered them. Official figures at 31/03/2026 (https://www.anncsu.gov.it/export/sites/anncsu/.allegati/Georeferenziazione-accessi-ANNCSU_31-MARZO.xlsx): 7,894 municipalities, 27,487,263 accesses, 18,417,502 with coordinates (67.0%), 4,304 municipalities fully georeferenced, 5,046 with at least one coordinate. The same file gives the figures per municipality.
- Coverage is uneven. In the Valle d'Aosta file of 2026-11-02, 19,248 of 94,256 rows (20.42%) have coordinates; 20 of 74 municipalities have at least one and 9 have all.
- Rows without coordinates stay in the file, so a row count is not a count of address points.
- No postcode field exists in the ANNCSU files.
- File format: semicolon-separated, decimal comma in the coordinates (for example `13,9961659;42,219746`), `COORD_X_COMUNE` is longitude. Coordinates are decimal degrees with 7 decimals in ETRF2000 at epoch 2008.0 (an ETRS89 realisation).
- The address file has 19 columns: `CODICE_COMUNE` (Belfiore code), `CODICE_ISTAT`, `PROGRESSIVO_NAZIONALE`, `CODICE_COMUNALE`, `ODONIMO`, `LOCALITA'`, `DIZIONE_LINGUA1`, `DIZIONE_LINGUA2`, `PROGRESSIVO_ACCESSO`, `CODICE_COMUNALE_ACCESSO`, `CIVICO`, `ESPONENTE`, `SPECIFICITA`, `METRICO`, `PROGRESSIVO_SNC`, `COORD_X_COMUNE`, `COORD_Y_COMUNE`, `QUOTA`, `METODO`. The published description (https://www.anncsu.gov.it/.allegati/metadata_indirizzario.json) documents only 18: it omits `LOCALITA'`, which is described in https://www.anncsu.gov.it/.allegati/metadata_stradario.json .
- `METODO` gives the coordinate method: 1 field survey with accuracy under 5 m, 2 field survey at 5 m or worse, 3 indirect derivation from a territorial database under 5 m, 4 indirect derivation at 5 m or worse, 5 derived through the municipalities' portal. The query API's help text gives an estimated accuracy of 2 m or worse for code 5.
- The national access id never changes, even when the civic number or street name does. Coordinates are not kept historically.
- The files include "SNC" accesses (senza numero civico, without a standard civic number) that municipalities entered in 2014-2016.
- The file name carries the creation date (`INDIR_ITA_20261102.csv`).
- The regional code `TREN` is the whole Trentino-Alto Adige region, not the Province of Trento.
- Licence: CC BY 4.0 is stated in the catalogue record (publisher Agenzia delle Entrate, 42 distributions, flagged high-value dataset, monthly) and in the press report, with citation of the source required. The ANNCSU site's own open data and download pages carry no licence statement.
- A third-party slide of July 2025 gives "4.9% with coordinates" without a reference date. It does not fit the official 67.0% at March 2026, so no growth rate should be read from it.
- OpenAddresses' Italian layer rests on the ANNCSU file of 2026-07-03; its later runs did not succeed.
- Bologna's municipal file carries both a postcode and the ANNCSU code, so it can be joined to the national file.
- The Poste Italiane statement on CAP data dates from June 2019; current prices and terms were not examined.
- Lombardia: data.europa.eu lists per-municipality datasets "Rete stradale - Numeri civici esterni georeferenziati" (road network - georeferenced external civic numbers) by Regione Lombardia under CC0.

### Not free or not available

- Bulk postcode (CAP) data: not free. Poste Italiane states that the CAP database is its property and cannot be downloaded free of charge. No open bulk CAP dataset was found; the GISCO Address API returns a CAP per address, as a lookup only.
- Coordinates for about a third of ANNCSU accesses (official figure at 31/03/2026): not in the file.
- Region-wide open address datasets for Veneto and the Province of Trento: none found (see the regional table).
- The list of municipalities that have not finished loading streets and civic numbers into ANNCSU: the site fills it in by script and it was not read.

### Could not be verified

- Counts in the national file of 2026-11-02: 27,413,752 rows, 20,728,959 (75.62%) with coordinates, 818,455 SNC rows, 7,891 municipality codes (5,502 with at least one coordinate, 4,454 with all), and the split by method (10,892,898 method 4; 7,118,388 method 3; 1,721,955 method 1; 705,060 method 5; 290,658 method 2). These are a researcher's count; the 336 MB file was not downloaded a second time. The official March 2026 figures above are consistent with the trend.
- Rate limits or terms of use for `querydata.php`: none were found, and the question was not examined a second time.
- Emilia-Romagna: that the DBTR civic numbers can be downloaded from the geoportal page, which returned HTTP 500.
- Piemonte: the publisher's licence for BDTRE addresses. CC BY 4.0 is OpenAddresses' record only.
- Lombardia: the per-province packages; the URL timed out after 45 s.
- Umbria: the ArcGIS service; the certificate does not match the host name.
- Sardegna: the geoportal page; empty reply from the server.
- Bologna: the licence (given as CC BY 4.0) is not in the API response.
- Alto Adige: the publisher's own licence statement; CC0 is OpenAddresses' record.
- Toscana: whether the ITER.NET package contains civic numbers.
- Liguria: what `civici.zip` contains.
