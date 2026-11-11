## Croatia (HR)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes | DGU "Adrese - INSPIRE", from the Register of Spatial Units | Bulk GML zip from an ATOM feed, no registration | Otvorena dozvola (Croatian Open Licence); commercial use allowed | Yes, EPSG:3035 | Yes | Weekly |

**In short.** Use the weekly zip from the State Geodetic Administration (DGU): about 1.68 million house-number addresses with coordinates and postcodes, no login, under the Croatian Open Licence. The catch is the format. The download was found only as INSPIRE GML: one 2.6 GB XML file written as a single line, in EPSG:3035, with no CSV and no open WFS. Street, settlement and postcode come either from the linked component files or from one free-text string per address.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Adrese - INSPIRE, derived from the Registar prostornih jedinica (RPJ, Register of Spatial Units) | Državna geodetska uprava (DGU, State Geodetic Administration) | Zip: https://geoportal.dgu.hr/services/atom/INSPIRE_Addresses_%28AD%29.zip ; address feed: https://geoportal.dgu.hr/services/atom/ad/xml ; service feed: https://geoportal.dgu.hr/services/atom/xml ; portal record: https://data.gov.hr/ckan/api/3/action/package_show?id=adrese-inspire ; metadata: https://geoportal.nipp.hr/geonetwork/srv/api/records/d3104048-688a-4305-9471-77288cc6e350/formatters/xml | 1,683,548 addresses (publisher's figure, from the file's `numberMatched` attribute), each with a point, a house number, and links to street, postal descriptor and two admin-unit names. Counted: 54,465 street names, 900 postal descriptors, 6,760 admin-unit names | Zip of 89,997,286 bytes, no login, no key. Four GML files, 2.68 GB unpacked; `Address.gml` alone is 2,614,426,484 bytes | Otvorena dozvola (OD), https://data.gov.hr/id/licence/otvorena-dozvola-rh | Weekly. The zip served on 2026-11-11 was generated on 2026-11-08 | confirmed (total address count not recounted) |
| Zagreb: Registar naziva ulica - adresna prostorna jedinica (street-name register) | Grad Zagreb, on data.gov.hr | https://data.gov.hr/ckan/api/3/action/package_search?q=registar+prostornih+jedinica&rows=10 | Street names only; file not opened | CSV and XLSX | Otvorena dozvola | Not checked | confirmed (listing only) |
| Rijeka: adrese po MO s ukupnim brojem stanova po adresi (addresses per local board with the number of flats) | Grad Rijeka, on data.gov.hr | https://data.gov.hr/ckan/api/3/action/package_search?q=adrese&rows=15 | Addresses per local board with flat counts; file not opened | XLS | CC BY 4.0 | Not checked | confirmed (listing only) |
| Preuzimanje podataka o poštanskim uredima (post office data downloads) | Hrvatska pošta (Croatian Post) | Page: https://www.posta.hr/preuzimanje-podataka-o-postanskim-uredima ; settlements: https://www.posta.hr/mjestaRh.aspx?vrsta=xml ; Zagreb streets: https://www.posta.hr/zagrebulice.aspx?vrsta=xml | Settlements with postcode (6,787 records: `brojPu` postcode, `nazivPu` post office, `naselje` settlement, `zupanija` county); Zagreb streets with delivery post office (5,378 rows, some with house-number ranges); post offices; parcel lockers | Excel and XML, no login | None stated on the page | Not stated | confirmed |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Croatia | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Croatian countrywide source | OpenAddresses | Source file: https://github.com/openaddresses/openaddresses/blob/master/sources/hr/countrywide.json ; downloads: https://batch.openaddresses.io | The same DGU zip, parsed from the one-string address field with regular expressions | Free download; needs a logged-in account | Recorded there as "no limitations to public access" | Marked weekly; source added 2024-04-25 | confirmed |
| Overture Maps addresses | Overture Maps | Release 2026-10-21.0 | Croatia is among the 19 EU countries covered | GeoParquet, no account | Per country | Per release | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- INSPIRE WMS, view only, anonymous: https://geoportal.dgu.hr/services/inspire/ad/wms?service=WMS&version=1.3.0&request=GetCapabilities . Layers `AD.Address` and `AD.Address.Default`.
- A second WMS, listed as "registrirani korisnici" (registered users): `https://geoportal.dgu.hr/services/auth/inspire/ad/wms`. It answered GetCapabilities without credentials.
- No open WFS. https://geoportal.dgu.hr/services/inspire/ad/wfs?service=WFS&version=2.0.0&request=GetCapabilities answers with the exception "Service WFS is disabled". So does `/services/auth/inspire/ad/wfs`.
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.

