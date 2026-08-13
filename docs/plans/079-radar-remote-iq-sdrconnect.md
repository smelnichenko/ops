# 079 — Radar remote IQ: consume the pi4 SDRconnect server over its WebSocket API

## Decision

Radar gains a network IQ source: a pure-Java client for SDRplay SDRconnect's officially
documented WebSocket API (spec 1.0.3; headless parity is stated in the spec; port 5454 comes
from SDRplay's module-system page, not the spec — spike-verified; shipped since SDRconnect
1.0.6, Jan 2026). The remote radio is addressed by a new selector grammar
`sdrconnect://host[:port][/serial][?mode=full|lite]` (Compact is demodulated-audio-only and
deliberately not consumable here) accepted by the existing
`radar.engine.sdr-device` / `ais-device` / `overlay-device` string slots and dispatched inside
`IqStreams.open`. First deployment (decided 2026-08-12): `overlay-device` — the pi4 RSP becomes
the dedicated overlay radio for all ~19 scheduled experiment windows while the local RSP keeps
ADS-B/AIS full-time (BandArbiter dedicated-overlay mode; observation never parks again).

IQ sources are **web-UI-configurable** (added 2026-08-12): a persisted source directory
(name + `sdrconnect://` address, e.g. pi4's IP) with CRUD + connection test, and per-slot
selection (AIS and overlay slots choose local or any defined source; the observation slot is
pinned local — ADS-B rates exceed the link). YAML device slots remain the bootstrap defaults;
UI changes persist in the state dir and take effect at the next session/window open.

SDRconnect stays on pi4 untouched. Rejected alternatives: the native :50000 protocol
(closed, undocumented, no public reverse engineering); SoapyRemote (zero Java changes but
unresolved upstream SDRplay enumeration bugs, lossy UDP over WiFi, and it would displace
SDRconnect — killing the live pi4 wedge A/B investigation); RSPTCPServer/rtl_tcp (clean simple
protocol, but also displaces SDRconnect). Both remain one-swap-away fallbacks at the same seam.

## Why

- pi4 (192.168.11.7, RSP on USB2, WiFi uplink) already runs `SDRconnect --server` — the user
  wants radar to take IQ from remote receiver boxes like it, without giving up the box's
  existing role.
- The WebSocket API is the only *officially supported* third-party IQ path out of SDRconnect:
  JSON control envelope + binary frames, type 2 = signed 16-bit little-endian interleaved IQ
  (primary tuner; type 5 secondary). JDK `java.net.http` WebSocket → no new dependencies.
- Every overlay/experiment band radar schedules asks for 62.5–768 kSPS, and windows are
  duty-cycled — even at the 2 MSPS ceiling (CS16 ≈ 66 Mbps) the link carries bounded bursts,
  not a 24/7 flood. ADS-B is the opposite: continuous, and 6 MSPS on an RSP (≈192 Mbps) —
  it stays local, enforced at boot. (Whether the stream arrives at the requested rate or at
  device rate is a spike question; see gate G3.)
- The wedge investigation (pi4 unreachable after ~2 days iff SDRconnect runs; instrumented
  2026-08-12, awaiting recurrence) must keep running. This plan adds exactly one pi4 change
  before the recurrence is captured: enabling `WebSocketInterfaceEnabled` (+ logged restarts).

## Architecture

```
workstation (radar-live)                         pi4 (192.168.11.7)
┌──────────────────────────────┐                 ┌──────────────────────────┐
│ *RxProcess (19 overlay bands)│                 │ SDRconnect --server      │
│   └ IqStreams.open(selector) │  ws://…:5454    │   ├ :50000 native (GUI)  │
│      ├ SoapySdr (local FFM)  │◄───────────────►│   ├ :5454 WebSocket API  │
│      └ SdrConnectIq (remote) │  JSON ctl +     │   └ sdrplay_apiService   │
│         └ SdrConnectClient   │  bin IQ frames  │        └ RSP (USB2)      │
│            └ IqFrameBuffer   │                 └──────────────────────────┘
│ SdrDemodFrameSource (ADS-B)  │──local only (remote selector = boot error)
└──────────────────────────────┘
```

- `io.schnappy.radar.source.sdrconnect`: `SdrConnectSelector` (grammar; note: the API expresses
  network mode only as a suffix of the device-selection commands, so `?mode=` without `/serial`
  means the client first discovers the serial via `valid_devices`/`active_device` and
  re-selects), `SdrConnectProtocol` (the ONE wire-format class: envelope `{event_type,
  property, value, device?}`, all values strings, `device` defaults to primary; commands
  `set_property`/`get_property`/`iq_stream_enable`/`device_stream_enable`/
  `selected_device_serial`; responses `get_property_response` + `property_changed` pushes;
  binary demux on the 2-byte LE type prefix), `IqFrameBuffer` (bounded 8 MiB, drop-newest +
  count on overflow — mirrors SoapySdr OVERFLOW-retry; 10 s idle timeout → EOF = wedge
  detection), `SdrConnectClient` (shared HttpClient, always-request backpressure policy,
  property futures), `SdrConnectIq` (open sequence with SoapySdr-parity read-back guards:
  rate ±1 %, freq max(10 Hz, f·1e-6), `lna_state` exact; consults `started` and issues
  `device_stream_enable` if the server idles — zero-frame-while-guards-pass must be impossible
  by construction, not mislabeled wedge), `SdrConnectGain` (RFGR→`lna_state` — the spec types
  it only as "RF gain, Uint32", so the spike must verify the SDRplay LNA-state orientation
  (0 = max gain) before per-band RFGR overrides are trusted on the remote; **no IF-gain
  property exists in the API** — IFGR requests fall back to the server's IF behavior, presumed
  AGC, spike-verified, recorded as "(IFGR requested, IF: server-managed)").
- `can_control` (read-only property) surfaces the server's client-precedence rule (observed
  "1st client controls the hardware" in the server log — spike-verified, not in the spec);
  a refused/unverified retune is an IOException → the standard "sdr error" + backoff.
