---
name: test-engineer
description: Test discipline for this org — how to know a test is worth anything. Read BEFORE writing or reviewing tests, when a fix "has tests", when a bug shipped despite a green suite, or when deciding what KIND of test a defect needs (unit / flow / artifact / oracle / measured). Encodes the break-it-and-rerun protocol, tautology detection, the classes of bug unit tests structurally cannot catch (packaging, deploy, UI reachability), instrument blindness, and the ordering/persistence/regression shapes that have actually bitten these repos.
---

# Test engineering discipline

One thesis, and everything below follows from it:

> **A passing test is not evidence. The only evidence a test gives you is that it FAILS without the fix.**

Every rule here was paid for by a green suite that shipped a bug. None of it is generic advice —
generic advice is assumed.

## 1. Prove it fails. Every time. No exceptions.

Writing the test and watching it pass tells you nothing: it may be asserting behaviour that was
already there, or nothing at all. **Revert the mechanism, run the test, record which test caught
it, restore.** Then say so in the commit.

```bash
cp Target.java /tmp/ok.java
# revert exactly ONE mechanism
python3 -c "...s.replace('if (input != null && !RspTcpSelector.matches(url)) {','if (false) {')..."
./gradlew test --tests '*TargetTest' 2>&1 | grep -E "^TargetTest > .*FAILED"
cp /tmp/ok.java Target.java
```

Do it per mechanism, not per commit, and keep the table:

| mechanism reverted | test that failed |
|---|---|
| quarantine covers both radios | `neitherRadioCanBeClaimedWhileObservationIsMoving` |
| epoch checked at settle | `aBeginThatLandsAfterTheRadiosMovedIsRefused` |

**This catches no-op fixes.** Real case: `captures()` was re-sorted by `aos_epoch_s` to fix a
listing-order bug. It passed review by eye. The test failed — because `sidecar()` is a regex parser
that stores every value as a **String**, so `instanceof Number` was never true and the comparator
silently fell back to the name order it was meant to replace. A "fix" that changed nothing, caught
only because the test was required to bite.

**Two traps when reverting:**
- If nothing fails, the test is worthless *or* you reverted the wrong thing. Find out which.
- Make sure the revert actually applied and compiled. A revert that silently no-ops produces a
  green run you will misread as "the test doesn't cover it".

### 1a. A suite can be comprehensive AND unable to reach the defect

The subtlest failure is a fixture that holds constant the very thing the bug needs to vary.

Real case, while writing the deploy-script tests *for this skill*: 21 assertions across seven
scenarios, all green — and they stayed green with the bug fully restored. The bug was a guard
placed after the point of no return, reachable only when a satellite pass **starts during the
build**. The test set `CAPTURE` for the whole run, so the FIRST guard refused and the run never got
near the install. The scenario list looked thorough; the state space did not include the defect.

The fix was to make the stub *change during the run* — a call counter, so a pass appears between
the two guards:

```bash
n=$(( $(cat "$STATE_CALLS") + 1 )); echo "$n" > "$STATE_CALLS"
[ -n "$CAPTURE" ] && [ "$n" -gt "${CAPTURE_AFTER:-0}" ] && cap="{...}"
```

With that, reverting the fix fails on exactly the right assertion (`did NOT restart: expected [0]
got [1]`). **When a bug depends on state CHANGING mid-operation, a fixture with constant state can
never see it** — and this is the normal shape of race, ordering, TOCTOU and guard-placement bugs.
Ask of every fixture: which variables does it pin, and does the defect live in one of them moving?

## 2. "Would this still pass if I deleted the method body?"

Ask it of every assertion. If yes, it asserts nothing.

- A test that drains a command log, discards it, then checks a later call is silent is satisfied by
  a no-op implementation.
- An assertion sitting under a `containsExactly` that already pins the full sequence is a
  tautology — it cannot fail independently. Spend the negative test on something that bites.
- A test that mocks the thing under test proves the mock works. Real case: a "refetch-then-mutate"
  test mocked `api.radioSources()` to a **constant**, so it could not distinguish the refetched
  value from the stale one — the exact behaviour being tested.

## 3. Never assert the bug as a feature

