---
name: aviation
description: Aeronautics domain knowledge for code that models aircraft — flight kinematics envelopes, ADS-B/Mode-S field semantics (GS vs airspeed, track vs heading, baro vs geometric altitude, TC19 subtypes), vehicle classes (airliner/GA/helicopter/glider/UAV) and their wildly different motion, observation geometry for tracking, and aerial-vehicle design basics. Read BEFORE designing or reviewing trajectory prediction, ADS-B decoding/interpretation, flight-envelope constants, plausibility gates, aircraft classification, or aerial-vehicle design — and whenever a model implicitly assumes "aircraft = airliner in cruise".
---

# Aviation domain discipline

Working rules for code that models aircraft. The recurring failure is not bad math but a wrong
domain model: assuming every target is an airliner in steady cruise, or trusting a field to mean
what its name suggests. Check the assumption, then the numbers.

## 1. Kinematics envelopes — plausibility bounds you can compute

Aircraft motion is bounded by physics you can derive, not guess:
- **Turn rate** ω = g·tan(φ)/v (bank φ, TAS v). Airliner at 250 m/s, 25° bank → **~1°/s**.
  GA standard rate = **3°/s** (2-min circle). Glider thermalling at 45°/50 kt → **~20°/s**.
  A "400 kt target turning 10°/s" implies 7 g — transport aircraft are certified to +2.5 g:
  that's a data or model bug, not a maneuver.
- **Turn radius** r = v²/(g·tan φ): 250 kt at 25° → ~3.6 km. Course changes are arcs km wide,
  not corners.
- **Longitudinal acceleration** is small: ~0.5–1.5 m/s² in flight, ~2 m/s² takeoff roll.
  Speed is the *most* constant state an aircraft has — the user-observed "planes move at
  near-constant speed short-term" is real physics, and CV-model process noise should reflect
  per-axis reality: gentle along-track, up to ~0.6 g cross-track in a 30° bank turn.
- **CV-model error in a turn** ≈ ½·v·ω·t² cross-track: airliner (1°/s) 5 s ahead → ~28 m (fine);
  thermalling glider (20°/s) 5 s → ~550 m (CV is useless — cap extrapolation or detect turning).
- **Vertical**: climb 2000–3000 fpm initial, 500–1000 high-altitude; descent ~1500–2500 fpm
  (a 3° glideslope at 140 kt ≈ 750 fpm). Sustained ±6000+ fpm on a transport = suspect data.

## 2. Field semantics — aviation data means less than its name says

- **Ground speed ≠ airspeed**: jetstream winds exceed 100 kt; GS can differ from TAS by that
  much. ADS-B TC19 subtypes 1–2 broadcast the **ground-speed vector** (E/N integer knots);
  subtypes 3–4 broadcast **airspeed + magnetic heading** instead (no GNSS velocity) — treating
  ST3/4 as a ground vector injects the full wind as error.
- **Track ≠ heading**: track is motion over ground, heading is where the nose points; crab in a
  crosswind reaches ~20°. Pointing/prediction wants track; ST3/4 gives heading.
- **Barometric ≠ geometric altitude**: baro is pressure altitude vs 1013.25 hPa (flight levels),
  offset from true altitude by QNH + ISA temperature deviation — routinely **hundreds of feet**,
  worse in winter. Point a telescope with **geometric (GNSS) altitude** (TC20–22 / `alt_geom`);
  accept baro only as fallback. Baro-derived vertical rate is lagged and noisy.
- **Units are imperial by treaty**: kt, ft, fpm, NM, flight levels = ft/100. Convert once at the
  boundary (kt→m/s ×0.514444; fpm→m/s ×0.00508; ft→m ×0.3048) and verify numerically.
- **Three altitude datums, one geoid between them**: pressure altitude (baro, flight levels),
  orthometric/MSL (maps, airports, humans), and WGS-84 ellipsoidal HAE (GNSS, geodetic math).
  ADS-B geometric altitude is HAE; a config-entered site altitude is usually MSL. The geoid
  undulation N = HAE − MSL varies −100…+85 m globally (≈ +18 m in Estonia) — mixing an MSL
  observer with HAE targets tilts every elevation by N/range (~0.2° at 5 km). Reconcile ONCE at
  the boundary and say which datum each stored altitude uses.
