## Cyprus (CY)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| No | Substitute: Cyprus Post street-to-postcode directory; no house numbers, no coordinates | Bulk CSV, no registration | CC BY 4.0 | No; the official street points cover 4% (EPSG:4258) | Yes, per street | Stated annual; newest CSV is September 2021 |

**In short.** No open dataset with house numbers was found. The official INSPIRE address service of the Department of Lands and Surveys is open (CC BY 4.0, WFS and REST, no key), but it holds 80,934 points covering 4% of the country and every house-number field is empty. The realistic substitute is Cyprus Post's street-to-postcode table: 32,819 rows, Greek and Latin street names, CC BY 4.0, no login. It has no coordinates and no single house numbers, and its two street-name column labels are swapped.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|
| Διευθύνσεις - Addresses (INSPIRE) | Τμήμα Κτηματολογίου και Χωρομετρίας (Department of Lands and Surveys, DLS) | Dataset page: https://data.gov.cy/en/dataset/543 ; REST: https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer ; WFS: https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/exts/InspireFeatureDownload/service?VERSION=2.0.0&SERVICE=WFS&REQUEST=GetCapabilities ; WMS: https://eservices.dls.moi.gov.cy/inspire/services/INSPIRE/AD_Addresses/MapServer/WMSServer?request=GetCapabilities&service=WMS | 80,934 address points placed on parcels. Street names in Latin capitals. No house numbers, no postcode. The publisher says the data cover 4% of Cyprus | WFS 2.0, ArcGIS REST (JSON and GeoJSON, 1,000 records per query), WMS; no key | CC BY 4.0. The WFS states fees "no conditions apply" and access constraints "None" | Released 15/01/2018, modified 16/03/2026, frequency "Irregularly"; the data refer to 12/11/2015 | confirmed; WMS address corrected |
| Ταχυδρομικός Κώδικας ανά Δρόμο σε Αστικές και Αγροτικές Περιοχές (postcode per street, urban and rural areas) | Τμήμα Ταχυδρομικών Υπηρεσιών (Department of Postal Services, Cyprus Post) | Dataset page: https://data.gov.cy/en/dataset/1037 ; latest CSV: https://data.gov.cy/en/resource/3104/download/file | 32,819 rows, 1,117 distinct 4-digit postcodes (both counted from the file). Street name in Greek and Latin, street limit "FROM - TO", postcode, municipality or community, district, serving post office | CSV of 6,880,847 bytes, no login. Three editions: August 2019, July 2020, September 2021 | CC BY 4.0 | Page modified 16/01/2024; stated frequency "Annually"; newest edition September 2021 | confirmed |
| Οδηγός Ταχυδρομικού Κώδικα - Post Code Directory | Cyprus Post | https://data.gov.cy/en/dataset/385 | Postcode directory as XLSX (3,263,480 bytes); content not parsed | XLSX download answers without login | CC BY 4.0 | Modified 18/09/2024; frequency "Annually"; temporal coverage 01/01/2024 | confirmed (file not opened) |
| Ταχυδρομικοί Κώδικες ανά Δήμο/Κοινότητα και Επαρχία (postcodes per municipality or community and district) | Cyprus Post | https://data.gov.cy/en/dataset/1134 | Postcodes per municipality or community and district (CSV, 74,463 bytes), plus an XLSX mapping to LAU codes (2021) | File downloads | CC BY 4.0 | Modified 16/01/2024 | confirmed |
| ΑΡΙ Κυπριακών Ταχυδρομείων για Ταχυδρομικούς Κώδικες (Cyprus Post postcode API) | Cyprus Post | Dataset page: https://data.gov.cy/en/dataset/1061 ; resource: https://data.gov.cy/el/resource/cyprus-postal-codes-api ; documentation: https://documenter.getpostman.com/view/6477303/RztmtUjG?version=latest | Postcode search API | Registration required, requested through a contact form; not called | CC BY 4.0 | Frequency "Continuously"; page modified 16/01/2024 | confirmed (listing only) |
| GISCO Address API | Eurostat | https://gisco-services.ec.europa.eu/addressapi | Address look-up; serves Cyprus | No key; look-up only, 1,000-row cap, no bulk download | None stated | Some country snapshots date from 2021-2022 | confirmed |
| OpenAddresses, Cyprus source | OpenAddresses | Source file: https://github.com/openaddresses/openaddresses/blob/master/sources/cy/countrywide.json ; downloads: https://batch.openaddresses.io | The DLS points: street name and point only, no house numbers, about 4% coverage | Free download; needs a logged-in account | Not checked | Source added 2026-09-29 in a single commit | confirmed |
| GeoNames postcodes | GeoNames | https://download.geonames.org/export/zip/ | Postcode centroids only, no addresses | File download | CC BY 4.0 | Not stated | confirmed |

