---
name: physics
description: Physical-world discipline for code that touches hardware or the environment — actuator/plant mechanics (inertia, ramps, backlash, dead-time), RF and antennas (wavelength sizing, link budgets, noise floors, front-end overload), SDR/sensor measurement physics (ADC bits, quantization, sample-and-hold, clock drift), optics and pointing (field of view, atmospheric refraction), and power/thermal limits. Read BEFORE designing or reviewing motor control, radio reception chains, telescope/camera pointing, sensor-noise models, or any tuning done against physical hardware — and whenever hardware behaves worse than the code's model predicts.
---

# Physics discipline

Working rules for code that meets the physical world. The recurring failure is a model that is
mathematically consistent but physically wrong — the hardware then "misbehaves" exactly as
physics predicts. Identify the mechanism first; every constant below is computable, not folklore.

## 1. Actuators are not integrators

A commanded rate is a *request* the plant approaches with its own dynamics:
- **Inertia + finite torque** → acceleration ramps (rate builds over ~seconds, not instantly).
  Measure the ramp with long fixed-command windows, both directions; short windows alias it.
- **Command handling is part of the plant**: firmware may reset its ramp, queue, or drop
  commands on every new one (measured here: re-commanding a mount every 0.3 s throttled it
  ~40× below its sustained rate). Command *bandwidth* is a plant constant — measure it like any
  other, and never command above it (dithering assumes the plant time-averages; a state-resetting
  plant does not).
- **Backlash, stiction, resonance**: reversals lose motion to gear lash; slow crawls stick-slip;
  structures ring near their natural frequency. Symptoms: hunting at reversal, limit cycles.
- **Feedback has physics too**: encoders/readouts quantize and sample-and-hold (a ~0.5 s-held
  position readout is a 0.25 s average lag), and serial links add dead-time. A controller tuned
  ignoring these oscillates on hardware and "works in sim" — put every measured pathology into
  the sim plant model, then tune.

## 2. Radio is geometry, wavelength, and noise

- **λ = c/f sizes everything**: 1090 MHz → λ = 27.5 cm; a quarter-wave monopole is **6.9 cm**.
  An antenna cut for another band receives fine *mechanically* and terribly *electrically*
  (a broadcast-FM whip at 1090 MHz cost this project a day). Check element lengths against λ/4
  or λ/2 before debugging software.
- **Link budget, not vibes**: FSPL(dB) = 20·log₁₀(d) + 20·log₁₀(f) − 147.55 (d in m, f in Hz);
  at 1090 MHz: ~92 dB at 1 km, +20 dB per decade. Received power = TX + gains − FSPL; compare
  against the noise floor kTB = **−174 dBm/Hz** + 10·log₁₀(BW) + receiver noise figure. Decode
  needs SNR above a threshold — compute the maximum range, don't guess it.
- **Front ends saturate**: more gain is not more signal. A strong nearby transmitter drives the
  LNA/mixer nonlinear (compression, intermodulation) and *reduces* decodes — measured here: max
  gain = 0 valid frames, mid gain = optimum. Sweep gain against a *decode-count* metric; expect
  an interior optimum. Dynamic range is a budget shared by the strongest and weakest signals.
- **Propagation is refracted geometry**: radio horizon uses the 4/3-earth model,
  d_km ≈ 4.12·(√h₁ + √h₂) (h in m). Below a few degrees elevation add multipath (ground
  reflections interfering) and deep fading — the worst data lives at the horizon, by physics.
- **Polarization and pattern**: a vertical monopole is omnidirectional in azimuth with a null
  overhead — the zenith null is an antenna fact, not a decoder bug.

## 3. Sensors and time

- **ADC bits set the noise floor**: SNR_max ≈ 6.02·N + 1.76 dB (8-bit ≈ 50 dB, 14-bit ≈ 86 dB).
  Bits beyond the analog noise buy nothing; bits below it clip weak signals into the quantization
  floor. Quantization behaves as uniform noise, σ = LSB/√12 — a *computable* measurement-noise
  term (use it in filters instead of a vibe).
- **Every reading has an epoch**: sample-and-hold, pipeline, and publish latencies stack into a
  systematic staleness that a tuned constant will silently absorb (then bite when something else
  changes). Carry timestamps or measured ages through the chain; anchor estimators at
  measurement time, not arrival time.
- **Clocks drift**: crystal oscillators are ~±20 ppm (≈ ±1.7 s/day) and temperature-sensitive; a
  Pi has no RTC at all. Never difference timestamps from two unsynchronized clocks; pick one
  monotonic clock per control loop and derive everything from it.

## 4. Light and atmosphere (pointing)

- **Field of view**: magnification = f_objective/f_eyepiece; true FOV = apparent FOV / mag.
  A tracking error budget must fit inside the FOV — a 1800 mm scope with a 1.5° TFOV eyepiece
  tolerates ~0.7° of pointing error before the target leaves the view.
- **Atmospheric refraction lifts everything near the horizon**: Bennett's formula
  R(arcmin) ≈ 1.02 / tan(h + 10.3/(h + 5.11)) (h = apparent elevation, deg): ~0.5° at h=1°,
  ~0.15° at 5°, <0.02° above 45°. Below ~5° elevation refraction is *the same order as the whole
  tracking error budget* — correct for it or state that you don't. It also varies with
  pressure/temperature (~±10%), so sub-0.05° pointing at the horizon is weather-limited.
- **Diffraction bounds resolution**: θ ≈ 1.22·λ/D — optics can't beat it, and neither can a
  "sharper" algorithm downstream.

## 5. Power and heat (embedded)

Silicon throttles before it breaks: an SBC at sustained load derates its clock (quietly changing
your control-loop timing); USB power budgets brown out peripherals (an SDR drawing its max on a
loaded bus resets mid-capture). Rule: measure the deployed thermal/power envelope once, then treat
sustained-load timing as a variable, not a constant.

## 6. Workflow

Name the physical mechanism before touching a constant → measure plant/channel constants with
controlled experiments (fixed input, long windows, both directions) → compute the expected
magnitude from first principles and compare with the observation (agreeing orders of magnitude =
right mechanism; disagreeing = wrong mechanism, stop tuning) → put every measured pathology into
the simulation model → only then tune, and record the measured constant with its experiment next
to the code. When software "can't fix it", check whether physics already forbids it (saturated
front end, sub-diffraction resolution, above-command-bandwidth control, sub-refraction pointing).
