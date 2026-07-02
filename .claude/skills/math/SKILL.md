---
name: math
description: Mathematical rigor for control loops, estimation/filtering (Kalman), geometry/geodesy, signal processing, and numerical tuning. Read BEFORE designing or debugging anything with dynamics, filters, angles, units, or tuned constants — and when a control system "works in sim but not on hardware" or oscillates/lags/hunts. Encodes the derive→dimension-check→verify-numerically→model-the-plant→re-sweep discipline.
---

# Applied math discipline

Working method for math-heavy engineering (servo control, state estimation, geodesy, DSP,
coding theory). Every rule below was paid for on real hardware; skip one and you will
rediscover its price.

## 1. State the model, then derive by hand

Name the physical model and its assumptions before coding ("target moves at near-constant
velocity short-term" → CV Kalman; "CRC is linear" → syndrome tables). Write the update
equations / geometry on paper first — e.g. a direct velocity measurement is a scalar KF
update with H=[0,1]: `S = P11+R, K = [P01, P11]/S`, then transcribe. If you cannot derive
it, you cannot debug it. Cite where each equation came from in a comment only when the
code cannot show it.

## 2. Time consistency: predictions anchor to *now*

Any estimate used by a controller must be propagated to the moment it is used, not to the
last measurement. A prediction anchored at the fix time goes stale between measurements —
the trim term fights it, then lurches when the next fix lands (a sawtooth at the
measurement cadence is the signature). Carry the measurement age and predict
`(age + lead)` ahead. `lead` compensates actuator latency ONLY (see §7).

## 3. Fuse every measurement the system already gives you

If the sensor broadcasts a state directly (ADS-B TC19 broadcasts velocity), fuse it as a
measurement — do not force the filter to infer what it is being told outright. Direct
state measurements pin the estimate from message one instead of after N noisy updates,
and eliminate re-convergence cost when the filter resets (target switch).

## 4. Units and sign conventions: a table at the boundary

At every interface, write the conversions and conventions explicitly, then verify each
with a one-line numeric check before building on them:
- kt → m/s = ×0.514444 · fpm → m/s = ×0.00508 · ft → m = ×0.3048
- track° (clockwise from true north) → ENU: `ve = v·sin(track)`, `vn = v·cos(track)`
  (check: track 90° ⇒ due east ⇒ ve=v, vn=0)
- ADS-B vertical rate: positive = climb; ENU up is positive
- Angles live on a circle: NEVER subtract raw azimuths — wrap with
  `((b − a + 180) % 360) − 180`; for slew cost use the dominant axis
  `max(|Δaz_wrapped|, |Δel|)`.

## 5. Verify numerically, not by inspection

Settle every mathematical claim with a cheap experiment in the project venv before
arguing about it: Monte-Carlo the filter (does P stay symmetric/PSD? does v converge?),
exhaustively enumerate small discrete spaces (all C(112,2)=6216 syndromes — zero
collisions, checked, not assumed), fixed-seed A/B runs for any behavior change, and
`sha256`-compare refactored table builders against the originals. A 10-line script beats
an hour of code-reading confidence.

## 6. Model the plant honestly, tune against the model

Measure the actuator before tuning anything: command latency, acceleration ramp,
feedback quantization/sample-hold, rate ladder — with controlled experiments (fixed
command, long windows, both directions; short windows lie). Put every measured pathology
into the simulation model (e.g. "every command resets the acceleration ramp"), then tune
gains against the *realistic* model. A controller tuned on an ideal integrator will
oscillate or stall on hardware. When sim and hardware disagree, the sim's plant model is
missing a pathology — go measure, don't re-tune blind.

## 7. Coupled constants: re-sweep after fixing a mechanism

A constant tuned in the presence of a bug has absorbed the bug (a 0.8 s prediction lead
tuned with stale anchoring was really ~0.3 s of latency compensation plus ~0.5 s of
bug-cancellation). After any mechanism fix, re-sweep the constants that were tuned around
it — parameter sweeps with fixed seeds, tabulated max/mean/p90, at more than one
operating point (e.g. two measurement cadences).

## 8. Respect actuator command bandwidth (the Fourier rule)

Do not command a plant faster than it can respond. Sigma-delta dithering assumes the
actuator time-averages fast switching; an actuator that resets state per command
(acceleration ramp) turns dithering into a ~40× throttle. Quantize with
nearest-step + hysteresis (hold a command while the request stays inside a band), hold
steady commands, rate-limit re-commands, and stop immediately only for safety.

## 9. Filter hygiene

- Keep covariance symmetric and PSD; if update equations can drift P01≠P10, symmetrize.
- Guard reinit paths: a position-reset must not wipe a velocity learned from a direct
  measurement (track initialization per state component).
- Process noise from physics (plausible target acceleration, m/s²); measurement noise
  from the sensor spec (CPR quantization ~5 m, broadcast velocity ~1 kt) — not vibes.
- Decouple axes when the model is diagonal (3-D CV = three independent 1-D filters):
  simpler, testable, no numpy needed.
- Cap extrapolation: dead-reckoning an aging track must not run unbounded (stale-data
  cutoffs at the consumer).

## 10. Experiments and sweeps

A single seeded run is an anecdote. Comparative claims (A/B, tuning) need: multiple seeds with
dispersion reported (max/mean/p90 per seed, not one blended number); identical policies in both
arms — measuring arm A under a feeding/gating policy production never runs produced flattering
headline numbers here once; more than one operating point (two measurement cadences beat one);
and plateau-seeking over point-optima (a constant chosen off a one-seed peak is noise — prefer
the flat region; 0.3 was chosen from a 0.0-0.45 plateau, not a spike). When an "improvement"
scores worse, suspect a coupled constant or a plant-model gap before suspecting the math (§7).

## 11. Workflow

Assumptions → hand derivation → dimension/sign checks → implement → property tests
(convergence, invariants, exact known cases) → sweep/A-B on the realistic sim (fixed
seeds, tabulated) → adversarial review of the math (a verifier must re-derive, not
approve) → measure on hardware → record the measured constants and the *why* next to the
code. If a result surprises you (an "improvement" scoring worse), suspect a coupled
constant or a wrong plant model before suspecting the math.
