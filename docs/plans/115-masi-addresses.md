# Plan 115: masi addresses - one model, every connection, search by any level and by range

Written 2026-11-12 from the operator's decisions of that day. Builds on plan 114 (places, the resolver's weighted
levels, OpenSearch) and replaces its single "one location per entity" model for jobs, companies and people.

## Goal

The operator, 2026-11-12: "we need a thorough redesign here, so we can implement job/company or person search by
address/parts of address like country/city/other address levels", "or even by range from some point/address", "we cover
whole world but start with EU countries", "what if we hold addresses both in DB and opensearch, where we use opensearch
exactly for searches?", "address data source collectors for other countries besides EE is the next step after address
connection redesign", "save it as plan and start implementing".

A job, a company or a person can be found by any part of an address - country, region, municipality, settlement,
district, street, postal code - and by range from a point or an address. One address model serves all three.

## Where masi is today (production, 2026-11-12)

- **Companies:** `company.address` text and `hq_city`: 27,348 of 28,971 have an address, all from the business
  register ("Harju maakond, Tallinn, Kesklinna linnaosa, Luise tn 1, 10142"); the 429 without a registry code have none.
- **Jobs:** `job.location` as the board wrote it - 140 distinct strings over 1,488 open jobs ("Tallinn" 247, "Tallinn,
  Harjumaa" 105, "Europe" 143, "Worldwide" 70, "Amsterdam, Netherlands; Remote - Europe" ...), 291 empty; `job.country`
  for 1,439; `remote_scope` derived from the text; `job_listing.location_raw` per posting.
- **People:** no address of any kind (11,985 people); tied to companies only.
- **Places:** `place` / `place_name` / `place_postal` (plan 114 phase 0a): Estonia's 4,812 places (counties,
  municipalities, settlements, districts, former places) from the bundled snapshot, searchable by name and postal code;
  no points, no parent links, nothing points at them.
- **OpenSearch 3.9.0** runs in production since 2026-11-12 (one node, green), not used by masi yet.

## Decisions (the operator, 2026-11-12)

1. **One level model for every country:** country -> regions (any depth: the EU's NUTS 1/2/3, then a country's own,
   such as Estonia's maakond, which sit inside NUTS 3) -> municipality (the EU's LAU) -> settlement -> district -> street
   -> house. Each country maps its own units onto it (Estonia: EE0 -> EE00 -> EE001..EE00A -> maakond -> vald or a city
   that is its own municipality -> küla / alevik / alev / linn -> linnaosa). A place's path holds every ancestor, so any
   level is one containment test. Every address carries a point or an area and its precision. (Refined 2026-11-12 while
   building A1: Estonia's five NUTS 3 regions are groups of counties, so regions take any depth.)
2. **Data sources per country** as researched in masi's `docs/places-feeds.md` (GeoNames where no official route
   works); Eurostat GISCO for the NUTS / LAU frame and boundaries.
3. **Estonia's house level** from the Land Board's official address file (`sihtnumbrid.zip`: every valid address, its
   full text, postcode and reference point; keyless, monthly on the 5th). No outside geocoder, no address leaves the
   cluster.
4. **Many addresses per entity, each with a role:** a company's registered address and offices; a job's locations (one
   per place it names) and its remote reach; a person's work address (through a company tie) and own address when a
   source gives one.
5. **People's own address** from GitHub's location field and the business register (board members); nothing else now.
6. **Range search by distance first** (points and areas); travel time later (plan 114 phase 3e).
7. **Postgres is the truth, OpenSearch only searches:** an outbox written in the same transaction as each change, an
   indexer lane draining it, every index rebuildable from Postgres; if OpenSearch is down only address search says so.