- **Quantization = your measurement noise floor**: baro alt 25 ft (Q-bit) else 100 ft; TC19
  velocity components 1 kt LSB; vertical rate 64 fpm LSB; CPR position ~5 m. Channel noise
  models below these values claim more than the encoding carries.
- **Message cadences differ per type**: airborne position ~2 Hz, velocity ~2 Hz, identification
  ~0.2 Hz — and they fade independently with SNR. Never assume "track alive" implies "field X
  fresh"; every metric needs its own age.
- **Identity**: the ICAO 24-bit address is the stable key; callsign is per-flight and mutable;
  registration is per-airframe. Mode-S-only targets (no ES) have NO position — presence without
  coordinates is normal, not corruption.

## 3. Vehicle classes — "aircraft" is not one motion model

| Class | Speed | Turn | Vertical | Traps |
|---|---|---|---|---|
| Airliner | 250–500 kt TAS, 120–160 kt approach | ~1°/s cruise | 500–3000 fpm | Predictable; procedures below FL100 (250 kt limit) |
| GA piston | 60–140 kt | up to 3°/s | ≤1000 fpm | Pattern work near fields: continuous turns |
| Helicopter | **0**–150 kt | arbitrary | ±2000 fpm, vertical | Hover: GS≈0, track undefined/garbage; can fly backwards |
| Glider | 45–90 kt | **15–20°/s** thermalling | −200 fpm to +1000 (lift) | Sustained circling breaks CV; often no transponder |
| Multirotor UAV | 0–40 kt | instant yaw ≠ track change | ±1000 fpm | All bets off; heading decoupled from motion |
| Balloon | wind speed | none | ±500 fpm | Track = wind vector; GS near zero aloft is normal |

Any gate, filter tuning, or classifier must state which classes it covers. A plausibility check
tuned for airliners silently discards helicopters at hover and gliders in thermals.

## 4. Observation geometry for ground-based tracking

- **Angular rate peaks at closest approach**: ω_max ≈ v/d — an airliner at 3 km abeam does
  ~2.5°/s; the same plane at 30 km does 0.25°/s. Actuator ceilings translate to a minimum
  trackable abeam distance d_min ≈ v/ω_actuator.
- **The keyhole**: near zenith, azimuth rate → ∞ for finite crossing speed; alt-az mounts cannot
  follow through overhead passes. Design for it (gimbal limits, target handoff), don't fight it.
- **Radio horizon** bounds reception: d_NM ≈ 1.23·(√h_rx_ft + √h_tx_ft) — a ground antenna vs
  FL350 traffic gives ~230 NM (~430 km); low traffic disappears at tens of km. Range rings and
  map extents should follow from this, not taste.
- **Slant range ≠ ground range**; elevation angle compresses everything near the horizon, where
  refraction (~0.1–0.5°) and multipath also live. Expect the worst data at el < 5°.

## 5. Aerial-vehicle design sanity (for design work and classifiers)

- Lift L = ½·ρ·v²·S·C_L: stall speed v_s = √(2W/(ρ·S·C_Lmax)) — wing loading sets the low-speed
  envelope; approach speed ≈ 1.3·v_s. Small UAVs live at low Reynolds numbers: airfoil data from
  full-scale doesn't transfer.
- Induced drag ∝ 1/(π·AR·e)·C_L²: endurance aircraft (gliders, HALE UAVs) have high aspect
  ratios; fast ones don't. Shape correlates with mission — usable for classification priors.
- Rotorcraft hover power ∝ √(disk loading): multirotors trade endurance for control authority;
  a "drone" loitering for hours at a point is more likely a fixed-wing type or a balloon.
- Density altitude: performance degrades with altitude/heat (ρ in every formula above); service
  ceilings and hot-day performance are ρ-effects, not arbitrary limits.

## 6. Review workflow

State the vehicle classes and flight phases in scope → check every envelope constant against §1/§3
(derive, don't vibe) → trace each consumed field to its transmitted semantic (§2 — subtype, source
bit, quantization) → test the model against the hostile classes (hovering helicopter, thermalling
glider, ST3/4 emitter, Mode-S-only) → check the geometry limits (§4) are designed for, not
discovered in the field. Verify numerically with the repo venv; a computed bound outranks a
remembered one.