- **Runtime source directory + slots** (web UI, added 2026-08-12): a small persisted registry —
  sources = `{name, sdrconnect://host[:port]…}`, slots = `{ais, overlay}` → `local` | source
  name (observation pinned local). REST under `/api/radio/…` following the
  GainController/NotchController pattern; persisted in `radar.engine.state-dir` like the
  receiver panel selection; a connection-test endpoint opens the WS and reads `api_version`.
  The ~19 overlay factories and the AIS factory stop capturing device strings at bean creation
  and consult the registry per open (`Supplier<String>`); `BandArbiter`'s dedicated-overlay
  flag becomes a `BooleanSupplier` re-read at its decision points so a slot change flips modes
  without a restart (effective next window/session; the UI says so). YAML slots seed the
  registry on first boot.
- No new Spring config beyond that seeding: the selector string is the configuration unit.
  `SdrDevices.isSdrplay()` stays false for sdrconnect selectors (pinned by test);
  `SdrDevices.gain()` learns to emit `IFGR=,RFGR=` for them so `SdrGainPolicy` band overrides
  compose unchanged.

## Migration strategy

1. **This plan doc** (ops PR, this file).
2. **Spike (user-assisted, needs sudo on pi4)** — investigation hygiene first: snapshot
   netwatch, timestamp every deliberate SDRconnect restart in the investigation memory. Enable:
   find the root-owned settings file (`sudo grep -rli websocketinterfaceenabled /root
   /opt/sdrconnect /etc`), back it up, flip `WebSocketInterfaceEnabled`, restart, verify :5454.
   Characterize from the workstation (websocat + throwaway probe, never committed):
   property set/read-back coverage; whether IQ flows on `iq_stream_enable` alone or needs
   `device_stream_enable` (watch `started`); delivered-rate semantics (device rate vs
   VFO/decimated) + format proof (known strong carrier appears in an int16-LE FFT where
   tuned); `lna_state` orientation (step it and watch a carrier's level — SDRplay convention
   is 0 = max gain; per-band RFGR overrides depend on this); IF-gain behavior (AGC vs fixed —
   level response vs lna_state steps); 60-min soak at 2 MSPS watching bytes/netwatch/RSS;
   consumer-stall behavior (RSS climb = candidate mechanism 3 evidence — record for the
   investigation regardless); two-client `can_control` semantics; restart-persistence.
   GO gates: G1 enable persists; G2 freq/rate/RF-gain controllable with verified lna_state
   orientation; G3 format verified + workable rates; G4 soak ≥99.5 % bytes, RSS drift <50 MB;
   G5 stall bounded. NO-GO → fallbacks above.
3. **PR: transport layer** (radar; pure addition, zero refs from main code): selector, protocol,
   buffer, client + hand-rolled RFC 6455 fake server with scriptable misbehavior; positive +
   negative tests per behavior.
