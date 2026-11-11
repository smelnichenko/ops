# Brief for the per-country report sections

You are writing one part of a report that answers: **for every EU member state, which address data
sources are available online for free?** State as of 2026-11-11. Readers: the operator who asked,
and developers who will build one address import per country from it. They have not seen the
research notes. They need to know, per country, what to download or call, on what terms, and what
is not there.

## Inputs

For each country you are given `by-country/<CC>-<Name>.md`. It has two parts:
1. "Research notes" - what a first researcher found.
2. "Independent check" - a second reader's verdict on each claim, made by re-requesting the sources.

The check overrides the notes. Also read the "corrections" and "unverified" lists at the top of the
region's `notes/verification_<region>.md`.

## Rules for every statement

- CONFIRMED claim: state it plainly.
- CORRECTED or WRONG claim: use the checked value only. Do not repeat the wrong one.
- UNVERIFIED claim: either leave it out or put it under "Could not be verified" with the reason.
  Never state it as fact elsewhere, never soften it into "reportedly".
- NOT DISPROVED (a negative such as "no open register exists"): write "none found" and say where
  was searched. Do not write "does not exist".
- A claim in the notes with no row in the check: treat as unverified.
- Record counts that the check did not recount: give them as "publisher's figure" or
  "researcher's count", not as checked.
- Every source gets its exact URL, copied from the inputs. Do not invent, shorten or "fix" a URL.
- Do not add knowledge of your own. If the inputs do not say it, it is not in the report.
- Do not make web requests. This is a writing task over the saved material.

## EU-wide sources (already checked; mention per country in one line each where they apply)

- GISCO Address API (Eurostat), https://gisco-services.ec.europa.eu/addressapi : serves every EU
  country except Ireland. No key. Lookup only (1,000-row cap, no bulk download). No licence stated.
  Some country snapshots date from 2021-2022.
- OpenAddresses, https://batch.openaddresses.io : sources for every EU country except Hungary,
  Ireland, Malta. Downloads are free but need a logged-in account. Weak spots: Germany lacks
  Bavaria; Romania is four towns around Bucharest, frozen 2020; Sweden is 18 municipalities; Cyprus
  has no house numbers; Slovenia's last successful run was 2024-06-14.
- Overture Maps addresses (release 2026-10-21.0, no account, GeoParquet): 19 EU countries; missing
  Bulgaria, Cyprus, Greece, Hungary, Ireland, Malta, Romania, Sweden. Licence is per country.
- GeoNames postcodes, https://download.geonames.org/export/zip/ (CC BY 4.0, postcode centroids
  only, no addresses): a file for every EU country except Greece; Ireland and Malta partial.

## Output: one file per country, written as soon as that country is done

Write `/home/sm/src/ops/docs/research/eu-free-address-data-sources/report/<CC>-<Name>.md` (same
`<CC>-<Name>` as the input file) with exactly this structure:

```
## <Name> (<CC>)

| Free national address data | Best free source | How to get it | Licence | Coordinates | Postcodes | Update cycle |
|---|---|---|---|---|---|---|
| Yes / Partly / No | name | e.g. "bulk CSV, no registration" | licence | yes/no + CRS | yes/no | e.g. weekly |

**In short.** Two to four sentences: what a developer should use, and the one thing most likely to trip them up.

### Sources

| Source | Publisher | Link | What it holds | Access | Licence | Updated | Check |
|---|---|---|---|---|---|---|---|

### Free APIs and services

### Caveats and recent changes

### Not free or not available

### Could not be verified
```

- The first table has exactly one data row; keep each cell under about 12 words and put no "|"
  inside a cell. "Yes" = a national house-number dataset with coordinates is free to download or
  query; "Partly" = free but incomplete, stale, regional only, login-gated or without coordinates
  (say which in the next cell); "No" = none found.
- "Check" column: confirmed / corrected / unverified / none found.
- Sources table: the authoritative national source first, then regional, postal, statistical,
  then the EU-wide sources that cover the country.
- Bullets under the last four headings; write "None." under a heading with nothing to say.
- Plain English, short sentences, no filler, no first person, no mention of "the notes", "the
  researcher" or "the checker" - just what is known and how firmly. Native names of registers in
  their own language with an English gloss on first use.
- Write each country file as soon as that country is finished, before starting the next, so that
  an interruption loses at most one country. Do not commit anything to git and do not edit any
  file outside `report/`.

Final message: one line per country - the file written, the "Free national address data" value,
and anything in the inputs that was contradictory or that you could not place.
