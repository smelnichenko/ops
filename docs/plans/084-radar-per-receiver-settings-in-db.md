# 084 — Radar: a receiver owns its radio, gain and notch — in the database

## Decision

A receiver row is the unit of configuration. Each one carries its own **radio**, **gain** and
**notch**, each stored as an OVERRIDE over the frequency-band default, with an explicit
per-receiver **reset to defaults**. All of it moves out of `state-dir/*.json` and into Postgres.

## Why

Operator, 2026-08-20: *"Receivers page shows list of radio consumers. each consumer like AIS
should be connected to radio, gain and notch"*, *"save settings to the DB!"*, and on inheritance:
*"frequency-band default, and there should be a reset to defaults button for each consumer"*.

The model is inconsistent today, and each inconsistency has already cost something:

- **radio** IS per receiver (083's assignment map) — the right shape.
- **gain** is per FREQUENCY BAND (`VHF marine`, `HF`, …). Two receivers sharing a band silently
  share gain. AIS at 162 and DSC at 156.5 are one band and cannot be tuned apart.
- **notch** is GLOBAL — a single `rf`/`dab` pair for the whole app. Setting a notch for one
  receiver sets it for every receiver on every radio. On 2026-08-19 a stored global `rf=on
  dab=on` cost 9.8 dB at 137.9 and 22 dB at 162 for every band at once, and the 137 MHz hunt
  spent a day inside that.

And the file-based persistence is itself a proven hazard. On 2026-08-20 an EMPTY `gains.json` —
`{"ifgr":{},"rfgr":{}}`, written the first time anything saved with nothing set — was a VALID
file, so restore reset the policy and applied nothing, destroying the entire shipped calibration
on every boot including the measured L-band ADS-B numbers. `radio_sources.json` had already lost
every LOCAL radio on every restart for the same class of reason (the writer knew about them, the
reader did not). Four separate JSON files, four hand-rolled readers, four chances to disagree.

## Architecture

- **One table, one row per receiver setting.** `receiver_setting(receiver, key, value)` with a
  unique `(receiver, key)`, rather than a wide table — receivers are added by config (a new FT8
  dial, a new NDB frequency) and must not need a migration each time.
- **Override, never a copy.** An absent row means "inherit the frequency-band default", stored as
  ABSENCE. This is 083's rule and the same reason applies: a band whose default changes later
  must move with it, and a receiver added by config must resolve sensibly with no operator edit.
  **Reset to defaults deletes the rows** — it must not write the current defaults as values.
- **Resolution order** for gain and notch, both per receiver: explicit receiver override →
  frequency-band default (`sdr-ifgr-bands`, `SdrNotchPolicy`'s below-30 MHz rule) → global default.
- **No migration — CORRECTED 2026-08-21, during PR 1.** The plan originally called for importing
  `state-dir/*.json` into the table on boot. That is wrong, and building it made the reason plain:
  `gains.json` is keyed by frequency BAND and `notches.json` is GLOBAL, so expanding either into
  per-receiver rows hands EVERY receiver an explicit override — the precise opposite of what this
  table is for. It would also freeze today's values, so a later re-baseline of a band would move
  nothing. The band table stays the band-default layer, the global notch stays the global layer,
  and the per-receiver layer starts EMPTY: every receiver resolves exactly as it does today until
  an operator overrides one, and the operator's live calibration survives untouched because it was
  never per-receiver in the first place.

## Migration strategy

1. **PR 1 — the table and the store.** DONE, radar #638. `receiver_setting` on the runOnChange
   baseline; a `ReceiverSettingStore` where absence IS the inheritance and reset DELETES rows. No
   JSON import, for the reason above. Nine integration tests against a real Postgres.
2. **PR 2 — gain per receiver.** DONE, split in two because the first half was inert on its own:
   **#639** added the resolution layer (receiver → band → global), **#641** carried the receiver's
   identity all the way to the hardware. The split matters: a setting that does not reach the radio
   is cosmetic, and #639 alone was exactly that. Resolved AT THE OPEN, not where the gain string is
   built — a rotating receiver retunes without rebuilding its gain, so a value baked in at build
   time is the wrong band's the moment it moves.
3. **PR 3 — notch per receiver.** DONE, radar #642. `auto` is still not `on` (NAVTEX at 518 kHz
   sits INSIDE the MW stopband), and an explicit `on` still beats the 30 MHz ceiling. Asserted on
   the BITMASK the box was sent.
4. **PR 4 — the Receivers page.** DONE across **#643** (endpoints, `inherited_*` vs the row's own
   vs `overridden`), **#651** (a collapsed `<details>` per row — 24 rows × 5 controls was a wall),
   **#652** (inline beside the radio picker, opening as a popover so a row does not shift the rows
   below it) and **#653** (rotating receivers report a live dial, so VOR/RTTY/WFAX/HFDL stopped
   silently having no controls at all).
5. **PR 5 — per-band settings.** NOT IN THE ORIGINAL PLAN, added from the operator 2026-08-21:
   *"several freq ranges means several collections of settings for rotating band (consumer)"*.
   DONE, radar #656: the key became `(receiver, band, key)`. RTTY runs DDH47 on 147.3 kHz LW and
   three HF outlets, and the right gain at 147 kHz is not the right gain at 7.6 MHz — one override
   per receiver was a single answer to two different questions. Reset is band-scoped; a setting
   with no band is refused rather than stored under `""`.
6. **Retiring `gains.json` / `notches.json` — OPEN, and its premise changed.** The plan assumed the
   table would make them redundant. It does not: they are the BAND-DEFAULT layer, which the
   per-receiver layer sits *over*. Retiring them now would mean moving band defaults into the
   database too — a separate decision with its own migration, not a tidy-up. Left alone
   deliberately.

## Outcome

Every receiver on the panel carries its own radio, gain and notch, per band, stored in Postgres,
with a reset that deletes rather than freezes. Two plan steps were wrong and were corrected in
flight — the JSON import (would have destroyed the inheritance it was meant to preserve) and the
assumption that one setting per receiver was enough (wrong for anything that rotates).
