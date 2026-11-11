## Portugal (PT)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | Base Nacional de Moradas (INE); stale, files from 2018 | GML per municipality from an ATOM feed, no registration | CC BY 4.0 | yes, EPSG:4258, 4326 and 3763 (islands 5014-5016) | yes | none seen since 2018 |

**In short.** The only national source is INE's Base Nacional de Moradas (BNM, National Address Base): door numbers, floor and unit designators, postcodes and coordinates for all 308 municipalities, CC BY 4.0, downloadable without registration. The files are a 2017 version generated in January 2018, although the metadata calls the update frequency "continuous". Addresses are at unit level, so one door number appears once per floor and unit. There is no national geocoding API; Eurostat's GISCO Address API covers Portugal from the same INE data.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Base Nacional de Moradas (BNM, National Address Base), INSPIRE Addresses | Instituto Nacional de Estatística (INE) | https://inspire.ine.pt/AD/atom/downloadservice.html ; portal record: https://dados.gov.pt/datasets/base-nacional-de-moradas | Addresses for 308 municipalities, built from the Ficheiro Nacional de Alojamentos (national dwellings file). Point per address, door number, floor and unit designators, postcode, street name, administrative units | Eight regional ATOM feeds; one zipped GML per municipality in four CRS. No registration or key | CC BY 4.0 (national portal and national catalogue records); the feeds say "Sem restrições" (no restrictions) | Version 2017, generated 2018-01-22; file probed last modified 17 April 2018. Metadata says "continuous" | confirmed |
| Números de Polícia (door numbers), Cascais | Municipality of Cascais | https://dados.gov.pt/datasets/geocascais-numerospolicia | Municipal door-number data | CSV, GeoJSON, JSON, SHP, KML, GeoPackage, DXF | CC BY | Last modified 2026-11-09 | confirmed |
| Toponímia: Números de Polícia (street names: door numbers), Oeiras | Municipality of Oeiras | https://dados.gov.pt/datasets/toponimia-numeros-de-policia | Municipal door-number data | WFS | CC BY | Last modified 2026-10-19 | confirmed |
| Toponímia da rede viária e numeração de polícia (street names and door numbering), Porto de Mós | Municipality of Porto de Mós | https://dados.gov.pt/datasets/toponimia-da-rede-viaria-e-numeracao-de-policia-porto-de-mos | Municipal street names and door numbers | WFS | Unknown | Modified 2025-10-17 | confirmed |
| Toponímia e numeração de polícia, Alto Tâmega e Barroso | Alto Tâmega e Barroso | https://dados.gov.pt/datasets/toponimia-e-numeracao-de-policia-no-alto-tamega-e-barroso | Street names and door numbers for the area | GeoPackage | CC BY | Modified 2023-03-17 | confirmed |
| Toponímia de Lisboa (Lisbon street names) | Municipality of Lisbon | https://dados.gov.pt/datasets/toponimia-de-lisboa | Street names only, no door numbers | GeoJSON | CC0 | Not stated | confirmed |
| CTT postcode file | CTT (postal operator) | https://www.ctt.pt/feapl_2/app/restricted/postalCodeSearch/postalCodeDownloadFiles.jspx | Postcode files | The page redirects to a login; an account is required | Terms not readable without logging in | Not known | confirmed (login required) |
| codigos_postais, a community conversion of the CTT file | centraldedados (third party) | https://github.com/centraldedados/codigos_postais | Postcodes for mainland and islands, more than 300,000 entries of three kinds (customers with their own postcode, localities, streets and street segments) | GitHub repository | PDDL, which the republisher itself calls a presumption that the data are public | Not stated | confirmed |
| Base Geográfica de Edifícios (BGE, Geographic Base of Buildings) | INE | https://snig.dgterritorio.gov.pt/rndg/srv/api/records/ad14e031-a2c1-4673-a85b-3b57b0df3767/formatters/xml | Building points georeferenced in the 2011 census, with residential buildings added or corrected in 2021 | Not open: limited public access, no download or service | - | Metadata dated 2026-06-17, maintenance "irregular" | corrected |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Forward and reverse lookup of Portuguese addresses: door number, street, city, postcode, coordinates. Declared source: "© Instituto Nacional de Estatística" | No key. Lookup only, 1,000-row cap, no bulk download | None stated | Not stated | corrected |
| OpenAddresses | OpenAddresses | https://batch.openaddresses.io ; source definition: https://github.com/openaddresses/openaddresses/blob/master/sources/pt/countrywide.json | Countrywide layer converted from the INE service, with postcodes | Free download, needs a logged-in account | CC BY 4.0, attribution "Instituto Nacional de Estatística, I.P." | Cached conversion dated 2026-02-23 | confirmed |
| Overture Maps addresses, release 2026-10-21.0 | Overture Maps | https://docs.overturemaps.org/guides/addresses/ | 5,607,450 Portuguese addresses (publisher's figure), from INE as distributed by OpenAddresses | GeoParquet, no account | No licence named for Portugal | Source pulled 2026-10-15 | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Direct file download | CC BY 4.0 | Regenerated daily | confirmed |

### Free APIs and services

