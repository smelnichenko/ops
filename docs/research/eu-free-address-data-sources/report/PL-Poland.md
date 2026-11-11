## Poland (PL)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | PRG address points (GUGiK) | Bulk SHP or GML zip, no registration | No named licence; "free of charge and for any use" | Yes, EPSG:2180 | Yes | Continuous at source; file schedule not stated |

**In short.** Use the address points of the *Państwowy Rejestr Granic* (PRG, State Register of Borders) from the surveying office GUGiK: one national zip in SHP (564 MB) or GML (805 MB), no login, about 8.64 million points with house number, postcode, TERYT codes and EPSG:2180 coordinates. The same data can be queried without a key through a WFS, an OGC API Features service and a geocoder. The likely trip-up is the national SHP zip itself: it is compressed with deflate64 (some unzip tools cannot open it), its attribute table is 7.07 GB (above the classic 2 GB dBase limit) and the national address layer has no `.cpg` encoding file. There is no licence text, only GUGiK's sentence that the data is free "for any use".

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| PRG address points, national SHP | Główny Urząd Geodezji i Kartografii (GUGiK) | https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/POLSKA.zip | Four layers: 8,640,975 address points, 297,609 streets, 8,619 squares, 68,403 localities (computed from the index files of the 10 Nov 2026 archive). Address fields: `ID_IIP`, `NUMER_PORZ` (house number), `KOD_POCZT` (postcode), `DATA_NAD`, `NAZWA_ULC` (street), `ID_ULIC`, `NAZWA_GMI`, `TERYT_GMI`, `NAZWA_MSC` (locality), `ID_SIMC`. CRS EPSG:2180 | Anonymous download, 564,312,601 bytes | No named licence; GUGiK: "free of charge and for any use" | File last modified 10 Nov 2026 | confirmed |
| PRG address points, national GML | GUGiK | https://opendata.geoportal.gov.pl/prg/adresy/PRG-punkty_adresowe.zip | 16 GML files, one per voivodeship, stamped 10.11.2026; 10.78 GB uncompressed | Anonymous download, 804,643,553 bytes | Same | File last modified 10 Nov 2026 | confirmed |
| PRG address points, per-voivodeship SHP | GUGiK | https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/14/14.zip (Mazowieckie) and https://opendata.geoportal.gov.pl/prg/adresy/PunktyAdresowe/16/16.zip (Opolskie) | Same layers per voivodeship; the path uses the two-digit TERYT voivodeship code. Opolskie: 230,984 address points, 9,728 streets, 1,437 localities, 257 squares; `.cpg` says UTF-8 | Anonymous download; 86.7 MB and 15.9 MB | Same | Both last modified 10 Nov 2026 | confirmed (these two files) |
| PRG page (description, licence wording, download links) | GUGiK | https://www.geoportal.gov.pl/pl/dane/panstwowy-rejestr-granic-prg/ | Says PRG includes addresses and their location, fed from the municipalities' address records; lists SHP and GML only | Web page | Carries the sentence "Dane PRG są dostępne bezpłatnie i do dowolnego wykorzystania" | - | confirmed |
| Municipal address datasets (Kielce "Punkty adresowe", "Adresy m.st. Warszawy") | Cities, on dane.gov.pl | dane.gov.pl datasets 4919 and 469; no file URL recorded | Kielce: GeoPackage, GeoJSON, Parquet. Warsaw: not recorded | Not tested; dane.gov.pl timed out | Not recorded | Not recorded | unverified (catalogue records only) |
| Official List of Postal Address Numbers (PNA), PDF | Poczta Polska | https://www.poczta-polska.pl/wp-content/uploads/2024/05/spispna.pdf (listed on https://www.poczta-polska.pl/en/dla-biznesu/oferta/uslugi-pozostale/pocztowe-numery-adresowe/) | Postcode list as a PDF, 7,894,567 bytes | Anonymous download | None stated on the page | File last modified 12 Oct 2026 | confirmed |
| TERYT full files (TERC, SIMC, ULIC) | GUS (statistical office) | https://eteryt.stat.gov.pl/eTeryt/rejestr_teryt/udostepnianie_danych/baza_teryt/uzytkownicy_indywidualni/pobieranie/pliki_pelne.aspx | Identifier catalogues of territorial units, localities and streets, in basic, address and statistical versions. No house numbers or coordinates by catalogue definition | Web form downloads (page post-backs) | Not recorded | Not recorded | confirmed (page only; no file opened) |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Poland | No key; lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io (source definitions: https://github.com/openaddresses/openaddresses/blob/master/sources/pl/mazowieckie.json) | PRG address points, 16 sources, one per voivodeship, pulled from the live per-voivodeship zips | Free download, needs a logged-in account | Recorded as "Polish Law on Geodesy and Cartography of 17 May 1989", attribution not required, no share-alike | All 16 processed 2026-10-30 | confirmed |
| Overture Maps addresses | Overture Maps Foundation | https://docs.overturemaps.org/guides/addresses/ | 8,628,514 Polish addresses in release 2026-10-21.0 (publisher's figure) | GeoParquet, no account | Listed as "No conditions to access and use" | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **Address WFS, no key:** https://mapy.geoportal.gov.pl/wss/ext/wfs/KrajowaIntegracjaNumeracjiAdresowej . Feature types `adresyUlice:A07_Punkty_adresowe` and `adresyUlice:A08_Ulice`, default CRS EPSG:2180, attributes include `KOD_POCZTOWY`. It reported 8,641,300 address points on 11 Nov 2026. Capabilities state fees "no conditions apply" and access constraints "otherRestrictions". GUGiK lists it at https://www.geoportal.gov.pl/pl/usluga/uslugi-pobierania-wfs/ .
- **INSPIRE Addresses WFS:** https://mapy.geoportal.gov.pl/wss/service/INSPIRE/Addresses . Feature type `ms:AD.Address`; capabilities state "No fees" and "No constraints". Only the capabilities document was read.
- **OGC API Features, no key, launched 2026-09-25:** https://ogcapi.geoportal.gov.pl/res/ims/maps/prg_ad/apiFeatures . Collections `PunktAdresowy` and `Ulica`, HTML and JSON, CRS84 with storage CRS EPSG:2180; 8,641,300 address points matched on 11 Nov 2026. The `self` and `next` links in replies point at the host `ogcapitest.geoportal.gov.pl`.
- **Geocoder UUG (*Uniwersalna Usługa Geokodowania*), no key:** https://services.gugik.gov.pl/uug/ , documentation https://services.gugik.gov.pl/uug/opis.html . HTTP GET, JSON. Requests: `GetAddress`, `GetAddressReverse` (WKT point with `srid` 4326 or 2180), `GetAddresses`, `GetCity`, `GetStreet`, `GetRoadMarker`, `GetLevelCrossing`, `GetLocation`, `GetRoads`. A test address returned city, street, number, TERYT, SIMC and ULIC codes, postcode and x/y in EPSG:2180, with `"max results limit":15`; a reverse lookup returned the nearest address within `"radius":100`. Requests to `/uug?...` are redirected (301) to `/uug/?...`.
- **WMS with address points and streets (map images):** https://mapy.geoportal.gov.pl/wss/ext/KrajowaIntegracjaNumeracjiAdresowej . Layers `A07_Punkty_adresowe`, `A08_Ulice`; fees "no conditions apply", access constraints "otherRestrictions".
- **Package links per municipality, county or voivodeship:** the PRG page says they are served through the geoportal map ("Dane do pobrania") and through WMS GetFeatureInfo at https://integracja.gugik.gov.pl/cgi-bin/PanstwowyRejestrGranic . No such request was made.
- **Old download links still redirect (302):** https://integracja.gugik.gov.pl/PRG/pobierz.php?adresy_zbiorcze_gml goes to the GML zip; the same script with `?adresy_zbiorcze_shp` goes to https://opendata.geoportal.gov.pl/prg/adresy/PRG-punkty_adresowe_shp.zip (564,312,601 bytes, same date as `POLSKA.zip`).
- **TERYT web service "ws1" (GUS):** https://api.stat.gov.pl/Home/TerytApi?lang=en . Free, XML, covers TERC, SIMC and ULIC and verifies addresses down to street level. It needs an account, requested by e-mail to teryt_ws1@stat.gov.pl.
- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key, lookup only.