### Free APIs and services

- DLS ArcGIS REST service, https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer?f=json : ArcGIS 10.91, one point layer "Addresses" plus 13 INSPIRE tables, EPSG:4258 (ETRS89 geographic), capabilities "Map,Query,Data", formats JSON and GeoJSON, at most 1,000 records per query, no key.
- DLS INSPIRE WFS 2.0, https://eservices.dls.moi.gov.cy/inspire/rest/services/INSPIRE/AD_Addresses/MapServer/exts/InspireFeatureDownload/service?VERSION=2.0.0&SERVICE=WFS&REQUEST=GetCapabilities : feature type `ad:Address`, default CRS EPSG:4258. Only the capabilities document was requested.
- DLS WMS 1.3.0 (view only), https://eservices.dls.moi.gov.cy/inspire/services/INSPIRE/AD_Addresses/MapServer/WMSServer?request=GetCapabilities&service=WMS .
- Cyprus Post postcode API: needs registration through a contact form; documentation at https://documenter.getpostman.com/view/6477303/RztmtUjG?version=latest .
- GISCO Address API (https://gisco-services.ec.europa.eu/addressapi): look-up only, no key, no licence stated.

### Caveats and recent changes

- DLS house numbers are absent. The locator table has 80,934 rows of type `addressNumber`, and none has a value. The component table is empty, so there is no postcode either.
- DLS coverage: the service extent is 32.3378 to 34.0672°E and 34.6370 to 35.2003°N. Positions are parcel-based (`specification: parcel`, `method: byAdministrator`). Identifiers are `AD.<n>` in namespace `CY.0001-DLS.AD` with status "current"; they sit in table 8 (`adAddress`), not in layer 0. `validFrom` and `beginLifespanVersion` are void.
- DLS WMS address: the WMS link printed on data.gov.cy (https://data.gov.cy/en/resource/1504) returns an HTML page, not WMS capabilities. Use the address given above, which has no `/rest` in its path.
- Cyprus Post CSV, swapped labels: the column whose name ends in `_EN` holds the Greek street name and the one ending in `_GR` holds the Latin one. There is also a serial-number column `SN`.
- Cyprus Post CSV, house numbers: one row normally means a whole street in one community. Only 857 rows carry a street limit; 839 of them contain digits and 18 hold text only. Example: the Limassol street "1ης Απριλίου" / "1 Apriliou" is split as "1 - 39, 2 - 18" for postcode 3116 and "41 - τ. 20 - τ." for 3117.
- Cyprus Post CSV, age: the page says "Annually", but the newest per-street edition is September 2021. Two older datasets (urban only, rural only) are marked "ΑΝΕΝΕΡΓΟ" (inactive).
- The Post Code Directory dataset has a second resource, a website link, that answers HTTP 403.
- High-value-dataset status: the national portal tags the DLS dataset "High Value Data". The EU catalogue does not: the record has `is_hvd: false` (https://data.europa.eu/api/hub/search/datasets/585d9407-05d2-4348-a9d6-0d0191d2dcdb), and no Cypriot dataset of any HVD category is flagged there. The national HVD page (https://data.gov.cy/en/high-value-datasets-hvds) gives the legal basis as Law 143(I)/2021, Article 21, with the harmonisation period ending June 2024.
- OpenAddresses added Cyprus on 2026-09-29 with the note "Current source data contains no house numbers … only street name and point geometry are populated. Coverage is also partial, about 4% of Cyprus per the publisher."

### Not free or not available

- National address register with house numbers: none found. Searched: data.gov.cy for "διευθύνσεις" (3 datasets, only the DLS one is about addresses) and the EU catalogue data.europa.eu (HVD "Addresses" and "Geospatial" counts for Cyprus are both 0). No project to build a register was found in the same searches.
- Cyprus Post postcode API: not open without registration.
- Overture Maps addresses (release 2026-10-21.0): no Cyprus data.

### Could not be verified

- Cyprus Post API: its behaviour, rate limits, and whether registration is free. It needs registration and was not called.
- Whether the 2024 Post Code Directory XLSX holds the same per-street content as the 2021 CSV: the file was not parsed.
- Whether a full download through the DLS WFS works: no GetFeature request was made.
- Whether the DLS points cover the areas not under government control: not examined. The Cyprus Post CSV does have rows for the districts Ammochostos (1,494) and Keryneia (58).
