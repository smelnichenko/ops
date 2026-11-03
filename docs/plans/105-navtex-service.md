# Plan 105 — NAVTEX as its own service and web UI, on the pi4

**Status:** draft 2026-11-03, for the operator's review. The decisions below were made by the operator on 2026-11-03:
the pi4's one tuner is SHARED (no second SDR), the code goes to a new repo `schnappy/navtex`, and the history, the
Telegram publishing and a public read-only part (for navtex.ee) move with it.

One PR at a time, each with a failing test first, revert checks, the repo's gate, a PR, merge, and a check on the
running box. No test post ever goes to a public channel.

## Why

NAVTEX is the part of the radar station that serves other people: Estonian and Baltic maritime safety broadcasts,
already republished to a Telegram channel. It should run on its own, on the pi4 next to the antenna, and later be
reachable from outside as navtex.ee. Today it is a bean inside the radar app on the workstation.

## What NAVTEX is in radar today (surveyed 2026-11-03)

- **Code, NAVTEX-only (~4.8k lines):** `NavtexRxProcess`, `NavtexDemod`, `NavtexReceiver`, `NavtexSlots`,
  `NavtexScheduler`, `NavtexDecoder`, `NavtexMessage`, `NavtexText`, `NavtexStations` (+ `navtex/stations.json`),
  `NavtexConsensus`, `Ccir476`, `NavtexSymbolController`, `NavtexSlotEntity`/`Repository`, `NavtexAlertService`.
- **Shared code it needs:** the rsp_tcp client and IQ front end (`RspTcpIq`, `RspTcpProtocol`, `Hdr`, `IqShift`,
  `IqResample`, `IqFront`, `IqStreams`, `SdrSession`), `SdrGainPolicy`, `LiveSettings`, `RttyCopyQuality` (consensus),
  `ReceptionLog`, `TelegramClient` and the alert send-once store. Not `Fft`, not `Baudot`.
- **Data:** rows with `receiver='NAVTEX'` in the shared `reception` table, `navtex_slot`, `alert_sent` rows with
  source `navtex`, the NAVTEX band target and its Telegram account (token and chat are operator data in the DB).
- **UI:** `NavtexCard` on Traffic, signal and posting on Receivers, the NAVTEX rule source on Alerts, the schedule.
- **Tests:** 36 `Navtex*` test classes and ~8.6 MB of fixtures (Kiwi 518/490 kHz, station capture, slot symbols).
- **Radio:** pi4-A and pi4-C are the SAME tuner (`rsptcp://192.168.11.7:1234`, antenna A or C), single-client. NAVTEX
  gets it in six daily calendar bookings, xx:46-xx:02 UTC; RTTY's bookings hold it the rest of the day.
- **pi4:** Pi 4B, 4 GB, 4 cores, 235 GB SD, Raspberry Pi OS trixie aarch64, SDRplay RSPdx-R2 on USB, patched
  rsp_tcp from radar's `receiver` playbook.

## The tuner, shared

One tuner, two services. The pi4's rsp_tcp stays the only thing that talks to the RSPdx; both services are its
clients, and its single-client lock is the mutex. The windows are a table both sides hold:

- **NAVTEX's windows:** the six daily xx:46-xx:02 UTC slots (Tallinn F at xx:50 and Pinneberg's 490 kHz around it),
  configured in the navtex service and published by it at `GET /api/tuner/windows`.
- **radar** reads that table instead of its own NAVTEX bookings, and releases pi4 for each window: a calendar entry
  for an EXTERNAL holder, which claims the radio and opens nothing. Outside the windows radar's calendar is as
  today (RTTY).
- **The handover** has slack: the navtex service connects from xx:46:00 and retries until rsp_tcp accepts it (radar
  lets go when its booking starts); radar retries from xx:02:00 the same way. A side that finds the port busy past
  its slack logs it, and a gauge says so.
- **Later, not now:** if NAVTEX should listen around the clock, the answer is a second SDR - one choice changes,
  nothing else in this plan.

## PRs, in order

1. **Repo `schnappy/navtex`.** Java 25 / Spring Boot 4, Gradle, Liquibase XML, a Taskfile with `task gate`. The
   decoder carried over with its tests and fixtures, unchanged, and gated before anything else is added: the same
   fixtures decode to the same bulletins as in radar (`DecodeQuality` baselines copied).
2. **Receiver.** The rsp_tcp client and IQ front end, `NavtexReceiver`, the slot history, Postgres on the pi4 (local
   install, as the appliance image already does). The window scheduler from "The tuner, shared". A capture fixture
   replayed end to end: IQ in, bulletins in the DB.
3. **Web UI.** React + Vite in the same repo, served by the service.
   - Public, read-only: latest bulletins by station and subject, a bulletin page, search, history by day, station
     list, signal now. No settings, no tokens, no IQ.
   - Operator: signal and slots, gain, windows, Telegram settings - on a separate path, LAN-only, behind auth.
4. **Telegram.** `NavtexAlertService`'s send-once rule moved over with its store. The token stays operator data in the
   service's DB, entered on the operator page. Tested against a PRIVATE test chat only.
5. **Deploy to the pi4.** An Ansible role (`navtex`) run by `task deploy` from the new repo: JRE 25 aarch64, Postgres,
   the systemd unit, the jar built off the Pi. Runs beside rsp_tcp. Memory and CPU measured on the Pi under a window.
6. **radar side.** radar reads `/api/tuner/windows` and books the EXTERNAL holder; its own NAVTEX row stays off.
   Until the cutover, radar keeps its NAVTEX code, switched off.
7. **Cutover** (one window boundary, production change):
   - Export from radar's DB and import into navtex: `reception` rows with `receiver='NAVTEX'`, `navtex_slot`,
     `alert_sent` (source navtex). The commands are shown before they run; nothing is deleted from radar here.
   - Telegram: radar's NAVTEX band target switched off and navtex's switched on in the same step, so a bulletin is
     posted once - never twice, never zero times. The send-once store came over in the import.
   - Checked over the next windows: bulletins in navtex's DB and on the channel, nothing from radar.
8. **Remove NAVTEX from radar.** Code, UI, tests, fixtures. Its old rows are deleted from radar's DB only after the
   operator says so (stateful delete: command shown, explicit OK).
9. **navtex.ee** (when the domain is registered).
   - Registration and DNS are the operator's.
   - The public path goes through the cluster's gateway on ten, which proxies the public read-only routes to the
     pi4 on the LAN. TLS via DNS-01 as for the other hosts. The operator routes are never proxied.
   - The pi4 is never exposed directly.

## Open questions for the operator

- The private Telegram chat for tests: which one?
- Public site language(s): English only, or Estonian and English?
- Retention of the public history: all of it, or the last N days?