The worst outcome is a test that *locks in* the defect. Real case: a per-row antenna control was
offered on local radios, producing `driver=sdrplay?ant=A`, which SoapySDR cannot open — a working
radio killed by picking an input for it. The test asserted **"offers the control for a local radio
too, not only remote boxes"**, presenting the bug as the requirement.

Before asserting a behaviour, ask what it *does downstream*, not just what it looks like. Follow the
value to where it is consumed. When you invert such a test, write the reason in it — that comment is
the most valuable line in the file.

## 4. All-green unit tests + an unreachable feature

Unit tests cover the units you thought of. They say nothing about whether the feature is *reachable*.

Real case: every unit test around the radio-settings classes passed while the page offered **no way
to change an existing radio at all** — the antenna picker existed only on the Add form, and
delete-and-re-add is refused for a radio a slot uses. The backend was never broken. Nothing
rendered a view, so nothing could fail.

The answer is a **flow test**: walk the operator's real sequence through the real entry points, in
order, and assert what they would SEE.

```java
// add -> assign -> verify -> the edit they actually need -> delete
c.put(new PutSource("pi4", PI4, "C"));
c.slots(new PutSlots(LOCAL, "pi4"));
assertThatThrownBy(() -> c.delete("pi4"));           // the dead end they hit
var after = c.put(new PutSource("pi4", PI4, "A"));   // what the control does
assertThat(radios.snapshot().observationDevice()).isEqualTo(PI4 + "?ant=A");
```

The last assertion is the point: not "the field changed" but "the device the radio actually opens
followed". A setting that does not reach the hardware is cosmetic.

## 5. Some bugs are structurally unreachable by unit tests

Know when the defect lives outside the code under test, and test the **artifact** instead.

Real case: the live station served a months-old UI for hours. Cause: `buildFrontend` writes into
`src/main/resources/web/ui` and had no ordering against `processResources`, so `bootJar` packaged
the pre-vite bundle. **No unit test could ever catch this** — every unit passed, the code was
correct, the jar was wrong.

What catches it:
- an **artifact assertion** at package time (`bootJar` fails when the packaged bundle ≠ what vite
  produced), and
- a **deploy-time assertion against the running process** (the served bundle / `ui_build` equals the
  one just built).

Rule: **when the failure is "the right code was not in the thing that ran", the test belongs in the
build or the deploy, not in the suite.** Verify against the running app, not the artifact alone — a
deploy that reports success while serving the previous bundle is exactly the failure being fixed.

Same family: config wiring, packaging, migrations, systemd units, permissions.

## 6. Know what your instrument cannot see

An assertion that *cannot fail* for a given subject is worse than none: it reads as coverage.

- **`scrollWidth <= clientWidth` is BLIND for `<select>`.** A select renders in a UA shadow tree.
  Measured live: a control clipped from 124 px to 44 px reported `scrollWidth == clientWidth == 44`
  while 80 px of text went unpainted ("antenna: default" rendered as "anten"). For a select,
  compare used width against a clone with `style.width='auto'`.
- **jsdom does no layout.** `getBoundingClientRect()` is all zeros. Any size/position/overlap claim
  needs a real browser. Render the REAL component into jsdom, dump `container.innerHTML`, load it
  into headless Chromium **with the real stylesheets and the real ancestor chain**, and measure
  there.
- **A raised noise floor does not prove sensitivity.** Compression raises it too. Use a shape test
  that is immune to gain: complex Gaussian noise has `E|x|⁴/(E|x|²)² = 2.0`; below 2 is compression.
- **A carrier test cannot find a suppressed-carrier signal.** "No peak Doppler-shifts" rules out a
  carrier, not a QPSK block with no discrete line. Match the statistic to the signal.

Before trusting a measurement, ask: *what would this read if the defect were present?* If the answer
is "the same", it is not a test.

## 7. Fixtures and code can be wrong together

A fixture built from the same misreading of the spec as the code agrees with it perfectly. Prefer:

- an **independent oracle** — a reference implementation, a known-good recording, another tool's
  output on the same input;
- **real captured data** over synthesized;
- deriving the fixture from the SPEC by hand, and saying in a comment which document and section.

And **test at shipped parameters**. A decoder verified at 96 kHz that ships at 250 kHz is untested.

## 8. Persistence needs a round trip, not a write

A save test proves the writer. The bug is almost always the reader.

