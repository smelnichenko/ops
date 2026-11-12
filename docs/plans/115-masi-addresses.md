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
- `official_address(id, country, source, ref, place_id, street, house, postcode, full_text, lat, lon, source_date,
  retired_on)` (as built in A3: `source` a key of `source(key)`, `ref` the register's id - Estonia's ADR_ID - `place_id`
  the deepest place, `retired_on` as `place`'s), unique `(source, country, ref)` (led by the source: its foreign key's index); 1.37 million Estonian rows, read
  monthly from `sihtnumbrid.zip` (148 MB of CSV), diff-only by `ref`, never deleted (an address gone from the file is
  retired). Its components resolve to places by the join `places-feeds.md` section 3 describes (component 2 =
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
- **Next:** A2b (PR 242), then A3 (built, 119a0d8), A3b.

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
- **The source row:** `places:eu` (`"frame": "eu"` in its config), seeded off, monthly on the 13th; kind DETERMINISTIC, scope PLACES. It goes through the places collector to its frame reader, not a collector of its own. masi's architecture rules keep one source package from using another, and name a collector's package by its key.
- **Rows:**
  - each country gets its COUNTRY row (named by Locale), with its level-0 boundary;
  - NUTS 1/2/3 become places of kinds `NUTS1`/`NUTS2`/`NUTS3` at level REGION, coded by `NUTS_ID`, named by `NAME_LATN`, with `nuts_code` set;
  - boundaries are simplified per level as one coverage across the EU, at 100 m, since the file is already generalised to 1:1M. Five rings in it cross themselves (German regions); they are fixed first.
- **Parents:**
  - NUTS1 under the country, NUTS2 under its NUTS1, NUTS3 under its NUTS2, each by `NUTS_ID` prefix;
  - a country's own top regions (Estonia's counties) under the NUTS 3 that holds their point, written as the county's `nuts_code`.
- **Outside every country feed's diff:** the NUTS kinds join COUNTRY in the rows a country feed never retires. A NUTS revision retires a code that GISCO no longer carries.
- **LAU and placement, per feed:** a feed declares what holds for its country (`PlacesFeed.regionsInNuts3`, `lauIsOwnCode`).
  - Estonia: its counties are NUTS 3 parts, placed by their point; its municipalities' codes are their LAU codes (GISCO's
    LAU 2023 are the EHAK codes), and each takes its county's NUTS 3.
  - A feed whose regions are NUTS regions or span several (a French région is a NUTS 1) declares nothing and maps its own.
- **Names:** a NUTS region's names are searchable unless they only repeat its parent's (Estonia's NUTS 1 and 2 are both
  "Eesti"). The country row also carries its own-language names, native scripts included.
- **Rollback limit:** once `places:eu` has run, an image older than masi 27bdc3f crash-loops on start. Its start-time link
  meets kinds it does not know. From 27bdc3f on, a failed start-time link is logged, shown on `masi_places_link_failed` and
  alerted (`MasiPlacesNotLinked`); masi still starts. So switch `places:eu` on only once rolling back below 27bdc3f is off the table.
