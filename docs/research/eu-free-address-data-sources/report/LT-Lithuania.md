## Lithuania (LT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Adresų registras files on registrucentras.lt (Registrų centras) | Bulk CSV and GeoJSON, no registration | CC BY 4.0 | Yes, in a separate file; EPSG:3346 not rechecked there | Yes | Monthly |

**In short.** Download the files of the Lietuvos Respublikos adresų registras (Address Register of the Republic of Lithuania) straight from registrucentras.lt: anonymous, CC BY 4.0, monthly. House numbers and postcodes are in one file and coordinates in another; the two join on the address code `AOB_KODAS`, and street names come from a third file. The trap is the copies: on data.gov.lt one attached spatial file dates from 2021, the address-point model in the portal's API is empty, and the INSPIRE copy carries a no-derivatives licence tag. Use the registrucentras.lt files.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Addresses given to land parcels and buildings, text file `adr_stat_lr.csv` | Valstybės įmonė Registrų centras (State Enterprise Centre of Registers) | File: https://www.registrucentras.lt/aduomenys/?byla=adr_stat_lr.csv ; catalogue record: https://data.gov.lt/datasets/1342/ | Pipe-delimited, UTF-8. Columns `SAV_KODAS\|AOB_KODAS\|GYV_KODAS\|GAT_KODAS\|NR\|KORPUSO_NR\|PASTO_KODAS\|AOB_NUO`: among them the address code (`AOB_KODAS`), settlement code (`GYV_KODAS`), street code (`GAT_KODAS`), house number (`NR`), block number (`KORPUSO_NR`) and postcode (`PASTO_KODAS`, format LT-85113). 1,132,892 rows (researcher's count, not recounted) | Anonymous, HTTP 200 | CC BY 4.0 | Monthly per the catalogue record | confirmed |
| Address points, spatial file `adr_gra_adresai_LT.zip` | Registrų centras | File: https://www.registrucentras.lt/aduomenys/?byla=adr_gra_adresai_LT.zip ; catalogue record: https://data.gov.lt/datasets/1351/ | The spatial address data (GeoJSON in a zip). The download answers HTTP 200 as `application/zip`; the archive's content was not rechecked | Anonymous, HTTP 200 | CC BY 4.0 | Catalogue record says yearly ("Kasmet"); the sibling streets file on the same server was generated 2026-11-03 | confirmed (content unverified) |
| Premises addresses `adr_pat_lr.csv` | Registrų centras | https://www.registrucentras.lt/aduomenys/?byla=adr_pat_lr.csv | Apartment-level file. Columns `SAV_KODAS\|PAT_KODAS\|AOB_KODAS\|PATALPOS_NR\|PAT_NUO`. 1,190,947 rows (researcher's count, not recounted) | Anonymous, HTTP 200 | CC BY 4.0 | Monthly | confirmed |
| Streets `adr_gatves.csv` and street centre lines `adr_gra_gatves.json` | Registrų centras | https://www.registrucentras.lt/aduomenys/?byla=adr_gatves.csv ; https://www.registrucentras.lt/aduomenys/?byla=adr_gra_gatves.json | `adr_gatves.csv`: columns `GAT_KODAS\|TIPAS\|TIPO_SANTRUMPA\|VARDAS_K\|GYV_KODAS\|GAT_NUO`, 2,736,369 bytes, 60,444 rows, newest `GAT_NUO` 2026-10-29. `adr_gra_gatves.json`: GeoJSON LineString features with GAT_KODAS, GAT_PAV, GYV_KODAS; CRS EPSG:3346; `formav_dat` 2026-11-03 | Anonymous, HTTP 200 | CC BY 4.0 | Monthly | confirmed |
| Copy on the national geoportal | Statybos sektoriaus vystymo agentūra (catalogue record data.gov.lt dataset 3160) | https://www.geoportal.lt/download/opendata/RC/RC_adresai_atviri_duomenys.zip | A zip of the Registrų centras open address data. Not opened | Anonymous, HTTP 200 | Not stated in the material read | Catalogue record modified 2026-11-08 | confirmed |
| INSPIRE Annex I Addresses, download service | Viešoji įstaiga Statybos sektoriaus vystymo agentūra | Catalogue record: https://data.gov.lt/datasets/3516/ ; file: https://inspire-geoportal.lt/resources/atom/ad/data/AnnexI_Addresses.zip (redirects to https://www.inspire-geoportal.lt/resources/atom/ad/data/AnnexI_Addresses.zip) | INSPIRE addresses, 111,435,789 bytes zipped. Not opened | Anonymous, HTTP 200 after the redirect | Creative Commons Attribution-NoDerivatives 4.0 | Monthly per the record; file last modified 2026-10-12. The record says to contact Registrų centras for the most current data | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for Lithuania | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Lithuania countrywide | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lt/countrywide.json | Built from the geoportal.lt zip. A separate Vilnius city source also exists | Free download, needs a logged-in account | CC BY 4.0, attribution "Registrų centras" | Not stated | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Lithuania is among the 19 EU countries covered | No account, GeoParquet | Per country | Release 2026-10-21.0 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Free download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **data.gov.lt open data store** ("Saugyklos API", get.data.gov.lt), output as JSON, JSONL, RDF and CSV. The building-address model https://get.data.gov.lt/datasets/gov/rc/ar/pastatas/Pastatas returns records with `nr`, `korpuso_nr`, `pasto_kodas`, `aob_nuo` and references to street, settlement and municipality; `?count()` gives 1,123,119. No key. The address-point model https://get.data.gov.lt/datasets/gov/rc/ar/adresotaskas/AdresoTaskas?count() returns 0, so the store has no coordinates for addresses.
- **INSPIRE download file** (https://www.inspire-geoportal.lt/resources/atom/ad/data/AnnexI_Addresses.zip): keyless, but see the licence tag below.
- **GISCO Address API** (https://gisco-services.ec.europa.eu/addressapi): keyless lookup, 1,000-row cap.
- A keyless national address-search or geocoding API: none identified. The register's own real-time service is restricted (see "Not free or not available").

### Caveats and recent changes

- **Three files make one address table.** `adr_stat_lr.csv` has the house number, block number and postcode; the address-point file has the coordinates; they join on `AOB_KODAS`. Street names come from `adr_gatves.csv` on `GAT_KODAS`. Apartments come from `adr_pat_lr.csv`, also on `AOB_KODAS`. Settlement, municipality and county files exist in the catalogue but were not probed.
- **Use the registrucentras.lt files, not the portal copies.** The file attached directly to the portal's spatial dataset (https://data.gov.lt/datasets/1351/, 373,858,286 bytes) is dated 2021-08-25. The store's building-address count did not change although its distribution is marked updated 2026-08-20, so the store copy is not refreshed monthly. The address-point model in the store is empty.
- The catalogue entry for the spatial address dataset says it is updated yearly, while the text datasets say monthly. The streets file on registrucentras.lt carried the generation date 2026-11-03.
- **Licence tags differ between copies.** The Registrų centras datasets are Creative Commons Attribution 4.0, access "Vieši" (public), status "Atvertas" (opened). The INSPIRE Addresses entry, published by another body, is tagged Attribution-NoDerivatives 4.0.
- The INSPIRE zip (last modified 2026-10-12) is older than the registrucentras.lt files seen (generated 2026-11-03).
- The download server `www.registrucentras.lt/aduomenys/` sends no `Content-Length` and ignores `Range` requests. A download cannot be resumed or sized in advance.
- registrucentras.lt itself is a JavaScript application; old open-data pages such as https://www.registrucentras.lt/p/1186 return an empty shell to a plain HTTP client. The file URLs above work directly.
- data.gov.lt answered HTTP 429 to a request that followed redirects automatically; one request per call worked. The portal's CSV link https://data.gov.lt/datasets/1342/distribution/14759/download/ only redirects to the registrucentras.lt file.
- The register is catalogued on data.gov.lt as about twenty datasets (counties, municipalities, elderships, settlements, streets, historic streets and settlements, parcel and building addresses, premises addresses, as text and as spatial data, plus monthly statistics): https://data.gov.lt/datasets/?q=Adres%C5%B3+registro
- High-value datasets: the address datasets sit in the portal group "Didelės vertės rinkiniai" (high-value datasets), and data.europa.eu flags them `is_hvd: true`.
- The register's open data dates from October 2020; the spatial dataset's period field starts on 20 October 2020.
- Contact for the open data: atviriduomenys@registrucentras.lt

### Not free or not available

- The continuously updated web service that returns addresses with coordinates (`https://www.registrucentras.lt/adrws/rest/get`, XML; catalogue record https://data.gov.lt/datasets/4085/, created 2026-01-16): access rights are marked "Apriboti" (restricted). Who may use it and at what cost was not found.
- A current address-point dataset through the data.gov.lt store API: not available (count 0).
- No paid address product was found; the register dumps are free and anonymous.

### Could not be verified

- Sizes and row counts of the large files, because the server gives no `Content-Length` and ignores `Range`:
  - `adr_stat_lr.csv`: 56,992,530 bytes, 1,132,892 rows, 1,132,710 with a postcode, newest registration date 2026-10-30 (researcher's count);
  - `adr_pat_lr.csv`: 43,834,598 bytes, 1,190,947 rows (researcher's count); `adr_gra_gatves.json`: 49 MB.
- The content of `adr_gra_adresai_LT.zip`: 62,555,111 bytes, holding `adr_gra_adresai_LT.json` (444,173,555 bytes, dated 2026-11-03), CRS EPSG:3346, about 1,132,891 point features with AOB_KODAS, GYV_KODAS, GAT_KODAS, X_KOORD, Y_KOORD, PASTO_KODA and E_KOORD/N_KOORD (WGS84 degrees). The archive cannot be inspected without downloading it in full, and it was not re-opened. Indirect support only: the sibling streets file declares EPSG:3346 and the generation date 2026-11-03.
- The figure of 1.13 million address points. A related live count was seen: 1,123,119 building-address records in the data.gov.lt store.
- The licence wording on registrucentras.lt itself: the site is JavaScript-only. CC BY 4.0 is taken from the data.gov.lt records.
- Other files under `/aduomenys/`: there is no directory listing and they were not enumerated.
- Postcode ownership (Lietuvos paštas, the postal operator) and any separate postal file: not checked. Postcodes are in the register data.
- A historic address-point file in the open data: none was seen, but the files were not enumerated. Historic streets and settlements are published.
- Figures for the 2020 opening (over 2.1 million unique addresses, over 1 million address points, data as of 1 October 2020): not in the source cited for them.
- The contents of the geoportal.lt zip and of the INSPIRE file: neither was opened.