8. **Order:** this plan on Estonia's data first; then the address collectors of the other EU countries (the next plan,
   from `docs/places-feeds.md`); place upkeep guards and self-healing are a later plan still (the operator: "a things of
   distant future/next plan").

## Model (Postgres)

### Places become a hierarchy
- `place` gains `level` (COUNTRY, REGION, MUNICIPALITY, SETTLEMENT, DISTRICT), `parent_id`, `path` (`bigint[]` of every
  ancestor's id, the place's own last; GIN-indexed - "anywhere in Harju" is `path @> {harju}`), `nuts_code`, `lau_code`,
  and its location: `lat`, `lon` (its representative point) and `area` (its boundary as GeoJSON text, simplified;
  no PostGIS - the CNPG image has none, and OpenSearch does the geometry).
- Each feed's country gets its own row (A1); every country's row and Estonia's NUTS 1/2/3 rows come in A2b, and EHAK's
  county and municipality rows take their LAU and NUTS 3 codes from GISCO; settlements and districts hang under their
  municipality. A city that is its own municipality (Keila, Narva, Tallinn) has no settlement row: a search by settlement
  matches it at municipality level.
- Points and areas: EHAK's own polygons (the shapefile beside the DBF the feed reads; L-EST97, EPSG:3301, converted to
  WGS84 in masi with a pinned transform) for settlements, municipalities and counties; GISCO's for NUTS.

### Official addresses (Estonia's house level)
- `official_address(id, country, source_id, adr_id, settlement_place_id, district_place_id, street, house, postcode,
  full_text, lat, lon, valid)`, unique `(country, source_id, adr_id)`; ~1.5 million Estonian rows, read monthly from
  `sihtnumbrid.zip` (streamed: 148 MB of CSV), diff-only by `adr_id`, never deleted (an address gone from the file is
  marked invalid). Its components resolve to places by the join `places-feeds.md` section 3 describes (component 2 =
  municipality, component 3 = settlement when EHAK has it there).
- Settlements' postal codes come from it too (replacing GeoNames' for Estonia, which stays for former names).

