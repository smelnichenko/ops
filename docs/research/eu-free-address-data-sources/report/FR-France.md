## France (FR)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | Base Adresse Nationale (BAN) | Bulk CSV, no registration | Licence Ouverte 2.0 | Yes; WGS84 lon/lat plus local projected x/y | Yes | Daily |

**In short.** Use the Base Adresse Nationale (BAN, "National Address Base"): one national CSV of about 945 MB, rebuilt every day, downloadable without an account under Licence Ouverte 2.0. For geocoding, call the Géoplateforme at `data.geopf.fr/geocodage`; the old host `api-adresse.data.gouv.fr` still answers but is past its announced sunset of 31 January 2026 and must not be used for new work. The likeliest trap is the `x`/`y` columns: they are Lambert-93 only in metropolitan France and local UTM overseas, so load `lon`/`lat` instead.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Base Adresse Nationale (BAN), national and per-département CSV | IGN operates and distributes it, under the responsibility of DINUM; data.gouv.fr organisation "Base Adresse Nationale" | Download page: https://adresse.data.gouv.fr/outils/telechargements ; file listing: https://adresse.data.gouv.fr/data/ban/adresses/latest ; national file: https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/adresses-france.csv.gz ; dataset record: https://www.data.gouv.fr/datasets/base-adresse-nationale | 26,122,628 addresses in 35,011 communes (publisher's live counter, 11 Nov 2026). Per row: house number, suffix, street, postcode, INSEE commune code, x/y, lon/lat, position type, postal delivery label, certification flag, cadastral parcel ids. One position per address | Bulk download, no login. National file 945,276,393 bytes on 11 Nov 2026. Folders `csv`, `csv-with-ids` (1.83 GB), `csv-bal` (1.43 GB), `csv-bal-with-lang`, `addok` | Licence Ouverte / Open Licence 2.0 | Daily; one archive per week kept for a year, one per month before that | confirmed |
| Bases Adresses Locales (BAL, "local address bases"), the communes' source files | Communes, through adresse.data.gouv.fr | https://adresse.data.gouv.fr/outils/telechargements (the files sit on each commune's page) | The file each commune publishes in BAL format; the BAN is built from these | Per-commune download, as stated on the download page | Not stated separately | Not stated | confirmed (statement on the page; no commune page was opened) |
| BAN PLUS | IGN | https://cartes.gouv.fr/rechercher-une-donnee/dataset/IGNF_BAN-PLUS | Link tables: address to building, address to parcel, building to parcel, address to road support, plus the BAN points. Replaces the former "Adresse PREMIUM" offer | Shapefile; no public access restriction stated in the catalogue record | Licence Ouverte (compatible ODC-BY, CC-BY 2.0) | Quarterly, with BD TOPO; publication dates from 2022-12-15 to 2026-09-15 | corrected |
| Référentiel National des Bâtiments (RNB, "national building register") | Publisher not named in the material read; listed on data.gouv.fr | Record: https://www.data.gouv.fr/api/1/datasets/referentiel-national-des-batiments/ ; national export: https://rnb-opendata.s3.fr-par.scw.cloud/files/RNB_nat.csv.zip ; documentation: https://rnb-fr.gitbook.io/documentation/api-et-outils/export-national-et-departemental | Buildings, not addresses: `rnb_id`, point and shape (WGS84, EWKT), status, external ids, the list of known addresses (each with at least the BAN interoperability key), parcels | CSV, one export per département plus a national file of about 11.7 GB zipped | Licence Ouverte 2.0 | Declared weekly; the national file was dated 2026-10-19 on 11 Nov 2026 | confirmed |
| Base officielle des codes postaux ("official postcode base", Hexasmal) | La Poste | Record: https://www.data.gouv.fr/datasets/base-officielle-des-codes-postaux ; CSV: https://data.laposte.fr/data-fair/api/v1/datasets/laposte-hexasmal/metadata-attachments/base-officielle-codes-postaux.csv ; portal record: https://data.laposte.fr/data-fair/api/v1/datasets/laposte-hexasmal | Commune-to-postcode table, 39,192 rows (publisher's figure): INSEE code, commune name, postcode, delivery label, line 5. The CSV export adds a commune centroid. No addresses | CSV, no login, 4,146,942 bytes | Licence Ouverte / Open Licence 2.0 | Portal data updated 8 Nov 2026 | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for France | API, no key; 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definitions: https://github.com/openaddresses/openaddresses/tree/master/sources/fr | Copy of the BAN, one source folder per département (104 entries) | Free download, needs a logged-in account | Follows the source | The BAN is pushed to it once a week (publisher's statement) | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Address points for France | GeoParquet, no account | Set per country; not recorded here | Per release | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **Géoplateforme geocoding (IGN).** `https://data.geopf.fr/geocodage/search` and, under the same base, `/reverse`, `/getCapabilities`, `/openapi` and `/openapi.yaml`. No key. Documented limit: 50 requests per second per IP address. Guide: https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/geocodage/
- A keyless call such as https://data.geopf.fr/geocodage/search?q=8+bd+du+port+amiens&limit=1 returns a house-number feature with `banId`, `postcode`, `citycode`, `x`/`y` and lon/lat. The service has three indexes: `address`, `poi`, `parcel`.
- **Batch geocoding.** A CSV of less than 50 MB or 200,000 lines is geocoded synchronously. Larger files, up to 1 GB, go through an asynchronous project that needs a Géoplateforme account and OAuth2 credentials (contact geoplateforme@ign.fr).
- **WFS.** Layer `BAN.DATA.GOUV:ban` at `https://data.geopf.fr/wfs/ows`, no key; it reported 26,120,609 features on 11 Nov 2026. The download page says the WFS and WMS are updated "bi-hebdomadaire" (twice a week).
- **WMS.** Layer `BAN.DATA.GOUV`, same update rhythm.
- **Vector tiles (MVT).** Updated in real time; listed on https://adresse.data.gouv.fr/outils/telechargements
- **BAN statistics.** https://plateforme.adresse.data.gouv.fr/ban/stats returns the live counters as JSON.

