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

Also found by reading the code, not measured:
- Valkey runs its commands on one thread: many captures spilling at once meet there.
- The page lists rows one by one, and the calendar and row switches assume someone looks at each.
- rsp_tcp boxes can wedge on repeated connects (operator's "no reconnects" rule). At 100 radios, wedged boxes are a
  normal event and need handling without a person.

## Decided

- **No shared ring (operator, 2026-11-07).** The ring waits for its slowest consumer, so one late decoder would cost
  every radio; writers would contend on one cursor; each consumer would step over every other radio's chunks. Each
  capture keeps its own queue, and a lock or ring on it has two threads however many radios there are.

## Not decided

- **Ring or lock inside each capture.** Built on radar `feat/iq-read-ahead-ring`, unmerged. Bench, 240,000 hand-overs a
  side beside a gate: stalls over 1 ms 95 for the lock, 114 for the ring, 0 dropped. No gain as built. Its buffers are
  not preallocated yet, and at the RS41-type mix allocation becomes a real cost, so step 2 measures reuse before this
  closes.
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

### 2. A rig with simulated radios

A test harness: N fake radios feeding real recorded IQ at the real rate into one JVM, N = 10, 25, 50, 100, in the mix
from step 0. No hardware. Runs on a host the operator picks, never beside the live station at full size.

Measured at each N: reader stalls, chunks spilled and dropped, decoder lag, GC pauses, Valkey latency. Then, on the same
rig: lock against ring; ring with reused buffers; G1 against generational ZGC; core groups on and off. Each of these is
adopted only on a measured gain. The knee in N says how many radios one host carries.

### 3. Decoder budget on a host

Keep one thread per decoder at first: threads parked in a read cost nothing, and moving 24 session classes to a shared
pool is a large rewrite (6 of them have a push `processChunk` today). So:

- Core groups by decoder class, from step 1: the thread sets its own affinity to a group, never to one core.
  `sched_setaffinity` through FFM; the JDK has no API for it.
- Admission: a host knows its decode budget from step 1. A capture past it is refused and visible, rather than slowing
  every other capture.
- A worker pool only if step 2 shows threads themselves as the limit.

### 4. Several hosts

From step 0's numbers. Each host owns its radios, readers, decoders and Valkey, since the sessions stay with the process
that owns the samples (plan 106). Control over plan 106's MQTT, records to Kafka. A wedged or dead host costs its own
radios only. Plan 106's open question about one scheduler or one per host is answered here.

### 5. Running 100 by hand is not an option

- The page: radios grouped by host and band, exceptions first, no row-by-row reading needed.
- Boxes: health from plan 106's `sdr/<radio>/health`, a wedged box restarted by its agent, a report of what was lost.
- Database writes per second measured at the rig's N, batched if the table shows they must be.

## Open questions for the operator

1. **Which radios?** RSP-type, RTL-SDR-type, other; USB on a host, or boxes on the network?
2. **What mix?** How many wideband (8 MS/s) and how many narrow (under 250 kS/s). Whether every radio runs at once, or
   they take turns by calendar.
3. **Where?** All at one site, how many hosts, and what network between them. Does aqua stay the only radar host?
4. **By when, and growing how?** 100 at once, or in stages? It sets how early step 4 is needed.
5. **Should every band still run one radio, one capture, one decoder at 100?** A wideband capture with many decoders in
   it would need far fewer radios, but the operator's rule of 2026-11-06 says no. Recorded here only so that the rule is
   held on purpose.