### Addresses and connections
- `address(id, country, raw, source, place_id, official_address_id, street, house, postcode, lat, lon, precision,
  method, score, resolver_version, resolved_at)`:
  - `raw` - the text as the source gave it, kept as is;
  - `place_id` - the deepest place resolved (its `path` gives every level above);
  - `precision` - HOUSE, STREET, DISTRICT, SETTLEMENT, MUNICIPALITY, REGION, COUNTRY, NONE;
  - `method` - CODE, POSTAL, EXACT, FUZZY, POINT, MANUAL (plan 114's resolver), with its score;
  - one row per distinct raw text and source, shared by every entity that uses it (27k company addresses are 27k
    rows; 140 job location strings are 140).
- `address_link(entity_type, entity_id, address_id, role, ordinal, since, until)`, PK `(entity_type, entity_id, role,
  address_id)`, index `(address_id)`:
  - company: REGISTERED (the register), OFFICE (its site, its postings' places);
  - job: LOCATION (each place it names; "Tallinn; Tartu" is two), from its open listings;
  - person: WORK (through a company tie: the company's REGISTERED or OFFICE, derived, not copied), OWN (GitHub, register).
- `reach` stays separate from addresses: a job's or company's remote reach is a set of countries (plan 114's reach
  arrays), never an address and never matched by distance.
- The old columns (`company.address`, `hq_city`, `job.location`, `country`, `remote_scope`, `job_listing.location_raw`)
  stay as the raw input; plan 114's `loc_*` columns are not built - this model replaces them.

### Outbox
- `search_outbox(id, entity_type, entity_id, changed_at)` written in the same transaction as any change to an entity's
  addresses, connections or searched fields; drained by the indexer; a gauge of its oldest row, alerted.

## Resolution: raw text to an address

Plan 114's resolver, extended to all levels and to the house:
1. **A code the source gives** - the business register's address carries its ADS id: an exact `official_address`.
2. **An official address by its text** - the register's and boards' Estonian addresses in the Land Board's own format
   ("Harju maakond, Tallinn, Kesklinna linnaosa, Luise tn 1"): matched to `official_address.full_text` (normalised).
3. **Levels parsed and looked up** - "Tallinn, Harjumaa, Estonia", "Peetri alevik, Rae vald": each part a level, looked
   up inside the level above it, with plan 114's weights, score and margin; a tie stays unresolved, never guessed.
4. **Fuzzy** (a misspelling) only inside the resolved parent, above a threshold.
5. **Regions and reach** ("Europe", "Remote, Global", "EMEA") are reach, not addresses.
6. **Several places in one text** ("Amsterdam, Netherlands; Remote - Europe") split first: each part its own address
   or reach.
Candidates come from OpenSearch's gazetteer index (places and official addresses); masi scores and decides; every
resolution keeps method, score and resolver version, so a new version re-resolves the stored raw texts.

## Search (OpenSearch)

- **Gazetteer index** `gazetteer`: places (every name and form, level, path, point, area) and Estonia's official
  addresses (full text, street, house, postcode, point) - the resolver's candidates and the address picker's
  suggestions.
- **Entity indexes** `jobs`, `companies`, `people`: one document per entity with its fields (title, name, status ...)
  and its addresses flattened by role: every ancestor place id and name, street, postcode, `geo_point` (house or place
  point), `geo_shape` (the area of a coarse place), precision; its reach countries.
- **Queries**, one shape for the three lists:
  - by level: `path` contains a place id (country, region, municipality, settlement, district);
  - by text: an address typed ("Teaduspargi 11, Tartu") resolved first, then as a level or a point;
  - by postal code, by street;
  - **by range:** within N km of a point or an address - `geo_distance` on points, `geo_shape` within-distance on areas
    (a "Tallinn" job is in range when Tallinn's area comes within N km); remote reach in or out by a switch;
  - combined with each list's own filters, sorted (distance when a range is set), paged as every masi list.
- **Sync:** the indexer drains the outbox in batches; a full rebuild into a new index behind an alias, switched
  atomically, on start when an alias is missing and on a mapping version change.
- **Distance is computed by the index at query time:** OpenSearch's geo queries over indexed points and shapes, no
  per-user table. Plan 114's per-user `user_reach` cache stays for travel time (routing is the expensive part).

## Phases (one PR each, in order; failing test first in each)

**Status 2026-11-12 (evening, UTC):**
- **A1 live:** masi #237 + #238, `c9da8e0` / `6fd7c90`. Estonia is one hierarchy, every path set.
- **A2 live:** masi #239, `8a71b78`.
- **Plan 114 phase 0a' live:** masi #240, `7067604`. The `places:ee` row and its collector bean.
- **`places:ee` switched on and run once, 2026-11-12 17:11 UTC** (the operator's choice): run 16358 OK in 33 s; 4,800
  places with a point and boundary (4,694 settlements, 13 districts, 78 municipalities, 15 counties). Monthly on the 12th
  at 06:30 from then on.
- **Production heap:** 3 GiB in a 5 GiB container (the run's heap peaked at 2.2 GiB).
- **Next:** A2b.

| # | What | Visible |
|---|---|---|
| A1 | Schema: `place` hierarchy columns (level, parent, path, NUTS/LAU codes, point, area) with CHECKs; `address`, `address_link` (with `since`/`until`), `search_outbox`; each feed's country row and its places linked into the hierarchy by their codes (diff-only, at each apply and at a start); an unknown kind fails closed; a former name under the place it is today | none |
| A2b | The EU frame: every country's row, NUTS 1/2/3 regions from GISCO (names, boundaries; read in a metric grid, EPSG 3035 - the simplifier's tolerance is metres), Estonia's LAU/NUTS 3 codes on its county and municipality rows, a country's own regions hung under their NUTS 3 (the REGION parent rule takes any depth; the frame rows join the country row outside every feed's diff) | none |
| A2 | Points and areas: EHAK's settlement, municipality and county polygons from their shapefiles (each file simplified as one coverage, converted, snapped valid; the `.prj` must be EPSG 3301); a place's point and area kept current by `places:ee`. GISCO NUTS/LAU codes and boundaries for Estonia moved to A2b. The snapshot carries no points: a fresh database has them after the first `places:ee` run (A4's tests may need points in the snapshot) | none |

**A2b as built (design, 2026-11-12):**
- **The source:** GISCO's NUTS 2024, `NUTS_RG_01M_2024_3035.geojson`.
  - 61 MB; 1,798 features in 39 countries; 1.6M vertices; EPSG 3035, which is metric.
  - Updated 2026-09-25, © EuroGeographics. masi is non-commercial; credit in NOTICE.
- **Countries:** the EU 27 (`EU_STAT = 'T'`). GISCO's `EL` is stored as ISO `GR`.
- **Read:** streamed feature by feature (Jackson), never parsed whole; only the EU countries' features are kept.
- **The source row:** `places:nuts`, seeded off, monthly; kind DETERMINISTIC, scope PLACES; its own collector.
- **Rows:**
  - each country gets its COUNTRY row (named by Locale), with its level-0 boundary;
  - NUTS 1/2/3 become places of kinds `NUTS1`/`NUTS2`/`NUTS3` at level REGION, coded by `NUTS_ID`, named by `NAME_LATN`, with `nuts_code` set;
  - boundaries are simplified per level as one coverage, at 100 m, since the file is already generalised to 1:1M.
- **Parents:**
  - NUTS1 under the country, NUTS2 under its NUTS1, NUTS3 under its NUTS2, each by `NUTS_ID` prefix;
  - a country's own top regions (Estonia's counties) under the NUTS 3 that holds their point, written as the county's `nuts_code`.
- **Outside every country feed's diff:** the NUTS kinds join COUNTRY in the rows a country feed never retires. A NUTS revision retires a code that GISCO no longer carries.
- **LAU:** Estonia's municipality rows get `lau_code` = their EHAK code (GISCO's LAU 2023 codes are the EHAK codes). Other countries' LAU comes with their own feeds.
| A3 | `official_address` from `sihtnumbrid.zip` (streamed, diff-only), its places joined; Estonia's postal codes from it | none |
| A4 | The resolver on all levels and the house; measured on production's 27k company addresses and the job location strings, the hand-checked set, precision and review share in the PR | none |
| A5 | Connections written: companies (REGISTERED from the register's ADS id), jobs (LOCATION per place named, reach apart) at ingest, register import and merge; people (OWN from GitHub's location, the register; WORK derived); batched backfill of every row; a gauge of entities without addresses | none |
| A6 | OpenSearch: masi's client, the gazetteer and entity indexes, the outbox indexer, the alias rebuild, its alerts | none |
| A7 | Search API: `/jobs`, `/companies`, `/persons` take `place`, `postal`, `street`, `near` (a point or an address) and `km`; the address picker's `/addresses/suggest`; paging and sorting as every list | the API |
| A8 | Site: the address filter and picker on the three lists, the location column; rendered samples and the operator's OK first | the filter |

Then: the other EU countries' address collectors (next plan, per `docs/places-feeds.md`); travel time (plan 114 3e);
place upkeep guards and self-healing (a later plan).

## Tests named now

- the hierarchy: every Estonian place's path ends at EE; "anywhere in Harju" finds a Rae vald village's job;
- official addresses: the Land Board's sample rows joined to their EHAK settlement; a renumbered settlement; a row whose
  third component is no settlement ("raudteeharu") goes to the municipality;
- the resolver: the register's address to its official address by ADS id; "Tallinn, Harjumaa" and "Tallinn, Estonia" one
  place; "Amsterdam, Netherlands; Remote - Europe" one address plus reach; a namesake village tie unresolved;
- range: a house within 5 km found, one at 6 km not; a "Tallinn" job in range of a point 3 km outside the city's
  boundary; remote jobs in or out by the switch;
- sync: a change reaches the index through the outbox; a rebuild behind the alias leaves search answering throughout;
  OpenSearch down - address search says so, ingest and edits go on;
- every list path pages (plan 112 / the paging rule) with an address filter set.

## Risks

- **1.5 million official addresses in Postgres:** about 0.5 GB with indexes; read monthly, diff-only, streamed; the
  ResultSizes guard sees each batch (declared).
- **Areas without PostGIS:** geometry lives in OpenSearch; Postgres keeps GeoJSON text and points only. A point-in-polygon
  in masi (JTS) only for a map pick.
- **Business register address formats** other than the Land Board's: measured in A4 before A5 writes anything.
- **People's GitHub locations** are free text in any language ("Tallinn, Estonia", "EE", "Earth"): resolved like job
  locations, unresolved kept as raw.
