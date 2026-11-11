# Free online address data sources, EU-27 - research in progress

Question: for every EU member state, which address data sources (house-number level, ideally with
coordinates and postcodes) are available online for free? Feeds masi plan 114 (places per market
country, one `PlacesFeed` per country).

**State: PAUSED on the operator's instruction, 2026-11-11 02:35 (Europe/Tallinn): no new agents, only
the first layer (the seven research passes) is collected here. Nothing in `notes/` has passed the
independent check yet. Treat every claim in the notes as unverified.**

## What is here

| File | Countries | Research | Independent check |
|---|---|---|---|
| `notes/pan_european_sources.md` | EU-wide layer: Regulation (EU) 2023/138 (high-value datasets), INSPIRE, OpenAddresses, OpenStreetMap, Overture, EuroGeographics, GISCO, GeoNames | done 02:33 | started 02:33, not finished |
| `notes/nordics_baltics.md` | DK, FI, SE, EE, LV, LT | done 02:34 | started 02:34, not finished |
| `notes/southeast_europe.md` | GR, CY, HR, RO, BG | done 02:31 | started 02:31, not finished |
| `notes/germany_austria.md` | DE (16 Länder), AT | done 02:35 | not started (pause) |
| (not saved yet) `western_europe.md` | FR, BE, NL, LU, IE | still running at the pause | not started |
| (not saved yet) `central_europe.md` | PL, CZ, SK, HU, SI | still running at the pause | not started |
| (not saved yet) `southwest_europe.md` | ES, PT, IT, MT | still running at the pause | not started |

Working copies (the files the researchers write to) are in
`/home/sm/src/monitor/research_notes/EU free address data sources/` on the workstation, untracked.
Each check writes `verification_<region>.md` beside the notes it checks; those are copied here as
`notes/verification_<region>.md` when they finish.

## Gaps the researchers reported themselves

- No per-country INSPIRE Addresses overview: the INSPIRE Geoportal's TLS certificate was expired
  (since 2026-10-30) and was not bypassed.
- No official per-country compliance table for addresses under Regulation 2023/138 was found.
- Blocked or unread pages are listed under "Not verified" / "Gaps" in each notes file
  (e.g. `data.egov.bg` and `ktimatologio.gr` answered 403; Swedish and Danish bulk files sit behind a login).

## To resume

1. Copy any notes and `verification_*.md` files that landed in the working folder after the pause.
2. Run the independent check for the four regions that have none (same brief as the first three:
   re-request every link, re-read licence / cost / registration / update frequency on the publisher's
   own page, verdict per claim, no spoofed headers, no TLS bypass).
3. Write the per-country report (one section per EU country, same fields in each), applying every
   correction from the checks and marking what stayed unverified.
4. Save the report as `docs/eu-free-address-data-sources.md` in this repo and as
   `/home/sm/src/monitor/reports/EU free address data sources.md`.
