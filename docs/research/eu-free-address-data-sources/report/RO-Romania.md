## Romania (RO)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| No | Substitute: Poșta Română postcode file of 2016; no house-number points | Bulk XLS, no registration | OGL-ROU-1.0 | No | Yes, to street level per the publisher | None; newest file is from 2016 |

**In short.** No free national source of house-number addresses with coordinates was found. The official register, RENNS, was reachable only through the cadastre agency's geoportal, and that geoportal has been offline since the cyberattack of 14 July 2026: on 2026-11-11 its host names no longer resolve, and no restart date is announced. What remains is a 2016 postcode table from Poșta Română and municipal street lists, none with address points. Any `geoportal.ancpi.ro` link in older documentation is dead.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| RENNS, Registrul Electronic Național al Nomenclaturilor Stradale (National Electronic Register of Street Nomenclatures) | Agenția Națională de Cadastru și Publicitate Imobiliară (ANCPI, the cadastre agency) | EU catalogue record: https://data.europa.eu/api/hub/search/datasets/-aa3a39d5-b7d6-4297-8cb9-6be9e470a1be- ; view service record: https://data.europa.eu/api/hub/search/datasets/-5dcafddb-7729-4655-8c5c-845ae8538bfc- ; download service record: https://data.europa.eu/api/hub/search/datasets/-d8d123a0-5f26-40af-bd73-b78ca7609c9c- | Per the catalogue: points with "the administrative numbers of urban-type localities", collected from 2009 on from town halls and prefectures | Offline. The WMS and the ATOM download feed sit on `geoportal.ancpi.ro`, which does not resolve | Not established; see "Could not be verified" | Download feed last updated 2019-09-12 | confirmed (services offline) |
| Municipal "nomenclator stradal" (street list) datasets: Cluj-Napoca (2020), Bucharest Sector 2 (2021), Copșa Mică, Săliștea, Bobicești, Puiești, Timișoara (2014) | The municipalities, on data.gov.ro | https://data.gov.ro/api/3/action/package_search?q=nomenclator+stradal&rows=12 | Street lists, not address points; files not opened | File downloads | CC BY 4.0; Timișoara OGL-ROU-1.0 | As dated | confirmed (listing only) |
| "Nomenclator strazi judetul …" (street list per county) | Ministerul Finanțelor Publice (Ministry of Public Finance), on data.gov.ro | https://data.gov.ro/api/3/action/package_search?q=strazi&rows=12 | Street lists per county; files not opened | File downloads | OGL-ROU-1.0 | 2016 | confirmed (listing only) |
| Coduri postale Romania (postcodes of Romania) | Poșta Română (Romanian Post), on data.gov.ro | Dataset page: https://data.gov.ro/dataset/coduri-postale-romania ; 2016 file: https://data.gov.ro/dataset/3eb7dc31-e53e-4c09-b2e2-87c909e68fb6/resource/29a5c89e-0f23-4a42-aa05-765ef04177b6/download/infocod-cu-siruta-mai-2016.xls | 6-digit postcodes, "detailed down to street level" per the dataset description. XLS files "infocod" of October 2013, May 2016 and September 2016 (with SIRUTA codes). Content not parsed | XLS download, no login; the 2016 file is 7,845,888 bytes | OGL-ROU-1.0 | Record last modified 2016-09-06 | confirmed (file not opened) |
| Caută cod poștal (postcode search) | Poșta Română | https://www.posta-romana.ro/cauta-cod-postal.html | Postcode look-up, described as updated periodically | Web look-up only; no file link on the page | Not stated | Not stated | confirmed |
| SIRUTA, register of administrative-territorial units | Institutul Național de Statistică (National Institute of Statistics), on data.gov.ro | https://data.gov.ro/api/3/action/package_search?q=SIRUTA&rows=12 | Administrative units down to settlement level; no streets, no addresses | File downloads | CC BY 4.0 | Latest "SIRUTA_s1 2026", modified 2026-08-11 | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Romania | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, two city sources | OpenAddresses | https://github.com/openaddresses/openaddresses/blob/master/sources/ro/bucharest.json ; https://github.com/openaddresses/openaddresses/blob/master/sources/ro/bucharest-metro.json ; downloads: https://batch.openaddresses.io | No countrywide source. The output is four towns around Bucharest, frozen in 2020 | Free download; needs a logged-in account | None recorded | Frozen 2020 | confirmed; upstream server status corrected |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- None from a national publisher is working. The RENNS view service (WMS), `https://geoportal.ancpi.ro/inspireview/rest/services/AD/AD_View/MapServer/exts/InspireView/service?SERVICE=WMS&REQUEST=GetCapabilities`, is offline with its host.
- Poșta Română's postcode search, https://www.posta-romana.ro/cauta-cod-postal.html , is a web look-up, not an API.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.
- The Esri Romania server behind the two OpenAddresses sources, `https://maps-gisportal.esriro.ro/arcgis/rest/services/SureData/SureData/MapServer/1` and `/2`, resolves and answers, but with a self-signed TLS certificate. A client that checks certificates cannot use it. Its content was not read.

### Caveats and recent changes

