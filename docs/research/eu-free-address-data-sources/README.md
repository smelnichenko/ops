# Free online address data sources, EU-27 - research in progress

Question: for every EU member state, which address data sources (house-number level, ideally with
coordinates and postcodes) are available online for free? Feeds masi plan 114 (places per market
country, one `PlacesFeed` per country).

**State, 2026-11-11 12:47 (Europe/Tallinn): first-layer research notes for all 7 regions are saved
here. The independent check runs one region at a time (operator, 12:47: "take zones 1-by-1 and record
immediate results"); each check writes `notes/verification_<region>.md` country by country. A region
without a verification file has NOT been independently checked: its notes record only what the
researcher opened and what it could not confirm.**

## What is here

| File | Countries | Research |
|---|---|---|
| `notes/pan_european_sources.md` | EU-wide layer: Regulation (EU) 2023/138 (high-value datasets), INSPIRE, OpenAddresses, OpenStreetMap, Overture, EuroGeographics, GISCO, GeoNames | done 02:33 |
| `notes/nordics_baltics.md` | DK, FI, SE, EE, LV, LT | done 02:34 |
| `notes/southeast_europe.md` | GR, CY, HR, RO, BG | done 02:31 |
| `notes/germany_austria.md` | DE (16 Länder), AT | done 02:35 |
| `notes/central_europe.md` | PL, CZ, SK, HU, SI | notes written 02:37; all five country sections present; the researcher was cut off by the usage limit before its closing summary |
| `notes/southwest_europe.md` | ES, PT, IT, MT | notes written 02:40; all four country sections and the comparison present; cut off before its closing summary |
| `notes/western_europe.md` | FR, BE, NL, LU, IE | cut off by the usage limit at 02:40, resumed 12:40, done 12:46 |

Working copies (the files the researchers write to) are in
`/home/sm/src/monitor/research_notes/EU free address data sources/` on the workstation, untracked.

## Gaps the researchers reported themselves

- No per-country INSPIRE Addresses overview: the INSPIRE Geoportal's TLS certificate was expired
  (since 2026-10-30) and was not bypassed.
- No official per-country compliance table for addresses under Regulation 2023/138 was found.
- Blocked or unread pages are listed under "Not verified" / "Gaps" in each notes file
  (e.g. `data.egov.bg` and `ktimatologio.gr` answered 403; Swedish and Danish bulk files sit behind a login).

## Still to do

1. Independent check, one region at a time, in this order: Southeast Europe, pan-European layer,
   Nordics + Baltics, Germany + Austria, Central Europe, Southwest Europe, Western Europe. Each
   re-requests every link and re-reads licence / cost / registration / update frequency on the
   publisher's own page. Its file is committed here as soon as the region finishes.
2. Write the per-country report (one section per EU country, same fields in each), applying every
   correction from the checks and marking what stayed unverified.
3. Save the report as `docs/eu-free-address-data-sources.md` in this repo and as
   `/home/sm/src/monitor/reports/EU free address data sources.md`.
