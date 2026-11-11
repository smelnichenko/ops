## Netherlands (NL)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | BAG (Kadaster), distributed by PDOK | Bulk GeoPackage or XML zip, no registration | Public domain (CC0 / Public Domain Mark 1.0) | Yes; EPSG:28992 (Amersfoort / RD New) | Yes | Monthly files; daily services |

**In short.** Use the BAG (Basisregistratie Adressen en Gebouwen, "Key Register of Addresses and Buildings") from PDOK: a 7.83 GB GeoPackage without history or a 3.66 GB zip of XML with full history, both public domain and downloadable without an account. Build the import from the files, not from the PDOK query services: those carry only the main address of each object, so objects with secondary addresses are incomplete. Coordinates in the files are in the Dutch RD New grid (EPSG:28992), not WGS84.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| BAG full extract (XML in a zip) | Kadaster (data owner "Dienst voor het kadaster en de openbare registers"); distributed by PDOK | File: https://service.pdok.nl/kadaster/bag/atom/downloads/lvbag-extract-nl.zip ; feed: https://service.pdok.nl/lv/bag/atom/bag.xml ; Kadaster page: https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-extract | Full copy of the BAG for the whole country, including history, as XML files. EPSG:28992 | Bulk download, no login; 3,657,771,488 bytes | CC0 on the PDOK feed; Creative Commons Public Domain Mark 1.0 on the Kadaster page | Monthly: a new extract on the 8th; file dated 8 Nov 2026 | confirmed |
| BAG GeoPackage | Kadaster; distributed by PDOK | File: https://service.pdok.nl/kadaster/bag/atom/downloads/bag-light.gpkg ; feed: https://service.pdok.nl/lv/bag/atom/bag.xml | "The most important BAG data (without history)"; the feed says not all BAG data is included, to keep the file simple. EPSG:28992 | Bulk download, no login; 7,827,132,416 bytes | CC0 | Feed updated monthly; file dated 1 Nov 2026 | confirmed |
| Adressen (INSPIRE geharmoniseerd) ("addresses, INSPIRE-harmonised") | Kadaster; distributed by PDOK | https://service.pdok.nl/kadaster/ad/atom/index.xml | BAG addresses in the INSPIRE data model | ATOM download feed | CC0 | Feed updated 2 Sep 2026 | confirmed |
| BAG dataset record | Kadaster | https://data.overheid.nl/en/dataset/10491-bag | Catalogue record: licence "Publiek domein", access public, labelled "High Value Dataset - EU", category Geospatial | Web page | Public domain | Record updated 05-08-2026 | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address lookup for the Netherlands | API, no key; 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/nl/countrywide.json | A cached upload `verblijfsobject.csv.zip` dated 2026-06-03 | Free download, needs a logged-in account | CC0 1.0, no attribution required | Not automatic: the source reads the upload of 2026-06-03 | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Address points for the Netherlands | GeoParquet, no account | Set per country; not recorded here | Per release | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- **PDOK Locatieserver ("location server"), geocoding.** "Een open en gratis geocodeerservice" with suggest, lookup, free and reverse APIs. No key. Documentation: https://api.pdok.nl/bzk/locatieserver/search/v3_1/ui/ ; page: https://www.pdok.nl/pdok-locatieserver
- A call such as https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=Hofweg+1+Den+Haag&rows=1&fq=type:adres returns `postcode`, `huis_nlt` (house number with suffix), `nummeraanduiding_id`, `centroide_ll` (WGS84 point) and `centroide_rd`, with source "BAG". The index held 10,085,895 documents of type `adres` on 11 Nov 2026 (https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?q=*:*&rows=0&fq=type:adres). That is a count of the BAG-derived index, not of the extract.
- **Fair-use limit of the Locatieserver:** none found. The Locatieserver page states no limit and the responses carry no rate-limit headers.
- **PDOK OGC API (Features and Vector Tiles).** `https://api.pdok.nl/kadaster/bag/ogc/v2`, no key, updated daily. Collections: `adres`, `ligplaats`, `pand`, `standplaats`, `verblijfsobject`, `woonplaats` (https://api.pdok.nl/kadaster/bag/ogc/v2/collections?f=json).
- **PDOK WFS and WMS.** `https://service.pdok.nl/lv/bag/wfs/v2_0` and `https://service.pdok.nl/lv/bag/wms/v2_0`, no key, fees "none", CC0. The WFS has the types pand, ligplaats, standplaats, verblijfsobject and woonplaats; it has no `adres` type.
- **Kadaster BAG API Individuele Bevragingen ("individual queries").** Free, but an API key must be requested by form; without a key the API returns 401. At most 50,000 requests per day and 50 per second. Not meant for bulk queries. Page: https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-api-individuele-bevragingen ; usage rules: https://www.kadaster.nl/-/richtlijnen-voor-het-gebruik-van-de-bag-api-individuele-bevragingen

### Caveats and recent changes

- **The PDOK services are incomplete for addresses.** PDOK states that only the main address is included, so objects with several addresses (main and secondary) are not complete and not all BAG addresses are present.
- **Two public-domain labels are in use:** CC0 on the PDOK feed and services, Public Domain Mark 1.0 on the Kadaster page. The data.overheid.nl record says "Publiek domein".
- **Kadaster's stated file size is out of date.** Its free-download page (https://www.kadaster.nl/-/gratis-download-bag-extract) says "ongeveer 2,8 GB" and links https://service.pdok.nl/kadaster/adressen/atom/v1_0/downloads/lvbag-extract-nl.zip ; that link serves the same 3,657,771,488-byte file as the PDOK feed.
- **Moved URLs.** The Kadaster page `.../bag-2.0-extract` now redirects to https://www.kadaster.nl/zakelijk/producten/adressen-en-gebouwen/bag-extract . The earlier OGC API path `https://api.pdok.nl/lv/bag/ogc/v1` returns 404.
- **The SOAP retrieval method with username and password ends in Q1 2027.** The BAG Extract Ophaal API (API key) replaces it; a SOAP route with a PKI-O certificate is also listed and not marked as ending. This concerns the paid deliveries below.
- **OpenAddresses is behind the source:** its Dutch source reads an upload dated 2026-06-03.
- **Postcodes in the BAG are free to reuse.** A trade journal (Binnenlands Bestuur, https://www.binnenlandsbestuur.nl/digitaal/ondermijning/bag-met-postcodegegevens-wordt-vrij-herbruikbaar) reports that the ministry ended the "postcodeconvenant" with TNT Post (now PostNL) in February 2011, that PostNL lost its court case, and that the restriction ended on 1 February 2012. This is a press report, not an official source.

### Not free or not available

- **Mutation subscriptions (Kadaster, ordered through Mijn Kadaster).** National or municipal monthly mutations: EUR 14.50 per month plus EUR 219 one-time. National daily mutations: EUR 219 per month plus EUR 219 one-time. Government bodies get them free.
- **One-off extract for a single municipality:** EUR 219 per delivery. The national extract is free.

### Could not be verified

- **PostNL's own Postcodetabel as a paid product** (https://www.postnl.nl/zakelijke-oplossingen/slimme-dataoplossingen/postcodetabel/): the page returned an HTTP/2 stream error and no content.
- **Contents of the GeoPackage.** Its layers and columns were not opened, so whether it carries secondary addresses, and which address fields it holds, is not established. The same applies to the internal layout of the XML extract.
- **An Esri document said to date a government-PostNL covenant on BAG postcode use to early 2014,** which does not match the 2012 date above: not pursued.
- **Whether the EU High-Value Datasets regulation changed BAG distribution** beyond the label: not pursued.
- **CBS files linking postcode and house number to neighbourhoods:** not checked.
