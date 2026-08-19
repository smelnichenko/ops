# 082 — Radar: decoder oracle fixtures ("music unit tests for all bands")

## Decision

Give every signal decoder the test discipline the FT4 arc proved out: committed WAV/IQ/vector
fixtures produced by an INDEPENDENT reference implementation (or real air), decoded in CI, with
the oracle named — so a wrong port can no longer pass its own tests. Standing user ask
(2026-08-17): "we need such music unit tests for all bands".

## Why

The 2026-08-19 audit found 6 decoders on independent ground and ~18 testing only against
themselves. The FT4/FT8 late-open defect class showed exactly why self-referential suites are
blind: encoder and decoder share every transcription error.

Solid today: FT8 + FT4 (ft8_lib WAVs), WSPR code layer (rtlsdr-wsprd golden symbols), DMR FEC
(MMDVMHost vectors), LRPT (real-air CADUs + satdump), AIS demod (real-air burst), GPS C/A
(IS-GPS-200 spec vectors).

## The gaps, ranked (a wrong port passes its own tests)

1. **FLARM** — fully closed loop: own XXTEA encoder feeds own demod/decoder; creaktive/flare and
   SoftRF cited, never executed. A wrong key schedule is invisible.
2. **HFDL** — 23 transcribed files; CI decodes our own `HfdlBurstEncoder`; `HfdlOracleTest`
   skips without `DUMPHFDL_BIN` and runs the wrong direction (dumphfdl reading our encoder);
   the "proven by transitivity" claim fails on shared transcription errors.
3. **RS41** — self-declared air-unverified; interleave from rs41mod.c never cross-checked by
   running rs41mod.
4. **ACARS** — acarsdec layout transcribed, never run.
5. **Mode-S/ADS-B** — the app's PRIMARY signal: `modes-golden.frames` is frozen output of a
   deleted own demod ("it is the reference now"); no real-air fixture exists.
6. **DSC VHF+HF** — maritime distress, both sides spec-built via one shared `DscWire`.
7. **RTTY / WFAX / VOR** — zero external grounding of any kind.
8. **DCF77 / MSF / NDB** — `OfflineCaptureSmokeTest` hooks exist (`$DCF77_CAPTURE` …) but no
   capture is committed: permanently skipped.
9. **AIVDM decode layer** — golden JSON from the author's own retired Python.
10. **DMR RF layer** — FEC oracle-proven, absolute symbol↔dibit mapping unproven.

Also: WSPR demod (IQ synthesized from own `WsprCode`; `wsprd_pipe` A/B gated on a retired local
binary), and a stale reference — `LrptLoopbackTest` cites a `LrptSatdumpOracleTest` that does
not exist.

## Architecture

Per decoder, ONE of three fixture sources, committed small and named in the test: (a) a
reference ENCODER generating known-content signal (ft8_lib pattern — best when a maintained
encoder exists); (b) a reference DECODER run at fixture-generation time over our captures with
its output committed as the expected truth (dumphfdl, acarsdec, dump1090-fa `--ifile`,
multimon-ng, fldigi, rs41mod pattern); (c) real-air captures with independently-verifiable
content (the AIS burst pattern; time signals verify against the broadcast time itself). Checkouts
of reference tools go to `/home/sm/src/<name>` per house rule; generation scripts live beside
the fixtures like `tools/dmr-xcheck`.

## Migration strategy

One small PR per decoder, worst-first: **1 FLARM · 2 HFDL (fix the oracle DIRECTION: dumphfdl
decodes a committed capture, our receiver must match) · 3 Mode-S (real-air capture + readsb
`--ifile` golden) · 4 ACARS · 5 RS41 · 6 DSC · 7 AIVDM (independent decoder cross-check) ·
8 time signals + NDB (commit the `OfflineCaptureSmokeTest` captures) · 9 RTTY/WFAX/VOR ·
10 WSPR demod end-to-end WAV · 11 DMR RF once real 70 cm capture exists**. Each PR: fixture(s) +
generation recipe + positive/negative tests; delete the stale `LrptSatdumpOracleTest` reference
in the first touched PR.

## Risks

Reference tools drift or die (pin exact checkouts in comments, commit their OUTPUT not their
runtime); fixture size bloat (seconds of signal, not minutes — FT4's 360 KB WAVs are the
budget); real-air captures for silent bands wait on reception (RRTY outlets, DMR 70 cm) — those
PRs take fixtures from whatever the antenna DOES hear first.

## Status

DRAFT 2026-08-19 — audit complete, execution not started; follows the 081 arc.
