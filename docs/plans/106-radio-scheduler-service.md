# Plan 106 — the radio scheduler as its own service, on events, over MQTT

**Status:** draft 2026-11-04. Operator's decisions on 2026-11-04: the scheduler becomes a separate microservice; it is
event-driven, not a 10 s poll; the transport is MQTT. Goes with plan 105 (NAVTEX on the pi4 shares the pi4's tuner).

## Why

On 2026-11-04 the pi4's tuner failed under RTTY's capture, and RTTY stayed off the air until reset by hand. The radar's
scheduler polls every 10 s: a reader that died was invisible to it, and an off/on switch inside one tick was lost.
Every receiver row runs its own copy of that loop, and the radio's owner is spread over `ScheduleRunner`,
`PeriodicWindowScheduler`, `BandArbiter`, `RadioBuses` and `ReceiverControl` (about 3k lines). NAVTEX moving to the pi4
(plan 105) needs the same tuner arbitrated across two processes, which an in-process arbiter cannot do.

## Step 1 — events inside radar (now, no new service) — DONE 2026-11-04

Merged and live: radar #1156 (a capture whose reader gave up is opened again), #1157 (switches and a reader giving
up are events on the receiver's ticker thread; an off-and-on inside one tick is latched; the 10 s tick is the safety
net), #1160 (a booking on the outlet the capture is already on does not re-open it). A setting that needs a
re-open was an event already (`retuneNow`). Not yet events: a booking's edge and the preemption it brings - found
by `ScheduleRunner`'s 20 s poll, so a booking starts up to 20 s late.

- Every change that decides who holds a radio is an event on the receiver's own single-thread executor, handled at
  once and in order: a switch on/off, a booking's edge, a setting that needs a re-open, a reader that gave up, a
  preemption.
- A switched-off-and-on row is latched: a toggle faster than any tick still re-opens the capture.
- The 10 s tick stays as a safety net only.
- Tests: each event acts within the same executor turn; a toggle inside one tick re-opens; a dead reader re-opens.

Booking edges and calendar edits as events: radar `feat/schedule-edges-as-events` - the runner arms a timer at
the calendar's next start or end (`ObservationSchedule.nextEdgeS`), and every calendar change calls its
`applyNow`. The 20 s poll stays as the safety net.

## Step 1b — the lease decision apart from the sessions (radar, pure refactor)

Today `BandArbiter` (one per radio, `RadioBuses`) both DECIDES who holds a radio and RUNS the sessions (stops the
displaced capture, stops/starts ADS-B or AIS) under one lock. Only the decision can move to a service; the sessions
stay with the process that owns the samples. So, first, inside radar:

- `RadioLeaseBook` (new, `io.schnappy.radar.radio`): one per radio, no `SdrSession` in it. State: the holder
  (claimant, priority, switch order), the asks (priority, first/last asked, patience), the continuous hold.
  Operations, each returning a decision and never touching a device:
  - `request(claimant, priority, switchSeq, patienceMs, nowMs)` -> GRANTED, GRANTED displacing X, REFUSED (holder
    or whose turn it is);
  - `release(claimant)`, `rerank(rungOf)`, `holdContinuous(held)` -> displaced X or nothing;
  - `holder()`, `othersWaiting()`.
- `BandArbiter` keeps its public API and its lock, asks the book, and carries out the answer: stop the displaced
  capture, free the continuous session, start the new one. Behaviour unchanged - the existing `BandArbiter*` and
  `RadioBuses*` tests are the regression net, plus the book's own tests (turns, patience lapse, switch order,
  displacement, hold).
- The book's state is what `radio/<radio>/lease` (retained) will carry, and `request` is
  `radio/<radio>/request`'s handler: step 3 moves the book, not a rewrite of it.
- **ADS-B and AIS become ordinary bands here** (operator 2026-11-05: the continuous sessions "убрать", folded into
  this step rather than a PR of their own that this refactor would rewrite): no continuous hold in the book, no
  session slot in `BandArbiter`; they ask for the radio, are switched and booked like every other band, and lose it
  to a hand switch on the same tuner like every other band. The book above is written without `holdContinuous`.

### Step 1b, mapped (2026-11-08)

What still runs on the continuous model, measured: `BandArbiter`'s continuous slot (two factories, the band, park,
hold, rebind, running, starts, `captureOnContinuousRadio`, `dedicatedOverlayRadio`), `ContinuousSessions` (projects the
ADS-B/AIS switches onto each radio), two `ContinuousStallWatchdog`s, `RadioBuses`' continuous bases (`Lease.onContinuous`,
`moveObservation`, quarantine), `RadioSources`' observation slot (`CONTINUOUS_ROWS`, `deviceFor(row, continuous)`,
`continuousDevices`), the store's `sdrParked`/`sdrHeldBy`/`activeBand`, and the page's `sdr_status`/`sea_status`. About
7,300 lines of main code and 19 test classes touch it.

