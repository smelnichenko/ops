# Free online address data sources: France, Belgium, Netherlands, Luxembourg, Ireland (state as of 11 November 2026)

Method note: "direct request" means I requested the URL myself on 10-11 November 2026 (HTTP status, headers, file size, or file content). "Search snippet" means the claim comes from a search-result summary of the page and I could not open the page itself; treat those as weaker. Row counts are my own counts of the downloaded files. Requests were sent without login, cookies or keys. Two batches on 11 Nov went out with a browser-style User-Agent string; every endpoint status quoted below from those batches was re-requested afterwards with a plain client identifier and gave the same result.

## France

### Takeaway
France has a fully open national register, the Base Adresse Nationale (BAN): about 26.1 million addresses, daily CSV dumps with no registration, Licence Ouverte 2.0, tagged as an EU High-Value Dataset. The geocoding API has moved to IGN's Géoplateforme (`data.geopf.fr/geocodage`); the old `api-adresse.data.gouv.fr` host still answered on 11 Nov 2026 but carries a sunset date of 31 Jan 2026.

### Cited Findings

**Authoritative register and publisher**
- The register is the Base Adresse Nationale (BAN, "National Address Base"). The data.gouv.fr dataset is owned by the organisation "Base Adresse Nationale"; operation and distribution are done by IGN under the responsibility of DINUM. Licence: "Licence Ouverte / Open Licence version 2.0". Dataset last updated 9 Nov 2026. — [data.gouv.fr dataset](https://www.data.gouv.fr/datasets/base-adresse-nationale)
- The dataset carries the tags "High value datasets" and "Reference data public service" on data.gouv.fr. — [data.gouv.fr dataset](https://www.data.gouv.fr/datasets/base-adresse-nationale)
- Official download page: https://adresse.data.gouv.fr/outils/telechargements. Site content is under "licence etalab-2.0" unless third-party rights are stated. — [adresse.data.gouv.fr downloads](https://adresse.data.gouv.fr/outils/telechargements)

**Bulk download (no registration)**
- Three daily file families: "CSV historique" (`/data/ban/adresses/latest/csv`), "CSV avec identifiants BAN" (`/latest/csv-with-ids`), and Addok (`/latest/addok`); national and per-département files; one position per address. Archives: one version per week kept for the last year, one per month before that. — [adresse.data.gouv.fr downloads](https://adresse.data.gouv.fr/outils/telechargements)
- The `latest` directory also holds `csv-bal` and `csv-bal-with-lang` folders (BAL-format exports). — [directory listing, direct request](https://adresse.data.gouv.fr/data/ban/adresses/latest/)
- National file `adresses-france.csv.gz`: HTTP 200 without any login, 945,177,341 bytes, Last-Modified 10 Nov 2026 01:59:57 GMT. — [direct request](https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/adresses-france.csv.gz)
- Other national files listed on 10 Nov 2026: `adresses-with-ids-france.csv.gz` 1.83 GB — [listing](https://adresse.data.gouv.fr/data/ban/adresses/latest/csv-with-ids/); BAL-format `adresses-france.csv.gz` 1.43 GB — [listing](https://adresse.data.gouv.fr/data/ban/adresses/latest/csv-bal/); `lieux-dits-beta-france.csv.gz` 8.03 MB and per-département files such as `adresses-75.csv.gz` 6.36 MB — [listing](https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/)
- Record count: the BAN statistics endpoint reports 26,120,990 addresses, of which 19,575,905 certified by the commune; 35,011 communes covered; 24,798,451 addresses carry a BAN id. — [BAN stats, direct request](https://plateforme.adresse.data.gouv.fr/ban/stats)
- Formats are CSV and Addok JSON only; the download page lists no GeoPackage/shapefile. — [adresse.data.gouv.fr downloads](https://adresse.data.gouv.fr/outils/telechargements)

**Content**
- CSV header (semicolon-separated): `id;id_fantoir;numero;rep;nom_voie;code_postal;code_insee;nom_commune;code_insee_ancienne_commune;nom_ancienne_commune;x;y;lon;lat;type_position;alias;nom_ld;libelle_acheminement;nom_afnor;source_position;source_nom_voie;certification_commune;cad_parcelles`. Sample row: `75104_9191_00036;75104_9191;36;;Rue du Temple;75004;75104;Paris 4e Arrondissement;;;652624.25;6862372.14;2.354278;48.859641;parcelle;...;commune;commune;1;75104000AG0084`. — [adresses-75.csv.gz, direct download](https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/adresses-75.csv.gz)
- So each row has house number + suffix (`rep`), street, postcode, INSEE commune code, projected x/y, WGS84 lon/lat, position type (e.g. `parcelle`), La Poste delivery label (`libelle_acheminement`), certification flag and cadastral parcel ids. — [same file](https://adresse.data.gouv.fr/data/ban/adresses/latest/csv/adresses-75.csv.gz)

**How the BAN is built (BAL)**
- Communes publish Bases Adresses Locales (BAL); the BAL source file of each commune is downloadable from its commune page. — [adresse.data.gouv.fr downloads](https://adresse.data.gouv.fr/outils/telechargements)
- Of the BAN's 26.12 M addresses, 23,261,438 come from BALs of 29,017 communes; 2,859,552 addresses in 5,994 communes are still "assemblage" (computed from other sources), of which only 72,650 certified. — [BAN stats](https://plateforme.adresse.data.gouv.fr/ban/stats)
- The separate folder `/data/adresses-locales/latest/csv/` still resolves but its files are dated 17/10/2023 (stale). — [listing, direct request](https://adresse.data.gouv.fr/data/adresses-locales/latest/csv/)

**APIs and services**
- Géoplateforme geocoding: `https://data.geopf.fr/geocodage/search`, `/reverse`, `/getcapabilities`, OpenAPI at `/openapi`. Limit: "Son usage est limité à 50 requêtes par seconde depuis une même adresse IP." No key for normal use. Synchronous CSV batches up to 50 MB or 200,000 lines; larger files (up to 1 GB) through an asynchronous project that needs a Géoplateforme account and OAuth2 credentials (geoplateforme@ign.fr). — [cartes.gouv.fr guide](https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/geocodage/)
- A keyless request returned a housenumber feature with `banId`, `postcode`, `citycode`, `x`/`y` and lon/lat; indexes are `address`, `poi`, `parcel`. — [direct request](https://data.geopf.fr/geocodage/search?q=8+bd+du+port+amiens&limit=1); [getCapabilities](https://data.geopf.fr/geocodage/getCapabilities)
- Map services: vector tiles (MVT, real time), WFS layer `BAN.DATA.GOUV:ban` and WMS layer `BAN.DATA.GOUV` (page says updated "bi-weekly"; whether that means twice a week or every two weeks is not clear from the fetch). — [adresse.data.gouv.fr downloads](https://adresse.data.gouv.fr/outils/telechargements)

**Service migration (API Adresse to IGN)**
- data.gouv.fr post of 3 April 2025: the API moved from DINUM to IGN; recommended endpoint `https://data.geopf.fr/geocodage/search/`; full traffic transfer targeted for 30 June 2025; the old domain kept "jusqu'à janvier 2026" as a redirect. The new service is described as "iso fonctionnel" and adds POI and cadastral-parcel search. — [data.gouv.fr post](https://www.data.gouv.fr/posts/lapi-adresse-de-la-base-adresse-nationale-est-transferee-a-lign-10)
- On 11 Nov 2026 `https://api-adresse.data.gouv.fr/search/?q=...` still returned HTTP 200 with JSON, with response headers `x-infra: gpf`, `deprecation: Sat, 31 Jan 2026 22:59:59 GMT`, `sunset: Sat, 31 Jan 2026 22:59:59 GMT` and a `location:` header pointing at `https://data.geopf.fr/geocodage/search/`. — [direct request](https://api-adresse.data.gouv.fr/search/?q=8+bd+du+port&limit=1)
- A CNIG document of June 2026 has the heading "URL API Adresse décommissionnée fin janvier 2026" (search snippet; PDF not opened). — [CNIG PDF](https://cnig.gouv.fr/IMG/pdf/cnig_gt_assurances_19062026.pdf)
- `geoservices.ign.fr/documentation/...geocodage` now 301-redirects to cartes.gouv.fr. — [redirect target](https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/geocodage/)
- The download page announced a service interruption for security maintenance on Wednesday 11 November (2026). — [adresse.data.gouv.fr downloads](https://adresse.data.gouv.fr/outils/telechargements)

**Postcodes (La Poste)**
- "Base officielle des codes postaux" (Hexasmal), producer La Poste, Licence Ouverte 2.0: INSEE code, commune name, postcode, delivery label, line 5 (lieu-dit / delegated commune). It is a commune-to-postcode table, not an address file. "Les contours géographiques des codes postaux ne sont pas fournis en open data." — [data.gouv.fr](https://www.data.gouv.fr/datasets/base-officielle-des-codes-postaux)
- CSV export with commune centroid: `https://data.laposte.fr/data-fair/api/v1/datasets/laposte-hexasmal/metadata-attachments/base-officielle-codes-postaux.csv` (link listed on data.gouv.fr). — [data.gouv.fr](https://www.data.gouv.fr/datasets/base-officielle-des-codes-postaux)
- That CSV returns HTTP 200 without login: 4,146,942 bytes, Last-Modified 8 Nov 2026. — [direct request](https://data.laposte.fr/data-fair/api/v1/datasets/laposte-hexasmal/metadata-attachments/base-officielle-codes-postaux.csv)
- La Poste's current portal record: 39,192 rows, "Licence Ouverte / Open Licence", data updated 8 Nov 2026, fields `code_commune_insee`, `nom_de_la_commune`, `code_postal`, `libelle_d_acheminement`, `ligne_5`. — [data.laposte.fr API record](https://data.laposte.fr/data-fair/api/v1/datasets/laposte-hexasmal)
- The old portal host `datanova.laposte.fr` failed TLS on 11 Nov 2026 ("certificate has expired"). — [direct request](https://datanova.laposte.fr/datasets/laposte-hexasmal)

**Secondary sources**
- Référentiel National des Bâtiments (RNB): Licence Ouverte 2.0, weekly, tagged `hvd`, one export per département plus a national file. — [data.gouv.fr API record](https://www.data.gouv.fr/api/1/datasets/referentiel-national-des-batiments/)
- RNB export is CSV with columns `rnb_id`, `point` and `shape` (WGS84, EWKT), `status`, `ext_ids` (BD Topo and BDNB keys), `addresses` (JSON list of known addresses, each with at least "la clé d'interopérabilité BAN") and `plots` (cadastral parcels intersected). — [RNB documentation](https://rnb-fr.gitbook.io/documentation/api-et-outils/export-national-et-departemental)
- IGN "BAN PLUS": `https://geoservices.ign.fr/ban-plus` redirects to a cartes.gouv.fr catalogue entry (HTTP 200). — [catalogue entry](https://cartes.gouv.fr/rechercher-une-donnee/dataset/IGNF_BAN-PLUS)
- OpenAddresses: the BAN "is pushed weekly to OpenAdresses" — [adresse.data.gouv.fr downloads](https://adresse.data.gouv.fr/outils/telechargements); the OpenAddresses repo has one folder per département under `sources/fr` — [GitHub](https://github.com/openaddresses/openaddresses/tree/master/sources/fr)

### Inferences
- The x/y columns are Lambert-93 (EPSG:2154) for metropolitan France: the Paris sample (652624, 6862372) fits that grid. The file does not name the CRS, so overseas rows need checking.
- Postcodes inside the BAN are open under the BAN licence; La Poste separately publishes only the commune-level table. No separate postcode licensing obstacle was found.
- RNB links buildings to BAN address keys, so it is the open route from an address to a building footprint; it is a building register, not a second address source.
- The old API hostname is living past its announced sunset as a proxy to the Géoplateforme; new integrations should use `data.geopf.fr` only.
- About 11% of addresses (assemblage communes) are not maintained by the commune and are mostly uncertified, so quality is uneven.

### Gaps
- Response headers of both API hosts show `x-ratelimit-limit-second: 1` next to `ratelimit-limit: 50`; I could not reconcile this with the documented 50 req/s.
- BAN PLUS content, licence and update cycle: the catalogue page is JavaScript-rendered, not read. Unverified.
- Whether the HVD regulation changed anything for the BAN beyond the tag: no statement found.
- `https://cadastre.data.gouv.fr/datasets/adresses-cadastre` returned 404; I did not establish whether a cadastre-derived address extract still exists.

## Belgium

### Takeaway
Belgium has a free federal aggregate, BeSt Address (BOSA), built from the three regional registers: 7.18 million address rows, weekly XML and CSV dumps with no registration, CC BY 4.0. On 18 Oct 2026 the dumps switched from Lambert 72 to Lambert 2008 coordinates, which breaks column names and file names. The regional registers are also open, but I could confirm Wallonia's licence and downloads fully, Flanders' partly, and Brussels' not at all from this machine.

### Cited Findings

**Federal aggregate: BeSt Address (Belgian Streets and Addresses), FPS BOSA**
- Page: https://opendata.bosa.be/ (NL: `index.nl.html`, FR: `index.fr.html`), titled "BeST: registres officiels d'adresses des trois Régions". Licence: "Creative Commons 4.0 Attribution". — [BOSA open data](https://opendata.bosa.be/index.fr.html)
- Files contain the latest versions of municipalities, street names, addresses, parts of municipalities (Wallonia only) and postal info. — [BOSA open data](https://opendata.bosa.be/index.fr.html)
- XML full download `https://opendata.bosa.be/download/best/best-full-latest.zip` ("+/- 290 MB", weekly): HTTP 200, 310,437,431 bytes, Last-Modified 8 Nov 2026. — [direct request](https://opendata.bosa.be/download/best/best-full-latest.zip)
- CSV per region, weekly, HTTP 200 without login (Last-Modified 8 Nov 2026): Flanders `openaddress-bevlg.zip` 153,229,244 bytes (CSV 621,964,649 bytes, 4,223,588 rows); Brussels `openaddress-bebru.zip` 18,162,025 bytes (CSV 127,464,055 bytes, 849,246 rows); Wallonia `openaddress-bewal.zip` 59,389,738 bytes (CSV 312,462,125 bytes, 2,109,079 rows). Total 7,181,913 rows. — [bevlg](https://opendata.bosa.be/download/best/openaddress-bevlg.zip); [bebru](https://opendata.bosa.be/download/best/openaddress-bebru.zip); [bewal](https://opendata.bosa.be/download/best/openaddress-bewal.zip)
- CSV header: `EPSG:3812_x,EPSG:3812_y,EPSG:4326_lat,EPSG:4326_lon,address_id,box_number,house_number,municipality_id,municipality_name_de,municipality_name_fr,municipality_name_nl,postcode,postname_fr,postname_nl,street_id,streetname_de,streetname_fr,streetname_nl,region_code,status`. Rows go down to box number (unit) level and carry a status (`current` in the samples). — [bebru CSV, direct download](https://opendata.bosa.be/download/best/openaddress-bebru.zip)
- Also: streets with at least one address per postcode (`postalstreets-latest.zip`, 2,188,474 bytes) and streets without addresses (`postalstreets-empty-latest.zip`); DCAT-AP at `/download/best/dcat.rdf`. — [BOSA open data](https://opendata.bosa.be/index.nl.html)

**Change of 18 Oct 2026 (Lambert 72 to Lambert 2008)**
- "Avis important (18/10/2026)": the download files were converted from Lambert 72 to Lambert 2008. XML: coordinates are now only in Lambert 2008 and file names no longer contain "L72". CSV: columns `EPSG:31370_x/_y` were replaced by `EPSG:3812_x/_y`. Differences of up to 20 cm are possible. The REST API keeps giving L72, L2008 and WGS84. — [BOSA open data](https://opendata.bosa.be/index.fr.html)
- The last Lambert 72 files (7 Oct 2026) are kept under `/download/best/archive/lambert72/`. — [BOSA open data](https://opendata.bosa.be/index.nl.html)

**Quality caveats stated by BOSA**
- "Pour certaines applications, les informations d'adresse ne sont pas d'une qualité suffisante pour pouvoir basculer vers une utilisation exclusive des registres régionaux d'adresses"; a joint project is working on the gaps; the user must judge whether quality is sufficient. Errors are reported to the regional partner. — [BOSA open data](https://opendata.bosa.be/index.fr.html)
- Notices present in the page source but commented out (not displayed): 9/2025, Brussels reset all version numbers to 1, dropped postal-zone names from the postalInfo XML and removed many duplicate addresses and streets; 01/2025, 28 Flemish municipalities merged and Flanders published old-to-new id mapping files ("verschilbestanden"). — [BOSA page source](https://opendata.bosa.be/index.fr.html)

**Federal APIs**
- Hosted API "for companies: free (but without guarantee) open service endpoint": `https://best.pr.fedservices.be/api/opendata/best/v1/belgianAddress/v2/doc/openapi.yaml`; public administrations go through the BOSA service integrator. — [BOSA open data](https://opendata.bosa.be/index.fr.html)
- The OpenAPI file ("v2 Belgian Streets and Addresses REST API", version 1.12.10) declares OAuth2 security, yet an anonymous `GET .../belgianAddress/v2/addresses?postCode=1000&streetName=Wetstraat&houseNumber=16` returned HTTP 200 with address data on 11 Nov 2026. Coordinates can be queried in WGS84, Lambert 72 or Lambert 2008. — [OpenAPI](https://best.pr.fedservices.be/api/opendata/best/v1/belgianAddress/v2/doc/openapi.yaml); [direct request](https://best.pr.fedservices.be/api/opendata/best/v1/belgianAddress/v2/addresses?postCode=1000&streetName=Wetstraat&houseNumber=16)
- "Best-in-a-box": a stand-alone Docker image with web service and database (`bosa/opendata-best-webapi`), described as a test version, with its own terms-of-use PDF. — [BOSA open data](https://opendata.bosa.be/index.fr.html)
- NGI/IGN derivatives on geo.be (BeSt address as GeoPackage, WMS) are marked "enkel niet-commercieel gebruik" (non-commercial only) by BOSA. — [BOSA open data](https://opendata.bosa.be/index.nl.html); [geo.be](https://www.geo.be/catalog/details/ca0fd5c0-8146-11e9-9012-482ae30f98d9?l=nl); contradicted by a transportdata.be listing of the NGI "Address points Belgium - BeST Address" dataset as CC BY 4.0 (search snippet) — [transportdata.be](https://transportdata.be/dataset/address-points-belgium-best-address)

**Flanders: Adressenregister (part of Gebouwen- en Adressenregister), Digitaal Vlaanderen**
- BOSA names the AR (Adressenregister) as the authentic source for Flanders. — [BOSA open data](https://opendata.bosa.be/index.fr.html)
- Catalogue entry "Gebouwen- en adressenregister - adressen": public, "Geen beperkingen op de publieke toegang", formats Esri Shape and GeoPackage, "Continu geactualiseerd", CRS Belgian Lambert 72, version 2026-11-10, download at `https://download.vlaanderen.be/product/11065`. — [Vlaanderen catalogue](https://www.vlaanderen.be/datavindplaats/catalogus/gebouwen-en-adressenregister-adressen)
- The metadata record references the licence `https://data.vlaanderen.be/id/licentie/modellicentie-gratis-hergebruik/v1.0`. — [metadata.vlaanderen.be record](https://metadata.vlaanderen.be/srv/api/records/9c8b57a1-3c9a-4813-926e-38bb0bd387a7)
- REST API `https://api.basisregisters.vlaanderen.be/v2/adressen`: an anonymous request returned HTTP 200 with address data on 11 Nov 2026. — [direct request](https://api.basisregisters.vlaanderen.be/v2/adressen?postcode=9000&limit=1)
- Keyless requests on 11 Nov 2026 also returned HTTP 200 for the WFS — [GetCapabilities](https://geo.api.vlaanderen.be/Adressenregister/wfs?service=WFS&request=GetCapabilities); for OGC API Features, single collection `Adres` — [collections](https://geo.api.vlaanderen.be/Adressenregister/ogc/features/v1/collections?f=json); and for the geolocation (geocoding) service — [sample](https://geo.api.vlaanderen.be/geolocation/v4/Location?q=Havenlaan%2088%20Brussel)
- The product page links a "Gebruik API key" guide, release notes and a status page. — [Digitaal Vlaanderen](https://www.vlaanderen.be/digitaal-vlaanderen/onze-diensten-en-platformen/gebouwen-en-adressenregister)
- Changes show in the WMS "near realtime" and in the geolocation service the next day. — [GRAR FAQ](https://www.vlaanderen.be/digitaal-vlaanderen/onze-diensten-en-platformen/gebouwen-en-adressenregister/faq)

**Wallonia: ICAR (Inventaire Centralisé des Adresses et des Rues), Service public de Wallonie**
- "ICAR - Points d'adresses": licence CC BY 4.0, "Pas de limitation d'accès public à cette donnée"; extracted daily, last update 09/11/2026; CRS EPSG:31370; only ICAR addresses with a geometric match to PICC building points have X,Y. — [Géoportail de la Wallonie](https://geoportail.wallonie.be/catalogue/2998bccd-dae4-49fb-b6a5-867e6c37680f.html)
- Full downloads, HTTP 200 without login: SHP 111,073,360 bytes — [icar_adpt_shp.zip](https://geoservices.wallonie.be/geotraitement/spwdatadownload/results/2998bccd-dae4-49fb-b6a5-867e6c37680f/icar_adpt_shp.zip); CSV 59,212,719 bytes — [icar_adpt_csv.zip](https://geoservices.wallonie.be/geotraitement/spwdatadownload/results/2998bccd-dae4-49fb-b6a5-867e6c37680f/icar_adpt_csv.zip)
- Services: ESRI REST `geoservices.wallonie.be/arcgis/rest/services/DONNEES_BASE/ICAR_ADR_PT/MapServer`, WMS, ATOM feed; a custom extract is sent by e-mail within 48 hours. No WFS or geocoding API is listed on the record. — [Géoportail de la Wallonie](https://geoportail.wallonie.be/catalogue/2998bccd-dae4-49fb-b6a5-867e6c37680f.html)

**Brussels: UrbIS addresses, Paradigm (formerly CIRB/CIBG)**
- "En Région bruxelloise, Paradigm publie le registre d'adresses, ainsi que divers services, sur datastore.brussels"; CSV, GeoPackage and GeoJSON for Brussels, updated weekly, at `https://datastore.brussels/web/data/dataset/a8c9ccde-5c2b-11ed-913a-900f0cda5d5c#access`. — [BOSA open data](https://opendata.bosa.be/index.nl.html)
- be.brussels says UrbIS is "covered by an Open Data license, ensuring free and unrestricted use" (search snippet; page not opened). — [be.brussels](https://be.brussels/en/about-region/urbis-data)
- The Geobru catalogue record for the Brussels BeSt address product describes it as freely downloadable as zipped files or via a WFS, and a WFS is listed at `geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs` (search snippets; record not opened). — [Geobru catalogue](https://geobru-geonetwork.irisnet.be/geonetwork/srv/api/records/a8c9ccde-5c2b-11ed-913a-900f0cda5d5c)
- A Geobru note says the older "UrbIS - Addresses" dataset is "not compliant with BeSt specification" (search snippet), so Brussels has two address products. — [Geobru UrbIS - Addresses](https://geobru-geonetwork.irisnet.be/geonetwork/srv/api/records/a8a807b0-6b0b-11ed-8e3b-010101010000)

**Postcodes (bpost)**
- bpost offers postcode lists as XLS: `https://www.bpost.be/sites/default/files/zipcodes/zipcodes_alpha_nl_2025.xls` and `.../zipcodes_num_nl_2025.xls`; no licence or reuse terms are stated on the page. — [bpost postcode tool](https://www.bpost.be/nl/postcodevalidatie-tool)
- Both files (and `zipcodes_alpha_fr_2025.xls`) return HTTP 200, 328,192 bytes, Last-Modified 16 Mar 2026. — [direct request](https://www.bpost.be/sites/default/files/zipcodes/zipcodes_alpha_fr_2025.xls)
- Postcodes are already in the BeSt files (`postcode`, `postname_*` columns, `postalinfo` XML). — [bebru CSV](https://opendata.bosa.be/download/best/openaddress-bebru.zip)

**OpenAddresses**
- The OpenAddresses sources for `be/bru`, `be/vlg`, `be/wal` all read the BOSA CSVs (`openaddress-bebru.zip` etc.), and BOSA itself points to OpenAddresses/Pelias. — [GitHub](https://github.com/openaddresses/openaddresses/tree/master/sources/be); [BOSA open data](https://opendata.bosa.be/index.nl.html)

### Inferences
- For a nationwide load, the three BOSA CSVs are the simplest route: one schema, WGS84 plus Lambert 2008, CC BY 4.0, commercial reuse allowed with attribution.
- Any pipeline written before 18 Oct 2026 that reads `EPSG:31370_x/_y` or XML file names with "L72" is now broken.
- The bpost XLS is a locality-to-postcode list of 328 KB, so it cannot be an address file; its reuse terms are unstated, so BeSt is the safer postcode source.
- Wallonia's own download is still in Lambert 72 while the federal aggregate is in Lambert 2008; the two must not be mixed without reprojection.

### Gaps
- Brussels: every request from this machine to `datastore.brussels`, `urbisdownload.datastore.brussels`, `geoservices-urbis.irisnet.be` and `geobru-geonetwork.irisnet.be` failed or timed out (connection timeouts, tried in three separate batches on 11 Nov 2026), and be.brussels pages returned nothing. I cannot tell whether the hosts were down or unreachable only from here. Exact licence name, download links, WFS and geocoder are therefore unverified.
- Flanders: `download.vlaanderen.be` is a JavaScript app; I could not confirm whether the download needs a login, nor the file sizes. Two product ids appear (11065 on the catalogue page, 10145 in the metadata record). API-key rules and rate limits are unverified (the docs pages rendered empty); a HEAD request to the REST API got 403 while GET got 200.
- `bosa.belgium.be` and `statbel.fgov.be` served a CAPTCHA. A Statbel page titled "Open data - Address files and statistical sectors - 2024" exists (https://statbel.fgov.be/en/news/open-data-address-files-and-statistical-sectors-2024) but its content is unverified.
- A Paradigm article announces a new geocoding API covering all Belgian addresses "from mid-November" (search snippet; year and URL unverified).
- HVD: I found no statement on whether BeSt or the regional registers are flagged as High-Value Datasets; a targeted search returned nothing and the geo.be record is JavaScript-rendered.
- The licence terms of the NGI/geo.be derivative are contradictory between sources (see above) and unresolved.
- Rate limits of the BOSA open endpoint are not documented on the page.

## Netherlands

### Takeaway
The Netherlands publishes the whole BAG (Basisregistratie Adressen en Gebouwen) free and without registration through PDOK: a 3.66 GB XML extract with history (monthly) and a 7.83 GB GeoPackage, both public domain (CC0 / Public Domain Mark), about 10.09 million addresses, flagged as an EU High-Value Dataset. Free keyless geocoding exists (PDOK Locatieserver); only mutation subscriptions and the per-object Kadaster API need payment or a key.

### Cited Findings

**Authoritative register and publisher**
- BAG = Basisregistratie Adressen en Gebouwen (Key Register of Addresses and Buildings), managed by Kadaster; data owner on data.overheid.nl is "Dienst voor het kadaster en de openbare registers". — [data.overheid.nl](https://data.overheid.nl/en/dataset/10491-bag)
- "BAG-data zijn open data"; use falls under the Creative Commons Public Domain Mark 1.0. — [Kadaster BAG Extract](https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-2.0-extract)

**Bulk download (no registration)**
- PDOK ATOM feed `https://service.pdok.nl/lv/bag/atom/bag.xml` has two entries, both EPSG:28992 (Amersfoort / RD New), rights `https://creativecommons.org/publicdomain/zero/1.0/deed.nl`. — [PDOK ATOM](https://service.pdok.nl/lv/bag/atom/bag.xml)
- GeoPackage "bevat de belangrijkste BAG gegevens (zonder historie)": `https://service.pdok.nl/kadaster/bag/atom/downloads/bag-light.gpkg`, HTTP 200, 7,827,132,416 bytes, Last-Modified 1 Nov 2026. — [direct request](https://service.pdok.nl/kadaster/bag/atom/downloads/bag-light.gpkg)
- Full extract with history, XML in a ZIP: `https://service.pdok.nl/kadaster/bag/atom/downloads/lvbag-extract-nl.zip`, HTTP 200, 3,657,771,488 bytes, Last-Modified 8 Nov 2026. — [direct request](https://service.pdok.nl/kadaster/bag/atom/downloads/lvbag-extract-nl.zip)
- Kadaster: "Het BAG Extract met BAG gegevens van heel Nederland is gratis beschikbaar"; a new extract is made on the 8th of each month. — [Kadaster BAG Extract](https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-2.0-extract)
- Kadaster's free-download page links `https://service.pdok.nl/kadaster/adressen/atom/v1_0/downloads/lvbag-extract-nl.zip` and says "ongeveer 2,8 GB"; that link resolves to the same 3,657,771,488-byte file. — [Kadaster free download](https://www.kadaster.nl/-/gratis-download-bag-extract); [direct request](https://service.pdok.nl/kadaster/adressen/atom/v1_0/downloads/lvbag-extract-nl.zip)

**What is paid**
- Mutation subscriptions and one-off municipal extracts cost money: national or municipal monthly mutations EUR 14.50 per month (EUR 219 one-time), national daily mutations EUR 219 per month, one-off municipal extract EUR 219. Government bodies get them free through budget financing. Ordering goes through Mijn Kadaster. — [Kadaster BAG Extract](https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-2.0-extract)
- The SOAP retrieval method with username/password is being phased out in Q1 2027; the BAG Extract Ophaal API (API key) replaces it. — [Kadaster BAG Extract](https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-2.0-extract)

**APIs and services**
- PDOK OGC API (Features and Vector Tiles): `https://api.pdok.nl/kadaster/bag/ogc/v2`, "dagelijks geactualiseerd". — [PDOK BAG page](https://www.pdok.nl/introductie/-/article/basisregistratie-adressen-en-gebouwen-ba-1)
- Collections: `adres`, `ligplaats`, `pand`, `standplaats`, `verblijfsobject`, `woonplaats`. — [direct request](https://api.pdok.nl/kadaster/bag/ogc/v2/collections?f=json)
- The earlier path `https://api.pdok.nl/lv/bag/ogc/v1` returns 404. — [direct request](https://api.pdok.nl/lv/bag/ogc/v1?f=json)
- WFS `https://service.pdok.nl/lv/bag/wfs/v2_0` and WMS `https://service.pdok.nl/lv/bag/wms/v2_0` answer GetCapabilities with HTTP 200. — [WFS, direct request](https://service.pdok.nl/lv/bag/wfs/v2_0?service=WFS&request=GetCapabilities)
- Caveat from PDOK: address objects in these services are included only as main addresses, so objects with secondary addresses are incomplete. — [PDOK BAG page](https://www.pdok.nl/introductie/-/article/basisregistratie-adressen-en-gebouwen-ba-1)
- PDOK Locatieserver: "een open en gratis geocodeerservice" with suggest, lookup, free and reverse APIs; docs at `https://api.pdok.nl/bzk/locatieserver/search/v3_1/ui/`. — [PDOK Locatieserver](https://www.pdok.nl/pdok-locatieserver)
- A keyless query works and returns `postcode`, `huis_nlt`, `nummeraanduiding_id`, `centroide_ll` (WGS84 point), municipality, neighbourhood and parcel links, source "BAG". The index holds 10,085,513 documents of type `adres`. — [sample](https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=Hofweg+1+Den+Haag&rows=1&fq=type:adres); [count](https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=*:*&rows=0&fq=type:adres)
- Kadaster BAG API Individuele Bevragingen: "U kunt de BAG API Individuele Bevragingen gratis gebruiken"; an API key must be requested by form; usage limits apply; meant for single objects, not bulk. — [Kadaster BAG API](https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-api-individuele-bevragingen)
- Without a key the API returns 401. — [direct request](https://api.bag.kadaster.nl/lvbag/individuelebevragingen/v2/adressen?postcode=2511AA&huisnummer=1)
- INSPIRE-harmonised addresses: "Adressen (INSPIRE geharmoniseerd)" ATOM, rights CC0, updated 2 Sep 2026. — [PDOK INSPIRE AD ATOM](https://service.pdok.nl/kadaster/ad/atom/index.xml)

**HVD**
- The BAG record on data.overheid.nl is labelled "HVD Hoogwaardige dataset - EU" / "High Value Dataset - EU", category Geospatial. — [data.overheid.nl](https://data.overheid.nl/en/dataset/10491-bag)

**Postcode history**
- The ministry of Infrastructure and Environment ended the "postcodeconvenant" with TNT Post (now PostNL) in February 2011 so that postcode data in the BAG could be reused commercially; PostNL sued the State claiming commercial rights and lost, so the restriction ended on 1 February 2012. — [Binnenlands Bestuur](https://www.binnenlandsbestuur.nl/digitaal/ondermijning/bag-met-postcodegegevens-wordt-vrij-herbruikbaar)
- PostNL still sells its own Postcodetabel (request and secured delivery; search snippet). — [PostNL](https://www.postnl.nl/zakelijke-oplossingen/slimme-dataoplossingen/postcodetabel/)

**OpenAddresses**
- `sources/nl/countrywide.json` reads a cached upload `verblijfsobject.csv.zip` dated 2026-06-03 (derived from the BAG GeoPackage), licence CC0 1.0, no attribution required. — [GitHub raw](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/nl/countrywide.json)

### Inferences
- Two public-domain labels are in use (CC0 on the PDOK feed, Public Domain Mark on Kadaster pages); either way there is no attribution duty and commercial reuse is unrestricted.
- The "about 2.8 GB" on Kadaster's page is out of date; the file is 3.66 GB.
- For a flat address table the GeoPackage is the practical source; the XML extract is needed for history and for secondary addresses, which the PDOK view services omit.
- Postcodes have been unrestricted inside the BAG since 1 Feb 2012; PostNL's table is a separate commercial product, not a licensing obstacle.

### Gaps
- Numeric rate limits of the BAG API Individuele Bevragingen and any fair-use limit of the Locatieserver: not stated on the pages read.
- A search snippet cites an Esri document dating a government-PostNL covenant on unrestricted BAG postcode use to early 2014, which does not match the 2012 date above; not resolved.
- Whether the HVD regulation changed BAG distribution (beyond the label): no statement found.
- CBS postcode/house-number-to-neighbourhood files were not checked.

## Luxembourg

### Takeaway
Luxembourg publishes everything free, without registration and under CC0 on data.public.lu: the national register of localities and streets (CACLR, about 249 thousand building lines, no coordinates) and the georeferenced BD-Adresses (179,784 address points with LUREF and WGS84 coordinates, weekly). The INSPIRE address dataset is tagged as an HVD; a keyless geocoding API runs on geoportail.lu.

### Cited Findings

**Authoritative register**
- "Registre national des localités et des rues" (national register of localities and streets, CACLR), publisher Administration du cadastre et de la topographie (ACT), licence CC0, weekly, last modified 9 Nov 2026. Resources: `caclr.zip` (1,956,389 bytes) and `caclr.xlsx` (43,103,641 bytes), a data-model description at act.public.lu, and an online lookup at `https://www.services-publics.lu/caclr/index.action`. — [data.public.lu](https://data.public.lu/fr/datasets/registre-national-des-localites-et-des-rues/)
- `caclr.zip` holds 13 fixed-width files: ALIAS.LOCALITE, ALIAS.RUE, CANTON, CODEPT, COMMUALL, CPTCH, DISTRICT, IMMDESIG, IMMEUBLE (248,702 lines), LOCALITE, QUARTIER, RUE (9,964 lines), TR.DICACOLO.RUCP; CODEPT has 4,430 lines. — [caclr.zip, direct download](https://download.data.public.lu/resources/registre-national-des-localites-et-des-rues/20261109-033002/caclr.zip)

**Georeferenced addresses (the file to use)**
- "Adresses géoréférencées (BD-Adresses)", publisher ACT, licence "Creative Commons Zero (CC0)", weekly, last update 9 Nov 2026; "un sous-ensemble des adresses figurant dans le registre national des localités et des rues", enriched with coordinates. — [data.public.lu](https://data.public.lu/fr/datasets/adresses-georeferencees-bd-adresses/)
- Resources on 9 Nov 2026: `addresses.csv` 28,212,250 bytes — [CSV](https://download.data.public.lu/resources/adresses-georeferencees-bd-adresses/20261109-033120/addresses.csv); `addresses.geojson` 80,908,855 bytes — [GeoJSON](https://download.data.public.lu/resources/adresses-georeferencees-bd-adresses/20261109-033133/addresses.geojson); `addresses-shp.zip` 19,703,541 bytes — [SHP](https://download.data.public.lu/resources/adresses-georeferencees-bd-adresses/20261109-033148/addresses-shp.zip). The dated folder in these URLs changes every week; the stable entry point is the dataset page or its API record. — [API record](https://data.public.lu/api/1/datasets/adresses-georeferencees-bd-adresses/)
- The CSV has 179,784 data rows. Header: `rue;numero;localite;code_postal;id_caclr_rue;id_caclr_bat;lat_wgs84;lon_wgs84;coord_est_luref;coord_nord_luref;id_geoportail;commune;lau2`. — [addresses.csv, direct download](https://download.data.public.lu/resources/adresses-georeferencees-bd-adresses/20261109-033120/addresses.csv)
- Caveats stated by ACT: georeferencing is based on the cadastral parcel and the digital cadastral plan, which may be offset from LUREF; coordinates come from manual placement or an automatic centroid (of the parcel or of the largest building on it); "les points d'adresses ne représentent pas l'entrée réelle des bâtiments"; several points can share coordinates; not all official addresses are georeferenced yet; "l'exhaustivité des données ne peut être garantie". — [data.public.lu](https://data.public.lu/fr/datasets/adresses-georeferencees-bd-adresses/)
- The dataset carries the portal badges `spd` and `pivotal-data`. — [API record](https://data.public.lu/api/1/datasets/adresses-georeferencees-bd-adresses/)

**INSPIRE / HVD**
- "INSPIRE - Annex I Theme Addresses - Addresses", organisation Géoportail, licence CC0, tagged `hvd` and `inspire`, last modified 9 Nov 2026: `ad.address.gml` (469,407,600 bytes), `ad.address.zip` (13,220,811 bytes), and a WMS at `https://wms.inspire.geoportail.lu/geoserver/ad/wms`. — [data.public.lu API record](https://data.public.lu/api/1/datasets/inspire-annex-i-theme-addresses-addresses/); [dataset page](https://data.public.lu/fr/datasets/inspire-annex-i-theme-addresses-addresses/)

**APIs**
- The BD-Adresses dataset lists "Geocode REST API" `https://apiv3.geoportail.lu/geocode/search` and "Reverse geocode REST API" `https://apiv3.geoportail.lu/geocode/reverse`. — [API record](https://data.public.lu/api/1/datasets/adresses-georeferencees-bd-adresses/)
- Both `apiv3` and `apiv4` hosts answered keyless requests with HTTP 200 on 11 Nov 2026 (search on v3 and v4, reverse on v4). — [apiv3 search](https://apiv3.geoportail.lu/geocode/search?queryString=1+rue+du+Fort+Thungen+Luxembourg); [apiv4 reverse](https://apiv4.geoportail.lu/geocode/reverse?easting=75980&northing=75098)
- An INSPIRE WFS for addresses answers GetCapabilities with HTTP 200. — [direct request](https://wms.inspire.geoportail.lu/geoserver/ad/wfs?service=WFS&request=GetCapabilities)
- A keyless request to `https://apiv4.geoportail.lu/geocode/search?queryString=...` returned a match with LUREF easting/northing, a lon/lat geometry, postcode, and `id_caclr_street` / `id_caclr_building` / `id_caclr_locality`. — [direct request](https://apiv4.geoportail.lu/geocode/search?queryString=54+avenue+Gaston+Diderich+Luxembourg)

**OpenAddresses**
- `sources/lu/countrywide.json` reads a data.public.lu resource of the BD-Adresses dataset, licence "CC 0", attribution not required. — [GitHub raw](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lu/countrywide.json)

### Inferences
- BD-Adresses (179,784 points) is smaller than the CACLR building file (248,702 lines). This fits ACT's statement that not all addresses are georeferenced, but the CACLR file may also hold historic or cancelled entries, so the gap is not a clean measure of missing coordinates.
- Postcodes are part of both ACT datasets under CC0; no separate POST Luxembourg licence stands in the way.
- Address points are parcel or building centroids, not entrances; unit (apartment) level is absent from the CSV columns.

### Gaps
- Terms of use and rate limits of the geoportail.lu geocoding API: not checked.
- Whether the HVD tag on the INSPIRE dataset came with any change in 2024: no statement found.
- The meaning of every CACLR file and the share of active records: data-model PDF not read.

## Ireland

### Takeaway
Ireland has no open national address register. The two national address databases, Eircode (ECAF/ECAD, operated by Capita) and GeoDirectory (An Post and Tailte Éireann), are licensed, paid products; the only free official access is the Eircode Finder web lookup with a daily cap. Tailte Éireann's High-Value Dataset release (CC BY 4.0, January 2026) covers 3.79 million building polygons and cadastral parcels but carries no address attributes.

### Cited Findings

**What is NOT free**
- Eircode sells two products under annual licence: ECAF (Eircode Address File), "base reference data containing over 2.2 million address points with their Eircode and USP Postal Address", and ECAD (Eircode Address Database), which adds alias addresses, geo-coordinates, boundary and building information. "The purchase of the ECAF is a prerequisite for purchase of the ECAD." Supply is direct (Direct End User, internal use only, "cannot sell or share these products or services with other companies") or through approved Eircode Providers. — [eircode.ie products](https://www.eircode.ie/business/products-and-services)
- Eircode's own price document, still served on 11 Nov 2026, is headed "Pricing effective from March 2015": two licence types (Eircode Provider Licence, Direct End User Licence), "All licences and data fees are on a one year contract", monthly usage returns required. — [Eircode pricing PDF](https://www.eircode.ie/files/eircode-pricing-information.pdf)
- Prices in that document. ECAF: EUR 60 per user for 1-83 users, EUR 5,000 single fee for 84 or more; EUR 4 per block of 100 transactions (only through a Provider); website use EUR 3,000 per year; group/legal entity EUR 25,000 per year. ECAD (ECAF included): annual data access fee EUR 1,000 (Eircode Provider) or EUR 500 (Direct End User), plus usage of EUR 180 per user (1-10 users) falling to EUR 100 (101-262 users), capped at EUR 30,000, or EUR 0.050 down to EUR 0.010 per transaction. — [Eircode pricing PDF](https://www.eircode.ie/files/eircode-pricing-information.pdf)
- GeoDirectory: "Ireland's most authoritative electronic register of addresses", "jointly developed by An Post and Tailte Éireann", operated by An Post GeoDirectory DAC, "over 1.9 million buildings and 2.3 million addresses". "We do not currently offer a free trial." Prices are on request. — [GeoDirectory FAQ](https://www.geodirectory.ie/knowledge-centre/faqs)

**What is free**
- Eircode Finder (https://finder.eircode.ie): a web lookup, not a dataset. In December 2019 Eircode wrote: "we have increased the daily limit on our Eircode Finder tool from 15 lookups per day to 50", "Terms and conditions apply." — [Eircode news, Dec 2019](https://www.eircode.ie/news/2019/12/03/christmas-cheer-from-eircode)
- GeoDirectory's GeoFindIT app is free ("the FREE GeoFindIT app"); it is an app, not data. — [GeoDirectory FAQ](https://www.geodirectory.ie/knowledge-centre/faqs)

**Tailte Éireann open data and HVD**
- Tailte Éireann (successor of OSi, the Valuation Office and the Property Registration Authority) publishes surveying open data at `https://data-osi.opendata.arcgis.com/`: "free to use" with attribution, "A standard Creative Commons licence applies to this data." — [Tailte open data](https://tailte.ie/services/open-data/)
- The portal's DCAT feed lists 178 datasets, all with licence `https://creativecommons.org/licenses/by/4.0`. Fifteen are titled "High Value Dataset - ...": Buildings, Building Groups, Cadastral Parcels Freehold, Cadastral Parcels Leasehold, Sites, Locales, Ways, Way GDF2, Way Points, Rail Network Segment, Rail Points, Water, Water Points, Water Single Stream, National Land Cover 2018. None is an address dataset. — [DCAT feed, direct request](https://data-osi.opendata.arcgis.com/api/feed/dcat-us/1.1.json)
- "High Value Dataset - Buildings" (issued 9 Jan 2026): Prime 2 building polygons, downloadable as CSV, GeoJSON, KML, File Geodatabase, GeoPackage and more. — [dataset page](https://data-osi.opendata.arcgis.com/datasets/osi::high-value-dataset-buildings)
- The Buildings feature layer has 3,785,414 polygons and only the fields `GUID`, `OBJECTID`, `Shape__Area`, `Shape__Length`; copyright text "© Tailte Éireann". No address, Eircode or use attribute. — [layer definition](https://services-eu1.arcgis.com/FH5XCsx8rYXqnjF5/arcgis/rest/services/Buildings/FeatureServer/0?f=json); [count](https://services-eu1.arcgis.com/FH5XCsx8rYXqnjF5/arcgis/rest/services/Buildings/FeatureServer/0/query?where=1%3D1&returnCountOnly=true&f=json)
- Valuation Office API (Tailte Éireann), CC BY 4.0, continuous, flagged as a High Value Dataset in the Statistics category under Regulation 2023/138: real-time valuation data for revalued rating-authority areas. — [data.gov.ie](https://data.gov.ie/dataset/valuation-office-api)
- Other HVD layers are not addresses either: "Locales" are named areas such as bays, mountain ranges and districts; "Sites" are large contiguous areas grouping related objects; "Cadastral Parcels Freehold" (issued 9 Jan 2026) holds the boundaries of each freehold title. — [DCAT feed](https://data-osi.opendata.arcgis.com/api/feed/dcat-us/1.1.json)
- A data.gov.ie search for "eircode" finds 17 datasets, all small point-of-interest lists (enterprise centres, Garda stations, schools, recycling centres) that include an Eircode column; none is an address register. — [data.gov.ie search](https://data.gov.ie/dataset?q=eircode)
- Tailte asks users to report errors in a property's "X&Y or Eircode" and notes "some property categories are not assigned an Eircode". — [Tailte open data](https://tailte.ie/services/open-data/)

**Aggregators**
- OpenAddresses has no Ireland source: `sources/ie` does not exist in the repository (GitHub API 404). — [GitHub](https://github.com/openaddresses/openaddresses/tree/master/sources)

**Policy**
- An April 2025 parliamentary answer says new Eircodes are published on the free-to-use Eircode Finder while licensed businesses receive the database files (search snippet; the page returned 403 to me). — [Oireachtas, 29 Apr 2025](https://www.oireachtas.ie/en/debates/question/2025-04-29/257)
- A December 2023 parliamentary answer says the Minister notified Capita in March 2023 of a three-year extension of the Eircode contract (search snippet). — [Oireachtas, 12 Dec 2023](https://www.oireachtas.ie/en/debates/question/2023-12-12/122/)
- data.gov.ie holds several user suggestions asking for the Eircode database as open data; none led to a release. — [data.gov.ie suggestion](https://data.gov.ie/ga/dataset/suggest/40acc585-4ca5-4b4f-9332-f2d954c935ab)

### Inferences
- The best free official building-level data is Tailte's HVD Buildings layer (geometry only). It gives locations of buildings but no house number, street or Eircode, so it cannot replace an address register.
- The Valuation Office data is the only official open source I found that pairs property records with coordinates and Eircodes, and it covers rateable (mostly commercial) property in listed council areas only; it is not a national address list.
- The HVD regulation did not open Irish address data: the HVD release contains buildings and parcels, and Eircode and GeoDirectory stayed commercial.
- For nationwide free house-number addresses, community data (OpenStreetMap) is what remains; coverage was not measured here.

### Gaps
- The current Eircode Finder daily limit and its terms: the Finder is a JavaScript app and the terms page was not found. A search snippet says the 50-per-day figure was a seasonal increase over a standing limit of 15; unverified.
- Current ECAF/ECAD prices: the only price list Eircode publishes is dated March 2015; whether those figures still apply in 2026 is unverified.
- Field content of the Valuation Office API (address text, X/Y, Eircode per property) was not confirmed from the API itself.
- No official statement was found on why addresses are absent from Ireland's HVD release, or on any plan to open Eircode. The Oireachtas pages could not be opened.
- Property Price Register, Logainm and CSO sources were not checked.
