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
| 6 | DSC | **DONE radar #1062** — DSCsnoop's reading of four Kiwi captures and twelve M.493-crafted calls, field by field | VHF physical layer (DSCsnoop is MF/HF only) |
| 7 | RTTY / WFAX / VOR | RTTY real air vs DWD text; WFAX line rate only; VOR nothing | a WFAX reference image; any real VOR (above 30 MHz: station recorder) |
| 8 | DCF77 / MSF / NDB | time signals decode real air against the broadcast time | an NDB ident decode; `OfflineCaptureSmokeTest` superseded, not fixed |
| 9 | AIVDM | **DONE radar #1056** — AIS-catcher's full reading of 34 sentences (real air + M.1371-crafted) | — |
| 10 | DMR RF | FEC/LC against MMDVMHost and ETSI | the symbol↔dibit mapping awaits real 70 cm |
| 11 | WSPR demod | **DONE radar #1061** — wsprd's reading of both Kiwi captures, per-station SNR/dt/frequency/drift; **types 2/3 DONE #1066** — 116 payloads, wsprd's readings | three 7040 kHz misses |
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

**Item 11 DONE (radar #1061):** wsprd (run, never vendored; `tools/wspr-xcheck`) reads each Kiwi capture —
resampled to 12000 S/s, cut to ±1400 Hz (else the real part folds an image onto the band: wsprd read
10140 kHz 3 dB low and missed IW2DWN), moved to 1500 Hz audio. Every type-1 station agrees on frequency,
drift, dt and SNR; exceptions named. Found: SNR 11-22 dB low on the crowded 7040 kHz capture (noise was the
band's median, which there is a station) — now the floor across ±160 Hz; the candidate search had the
same median (14 candidates a pass for 25 stations); WsprDemod's 63-tap filter sloped 1.8 dB inside the
band and let 265 Hz fold in at -24 dB — now a flat 657-tap Blackman. Ratchet 7040 margin 83 -> 85.


**Item 6 DONE (radar #1062):** PA2OHH's DSCsnoop (run unmodified and headless; `tools/dsc-xcheck`) reads the
real-air captures (one call each on three, none on 2187.5 kHz — the same three we accept) and twelve calls
crafted from M.493 and sent by our keyer: distress in two quadrants and unknown, all-ships, individual with
frequencies (incl. 10 Hz extended), group, area, acknowledgement, relay, position reply and request. Found:
the decoder read only the distress layout (second telecommand, frequencies, distress time/subsequent, an
ack's/relay's distressed ship, an area — read as an MMSI —, position replies all unread); relays were
"routine" and, once distress, the UI put the relaying coast station under the SOS; the test keyer sent
±42.5 Hz with inverted polarity (HF DSC is ±85 Hz, a 1 the lower tone). Crafted captures' SHA-256 pinned
ungated (ACARS too). Next: VOR, FLARM RF, APRS (the remaining own-keyer bands).

**WSPR types 2/3 DONE (radar #1066, 2026-09-29):** compound (type 2) and hashed (type 3) callsigns,
learned black-box from wsprd's OUTPUT only (payloads our encoder keyed, one to a WAV; wsprd's source
never read): 116 readings committed, regenerated byte for byte where WSPRD is set (local only; CI has
no wsprd). 7040 kHz real air now reads PA3EDR/G and two `<...>` stations as wsprd does (19 -> 22
decodes). Three test reviews: prefix/callsign space rules, the shortest type-1 call, two hashed
stations or identical twins are two decodes (payload AND place, not text), the station's delivery,
and the HF logs keyed by row id (a `<...>` row click opened another station). Next: the 7040 misses.

**7040 kHz misses (radar #1067, 2026-09-30):** PE1AHJ/M0GUC (0.8 Hz apart, one candidate) read by
a second, time-distinct start per candidate; a payload that unpacks to nothing is no decode and is
never subtracted (it had erased PA1JCK; synthetic test, 5 scenes). 22 -> 24; the ratchet now records
each WSPR fixture's fanoCalls (lower is better): the extra start costs 10140 kHz 80 -> 93 calls.
M1LCR stays missed: never a candidate beside the M0LHP/DK3BI pair's subtraction residue.

**ADS-B 2 MS/s (radar #1068):** each sample repeated to six a bit before slicing: 106 -> 125 of
readsb's 129. I/Q interpolation (127 clean) lost weak frames under noise; a seed-by-seed paired
check against the two-a-bit slicer, not a floor, is what tells them apart. Next: APRS vs direwolf.

**APRS DONE (radar #1069, 2026-09-30):** direwolf run black-box (`tools/aprs-xcheck`) reads a
54-packet corpus keyed by OUR keyer: it hears every packet; our demod recovers the same frames
(addresses included); the parser matches its positions to 1e-5 deg except 18 named packets where
direwolf is lenient (ambiguity as zeros, beyond +-90/+-180, misaligned object/item names, unmarked
object, table outside the spec, no symbol code) and Mic-E. Objects/items now parsed — and review
found every position was filed under the SENDER (a digipeater moved 16.8 deg to its repeater
object): objects are rows of their own now, killed ones leave. Remaining own-keyer bands: VOR,
FLARM RF (need real captures); CommB, Morse.

**Comm-B DONE (radar #1072, 2026-09-30):** DF20/DF21 replies packed from ICAO Doc 9871 (plus two real-air
replies from J. Sun's "The 1090 MHz Riddle", of another aircraft) read by readsb black-box through its raw
port: our fields match every 5,0/6,0 readsb reads; our register inference (against the aircraft's own ADS-B,
exactly one register fitting) is readsb's but for ten named, deliberate differences. Review found the
station's own Comm-B rule (ambiguity guard, 30 s staleness, 15 s pairing, one sample per pair) reached by NO
test — pinned by AdsbReceiverCommBTest (29/30 mutants, one equivalent). `task gate` now sets READSB,
WSPRD, DIREWOLF, ACARSDEC and DSCSNOOP where installed: every oracle's byte-for-byte check runs at every
gate (first run: all seven classes ran, none skipped). Remaining: VOR and FLARM RF (need real captures), Morse.

**Morse DONE (radar #1074, 2026-09-30):** multimon-ng's MORSE_CW, run black-box
(`tools/morse-xcheck`), told each recording's dit length, reads an 11-message corpus keyed by OUR keyer
(pangrams, digits, E/T, VOR idents at 7 wpm, 5-25 wpm, up to 20% jitter) exactly as sent; ours, given
the same durations, reads what it read, except a lone element (no unit to measure against: T reads E).
Measured limits: multimon-ng misreads above 30 wpm or at 30% jitter; ours holds 5-40 wpm at 30%
(now pinned in MorseDecoderTest). Review found the gating broken for EIGHT oracles: `task gate` sets
an absent program's variable empty, and `Files.isExecutable(Path.of(""))` is true, so on a host without
the program they failed instead of skipping (`OracleProgram.named` now); and AIS_CATCHER and
DUMPHFDL_RUN were never set by the gate, so the AIVDM, ship-type and HFDL real-air checks had skipped
at every gate.

**Morse mark bias FIXED (radar #1076, 2026-09-30):** ours broke past 0.34 dit of mark bias (a threshold
lengthens marks, shortens spaces) where multimon-ng reads -0.40..+0.50. Five biased rows joined the corpus
(multimon-ng reads them exactly); the unit and the bias are now fitted together (log cost), believed only
when clearly better than none. Paired vs the old decoder, 17000 runs: 3694 better, 25 worse (30% jitter,
|b| .15-.25), none worse without bias. VorDemod's own keying measured -0.01..-0.04 dit: inert there today.