A live symptom of the coupling (2026-11-08 14:25): RTTY taking pi4-C - AIS's radio - stamped "paused - RTTY has the
radio" on the air status while ADS-B received ten aircraft on the sdrplay. The overlay port marks the air radio held
whenever a capture lands on any radio a continuous row is assigned to.

The cuts, each its own PR, each behaviour-checked by the existing tests plus its own:

| PR | What | Why first / what it frees |
|---|---|---|
| 1 | A local radio that goes silent ends its stream: SoapySDR read timeouts for 10 s are an end, as rsp_tcp's `SO_TIMEOUT` already is | The watchdog exists for the 2026-08-22 stall (a local read delivering nothing for 105 min). `DemodProcess` and `AisRxProcess` already reopen on a stream end, and a staying window row reopens on a reader that gave up - so the fix belongs in the read path, for every row, and the watchdog has nothing left to do |
| 2 | ADS-B and AIS become `PeriodicWindowScheduler` rows on `overlayPort(row)`, their sessions the same `DemodProcess`/`AisRxProcess`; `ContinuousSessions` and both watchdogs go; the mount's domain is derived from which row listens (ADS-B first); the port stops setting `sdrHeldBy` | The behaviour change the operator decided (2026-11-05): switched, booked and preempted like every band. The continuous slot is then never started (radios are built parked) |
| 3 | `BandArbiter` loses its continuous slot; `RadioBuses` loses bases, `Lease.onContinuous`, `moveObservation` | Dead after 2 |
| 4 | `RadioSources`' observation slot, `CONTINUOUS_ROWS`, the `continuous` flag, `overlay-device` go (ADS-B/AIS assignments migrated to explicit first); the store's `sdrParked`/`sdrHeldBy`, `sdr_status`/`sea_status` and `Engine.radioStatus` go, the page reading the rows' own status | Dead after 2-3 |
| 5 | `RadioLeaseBook` out of the then-plain `BandArbiter` (the pure refactor above) | Written once, without the continuous hold |

**Progress (2026-11-08):**
- PR 1 #1233 LIVE 14:57: a silent local radio ends its stream (`SoapySdr.Silence`, rsp_tcp's 10 s).
- PR 2 #1234 LIVE 16:09: ADS-B and AIS are ordinary window rows. An independent review found two critical problems
  before it shipped, both fixed: a row's claim and its session could resolve different radios, and a radio could get
  a second arbiter. It found three warnings too, also fixed: a staying capture never yielded, a directory edit never
  re-tuned a staying row, and the status read a bare "stopped". The decode-stall watch is kept as `DecodeStallWatchdog`
  over the row's capture: it fired 123 times on 10-02..05 with samples flowing.
- Found on the way, #1235 LIVE 16:44: a booking's outlet is set before the booking is announced. RTTY's capture was
  re-tuned 1 ms after opening, at every booking edge.
