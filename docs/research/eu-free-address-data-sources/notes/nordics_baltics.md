# Free online address data sources: Denmark, Finland, Sweden, Estonia, Latvia, Lithuania (state as of 11 November 2026)

Method note: every official page below was opened on 2026-11-11. "Probed" means I made the HTTP request myself that day and report the status code, size or record count I got. Three official sites are JavaScript-only (dataforsyningen.dk, geotorget.lantmateriet.se, registrucentras.lt); for those I read the same content through the site's own public data endpoints or through catalogue/portal records, and say so. One key question per country; the eight sub-questions of the brief are answered inside each country's "Cited Findings" under bold labels.

## Denmark - which free address data sources exist?

### Takeaway
Danmarks Adresseregister (DAR) is free under CC BY 4.0, but the well-known keyless DAWA API was shut down on 1 October 2026 (it now answers HTTP 410); bulk data and lookups now come from Datafordeleren, which needs a free account plus API key/OAuth. Autocomplete moved to a new service, Adressevælger (adressevaelger.dk), which currently needs only a dummy token.

### Cited Findings

**Authoritative register and publisher**
- Danmarks Adresseregister (DAR, "Danish Address Register") is "the authoritative register for Denmark's road names and addresses with associated postcode and supplementary town names"; it is published on Datafordeleren (The Danish Data Distributor) - [Datafordeler: DAR data overview](https://datafordeler.dk/dataoversigt/danmarks-adresseregister-dar/)
- Klimadatastyrelsen (KDS, Danish Agency for Climate Data; formerly SDFI/SDFE) is responsible for the IT system and the distribution of DAR data; addresses and road names are set by the municipal address authorities - [KDS Confluence: Danmarks Adresseregister (DAR), page last modified 6 Oct 2026](https://confluence.kds.dk/pages/viewpage.action?pageId=10616849)
- About 3.8 million addresses and about 110,000 road names are registered; every address has a geographic coordinate, an unambiguous address designation and a unique key - [KDS Confluence: DAR](https://confluence.kds.dk/pages/viewpage.action?pageId=10616849)
- The Address Act requires the data to be available without payment ("det er indskrevet i adresseloven at data skal være til rådighed uden betaling") - [KDS Confluence: DAR](https://confluence.kds.dk/pages/viewpage.action?pageId=10616849)

**DAWA shutdown (the big 2026 change)**
- "DAWA er lukket den 1. oktober 2026" - address data must now be fetched from Datafordeleren; all web services under DAWA (those described on dawadocs.dataforsyningen.dk) and the existing address WFS services stopped on 1 Oct 2026. Page title: "DAWA - Danmarks Adressers Web API (Opdateret 1/10 - 2026)", record modified 26 Oct 2026 - [Dataforsyningen: DAWA product page](https://dataforsyningen.dk/data/4924) (JS page; text read through the site's own search backend `https://dataforsyningen.dk/es/products/_search`)
- Probed 2026-11-11: `https://api.dataforsyningen.dk/adresser?q=...` and `https://dawa.aws.dk/adresser?q=...` both return HTTP 410 with body `"The requested resource is no longer available and will not be available again."`; `https://dawadocs.dataforsyningen.dk/` redirects to the closure page - [api.dataforsyningen.dk/adresser](https://api.dataforsyningen.dk/adresser), [dawa.aws.dk/adresser](https://dawa.aws.dk/adresser)
- The closure date moved: a news item first published 16 Dec 2025 and updated 12 Jun 2026 gives 1 October 2026; an earlier notice in the same news stream said "Som udmeldt lukker DAWA d. 1. juli 2026" - [Dataforsyningen news 5117: "Distribution af registre fra DAWA lukker (opdateret 12/6 - 2026)"](https://dataforsyningen.dk/news/5117)
- DAWA "was established as a temporary solution to distribute address data before Datafordeleren was in operation"; DAWA also carried DAGI (postcodes, parishes, municipalities), GeoDanmark buildings, cadastre and place names, all gone with it - [Dataforsyningen news 5117](https://dataforsyningen.dk/news/5117)
- Earlier partial removals: BBR data 3 Apr 2024; zone data 11 Sep 2024; DAWA WMS 14 Jan 2025; large-recipient postcodes ("stormodtagerpostnumre") removed 28 Feb 2025 after Trafikstyrelsen phased them out on 1 Jan 2025 - [Dataforsyningen: DAWA product page](https://dataforsyningen.dk/data/4924)
- Unlike DAWA (whose code was on GitHub), the replacement Adressevælger cannot be self-hosted ("Kan man self-hoste API'en ligesom man kan i dag vha. Github DAWA siden? Nej, dette bliver ikke muligt") - [KDS Confluence: Adressevælger FAQ](https://confluence.kds.dk/display/ADV/FAQ)

**Bulk download (what replaces DAWA replication)**
- Since 28 April 2025 Datafordeleren offers entity-based file downloads ("fildownload") for DAR, the cadastre, GeoDanmark, DAGI and place names as the replacement for DAWA replication, for users needing daily updates - [Dataforsyningen: DAWA product page](https://dataforsyningen.dk/data/4924)
- DAR file download: types "Totaldownload, deltadownload"; formats "JSON og CSV"; per-municipality downloads for entities with municipality code or geometry; current version 3; security zone 0 (no confidential data). Entities: Adresse, Adressepunkt, Husnummer, NavngivenVej, NavngivenVejKommunedel, NavngivenVejPostnummer, NavngivenVejSupplerendeBynavn, Postnummer, SupplerendeBynavn - [KDS Confluence: Fildownload (DAR), changed 18 Mar 2026](https://confluence.kds.dk/pages/viewpage.action?pageId=148452334)
- URL pattern: `https://api.datafordeler.dk/FileDownloads/GetFile?Register=DAR&LatestTotalForEntity=Husnummer&type=current&format=JSON&apikey=...`; three flavours: `bitemporal`, `temporal`, `current`; delta downloads are generated "daily between 3 and 6" - [KDS Confluence: Fildownload (DAR)](https://confluence.kds.dk/pages/viewpage.action?pageId=148452334)
- Authentication is mandatory for file download ("Når du ønsker at benytte fildownload kræver det at du er autentificeret"); DAR is reachable with service user (legacy), API key, or OAuth - [KDS Confluence: Fildownload på Datafordeleren, changed 28 Sep 2026](https://confluence.kds.dk/pages/viewpage.action?pageId=151999753)
- Probed 2026-11-11: `https://api.datafordeler.dk/FileDownloads/GetAvailableFileDownloads?Register=DAR` without a key returns HTTP 401 - [api.datafordeler.dk](https://api.datafordeler.dk/FileDownloads/GetAvailableFileDownloads?Register=DAR)
- Account creation: on Datafordeler Administration with MitID Erhverv or an e-mail user; for GraphQL or Fildownload you create an "IT-system" and an API key or OAuth credential - [Datafordeler: Brugeradgang](https://datafordeler.dk/vejledning/brugeradgang/)

**APIs**
- Datafordeler offers GraphQL (incl. entity-based events and flexible lookup logic) and WMS for DAR; documentation index - [KDS Confluence: DAR](https://confluence.kds.dk/pages/viewpage.action?pageId=10616849)
- Legacy Datafordeler interfaces for DAR - REST, Hændelser (events), Filudtræk (FTP extracts) and their schemas - are marked "udfases 15. januar 2027"; access with web user/service user also ends 15 Jan 2027 - [KDS Confluence: DAR](https://confluence.kds.dk/pages/viewpage.action?pageId=10616849), [KDS Confluence: Fildownload på Datafordeleren](https://confluence.kds.dk/pages/viewpage.action?pageId=151999753)
- The modernised Datafordeler went live 4 December (2025); parallel running was extended and the phase-out of non-modernised REST/events/file extracts was moved to "ultimo 2026" - [Klimadatastyrelsen news, 26 Feb 2026](https://www.klimadatastyrelsen.dk/om-klimadatastyrelsen/nyheder/nyhedsarkiv/2026/feb/newspage)
- Adressevælger replaces DAWA Autocomplete; Adressevask replaces DAWA address cleansing ("datavask"). Endpoints: `https://adressevaelger.dk/husnumre/soeg?tekst=...&token=...`, `https://adressevaelger.dk/adresser/soeg?tekst=...&token=...`, `https://adressevaelger.dk/vask/?token=...&adresse=...` - [KDS Confluence: Adressevælger - Fonetisk søgning, modified 22 Oct 2026](https://confluence.kds.dk/pages/viewpage.action?pageId=244318431), [KDS Confluence: Adressevask](https://confluence.kds.dk/display/ADV/Adressevask)
- Adressevælger has no user management yet (expected "ultimo 2026 eller primo 2027"), but a `token` parameter of at least 10 arbitrary characters is mandatory; KDS recommends everyone use the same published placeholder token - [KDS Confluence: Brugerstyring](https://confluence.kds.dk/display/ADV/Brugerstyring)
- Adressevælger: no rate limit ("Nej, der kommer ikke til at være en limit"); no reverse geocoding (use Datafordeler GraphQL instead); returns DAR UUIDs; data refreshed once a day; delivered as API endpoint plus a JavaScript GUI component; responses are not 1:1 with DAWA - [KDS Confluence: Adressevælger FAQ, modified 8 Jun 2026](https://confluence.kds.dk/display/ADV/FAQ)
- A further service, Bifrost (search in addresses, road names, property data, place names and DAGI divisions), is expected "ultimo Q4" 2026 - [Dataforsyningen: DAWA product page](https://dataforsyningen.dk/data/4924), [KDS Confluence: Bifrost](https://confluence.kds.dk/display/Bifrost/Bifrost)
- GSearch (Dataforsyningen REST search over DAR, DAGI, cadastre and place names, base `https://api.dataforsyningen.dk/rest/gsearch/v2.0/`) still exists; probed 2026-11-11 without token it returns HTTP 400 "Authentication token must only be lowercase (token) or uppercase (TOKEN)!", i.e. a Dataforsyningen token is required - [api.dataforsyningen.dk GSearch](https://api.dataforsyningen.dk/rest/gsearch/v2.0/husnummer?q=Rentemestervej%208)
- An INSPIRE Addresses product (OGC API Features `ad_inspire` and WMS, token required) is listed on Dataforsyningen - [Dataforsyningen: INSPIRE - Adresser](https://dataforsyningen.dk/data/3937)

**Licence**
- "Vilkår for brug af Danmarks Adresseregister (DAR) - (16.05.2024)": CC BY 4.0 applies to free basic data; you may freely fetch, share and adapt; "Du skal kreditere Klimadatastyrelsen på et passende sted" - [Datafordeler: terms for DAR](https://datafordeler.dk/vejledning/brugervilkaar/danmarks-adresseregister-dar/)
- General Datafordeler terms: CC BY 4.0 for free basic data; the registers may change terms at any time, with e-mail notice to registered users - [Datafordeler: Brugervilkår](https://datafordeler.dk/vejledning/brugervilkaar/)

**Content**
- Husnummer = access address (house number, link to road, municipality, parish, postcode, supplementary town name, BBR building); Adresse = unit level (floor "etage" and door "dør" designation); Adressepunkt = position of access points and road points plus a "teknisk standard" describing how the point was placed (quality); identifiers are `id_lokalId` UUIDs; full bitemporal history is downloadable - [KDS Confluence: Fildownload (DAR)](https://confluence.kds.dk/pages/viewpage.action?pageId=148452334)
- Quality figures in the Dataforsyningen catalogue record for DAR (record dated 2020): completeness about 96 % by sample; about 4 % of address points placed approximately (centre of the cadastral parcel), the rest expected better than +/- 2 m; "Adressedata har siden 2013 været frie data" - [Dataforsyningen catalogue record "Danmarks Adresseregister" (data product 2913, read via the site's search backend `https://dataforsyningen.dk/es/dataproducts/_search`; it is the data product behind INSPIRE - Adresser)](https://dataforsyningen.dk/data/3937)

**Postcodes**
- Postcodes are set by Trafikstyrelsen under the Postal Act; the Address Act requires postcode information to be made available digitally free of charge; the postcode map is part of KDS's DAGI dataset - [danmarksadresser.dk: Postnumre](https://danmarksadresser.dk/om-adresser/postnumre)

**HVD**
- "All INSPIRE datasets on The Danish Data Distributor are also covered by HVD"; DAR is listed under the HVD theme Geospatial; data is "available free of charge through APIs and file downloads ... GraphQL and WFS, as well as bulk download ... JSON and GeoPackage"; legal basis cited: Implementing Regulation (EU) 2023/138 - [Datafordeler: INSPIRE and HVD data](https://datafordeler.dk/vejledning/inspire/)

**Other caveats**
- Dataforsyningen itself moves to a new hosting platform: postponed from 2 Nov to 30 Nov 2026, service window 26 Nov 16:00 to 30 Nov 08:00 - [Dataforsyningen news 5199](https://dataforsyningen.dk/news/5199)
- OpenAddresses' Denmark source no longer points at DAWA: it is a cached upload dated 2026-03-27 "sourced from Datafordeler DAR GraphQL API", licence CC BY 4.0, attribution Klimadatastyrelsen - [openaddresses: sources/dk/countrywide.json](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/dk/countrywide.json)

### Inferences
- Denmark went from the easiest country in Europe (anonymous CSV/JSON of the whole register from DAWA) to "free but registered": zero cost and CC BY 4.0, commercial reuse allowed, but an account and API key are now needed for bulk data.
- Anything written before October 2026 that points to dawa.aws.dk or api.dataforsyningen.dk for addresses is dead; third-party tools hard-wired to DAWA (geocoders, OpenAddresses-style harvesters) had to change source.
- HVD caused no price change for addresses: they were already free by national law; the visible 2024-2026 change is the platform migration, not the licence.
- Adressevælger is effectively keyless today, but KDS has announced real user management for late 2026 / early 2027, so that will also become a registered service.

### Gaps
- I did not call adressevaelger.dk live (the request was blocked by this session's permission policy), so its behaviour is documented from KDS's pages only.
- File sizes of the DAR total downloads and the coordinate reference system used in them: not visible without a Datafordeler login; unverified. (ETRS89 / UTM zone 32N is the national standard, but I did not confirm it in the DAR download documentation.)
- Whether the Dataforsyningen INSPIRE address service kept running after 1 Oct 2026 was not probed (needs a token).
- The Dataforsyningen service catalogue still says the Datafordeler DAR REST service "Udgår 30. juni 2026" (record from Jan 2026), while the Confluence pages say 15 January 2027; I take the later Confluence date as current but did not find one consolidated official timetable.
- I did not find the data.europa.eu record for DAR to confirm its HVD flag there.

## Finland - which free address data sources exist?

### Takeaway
Finland has no stand-alone open address register; the national source is building addresses, and it changed hands: DVV stopped distributing its open "building addresses" file on 14 March 2025, and the data is now served by the Finnish Environment Institute (Syke) from the Ryhti system as a keyless OGC API (3.87 million address points, CC BY 4.0). Posti's postcode and street-range files are free separately.

### Cited Findings

**Authoritative source and publisher**
- Ryhti (Rakennetun ympäristön tietojärjestelmä, Built Environment Information System), run by Suomen ympäristökeskus (Syke), collects building and land-use data nationally; addresses arrive with building permit data from municipalities. Building addresses created before Ryhti were taken over from DVV's Population Information System; during a transition period (2025-2028) municipalities may still deliver permit data to the Population Information System, which forwards it to Ryhti - [avoindata.suomi.fi: Rakennetun ympäristön tietojärjestelmän rakennusten osoitetiedot](https://avoindata.suomi.fi/data/fi/dataset/rakennetun-ympariston-tietojarjestelman-rakennusten-osoitetiedot)
- "In the first phase, the addresses do not have their own location points, and are instead linked to building objects" - [avoindata.suomi.fi: Ryhti building addresses](https://avoindata.suomi.fi/data/fi/dataset/rakennetun-ympariston-tietojarjestelman-rakennusten-osoitetiedot)
- "The maintenance of building data is being transferred from the Digital and Population Data Services Agency to the Finnish Environment Institute's Built environment information system (Ryhti)"; the INSPIRE obligations for addresses and buildings moved from DVV to Syke - [National Land Survey service message, 28 Feb 2025](https://www.maanmittauslaitos.fi/en/service-messages/changes-inspire-services-concerning-buildings-and-addresses)

**The old DVV open dataset is gone**
- Readme shipped with the last DVV extract: "Rakennusten osoitetiedot ja äänestysalue - aineiston jakelu päättyy 14.3.2025"; after that DVV refers users to its chargeable information services; the last extract was taken 3 Feb 2025 and holds 3,872,156 buildings (only buildings with coordinates and at least a postcode) - [Funet mirror: rakennukset_readme.txt](https://www.nic.funet.fi/index/geodata/dvv/osoitteet/2025/rakennukset_readme.txt)
- Probed 2026-11-11: the former portal entries return 404 (`package_show?id=postcodes`, `package_show?id=rakennusten-osoitetiedot-koko-suomi`, and the dataset page) - [avoindata.suomi.fi (old dataset URL, 404)](https://www.avoindata.fi/data/fi/dataset/rakennusten-osoitetiedot-koko-suomi)
- A frozen copy of that last extract is mirrored by Funet as a shapefile set (osoiteet_2025.shp 105 MB, .dbf 832 MB, dated 23 May 2025), alongside 2016, 2018, 2020 and 2022 snapshots - [Funet: /index/geodata/dvv/osoitteet/2025/](https://www.nic.funet.fi/index/geodata/dvv/osoitteet/2025/)
- DVV's own open-data page no longer lists any building/address dataset - [DVV: Avoin data](https://dvv.fi/avoin-data)
- NLS's INSPIRE WMS/WFS for addresses and buildings (built on DVV data) were switched off after 30 May 2025; replacement is Syke's OGC API Features - [National Land Survey service message, 28 Feb 2025](https://www.maanmittauslaitos.fi/en/service-messages/changes-inspire-services-concerning-buildings-and-addresses)

**Bulk / API access today (Ryhti)**
- Open endpoints: OGC API Features `https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1` (collections `open_address`, `open_address_deleted`, `open_building`, ...), INSPIRE flavour `https://paikkatiedot.ymparisto.fi/geoserver/ryhti_inspire_ad/ogc/features/v1` (collection `AD.Address`), plus WMS - [avoindata.suomi.fi: Ryhti building addresses](https://avoindata.suomi.fi/data/fi/dataset/rakennetun-ympariston-tietojarjestelman-rakennusten-osoitetiedot)
- Probed 2026-11-11 without any key: `open_address` reports `numberMatched` 3,870,989; storage CRS EPSG:3067 (ETRS-TM35FIN), GeoJSON returned in WGS84 lon/lat; newest `modified_timestamp_utc` seen 2026-11-03 - [Ryhti open_address items](https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1/collections/open_address/items?f=application/json&limit=2)
- Fields seen in `open_address`: `address_key`, `building_key`, `address_fin`, `address_swe`, `address_name_fin/swe` (street), `number_part_of_address_number`, subdivision letters, `postal_code`, `postal_office_fin/swe`, `municipality_number`, `modified_timestamp_utc` - [Ryhti open_address items](https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1/collections/open_address/items?f=application/json&limit=2)
- The INSPIRE collection `AD.Address` also reports 3,870,989 features and adds the permanent building identifier and parcel identifier (`building`, `parcel`), locator level "siteLevel", position specification "building" - [Ryhti AD.Address items](https://paikkatiedot.ymparisto.fi/geoserver/ryhti_inspire_ad/ogc/features/v1/collections/AD.Address/items?f=application/json&limit=1)
- Syke recommends using timestamps in requests to fetch only data updated since the last query - [Ryhti: Services](https://ryhti.syke.fi/en/front-page/services/)
- Data content description (27 May 2026) lists "Addresses of completed buildings" and "Addresses of project buildings" as open interfaces; there are also two contractual interfaces - [Syke: Ryhti_rakennustiedot_EN.pdf](https://geoportal.ymparisto.fi/meta/julkinen/dokumentit/Ryhti_rakennustiedot_EN.pdf)

**Licence**
- "The services are free of charge. Open data is licenced under Creative Commons Attribution 4.0 International licence" - [Ryhti: Services](https://ryhti.syke.fi/en/front-page/services/)
- Portal record: licence cc-by-4.0, maintainer Syke (ryhti@syke.fi), created 2025-11-19, modified 2026-01-27; non-open products need a data permit and/or usage agreement - [avoindata.suomi.fi: Ryhti building addresses](https://avoindata.suomi.fi/data/fi/dataset/rakennetun-ympariston-tietojarjestelman-rakennusten-osoitetiedot)

**National Land Survey (Maanmittauslaitos) - geocoding**
- Geocoding service (REST, Pelias-based): forward `/geocoding/v1/pelias/search` and reverse `/geocoding/v1/pelias/reverse`; sources include "Building addresses" (documented as from the Population Information System) and "Interpolated road addresses" (Topographic Database); EPSG:3067 fully, WGS84 partly; "open interface with API-key authentication" or contract interface - [NLS: Geocoding API description](https://www.maanmittauslaitos.fi/en/maps-and-spatial-data/expert-users/kartta-ja-paikkatietojen-rajapintapalvelut/geokoodauspalvelu)
- API key: free, created in the NLS "My Account" service after registering with an e-mail address - [NLS: Instructions for using the API key](https://www.maanmittauslaitos.fi/en/rajapinnat/api-avaimen-ohje)
- Terms changed 29 Sep 2026: the open, free interface "is intended for testing and production use in services where performance is not critical"; NLS may block a user; heavier production use needs a paid agreement (fee based on number of queries); data licence is the NLS open data CC BY 4.0 licence - [NLS service message, 29 Sep 2026](https://www.maanmittauslaitos.fi/en/service-messages/changes-terms-use-open-interface-national-land-survey-finland)

**Postal operator (Posti)**
- Free files at `https://www.posti.fi/webpcode/`: PCF (Postcode File), BAF (Basic Address File: valid postcodes, streets and municipalities for Finland excluding Åland; where a street spans several postcodes the right one is given by house numbers) and POM (postcode changes of the previous month) - [Posti: Postinumerotiedostot](https://www.posti.fi/fi/yrityksille/asiakastuki/postinumerotiedostot)
- Update rhythm: PCF daily except Sunday; BAF weekly on Saturdays; POM monthly on the 3rd; older files stay about three months in `./arch`; redistribution is allowed if the current service description and terms are passed along - [Posti: Postinumerotiedostot](https://www.posti.fi/fi/yrityksille/asiakastuki/postinumerotiedostot)
- Probed 2026-11-11: directory lists `BAF_20261107.zip`, `PCF_20261110.zip`, `POM_20261102.zip`, uncompressed copies under `/unzip/`; no login - [posti.fi/webpcode](https://www.posti.fi/webpcode/)
- Terms and record layouts are in a document dated 1 Jan 2015 - [Posti: service description and terms of use (PDF)](https://assets.ctfassets.net/dvxpcmq06s7e/1eKbwM2WAEY5AuGi5TrSZ7/3550dd7d56837b39126cf8c1b15e9b0a/posti-postinumeropalvelut-palvelukuvaus-ja-kayttoehdot-20150101.pdf)

**Statistical office and municipal portals**
- Statistics Finland's Paavo postcode-area statistics are listed as CC BY 4.0 - [avoindata.suomi.fi search "postinumero"](https://avoindata.suomi.fi/data/api/3/action/package_search?q=postinumero&rows=40)
- City address datasets under CC BY 4.0 on the national portal include Helsinki ("Helsingin osoitteet"), the capital-region address list ("Pääkaupunkiseudun osoiteluettelo"), Espoo, Vantaa, Turku and Kaarina address points, Oulu, Salo, Hyvinkää, Raisio, Vihti, Kauniainen, and an Uusimaa address API - [avoindata.suomi.fi search "osoitteet"](https://avoindata.suomi.fi/data/api/3/action/package_search?q=osoitteet&rows=40)

**Country-specific aggregator note**
- OpenAddresses' Finnish sources (countrywide and per region, Finnish and Swedish variants) now use a cached upload dated 2026-09-30 named `open_address.csv.zip`, attributed to Syke, CC BY 4.0 - [openaddresses: sources/fi/countrywide-fi.json](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/fi/countrywide-fi.json)

**HVD**
- The national portal record for the Ryhti address dataset carries `highvalue: false`, and data.europa.eu shows `is_hvd: false` for it (checked 2026-11-11) - [avoindata.suomi.fi API record](https://avoindata.suomi.fi/data/api/3/action/package_show?id=rakennetun-ympariston-tietojarjestelman-rakennusten-osoitetiedot), [data.europa.eu search](https://data.europa.eu/api/hub/search/search?q=rakennusten+osoitetiedot&filter=dataset&limit=5&facets=%7B%22country%22%3A%5B%22fi%22%5D%7D)
- An INSPIRE data product has been published from the Ryhti address data - [avoindata.suomi.fi: Ryhti building addresses](https://avoindata.suomi.fi/data/fi/dataset/rakennetun-ympariston-tietojarjestelman-rakennusten-osoitetiedot)

### Inferences
- For a countrywide Finnish address file in November 2026 the only live official route is paging the Ryhti OGC API (3.87 M features); there is no official one-click bulk file any more. The Funet shapefile is a convenient but frozen February 2025 snapshot.
- Records are building-level points with street, number, postcode and post office in Finnish and Swedish; there is no apartment/unit level in the open data.
- The NLS geocoder's documentation still names the Population Information System as its building-address source; given the transfer to Ryhti this wording is probably out of date, but I could not confirm which source it uses now.
- Posti's BAF gives street + house-number range to postcode mapping, not individual address points and no coordinates; postcodes are Posti's product under its own terms, not CC-licensed.

### Gaps
- No official statement found on how often the open Ryhti address API is refreshed (timestamps suggest near-continuous, last seen 2026-11-03), nor any published rate limit for it.
- Posti's page contradicts itself: the intro says the files contain no street names ("Tiedostoissa ei ole kadunnimiä tai kartta-aineistoa") while the BAF description says it contains streets; I did not open the BAF file to settle it.
- Whether Finland has formally reported addresses as an HVD under Regulation 2023/138: not found; portal flags say no.
- Digiroad (Finnish Transport Infrastructure Agency, CC BY 4.0 on the portal) is known to carry road address ranges, but I did not verify its content.
- I did not verify exact licence wording for Paavo beyond the portal's CC BY 4.0 tag.

## Sweden - which free address data sources exist?

### Takeaway
Sweden's national address data (Lantmäteriet's "Belägenhetsadress") became free of charge as a high-value dataset in February 2025 under CC BY 4.0, but it is not anonymous: you need a Geotorget account and an approved per-product application stating how you will process personal data, and the download server answers 401 without credentials. There is no free official postcode file that I could find.

### Cited Findings

**Authoritative register and publisher**
- The dataset "Belägenhetsadress" contains "information om adresser från fastighetsregistrets adressdel" (addresses from the address part of the Real Property Register); publisher Lantmäteriet (the Swedish mapping, cadastral and land registration authority) - [data.europa.eu search record "Belägenhetsadress"](https://data.europa.eu/api/hub/search/search?q=bel%C3%A4genhetsadress&filter=dataset&limit=10)
- Product pages on lantmateriet.se now redirect to Geotorget, e.g. `https://geotorget.lantmateriet.se/geodataprodukter/belagenhetsadress-nedladdning-vektor-api` (bulk) and `https://geotorget.lantmateriet.se/geodataprodukter/belagenhetsadress-direkt-api` (API); both are JavaScript-only pages - [Geotorget: Belägenhetsadress Nedladdning, vektor](https://geotorget.lantmateriet.se/geodataprodukter/belagenhetsadress-nedladdning-vektor-api)

**Bulk download**
- STAC catalogue (public metadata): collection `belagenhetsadresser`, "Belägenhetsadresser kommunindelat i geopackage", `license: CC-BY-4.0`, provider Lantmäteriet - [Lantmäteriet STAC: belagenhetsadresser](https://api.lantmateriet.se/stac-vektor/v1/collections/belagenhetsadresser)
- Probed 2026-11-11: 290 items (one zipped GeoPackage per municipality), total 324,549,145 bytes zipped; items carry `proj:epsg: 3006` (SWEREF 99 TM), `created: 2025-02-03`, `updated: 2026-11-10T11:39Z`; asset URLs look like `https://dl1.lantmateriet.se/adress/belagenhetsadresser/belagenhetsadresser_kn2584.zip` - [Lantmäteriet STAC items](https://api.lantmateriet.se/stac-vektor/v1/collections/belagenhetsadresser/items?limit=1000)
- Probed 2026-11-11: a HEAD request to such an asset URL returns `401 Unauthorized` with `WWW-Authenticate: Basic realm="Authorization Server"` - [dl1.lantmateriet.se asset](https://dl1.lantmateriet.se/adress/belagenhetsadresser/belagenhetsadresser_kn2584.zip)

**Registration and review**
- To use the free products: create a Geotorget account (private person) or apply for an organisation account; create a system account; apply for authorisation per product; "vissa produkter kräver ändamålsprövning enligt fastighetsregisterlagen, vissa produkter innehåller personuppgifter och kräver godkännande av villkor samt att du anger hur du ska behandla personuppgifter" - [Lantmäteriet: Avgiftsfria produkter](https://www.lantmateriet.se/sv/geodata/vara-produkter/avgiftsfria-produkter/)
- The Open Data Act "does not give a right to access data from Lantmäteriet"; GDPR, the Real Property Register Act and secrecy law take precedence; for HVDs with personal data or property-register information Lantmäteriet must judge that nothing prevents access, via an application form in Geotorget - [Lantmäteriet: Om tillhandahållandet](https://www.lantmateriet.se/sv/geotorget-produktstod/om-tillhandahallandet/)
- Lantmäteriet names addresses among the high-value datasets it holds (addresses, buildings, geographic names, administrative units, cadastral parcels, hydrography, elevation, land cover, orthophoto) - [Lantmäteriet: Om tillhandahållandet](https://www.lantmateriet.se/sv/geotorget-produktstod/om-tillhandahallandet/)

**Licence**
- "Användningsvillkor för värdefulla datamängder som innehåller personuppgifter", version 1.1, 2025-03-04: products are made available under CC BY 4.0, including commercial use; when publishing you must state product name, "©Lantmäteriet", whether the data was processed, and that CC BY 4.0 applies - [Lantmäteriet: användningsvillkor (personuppgifter) PDF](https://www.lantmateriet.se/globalassets/geodata/geodataprodukter/anvandningsvillkor_for_vardefulla_datamangder_pu.pdf)
- Additional conditions in the same terms: 3.3 personal data may only be processed for the purposes stated in the application and approved by decision; 3.4 only take the personal data necessary (e.g. geographic selection); 3.5 process/store personal data only within the EU/EEA unless the decision says otherwise (US-owned cloud only under the EU-US Data Privacy Framework); Lantmäteriet may run spot checks and revoke access - [Lantmäteriet: användningsvillkor (personuppgifter) PDF](https://www.lantmateriet.se/globalassets/geodata/geodataprodukter/anvandningsvillkor_for_vardefulla_datamangder_pu.pdf)
- Lantmäteriet's separate "öppna data" are CC0 with no attribution requirement; the product list distinguishes three filters: Öppna data, Värdefulla datamängder, Avgiftsfria produkter - [Lantmäteriet: Öppna data](https://www.lantmateriet.se/sv/geodata/vara-produkter/avgiftsfria-produkter/oppna-data/), [Lantmäteriet: Avgiftsfria produkter](https://www.lantmateriet.se/sv/geodata/vara-produkter/avgiftsfria-produkter/)
- HVDs "ska vara avgiftsfria, tillgängliga för vidareutnyttjande enligt CC BY 4.0 eller lägre samt tillhandahållas i öppna format via API:er och för bulknedladdning" - [Lantmäteriet: Om tillhandahållandet](https://www.lantmateriet.se/sv/geotorget-produktstod/om-tillhandahallandet/)

**APIs**
- Belägenhetsadress Direkt API access point `https://api.lantmateriet.se/distribution/produkter/belagenhetsadress/v4.2`; STAC download access point as above - [data.europa.eu search record "Belägenhetsadress"](https://data.europa.eu/api/hub/search/search?q=bel%C3%A4genhetsadress&filter=dataset&limit=10)
- INSPIRE Addresses ATOM feed `https://api.lantmateriet.se/belagenhetsadress/atom/v1.2/inspire/ad` is publicly readable: 290 municipality entries, CRS EPSG:3006 and EPSG:4258, but entries are dated 30 Sep - 1 Oct 2024 and the feed's rights text still says "Avtal för användning krävs, avgifter för användning tas ut" - [Lantmäteriet INSPIRE ATOM feed](https://api.lantmateriet.se/belagenhetsadress/atom/v1.2/inspire/ad)

**Content and volume**
- The INSPIRE address dataset holds location by "gatunamn, gatunummer och postnummer" (street name, street number and postcode), adapted to scale 1:10 000 - [data.europa.eu search record "Datamängd för Belägenhetsadresser, Inspire"](https://data.europa.eu/api/hub/search/search?q=bel%C3%A4genhetsadress&filter=dataset&limit=10)
- An OSM contributor whose application was approved reported access to "alle 3.7 millioner adresser i Sverige" (15 March 2025), having stated OSM import as the purpose; another notes the download product lacks the building-entrance link available in Byggnad Direkt (community forum, not official) - [OSM community forum: Lantmäteriet Belägenhetsadress](https://community.openstreetmap.org/t/lantmateriet-belagenhetsadress/127427)

**HVD**
- data.europa.eu flags the Lantmäteriet "Belägenhetsadress" record `is_hvd: true` (record modified 2026-02-24) - [data.europa.eu search](https://data.europa.eu/api/hub/search/search?q=bel%C3%A4genhetsadress&filter=dataset&limit=10)
- Legal basis as stated by Lantmäteriet: Open Data Directive (EU) 2019/1024, Swedish Open Data Act (2022:818), Implementing Regulation (EU) 2023/138 - [Lantmäteriet: Om tillhandahållandet](https://www.lantmateriet.se/sv/geotorget-produktstod/om-tillhandahallandet/)

**Municipal portals and aggregator note**
- Malmö stad stopped publishing address data on its open data portal from 2026-09-01: publication "is not compatible with current licence terms under the geodata cooperation with Lantmäteriet", which restrict reuse and sharing with third parties, and addresses can be personal data; it points to Lantmäteriet's own provision under special terms - [data.europa.eu record: Malmö stad "Adresser"](https://data.europa.eu/api/hub/search/search?q=bel%C3%A4genhetsadress&filter=dataset&limit=10)
- OpenAddresses has no countrywide Swedish source, only 18 municipal ones (e.g. Stockholm from a 2016 cache with no licence recorded) - [openaddresses: sources/se](https://github.com/openaddresses/openaddresses/tree/master/sources/se), [sources/se/municipality_of_stockholm.json](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/se/municipality_of_stockholm.json)

### Inferences
- The HVD regulation is what made Swedish address data free: STAC items were created on 2025-02-03 and the HVD terms date from February-March 2025; before that the same data was a chargeable product (the stale ATOM feed text still says fees apply).
- "Free" in Sweden means zero cost and CC BY 4.0 on paper, with commercial reuse allowed, but the personal-data conditions (purpose limitation, EU/EEA storage, revocable decision) are restrictions on top of CC BY 4.0; this is why OSM contributors asked for exemptions and why open republication by third parties (Malmö) is being withdrawn rather than expanded.
- Daily refresh is implied by the STAC `updated` stamps of 2026-11-10 on files created in 2025.
- The STAC item listing itself is open and scriptable; only the file fetch needs the Geotorget credentials.

### Gaps
- I could not open the GeoPackage (credentials needed) or the Geotorget documentation tab (JavaScript app), so the exact attribute list - in particular whether the free bulk product carries postnummer/postort, entrance-level points and apartment numbers - is unverified; only the INSPIRE dataset description confirms postcodes.
- No official Lantmäteriet news page found giving the exact release date; "3 February 2025" rests on the STAC `created` field.
- A search hit says LMFS 2023:2 priced "belägenhetsadress" at 3.30 kr per property before the change; I did not open the regulation, so the old price is unverified.
- Postcode ownership (PostNord) and whether any free official postcode file exists: no reliable source found.
- Statistics Sweden (SCB) address or postcode products: not checked.
- Rate limits and current terms of Belägenhetsadress Direkt: not found (page is a JavaScript app; API root returns 405 to a bare GET).

## Estonia - which free address data sources exist?

### Takeaway
Estonia's Address Data System (ADS) is fully open with no licence agreement, monthly full CSV extracts, and a keyless search/geocoding API (In-ADS) that returns postcodes and coordinates. In 2026 ADS is being folded into a new Addresses and Place Names System (AKS): the public application and downloads moved to aks.geoportaal.ee, and the old X-tee SOAP services close at the end of 2026.

### Cited Findings

**Authoritative register and publisher**
- Aadressiandmete süsteem (ADS, Estonian Address Data System), launched 2009, legal basis the Spatial Data Act and the ADS regulation; run by Maa- ja Ruumiamet (Estonian Land and Spatial Development Board, the former Maa-amet / Land Board); local governments are responsible for the accuracy of official addresses - [Maa- ja Ruumiamet geoportal: Aadressiandmed (last changed 1 Jul 2026)](https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed-p112.html)
- "ADS contains only official addresses ... no address in Estonia is valid before the address is registered in ADS" - [Geoportal: Address Data (last update 17 Jul 2026)](https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html)
- The old domain geoportaal.maaamet.ee redirects (302) to geoportaal.maaruum.ee - probed 2026-11-11 - [geoportaal.maaamet.ee address page](https://geoportaal.maaamet.ee/eng/spatial-data/address-data-p313.html)

**AKS migration (2026 change)**
- "Maa- ja Ruumiamet is developing a new Addresses and Place Names System (AKS), into which the former ADS is now added"; the AKS-ADS public application and new aks-ads X-tee REST services are ready; the data composition stays the same (all earlier identifiers and field names are kept) - [Geoportal: ADS X-tee suletavad teenused](https://geoportaal.maaruum.ee/est/teenused/x-tee-teenused/ads-x-tee-teenused/ads-x-tee-suletavad-teenused-p1032.html)
- Old X-tee SOAP services "suletakse 2026. aasta lõpus" (close at the end of 2026); the new aks-ads REST services are open to all X-tee consumers by default; X-tee returns at most 100 answers per query - [Geoportal: ADS X-tee teenused (changed 19 Oct 2026)](https://geoportaal.maaruum.ee/index.php?lang_id=1&page_id=266)
- Probed 2026-11-11: `https://xgis.maaamet.ee/adsavalik/extracts` redirects to `https://aks.geoportaal.ee/aks`, a JavaScript application - [xgis.maaamet.ee/adsavalik/extracts](https://xgis.maaamet.ee/adsavalik/extracts)
- Current entry points: address search `https://aks.geoportaal.ee/aks/search/address`, embeddable search generator "In-AKS" `https://aks.geoportaal.ee/aks/inaks/generaator`, extracts `https://aks.maaruum.ee/aks/valjavotted` - [Geoportal: Aadressiandmed](https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed-p112.html)

**Bulk download**
- "In the beginning of every month we create complete extracts of all ADS data", available on an SFTP server and in the public service; "CSV extracts are produced once in every 30 days"; the extracts folder has a readme.pdf in English - [Geoportal: Address Data](https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html)
- SFTP: server `aksfailid.maaruum.ee`, port 22, with a public username and password printed on the official page; "The access is limited for foreign IP addresses" - contact the ADS help e-mail if blocked - [Geoportal: Address Data](https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html)
- Extract no. 9 "Addresses with components and history": fields ADR_ID, code address, full address, proximate address, status (K valid; V and T invalid), valid-from/valid-to, reference point X/Y, eight levels of component code/name; sample file offered - [Geoportal: Address Data](https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html)
- Postcode file: `https://geoportaal.maaruum.ee/docs/aadress/sihtnumbrid.zip` (~28 MB), CSV of valid address versions with ADR_ID, SIHTNUMBER, LAHIAADRESS, TAISAADRESS, VIITEPUNKT_X, VIITEPUNKT_Y; refreshed on the 5th of each month - [Geoportal: Aadressid ja posti sihtnumbrid](https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed/aadressid-ja-posti-sihtnumbrid-p582.html)
- Probed 2026-11-11: that zip answers HTTP 200, `content-length` 29,591,636, no login - [sihtnumbrid.zip](https://geoportaal.maaruum.ee/docs/aadress/sihtnumbrid.zip)

**APIs**
- In-ADS: address search API and embeddable widget at `https://inaadress.maaamet.ee/inaadress`; JSON gazetteer e.g. `https://inaadress.maaamet.ee/inaadress/gazetteer?address=...` or `?adrid=...`, XML via `/inaadress/service` - [Geoportal: In-ADS](https://geoportaal.maaruum.ee/eng/services/in-ads-p660.html), [Geoportal: Postal Codes](https://geoportaal.maaruum.ee/eng/spatial-data/address-data/postal-codes-p661.html)
- Probed 2026-11-11 without key: the gazetteer returned full address, ADS_OID, ADR_ID, component codes, `sihtnumber` (postcode), L-EST coordinates (`viitepunkt_x/y`) and WGS84 (`viitepunkt_l/b`), bounding box - [In-ADS gazetteer sample](https://inaadress.maaamet.ee/inaadress/gazetteer?address=Vesilennuki+12&results=2)
- In-ADS Terms of Use v1.3 (03.01.2024): free of charge; automated use allowed up to 3,000 queries per 10 minutes and 10,000 per hour per IP; from IPs outside Estonia 2,000 per 10 minutes and 6,000 per hour; for more, install the In-ADS container solution in your own infrastructure; autocomplete must start after the 4th character with a 500 ms pause; "No personal data is processed in In-ADS"; data made available is open data - [In-ADS Terms of Use (PDF)](https://geoportaal.maaruum.ee/docs/aadress/In-ADS_terms_of_use.pdf)
- Geocoder: single and mass geocoding (CSV/XLS/XLSX in; CSV, XLSX, GeoJSON, GeoPackage, KML, SHP out) and a Geocoder API with Swagger at `https://inaadress.maaamet.ee/geocoder-api/...` - [Geoportal: Address Data Geocoding](https://geoportaal.maaruum.ee/eng/services/address-data-geocoding-p873.html)
- Also listed: address WMS, and WMS/WFS of residential buildings derived from address data - [Geoportal: Aadressiandmed](https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed-p112.html)
- X-tee services need X-Road membership (a legal person must first join X-tee) - [Geoportal: ADS X-tee teenused](https://geoportaal.maaruum.ee/index.php?lang_id=1&page_id=266)

**Licence**
- "ADS data is open data, so there is no license agreement. If you use our data and have a list of data providers, please refer to the Estonian Land and Spatial Development Board as the provider of Estonian address data" - [Geoportal: Address Data](https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html)
- The Board's general open data licence (dated 01.01.2025; URL `https://geoportaal.maaruum.ee/opendata-licence`): free use for an unspecified term, derivatives, commercial and non-commercial use, redistribution; obligation to cite licensor name, data title and date - [Maa- ja Ruumiamet open data licence (PDF)](https://geoportaal.maaruum.ee/docs/Avaandmed/ETAK_open_data_licence.pdf)

**Content**
- About 2.4 million address objects: cadastral parcels ~772,000; residential buildings ~305,000; non-residential buildings ~679,000; dwellings/flats ~559,000; other building parts ~68,000 - [Geoportal: Address Data](https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html)
- Eight component levels (county, municipality, settlement/city district, address area, thoroughfare, object name, address number, building-part number); identifiers ADR_ID (address version), ADS_OID (object, stable) and ADOB_ID (object version); ~99.9 % of addresses have a reference point; coordinates in L-EST97 (EPSG:3301) - [Geoportal: Address Data](https://geoportaal.maaruum.ee/eng/spatial-data/address-data-p313.html)
- Postcodes were added to ADS in 2019; they are managed by Omniva (the postal operator) and applied to ADS addresses according to Omniva's postcode areas - [Geoportal: Aadressid ja posti sihtnumbrid](https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed/aadressid-ja-posti-sihtnumbrid-p582.html)
- ADS also holds unofficial data: neighbourhoods, quarters, commonly used building names - [Geoportal: Aadressiandmed](https://geoportaal.maaruum.ee/est/ruumiandmed/aadressiandmed-p112.html)

**HVD and aggregator note**
- data.europa.eu flags "Estonian Address Data System Information System" (catalogue ng-ee) `is_hvd: true` - [data.europa.eu search](https://data.europa.eu/api/hub/search/search?q=aadressiandmed&filter=dataset&limit=5&facets=%7B%22country%22%3A%5B%22ee%22%5D%7D)
- OpenAddresses' Estonian source is now a third-party mirror (`address.dev.peatus.ee`) of the official extract because "the official download portal at xgis.maaamet.ee/adsavalik/ads has moved to the JS-rendered aks.geoportaal.ee/aks app"; it notes that as of 2026-09 the extract's column headers are all lowercase - [openaddresses: sources/ee/countrywide.json](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/ee/countrywide.json)

### Inferences
- Estonia is the most open of the six: no account, no key, commercial reuse allowed, postcodes included, apartment level included, history included.
- The practical risk in late 2026 is plumbing, not licensing: download links moved into a JavaScript application, the SFTP server limits foreign IPs, and file headers changed case - scripted harvesters written for the old ADS public app need rework.
- HVD made no visible difference to price or licence; the data was already free.
- In-ADS (inaadress.maaamet.ee) was still answering on 2026-11-11, while "In-AKS" exists in parallel; a later retirement of In-ADS is plausible but I found no announced date.

### Gaps
- I could not test the SFTP server or the AKS "Väljavõtted" downloads (JavaScript app; SFTP not tried), so current file names, sizes and whether foreign IPs are really blocked are unverified.
- No announced end date found for In-ADS itself, and no terms of use found for In-AKS.
- The English page still links the old "ADS public service" URLs; the Estonian page is more current - the two disagree on entry points.
- Statistics Estonia and municipal portals were not checked (ADS is the single source they would use).

## Latvia - which free address data sources exist?

### Takeaway
Latvia's State Address Register is published in full, anonymously, as daily-refreshed CSV and shapefile dumps on data.gov.lv under CC BY 4.0, down to apartment level and with postcodes and coordinates. Watch one fresh breaking change: on 7 October 2026 the coordinates switched from LKS-92 TM to LKS-2020 TM.

### Cited Findings

**Authoritative register and publisher**
- Valsts adrešu reģistrs (State Address Register; its information system is abbreviated VARIS), published by Valsts zemes dienests (VZD, State Land Service); open-data page first published 07.12.2021, updated 08.10.2026 - [VZD: Adrešu reģistra atvērtie dati](https://www.vzd.gov.lv/lv/VAR-atversana)
- Dataset "Valsts adrešu reģistra atvērtie dati": publisher VZD, licence CC-BY-4.0, frequency daily, contact dati@vzd.gov.lv, 41 resources - [data.gov.lv: varis-atvertie-dati](https://data.gov.lv/dati/lv/dataset/varis-atvertie-dati)

**Bulk download (no registration)**
- "VZD publishes denormalised State Address Register data": text data as CSV, spatial data (incl. administrative boundaries) as SHP; "Datus Latvijas Atvērto datu portālā aktualizējam reizi diennaktī" (updated once a day) - [VZD: Adrešu reģistra atvērtie dati](https://www.vzd.gov.lv/lv/VAR-atversana)
- Probed 2026-11-11 via the portal API: all data resources carry `last_modified` 2026-11-10; sizes: `aw_eka.csv` (building and buildable-parcel addresses) 141,794,829 bytes; `aw_dziv.csv` (premises groups, i.e. apartment-level addresses) 142,907,017 bytes; `aw_iela.csv` (streets) 3.3 MB; `aw_ciems.csv` (villages) 1.7 MB; historic counterparts `aw_eka_his.csv` 192 MB and `aw_dziv_his.csv` 215 MB; `aw_shp.zip` (spatial data) 52,584,058 bytes; plus document-metadata files `aw_doc_nl.csv` 128 MB, `aw_doc_tg.csv` 95 MB - [data.gov.lv API: package_show varis-atvertie-dati](https://data.gov.lv/dati/api/3/action/package_show?id=varis-atvertie-dati)
- Direct URL pattern: `https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/{resource-id}/download/{file}`; e.g. building addresses - [aw_eka.csv](https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/a510737a-18ce-400f-ad4b-04fce5228272/download/aw_eka.csv), spatial data - [aw_shp.zip](https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/b643b1b3-223f-4394-9beb-18524f8b0b82/download/aw_shp.zip)
- Probed 2026-11-11: I downloaded `aw_eka.csv` anonymously (HTTP 200): 611,370 rows, of which 551,086 status EKS (existing), 32,507 DEL (liquidated), 27,777 ERR (erroneous); 457,195 rows are buildings and 154,175 are parcels intended for building (`FOR_BUILD` = Y); all existing rows have a postcode and all but one have coordinates; newest `DAT_MOD` 2026.11.09 - [aw_eka.csv](https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/a510737a-18ce-400f-ad4b-04fce5228272/download/aw_eka.csv)

**Content**
- Columns of `aw_eka.csv`: KODS (object code), TIPS_CD, STATUSS, APSTIPR, APST_PAK, VKUR_CD/VKUR_TIPS (parent object), NOSAUKUMS (name/number), SORT_NOS, ATRIB (postcode, e.g. LV-4211), PNOD_CD (post office service-area code), DAT_SAK, DAT_MOD, DAT_BEIG, FOR_BUILD, PLAN_ADR (planned address), STD (full address string), KOORD_X, KOORD_Y ("centroid ... LKS-2020"), DD_N, DD_E (decimal degrees) - [aw_eka_metadata.json](https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/27ab50ae-95ae-46be-88c8-d54d4b4c70b5/download/aw_eka_metadata.json)
- The dataset covers municipalities, parishes, former districts (valid to 30 June 2009), cities, villages/hamlets, streets, building and buildable-parcel addresses, premises-group (incl. apartment) addresses, the link of Riga addresses to city districts, place centroids, and historic address forms for all levels - [VZD: Adrešu reģistra atvērtie dati](https://www.vzd.gov.lv/lv/VAR-atversana)
- The shapefile archive holds boundary polygons, address points of hamlets and of buildings/buildable parcels, and street/road centre lines - [VZD: Adrešu reģistra atvērtie dati](https://www.vzd.gov.lv/lv/VAR-atversana)
- Change log: "07.10.2026 - transformētas koordinātas no LKS-92 TM uz LKS-2020 TM"; 24.07.2025 three document-metadata resources added; 13.06.2025 new columns in the Riga district link file - [data.gov.lv: varis-atvertie-dati](https://data.gov.lv/dati/lv/dataset/varis-atvertie-dati)
- Specifications for the text data (updated 07.10.2026) and the spatial data are linked from the VZD page - [VZD: text data specification](https://www.vzd.gov.lv/lv/media/9209/download?attachment), [VZD: spatial data specification](https://www.vzd.gov.lv/lv/media/5020/download?attachment)

**Services (WFS / ATOM)**
- On geolatvija.lv VZD publishes, as "augstvērtīgas datu kopas" (high-value datasets), INSPIRE Annex I "Adreses" data as WMS, WFS and a bulk ATOM feed in GML; the register data there is refreshed once a week - [VZD: Adrešu reģistra atvērtie dati](https://www.vzd.gov.lv/lv/VAR-atversana), [geolatvija.lv: Adreses](https://geolatvija.lv/main?geoproduct=open&geoProductId=291)

**Licence**
- "Open data use must follow the Creative Commons Attribution 4.0 licence": free to copy, adapt, distribute; commercial or non-commercial; no permission from VZD needed; you must cite the source (example: "Izmantoti Valsts adrešu reģistra informācijas sistēmas dati"), link the licence, and describe changes made; you may not imply VZD approved your product - [VZD: Par datu izmantošanas noteikumiem](https://www.vzd.gov.lv/lv/par-datu-izmantosanas-noteikumiem)

**HVD and aggregator note**
- The CSV metadata carries the keyword "Augstvērtīga datu kopa" (high-value dataset); data.europa.eu flags the dataset `is_hvd: true` - [aw_eka_metadata.json](https://data.gov.lv/dati/dataset/6b06a7e8-dedf-4705-a47b-2a7c51177473/resource/27ab50ae-95ae-46be-88c8-d54d4b4c70b5/download/aw_eka_metadata.json), [data.europa.eu search](https://data.europa.eu/api/hub/search/search?q=Valsts+adre%C5%A1u+re%C4%A3istra&filter=dataset&limit=5&facets=%7B%22country%22%3A%5B%22lv%22%5D%7D)
- OpenAddresses' Latvian countrywide source is the official `aw_shp.zip`, CC-BY 4.0, attribution "Valsts zemes dienests" - [openaddresses: sources/lv/countrywide.json](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lv/countrywide.json)

### Inferences
- Latvia's opening predates the HVD regulation (the VZD open-data page was published in December 2021), so HVD did not turn paid data free here; what carries the HVD label today is the dataset itself plus the INSPIRE-format services on geolatvija.lv.
- With about 551,000 live building/parcel addresses and a separate apartment-level file, coverage goes to unit level; every live record has a postcode, so no separate postal file is needed.
- Any pipeline that assumed LKS-92 TM coordinates in KOORD_X/KOORD_Y silently changed meaning on 7 Oct 2026; the DD_N/DD_E degree columns are the safer fields.
- The CSV metadata declares encoding ISO-8859-1, but the file I downloaded starts with a UTF-8 byte-order mark and decodes cleanly as UTF-8 (Latvian diacritics intact) - the metadata looks wrong.

### Gaps
- Latvijas Pasts: I found no free official bulk postcode file (search only; one per-city PDF surfaced); who legally owns the postcode system was not verified. Postcodes are nonetheless inside the VZD data.
- I did not open geolatvija.lv (JavaScript portal) to confirm the WFS/ATOM URLs, their licence text or whether a key is needed.
- I did not count `aw_dziv.csv` (apartment-level) rows.
- The EPSG code for LKS-2020 TM is not stated on the pages I read.
- OpenAddresses also lists a `city_of_riga` source; not examined.

## Lithuania - which free address data sources exist?

### Takeaway
Lithuania's Address Register is downloadable anonymously from Registrų centras as monthly CSV/GeoJSON dumps under CC BY 4.0: 1.13 million address points with postcodes and coordinates, plus a separate premises (apartment) file. House numbers and coordinates sit in different files that join on the address code.

### Cited Findings

**Authoritative register and publisher**
- Lietuvos Respublikos adresų registras (Address Register of the Republic of Lithuania), data provider Valstybės įmonė Registrų centras (State Enterprise Centre of Registers), contact atviriduomenys@registrucentras.lt - [data.gov.lt: dataset 1342](https://data.gov.lt/datasets/1342/)
- registrucentras.lt is now a JavaScript application: the old open-data pages (e.g. `/p/1186`) return only an empty shell to a plain HTTP client (probed 2026-11-11) - [registrucentras.lt/p/1186](https://www.registrucentras.lt/p/1186)

**Bulk download (no registration)**
- The portal's CSV link for "addresses given to land parcels and buildings" redirects to `https://www.registrucentras.lt/aduomenys/?byla=adr_stat_lr.csv` - [data.gov.lt distribution link](https://data.gov.lt/datasets/1342/distribution/14759/download/)
- Probed 2026-11-11, anonymous: `adr_stat_lr.csv` - HTTP 200, 56,992,530 bytes, pipe-delimited, columns `SAV_KODAS|AOB_KODAS|GYV_KODAS|GAT_KODAS|NR|KORPUSO_NR|PASTO_KODAS|AOB_NUO`, 1,132,892 rows, 1,132,710 with a postcode (format LT-85113), newest registration date 2026-10-30 - [adr_stat_lr.csv](https://www.registrucentras.lt/aduomenys/?byla=adr_stat_lr.csv)
- Probed 2026-11-11: `adr_gra_adresai_LT.zip` - HTTP 200, 62,555,111 bytes, containing `adr_gra_adresai_LT.json` (444,173,555 bytes, file date 2026-11-03): GeoJSON, CRS declared as EPSG:3346, about 1,132,891 point features with AOB_KODAS, GYV_KODAS, GAT_KODAS, X_KOORD, Y_KOORD, PASTO_KODA, E_KOORD/N_KOORD (WGS84 degrees) and `formav_dat` 2026-11-03 - [adr_gra_adresai_LT.zip](https://www.registrucentras.lt/aduomenys/?byla=adr_gra_adresai_LT.zip)
- Probed 2026-11-11: `adr_pat_lr.csv` (premises addresses) - 43,834,598 bytes, columns `SAV_KODAS|PAT_KODAS|AOB_KODAS|PATALPOS_NR|PAT_NUO`, 1,190,947 rows; `adr_gatves.csv` (streets) 2.7 MB with `GAT_KODAS|TIPAS|TIPO_SANTRUMPA|VARDAS_K|GYV_KODAS|GAT_NUO`; `adr_gra_gatves.json` (street centre lines) 49 MB, EPSG:3346 - [adr_pat_lr.csv](https://www.registrucentras.lt/aduomenys/?byla=adr_pat_lr.csv), [adr_gatves.csv](https://www.registrucentras.lt/aduomenys/?byla=adr_gatves.csv), [adr_gra_gatves.json](https://www.registrucentras.lt/aduomenys/?byla=adr_gra_gatves.json)
- The same register is catalogued as some twenty datasets (counties, municipalities, elderships, settlements, streets, historic streets and settlements, parcel/building addresses, premises addresses, each as text and as spatial data, plus monthly statistics) - [data.gov.lt search "Adresų registro"](https://data.gov.lt/datasets/?q=Adres%C5%B3+registro)
- A copy is also offered on the national geoportal: `https://www.geoportal.lt/download/opendata/RC/RC_adresai_atviri_duomenys.zip` answered HTTP 200 on 2026-11-11 - [geoportal.lt RC open data zip](https://www.geoportal.lt/download/opendata/RC/RC_adresai_atviri_duomenys.zip)

**APIs**
- data.gov.lt offers each dataset through its open data store ("Saugyklos API", get.data.gov.lt) with JSON, JSONL, RDF and CSV output - [data.gov.lt: dataset 1342](https://data.gov.lt/datasets/1342/)
- Probed 2026-11-11: `https://get.data.gov.lt/datasets/gov/rc/ar/pastatas/Pastatas` returns records (nr, korpuso_nr, pasto_kodas, aob_nuo, references to street/settlement/municipality) and `?count()` gives 1,123,119; but the address-point model `.../adresotaskas/AdresoTaskas` returns an empty list and count 0 - [get.data.gov.lt Pastatas](https://get.data.gov.lt/datasets/gov/rc/ar/pastatas/Pastatas?limit(2)), [get.data.gov.lt AdresoTaskas](https://get.data.gov.lt/datasets/gov/rc/ar/adresotaskas/AdresoTaskas?count())
- A continuously updated web service returning addresses "su koordinatėmis" (with coordinates) exists at `https://www.registrucentras.lt/adrws/rest/get` (XML), but its access rights are marked "Apriboti" (restricted); catalogued 16 Jan 2026 - [data.gov.lt: dataset 4085](https://data.gov.lt/datasets/4085/)
- INSPIRE Annex I Addresses: download service file `https://inspire-geoportal.lt/resources/atom/ad/data/AnnexI_Addresses.zip` (GML), updated monthly; "to get the most current data, contact Registrų centras" - [data.gov.lt: dataset 3516](https://data.gov.lt/datasets/3516/)

**Licence**
- The Registrų centras address datasets are licensed Creative Commons Attribution 4.0, access "Vieši" (public), status "Atvertas" (opened) - [data.gov.lt: dataset 1342](https://data.gov.lt/datasets/1342/), [data.gov.lt: dataset 1351](https://data.gov.lt/datasets/1351/)
- The INSPIRE Addresses download entry (publisher: Statybos sektoriaus vystymo agentūra) is instead tagged Creative Commons Attribution-NoDerivatives 4.0 - [data.gov.lt: dataset 3516](https://data.gov.lt/datasets/3516/)

**Update frequency**
- Text datasets: "Atnaujinama: Kas mėnesį" (monthly); the spatial address dataset's catalogue entry says "Kasmet" (yearly) - [data.gov.lt: dataset 1342](https://data.gov.lt/datasets/1342/), [data.gov.lt: dataset 1351](https://data.gov.lt/datasets/1351/)
- The file attached directly to the portal's spatial dataset (`adresai_lt.json`, 373,858,286 bytes) is dated 2021-08-25, whereas the file on registrucentras.lt was generated 2026-11-03 (see probe above) - [data.gov.lt: dataset 1351](https://data.gov.lt/datasets/1351/)

**HVD and aggregator note**
- The address datasets sit in the portal group "Didelės vertės rinkiniai" (high-value datasets); data.europa.eu flags them `is_hvd: true` - [data.gov.lt: dataset 1342](https://data.gov.lt/datasets/1342/), [data.europa.eu search](https://data.europa.eu/api/hub/search/search?q=Adres%C5%B3+registro+adres%C5%B3&filter=dataset&limit=5&facets=%7B%22country%22%3A%5B%22lt%22%5D%7D)
- OpenAddresses' Lithuanian countrywide source uses the geoportal.lt zip, licence CC BY 4.0, attribution "Registrų centras"; a separate Vilnius city source also exists - [openaddresses: sources/lt/countrywide.json](https://raw.githubusercontent.com/openaddresses/openaddresses/master/sources/lt/countrywide.json)
- Background: the register was first opened with data as of 1 October 2020 (reported as over 2.1 million unique addresses and over 1 million address points); text and spatial data join on AOB_KODAS (2020 community sources, secondary) - [OSM talk-lt, Oct 2020](https://lists.openstreetmap.org/pipermail/talk-lt/2020-October/002512.html)

### Inferences
- To build a usable address table you join three files: `adr_gra_adresai_LT` (coordinates + postcode) with `adr_stat_lr.csv` (house number, block number) on AOB_KODAS, then street names from `adr_gatves.csv` on GAT_KODAS and settlement names on GYV_KODAS; apartments come from `adr_pat_lr.csv`.
- For current data use the registrucentras.lt `/aduomenys/` files, not the copies and API models on data.gov.lt: one portal file is from 2021 and the address-point API model is empty.
- Refresh is monthly in practice (files stamped 3 November 2026 with records up to 30 October 2026), despite the "yearly" label on one catalogue entry.
- Opening dates from October 2020, before the HVD regulation; HVD's effect is the labelling and the INSPIRE service, not a price change.
- The ND (no-derivatives) tag on the INSPIRE copy conflicts with the CC BY 4.0 on the source data; prefer the Registrų centras files to avoid the question.

### Gaps
- I could not read the licence wording on registrucentras.lt itself (JavaScript-only site); CC BY 4.0 is taken from the data.gov.lt records and OpenAddresses.
- File names in `/aduomenys/` other than those listed were not enumerated (no directory listing; settlement, municipality and county files exist per the catalogue but were not probed).
- Postcode ownership (Lietuvos paštas) and any separate postal file: not checked; postcodes are in the register data.
- Conditions for the restricted real-time `adrws` service (who may use it, cost): not found.
- No historic address-point file found in the open data (historic streets and settlements are published).
- I did not download the geoportal.lt zip or the INSPIRE GML to compare their dates with the registrucentras.lt files.