### Caveats and recent changes

- The national SHP zip is a zip64 archive compressed with deflate64 (method 9), which some unzip tools cannot inflate. Its address `.dbf` is 7,068,317,904 bytes uncompressed. The national address layer has no `.cpg` file, although the other three national layers have one; the Opolskie package's `.cpg` says UTF-8.
- The address points have no flat or unit field: the ten attributes listed above are all there is.
- PRG addresses come from the municipalities (gminas) and are updated at source as municipalities change their records. GUGiK publishes no regeneration schedule for the download files; on 11 Nov 2026 every file checked was dated 10 Nov 2026.
- Counts differ slightly by route: 8,640,975 points in the 10 Nov 2026 file, 8,641,300 from the live WFS and OGC API on 11 Nov 2026.
- Quality varies by municipality. The OpenStreetMap wiki says supply "may range from excellent to 'no data supplied, despite legal obligation'" (https://wiki.openstreetmap.org/wiki/Pa%C5%84stwowy_Rejestr_Granic , page last edited 29 January 2023).
- Formats are SHP and GML only. There is no archive of past address data; the archives on the PRG page (2005-2025) hold boundaries only.
- Licence basis: GUGiK's sentence on the PRG page, and Art. 40a(2)(1)(a) of the Geodetic and Cartographic Law, which says no fee is charged for PRG datasets (https://api.sejm.gov.pl/eli/acts/DU/2024/1151/text.html). No Creative Commons or other named licence appears on the PRG page.
- The UUG and OGC API pages publish no key requirement, rate limit or terms of use: none found on the UUG landing and documentation pages, the OGC API landing page, the launch notice (https://www.geoportal.gov.pl/aktualnosci/nowe-uslugi-ogc-api-features-dla-danych-prg-i-prng/) or the WFS list page.
- UUG's documentation gives a default `accuracy` of 0.6 (range 0.5-1.0), but a live reply reported `"min accuracy limit":0.4`.
- The free Poczta Polska PDF sits under a `2024/05` path but was last modified on 12 Oct 2026.
- High-value datasets: on data.europa.eu, 0 of 26,701 Polish datasets carry the high-value flag (11 Nov 2026). GUGiK's PRG dataset (dane.gov.pl dataset 726) and "Adresy INSPIRE (AD)" (dataset 672; WFS, ATOM and WMS distributions; modified 2024-03-19) are listed, seen through data.europa.eu's copy of the dane.gov.pl catalogue, without the flag. The OGC API launch notice does not mention high-value datasets.

### Not free or not available

- **Poczta Polska postcode list in electronic form:** sold in its online shop and as an annual subscription (PDF, TXT, XLS, quarterly updates). Postal operators get access under a written agreement, for a fee set in a price list. A third-party review describes it as a commercial product for the customer's own use with no resale (https://datahub.io/logistics/postal-codes-pl/.licensing-notes). Only the PDF is free.
- **TERYT:** street and locality identifiers only, no house numbers. Its web service needs an account.
- **CSV or GeoPackage of PRG addresses:** not offered.
- **Flat or unit numbers:** not in the PRG address points.

### Could not be verified

- That PRG holds exactly one point per house number: this needs the full national file, which was not downloaded.
- That the download files are regenerated daily: the dates fit, but no schedule is published.
- How completely municipalities fill the postcode field: not measured.
- That commercial reuse is allowed without attribution: there is no licence text. It rests on GUGiK's "for any use" sentence, the statute, and the terms OpenAddresses and Overture record.
- Whether the TERYT building catalogue (NOBC) can be downloaded: it is not on the eTERYT full-files page and no other route was tried.
- Contents of the TERYT files, and the ws1 endpoint addresses and terms: no file or manual was opened.
- Poczta Polska's own licence wording for the free PDF: not on its PNA page.
- Anything on dane.gov.pl itself, including the Kielce and Warsaw address datasets: the portal and its API timed out on 11 Nov 2026, so only data.europa.eu's records of them were seen.
- Undocumented throttling on UUG, the WFS or the OGC API: unknown.
