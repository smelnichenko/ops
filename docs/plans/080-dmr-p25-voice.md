# 080 — DMR + APCO P25 digital voice listening

## Decision

Turn the radar app from a DMR *metadata* receiver into a digital-**voice** receiver for two
modes — **DMR** (AMBE+2 half-rate) and **APCO P25 Phase 1** (IMBE full-rate) — with **per-call
recorded audio clips** surfaced in the receiver UI and **trunk-following** for P25 systems whose
control and voice channels sit inside one captured span. Operator-locked at request time: full
voice (not metadata-only), per-call clips (no live streaming for v1), trunking-aware.

The existing DMR chain (`DmrDemod`/`DmrRxProcess`/`DmrReceiver` + `decode/dmr`) already recovers
Link-Control metadata; it deliberately never touched the voice payload. This arc reuses that
front end, adds a vocoder, a per-call session/clip model, a P25 decoder, and a wideband
multi-channel tap, in PR-sized steps that each stand alone.

## Why

- The metadata receiver proved the hard part — a Java 4FSK front end (NCO → decimate → FIR →
  FM discriminator → 4-level slicer at 4800 sym/s) with FEC verified against MMDVMHost. Voice is
  the same PHY plus a codec and framing; the incremental risk is bounded.
- P25 Phase 1 is **the same 4-level FM at 4800 sym/s** as DMR (C4FM, ±1800/±600 Hz vs DMR
  ±1944/±648 Hz, both exactly 3:1 outer:inner) — an amplitude-normalized slicer serves both, so
  one generalized front end covers both modes.
- The only pure-JVM decoder for both codecs already exists (JMBE), so the in-process-decoder
  doctrine survives without a native dependency or a from-scratch vocoder port.
- Trunk-following need not touch the radio at all: capture one 1–2.4 MHz span, run parallel
  per-channel chains off the same IQ, and a voice-grant just spins up a new chain at the granted
  offset — zero radio commands, zero grant latency.

## Architecture

**Front end (shared).** Generalize `DmrDemod`'s DSP into a mode-generic C4FM demod where a *mode*
is `{devOuter, devInner, syncTable, symbolFilter, framer}`. The existing slicer already
amplitude-normalizes (it tracks the eye scale from a MAD estimator, `DmrDemod.scale`, applied at
slice time) and already removes a static frequency offset (the slow discriminator DC-block,
`discDc`) — so the deviation difference and a constant LO offset are **already handled on a
continuous stream**; what is genuinely mode-specific is only the *initial* scale seed
(`scaleInit = 2π·devInner/procFs`, DMR-specific today → mode-derived).

The symbol filter is where the real subtlety lives, and the plan must not overstate it: `DmrDemod`
has **no RX matched filter today** — an anti-alias FIR + a ~6.5 kHz windowed-sinc channel low-pass,
then the FM discriminator, then a direct slice at symbol instants. So `symbolFilter` is
**passthrough for DMR (exactly today's behaviour — the proven, MMDVMHost-verified path is not
touched)** and P25's spec-intended one-symbol integrate-and-dump boxcar for P25. Adding an RRC
matched filter to DMR is explicitly **out of scope** here: it would change the eye and re-open the
one proven part of the system.