### Caveats and recent changes

- Format: INSPIRE Addresses GML 3.2.1 (schema `ad/4.0`), a WFS 2.0 FeatureCollection saved as a single line of XML. It must be stream-parsed. The root element says `numberMatched="1683548"` but also `numberReturned="10000"` with a `next` link: the file is built from 10,000-record WFS pages.
- Coordinates are ETRS89/LAEA, EPSG:3035, and need reprojecting for most uses.
- Reading an address: each record has a house number (`LocatorDesignator`, type `addressNumber`), `validFrom`, `beginLifespanVersion` and four component links. The identifier is a `localId` such as `KB.0000000135` in namespace `HR.DGU.RPJ`. `ad:alternativeIdentifier` holds the whole address as one string, for example "Brežna ulica 33 Andraševec 49243 Oroslavje" (street, number, settlement, 5-digit postcode, post town).
- What the point marks is not stated. `ad:specification` and `ad:method` are nil ("unpopulated") in all 9,030 records sampled, so the file does not say whether a point is on the building, the entrance or the parcel.
- Text is Latin script with Croatian diacritics, UTF-8.
- Licence terms, read in the official gazette NN 67/2017 (https://narodne-novine.nn.hr/clanci/sluzbeni/2017_07_67_1577.html): the Open Licence allows commercial and non-commercial use, free of charge, without limit in space or time. The user must name or link the source and give the date of last change. A ban on commercial use cannot be added. The licence page itself, https://data.gov.hr/otvorena-dozvola , is JavaScript-only.
- Contradictory label: the metadata, both ATOM feeds (`rights`) and the WMS (`AccessConstraints`) also carry "ograničenje javnog pristupa prema članku 13 stavku 1 točki (e) INSPIRE Direktive" (a limit on public access under Article 13(1)(e) of the INSPIRE Directive). The portal record, the metadata's use constraint and the WMS `Fees` element all state the Open Licence, and the file downloads anonymously.
- No charge: NN 39/22, Article 1(3) (https://narodne-novine.nn.hr/clanci/sluzbeni/2022_03_39_477.html) says real costs are not charged for access through network services or other electronic access points. Paragraph (4) says data issued in other ways are charged.
- The portal record is new. `adrese-inspire` was created on 2026-10-14 and modified on 2026-10-22. The older address https://data.gov.hr/ckan/en/dataset/adrese returns HTTP 404. The record also carries a stale `temporal_end` of 2019-12-05.
- The ATOM feed's `length` attribute (84,406,413) does not match the served file (89,997,286 bytes). Do not validate the download against it.
- High-value-dataset status: the record is flagged as an HVD in category "Addresses" (`http://data.europa.eu/bna/c_c3de25e4`) under Regulation (EU) 2023/138. On data.europa.eu it is the only Croatian dataset in that category.
- Hrvatska pošta files carry no licence or reuse terms. An OpenStreetMap mailing-list post quotes a 2014 e-mail from Hrvatska pošta giving the OSM community permission (https://lists.openstreetmap.org/pipermail/talk-hr/2015-January/002317.html). That is not a published licence.
- Hrvatska pošta's Zagreb street list gives ranges, for example "ALEJA GRADA BOLONJE 2 - 68" with post office "10090 ZAGREB-SUSEDGRAD".

### Not free or not available

- Download in any format other than INSPIRE GML (CSV, GeoPackage, regional split): none found on the ATOM feed or the portal record.
- Working address WFS: by agreement only. "Adrese - WFS INSPIRE (sporazum)", `https://geoportal.dgu.hr/services/sla/inspire/wfs_ad/wfs?authKey=…`, is open to public-law bodies with special user status that sign a data-use protocol with DGU (https://registri.nipp.hr/api/izvori/452/pdf/).

### Could not be verified

- That every address is at locator level `siteLevel` (one record per house number, no entrance or dwelling level): true for the first 9,030 records; the whole file was not read.
- Whether DGU offers a free geocoding or address-autocomplete API: one web search with Croatian keywords found none. The geoportal's own search box was not tested.
- Whether the RPJ source data are offered in another form, such as a SOAP service: the document said to mention it, https://www.bib.irb.hr:8443/1091653/download/1091653.HKOIG-Zbornik-radova-2019-web-81-86.pdf , returns HTTP 403.
- Whether the 900 postal descriptors cover every delivery postcode: not compared with Hrvatska pošta's 6,787-row list.
- Content of the Zagreb and Rijeka city files: not opened.