- **Later:**
  - A6: a place's change (a re-parent rewrites every place's flattened ancestors below it) must reach the indexes, by the
    outbox or a rebuild.
  - A8: where the site draws these boundaries, "© EuroGeographics for the administrative boundaries" in the map legend
    (GISCO's condition).
  - The guards plan: a NUTS code missing from one read is retired at once; retire it only after two misses, as there.
| A3 | `official_address` from `sihtnumbrid.zip` (streamed, diff-only), its places joined; Estonia's postal codes from it | none |

**A3 as built (2026-11-12, masi 119a0d8, after PR 242):**
- **The file, measured whole** (masi `docs/places-feeds.md` §3): 1,369,879 addresses on 2026-11-05, every ADR_ID once,
  every one with a postcode; `VIITEPUNKT_X` is the easting. 38% carry an apartment ("Luise tn 1-5"); 414k are a name
  alone (a farm). Not in ADR_ID order.
- **The source:** `addresses:ee` (collector `addresses`, scope PLACES), seeded off, monthly on the 6th at 07:00; deadline
  1800 s. The zip is downloaded whole, then read a line at a time; each line is decoded strictly as UTF-8 and checked
  (6 fields, numeric ADR_ID, 5-digit postcode, a point inside Estonia in L-EST97): a file of another shape fails at its line.
- **`official_address`:** `ref` (ADR_ID, varchar for other countries' ids), `place_id` (the deepest place: settlement or
  district, else municipality - one column, its `path` gives the levels), `street`/`house` (an address without a number
  has its name as the house), `postcode`, `full_text`, point (1e-6°), `source_date`, `retired_on` (not a `valid` flag:
  as `place`). The places' stamp and keep triggers. `address.official_address_id` added for A4.
- **The join:** component 2 the municipality, component 3 the settlement or district when EHAK has one of that name
  there, else the municipality; a name two current places share answers at the level above. On the real file every
  address is placed (1,257,804 in a settlement or district).
- **Writes:** batches of 1,000, each one transaction under the source's advisory lock, only what differs written. An
  address a complete read no longer holds is retired; a failed read retires nothing. No thresholds (the operator,
  2026-11-12): the deferred upkeep plan's missing-twice and retirement brake cover addresses too.
- **A3b (masi PR after 243): Estonia's postal codes from this file instead of GeoNames.**
  - `places:ee` gains `addressesUrl` (changeset 129, which also updates the row's name and terms where they are still the
    seeded texts). Each place gets every code its addresses carry, joined by the same rule as A3 (`EstoniaAddressJoin`,
    one class for both). GeoNames only names former settlements.
  - Measured: 4,715 places; 9,585 place-code pairs against GeoNames' 5,397; 5,436 distinct codes against production's
    5,292, so the postal guard passes. Reading the file adds 18 s to the run.
  - **The switch rewrites history, decided:** the first run expires 48 of today's 5,385 pairs (34 codes the file has
    nowhere, 14 now another place's) and adds 4,248. Plan 114's "two sources that disagree keep both" does not apply: the
    Board's file is the authority on which codes a place's addresses carry, and GeoNames was an approximation of it. An
    expired code still matches, ranked after the current ones (`PlaceSearch`).
  - A file that joins no address to any settlement is refused (a zero check, not a threshold). The file's date is said in
    the run's note; a file over 45 days older than EHAK's export is said too.
  - **The deploy switches a live source** (`places:ee` is on): run it once by hand right after the deploy and watch the
    run time, the heap, and the note's "with other postal codes".
  - The snapshot keeps GeoNames' codes: the 148 MB file cannot be a fixture. A fresh database gets the file's codes at
    its first `places:ee` run. Test and fresh databases therefore differ from production until then - A4/A7 tests must not
    depend on which.
- **Allow-list:** `geoportaal.maaruum.ee` on test's list (platform 9375f19); production's is `*`.
- **After the reviews (masi dad96ee, 85565d7):** the file is read and checked whole before a row is written (another
  grid of the region - UTM 34N - passes the box line by line; written as it came, batches 170 km off would have
  stayed); an empty file is refused (an empty read never counts against an address); retiring goes a page at a time,
  stopped by the run's deadline; `source` references `source(key)`; the source runs on the **13th at 07:30**, after
  the month's places (`places:ee` on the 12th, `places:eu` on the 13th at 06:40), so addresses are placed among the
  same month's settlements. Gauges `masi_official_addresses{state}` and `..._checked_timestamp_seconds`; alerts
  `MasiAddressesNotChecked` (35 days, once read) and `MasiAddressesDropped` (a twentieth fewer in a day) - platform
  0f98c6b, visibility only.
- **"A renumbered settlement" (a test named above):** moot for this file - the join is by name (`ONIMI`, `ANIMI`), never
  by EHAK code, so a renumbering changes nothing here; it matters to extract no. 9 (codes) if that is ever read.
- **For the next plan's countries:** the run holds the refs it read in memory (Estonia: ~125 MB for 1.37 M). Austria's
  2.5 M fit; France's BAN and the Netherlands' BAG (several times more) do not in a 3 GiB heap - decide a database-side
  comparison (refs staged per run, a chunked anti-join to retire) before copying this design.
- **Open for A4/A5:** OpenSearch comes in A6, after A4 - so A4's resolver finds an official address in Postgres: by
  ADS id on `(source, country, ref)`, and by text on a normalised `full_text` (an expression index in A4's changeset;
  only the monthly run writes the table). A5: an address resolved to an official one that is later retired keeps its
  link (the row stays); a new resolver version re-resolves it.
| A4 | The resolver on all levels and the house; measured on production's 27k company addresses and the job location strings, the hand-checked set, precision and review share in the PR | none |

**A4 measured first (2026-11-12, production's company addresses against the Land Board's file of 2026-11-05):**
- The register's addresses are the Board's own full text plus `, <postcode>`. Stripping the postcode, an **exact** text
  match finds the official address for **13,405 of 13,906 distinct addresses (96.4%)**, covering **26,515 of 27,349
  companies (97%)**. 440 of those carry a postcode the file gives differently (the register's is stale: the file's
  wins). Case and whitespace normalising adds nothing.
- The 501 misses (834 companies) are mostly foreign addresses (e-residents' companies: Montréal, Plovdiv, Bratislava,
  Tehran) - country, not house - and a few Estonian ones in an older form that repeats a component ("Tartu maakond,
  Tartu linn, Tartu linn, Tamme pst 132").
- So A4's first step - the official address by its text - needs an index on `official_address.full_text` (A4's
  changeset) and the file loaded (`addresses:ee` on). Levels, weights and fuzzy are for the rest: job locations (167
  distinct strings, mostly "Tallinn", "Tallinn, Harjumaa", and reach such as "Europe", "Remote, Global") and the
  repeated-component Estonian forms.
- Two more rules for the official step, measured: a corner building's two addresses ("Kadaka tee 7 // Laki tn 20",
  "Parda tn 3 // 5 // 7": each alternative tried, a bare number continuing the street before it) and a repeated
  component collapsed ("Tartu linn, Tartu linn") recover 28; an apartment the file does not list falls to its house
  ("Estonia pst 5-410a" -> "Estonia pst 5") for 6. Together **13,439 of 13,906 (96.6%) at house level**; 15 Estonian
  texts fall to a place ("Harju maakond, Tallinn"; "..., Rõõmu küla"), 452 are foreign.
- **A4 in two PRs:** A4a - the official step (index, the rules above), the place-level fallback for the register's
  Estonian form, foreign text marked NONE (country only when it names one), the resolver version; measured on the real
  file by an env-gated test. A4b - free text (job locations, people's): the lexicon parser, case forms, levels with
  weights and margin, reach split off.
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