AFC beyond the existing `discDc` is a **fast/transient** re-centre seeded from the sync
soft-symbols, added to *compose with* (never a second DC-removal loop fighting) `discDc` — needed
because a burst that arrives already off-frequency must lock within the sync, faster than the slow
DC-block settles; a steady ~1 ppm UHF offset (~450–850 Hz, past P25's 600 Hz inner deviation) the
DC-block already subtracts on a continuous stream.

**Wideband tap.** An `IqTap.subscribe(centerHz) → decimated cs16 stream` fans one wide capture out
to N per-channel NCO chains (the shape `DmrRxProcess` already uses for parallel channels).
Measured cost: 0.51 % of one core per channel, N≤20 ≈ 10 % of one core — so the naive per-channel
NCO beats a polyphase channelizer well past N≈50 (sdrtrunk field reports its PFB using *more* CPU
than heterodyne mode). The tap interface lets a PFB slot in later if ever needed. **One IQ gap
from the remote link must broadcast a reset to every chain** (the stale-align frame-corruption
lesson) — gluing discontinuous IQ poisons all decoders at once.

**Voice codec.** JMBE (pure Java, GPLv3), built once from pinned tag **v1.0.9** and hosted in the
private Nexus (it has no Maven coordinates), wrapped behind an `AudioCodec` seam in a new
`decode/voice` package. Decodes IMBE 144-bit and AMBE+2 72-bit frames → 8 kHz 16-bit mono PCM.
No GPL *source* enters the repo (house rule intact); it is a build-time dependency of a private,
non-distributed appliance.

**Per-call model.** A new `CallSession` keyed by (mode, channel, DMR slot / P25 call) assembles
PCM by **sample-derived timestamps with silence-fill for lost frames** — never bare concatenation,
which drifts the clip. The existing `DmrReceiver` roster (keyed by srcId, newest-wins, 300 s
age-out) stays as the metadata card but cannot drive clips: two concurrent DMR slots would corrupt
one clip. Sessions close on call-end events (DMR terminator / P25 TDU, or idle timeout) and emit a
clip + a metadata row.

**Storage + serving.** Follows the `PhotoController` pattern: metadata rows in new **bounded
(pruned-history)** `dmr_call` / `p25_call` tables (`CREATE ... IF NOT EXISTS` appended to
`db/schema.sql`; `DmrCallEntity` + `DmrCallRepository.record()` native insert, mirroring
`WsprSpotEntity`/`WsprSpotRepository`; wired optionally via `ObjectProvider` like
`WsprReceiver.Log`) — "bounded", not "append-only", because the retention policy DELETEs old rows,
unlike the truly append-only WSPR precedent. Clip **bytes** as 8 kHz mono WAV in a node-local disk
cache (à la `PhotoProperties`), served by `GET /api/{mode}/clip/{id}` (where **`{id}` must parse as
the row's typed id — UUID/long — so the path variable cannot itself carry traversal**) streaming a
`FileSystemResource` behind the `PhotoController` resolve/normalize/startsWith path-traversal guard
(the stored path is writer-controlled, unlike the photo case's regex-on-path-variable). **8 kHz WAV**
(plays natively in browsers, ≈0.96 MB/min, ~160 kB per 10 s call); Opus (pure-Java Concentus
exists, but needs a hand-rolled Ogg writer) deferred until storage actually hurts. Clip retention
is a **purpose-built age/count/size policy keeping DB rows and files consistent** — not
`SatCaptureScheduler`'s keep-N inline prune (built for a handful of half-GB files, not thousands
of small clips) and not the photo pattern (no pruning at all).

**P25 decoder (`decode/p25`, shares nothing with `decode/dmr`).** Frame sync `0x5575F5FF77FF`
(normal + inverted correlation) → **status-symbol stripping every 70 bits** (a 2-bit dibit across
the *whole* stream; wrong phase breaks everything downstream) → NID `BCH(63,16)` → NAC + DUID →
per-DUID handling: LDU1/LDU2 carry 9 IMBE frames each (LC `RS(24,12)`, Encryption-Sync `RS(24,16)`),
TDU ends the call, TSDU carries trunking. **IMBE decode order is load-bearing** (the first
Golay(23,12) codeword seeds the PN de-scrambler for the rest) — JMBE handles it internally, which
is exactly why we validate against JMBE rather than reimplement.

**Trunking.** TSBK: deinterleave → rate-1/2 Viterbi → CRC-16, **act only on CRC-valid blocks**.
Cache `IDEN_UP` band-plan blocks; a voice grant (`GRP_V_CH_GRANT` / `_UPDT`) resolves
`freq = base + channel# × spacing` and `IqTap.subscribe()`s a new in-span chain — following all
simultaneous grants with no radio command. Ship a **coverage-% metric and out-of-span
"missed-grant" log** so a system wider than the capture reads as a coverage gap, not a decoder bug.

**Encryption.** Read ALGID per call (HDU, re-checked at LDU2 Encryption Sync since conventional
calls may lack an HDU): `0x80` = clear → decode; anything else → **mark encrypted, mute the
vocoder, log ALGID/KEYID/MI as metadata**. Clear and encrypted calls interleave on one system, so
the gate is per-call and mandatory.

**Radio time.** Continuous voice monitoring monopolizes the overlay slot and is preempted by sat
passes, so this runs on a **dedicated overlay radio** (`overlay-device`, the remote pi4 RSP is
exactly this) via `PeriodicWindowScheduler` (flexible-overlay, continuous-hold) + a
`ReceiverControl` panel toggle. Two-radio mode keeps 1090/162 alive through a voice session.

## Migration strategy

Each step is one PR with the CD gate (`backend/gradlew -p backend clean check`) green, a full
review, and a live restart after merge. DSP steps are oracle-verified the way `DmrFecTest` pins
FEC against MMDVMHost's encoder.

**PR 0 — Real-air DMR metadata gate + fixture capture (spike, not code).** Before building voice on
it, prove the existing DMR chain decodes *real air*: enable DMR on the remote radio at **ES1DMR
434.5875 MHz, CC1** (Tallinn, ~25 km — the live config already tunes exactly this: `center-khz
434537`, `channels-hz 434587500`, note the code *defaults* of 433600 do NOT, so a fresh context
must set them) and capture at least one Link-Control metadata decode (talkgroup/srcId). The chain
has never decoded a real signal (`DmrDemodTest` javadoc: mapping "awaits a real 70 cm reception").
**Retain the raw cs16 IQ of a keyed-up call — it becomes the checked-in DMR-voice fixture for
PR 1/3/4/5's oracle diffs and the PR 1 real-air regression.** If ES1DMR stays idle, capture off-air
IQ another way. **This gates the whole DMR side.**

**PR 0b — P25 reference-capture spike (not code), before PR 6.** P25 is effectively unreceivable
locally (see Risks), so PR 6+ are recordings-only. This spike must (a) obtain a trunked-P25 Phase-1
site capture with a known RadioReference band plan (community captures / sigidwiki / an OH2RCH
reception attempt), (b) reproduce a reference decode with OP25 (`-r`/`--symbols` raw-symbol replay)
and/or dsd-fme so their output is the committed oracle, and (c) confirm the CPU budget of the
wideband tap at the **real 1–2.4 MHz span rate** (the 20-channels-≈-10%-of-a-core figure is an
*estimate* extrapolated from the current 768 kHz DMR path; the naive-NCO-vs-PFB crossover can shift
~3× with input rate). PR 6 does not start until this lands the fixture + oracle output.

**PR 1 — Generalize the C4FM front end + AFC.** Extract a mode-generic C4FM demod from `DmrDemod`
(mode = deviations + syncTable + symbolFilter=passthrough for DMR / boxcar for P25 + framer),
**DMR keeping its exact current path (passthrough symbol filter, no RRC added)**; mode-derive the
scale seed; add a fast sync-seeded AFC re-centre composing with the existing `discDc`. *Verify:*
`DmrDemodTest` + `DmrFecTest` stay green (the proof DMR is byte-for-byte unchanged); the generalized
front end still decodes the **PR 0 real-air capture** (real-air regression, not only synthetic);
new parameterized `C4FMDemodTest` recovers metadata for both DMR and P25 constants from a synthetic
modulated stream with injected 500–1000 Hz LO error (the AFC test).

**PR 2 — Vocoder integration + oracle harness.** JMBE jar built from v1.0.9 → Nexus; `AudioCodec`
seam in `decode/voice`. *Verify (two distinct checks, since JMBE both *is* the codec and the
oracle — comparing the seam to JMBE-direct proves only frame packing, not audio):* (a) **seam
test** — wrapper output vs JMBE-direct on identical 144-bit IMBE / 72-bit AMBE frames, catching
bit-order/endianness bugs in the frame-packing seam; (b) **independent audio oracle** — a committed
reference PCM/WAV (produced offline by dsd-fme/OP25 on a known frame stream) the wrapper must
reproduce within a stated tolerance. Both headless in CI.

**PR 3 — DMR voice burst extraction.** Match the BS/MS VOICE syncs (currently deliberately unmatched
in `DmrDemod`), symbol timing across the 6-burst voice superframe, embedded-LC + AMBE-frame
extraction (3× 72-bit AMBE per 30 ms burst, per slot). **Flip the "no voice" javadocs in the files
this PR touches** (`DmrDemod.java`, and any extraction-path comment that becomes untrue here) — a
voice-extracting `DmrDemod` whose own javadoc says it never touches voice would be correctly
rejected in review; the remaining sites flip in the PR that invalidates each. *Verify:* oracle diff
against dsd-fme/sdrtrunk on the **PR 0 retained capture** (bit-exact on AMBE frame bytes / LC;
sync-detect rate reported) — offline compare, committing the reference output if the decoder can't
run headless in CI; single-bit-flip tolerance + gross-corruption rejection (`DmrFecTest` style).

**PR 4 — Per-call session model + clip assembly + storage.** `CallSession` (channel, slot) with
silence-fill assembly → 8 kHz WAV on disk + append-only `dmr_call` row (`schema.sql`, `DmrCallEntity`,
`DmrCallRepository.record()`, optional `ObjectProvider`); clip retention policy (age/count/size).
*Verify:* replay a captured call → WAV + DB row; sample-count→wall-clock timestamping; retention
prune keeps DB and files consistent (pos/neg).

**PR 5 — Clip serving + UI playback.** `GET /api/dmr/calls` (limit capped like `HfLogController`)
and `GET /api/dmr/clip/{id}` (typed-id → row → `FileSystemResource` + `PhotoController`
path-traversal guard); frontend `types.ts` + `Receivers.tsx` DMR card gains a per-call clip list
with an `<audio>` element (greenfield — no audio in `frontend/src` today). *Verify:* headless
Playwright plays a clip; traversal guard pos/neg; the **remaining** "no voice" sites flip here — the
UI/`types.ts` copy plus any not already flipped alongside their code in PR 3/4 (confirmed surface:
`DmrDemod.java:10,16`, `DmrReceiver.java:11,13`, `DmrRxProcess.java:16`, `EngineSourceConfig.java:677,684`,
`StateStore.java:239`, `frontend/src/core/types.ts:159`).

**PR 6 — P25 Phase 1 framer + FEC (`decode/p25`).** Frame sync (normal+inverted), status-symbol
stripping, NID `BCH(63,16)` → NAC/DUID, LDU1/LDU2 IMBE extraction, LC `RS(24,12)` / ES `RS(24,16)`,
ALGID gate. *Verify:* oracle vs **OP25 raw-symbol replay (`-r`/`--symbols`) fed the same dibit
stream** and dsd-fme on the same capture — NAC/DUID/LC/ALGID match; single-bit-flip correction;
encrypted-call fixture confirms the vocoder is muted and ALGID/KEYID/MI logged.

**PR 7 — P25 voice clips.** HDU→LDU1/LDU2→TDU call boundaries (late-entry starts a clip on a bare
LDU) into the PR 4/5 session/clip/UI machinery; `p25_call` table. *Verify:* replay a P25 voice
capture → WAV + row + browser playback; late-entry call still clips.

**PR 8 — Wideband IQ tap + trunk-following.** `IqTap.subscribe(centerHz)` fan-out; TSBK
deinterleave → Viterbi → CRC-16 (act only on valid); IDEN_UP cache; grant-follow subscribes a new
in-span chain; coverage-% metric + out-of-span logging; IQ-gap detection broadcasting a reset.
*Verify:* replay a trunked P25 site capture — IDEN_UP→frequency matches the RadioReference listing;
all simultaneous grants followed; injected IQ discontinuity resets every tracker.

**PR 9 — Scheduling, panel, dedicated overlay.** *Extend* the existing `dmrScheduler` bean +
`radar.dmr.*` keys (`EngineSourceConfig.java:675–712`, already wired) with the
continuous-hold/dedicated-overlay path; **add** the new `p25Scheduler` bean + `radar.p25.*` keys;
`ReceiverControl` rows; dedicated-overlay path so continuous voice never parks 1090/162; live-window
chip extended (note `types.ts` `dmr_rx.until_epoch_s` is stale — backend sends only `center_khz`).
Note DMR voice (PR 3–5) already reaches the air through the *existing* scheduler/`DmrRxProcess`
path, so it is usable after PR 5 — this PR is the continuous-monitoring/preemption polish, not a
prerequisite for DMR voice. *Verify:* panel toggle holds the radio continuously; sat-pass priority
still preempts; two-radio mode keeps base receivers alive through a voice session.

## Operator decisions (gate the arc shape)

1. **Legal/privacy sign-off.** The arc flips the standing "no voice" guarantee and *stores* clips
   of third-party communications. Estonia is reception-free / disclosure-restricted (Constitution
   §43; Penal Code §156 targets *disclosure*, not listening). Proceeding assumes: personal-use
   reception only, clips never republished, and a bounded retention. **Recommendation:** proceed
   for amateur/unencrypted traffic, keep clips on the private appliance only, cap retention (below),
   never decode/disclose encrypted content. Confirm.
2. **DMR-voice patent posture.** IMBE (P25) is patent-clear everywhere (US 5,517,511 / 5,870,405
   expired 2012–13). DMR AMBE+2 is arguably still covered in the **US** by **US 8,359,197, active
   until 2028-05-20**; the EP family from the 2004 filings should have lapsed (~2024) but that was
   not register-verified. For a private, non-distributed hobby appliance in Estonia the practical
   exposure is negligible. **Recommendation:** proceed with both; if you'd rather be conservative,
   ship **P25/IMBE first** and gate DMR-voice (PR 3+) behind the patent question. Confirm.
3. **GPL dependency (JMBE).** House rule bars GPL *code in the repo*; a GPL *library dependency* of
   a private service is the debate item. GPLv3 obligations trigger on conveyance/distribution, not
   private network use. **Recommendation:** accept the dependency; hard rule that no container image
   bundling JMBE ever reaches a public registry (private Nexus/Forgejo only). Confirm.
4. **P25 test RF.** P25 is effectively unreceivable locally (Europe = TETRA/DMR; the only candidate
   is OH2RCH Espoo 434.625 across ~80 km of gulf, uncertain). The P25 arc is developed and proven
   against **recorded trunked-site IQ + reference-decoder oracles** (PR 0b). Can you source a good
   trunked P25 capture with a known RadioReference listing (sigidwiki / sdrtrunk community), or
   should PR 0b schedule an OH2RCH reception attempt first?

**Decided by the plan (defaults, override knobs provided — not gates):** the voice arc runs on the
remote pi4 RSP as the dedicated `overlay-device` (already the wired default); clip retention caps at
**30 days AND 5 GB, whichever hits first** (config-overridable). Oracle pass-criteria are stated
per check: **bit-exact** for FEC/frame bytes and NAC/DUID/LC/ALGID (the `DmrFecTest`-vs-MMDVMHost
discipline); a **defined tolerance** for vocoder PCM (timing/vocoder variance makes bit-exact
audio impossible) — where a decoder cannot run headless in CI, the comparison is done offline and
only its reference output is committed.

## Risks

- **The DMR chain has never decoded real air** (`DmrDemodTest`: mapping "awaits a real 70 cm
  reception"; DMR live-OFF in memory). PR 0 gates the DMR side on a real metadata decode before
  voice is built on top.
- **P25 likely unreceivable locally** — recordings-only development; secure captures before PR 6.
- **Voice syncs + superframe timing** — the current per-sample brute-force sync (no PLL, justified
  "for a burst this short") must become real symbol timing across the superframe (embedded LC in
  bursts B–E, not full syncs).
- **Status-symbol stripping (P25)** — 2-bit dibit every 70 bits across the whole stream; wrong
  phase breaks NID/BCH and all downstream FEC. Match OP25's accumulator offset.
- **IMBE decode order** — first Golay(23,12) seeds the PN de-scrambler before the rest; validate
  against JMBE (it handles this).
- **Deviation-scale / AFC framing must not double-implement what exists** — the slicer already
  amplitude-normalizes (`scale` MAD) and `discDc` already removes a static offset on a continuous
  stream, so the real work is mode-deriving the scale seed and adding a *fast, sync-seeded*
  transient AFC that composes with `discDc` — not a second DC-removal loop. The naive "mis-slices
  every symbol / mis-slices P25 unless normalized" framing is only true for the *initial* seed and
  the *transient* lock, not steady state.
- **Single gain across a wide span** — one strong in-span blocker compresses all channels; manual
  gain discipline required (the band-survey found AGC ignoring gain settings).
- **IQ gaps corrupt all channels at once** — gap detection + broadcast reset is load-bearing.
- **TSBK trust** — deinterleave→Viterbi→CRC and act only on CRC-valid grants, or mis-tune on
  corrupted control.
- **`schema.sql` discipline** — new tables are `CREATE IF NOT EXISTS`; any ALTER to an existing
  table is its own new Liquibase changeset (checksum semantics), never an edit in place.
- **Clip retention must keep DB rows and files consistent** — purpose-built, not the keep-N `.cs16`
  precedent (wrong shape) nor the photo pattern (no pruning).
- **"No voice" is load-bearing documentation in 8 confirmed places** — but they do NOT all flip in
  PR 5: `DmrDemod`'s own "never touches voice" javadoc goes false at **PR 3** (a reviewer rejects a
  voice-extracting class that still claims otherwise). Flip each site in the PR that invalidates it;
  the UI/`types.ts` copy batches in PR 5.
- **US 8,359,197 (AMBE+2) active until 2028-05-20 in the US**; EP-family lapse (~2024) is inferred,
  not verified; none of this is legal advice.
- **CQPSK/LSM simulcast** shares the constellation but degrades a pure C4FM discriminator — scope
  v1 to non-simulcast; note an LSM equalizer as a later add-on.
- **P25 Phase 2 (H-DQPSK + AMBE+2)** — a Phase-1 decoder reads the Phase-1 C4FM control channel but
  cannot decode Phase-2 voice; detect from TSBK service class and mark, don't attempt.

## Reused existing machinery (no new equivalents)

`DmrDemod` DSP front end (NCO/decimate/FIR/discriminator/slicer) → generalized, not forked;
`decode/dmr` FEC classes; `DmrReceiver` roster (metadata card, unchanged); `IqStreams`/rsp_tcp
remote capture + the `overlay-device` dedicated-radio mode from arc 079; `PeriodicWindowScheduler`
continuous-hold + `ReceiverControl` panel toggle; `WsprSpotEntity`/`Repository` native-insert +
`ObjectProvider` optional-wiring pattern; `PhotoController` guarded file-serve + path-traversal
guard; `HfLogController` capped-limit list endpoint; `db/schema.sql` `CREATE IF NOT EXISTS`
convention; the `DmrFecTest`-vs-MMDVMHost oracle discipline (extended to OP25/dsd-fme/JMBE oracles).

## Verification

Per-PR: CD gate + full review + live restart (safe: each PR is inert until configured, except the
staged "no voice"→voice doc flip that begins at PR 3 with the code that first extracts voice). The
DMR spike PR 0 gates PRs 1–5; the P25 spike PR 0b gates PRs 6–8 and must land the reference capture
+ committed oracle output before any P25 code. Arc close: a real-air DMR voice clip in the UI (PR 0
gate met), a P25 clip decoded from the reference capture matching the committed oracle, trunk-follow
matching a RadioReference band plan, full clean check, live restart, this plan closed with
measurements.
