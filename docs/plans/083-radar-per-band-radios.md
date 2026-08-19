# 083 — Radar: a radio per band, not three slots

## Decision

Every receiver row names the radio it uses. The three-slot model (observation / overlay / ais)
is demoted to two DEFAULTS behind a sparse per-row override map, and arbitration becomes
per-physical-radio so rows on different radios run at the same time.

## Why

Operator, 2026-08-19: *"what the fuck have you created with these radios overlays and
experiments? radio source should be configured per band"*. The complaint is correct and the
model is the bug.

`observation`, `overlay` and `experiment` are INTERNAL concepts — how the code groups rows —
and they leaked into the operator surface. A row never named a radio; it was silently grouped
into a slot by its `Kind`. The consequence was visible the same afternoon: the 137 MHz dipole
moved to the local RSP1a, the overlay slot was pointed there so satellite passes would use it,
and FT8-20 — an "experiment", therefore "overlay" — started listening to 20 m through a VHF
dipole. Nothing was misconfigured; the model simply cannot express what the operator meant.

The station now has two radios and more antennas than radios. The unit of assignment the
operator thinks in is the BAND (the row), and that is what the UI must offer.

## Architecture

- **Assignment.** A sparse `rowName -> sourceName` map beside the existing source directory in
  `state-dir/radio_sources.json`. ABSENT means "inherit my kind's default", stored as absence,
  never as a value — so a band added by config later (an FT8 dial, a new NDB) resolves sensibly
  with no operator edit, and a later default change still moves it.
- **Defaults.** The two slots survive, renamed in the UI to "default radio for observation" and
  "…for experiments". They remain what `radar.engine.sdr-device` / `overlay-device` seed.
- **Radio identity.** One arbiter per PHYSICAL radio, keyed by a normalized id: for `rsptcp://`
  it is `host:port` with the default-port rule and **`?ant` dropped**. This is load-bearing —
  the live state file already holds `pi4-A` and `pi4-C`, two names for one single-client box.
  Keying on the raw URL would permit two concurrent claims on one server and leave the loser in
  a permanent reconnect spin.
- **Arbitration per radio.** Rows on different radios open windows concurrently; rows sharing a
  radio contend exactly as today. The satellite recorder's priority preemption applies to its
  own radio only. `captureOnBaseRadio` generalizes to "freeze the bus at begin", so a window
  finishes on the radio it started on however the assignment changes underneath.
- **Exclusivity per radio.** `ReceiverControl.groupOf` keys on the radio id instead of `Kind`.
  This SUBSUMES today's behaviour: one radio gives one group (the current merged selection),
  two radios give the current split. A regroup that collapses two armed rows onto one radio
  keeps the most recently armed and switches the rest off, deterministically.
- **UI.** The picker goes on the row, in the Receivers panel where the rows already are, and is
  hidden entirely while only one radio exists. The Settings block keeps the directory
  (add / test / delete) and the two defaults.

## Migration strategy

1. **PR1 — radio identity + bus registry.** `RadioId` normalization, `RadioBuses` (id ->
   arbiter, session -> bus, reap on stop); the arbiter learns "is the base radio mine" from its
   own bus rather than a global boolean. One radio configured = byte-identical behaviour.
2. **PR2 — per-row assignment: model, persistence, API, picker.** Still one arbiter, so
   contention is unchanged and the UI says so plainly rather than implying concurrency that has
   not landed.
3. **PR3 — per-radio arbitration and per-radio exclusivity.** The risky one: overlay ports
   resolve their bus at claim time, `BaseObservation` projects onto the observation bus, no path
   may hold two bus locks. ADS-B and AIS stay pinned to one radio, refused loudly.
4. **PR4 — UI truth-up.** An explicit selected row for the detail pane (two radios can have two
   armed experiments), conditional panel copy, and `SdrOpens` carrying the device so "recent
   tunes" says WHICH radio tuned.
5. **PR5 — split the base rows.** ADS-B and AIS become independent per-bus sessions; the
   AIR/SEA band concept collapses to one band per base bus.
6. **PR6 — vocabulary cleanup (optional).** Persisted `slots` becomes `defaults`, with the old
   reader kept forever.

## Risks

- **Two names, one box** (live today): mitigated only by the `?ant`-dropping identity. Symptom
  if wrong is a permanent reconnect spin, not a crash. Tested first.
- **The no-reset rule** ([[settings-persist-always]]): the design writes NOTHING at boot —
  absence means inherit, so the current file resolves every row exactly as it does today. A
  first-boot expansion into explicit per-row entries was considered and rejected: it would
  freeze today's resolution, be unrecoverable without hand-editing JSON on the appliance, and
  fall into the trap that `overlay:"local"` does not mean the local radio — on this box it
  resolves through the fallback to the REMOTE pi4.
- **Mid-window reassignment**, **lock order across N buses**, **panel/reality divergence on
  regroup**: each pinned by tests before the behaviour lands.
- **Host limits**: two concurrent captures (6 Msps ADS-B plus a sonde window) is a USB/CPU
  question the code has never had to answer; the per-radio rate check becomes per row and stays
  loud.
- **Out of scope, stated to the operator:** gain and notch settings are per RF band and GLOBAL,
  not per radio. With two radios and different antennas running at once, one gain table drives
  both. Follow-up arc; see `radar/docs/GAIN-SURVEY-2026-08.md` for what a per-chain split needs.

## Status

DRAFT 2026-08-19. Supersedes the slot model introduced with the remote-IQ arc (079).