### Caveats and recent changes

- **The geocoding API moved from DINUM to IGN.** A data.gouv.fr post of 3 April 2025 (https://www.data.gouv.fr/posts/lapi-adresse-de-la-base-adresse-nationale-est-transferee-a-lign-10) set 30 June 2025 as the target for the full traffic transfer and kept the old domain "jusqu'à janvier 2026". The new service is described as "iso fonctionnel" and adds POI and cadastral-parcel search.
- **The old host is still alive, past its sunset.** On 11 Nov 2026 `https://api-adresse.data.gouv.fr/search/` still returned HTTP 200 with JSON. Its headers carry `deprecation` and `sunset: Sat, 31 Jan 2026 22:59:59 GMT`, `x-api-deprecated: true`, `x-infra: gpf` and a notice that the URL will be decommissioned. Use `data.geopf.fr` only.
- **`x`/`y` are not one projection.** They are in the local legal projection: Lambert-93 in metropolitan France, local UTM overseas (a Réunion address has x 338805.95, y 7690488.36). The CSV does not name the projection. `lon`/`lat` are uniform.
- **Quality is uneven.** 23,263,076 addresses come from the BALs of 29,018 communes. 2,859,552 addresses (10.9%) in 5,993 communes are still "assemblage", computed from other sources, and only 72,650 of those are certified. In total 19,576,730 addresses are certified by their commune (publisher's live counters, 11 Nov 2026).
- **Directory URLs.** Use listing paths without a trailing slash; the form with a slash answers 308.
- **CSV details.** The separator is a semicolon; the "CSV historique" file has 23 columns. The download page offers CSV and Addok JSON only; no GeoPackage or shapefile of the BAN itself.
- **A stale folder.** `https://adresse.data.gouv.fr/data/adresses-locales/latest/csv` still resolves, but its files are dated 17/10/2023. Do not import from it.
- **Old IGN documentation links** under `geoservices.ign.fr` redirect to cartes.gouv.fr (geocoding guide and BAN PLUS).
- **La Poste.** The old portal host `datanova.laposte.fr` fails TLS with an expired certificate. The data.gouv.fr record of the postcode base shows a last update of 2023-07-09 and a half-yearly rhythm, while the file on data.laposte.fr was updated on 8 Nov 2026; take the file from data.laposte.fr.
- **Rate-limit headers.** Both geocoding hosts send `x-ratelimit-limit-second: 1` next to `ratelimit-limit: 50`. Only the 50 per second is documented.
- **Maintenance notice.** On 11 Nov 2026 the download page announced a service interruption for security maintenance on "mercredi 11 novembre"; requests made that day were served.
- **High-Value Dataset tags.** The BAN, the RNB and BAN PLUS are flagged `hvd`; the BAN is also tagged as reference data (`spd`).

### Not free or not available

- **Postcode boundaries.** La Poste states that the geographic contours of postcodes are not provided as open data.
- **Geocoding files over 50 MB or 200,000 lines** need a Géoplateforme account and OAuth2 credentials; the keyless service does not take them.
- **Cadastre address extract.** `https://cadastre.data.gouv.fr/datasets/adresses-cadastre` returns 404; no current cadastre-derived address file was found.

### Could not be verified

- **A CNIG document of June 2026** (https://cnig.gouv.fr/IMG/pdf/cnig_gt_assurances_19062026.pdf) is said to carry the heading "URL API Adresse décommissionnée fin janvier 2026". The PDF exists (5,009,213 bytes) but its text was not read.
- **Which rate limit is enforced.** The meaning of the `x-ratelimit-limit-second: 1` header is undocumented and was not tested with a burst of requests.
- **Effect of the EU High-Value Datasets regulation on the BAN** beyond the tag: no publisher statement was looked for.
- **Postcodes inside the BAN.** That the postcode column carries no licensing condition of its own, separate from the BAN licence, was not checked.
