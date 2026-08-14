# 079 — Radar remote IQ from the pi4 receiver box (SDRconnect WS → rsp_tcp)

## CLOSE-OUT (2026-08-14): arc delivered, acceptance green

Everything the amendment planned is live, plus two operator decisions that superseded parts of
the plan text below (which is kept as written for the record):

- **The 2 MSPS "link budget" is gone.** iperf3 (2026-08-14, WiFi as deployed): **557 Mbps
  up / 393 Mbps down**, 0 retransmits. The remote rate cap is now the rsp_tcp/RSPdx-R2
  **hardware limit, 10 MSPS** (≈320 Mbps CS16 — fits with headroom). The hour-long soak ran at
  64 Mbps; sustained loss-free delivery far above 2 MSPS is unproven until a soak at rate —
  the delivered-rate diagnostic is the standing tripwire.
- **Nothing stays local-only** (user, 2026-08-14). The plan's "observation pinned local" is
  superseded: the observation (base 1090/162) radio is a third runtime slot like overlay/AIS,
  ADS-B opens through the IqStreams dispatch (a remote RSP runs the full 6 MSPS), and
  `BandArbiter.rebindBase()` bounces the running base session when the slot or its source URL
  changes — a healthy base session never otherwise ends. Full-time (non-arbiter) mode still
  reads its device at boot; the live deployment is arbiter mode.

**PR ledger (radar)**: #595-#597 receiver-box ansible (rsp_tcp unit, SDRplay API stack,
SDRconnect toggle); #598 transport (`RspTcpIq`/selector/protocol + fake server); #599
`IqStreams` dispatch + rate gates + live smoke; #600 `RadioSources` registry + `/api/radio/…`;
#601 Settings UI (source CRUD + handshake test + slot chips); #602 dual-radio receiver panel
(group-scoped exclusivity); #603 WiFi watchdog (capture-then-recover); #604 10 MSPS cap +
remote-capable observation slot; #605 rsp_tcp `TimeoutStopSec=10`; #606 CLAUDE.md; #607
receiver `tcp_retries2=8`. Ops: #22 spike results.

**Acceptance**: FT8-20 via the remote RSP decoded real signals (LZ1ZF KN22 −13.9/−18.5 dB,
SV2HTW −8.1 dB) **while** 1090/162 ran on the local radio — up to 4 vessels concurrently
tracked; both rows ON is the normal state. NAVTEX: the remote MF retune + per-band
gain + slot-hop are proven (`freq=515000/487000 rate=250000 IFGR=30,RFGR=5/6 (remote)`), but
NO message decoded — ~3 h of 518 kHz home-listening plus the full Tallinn 490 kHz slot
(19:10-19:20 EEST, stream verified healthy throughout) produced zero messages. The same
decoder has real decodes on the LOCAL antenna, so this is pi4's short whip at 600 m
wavelength, not the transport: an MF antenna for the receiver box is the follow-on.

**Negative runs (all live, 2026-08-14)**:
- *(a) unreachable host*: overlay slot pointed at a ghost box — every window failed with one
  clean `No route to host` warn, scheduler kept ticking, base untouched; a **restart** with the
  ghost slot persisted booted green and restored it; flipping back recovered on the very next
  window (9 s later). The test source deleted afterwards.
- *(b) server stop mid-stream*: `systemctl stop rsp_tcp` exposed that **rsp_tcp ignores
  SIGTERM while streaming** (sdrplay API teardown hang) — systemd waited its default 90 s and
  SIGKILLed. Radar rode it out: TERM-time socket reset → one in-window glitch-retry
  (reconnected into the dying server), SIGKILL reset ended the window quietly, next 13-min hop
  reopened unaided. Fix: #605 bounds the stop at 10 s (same SIGKILL, 80 s sooner) — deployed
  and observed working (stop-to-kill exactly 10 s on the next deploy's restart).
- *(c) established-stream blackhole* (the wedge signature; `iptables -I INPUT 1 … -j DROP` on
  pi4 — note ufw port rules can NOT produce this, its conntrack ESTABLISHED accept outranks
  them): idle SO_TIMEOUT EOF fired at **+10 s** (`remote wedged or link dead`), the glitch-
  retry hung on the dropped SYN and timed out at **+5 s**, the rx thread exited cleanly (zero
  stuck threads), and the first hop after rule removal reopened unaided.
- *(d) the REAL wedge* rode through during this very acceptance run: the daily ~18:06 GTK
  rekey wedged pi4's WiFi mid-stream (mechanism now PROVEN by the watchdog's first forensic
  bundle: mt7921u TX stall under streaming load freezes wpa_supplicant in its EAPOL sendto —
  driver bug, not userspace SAE; details in the pi4 connectivity investigation). Radar: idle
  EOF at +10 s, window warns during the ~3 min outage, watchdog tier-1 recovered pi4 in 8 s at
  fails=3, and the next hop reopened unaided. Exactly the ride-through the plan demanded.
  ONE follow-on found and fixed: the wedge kills the client without a FIN, and single-client
  rsp_tcp keeps retransmitting into the dead ESTAB (~200 KB Send-Q observed) while fresh
  clients sit unserved in CLOSE-WAIT for the kernel-default ~15-25 min — and it DOMINOES:
  each timed-out fresh attempt leaves the next corpse the server then blocks on, so a
  periodic reconnector (the 13-min NAVTEX hops) keeps the box wedged indefinitely (observed
  18:20 -> 18:33 -> 18:46, all read-timeouts; radar's side stays clean warns throughout —
  correct client behaviour against a mute server). #607 sets `net.ipv4.tcp_retries2=8` on
  the receiver profile so a corpse dies in ~100 s, faster than the reconnect period — the
  domino cannot sustain. Until deployed, an rsp_tcp restart clears the pile instantly.

