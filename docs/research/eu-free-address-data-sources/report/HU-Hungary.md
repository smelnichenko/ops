## Hungary (HU)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Partly | GISCO Address API (Eurostat; data credited to Lechner Tudásközpont) | Keyless lookup API; GeoPackage on GISCO, contents unchecked | None stated; reuse terms unchecked | Yes; degrees, CRS not stated | Yes | Not known; GeoPackage dated 7 Mar 2026 |

**In short.** No Hungarian portal offers an address download: the national register, the *Központi Címregiszter* (KCR, Central Address Register), may by law be passed only to listed public bodies. The one free route to official house-number data is Eurostat's GISCO: its Address API returns Hungarian addresses with house number, postcode and coordinates, credited to the state body Lechner Tudásközpont, and GISCO's public directory holds a 146 MB GeoPackage of Hungarian addresses. The trip-up is that the GeoPackage's contents and date, and any terms for reusing the Hungarian data, were not checked, and the API is lookup-only. For postcodes alone, Magyar Posta's spreadsheet and the statistical office's gazetteer are free downloads.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Központi Címregiszter (KCR) | State register; operator's website not located | Rules: https://njt.jog.gov.hu/jogszabaly/2024-322-20-22 (Chapter XIX, § 122 onward) | By law: country, county, settlement, postcode, settlement part, district, street name and type, house number, building, staircase, floor and door, plus address coordinates, land-registry identifier and a unique ID | No public download, API or catalogue listing | Not open | - | none found |
| Postcode spreadsheet | Magyar Posta | https://www.posta.hu/static/internet/download/Iranyitoszam-Internet_uj.xlsx | Sheet "Települések": 11,160 rows of postcode, settlement, settlement part. Sheet "Bp.u.": 9,701 Budapest rows of postcode, street name and type, city part, house-number range, district. Street sheets for Miskolc (1,315), Debrecen (2,213), Szeged (1,687), Pécs (1,464), Győr (1,022). No coordinates, no single house numbers | Anonymous download, 1,019,747 bytes | None found | File last modified 12 Oct 2026 | confirmed |
| Gazetteer "Helységnévtár" | Központi Statisztikai Hivatal (KSH, statistical office) | https://www.ksh.hu/docs/helysegnevtar/hnt_letoltes_2026.xlsx (application: https://www.ksh.hu/apps/hntr.main) | Sheet "Helységek 2026.01.01.": 3,182 rows with settlement name, KSH code, legal status, county, district, area, population, dwellings. Sheet "Településrészek 2026.01.01.": 13,723 rows of settlement parts with a postcode column. No streets or house numbers | Anonymous download, 1,377,826 bytes | Not checked | File last modified 7 Oct 2026; state of 1 Jan 2026 | confirmed |
| GISCO Address API | Eurostat; Hungarian data credited "© Lechner Tudásközpont" | https://gisco-services.ec.europa.eu/addressapi (credits: https://gisco-services.ec.europa.eu/addressapi/copyright) | Hungarian addresses with house number, street, settlement, postcode and coordinates. A search for country HU, postcode 2000 returned 100 records | No key; lookup only, 1,000-row cap, no bulk download | None stated | Not known | confirmed |
| GISCO-hosted Hungarian address file | Eurostat (GISCO public directory) | https://gisco-services.ec.europa.eu/pub/Inspire/ANNEX-1/Addresses/HU/Derived/2026/HU_MST_PC_A.gpkg | GeoPackage, 145,772,544 bytes. A 2023 edition of 505 MB sits beside it. The directory's metadata sheet for Hungary (`Addresses/Metadata/HU.pdf`, dated 12 May 2023) maps source fields for street name, house number from/to, postcode and settlement | Anonymous download (file not opened) | Not checked | File last modified 7 Mar 2026 | confirmed that the file exists; contents and terms unverified |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | Anonymous download | CC BY 4.0 | - | confirmed |

### Free APIs and services

