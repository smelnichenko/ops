---
name: naval-navigator
description: Maritime domain knowledge for code that models vessels — AIS/AIVDM field semantics (SOG vs speed-through-water, COG vs heading, MMSI/MID structure, crew-set nav-status, Class A vs B, sentinels, message cadences), surface-vessel kinematics envelopes, ship classes (cargo/tanker/passenger/fishing/tug/sailing/HSC/anchored) and their motion, and near-horizon observation geometry for coastal tracking. Read BEFORE designing or reviewing AIVDM decoding/interpretation, vessel tracking/prediction, MMSI/nav-status handling, vessel classification, or sea-target pointing geometry — and whenever a model implicitly assumes "vessel = cargo ship steaming in a straight line".
---

# Naval navigation domain discipline

Working rules for code that models vessels from AIS. The sea domain is the slow-motion mirror of the
air domain: the recurring failure is the same — a wrong domain model or trusting a field to mean what
its name suggests — but the physics, the datums, and the geometry all differ. The one that bites: a
ship is a **surface** target near or below the horizon, not a point high in the sky. Check the
assumption, then the numbers.

## 1. Kinematics envelopes — surface motion you can compute

Vessels are slow and enormously inertial; the bounds are tighter than aircraft and CV models fit
*better* — except in harbours.

- **Speed**: cargo/container 10–24 kt, VLCC tanker 12–16 kt, ferry/passenger 15–30 kt, HSC (fast
  ferry/catamaran) 30–45 kt, fishing 8–12 kt in transit (erratic while working), tug 8–13 kt,
  sailing/pleasure 5–15 kt, anchored/moored **0**. AIS caps SOG at 102.2 kt (raw 1022 = "≥"), so
  anything near that is a fast craft or bad data.
- **Turn rate is small and hull-limited**. A large ship's tactical diameter is several ship-lengths:
  a 300 m tanker turns in ~1–2 km, taking minutes. Sustained cruise turns are **< 0.5 °/s**; a hard
  rudder on a big hull is still only ~1–2 °/s. The AIS Rate-of-Turn field encodes up to ±708 °/min
  (±11.8 °/s), but that ceiling is for small craft — a VLCC physically cannot approach it. A "large
  cargo vessel turning 5 °/s" is a decode or association bug, not a manoeuvre.