**Receiver-box facts that postdate the plan text**: the unit is `rsp_tcp -E -b 16` (extended
mode alone stays 8-bit — spike-proven), StartLimit 5/300 s + shm readiness gate defend the
API-daemon race, `TimeoutStopSec=10`, and `systemctl start SDRconnect` remains the manual GUI
toggle with reboot restoring rsp_tcp mode. The WiFi wedge mechanism was identified during this
arc (daily GTK rekey hangs wpa_supplicant 2.10 under load; dbus reply-quota poisoning is
permanent) — WPA3 kept per user, powersave off, watchdog #603 deployed as survival+forensics;
that thread continues in the pi4 connectivity investigation, not here.

**Still open beyond this plan**: sustained soak before any band RELIES on rates far above
2 MSPS; per-device gain/notch/opens split (device-global singletons apply to both radios);
remote antenna re-baselining per band (pi4's whip ≠ the calibrated local antenna).

## AMENDMENT (2026-08-13): transport pivots to rsp_tcp / rtl_tcp

The 2026-08-13 spike (below) proved the SDRconnect WebSocket API works end-to-end **and**
found its capability ceiling: only RF gain (`lna_state`) is controllable — no IF-gain property
exists, IF AGC cannot be disabled, and there is no notch control. That collides with radar
doctrine (per-band IFGR table + AGC-off verification exist because of the #534 AGC lesson;
the <30 MHz auto-notch policy needs notch commands). **Decision (user, 2026-08-13): the
transport is SDRplay's RSPTCPServer (`rsp_tcp`) in extended mode**, whose command set has full
parity (SET_IF_GAIN_R, SET_AGC + setpoint, SET_NOTCH, SET_ANTENNA, SET_BIAST, SET_LNASTATE,
16-bit samples) — and whose client doubles as a plain `rtl_tcp` client, so any RTL-dongle box
also becomes a radar source. WebSDR/OpenWebRX were evaluated and rejected: they are human
*listening* servers (audio/waterfall consumers of a receiver), not machine IQ sources.

### Spike v1 results (SDRconnect headless WS, pi4 RSPdxR2 24051B0570, 2026-08-13)

Kept as the record of why WS lost despite working, and as transport-agnostic link evidence:
- Exact-rate delivery: 2 MSPS → 64.01 Mbps sustained over the pi4 WiFi link; decimated rates
  honored (250 k → 8 Mbps, 62.5 k → 2 Mbps); **96 k silently refused** (read-back caught it —
  rate acceptance is power-of-2-from-2M only).
- Format proven: int16 LE interleaved; +100 kHz retune moved the dominant FM peak by exactly
  −100 kHz (same absolute station, ~100.6996 MHz).
- `lna_state` orientation proven: 0→6 dropped band power −5.9 → −21.6 dBFS (SDRplay RFGR
  convention, 0 = max gain; dxR2 range 0–26).
- Stall test: 30 s consumer stall → TCP backpressure, ~3 s bounded server buffer then drop,
  no disconnect, server RSS +116 kB only (evidence against the buffering-leak wedge theory).
- Two-client: NO first-client lock on the WS API — a second client can retune mid-stream
  (`can_control` just means "device started"). Cooperative control, no protection.
- Unknown properties never answer (get_property needs a client timeout); no IF-gain/notch/
  AGC-off surface (agc_enable is the *audio* AGC).
- 60-min 2 MSPS soak: link-level result recorded in the closing notes when complete.

### What the pivot changes

- **Client protocol** (transcribed from RSPTCPServer source, pinned clone at
  `/home/sm/src/RSPTCPServer`, HEAD 61b8c91): connect → read 12-byte `RTL0` header (tuner
  type/gain count, uint32 BE) → in extended mode read the 45-byte packed `RSP0` capabilities
  struct (version, capability bitmap, hardware_version, sample_format, antenna count + third
  antenna name/freq limit, tuner_count, **ifgr_min/ifgr_max** — all uint32 BE) → raw int16
  native-order interleaved IQ stream; commands are 5 bytes (1-byte id + uint32 BE arg):
  standard rtl_tcp 0x01–0x0e + extended 0x1f–0x26. **No read-backs** — the delivered-rate
  diagnostic and the capabilities struct are the verification surface; a plain-rtl_tcp server
  (no `RSP0` block) degrades to 8-bit/RTL semantics behind the same client.
- **Rates**: arbitrary in [31.25 k, 10 M] honored exactly (`fs = rate × decimation`, ≤64,
  IF bandwidth auto-selected ≤ rate) — better than the WS API's power-of-2 set.
- **Selector grammar** becomes `rsptcp://host[:port]` (extended, RSP) and `rtltcp://host[:port]`
  (plain rtl_tcp, RTL dongles); `sdrconnect://` is dropped.
- **Server lifecycle on pi4**: the ansible receiver profile moves EARLY (it is now the enable
  path): installs the standalone SDRplay API (pinned 3.15.2, per rsp.yml pattern), builds
  RSPTCPServer (pinned ref), ships `rsp_tcp.service` (`-E -a 0.0.0.0 -p 1234 -d <serial>`),
  with `Conflicts=SDRconnect.service` so the box toggles between "radar source" and the
  user's GUI browsing server with one systemctl command. rsp_tcp is **single-client**.
- **Wedge investigation reframed (logged as a deliberate change)**: SDRconnect leaves pi4's
  runtime; the A/B becomes "does the wedge follow sustained streaming load or the SDRconnect
  binary" — netwatch + persistent journald instrumentation stays, restart/stop timestamps
  continue to be recorded in the investigation memory.
- Steps 3–4 (client transport + integration PRs) and the runtime source-directory/UI steps
  are unchanged in shape; only the protocol class inside PR 1 changes (simpler: no WebSocket
  framing, no JSON). The conditional "post-spike gaps" step disappears (IFGR/AGC/notch are
  first-class commands now).

### Spike v2 results (rsp_tcp -E -b 16 on pi4, 2026-08-13 — ALL GATES GREEN)

- **Handshake**: RTL0 (tuner=5 R820T-faked, 28 gains) + RSP0 v1: hw=7 (RSPdx-R2), caps=0x9d
  (biasT, refIn, BC notch, DAB notch, AGC), format=INT16, antennas=3 (third "Antenna C",
  200 MHz limit), tuners=1, **ifgr=[20..59] carried in the handshake** (feeds client gain
  clamping). GOTCHA: `-E` alone leaves the stream 8-bit — `-b 16` is required (now in the
  unit); `third_antenna_freq_limit` is host-order (LE) while other u32s are network-order.
- **Rates honored EXACTLY, arbitrary values** (steady-state, measured): 62.5 k, 96 k (the rate
  SDRconnect refused), 250 k, 768 k, 2 M → delivered within ±0.3 %. 2 MSPS CS16 = 63.95 Mbps
  over the pi4 WiFi (same load spike v1 soaked for an hour at 99.999 %). Server streams at its
  2.048 M default from connect until commands land — clients must set rate/freq first and
  measure delivery only after settling.
- **Retune proof (16-bit)**: +100 kHz tune moved the FM peak −100 kHz (same absolute station);
  int16 LE interleaved confirmed.
- **Gain doctrine restored remotely**: AGC off + IFGR 20→59 = 28.7 dB measured drop (shortfall
  vs 39 dB commanded = front-end compression on the strong FM band at max gain — direction and
  scale prove the command path); LNA 0→6 on a notched floor = **18.7 dB clean** (SDRplay
  convention, higher = more reduction); **broadcast notch = ~30 dB FM kill** and un-clips the
  ADC (at IFGR 40 / LNA 0 the FM band SATURATES the dxR2 on pi4's antenna — per-band gain
  policy genuinely matters on the remote radio; DC spike appears at max IFGR as usual).
- **Ops**: two idempotent re-provisions proven; convergence check (key-based two-sample assert)
  proven against a healthy unit; ufw rule active; sequential client sessions all accepted
  (single-client at a time, accept-loop survives disconnects).
- Client-PR notes: no acks in the protocol — verification = capabilities struct + delivered-
  rate diagnostic; discard/tolerate the pre-command 2.048 M ramp; commands are 5-byte
  cmd+u32-BE; extended set 0x1f–0x26.

### Incident record (2026-08-13, first apply)

The first receiver-profile apply crash-looped rsp_tcp (upstream never checks
`sdrplay_api_ApiVersion`'s return; racing the restarting API daemon yields garbage + exit(1));
the unbounded restart loop hammered the daemon's shm channel for hours and coincided with —
and plausibly load-sensitized — the pi4 WiFi wedge, whose mechanism the instrumented recurrence
finally revealed (daily hostapd GTK rekey hits a hung wpa_supplicant; D-Bus reply exhaustion
makes it permanent; see the pi4 investigation memory). Fixes shipped: StartLimit + readiness
gate + RestartSec=10, ufw allow, deterministic convergence assert, reset-failed on re-run
(radar #596, #597).

The original decision record and architecture below are retained for history; where they
conflict with this amendment, the amendment wins.

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
