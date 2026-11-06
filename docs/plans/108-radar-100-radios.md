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

- **A decoder is a microservice, on the Kubernetes cluster (operator, 2026-11-07).** "some machines may run subset of
  decoders, decoder should be a microservice"; "we have kubernetes cluster". Radios are on the network, so a decoder
  need not run where its radio is.

## The shape

Box (rsp_tcp) -> decoder pod (read path, decoder, its captures) -> records. Plan 106's scheduler says who holds a radio;
the pod opens the capture directly when it holds the lease. radar keeps the page and the history.

| Wanted | What the cluster gives | What it does not |
|---|---|---|
| A machine runs a subset | a Deployment per decoder, node labels | |
| Consumers on need | replicas and rollouts; later, scaling on demand | a JVM starts in seconds: too slow to start per FT8 slot, so a pod stays up and opens captures |
| Pinned consumers | kubelet static CPU manager: a Guaranteed pod with whole CPUs gets exclusive cores | it does not know P cores from E cores; `ten` runs policy `none` today, and changing it is a write on ten |
| A slow or crashed decoder stays its own | a process per pod: its own heap, GC and crash | |
| Adding a host | a node joins | |

The cluster today, read 2026-11-07: one node, `ten`, 20 CPUs, 64 GB with 34 GB in use, 5% CPU at that moment, a limit of
110 pods. So:
- `ten` reboots take every decoder with them. Today's radar on aqua does not depend on it.
- 100 pods do not fit beside what runs there under that pod limit; a pod carrying several captures of one decoder, or
  more nodes, is the answer. Memory is the other limit: one JVM per pod, its idle size not measured yet.
- IQ stays out of the mesh's sidecars: a proxy on every chunk costs CPU for nothing. Pods reach the boxes on the LAN
  through an egress NetworkPolicy.
- Each pod's JVM carries only its own radios, so GC is no longer shared between 100 readers: the case for reused buffers
  below mostly goes away.

## Not decided

- **Ring or lock inside each capture.** Built on radar `feat/iq-read-ahead-ring`, unmerged. Bench, 240,000 hand-overs a
  side beside a gate: stalls over 1 ms 95 for the lock, 114 for the ring, 0 dropped. No gain as built, and with a JVM
  per pod allocation stays near today's per radio. Recommendation: drop it, keep the locked queue and the spill, unless
  step 2 finds a pod carrying many wideband captures.
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

### 3. One decoder as a service: the pilot

One narrow decoder, from a network radio, as a pod on the cluster, side by side with radar and compared on the same air:
same bulletins, stamps within a slot, no more losses. It needs plan 106's lease (step 1b onward), so that two owners
never open one box. Measured: idle JVM size, CPU against step 1, connect-to-first-sample. This sets the template for the
rest.

Then the others one at a time, heaviest last. The read path (`IqReadAhead`, `AirStamp`, the spill, rsp_tcp's client)
goes with them. The common library was removed from all services in March, so one repo and one image with a Deployment
per decoder keeps one copy of it (question 6). Waterfall, audio and IQ recording read a capture in process today, and
each needs an answer in this step: stay in the pod, or a stream out of it.

### 4. Budget, pinning, nodes

No fixed number of radios or hosts (operator, 2026-11-07: "numbers can grow, some hosts will have a few, some more"):

- A pod's CPU and memory requests come from steps 1 and 3: never one size for all, and 100 is not a limit built into
  anything.
- A capture past what its pod carries is refused and visible, rather than slowing every other capture.
- Exclusive cores only if step 2 shows stalls that cost samples: kubelet static CPU manager, Guaranteed pods. A machine
  that runs subsets by a node label.
- Adding a radio is a row in the directory; adding a machine is a node joining. No code change, no redeploy of the
  others.
- Nothing assumes radios are evenly spread: the page and the budgets go per pod and node. Valkey per node, not one for
  all.
- Control over plan 106's MQTT, records to Kafka.

### 5. Running 100 by hand is not an option

- The page: radios grouped by host and band, exceptions first, no row-by-row reading needed.
- Boxes: health from plan 106's `sdr/<radio>/health`, a wedged box restarted by its agent, a report of what was lost.
- Database writes per second measured at the rig's N, batched if the table shows they must be.

## Open questions for the operator

1. **Which radios?** Mostly from the network (operator, 2026-11-07). Still open: which boxes, and the link to each.
2. **What mix?** How many wideband (8 MS/s) and how many narrow (under 250 kS/s). Whether every radio runs at once, or
   they take turns by calendar.
3. **Which machines?** Hosts differ and grow (operator, 2026-11-07). Does a second node come early, or does `ten` carry
   the decoders alone at first, reboots included? Does aqua join the cluster, or keep its local radios outside?
4. **Growing how?** No fixed end, so stages by need (operator, 2026-11-07). Roughly how many in the next stage?
5. **Should every band still run one radio, one capture, one decoder at 100?** A wideband capture with many decoders in
   it would need far fewer radios, but the operator's rule of 2026-11-06 says no. Recorded here only so that the rule is
   held on purpose.
6. **One image, or one repo per decoder?** Recommended: one repo and image, a Deployment per decoder. 24 repos would
   carry 24 copies of the read path, or bring the common library back.
7. **Do plans 105 and 106 still stand as written?** 105 puts NAVTEX on the pi4. 106 keeps radio control independent of
   `ten`. Decoders on the cluster depend on `ten`, though leases on the pi4 still need not.