- Outage timeline. All ANCPI systems went down on 14 July 2026; ANCPI announced the attack on 15 July (https://agerpres.ro/2026/07/15/agentia-nationala-de-cadastru---tinta-unui-atac-informatic-datele-sunt-in-siguranta-si-se-lucreaza-l--1576362). On 17 August the Government said e-Terra worked and the other systems, Geoportal included, were still down (https://startupcafe.ro/situatia-de-la-cadastru-aplicatia-e-terra-functioneaza-iar-volumul-ridicat-de-solicitari-este-in-curs-de-procesare-celelalte-sisteme-ancpi-sunt-tot-blocate-guvern-105217).
- ANCPI's own notice, dated 20 August 2026 and still the only page on https://www.ancpi.ro/ , says the restart concerns "exclusively" e-Terra. The other platforms "și Geoportal" will return in stages, each restart announced publicly. The notice names "Geoportal", not RENNS.
- State on 2026-11-11: `geoportal.ancpi.ro` and `renns.ancpi.ro` return NXDOMAIN from three public resolvers (1.1.1.1, 8.8.8.8, 9.9.9.9). No announcement of a return was found on ancpi.ro or in one web search in Romanian.
- A Digi24 headline of 2026-07-21 says ANCPI is moving its applications to the Government Cloud (https://www.digi24.ro/digieconomic/digital/ancpi-muta-aplicatiile-in-cloudul-guvernamental-dupa-atacul-cibernetic-cand-ar-putea-reveni-serviciile-110985). Only the headline was read.
- Forbes România (3 September 2026) reports that the attackers had access for 86 hours before detection, and quotes a ransom note that claims a copy of the source code of eTerra and RENNS (https://www.forbes.ro/hackerii-au-avut-acces-la-sistemele-ancpi-timp-de-86-de-ore-inainte-de-a-fi-detectati-519051). That is the attackers' claim, and it is about code, not data.
- What the download was before the outage. An archived copy of the ATOM feed (http://web.archive.org/web/20260212012623/http://geoportal.ancpi.ro/inspiredownload/rest/directories/arcgisforinspire/AD/AD_Download_MapServer/Main_ATOM_AD.xml) shows one dataset, `AD.RENNS` / `RO.ANCPI`, as a file geodatabase zip in EPSG:4258, last updated 2019-09-12. Its `rights` element reads "(a) the confidentiality of the proceedings of public authorities, where such confidentiality is provided for by law".
- That feed's extent element reads "23,6866 44,9372 23,7291 44,9611": two coordinate pairs with decimal commas, not a valid polygon. Read as a box it is about 0.04° by 0.02°. The dataset-level feed (`AD_Dataset.xml`) has no archived copy, so the size, date and extent of the old download are unknown.
- The EU catalogue gives EPSG:3844 (Stereo 70) as the dataset's reference system; the download feed gave EPSG:4258.
- Legal basis: Government Decision 777/2016 governs RENNS. A private copy of the gazette text (Monitorul Oficial 867/2016, on legeaz.net) says RENNS is built, updated and administered by ANCPI (Art. 1(2)) and that its information is public, "au caracter public" (Art. 1(3)). It was not read on an official legislation site.
- Other dead ends: Romania's INSPIRE portal host, https://geoportal.gov.ro/ , resolves but accepts no connection on ports 443 and 80. The former EU INSPIRE Geoportal was decommissioned on 1 July 2026; its host now serves an expired TLS certificate, so the RENNS metadata record there (https://inspire-geoportal.ec.europa.eu/srv/api/records/%7B5DCAFDDB-7729-4655-8C5C-845AE8538BFC%7D) cannot be read.
- Postcode file: the newest resource is labelled "Sept.2016" but its file name is `infocod-cu-siruta-mai-2016.xls`. The 6-digit postcode has been in force since 1 May 2003. The data is ten years old.
- High-value-dataset status: no Romanian dataset of any HVD category is flagged in data.europa.eu. The three RENNS records there have `is_hvd: false`.

### Not free or not available

- National house-number addresses with coordinates: none found. Searched: data.gov.ro ("RENNS": 0 results; "adrese": 4 unrelated results; "ANCPI": 121 datasets, none about addresses or streets; "nomenclator stradal" and "strazi": street lists only) and the EU catalogue data.europa.eu (three RENNS records, all pointing to offline services).
- RENNS view and download services: offline since 14 July 2026. The download feed was at `http://geoportal.ancpi.ro/inspiredownload/rest/directories/arcgisforinspire/AD/AD_Download_MapServer/Main_ATOM_AD.xml`.
- Postcode file newer than 2016: none found on data.gov.ro. Poșta Română's site offers the look-up only.
- Overture Maps addresses (release 2026-10-21.0): no Romanian data.

### Could not be verified

- The use terms in RENNS's INSPIRE metadata: a statement that the data "nu se comercializează" (are not sold), and a limit on public access under Article 13(1) of the INSPIRE Directive and its letter. The servers holding the metadata are offline or fail TLS, and the EU catalogue records lack the wording. Only the letter (a) text in the archived download feed was seen.
- Whether RENNS was ever open as a bulk download, and whether the downloadable file covered the country or a sample area: the file and its feed are offline and there is no archive copy.
- Content of the 2016 postcode XLS (columns, row count, whether it has house-number ranges): the file was not downloaded or parsed.
- Whether Poșta Română publishes a newer postcode file anywhere else: not searched beyond data.gov.ro and the look-up page.
- Content of the municipal and county street-list files: not opened.
- Content and licence of the Esri Romania "SureData" layers: the server's self-signed certificate was not bypassed.