Real case: `put()` was taught that a local radio is a radio and `save()` wrote it, but `restore()`
still accepted `rsptcp://` only — so every restart silently **deleted** the operator's local radio
while the file on disk still listed it, and dropping the source reset the slot pointing at it.

The shape that catches it: write with one instance, construct a **second instance from the same
directory**, assert through the second.

```java
RadioSources first = new RadioSources(props(dir), Runnable::run);
first.put("workstation", "driver=sdrplay", null);
RadioSources second = new RadioSources(props(dir), Runnable::run);   // the restart
assertThat(second.snapshot().sources()).extracting(Source::name).contains("workstation");
```

Also test the **hostile file**: one malformed entry must cost that entry, not the directory. A
per-entry failure that aborts the whole restore drops the survivors, skips the projection, and lets
the next save overwrite the file with the truncated set.

## 9. Ordering bugs need a case where the two orders DISAGREE

A sort test whose fixture is already in the right order under both comparators proves nothing.

Real case: satellite retention sorted by **filename**. Names are satellite-major, so every
`METEOR-M2_3_*` sorted ahead of every `METEOR-M2_4_*` regardless of date — and with one eviction per
pass, every M2-3 capture was deleted by the pass that followed it, including an 84.4° overhead pass
86 minutes after recording, while files three weeks older survived.

Construct the fixture so name order and time order **conflict**, and assert the semantic one:

```java
// NEWEST file, but its name sorts FIRST
recordingAt(dir, "METEOR-M2_3_20260819-181811", aos = 9_000_000);
recordingAt(dir, "METEOR-M2_4_20260727-002659", aos = 1_000_000);
assertThat(remaining).containsExactly(/* the M2-3 survives */);
```

**When a comment documents a sorting hazard, grep for every other place that sorts that collection.**
`tracks()` had the fix and a comment spelling out the hazard verbatim; `prune()` and `captures()`
did not.

## 10. Positive AND negative, and make the negative bite

Every fix ships both: the new behaviour, and a guard on the old one returning.

Distinguish a **value** from a **fault**: a mount refusing a below-horizon goto answers `'0'` — a
return value. A response that is neither `'0'` nor `'1'` is an exception. Collapsing them makes a
broken link look like a polite refusal.

Distinguish "no" from "could not ask". A guard that treats an unreachable dependency as "nothing to
worry about" fails open at the worst moment.

## 11. Never dismiss a flaky test

Pass-in-isolation / fail-in-suite is a real race or a leaked singleton. Fix it. "Retry it" is how a
production race gets shipped with a green build. Concurrency defects need a test that names the
**interleaving** — a latch that holds one thread inside the critical section while another asserts
what it can see — not a hopeful `sleep`.

## 12. A regression test carries its incident

Name it after the behaviour, and put the real event in the comment: date, what was observed, what it
cost. `retentionReapsTheOLDESTPassEvenWhenANEWERONESortsFirstByName` with a comment naming the
84.4° pass tells the next reader why the odd-looking fixture must stay. `testPruneSorting` does not.

## 13. Repo-specific facts

- **Gates exist in three repos out of four.** monitor, chat, admin run SpotBugs / PITest / JaCoCo /
  OWASP / Sonar. **radar (ex plane-tracker) runs none of them** — don't write to satisfy a gate that
  isn't there, and don't assume one will catch you.
- **`clean check` is the CD gate.** A jar that has not passed it is not a jar that ships.
- **radar/frontend has jsdom + @testing-library/react** (added 2026-08-19). View tests are possible;
  opt in per file with `// @vitest-environment jsdom` (the project default is `node`), and register
  `afterEach(cleanup)` **explicitly** — vitest `globals` is off, so Testing Library's auto-cleanup
  never registers and each test otherwise renders on top of the last one's DOM.
- **Query like a user**: `getByRole` with the accessible name, then `getByLabelText`. A component
  findable only by test id usually has no accessible name — that is the bug.
- **One Testcontainer for the whole suite**, started in a static block; the per-class `@Container`
  lifecycle stops it between classes while Spring's cached context still points at it.
- **Hardware and live smokes are env-gated with `assumeTrue`** (skip, never fail). A `-D` system
  property does not reach the forked test JVM — use the environment.
- **Don't run tests without being asked**, and when you do, run the full clean check at the end.
