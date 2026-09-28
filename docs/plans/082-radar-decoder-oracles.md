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

**Re-audited 2026-09-28** (radar main 050713ee). Much moved without this plan being worked from:

| # | item | grounding now | still missing |
|---|---|---|---|
| 1 | FLARM | packet layer against a compiled `flare` (docs/094, 3000 packets) | RF layer: our GFSK keyer into our demod; no real-air or reference IQ |
| 2 | HFDL | **DONE radar #1059** — dumphfdl 1.7.0's whole reading of three Kiwi captures, frames paired in order, contacts compared | — (`HfdlOracleTest`, dumphfdl reading our encoder, stays as the encoder's check) |
| 3 | Mode-S / ADS-B | **DONE radar #1055** (below) | a real 6 MS/s cs16 capture through the station's own `IqStreams` |
| 4 | ACARS | **DONE radar #1060** — acarsdec 3.7's whole reading of the real-air capture, and of crafted blocks our modulator sends, field by field | — |
| 5 | RS41 | real air + rs41mod output (burst, PTU, XDATA) | — |
| 6 | DSC | HF real air (two calls) | a reference decoder's output; VHF physical layer still our own keyer |
| 7 | RTTY / WFAX / VOR | RTTY real air vs DWD text; WFAX line rate only; VOR nothing | a WFAX reference image; any real VOR (above 30 MHz: station recorder) |
| 8 | DCF77 / MSF / NDB | time signals decode real air against the broadcast time | an NDB ident decode; `OfflineCaptureSmokeTest` superseded, not fixed |
| 9 | AIVDM | **DONE radar #1056** — AIS-catcher's full reading of 34 sentences (real air + M.1371-crafted) | — |
| 10 | DMR RF | FEC/LC against MMDVMHost and ETSI | the symbol↔dibit mapping awaits real 70 cm |
| 11 | WSPR demod | real air, four stations | wsprd output committed |
| — | AIS identity | **DONE**: flags #1057 against the ITU's MID table (found Panama 374 missing); ship types #1058 against AIS-catcher's text for all 256 codes (placed the newer 1-19/38/39) | — |
| — | APRS, CommB, Morse | own keyers | not in the original list |

**Item 3 DONE (radar #1055, 2026-09-28):** readsb (run, never vendored; `tools/modes-xcheck`) reads the
real-air vector (dump1090's modes1.bin, resampled exactly to 2.4 MS/s): 129 DF17 frames of 4d2023/AMC421
with every field, committed as truth, plus crafted frames for the signs and "no information" values the
vector never shows. The decoder matches readsb on every field; the demod finds 128 of 129 at 6 MS/s
through the station's own pump (106 at 2 MS/s), with a cap on candidates offered. `modes-golden.frames`
(frozen own output) deleted; the stale `LrptSatdumpOracleTest` reference struck. Found on the way: the pump
lost every frame straddling two 256 KB IQ reads — fixed.

**Item 9 DONE (radar #1056):** AIS-catcher (run, never vendored; `tools/ais-xcheck`) reads a 34-sentence
corpus — the old golden's cases, the station's five real-air sentences, and M.1371-crafted cases for what
neither brought (southern/western hemispheres, types 2/3/19, msg 24B, every "not available", a coast
station's MMSI, a runt, fill bits) — and `AivdmOracleTest` holds every field to it; 25 reverts bite; with
`AIS_CATCHER` set the truth must regenerate byte for byte. **AIS identity, flags (radar #1057):** the
ITU's own MID allocation table; exact names, the listed flags pinned, 000-999 swept; found Panama's 374
missing and added the territory registers Madeira, Gibraltar, Greenland, Macao. **Ship types (radar
#1058):** AIS-catcher's text for every value 0-255 (M.1371-6's table) — the codes M.1371-5 left reserved
had all read "other"; trawler/fish factory/fish farm are fishing now, the 1-19 work vessels special. No
retired-Python golden is left in radar's identity layer.

**Item 2 DONE (radar #1059):** dumphfdl reads each committed Kiwi capture at its own rate
(`tools/hfdl-xcheck`); our FCS-valid frames must be its messages in time order, field by field (the
contact rows too), 224 WK018H named missed by place. Found: a logon resume's network PDU (flight,
position, time) after the ICAO address was never read — now read, for the resume only. Next: ACARS
(acarsdec's text and labels committed), WSPR (wsprd output), DSC (a reference decoder).

**Item 4 DONE (radar #1060):** acarsdec (run, never vendored; `tools/acars-xcheck`) reads the real-air
capture — its channel kept, envelope-detected, resampled exactly to 12500 S/s — and five messages from
four aircraft are committed with every field; blocks the air never carries (short downlinks, ETB both
ways, line breaks, padding) are crafted, sent by our modulator, and read by acarsdec too. Our receiver
says the same of every one, under three named policies (absent field null, one newline a break,
padding stripped). Found: a short downlink's sequence and flight were read past its ETX/ETB — a
fragment read as complete, an eight-character one lost both fields; ETB was never surfaced, and is
now marked "(more follows)" in the Receivers list and the plane panel. Next: WSPR (wsprd output —
wsprd reads 3 on 10140k where we read 4, 25 on 7040k where we read 19; types 2/3 not unpacked), DSC.
