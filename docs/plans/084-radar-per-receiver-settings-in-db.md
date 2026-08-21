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

1. **PR 1 — the table and the store.** DONE, radar #638. `receiver_setting(receiver, key, value)`
   on the runOnChange baseline; a `ReceiverSettingStore` where absence IS the inheritance and reset
   DELETES rows. No JSON import, for the reason above. Nine integration tests against a real
   Postgres, four mechanisms reverted and each caught.
2. **PR 2 — gain per receiver.** `SdrGainPolicy` gains a per-receiver layer over the band table;
   the open path passes the receiver name. Band defaults keep working untouched.
3. **PR 3 — notch per receiver.** Same shape. `SdrNotchPolicy`'s auto rule becomes the band
   default rather than the only answer.
4. **PR 4 — the Receivers page.** Each row shows and edits radio, gain, notch, with a reset that
   deletes overrides. View tests (jsdom + Testing Library), and the reset asserted to DELETE
   rather than write current values.
5. **PR 5 — retire the JSON.** Only once the table has been authoritative on the live station for
   a while, and only for the files fully migrated.

## Risks

- **Ordering at boot.** Gains are read by the first radio open. Today's log shows ADS-B opening at
  15:02:16 with the seed and AIS at 15:02:18 with the restored value — the store must be
  authoritative BEFORE any open, or the first session of every boot uses the wrong gain.
- **The DB is not always up.** The app must start and receive with Postgres unavailable; settings
  degrade to config defaults rather than the app failing to boot. Radar is a station, not a CRUD app.
- **Per-receiver notch multiplies opens.** Two receivers on one radio with different notches
  cannot run simultaneously — that is arbitration's problem (083) and must be stated, not
  discovered.
- **083 must land first.** It owns the per-receiver radio assignment this builds on.

## Verification

Per PR: `./gradlew clean check`, the `test-engineer` pass (revert each mechanism, record which
test failed), and `task test:mutation` on the touched classes. Arc close: the live station's
current calibration survives the migration byte-for-byte, and a reset returns a receiver to the
band default rather than to the bare global one.
