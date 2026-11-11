# Free online address data sources in the EU, country by country

State as of 11 November 2026. Question: for each of the 27 EU member states, which address data
(house-number level, ideally with coordinates and postcodes) can be downloaded or queried online
at no cost, and on what terms?

## Key findings

- **17 countries publish a free national address dataset with house numbers and coordinates:**
  Austria, Belgium, Croatia, Czechia, Denmark, Estonia, Finland, France, Italy, Latvia, Lithuania,
  Luxembourg, the Netherlands, Poland, Slovakia, Slovenia, Spain. Slovenia is counted on the
  publisher's statement: its download host refused the check.
- **7 countries have free official data with a serious limit:**
  - Germany: free per state for most states, no nationwide file, Bavaria sells its data.
  - Sweden: free, but behind a login and an approved application per product.
  - Portugal: the national address base is free but its files date from 2018.
  - Greece: a 2023 cadastre snapshot of street points, with no municipality or postcode.
  - Bulgaria: cadastre building polygons with address fields, numbering incomplete, no licence printed.
  - Hungary and Malta: official addresses only through Eurostat's lookup API, no national download found.
- **3 countries have no free source of residential addresses with coordinates:** Ireland (the
  national products are paid), Cyprus (the open service covers about 4% of the country and has no
  house numbers) and Romania (the register was never open in bulk and its geoportal has been
  offline since July 2026).
- **Postcodes are not always in the free data.** Italy's national file has none, several German
  states leave them out of the bulk file, and Greece and Malta have none in their best source.
- **Italy's coordinates are incomplete:** 67% of civic numbers have them (official figure, March 2026).
- **Older descriptions are often wrong, because services moved in 2025-2026:**
  - Denmark's DAWA closed on 1 October 2026.
  - Finland's open building-address file stopped in March 2025.
  - France's address API moved to `data.geopf.fr`.
  - Estonia's In-ADS search is being replaced by In-AKS.
  - Belgium's federal files switched coordinate system on 18 October 2026, and Latvia's on 7 October 2026.
- **EU law already requires this data to be free.** Regulation (EU) 2023/138 has applied since
  9 June 2024, but no official per-country compliance table was found.
- **Cross-border sources fill some gaps, with limits:**
  - Eurostat's GISCO Address API covers every country except Ireland; it is lookup only.
  - OpenAddresses covers 24 countries and needs a free account.
  - Overture covers 19 countries and needs none.

## How to read the overview table

- **Yes**: a national dataset with house numbers and coordinates can be downloaded or queried free.
- **Partly**: free official house-number data exists for all or most of the country, with the
  limit named in the next cell (stale, per region, lookup only, approval needed, incomplete).
- **No**: nothing free with house numbers and coordinates for more than a small part of the
  country; the best substitute is named.

## How this was made, and how far to trust it

- **Two passes.** Seven research passes (six groups of countries plus the EU-wide layer) collected
  the sources. Then an independent second reader re-requested every link and re-read licence, cost,
  registration and update cycle on the publisher's own page, claim by claim.
- **Result of the second pass:** 1,205 claims checked. 966 confirmed, 78 corrected, 10 wrong,
  126 could not be verified, 17 negative claims not disproved, 8 other (first-pass estimates and
  one cross-reference). This report uses the checked values.
- **What "could not be verified" means.** The site refused a plain client, needed a login, timed
  out, had an invalid certificate, or the file was too large to recount. Nothing was bypassed.
  Those items are listed at the end of each country section and are not stated as fact anywhere.
- **What "none found" means.** A search of the national open data portal and the EU catalogue
  found nothing. It is not proof that nothing exists.
- **Record counts** are the publisher's figure or a first-pass count ("researcher's count") unless
  a section says they were recounted. National files were not downloaded in full for the check.
- **Links and services change.** Every link here answered, or failed as described, on
  11 November 2026.

The claim-by-claim evidence is in the ops repository under
`docs/research/eu-free-address-data-sources/`: `by-country/<code>-<country>.md` holds each
country's research notes and its check table.
