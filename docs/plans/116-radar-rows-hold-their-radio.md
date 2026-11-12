# Plan 116 — radar: a row holds its radio while it is on (the window scheduler goes)

**Status:** approved 2026-11-12; PR 1 next. Decisions below are the operator's of 2026-11-12.

## Why

Every radar row runs in fixed windows (`PeriodicWindowScheduler`, mostly 300 s). At each window's end the capture is
closed and the same one opened again, even when nothing else wants the radio: ADS-B on the local SDRplay and UVB-76 on
the pi4 reopen every five minutes. Holds, stays and keep-open patches were piling onto that loop. Operator,
2026-11-12: "windows scheduler is crap and needs redesign" and "no 5/whatever min reconnects!".

The inventory of everything the six schedulers decide, with the reason for each, is in radar
`scratchpad/m5/scheduler-inventory.md` (2026-11-12). It found that the window end's one real job is letting a waiting row
onto a shared tuner, and that rows practically never share a tuner now: switching a row on switches its tuner mates off.

## Decisions (operator, 2026-11-12)

1. **The holder keeps its radio** while its row is on. No windows, no time-slicing, no turns. **A manual switch
   overrides the schedule**: a row switched on by hand beats a booking, and a later hand switch takes the tuner (its
   mates go off, as today).
2. **No rotation.** RTTY, WFAX, HFDL and VOR each listen to one station: the pinned one, or the first.
3. **DCF77 and MSF listen continuously**: no close-on-decode.
4. **SAT-REC is a normal row**: no rung, no automatic booking of passes.
5. **NAVTEX: 518 and 490 kHz are outlets** picked in its settings, like RTTY's DDK stations; no timetable hops.
6. **WSPR listens on one band**, chosen in its row, like FT8 and FT4; no day/night switch.
7. **VLF listens continuously**: no 60 s every 15 minutes, no daylight gate.
8. **Nothing reopens on a timer, ever.** A capture closes only when:
   - its row is switched off;
   - a manual switch, or a booking, takes its tuner;
   - a setting changes that needs another tune (an outlet, a band, the radio);
   - its reader dies, and then it reopens after `ReopenBackoff` (5 s doubling to 300 s).

## The model

**One `RowRunner` per row** replaces `PeriodicWindowScheduler`, `NavtexScheduler`, `TimeSignalScheduler`,
`VlfScheduler`, `SlotAlignedScheduler` and `SatCaptureScheduler`.

- **Listening:** a row listens while it is switched on, or booked with no row on its tuner switched on by hand (the
  hands rule, as today). Then it claims its radio and holds the capture.
- **Events, not ticks:** switches, booking edges, settings that need a re-tune, a dead reader, and a lost claim each
  wake the row at once. The poll survives only as a safety net for a missed event; it decides, it never reopens.
- **Turns:** gone. A claim on a held radio waits; the holder is never asked to let go by an equal claim. The only
  displacement is the operator's: a later hand switch (`switchSeq`), whose "one receiver per tuner" switches the
  holder's row off anyway.
- **Rungs:** gone. MANUAL/SCHEDULED only mattered for two listening rows on one tuner, which the hands rule and one
  receiver per tuner already prevent.
- **Slot-aligned decoding** (FT8, FT4, WSPR) stays inside the session: a held capture is cut into UTC slots, as FT8
  already does ("no reconnects", 2026-08-21). The scheduler no longer opens on the grid.
- **What each reopen used to reset, now continuous:**
  - VOR, RBU and WFAX: each measurement's length becomes the row's own constant (VOR 55 s, RBU 70 s, WFAX 670 s:
    today's `window + TICK_S`), not the scheduler's window.
  - UVB-76: the buzzer detector's floor rolls over the stream instead of starting fresh per capture.
  - NAVTEX: its slot bookkeeping no longer depends on a capture ending at the slot grid.
- **Unchanged:** `ReopenBackoff` after a dead reader; the SDRconnect handover; the radio directory and per-row radio
  moves (a move re-tunes); booked pins and the held-settings rule inside a booking; the IQ recorder (a capture held for
  days is recorded as a ring, #1260).

## Removed

- `holdWhile`, `holdYieldsToWaiting`, the per-row hold switch (nothing to hold past: no window end).
- `stayWhile`, `othersWaiting`, the turn machinery in `BandArbiter`/`RadioLeaseBook`, the MANUAL/SCHEDULED rungs.
- Rotation: VOR's, RTTY's, WFAX's and HFDL's turn counters, RS41's centre sweep, WSPR's band choice, NAVTEX's hops.
- DCF77/MSF close-on-decode; VLF sampling and its daylight gate; SAT-REC's pass windows.
- Stale comments and docs the inventory lists (§7.16: the CAPTURE/PASS/WINDOW ladder, "parks 1090/162", SAT-REC
  exempt, DSC "re-arm").

## Steps (one PR each, radar; each with tests that fail first, revert checks, full review, gate)

1. **`RowRunner` for the single-station rows**: ADS-B, AIS, UVB-76, LORAN, ACARS, APRS, FLARM, DMR, DSC, DSC-HF, RBU,
   SARSAT, RS41. Holds go. Whole-chain test: a row held for simulated hours never reopens; it closes only on the four
   events above.
2. **The rotating rows to one station**: RTTY, WFAX, HFDL, VOR. Measurement constants for VOR, RBU, WFAX.
3. **The other schedulers' rows**: NAVTEX (518/490 outlets), DCF77, MSF, VLF, WSPR (one band), FT8, FT4, SAT-REC. The
   six schedulers are deleted.
4. **The arbiter without turns and rungs**, and the stale docs.

UI changes (each a rendered sample for the operator's OK before it ships): NAVTEX's outlet picker, WSPR's band
picker, the hold switch removed from the rows that had it.

**Then plan 106 step 3e** moves the lease book to `radio-scheduler` on the radio's host, row by row. Its protocol gets
simpler: no rungs, no turns; a holder renews while its reader gets samples (liveness), a later hand switch displaces.

## Decided after the draft (operator, 2026-11-12)

- **Go.**
- **SAT-REC switched on records continuously** on its band, like any other row.
- **An unpinned former rotator listens to the first station**, as today: DDK2 (RTTY), DWD 7.88 MHz (WFAX), the first
  HFDL cluster, TLL (VOR). The existing pin changes it.