4. **PR: integration** (radar; inert until configured): `SdrConnectIq`/`SdrConnectGain`,
   dispatch in `IqStreams.open`, `SdrSampleRates` remote branch (accepted-rate set **per G3's
   finding** — the SoapySDRPlay3 sub-2 MHz decimation table is a driver property, not
   necessarily SDRconnect's — ∩ ≤2 MSPS link budget), ADS-B boot fail-fast
   (`EngineSourceConfig.validateSource`) + backstop, `SdrOpens` visibility, env-gated live
   smoke (`SMOKE_SDRCONNECT=1 SDRCONNECT_URL=…`).
5. **Early live validation** (run/ is gitignored — edit + `restart-live.sh`, no PR):
   `overlay-device: sdrconnect://192.168.11.7:5454` **and in the same edit**
   `satellites.capture.enabled: false` — SatRecorder follows overlay-device, so sat capture
   would silently move to pi4's antenna; re-enable only if 137 MHz there is proven usable.
   Gate: FT8-20 (14.074 MHz) real decode via the remote RSP while the 1090 message rate runs
   uninterrupted (the dedicated-overlay proof). This burns in the client against the real
   server before the UI is built on top.
6. **PR: runtime source directory + slots** (radar backend): persisted registry (sources +
   ais/overlay slot assignment, observation pinned local), REST under `/api/radio/…`,
   connection-test endpoint, `Supplier<String>` threading through the overlay/AIS factories,
   `BandArbiter` dedicated-flag as `BooleanSupplier`, YAML seeding, validation (grammar parse,
   slot restrictions). Positive + negative tests per rule.
7. **PR: web UI source selection** (radar frontend): Settings section — source list CRUD
   (name + host[:port]) with test button, slot dropdowns (local | source), "effective at next
   window/session" messaging; Receivers/state surfaces unchanged for now.
8. **Acceptance (UI-driven) + negatives**: re-run the FT8-20 proof configured through the UI;
   a 518 kHz NAVTEX window (retune + MF gain). Negatives: unreachable host → boots green +
   window warnings only; server stop mid-window → glitch-retry, next window recovers unaided;
   firewall DROP of 5454 (wedge signature) → idle timeout, no stuck threads, unaided recovery;
   slot flipped back to local mid-operation → next window on local radio, no restart; the real
   wedge, when it recurs → ride-through recorded in the investigation memory.
9. **PR: post-spike gaps (conditional)**: VFO/decimation rate mapping if G3 says device-rate
   only; undocumented IF-gain property if the spike finds one; `overload` event surfacing.
10. **PR: ansible receiver profile (INERT)** (radar): `playbooks/receiver.yml` with
   `tasks_from: sdrconnect.yml` (NOT a site.yml flag — site.yml provisions the full appliance),
   `sdrconnect.service.j2` (Description, `Restart=on-failure`, `RestartSec=5`), settings key
   asserted via lineinfile (never a full-file template — SDRconnect rewrites its own settings),
   Taskfile `deploy:provision-receiver`. **Applied to pi4 only after the first instrumented
   wedge recurrence is captured** (or the investigation closes): adding `Restart=` earlier
   would turn a diagnostic OOM end-state into an RSS sawtooth mid-experiment.
11. **Docs/memory**: investigation memory (restart timestamps, streaming-load start, stall-test
    RSS finding), new remote-IQ memory, radar CLAUDE.md line, close this plan with measurements.

## Risks / notes

- **WiFi ceiling**: 2 MSPS CS16 ≈ 66 Mbps sustained is the deliberate upper edge; remote ADS-B
  (≥2 MSPS RTL / 6 MSPS RSP) is permanently out of scope on this link. A delivered-rate
  diagnostic (measured bytes/s vs 4·rate, warn >10 %) is the tripwire for both link trouble
  and wrong rate semantics.
- **Wedge interplay**: 24/7 streaming is candidate mechanism 1's exact stressor (sustained
  mt7921u TX). Acceleration is diagnostically useful (instrumentation is live) and survivable
  by design — remote windows fail-warn and resume; observation is local and unaffected. No pi4
  changes beyond the settings flip until the recurrence is captured; every deliberate restart
  timestamped.
- **API stability**: officially documented and supported, but unversioned on the wire beyond
  the `api_version` property (pin: spec 1.0.3). `SdrConnectProtocol` is the single class that
  knows the encoding; SoapyRemote/RSPTCPServer remain one swap away behind the same seam.
- **Hardware-control contention**: the server grants control to the first client. Radar should
  be the long-lived first client; an interactive GUI session connecting first after a server
  restart owns the tuner — refused retunes surface as window warnings, not silent AGC captures.
- **Device-global singletons**: `SdrGainPolicy` band table, `SdrNotchPolicy`, and the
  `SdrOpens` ring are one-tuner designs; with two radios they apply to both and the ring
  interleaves both. Accepted for v1; per-device split is a later arc. No notch control exists
  over the WS API at all (property absent) — sub-30 MHz remote captures forgo MW rejection.
- **Antenna reality**: overlay bands inherit pi4's antenna; decode rates re-baseline wholesale
  (`sdr-ifgr-bands` was tuned on the local antenna). The per-band IF numbers may need a remote
  sweep later; IF gain is server-AGC anyway until/unless a property is found.
- **Runtime slot changes**: applied at the next open, never mid-stream — a running window
  finishes on the radio it started on. The dedicated-overlay flag is re-read at arbiter
  decision points; flipping it mid-capture must not orphan a session (tests pin this).
- **Security**: :5454 is unauthenticated control + IQ. LAN-only, never port-forwarded. The
  source-directory UI accepts arbitrary hosts — it is an internal tool on an authenticated
  LAN app; the connection test never follows redirects and speaks only the WS protocol.
- **Out of scope**: remote ADS-B; Compact/audio/spectrum modes; the native :50000 protocol;
  multi-VRX fan-out; moving observation off the local radio; per-device gain/notch/opens split.
