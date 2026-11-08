# Plan 108 — radar at 100 radios

**Status:** draft 2026-11-07, nothing built. Operator, 2026-11-07: "100 radios are real target"; "dropping single ring
idea". Goes with plan 106 (the scheduler as a service, over MQTT) and plan 107 (a late decoder never drops samples).

## Today

One JVM on aqua (Ultra 5 125H: 4 P cores with 2 threads each, 8 E cores, 2 LP-E cores; 30 GB RAM). 26 receiver rows and
24 session classes. A capture is one reader thread, one decoder thread with its own blocking read loop, and sometimes a
recording writer.

Measured on the live station, 2026-11-07 (one 5 s thread sample, so a first figure only):

| Capture | Decoder | Reader | Writer | Total, of one core |
|---|---|---|---|---|
| RS41, 8 MS/s, 32 MB/s | 23% | 0.8% | - | about 24% |
| RTTY, 96 kS/s, 0.38 MB/s | 5.4% | 1.0% | 1.2% | about 8% |

GC: 320 young collections, 0.71 s in 1026 s, 2.2 ms each on average. Sample losses on the local radio: none in 24 h,
gates included.

## What runs out

Estimates, scaled from the table above. Step 2 replaces them with measurements.

| Limit | 100 RTTY-type | 100 RS41-type |
|---|---|---|
| CPU | about 8 cores: fits aqua | about 24 cores: more than aqua's 14 |
| Data rate | 38 MB/s | 3.2 GB/s |
| Gigabit link (125 MB/s) | one link | about 3 radios a link |
| Queue RAM, half a second each | 19 MB | 1.6 GB |
| Valkey, all 60 s behind | 2.3 GB | 192 GB |
| Allocation, chunks not reused | 38 MB/s, about today | 3.2 GB/s: 7% of the time stopped if young collections scale as they are, every reader stopped at once |

The mix decides almost everything, so step 0 comes first.

Radios come mostly from the network (operator, 2026-11-07), so:

- The host's network link is the wideband limit, not USB: at full 16-bit IQ one RS41-type radio is 32 MB/s, so about 3
  on 1 Gb/s and about 39 on 10 Gb/s. Decimating on the box would cut this, but moves work and failure there.
- A reader is a blocked socket and stays cheap. Its slack is the TCP buffers on both ends and the box's own, and a late
  reader shows up as a stalled box, not a driver overflow. What the box drops, the host only sees as missing samples.
- Today's pi4-C is that class of radio, so its 1.1-1.3 s start deficit is a problem of the main case, not of one box.
- rsp_tcp's wedging on repeated connects multiplies with the box count, and one-capture-per-slot rows (FT8) connect
  often. Retuning a running stream, not built today, would cut those connects and the time a switch takes.

