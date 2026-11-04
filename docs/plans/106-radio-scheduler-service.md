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

## Step 2 — MQTT on the pi4

- Mosquitto on the pi4, next to the tuner; LAN only; a login per service and an ACL per topic.
- Topics (MQTT 5, QoS 1, handlers idempotent):
  - `radio/<radio>/lease` (retained) - who holds the radio and until when. Published by the scheduler only.
  - `radio/<radio>/request` - a row asks for a radio (receiver, priority, wanted until); request/response by
    correlation id, with a message expiry so a stale ask never runs late.
  - `rx/<receiver>/state` (retained, Last Will `offline`) - listening, ended, off.
  - `sdr/<radio>/health` (retained, Last Will) - rsp_tcp and the tuner, from the agent on the pi4 (initHw errors,
    restarts).
- Broker down: a holder keeps its lease to its expiry; nothing new is granted.

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
- It owns the radio directory, the calendar (bookings and their outlets), and the leases; it decides, the receivers
  ask. The windows, holds and stays become lease requests and renewals from the receiver side.
- Runs on the pi4 (so NAVTEX does not depend on the workstation); radar's receivers on the workstation's own radios are
  its clients too.
- radar's `ScheduleRunner` / `BandArbiter` / per-row `PeriodicWindowScheduler` loops are replaced by a client of the
  service, one row at a time, RTTY first.

## Open questions for the operator

- The service on the pi4 also deciding for the workstation's own radios - or one scheduler per host?
- Calendar UI: stays in radar's web UI (talking to the service), or moves with the service?