- **Acceleration is glacial**: a loaded ship takes *minutes* to change speed and *miles* to stop
  (a VLCC's crash-stop is ~15 min / 3 km). SOG is the most constant state a vessel has — even more so
  than an aircraft's — so CV process noise along-track should be tiny.
- **CV-model error in a turn** ≈ ½·v·ω·t²: a cargo ship steaming *straight* has ω ≈ 0 so CV is
  effectively exact, but in a 0.3 °/s course change 30 s of CV drifts **~24 m** (≈ 0.27° at 5 km —
  right at a sub-degree pointing budget, so "CV is fine short-term" is true only while it isn't
  turning; cap extrapolation during a manoeuvre). A **fishing boat trawling** or a **sailboat tacking** reverses
  course repeatedly (zigzag COG); a tug in close-quarters work pivots — for these, CV over more than a
  few seconds is useless, exactly like a thermalling glider. Anchored vessels **swing around the
  anchor** (position roughly fixed, heading wandering ±180°).
- **No vertical dimension.** A vessel is at sea level. In the geodetic frame that is height-above-
  ellipsoid = **+N** (the geoid undulation), the SAME frame a GNSS observer uses — so drop N and every
  ship sits N metres off and its (already tiny) elevation tilts.

## 2. AIS field semantics — the data means less than its name says

- **SOG ≠ speed through water**: SOG is GPS ground speed; tide/current shift it from speed-through-
  water by several knots (a 12 kt ship in a 3 kt current makes 9–15 kt over ground). AIS SOG LSB 0.1
  kt; **1023 = not available**, 1022 = "≥102.2 kt". A vessel with no GPS fix transmits SOG = 1023.
- **COG ≠ heading**, and the gap is the sea's crosswind. COG is motion over ground (GPS track); true
  heading is where the bow points (gyro/magnetic). Current and leeway make a ship **crab**: in a beam
  tide, heading and COG differ by 10–30°. For a **position track / pointing**, use COG; heading only
  tells hull orientation. COG LSB 0.1°, **3600 = N/A**; heading integer 0–359, **511 = N/A**. At
  anchor (SOG ≈ 0) COG is undefined/garbage — like a helicopter at hover — but heading is still valid
  as the ship swings. Never feed a resting vessel's COG into a velocity model.
- **MMSI is not always a ship** (9 digits, and the leading digits are a type discriminator):
  - `2..7` + = an ordinary ship; the first **three** digits are the MID (Maritime Identification
    Digits) → flag state. `2xx` Europe, `3xx` N.America/Caribbean, `4xx` Asia, `5xx` Oceania/SE Asia,
    `6xx` Africa, `7xx` S.America. Flags-of-convenience registries are spread across these (Panama `35x`
    in 3xx, Liberia `63x` in 6xx, Marshall Is `538` in 5xx), not one block.
  - `00xxxxxxx` coast station, `0xxxxxxxx` group of ships, `111xxxxxx` **SAR aircraft**, `98xxxxxxx`
    craft associated with a parent ship, `99xxxxxxx` **aids-to-navigation** (a buoy/lighthouse — fixed,
    not a vessel), `970/972/974` SAR-transponder / MOB / EPIRB-AIS.
  - So a country/vessel lookup MUST gate on the 9-digit, leading-`2..7` form before reading the MID;
    everything else is legitimately not a flagged ship.
- **Nav-status is crew-set and often wrong.** The 0–15 code (0 under-way-engine, 1 at-anchor, 2 not-
  under-command, 3 restricted-manoeuvrability, 4 constrained-by-draught, 5 moored, 6 aground, 7
  fishing, 8 under-way-sailing, 15 = default/undefined) is entered by hand and frequently stale — a
  moored ship still broadcasting "under way" is common. Use it for display/plausibility hints, **never**
  as ground truth for automation. A vessel showing nav-status 1/5 but SOG 8 kt is dragging anchor or a
  stale status, not a stationary target.
- **Class A vs Class B is a capability difference, and null fields are legitimate.** Class A = SOLAS
  ships (12.5 W, msgs 1/2/3 + 5), report every 2–10 s under way (3 min at anchor), and carry nav-status,
  ROT, draught, destination. Class B = leisure/small (2 W, msgs 18/19 + 24), report every 30 s (3 min
  slow), and legitimately **lack nav-status, ROT, draught**, and sometimes heading. A null on a Class B
  vessel is normal, not missing data.
- **Static data arrives minutes apart — every field needs its own age.** Position (1/2/3/18/19) is
  seconds-fresh; **name / type / dimensions / destination (msg 5, msg 24 A/B) broadcast every ~6 min**.
  A newly-acquired vessel has a position but NO name or type until a static message lands — plot it,
  don't treat the null name as corruption, and don't let a fresh position imply fresh static. (This is
  the maritime version of "track alive ≠ field X fresh".)
- **Dimensions & draught**: length = A+B (GPS-antenna-to-bow + to-stern), beam = C+D (to-port + to-
  starboard); **0 = not available**. Draught msg-5 LSB 0.1 m, 0 = N/A. A `0/0` dimension pair is
  "unknown", not a zero-size vessel.
- **Position sentinels**: lat **91°** (raw 91·600000), lon **181°** (raw 181·600000) = no fix.
  Absolute lat/lon in 1/10000-minute units (÷600000 → degrees); a decoder must map the sentinel to
  null, not plot a ship at 91°N.
- **Two channels, one stream**: AIS alternates on 161.975 (A/87B) and 162.025 MHz (B/88B). A multi-
  fragment message is reassembled per (sequence-id, channel); the channel token is part of the key.
- **AIS is self-reported and spoofable** (as is ADS-B, but AIS more so, and with no crypto): identity,
  type, and even position can be falsified ("dark" ships go silent; spoofers invent tracks). Trust AIS
  for display and situational awareness, never as a safety-of-navigation or security source.

## 3. Vessel classes — "vessel" is not one motion model

| Class | Speed | Turn | Traps |
|---|---|---|---|
| Cargo / container | 10–24 kt | slow, ~1–2 km diam | Predictable; CV excellent |
| Tanker (VLCC) | 12–16 kt | very slow, km-scale | Stops in miles; manoeuvres over minutes |
| Passenger / ferry | 15–30 kt | moderate; tight on approach | Scheduled routes; harbour turns are quick |
| HSC (fast ferry) | 30–45 kt | fast | SOG-cap 1022 sentinel; agile — CV weaker |
| Fishing | 8–12 kt transit | **erratic while working** | Nav-status 7; trawling breaks CV like a thermalling glider |
| Tug | 8–13 kt | tight (harbour) | Nav-status 3; towing = combined motion with an unlit barge astern |
| Sailing / pleasure | 5–15 kt | **tacking = zigzag COG** | Often Class B (no nav-status); may drift with no propulsion |
| Anchored / moored | **0** | none | COG garbage; **swings on the anchor** (heading roams, position ~fixed) |
| Aid-to-navigation | 0 | none | MMSI `99…`; a fixed buoy, not a vessel — exclude from tracking |

Any gate, filter, or classifier must state which classes it covers. A plausibility check tuned for a
cargo ship steaming straight silently mishandles a trawler working, a sailboat tacking, and a buoy.

## 4. Observation geometry — surface targets live at the horizon

This is where the sea domain most differs from the air domain. An aircraft is *high* (large positive
elevation, the zenith keyhole is the hazard). A vessel is *on the surface* — its elevation is ≈ 0 and
goes **negative** with range as the Earth curves away. Design for the horizon, not the sky.

- **The horizon is the ceiling.** From an observer at height h_obs, the geometric horizon distance is
  d_hor ≈ 3.57·√h_obs km (h in m). Refraction extends it — standard optical ~×1.07 (≈ 3.83·√h), and
  **radio further, ~×1.15** (the 4/3-Earth model, d_radio ≈ 4.12·√h): radio bends *more* than light, so
  the radio horizon is the larger one. A 10 m coastal mast sees ~11 km geometric (~13 km by radio) to
  sea level; a 50 m hill ~25 km. Beyond that a ship is **hull-down** (only
  the superstructure clears the horizon) then fully hidden. AIS VHF range (~20–40 NM) routinely exceeds
  the *optical* horizon, so you will hold an AIS track for a vessel you cannot see.
- **Elevation is ≈ 0 to slightly negative — clamp, don't reject.** A sea-level target at range d from
  an observer of height h has geometric elevation el ≈ **−atan((h + d²/(2R_e))/d)** (R_e ≈ 6371 km) —
  **≤ 0 at every range**, because you always look *down* at the sea surface: a 10 m mast sees a 5 km
  ship at ≈ **−0.14°**, dipping further with range as the surface curves away. Pointing hardware should aim at el = **max(0,
  el)** (the horizon), not at a physically-correct negative angle that drives the tube into the sea-
  wall — the Python `_update_vessel_target` clamps el ≥ 0 for exactly this. But do NOT use that clamp
  to *reject* a vessel: a ship legitimately computes to el ≈ 0 or slightly negative and is still a
  valid target (unlike an aircraft, where a strongly-negative elevation means bad altitude data).
- **Refraction and multipath dominate at low elevation.** Atmospheric refraction lifts a horizon
  target by ~0.5° (34′) — the same order as the whole elevation budget here, and highly variable with
  temperature (ducting over cold water can bend the ray far past the geometric horizon). Sea-surface
  multipath smears the apparent elevation. Any sub-degree elevation claim near the horizon that ignores
  refraction is over-precise.
- **Slant range ≈ ground range.** A vessel is at sea level, so there is no altitude leg: slant ≈
  horizontal distance (contrast aircraft, where slant = √(ground² + alt²) and altitude dominates
  overhead). Range-vs-ground-range confusion that matters for aircraft is a non-issue for ships.
- **No zenith keyhole; the low-elevation band is the constraint instead.** Ships never pass overhead,
  so the alt-az azimuth-rate singularity never fires. Angular rates are gentle: ω ≈ v_perp/d — a 20 kt
  (10 m/s) ship at 5 km abeam is only ~0.11 °/s (trivial to follow); the same ship at 500 m in a
  harbour is ~1.1 °/s. The hard part is seeing through refraction/multipath and the earth's bulge, not
  slewing fast.
- **Bearing wraps, elevation barely moves.** As with any alt-az target, azimuth is circular (a
  westbound ship crossing due-north wraps 0/360); but unlike an aircraft, elevation stays pinned near
  the horizon for the whole pass, so an elevation servo is nearly idle while azimuth does the work.

## 5. Cross-checks before you trust a vessel model

- Does the code gate MMSI to the 9-digit, leading-`2..7` ship form before a MID/country lookup, and
  exclude `99…` aids-to-nav from tracking?
- Are position and static ages tracked **separately** (a fresh fix does not imply a fresh name)?
- Is a resting vessel's garbage COG kept out of the velocity/prediction model (use heading or hold)?
- Is nav-status treated as a hint, never as automation ground truth?
- Is the elevation **clamped to the horizon for pointing** but **not used to reject** the vessel?
- Is the geoid undulation applied so sea level sits at +N in the observer's HAE frame?
- Do the plausibility bounds (max SOG, max turn) admit the whole fleet — the tacking sailboat and the
  working trawler, not just a cargo ship in a straight line?
