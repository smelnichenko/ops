---
name: concurrency
description: Concurrency discipline for threads, asyncio, locks, and shared state — check-then-act atomicity (TOCTOU), lock ownership and reentrancy, event-loop vs worker-thread boundaries, clock/ordering coherence, and cancellation/shutdown safety. Read BEFORE designing or reviewing anything with threading, asyncio, locks, shared mutable state, background loops, Kafka consumers, or WebSocket handlers — and whenever a bug is timing-dependent, "happens only on hardware", or vanishes under a debugger.
---

# Concurrency discipline

Working rules for shared state and time. Races don't show up in tests that don't schedule them;
they show up in production at the worst load. Every rule below was violated in this codebase at
least once and found by review or hardware.

## 1. Check-then-act must be atomic

A guard that releases its lock before the action it guards is a decision made on stale state
(classic TOCTOU: `with lock: known = x in table` … `if known: mutate(table)` — the entry can
vanish between the two). Move the check *inside* the operation that owns the state
(`mutate(x, require_known=True)` under one lock acquisition), or accept and document the race
window with its worst case. Grep for the pattern: a lock released between a read and the write
that depends on it.

## 2. Locks: ownership, scope, reentrancy

- **One lock per invariant**, and write down what it protects (a comment on the lock field).
  Two locks protecting overlapping state is an ordering deadlock waiting for load.
- **Know your lock's reentrancy**: `threading.Lock` is NOT reentrant — a helper that re-acquires
  the caller's lock deadlocks; either pass control fully inside one acquisition or use explicit
  call contracts ("caller must hold the lock" in the docstring).
- **Never hold a lock across I/O** (serial, network, disk): latency under the lock starves every
  other participant and turns a hiccup into a stall.
- Frozen snapshots beat shared references: hand consumers an immutable copy (frozen dataclass,
  tuple) taken under the lock, not a live view of guarded state.

## 3. Event loop vs threads: who owns what

- **Nothing blocking on the loop**: serial reads, subprocess waits, file I/O go through
  `asyncio.to_thread`/executors. One blocked tick stalls every coroutine — the UI, the ticker,
  the watchdogs.
- **Every mutable object has exactly one writing context** (one thread or the loop). Cross-context
  reads get either a lock or an immutable snapshot; "it's just a float" is how torn multi-field
  reads are born (two fields updated non-atomically read half-updated).
- Reads of several related fields back-to-back are only consistent if nothing awaits between them
  — an `await` in the middle is a scheduling point where the world changes.
- Data flowing loop→thread→loop: prefer handing values through call arguments/returns over
  sharing attributes; the tick that passes `point, interval, age` is race-free by construction.

## 4. Time and ordering

- **One monotonic clock per control loop**, owned by the loop. Never difference timestamps from
  two clocks (a 4 Hz ticker clock vs an 8 Hz servo's `time.monotonic()` produced quantized ages
  and a hidden bias here). Wall clocks are for humans; `time.monotonic()` is for durations.
- Measurements carry their **epoch** (or age) through queues and snapshots; consuming a value at
  arrival time when it was produced earlier silently shifts every derived quantity.
- Out-of-order events are normal under concurrency: decide explicitly (drop, clamp, reorder) —
  an accidental `dt <= 0` branch doing a state reset is a policy nobody chose.

## 5. Cancellation, shutdown, runaway

- **`finally` must stop the actuator**: any loop that commands hardware wraps the command phase
  so an exception can't leave the plant running (a crashed calibration script left the mount
  slewing 30° here — the `stop()` lived before the exception, not in `finally`).
- Shutdown ordering: stop producers, then drain, then close resources; a daemon thread killed
  mid-write corrupts what it owned. `join(timeout=)` + a documented abandon policy beats hanging.
- Stops must be **idempotent** and safe to call from any state — shutdown paths run twice more
  often than you think (signal + finally + atexit).
- Background tasks that die must be *seen*: surface a status ("read error: …"), never a silent
  return — a dead reader thread looks exactly like an empty sky.

## 6. Language specifics worth pinning

- Python: the GIL makes single bytecode ops atomic-ish but NOT read-modify-write sequences or
  multi-field updates; `dict` iteration during mutation raises — snapshot (`tuple(d.items())`)
  under the lock.
- Java/Spring: singleton beans are shared across request threads — instance fields are shared
  state; use locals, `Atomic*`, or immutability. One Kafka consumer instance per thread (they are
  not thread-safe); WebSocket sessions must be written from one writer at a time.

## 7. Review workflow

Map every shared mutable object → its writers/readers and contexts → its lock or immutability
story. For each guard: is the check inside the same acquisition as the act? For each `await`/lock
release: what can change during it, and does the code re-validate? For each loop commanding
hardware: crash → does it stop? For each timestamp: whose clock, what epoch? Test races by
injecting clocks and forcing the interleaving (hooks, barriers) — a `sleep()` in a test schedules
nothing and proves nothing.
