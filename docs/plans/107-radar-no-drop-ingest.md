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
     - Weighed when FT8 took the air (radar #1183):
       - A drop inside the box shows as a forward jump at the next window's correction, and FT8 turns it into a hole
         at most 10 s after it happened.
       - Arrival dating held a loss under 1 s unseen for up to a minute, so FT8 is better off on the air, even remote.
       - The deficit report would shorten the 10 s to one chunk. It stays open; only FT8 needs it. WSPR reads only
         its first sample's air, so a drop mid-capture never moves its slot.
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
     - **Live check, 2026-11-06, with `task gate` running as load** (sampler and data in `107-data/`, one row
       every 2 s per open capture):
       - **RTTY**, rsp_tcp at 192 kS/s, 07:16-07:35: at most 11 ms behind at load 31.9. It never needed the spill.
       - **RS41**, local SDRplay at 8 MS/s, on its own schedule, 07:35-07:53. This is the 2026-10-31 drop case. In
         the gate's Gradle phase (load 30-33) it fell up to **2.29 s** behind, more than 0.5 s for about 64 s of
         samples. The store took the excess, up to **62 MB** in its one log.
         - **Dropped: 0.000 s** throughout. No driver overflow and no spill warning in the log.
         - The store emptied as it caught up: 0 keys and 1.19 MB after.
         - Before step 3, everything past half a second would have been dropped.
4. Every other decoder stamps from the chunk: NAVTEX, RTTY, WFAX, HFDL, FT8/FT4/WSPR (slot alignment from the air's
   time), DCF77/MSF/VLF, VOR, SAT-REC, ADS-B/AIS (with plan 106 step 1b, where they become ordinary bands). After it, no
   decoder reads the wall clock for a record's time.
   - **NAVTEX (radar #1181), live 2026-11-06:**
     - the heard time and the slot judgement, the panel's slot, the recording span, and the row (`received_at`,
       `day`) read the air;
     - ages and pruning stay on the clock.
   - **RTTY (radar #1182), live 2026-11-06 11:01:**
     - the heard time, the timetable product, a fade's slot, the day-time mend, and the row read the air;
     - the silence that closes a bulletin and the card's freshness stay on the clock.
     - Recordings are written through the tap and stamped by the clock, so their marks are moved by the decoder's
       lag. This fixed NAVTEX's marks too.
   - **FT8/FT4 (radar #1183), live 2026-11-06 15:53:**
     - Slots are cut on the air's grid. A forward jump of the air over 10 ms is a loss:
       - inside its slot, the hole is zero-filled;
       - past the slot's end, the slot is handed off and the stream re-dated.
     - Decodes are filed at the slot's start, and an older slot's decode never replaces a newer row.
     - The test-quality audit found a real bug: the row guard dropped an older CQ's grid. Fixed.
     - Live check, over the last hour of `ft8_contact`:
       - all 72 rows filed after the deploy have `last_heard` exactly on the 15 s grid;
       - the 160 rows before it were 2.4-6.4 s into their slot, which is when the decode finished.
     - pi4-C (rsp_tcp) logged two losses in the first 20 s after start, 15 ms and then 1291 ms, 10 s apart (one
       `AirStamp` window). Probably the reader stalled during JVM warm-up and the box dropped what overflowed. None
       since. Watch the hourly count of "ms lost on the air".
   - **WSPR (radar #1184), live 2026-11-06 18:45:**
     - Spots are filed at the even UTC minute the capture's first sample was on the air in.
     - A capture held across slots (a one-band plan, no reconnects) is cut at each slot's end, each slot decoded as
       it closes.
     - WSPR is switched off in the station's panel, so the row's `last_heard % 120 == 0` check waits until it is on.
   - **Next:** DCF77/MSF/VLF, VOR, HFDL, WFAX, DSC, SAT-REC, and ADS-B/AIS with plan 106 step 1b. Then the
     recordings stamped by the air (`IqRecordings`, `RecordTap`), after which the marks move to the air.

## One band, one capture, one decoder (operator 2026-11-06)

"separate bands processing - no simultaneous ft processing together with rtty, for all bands same principle".
Reverses radar doc 098 (2026-09-19). No decoder rides another band's capture. All live 2026-11-06:

- **FT8 off RTTY (radar #1185):** the passenger mechanism is gone; FT8 30 m is an ordinary band of FT8's plan.
- **SARSAT (radar #1186):** its own row and capture (406.05 MHz, 200 kHz above the tune, 2 MS/s). Operator: stays off.
- **RBU (radar #1187):** its own row and capture (66.66 kHz); its meter out of `MsfDemod`, bit-for-bit the same reading.
  Off until assigned a radio: unassigned it opens on the sdrplay RS41 holds; MSF is on pi4-C.
- **RTTY back to 96 kS/s** (live config): its reasons for 192 kS/s, passengers and the DDH47 LW window, are gone. CPU
  fell about a third. Its copy at 96k is still to be judged on daytime traffic.

**Open, found 2026-11-06:** pi4-C delivers about 1.1-1.3 s fewer samples than counted early in every rsp_tcp capture,
seen at the second `AirStamp` window, about 20.5 s after the open (15:53, 17:45, 18:42, 19:02). Suspected: the SDRplay
driver dropping samples while it applies the open's settings commands. Matters for FT8 on pi4-C, where each slot is a
fresh 14 s capture.

**Open, design item 1:** `IqReadAhead` is still an `ArrayDeque` under a `ReentrantLock`. Step 3 built the spill around
it; the LMAX `RingBuffer` for its fast path is next.

## Done 2026-11-07

- **The read-ahead on a Disruptor ring** (radar #1189), one per capture; the operator kept it ("in any way disruptor will
  stay"). No gain over the lock at hand-over, measured; a concurrency review and a test audit both fixed things in it.
  Full with no store it drops the newest.
- **AirStamp says when its anchor moves** (#1188, #1193): added up, at most once a minute, the longest read gap behind it,
  and what a capture ends with. This found the pi4-C start deficit.
- **The pi4-C deficit, found and fixed on the box:**
  - The HDR patch restarted the stream (about 770 ms) even when HDR was already off (#1194).
  - The box streamed at its defaults before the client's commands landed: seconds of air at the wrong rate and frequency
    at every open (#1195). It now holds samples until the client's new start command.
  - HDR left on by NAVTEX is cleared at each client's init (#1195).
  - Live after it: an open moves 17 ms and then nothing.
- **Radiofax** (#1191) had read noise 1900 Hz above every signal since it was built. Proved on a chart recorded off DWD.
- Band map with the station's own channels (#1190), recordings paging (#1192).

Still to do in this plan: FT8 holding one capture across slots, the other decoders' air time, recordings dated by the
air, RTTY's dropped characters.

## Decided (operator 2026-11-05)

- No lateness bound; records carry the air's time (design 5).
- All decoders on the one shared system (design 2, steps 3-4).
- The backlog is bounded by time, no memory reserved per capture or station-wide ("without specific reservations").
- Retention timeout 60 s, one for every decoder; the log is Valkey Streams.

## Open questions for the operator

None open.
