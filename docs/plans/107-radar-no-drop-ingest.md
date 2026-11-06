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
   **One shared system for every decoder** (operator 2026-11-05: "all decoders should use this system, shared"): the
   sample time, the ring and the spill live in the common read path (`IqReadAhead` / `IqStream`), not per decoder;
   every decoder that stamps time reads it from the chunk. RS41 is the first one switched over only because its test
   is the sharpest; the rest follow in the same arc, and none keeps a private path.
3. **Overflow goes to Valkey, not to the floor.** When an adopted decoder's ring is full, the reader appends chunks to
   a per-capture Valkey Stream (`radar:iq:<captureId>`, XADD with the chunk's sample index and time) instead of
   dropping; once spilling has begun every chunk goes there until the consumer has drained it, so the order is the
   radio's. The consumer drains the ring, then the stream, then the ring again. A capture's stream is deleted when the
   capture's decode has caught up or the capture is closed and drained.
4. **Bounded by TIME, like a Kafka topic's retention - never blocking** (operator 2026-11-05: "kafka sends received
   data to decoders and once it times out - goes to log and out of the wheel"). The received data is a log the
   decoder reads at its own offset; a chunk older than the retention timeout leaves the wheel (Valkey `XTRIM MINID`,
   the stream ids being the chunks' air time) and, if its decoder had not read it, the decoder's offset jumps past it
   and the loss is logged ("RS41: 12.4 s of air timed out unread") and counted in `dropped_s`. No byte budgets: the
   RAM used is rate x timeout per capture (RS41 32 MB/s x 60 s = 1.9 GB; NAVTEX 1 MB/s x 60 s = 60 MB), one timeout
   for every decoder. Valkey down: the same timeout on the in-process ring alone, never a wait in the reader.
5. **Records carry the air's time.** A record decoded from the backlog carries its sample time; the reception log and
   any push (Telegram) state when it was on the air, and the panel shows each decoder's backlog depth. No lateness
   bound and no late-push cut-off: the operator expects no such delays (2026-11-05) - the backlog absorbs stalls of
   seconds to minutes.

## Steps (one PR each, failing test first, revert checks, gate, test-quality audit)

1. **DONE 2026-11-05 (radar #1172, live):** each running capture's decoder lag and drops on the recent-tunes card
   ("decoder 0.3 s behind · 8 ms dropped"; `/api/sdr/opens` `behind_s`, `dropped_s`) - the measure the rest is judged by.
2. Sample time on every chunk through `IqStream`, for every source (SoapySDR, rsp_tcp, the recorded-IQ replay);
   RS41 stamps frames from it first (a test feeds a capture whose consumer stalls 10 s and checks the frame times are
   the air's, not the read's).
   **2a - DONE 2026-11-05 (radar #1173, live):** local SoapySDR captures - `AirStamp` on the read-ahead's reader
   thread, `IqAirTime` carried to the receiver's end of the chain, `IqStream.airNanos()` (no default); RS41 frames,
   fixes, follow, mount age, start date, heard marks, frames/min and SARSAT bursts by the air. 38 revert checks caught.
   **2b - in review 2026-11-05 (radar branch `feat/rsptcp-read-ahead`):** rsp_tcp captures on an `IqReadAhead` reader
   thread: the socket drained in whole samples (a read ending inside a sample keeps its whole ones), each chunk stamped;
   the read-ahead, shift/resample chain and lag reading in `IqChain`, which both transports use (no longer statics on
   the SoapySDR binding); the lag shown for remote captures. The link's end (hang-up, silence past SO_TIMEOUT, a reset)
   closes the socket only and leaves the backlog to the decoder; the receiver's close drops it.
   - **Settles ride the reader's socket reads - decided, not the event/poll first written here.** The reader reads the
     socket continuously (a live box never idles: 250 kS/s and up), so a settle goes out within milliseconds; a box that
     stops sending ends the link at SO_TIMEOUT, so there is nothing left to settle. The tests now prove the settle is
     carried by the reader's reads, not the receiver's.
   - Found in review and fixed: a lag registered after its capture ended stayed on the card for good (both transports;
     `SdrOpens.lag` now decides under the ring's lock, and a stream opened after `close()` reads nothing); `close()`
     ending the link before the read-ahead let a released capture's backlog reach the decoder; ADS-B's stop interrupted
     its pump before closing, so every stop on a read-ahead read "connection dropped" (both transports).
   - **Open, before a slot-timed decoder (FT8, WSPR) takes air time from a remote capture:** `AirStamp` counts at the
     rate ASKED, and rsp_tcp acknowledges nothing - a rate the box ignores, or samples it drops inside, are no loss to
     the read-ahead, so stamps run early until the window floor re-anchors them (up to ~20 s). The delivered-rate
     deficit (`diagnose()` measures it once) should be reported as a loss, so the next chunk re-anchors.
3. The read-ahead on a Disruptor ring TOGETHER with the Valkey spill, for decoders adopted in step 2 only.
3. The read-ahead on a Disruptor ring TOGETHER with the Valkey spill, for decoders adopted in step 2 only.

   **Why not the ring first (found 2026-11-05, before writing it):** a single-producer ring cannot drop its OLDEST
   chunk - only the consumer advances past a slot - so a ring alone drops the NEWEST. After a long stall the decoder
   would then resume on air as old as the stall (10 s after a 10 s stall) and, stamping time as it reads, file it ten
   seconds wrong; today's drop-the-oldest leaves it the newest half second. With sample time on every chunk (step 2) the
   newest end is the right end - and in this step it is spilled to Valkey, never dropped, in the radio's order.

   Budgets and the Valkey-down fallback as in the design (tests: a stalled consumer loses nothing within budget and
   decodes everything in order with the air's times; over budget the gap is marked; Valkey down never blocks the reader).
   The ring and the spill are the shared read path: every capture gets them, not only RS41's.

   **Found before writing it (2026-11-06, the live station):**
   - The station's Valkey (`radar-valkey-1`, the L1 cache) runs `noeviction` with no `maxmemory` - a spill stream is
     never evicted silently - but with `--save 60 1`: a stream taking RS41's 32 MB/s would fork and write an RDB
     snapshot of gigabytes every minute (copy-on-write doubling its memory under that write load). The IQ log gets its
     OWN instance, persistence off (`--save "" --appendonly no`), beside the cache; a restart loses at most the 60 s
     the retention keeps anyway. The host has 31 GB (18 GB free): RS41 1.9 GB + NAVTEX 60 MB at the 60 s retention.
   - Valkey down: the in-process ring alone (half a second), the reader never waits; a full ring then drops the
     NEWEST chunk, marked - a Disruptor ring cannot drop its oldest, and with air time on every chunk the decoder's
     records stay right either way. The JVM heap (no -Xmx: a quarter of the host, ~7.7 GB) is not used for the 60 s.
   - Sub-steps: **3a** the ring and the spill behind a `SpillStore` seam (an in-memory store for the tests; the
     switch protocol: once the ring is full the reader spills EVERY chunk until the consumer has drained the stream,
     a SWITCH marker in the stream handing the consumer back to the ring, so the order is the radio's; retention by
     `XTRIM MINID` on the chunks' air time, a consumer offset trimmed past read as "N s of air timed out unread");
     **3b** the Valkey store on its own instance (deploy compose + the backend's second connection); **3c** RS41's
     capture on it, live-checked under a gate (the 2026-10-31 drop case).
   - **3a as built (2026-11-06, radar `feat/iq-spill`):**
     - **The protocol:** the switch back needs no marker. The reader switches back on its first chunk after the queue
       has drained, and records the spill sequence it had reached. The consumer reads the store up to that sequence
       before anything queued since.
     - **Retention:** trimmed on the store's id clock, which is not the chunks' air time (the store's ids order by
       arrival). The decoder also trims what it has read once it is back on the queue.
     - **Found by the concurrency review and the test audit, then fixed:**
       - **A later spill read ahead of the queue.** The decoder asked for "all it has", and the store's answer could
         include a spill that began after a switch back. The bound is now what the store had taken, under the lock.
       - **A refused append is not known to be unwritten.** A timed-out XADD still runs: reproduced with
         `docker pause`. Its sequence is never reused or delivered.
       - **A refusal backs off for 1 s mid-spill too.** Before, each chunk cost one client timeout.
       - **Gaps are counted by each entry's own byte offset.** The spill's average left the lag wrong for good.
       - **A store that cannot be read writes off only up to its bound**, and never fetches it again.
       - **A throwing client is a refusal.**
       - **Close:** an append in flight at close leaves no log, and a read inside the store at close delivers nothing.
     - **The contract 3b must meet** (`SpillStore`, `SpillStoreContract`):
       - a call answers within a small part of a chunk, or refuses;
       - exact `MINID` trim (no `~`);
       - a null loss round-trips;
       - `UNLINK`, not `DEL`, for a whole log (a minute of RS41 is 1.9 GB).
   - **3b as built (2026-11-06, radar `feat/iq-spill-valkey`): the contract went ASYNCHRONOUS.**
     - **Why:** the concurrency review found that a synchronous XADD holds the radio's reader up to 100 ms (300 ms on a
       first connect), where the driver holds tens of ms. That re-creates the overflow the spill exists to remove.
     - **The contract now:**
       - `append` hands the chunk over and returns: false = not taken; otherwise an id, or a failure, arrives at a
         callback.
       - The read-ahead reads only up to the settled sequence (every one before it answered) and waits for the rest.
       - A failed answer is a loss, marked where it was. Failures may be answered out of order (each times out alone).
     - **Measured on valkey 8:**
       - XADD of 256 KiB: median 0.18 ms, p99 0.54 ms.
       - A minute of RS41: 2.46 GB of instance memory for 1.97 GB of chunks.
       - XTRIM of that minute at once: 109 ms. So trims are bounded (`~ LIMIT 500`), and the decoder trims as it
         reads, one batch at a time.
     - **The store:**
       - Writes on their own client: 1 s timeout, 64 MB in flight at most. A fault drops the connection, which frees
         the chunks it pinned, rests the link 1 s, then reopens it in the background.
       - Reads on another client: 2 s.
       - `-OOM` and an interrupted read refuse that command alone.
       - Every log expires 2 min after its last append or trim.
     - **No sweep.** Each backend run writes under `radar:iq:<run>:`. Before this, every Spring test context and
       `task dev` on the station swept the live backend's logs (the platform review). Tests and `task dev` run with
       the spill off.
     - **The instance (`valkey-iq`):**
       - host networking (no docker-proxy), 127.0.0.1:6380;
       - `--maxmemory 4gb`, a 5 GB cgroup, no swap, `oom_score_adj 500`;
       - `task deploy:live` brings it up before the restart and reports its memory.
     - **Live 2026-11-06 04:52** (#1178, then #1179, which fixes the deploy's report line): `valkey-iq` healthy, with
       the backend's `radar-iq-reads` and `radar-iq-writes` connections on it.
   - **3c as built (2026-11-06, radar #1180, live 07:16):** every capture's read-ahead spills to the station store, under
     `<receiver>:<captureId>`.
     - **Store pickup:** each capture takes the store at its first spill. The continuous ADS-B/AIS session opens its
       radio before the store's bean exists, so a store looked up at open would never reach it.
     - **Shutdown:** Spring destroys the store before the captures. The store's `close()` therefore unlinks its own
       run's logs first; otherwise a minute of RS41 would sit next to the next run's spill for 2 min.
     - **Reads:** a failed read is asked again once before the backlog is abandoned.
     - **Tests:** the test JVM pins the spill off.
     - **Live check:** RS41 is off (operator), so it ran on the RTTY capture under `task gate` load; results below.
4. Every other decoder stamps from the chunk: NAVTEX, RTTY, WFAX, HFDL, FT8/FT4/WSPR (slot alignment from the air's
   time), DCF77/MSF/VLF, VOR, SAT-REC, ADS-B/AIS (with plan 106 step 1b, where they become ordinary bands). After it, no
   decoder reads the wall clock for a record's time.

## Decided (operator 2026-11-05)

- No lateness bound; records carry the air's time (design 5).
- All decoders on the one shared system (design 2, steps 3-4).
- The backlog is bounded by time, no memory reserved per capture or station-wide ("without specific reservations").
- Retention timeout 60 s, one for every decoder; the log is Valkey Streams.

## Open questions for the operator

None open.