Also found by reading the code, not measured:
- Valkey runs its commands on one thread: many captures spilling at once meet there.
- The page lists rows one by one, and the calendar and row switches assume someone looks at each.
- rsp_tcp boxes can wedge on repeated connects (operator's "no reconnects" rule). At 100 radios, wedged boxes are a
  normal event and need handling without a person.

## Decided

- **No shared ring (operator, 2026-11-07).** The ring waits for its slowest consumer, so one late decoder would cost
  every radio; writers would contend on one cursor; each consumer would step over every other radio's chunks. Each
  capture keeps its own queue, and a lock or ring on it has two threads however many radios there are.

- **The Disruptor stays (operator, 2026-11-07):** "in any way disruptor will stay". One ring per capture. Measured so
  far, no gain over the lock at hand-over, so its value here is in what step 2 measures next: reused buffers.
- **radar is split into parts first; then some of them go into the cluster (operator, 2026-11-07):** "we will split
  radar
  into parts first, then some of them will go into cluster". Not the whole app as it is.
- **A decoder is a microservice (operator, 2026-11-07):** "some machines may run subset of decoders, decoder should be a
  microservice". Radios are on the network, so a decoder need not run where its radio is.

## The split

radar's backend today, 93,000 lines, in four parts (agreed by the operator, 2026-11-07), by what imports what:

| Part | Packages | Lines | Where it can live |
|---|---|---|---|
| Capture and decoders | `source`, `decode` | 56,500 | on machines, per decoder; the cluster only if measured to carry IQ |
| Scheduler | `engine` | 8,800 | plan 106's service |
| Station hardware | `mount`, `servo`, `tracking`, `select` | 7,400 | at the hardware |
| Records and page | `controller`, `service`, `history`, `repository`, `entity`, `dto`, `alerts`, `bandmap`, `identity`, `photo`, `track`, `map`, `client`, `orbit`, the frontend | 14,200, plus the frontend | the cluster's first candidates: no samples, no hardware |

Left to settle: `settings` (2,900) reaches into both sides, and `model` and `geo` (700) are used everywhere; the common
library was removed in March, so they are copied or kept minimal.

The hard seam: 28 files on the records side import `source` or `decode` directly. Those become events first, inside the
one JVM, with nothing moved: that is the split's first step, it needs no new deployment, and it shows up the real size
of
the rest. `engine` also imports `source` in 15 files, which plan 106's step 1b already separates.

### The seam, mapped (2026-11-07)

Counted again after the air-time work: 18 files in the records packages touch `source` or `decode`, plus 12 in
`settings` (left to settle, above). What each one actually uses decides what it becomes:

| Group | Files | What they use | Becomes |
|---|---|---|---|
| Row names | `AlertBands`, `Uvb76AlertService`, part of `NavtexAlertService`, `Rs41Controller` (the serial key) | `NAME`/`SERIAL` constants | constants in a neutral class |
| Current state of a receiver | `NavtexSymbolController`, `Dcf77HistoryController`, `WfaxController`, `ReceptionHistoryController`, `Rs41Controller`, `ControlController` | snapshots, history | read interfaces the receivers implement |
| Decoded messages | `NavtexAlertService` | NAVTEX bulletins via a listener | an event type outside `source`/`decode` |
| The radio-control surface | `GainController`, `NotchController`, `RadioSourceController`, `SdrController`, `SpectrumController`, `AudioController`, `IqController` | gain/notch stores and policy, probes, opens, spectrum, audio, recordings | the capture part's control interface |
| Pure science | `Rs41Controller` | ozone and dew-point maths | moved out of `decode` |
| A decoder on the wrong side | `SatDecodeService` | offline LRPT decode | moved to the decoder part |
| An inverted dependency | `SeenRegistry` | implements `SightingRecorder` | the interface moves to the records side |

The first three are the events step proper: no behaviour changes, the records side stops importing decoder classes.
The radio-control surface is the one that becomes an API between parts later, so it gets its interface designed rather
than extracted.

**Done first, 2026-11-07: every record carries the time it was on the air** (#1196, #1198-#1202). Once a decoder runs
in its own process, the side that files a record no longer shares its clock or its lag, so the record has to say when
it was heard. The time signals, VOR, HFDL, ACARS, APRS, FLARM, DMR, DSC (to the call's end), HF DSC, LORAN, VLF,
WFAX, ADS-B (through the demod's pipe) and AIS now do; a capture with no air falls back to the clock.

**The records seam: done, 2026-11-07 (radar #1203-#1212).** No records class names `source` or `decode`. They read
through `feed`: plain records and interfaces the capture side implements (NAVTEX bulletins and slots, symbols, time
signals, charts, sondes, vessels, satellite decoding, sightings, radio opens, spectra, radio probes, notches, gain,
audio by sample index, the IQ archive). Shared values moved to neutral packages: `model` (row names, the sonde
serial, the NAVTEX station table), `atmosphere` (ozone, dew point), `sigmf` (the archive format). `RecordsSeamTest`
now forbids any mention - import, static import, or a qualified name; it found one the import-only check had missed
(the history controller named `decode.NavtexStations` in full).

### The radio-control surface: an API, designed (2026-11-07)

Steps 1-4 of the seam (#1203-#1206) left 7 records classes, all the page's control of the radios. Each needs these from
the capture code today, mostly static policy classes and record types:

| Controller | Uses | As an API |
|---|---|---|
| `GainController` | `SdrGainPolicy`: the bands, IFGR limits, per-band overrides and effective values, set IFGR/RFGR | `Gain`: bands with limits, overrides, effective values; set |
| `NotchController` | `SdrNotchPolicy`: RF and DAB notch modes, set | `Notch`: modes per band; set |
| `RadioSourceController` | `RspTcpIq.probe`, `SoapySdr.probe`, `RspTcpSelector.matches`, `RspCapabilities` | `Radios`: probe a source, its capabilities |
| `SdrController` | `SdrOpens`: recent opens, their ends, read lag | `Opens`: recent opens with ends and lag |
| `SpectrumController` | `Spectrum.snapshot` | `Spectrum`: a snapshot |
| `AudioController` | `AudioMonitor`: arm, armed, rows, rings, a row's radio | `Audio`: arm, what is armed, its audio |
| `IqController` | `IqRecordings` (policy, usage, recordings, found/gone), `SigmfArchive` (write, sizes), `IqRecordingSpectrum`, `SdrOpens.recentWithEnds` | `Recordings`: list, usage, policy, export, a recording's spectrum |

Rules for the API, so it can later cross a process boundary without a redesign:
- **Plain values only:** records of strings, numbers and lists, in `feed`. No stream, file handle or capture object
  crosses; a recording's export is named by id, and the capture side writes it.
- **One interface per row of the table**, implemented on the capture side by the classes that hold the state now. The
  static policies (`SdrGainPolicy`, `SdrNotchPolicy`) stay where they are, behind an instance the controller is given.
- **Each controller keeps its HTTP shape.** The page does not change; only where the controller gets its answers.

Order: the read-only four first (`Opens`, `Spectrum`, `Radios`, `Recordings` listing), then the ones that change state
(`Gain`, `Notch`, `Audio` arming, `Recordings` export), each with tests that the page's requests still do the same.

### The scheduler's seam, mapped (2026-11-07)

Operator, 2026-11-07: the scheduler part's seam comes before the module split. Measured: 18 of `engine`'s 31 files import
another part, 86 of those imports from `source`. The direction is already one-way: `source` imports nothing from
`engine`.

| Group | Files | What they use | Becomes |
|---|---|---|---|
| The composition root | `EngineSourceConfig` | every receiver and capture loop, to build them | stays the wiring; split per part with the modules |
| The session contract | the 7 schedulers, `ContinuousSessions`, `ContinuousStallWatchdog`, `RadioSources`, `EngineProperties`, `SdrAutoDetect`, `ReceiverControl` | `SdrSession` (24 implementers in `source`), `RadioId`, `SdrDevices`, `BandArbiter` and its overlay port | a neutral `radio` package both parts import: a session, a radio's identity, radio time |
| The trackers the tick reads | `Engine`, `AsyncPlaces` | ADS-B, AIS, RS41, UVB-76, FT8 receivers; aircraft and vessel sources | `feed` read interfaces (vessels already exist) |
| Policies | `ReceiverControl` | `SdrGainPolicy`, `SdrNotchPolicy` | `feed.Gain`, `feed.Notch` (records seam steps 7-8) |
| Other parts | `Engine`, `NavtexScheduler`, `SatCaptureScheduler`, `VlfScheduler`, `StoreConfig`, `ScheduleStore`, `ReceiverControl`, `EngineController` | `tracking.StateStore` (station hardware), `settings.BookingStore`, `bandmap`, `service`, `orbit`, `map` | each its own seam, after `source` |

`BandArbiter` has no imports of its own and both parts use it (capture loops, `IqSpawn`, `RadioBuses`; the engine), so it
is shared contract, not scheduler-only. A ratchet like `RecordsSeamTest` guards `engine` against `source`/`decode`,
starting from what it imports now.

**Step 1, 2026-11-07 (radar `feat/sched-seam1`):** `SdrSession`, `RadioId`, `BandArbiter`, `SdrDevices` and
`RspTcpSelector` (a closed group, no station imports) moved to `radio`. `engine` now names `source` in 6 files, not 15:
`EngineSourceConfig` (the composition root, excused), `Engine` and `AsyncPlaces` (the trackers), `ContinuousSessions`,
`ReceiverControl`, `SatCaptureScheduler`. `EngineSeamTest`: that list only shrinks, `radio` names no part, and
`source`/`decode` never name `engine`.

**Steps 2-4, 2026-11-07/08 (radar #1214, #1215, `feat/sched-seam4`): the scheduler seam is done.**
- Step 2: `ContinuousBands` to `radio` (the AIS channels are the stated fact; the dial and the demod's offsets derive
  from them); `radio.FileSession` for the pass recorder's file; `Places` to `model`.
- Step 3: `ReceiverControl` reads the inherited gain and notch through `feed.Gain`/`feed.Notch`
  (`bandAt`/`ifgrAt`/`rfgrAt`, `rfAt`/`dabAt`).
- Step 4: the engine's tick stops holding 20 receivers. `TickPublisher.InOrder`, built in `EngineSourceConfig`, copies
  each receiver's readings into the store in the tick's own order; the sonde the mount follows comes through
  `feed.SondeTrack`; `AircraftSource`/`VesselSource` moved to `feed`. AIS weather is passed on by the AIS receiver's
  own publisher: `AisMeteo` belongs to the sealed `decode.AisMessage` and cannot leave `decode`.
- `EngineSeamTest` is now a rule: only the composition root in `engine` names `source`/`decode`.
- Four test gaps the reverts found on the way, each closed: the inherited gain and notch on the panel; the AIS
  weather, ADS-B rate and NAVTEX readings reaching the store.

### The module split, mapped (2026-11-08)

Both seams are rules now, but the package graph still has three cycles. Measured from every mention, imports and
qualified names alike: `geo` <-> `model`, `dto` <-> `entity`, and one of 12 packages (`source`, `decode`, `engine`,
`settings`, `tracking`, `mount`, `servo`, `history`, `repository`, `track`, `service`, `bandmap`). Gradle modules
cannot form a cycle, so the split needs every edge that runs against the module order cut first.

| Module | Packages | May depend on |
|---|---|---|
| core | `model`, `geo`, `feed`, `radio`, `atmosphere`, `sigmf`, `select`, `orbit`, `identity` | - |
| capture | `source`, `decode` | core |
| settings | the stores in `settings` (bookings, radio directory, receiver/station settings) | core |
| state | `tracking`, `mount`, `servo` | core, settings |
| scheduler | `engine` without its composition root | core, settings, state |
| records | `controller`, `service`, `history`, `repository`, `track`, `entity`, `dto`, `alerts`, `bandmap`, `photo`, `client`, `map` | everything except capture |
| app | `Application`, the composition roots (`EngineSourceConfig`, `StoreConfig`, `HistoryConfig`, `TrackConfig`), the `*Wiring` classes | all |

The cycles inside one module (`geo`/`model`, `dto`/`entity`, `decode`/`source`, `repository`/`history`/`track`) need
nothing. The edges that run against the order, and the cut for each:

| Edge | What it uses | Cut |
|---|---|---|
| `tracking` -> `source`, `decode` | `StateStore.updateMeteo(AisReceiver.MeteoReading)`, `AisMeteo` | a plain meteo record in core; the AIS publisher converts |
| `source` -> `tracking` | `PositionVelocityFilter` (pure maths) | to `geo` |
| `history`, `track` -> `engine` | `SnapshotListener` | to `feed` |
| `engine` -> `service` | `SatellitePassService` (pass table, resolve), `GeocodeService` | `feed` interfaces, the services implement them |
| `engine` -> `bandmap` | `Entry`, `OwnChannels` (the band-map row types) | to core |
| `mount` -> `engine`, `engine` -> `mount` | `SdrAutoDetect`; `MountProperties` (in `StoreConfig`, the root) | `SdrAutoDetect` to core; the root moves to app |
| `tracking` -> `engine`, `settings` | `StatePersistence`, `ReceiverStatePersistence` use `EngineProperties`, `ReceiverControl`, stores | persistence is wiring: to app |
| `settings` -> `source`, `decode`, `engine`, `repository` | the `*Wiring` classes, `Rs41FixStore`, `Uvb76*`, `RfSettingsReady` | wiring to app; capture-owned stores to capture |
| `source` -> `settings` | `SdrGainPolicy` uses `BandSettingWiring` | invert: the wiring sets a policy writer |

Each cut is its own PR with a ratchet like the seams' (a package-order test from the same mention scan), then one
PR moves the packages into Gradle modules and lets the compiler hold the order.

**Step 1 (radar `feat/split-1`):** `ModuleOrderTest` holds the order above; 20 file-level edges listed against it, the
list only shrinks. `orbit` and `identity` turned out to import nothing but core while the scheduler and the capture
both use them, so they are core. `PositionVelocityFilter` moved to `geo` and `SnapshotListener` to `feed`.

**Steps 2-7, 2026-11-08 (radar #1218-#1222, `feat/split-7`): the module order holds, and the compiler holds it.**
- Step 2: the scheduler names no records package (`Entry`/`OwnChannels` to `model`, `AsyncPlaces` to `service`,
  `EngineController` to `controller`, `feed.Satellites` for the pass table).
- Step 3: the AIS weather the store shows is `model.MeteoReading`.
- Step 4: two javadoc links, `LiveSettings` to `radio`, `UvbRecordings` to `feed`, three wiring classes counted as the
  app's.
- Step 5: the RS41 fix contract (`feed.Rs41Fixes`) speaks core records; `Rs41FixWiring` hooks the store up; the launch
  height helper is `Geodesic`'s.
- Step 6: the UVB-76 transcripts reach the recognizer through `feed.SpeechToText`; `ModuleOrderTest` became a rule.
- Step 7: one Gradle source set per module over the same `src/main/java`, each seeing only the modules before it;
  `compileModules` runs in `check`, so the gate fails a class that names a later module. The jar is unchanged. The
  compiler found three edges the mention scan could not see (a same-package simple name into a wiring class; the root
  package's `HardwareSwitch`, now `radio`'s; `IqController` taking `IqRecordingWiring`, now `feed.IqRecordingControl`).
- Two flaky tests the gates found, each reproduced and fixed: a gain seed leaking between test classes
  (`ReceiverDefaultsTest` cleaned up with a `parse("")` that does nothing), and a race between a receiver change and
  its announcement (`ScheduleRunnerWiringTest`).

Next: separate Gradle subprojects (and their own jars) when the first part runs as its own process; the source sets
already hold the boundaries those subprojects will have.

## The shape

Box (rsp_tcp) -> decoder service (read path, decoder, its captures) -> records. Plan 106's scheduler says
who
holds a radio; the service opens the capture directly when it holds the lease. radar keeps the page and the history.

- A process per decoder service has its own heap, GC and crash, so GC is no longer shared between 100 readers.
- A JVM starts in seconds, too slow to start per FT8 slot: a service stays up and opens captures on need.
- A machine runs the subset it is configured for.

## Not decided

- **Pinning.** Bench beside a gate, 480,000 hand-overs: all cores 209 stalls over 1 ms, P cores 119, E cores 83, with
  the load falling across the runs and the gate not kept off those cores. Not proof either way. It says nothing about a
  decoder's DSP.
- **The gate on all cores** is a standing rule. Reserving cores for radios on a host that also builds would change it:
  the operator's call.

## Steps

### 0. The target, in numbers (operator)

See the questions below. No code.

### 1. What each decoder costs

Replay the committed captures through each of the 24 session classes, one at a time, on a P core group and on an E core
group (`taskset`, offline). The result is a table: CPU per decoder per core class, and whether it keeps up on each. This
sizes everything after it, and shows which decoders actually need P cores.

**First cut, 2026-11-08 (radar `DecoderCostBench`, `feat/decoder-cost`).** Each band's committed capture, resampled
to its live rate and looped to 120 s of air, through its demod at its live offset after a 10 s warm-up; one run pinned
to the P cores (0-7, 4.5 GHz), one to the E cores (8-15, 3.6 GHz), on the workstation beside the live station.

| Band | Rate | P core | E core | E/P | Real time on E |
|---|---|---|---|---|---|
| DMR | 768k | 4.65% | 6.52% | 1.40 | 15x |
| FLARM | 500k | 3.79% | 6.11% | 1.61 | 16x |
| VOR | 192k | 2.73% | 4.90% | 1.79 | 20x |
| RTTY | 96k | 2.56% | 3.59% | 1.40 | 26x |
| NAVTEX | 250k | 1.32% | 2.15% | 1.63 | 47x |
| ACARS | 768k | 1.09% | 1.98% | 1.82 | 51x |
| VLF | 96k | 0.98% | 1.59% | 1.62 | 63x |
| APRS | 192k | 0.56% | 1.00% | 1.79 | 100x |
| HF DSC | 96k | 0.42% | 0.83% | 1.98 | 120x |
| DSC | 192k | 0.40% | 0.65% | 1.62 | 154x |
| RBU | 96k | 0.27% | 0.41% | 1.52 | 242x |
| WFAX | 96k | 0.22% | 0.38% | 1.73 | 265x |
| MSF | 96k | 0.16% | 0.23% | 1.44 | 435x |
| DCF77 | 96k | 0.15% | 0.22% | 1.47 | 447x |
| WSPR | 96k | 0.08% | 0.14% | 1.75 | 740x |
| LORAN | 96k | 0.05% | 0.10% | 2.00 | 959x |
| **16 bands** | | **19% of a core** | **31% of a core** | **1.59** | |

What it says: no demod here needs a P core - each keeps up on an E core at 15x real time or better, and all sixteen
together take a third of one E core; an E core costs 1.4-2x a P core. What it does not say yet: the IQ read path,
read-ahead, recording and the spectrum tap are not in it; WSPR's (and FT8's) slot decode runs at the slot's end, not in
the chunks, so their rows understate them; several captures sit off the live offset and decode nothing, so their rows
are the front end alone. Second cut: RS41 (8 MS/s, channelised), ADS-B (2 MS/s), AIS, SARSAT, FT8, UVB-76, each with
its own driver, and one row per band through its whole session (read path included).

### 2. A rig with simulated radios

A test harness: N fake radios feeding real recorded IQ at the real rate into one JVM, N = 10, 25, 50, 100, in the mix
from step 0. No hardware. Runs on a host the operator picks, never beside the live station at full size.

Measured at each N: reader stalls, chunks spilled and dropped, decoder lag, GC pauses, Valkey latency. Then, on the same
rig: the ring with and without reused buffers; G1 against generational ZGC; core groups on and off. Each of these is
adopted only on a measured gain. The knee in N says how many radios one host carries.

### 3. One decoder as a service: the pilot

One narrow decoder, from a network radio, as a service on a machine, side by side with radar and compared on the same
air:
same bulletins, stamps within a slot, no more losses. It needs plan 106's lease (step 1b onward), so that two owners
never open one box. Measured: idle JVM size, CPU against step 1, connect-to-first-sample. This sets the template for the
rest.

Then the others one at a time, heaviest last. The read path (`IqReadAhead`, `AirStamp`, the spill, rsp_tcp's client)
goes with them. The common library was removed from all services in March, so one repo and one jar, run per decoder,
keeps one copy of it (question 6). Waterfall, audio and IQ recording read a capture in process today, and
each needs an answer in this step: stay in the service, or a stream out of it.

### 4. Budget, pinning, machines

No fixed number of radios or hosts (operator, 2026-11-07: "numbers can grow, some hosts will have a few, some more"):

- What a service may use comes from steps 1 and 3: never one size for all, and 100 is not a limit built into anything.
- A capture past what its machine carries is refused and visible, rather than slowing every other capture.
- Core groups only if step 2 shows stalls that cost samples: the thread sets its own affinity to a group, never to one
  core, `sched_setaffinity` through FFM.
- Adding a radio is a row in the directory; adding a machine is a service coming up on it. No code change, no redeploy
  of
  the others.
- Nothing assumes radios are evenly spread: the page and the budgets go per machine. Valkey per machine, not one for
  all.
- Control over plan 106's MQTT. Records: plan 106 sends them to the cluster's Kafka, which radar on aqua can still do.

### 5. Running 100 by hand is not an option

- The page: radios grouped by host and band, exceptions first, no row-by-row reading needed.
- Boxes: health from plan 106's `sdr/<radio>/health`, a wedged box restarted by its agent, a report of what was lost.
- Database writes per second measured at the rig's N, batched if the table shows they must be.

## Open questions for the operator

1. **Which radios?** Mostly from the network; SDRplay and RTL-SDR for sure (operator, 2026-11-07). Still open: other
   kinds,
   and the link to each. The radio does not set the load: a row's rate does. An SDRplay running RTTY is 96 kS/s, and an
   RTL-SDR tops out near 2.4 MS/s at 8 bits, 4.8 MB/s. radar's network client speaks rsp_tcp, so RTL-SDR over the
   network
   needs checking in step 0.
2. **What mix?** How many wideband (8 MS/s) and how many narrow (under 250 kS/s). Whether every radio runs at once, or
   they take turns by calendar.
3. **Which machines?** Hosts differ and grow (operator, 2026-11-07). How many in the next stage, and what are they?
4. **Growing how?** No fixed end, so stages by need (operator, 2026-11-07). Roughly how many in the next stage?
5. **Should every band still run one radio, one capture, one decoder at 100?** A wideband capture with many decoders in
   it would need far fewer radios, but the operator's rule of 2026-11-06 says no. Recorded here only so that the rule is
   held on purpose.
6. **Repos:** a single repo for now (operator, 2026-11-07).
7. **Do plans 105 and 106 still stand as written?** 105 puts NAVTEX on the pi4; 106 runs the scheduler there.