- PR 3 #1239 LIVE 19:52: the arbiter's continuous slot and the registry's continuous bases are deleted; one
  arbiter per radio, every band claims it the same way. (#1236 held the pre-rebase commits; the force-push was
  blocked, so the rebase went up as #1239.) Its review found a shutdown order bug (a destroyed registry threw in a
  scheduler's stop), fixed in the PR.
- Found in PR 3's review, #1240 LIVE 20:36: a band's claim and its session each looked up the row's radio, so a row
  moved between the two claimed one radio while its session opened another. The radio is now read once per capture.
- PR 4a #1248 LIVE 2026-11-09 04:02: the observation and overlay slots, `CONTINUOUS_ROWS`, the `continuous` flag,
  `overlay-device`, `ais-device` and the slot migration are gone. A row opens its assignment or the boot radio
  (`sdr-device`). All 26 rows opened the same radio before and after; `overlay-device` is out of the live config.
- PR 4b DROPPED 2026-11-09: it gave the ADS-B and AIS rows named status lines, a special path for two bands. Instead:
  #1250 LIVE (no special rows: `alwaysOnRow`, `STAYING_ROWS`, `DecodeStallWatchdog` and `quietSeconds` gone), and #1251
  (CI green, not merged): `sdr_status`/`sea_status`/`sdr_parked`, `AirRows`, `Engine.radioStatus` and the top-bar lines go.
- PR 5 #1249 LIVE 2026-11-09 04:41: `RadioLeaseBook` decides who holds a radio with no session in it; `BandArbiter`
  keeps its API and lock and carries the answer out. The `BandArbiter*` tests passed unmodified; 12 of 12 reverts caught.
- #1251 LIVE 2026-11-09 17:27: step 1b is DONE.
- Step 2 LIVE 2026-11-09 17:00 (#1252, deployed with the broker's tasks only; rsp_tcp not restarted): Mosquitto on the
  pi4, no clients yet. Checked on the real broker: anonymous and wrong password refused from the workstation, the four
  logins accepted, ACL as designed, one LAN-only ufw rule, a second deploy changes nothing.

## Step 2 — MQTT on the pi4

- Mosquitto on the pi4, next to the tuner; LAN only; a login per service and an ACL per topic.
- Topics (MQTT 5, QoS 1, handlers idempotent):
  - `radio/<radio>/lease` (retained) - who holds the radio and until when. Published by the scheduler only.
  - `radio/<radio>/request` - a row asks for a radio (receiver, priority, wanted until); request/response by
    correlation id, with a message expiry so a stale ask never runs late.
  - `rx/<receiver>/state` (retained, Last Will `offline`) - listening, ended, off.
  - `sdr/<radio>/health` (retained, Last Will) - rsp_tcp and the tuner, from the agent on the pi4 (initHw errors,
    restarts).
  - `reply/<login>/...` - the answer to a request, on the asker's Response Topic. Each login reads only its own.
  - `data/...` - what the bridge carries to Kafka: bulletins and receptions from radar, `data/sdr/...` health history
    from the agent. The bridge reads only these.
- `<radio>` is one topic level: `RadioId` with no `/`, `+` or `#` (`rsptcp://192.168.11.7:1234` is
  `rsptcp-192.168.11.7-1234`). Directory names like `pi4-A` and `pi4-C` are not ids: they are one tuner.
- Broker down: a holder keeps its lease to its expiry; nothing new is granted.

Decided for step 3 by step 2's review (2026-11-09):

- **A power cut can bring back an old lease.** Retained state reaches the SD card every 5 minutes, so a restart may
  restore a lease that has since moved. The scheduler republishes every lease on connect before it grants anything,
  and a lease carries a generation number that holders check along with `until`.
- **A Last Will is per connection.** Each `rx/<receiver>/state` Will needs its own connection (distinct client id, one
  login), or one process-level liveness topic replaces them; the ACL may change with that choice.
- **The broker needs an alert before step 3 relies on it.** It has no monitoring on the pi4 today: a dead broker
  silently means nothing new is granted. An exporter needs a `$SYS` read login, which the ACL does not have yet.

Open, for the operator before step 3:

Decided (operator, 2026-11-09):

- **NAVTEX is an MQTT client.** Leases replace plan 105's `/api/tuner/windows` and its reliance on rsp_tcp's single-client
  lock. It gets its own login with the client: `navtex`, lease read, request write, its own `rx/` state, health read,
  `data/navtex/#` write, and `RADAR_MQTT_PASSWORD_NAVTEX` in the secret file.

## Hybrid: control on MQTT, data to the cluster's Kafka (operator, 2026-11-04)

- **Control stays local, on MQTT on the pi4:** leases, requests, receiver state, SDR health. Radio arbitration never
  depends on ten, the cluster or a broker restart there.
- **Data goes to the cluster's Kafka** (Strimzi, `schnappy-production-kafka`, one broker, ClusterIP only today):
  NAVTEX and RTTY bulletins, receptions, SDR health history. Consumers in the cluster: the navtex.ee site, Telegram,
  alerts, Grafana, the archive.
- **One bridge** subscribes to the data topics on MQTT and produces them to Kafka (topics keyed by receiver, idempotent
  producer). It runs on the pi4 with Mosquitto persistent sessions, so a cluster outage is buffered and caught up.
- **Kafka gets one external client**, the bridge, write-only: an external listener (address from the Cilium L2 pool,
  TLS, SCRAM user with produce rights on the station's topics only), a NetworkPolicy for it, LAN only. infra/platform
  change, through a full run and review like any production change.
- Kafka's topic naming and retention per data kind are decided in that infra change.

## Step 3 — the scheduler service

- New repo `schnappy/radio-scheduler` (Java 25 / Spring Boot, the MQTT client from Eclipse Paho or HiveMQ).
- Its own SonarQube project from the first commit, in CI like every service: PR test + sonar, main test + sonar + deploy
  (operator, 2026-11-09: every decomposed part gets one; radar itself does not).
- **One scheduler on each radio host, deciding only that host's radios (operator, 2026-11-09).** A lease depends only on
  the machine the radio is on, so a dead host costs its own radios and nothing else. The pi4 is first; the workstation's
  radios get their own scheduler and broker when they move over.
- It owns that host's leases and radio directory; it decides, the receivers ask. The windows, holds and stays become
  lease requests and renewals from the receiver side.
- The calendar (bookings and their outlets) is separate: one small service that asks for leases on behalf of its
  bookings. If it is down, rows already holding a radio keep it; bookings just do not start.
- radar's `ScheduleRunner` / `BandArbiter` / per-row `PeriodicWindowScheduler` loops are replaced by a client of the
  service, one row at a time, RTTY first.

### Step 3, the lease protocol (2026-11-09, from PR 1's review)

The book as moved decided who holds a radio inside one process. Across processes it needs more, so "step 3 moves the book,
not a rewrite of it" no longer holds for these parts:

- **A lease has an end.** `until` (wall clock, epoch ms; the hosts run NTP) is set on every grant and renewal. A holder that
  dies stops renewing and its lease lapses. Holds are short and renewed, so a stale state does not last.
- **Generation.** It rises each time the holder changes, not on a renewal, so a redelivered request is at most one more
  renewal. It
  starts from `(boot epoch << 32)`, the boot epoch being a counter persisted and fsynced once per start on the host's disk:
  a Pi has no RTC, and a counter held in memory or seeded from a retained lease would start below what holders have seen
  after the same power cut. The counter is a `long`: `<< 32` on an `int` does nothing. Holders reject a lower generation.
- **The holder asking again is a renewal**, never a refusal or a displacement of itself. QoS 1 redelivery is harmless.
- **A release names its claimant and generation.** A displaced row's late release changes nothing.
- **Waiters go by rung, then by who waited longest**, then by name so the order is defined. A waiter can withdraw (switched
  off, Last Will), and lapsed asks are dropped so names from messages cannot grow the book for ever.
- **The switch order is the row's.** Each request carries `switchedAt`, when the operator switched that row on (0 if never).
  radar keeps it with the row's saved switch. A scheduler-owned counter was tried on paper and rejected in review: not safe
  to redeliver, lost on restart, grown by names from messages, shared across radios. A future time counts as now. The
  holder's is in the lease.
- **Durations come from messages, so they are bounded:** a hold from 1 ms to 1 hour, patience up to 1 hour.
- **The scheduler publishes the lease whenever it changed**, after any operation: a request can end a lapsed lease on the way
  to any answer. It starts only after the clock is synchronised (`systemd-time-wait-sync`): a lease's end is wall-clock time
  and a Pi boots with a wrong one.
- **After a restart** the scheduler reads the retained leases, restores the live ones under a new generation, republishes
  them, and only then grants. A retained lease can be 5 minutes stale, which the short holds and the generation absorb.

Messages (JSON, QoS 1):
- `radio/<radio>/lease`, retained: `{"holder", "priority", "generation", "until", "switchSeq"}`; holder null while free.
- `radio/<radio>/request`, with MQTT 5 Response Topic `reply/<login>/...`, Correlation Data and a message expiry:
  `{"op": "request", "receiver", "priority", "holdMs", "patienceMs", "switchedAt"}`, `{"op": "release", "receiver", "generation"}`,
  `{"op": "withdraw", "receiver"}`.
- The reply: `{"decision", "displaced", "generation", "until"}`, the decision being GRANTED, RENEWED, DISPLACING, REFUSED,
  RELEASED, NOT_HOLDER, WITHDRAWN, UNKNOWN_RADIO or INVALID. A Response Topic must be under `reply/`, or there is no answer.
- At start the scheduler subscribes to its own radios' leases, publishes a marker on `reply/<login>/settle-<id>`, and treats
  what arrived before the marker as the retained leases. That order is Mosquitto's, not an MQTT guarantee.

Before radar is a client: the scheduler does not yet read `rx/<receiver>/state`, so a row that dies while waiting holds its
place until its patience lapses. radar uses short patience until the Last Will choice above is made. A request sent while
the scheduler restarts is lost: radar times out and asks again.

Before it runs on the pi4: Java on the box, `Requires=` nothing but `After=` the broker, `systemd-time-wait-sync` (decide what
happens if no NTP is reachable after a power cut), a heap cap, and how it is deployed.

PRs, one at a time: the book with leases (no MQTT); the MQTT service against a real Mosquitto; running on the pi4; radar as a
client, RTTY first and switchable back; the calendar service.

## Open questions for the operator

None left for step 3. Decided 2026-11-09: the calendar UI stays in radar's web UI, talking to the calendar service; the
calendar service runs on the pi4 for now, and parts are relocated after the decomposition.