- **GISCO Address API (Eurostat)**, https://gisco-services.ec.europa.eu/addressapi : no key, forward and reverse lookup, built on INE data. `/reverse?x=-9.1411&y=38.7128` returned five results, for example door 11, street "DUQUE", Lisboa, postcode 1200-158. `/search?country=PT&postcode=1100-048` returned two addresses on "AUGUSTA". Street names are stored without the type word: a search for road "Rua Augusta" returned nothing.
- **INE INSPIRE ATOM download service**, https://inspire.ine.pt/AD/atom/downloadservice.html : eight dataset feeds (Norte, Centro, Área Metropolitana de Lisboa, Alentejo, Algarve, Madeira, Açores central and eastern groups, Açores western group). Example feed: https://inspire.ine.pt/AD/atom/CDG_AD_BNM_pc_AML_Atom.xml . Example file: https://inspire.ine.pt/AD/atom/gml/Addresses_1106_EPSG4326.zip (Lisbon).
- **Municipal WFS**: Oeiras and Porto de Mós publish their door-number layers as WFS (see the table).
- **National geocoding API**: none found.

### Caveats and recent changes

- The data are old. The Lisbon file carries `versionId` 2017, `validFrom` 2018-01-01, a generation timestamp of 2018-01-22 and a server date of 17 April 2018. Feed entries are dated 2017-05-17 and the feeds 2019-11-11. The portal record gives frequency "continuous" and last modification 2025-01-08, but the files did not change.
- No newer BNM release and no other national address-point dataset: none found. Searched: data.europa.eu for "moradas" in Portugal (18 results, the BNM the only national address dataset).
- Addresses are at unit level. Each locator carries a door number (`buildingIdentifier`), a floor (`floorIdentifier`) and a unit (`unitIdentifier`, for example "ESQ"); the point is placed at the building. An import that wants one record per door number has to collapse them.
- Counts of "feature members" include postal descriptors, street names and administrative units alongside addresses, so they are not address counts.
- The feeds are not clean. In the Norte, Centro, Lisbon-area and Alentejo feeds, 139 EPSG:3035 entries link to `Addresses_1007_EPSG3035.zip` instead of their own municipality's file, so the EPSG:3035 links cannot be trusted; the EPSG:3763, 4258 and 4326 links are consistent. Municipality 0914 is listed in both the Norte and Centro feeds, and Madeira lists 12 entries per CRS for 11 codes.
- CRS: mainland files come in EPSG:3763, 4258, 4326 and 3035. The islands replace 3763 with EPSG:5014 (Açores western group), 5015 (Açores central and eastern groups) or 5016 (Madeira).
- In the EPSG:4326 files `gml:pos` is latitude first.
- Files are large once unpacked: the Lisbon ZIP is 21,760,599 bytes and its GML 942,686,107 bytes.
- `HEAD` requests to the ZIP files get no HTTP response; `GET` (also ranged) works.
- The portal description speaks of addresses of mainland Portugal ("Portugal Continental"), but the service also has feeds for Madeira and the Azores.
- The portal record is tagged as a High-Value Dataset under Regulation (EU) 2023/138. INE's own HVD page (https://www.ine.pt/scripts/hvd/en/geo.html) shows the National Address Base only; its metadata link for the address base returned HTTP 404.
- INE gave the Portuguese OpenStreetMap community written permission to import the data (https://wiki.openstreetmap.org/wiki/Portugal/Projetos/Importa%C3%A7%C3%A3o_de_endere%C3%A7os).
- Overture names no licence for its Portuguese addresses, although the same data are CC BY 4.0 at the national portal.

### Not free or not available

- National geocoding API: none found. The GISCO Address API fills the gap for lookups.
- Base Geográfica de Edifícios (buildings base): not open. Its metadata record declares "Acesso público limitado de acordo com o Artigo 13(1)(f) da Diretiva INSPIRE" (limited public access) and offers no download or service.
- CTT postcode file: behind a login, and its terms of use could not be read. The only licence in circulation is a third party's presumption (PDDL), so it cannot be treated as open data.
- Open postcode dataset on the national portal: none found. A search of dados.gov.pt for "códigos postais" returned zero datasets (https://dados.gov.pt/api/1/datasets/?q=moradas&page_size=12 for "moradas" returned three, of which only the BNM is an address dataset).
- Door-number datasets for the municipalities of Lisbon and Porto: none found. Searched: dados.gov.pt and data.europa.eu for "números de polícia"; the municipal portals themselves were not searched.

### Could not be verified

- Total size of one CRS set, 471.7 MB zipped: researcher's count. The feeds carry no sizes and it would take 308 requests to recount.
- 6,475,977 feature members over the 308 files: researcher's count. Only Lisbon's 336,033 was re-read.
- 324,640 Lisbon addresses with a locator: researcher's count; it needs the full file.
- That every one of the 308 files dates from 2018: the dates were read on the Lisbon file only.
- That the BNM leaves out businesses and facilities: no such sentence was found on the OpenStreetMap wiki page cited for it.
- That the CTT account is free: only the login requirement was seen; no account was created. CTT's terms of use, update frequency and position on commercial reuse are unknown for the same reason.
- The INSPIRE Geoportal record for the buildings base: the Geoportal's TLS certificate had expired on 2026-11-11; the national catalogue record was used instead.