- **GISCO Address API (Eurostat):** https://gisco-services.ec.europa.eu/addressapi . No key. Its `search` call with `country=HU&postcode=2000` returned records such as house number 2, street "ÁBRÁNYI EMIL", settlement "SZENTENDRE", postcode 2000, coordinates [19.0769792, 47.6745707]. Lookup only.
- **Magyar Posta postcode lookup:** https://www.posta.hu/szolgaltatasok/iranyitoszam-kereso redirects to an interactive page at `net.posta.hu/dashboard/public/dashboard-ui/iranyitoszam-kereso`. It is a web application, not a documented API.
- **KSH gazetteer application:** https://www.ksh.hu/apps/hntr.main .
- **KSH high-value dataset APIs:** https://www.ksh.hu/hvd_eng . These serve statistics, not addresses.
- **Public lookup or API for KCR:** none found.

### Caveats and recent changes

- KCR's original decree, 345/2014. (XII. 23.) Korm. rendelet, was repealed with effect from 7 November 2024. The rules are now Chapter XIX of 322/2024. (XI. 6.) Korm. rendelet.
- § 127 of that decree lets address data go by automatic transfer to the population and address registry, the land authority, the public-building cadastre operator, the Smart City platform operator, the tax authority, KSH and bodies obliged to provide digital services. The postal operator may see addresses for its own tasks but may not pass them on. The chapter has no wording on public access, public queries or fees.
- The only publication duty is local: addresses affected by an address procedure are posted on the municipality's website or notice board for at least one month (§ 129(6)).
- The GISCO route is official-source data, but it is not published by any Hungarian portal. Check the reuse terms and the date of the data before relying on it.
- Magyar Posta's spreadsheet gives street-level postcodes only for Budapest and five cities, as house-number ranges.
- Magyar Posta publishes no licence for the spreadsheet that could be found. A third-party note says the file is listed on Magyar Posta's site under public-interest data and treats the licence as unresolved (https://datahub.io/logistics/postal-codes-hu/.licensing-notes).
- High-value datasets: on data.europa.eu, none of the 2,283 Hungarian datasets carries the high-value flag, and none is in the category "Addresses" (11 Nov 2026).
- The register was built in a 2012-2015 project that replaced overlapping address databases; Lechner Tudásközpont's predecessor and Magyar Posta were in the consortium (https://lechnerkozpont.hu/en/node/568).

### Not free or not available

- **KCR itself:** no public download, API or open-data listing found. Searched: the governing decree; the national open data portal kozadatportal.hu (2,283 datasets; searches for "cím", "címek", "címregiszter", "irányítószám", "házszám", "utca", "address", "KCR" and wildcard title searches found no address dataset); data.europa.eu; and Lechner's national INSPIRE catalogue.
- **INSPIRE Addresses dataset or service:** none found in the national INSPIRE catalogue (https://inspire.lechnerkozpont.hu/geonetwork/srv/eng/csw , 308 records). An ATOM feed exists for administrative units; the matching address feed name returns 404.
- **OpenAddresses:** no Hungarian source.
- **Overture Maps addresses:** Hungary is not covered.
- **Voter-register address data (National Election Office):** released only to candidates and nominating organisations, for campaigning, for a fee (https://www.valasztas.hu/en/szavazokori-nevjegyzeki-adatok-igenylese-jeloltek-partok-reszere).

### Could not be verified

- The GISCO GeoPackage: its contents, the date of the data in it, and GISCO's reuse terms for the Hungarian data. Only the file's existence, size and date were checked.
- Whether a public KCR lookup or a paid data-supply service exists: one web search found only legal texts, a 2015 project leaflet and municipal notices. The search was not exhaustive.
- Magyar Posta's terms of use for the spreadsheet: no terms page was found.
- The licence of the KSH gazetteer: not checked.
- Municipal open address datasets: not searched beyond the national portal, where none appeared.
- Whether the election office currently publishes a downloadable street list: not checked.
- The EU INSPIRE Geoportal's record for Hungary: the site presented an expired TLS certificate and was not opened.
