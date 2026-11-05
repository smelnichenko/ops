# Plan 107 — radar: a decoder that falls behind never drops samples (Disruptor ring, Valkey overflow)

**Status:** draft 2026-11-05. Operator's direction, 2026-11-04: "the solution would be data accumulation and decoding
at free moment"; "use cache service ... for undecoded data instead of dropping"; "use rotating wheel pattern for
incoming data without synchronization"; "disruptor, exactly"; "use valkey, there is a plenty of ram".

## Why

A decoder slower than its radio loses samples. `IqReadAhead` (radar `source/IqReadAhead.java`) drains the driver on a
thread of its own into a lock-guarded `ArrayDeque` half a second deep (`SoapySdr.rawStream`: `wireRate * 4 / 2`
bytes); a consumer further behind than that loses the OLDEST chunks, marked "demod fell behind the read-ahead". Measured:
RS41 at 8 MS/s under a gate on 2026-10-31 dropped 16 MB chunks repeatedly (537 in one report) - each a sonde frame or
more gone. The gate now runs on every core (operator 2026-11-04: no core kept for RS41), so the next heavy build costs
RS41 the same way.

The queue is short on purpose today: everything downstream stamps time as it READS, so a consumer far behind the air
would stamp wrong times. Decoding later therefore needs the sample's own time carried with it - that is the hard part,
not the buffer.

## Already done (plan 106 neighbourhood, 2026-11-05)

- IQ RECORDING is off the reader thread (radar #1169): `AsyncTake`, a Disruptor single-producer ring and a writer
  thread per capture; a stalled disk costs the recording a marked gap, never the reception. The same library and the
  same discipline (one producer, no lock on the reader's path, close from any thread as a flag) carry over here.

## Design

1. **The read-ahead becomes a Disruptor ring.** `IqReadAhead`'s `ArrayDeque` + `ReentrantLock` becomes a
   single-producer `RingBuffer` (the driver's reader thread publishes, the demod consumes): preallocated slots, no lock,
   no allocation in steady state. Same depth as today at first (half a second); no behaviour change beyond the lock.
2. **Each chunk carries its sample time.** The reader stamps every chunk with the capture's sample index and the
   instant of its first sample (driver timestamp where the driver gives one, else the read instant minus what the
   driver still held). `IqStream` exposes it; decoders that stamp time take it from the chunk, not from the wall clock.
   Adopted decoder by decoder (RS41 first, then the others that file timed records); a decoder not yet adopted keeps
   today's short ring and today's drop-oldest, so nothing gets WORSE before it is ported.
3. **Overflow goes to Valkey, not to the floor.** When an adopted decoder's ring is full, the reader appends chunks to
   a per-capture Valkey Stream (`radar:iq:<captureId>`, XADD with the chunk's sample index and time) instead of
   dropping; once spilling has begun every chunk goes there until the consumer has drained it, so the order is the
   radio's. The consumer drains the ring, then the stream, then the ring again. A capture's stream is deleted when the
   capture's decode has caught up or the capture is closed and drained.
4. **Bounded, and never blocking.** A per-capture and a station-wide byte budget (Valkey `maxmemory` set, policy
   `noeviction` for this keyspace in its own logical DB). Over budget, or Valkey down: today's drop with the gap marked
   - the reader never waits on Valkey. RS41 at 8 MS/s is 32 MB/s: one minute behind is ~1.9 GB.
5. **Live outputs say they are late.** A record decoded from the backlog carries its sample time; the panel and any
   push (Telegram, the reception log) show when it was on the air, and the panel shows each decoder's backlog depth.

## Steps (one PR each, failing test first, revert checks, gate, test-quality audit)

1. **DONE 2026-11-05 (radar #1172, live):** each running capture's decoder lag and drops on the recent-tunes card
   ("decoder 0.3 s behind · 8 ms dropped"; `/api/sdr/opens` `behind_s`, `dropped_s`) - the measure the rest is judged by.
2. Sample time on every chunk through `IqStream`; RS41 stamps frames from it (a test feeds a capture whose consumer
   stalls 10 s and checks the frame times are the air's, not the read's).
3. The read-ahead on a Disruptor ring TOGETHER with the Valkey spill, for decoders adopted in step 2 only.

   **Why not the ring first (found 2026-11-05, before writing it):** a single-producer ring cannot drop its OLDEST
   chunk - only the consumer advances past a slot - so a ring alone drops the NEWEST. After a long stall the decoder
   would then resume on air as old as the stall (10 s after a 10 s stall) and, stamping time as it reads, file it ten
   seconds wrong; today's drop-the-oldest leaves it the newest half second. With sample time on every chunk (step 2) the
   newest end is the right end - and in this step it is spilled to Valkey, never dropped, in the radio's order.

   Budgets and the Valkey-down fallback as in the design (tests: a stalled consumer loses nothing within budget and
   decodes everything in order with the air's times; over budget the gap is marked; Valkey down never blocks the reader).
4. Adopt the other timed decoders (NAVTEX, RTTY, ADS-B/AIS after plan 106's lease work, the slot-aligned FT8/WSPR).

## Open questions for the operator

1. The Valkey budget for undecoded IQ: per capture and station-wide (17 GB of RAM free on the station today).
2. How late may a decode be? RS41 telemetry an hour late is still a flight track; a NAVTEX warning posted to Telegram
   an hour late may mislead. Per decoder, or one bound?
3. Order of adoption after RS41.
