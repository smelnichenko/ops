# Plan 125 - the Vagrant copy built once, reverted per run; proof matched to risk

**Status:** decided 2026-11-18 (operator: "maybe it's time to make rules more flexible?" - "both, do it"); drafted.

## Decisions (operator, 2026-11-18)

1. **The copy from a snapshot.** Every copy run, and every upgrade-cycle unit proof, built the copy from nothing - 49 min
   (copy run 5: 04:38-05:27 for the build, 18-22 min for a change and every check) - then destroyed it. From now on the
   copy is built once, snapshotted, and each run reverts to the snapshot.
2. **Proof matched to risk.** A copy run is mandatory where a change touches state: database migrations, version
   upgrades, one-way changes, anything that restarts or drains a stateful service (a Postgres, Kafka, ScyllaDB or
   ClickHouse pod's roll, a policy that drains their connections), backup and restore logic. A change whose effect is
   fully determined and inert to state - deleting objects a live audit shows select nothing, CI checks and harnesses,
   alert rules and runbooks, docs, a render-only refactor whose production render diff is empty - ships on its render
   diff per environment (Argo's own diff against the live objects of each app it touches, not a helm-template diff alone:
   server-side apply, managed fields and ignoreDifferences can make an empty template diff change live state, or hide a
   change), the full review and a live check after it. When unsure, it is a copy run. Unchanged: the full
   review before every production change, the one-way gates, the copy never a scratch box.

## The snapshot - the base, not the settled stack (review, 2026-11-18)

The first draft snapshotted the copy fully built and settled. Its review (three Criticals) showed a reverted settled
stack is not a fresh build: the mirror's revisions record a former run's push (an ops-only proof waits 40 min for
commits the copy no longer has); the restart history's post-boot settle judges the next stage's ordinary restarts; the
survival check's Mimir query finds no block hours after a seed made minutes before the save; CronJobs, Velero and the
Pis' timers fire their missed runs at boot; a moved main needs part of test:copy:argo replayed. Each is a red handed to
the fix agent for a unit with no defect.

So the snapshot is the **base**: the copy as test:copy:build leaves it at its cold-boot halt - the Pis and the node built
(_copy:base), Argo not yet on it. A run reverts to it, boots it cold (the build's own cold boot) and builds the Argo layer
as the build does (test:copy:argo). Nothing of a former run is in the snapshot. It saves the base's ~21 min of the 49
(copy run 6: base 12:04-12:25, Argo layer 12:26-12:52); a deeper snapshot can be weighed once this one has proven
itself.

- **Taken** at the build's cold-boot halt (`scripts/copy-snapshot.sh save`): each domain shut down by itself (a forced
  power-off refused - the Vagrantfile's `graceful_halt_timeout` is 300 s now, Vagrant's 60 s cut the node's drain short),
  one internal libvirt snapshot each by the UUID vagrant holds, the record (`.copy/snapshot/meta`) last. A save that
  fails drops what it made and never fails the build.
- **Reverted** (`test:copy:ready`): production's inventory read, then - fresh - every domain halted and reverted, left
  shut off; booted cold, vms-ready, test:copy:argo. Stale - the build. A revert that fails after the stale check drops
  the snapshot and the same run builds: a broken snapshot is never reused.
- **Stale** when: older than 24 h; production's inventory or the Pis' versions moved; the files that build the base
  changed (Vagrantfile, deploy/ansible, the Pis' apt pins, the Taskfile's `_copy:base` and `_vagrant:pi-*` steps - not a
  check's file); a domain or its snapshot gone or another domain under a machine's name; `COPY_SNAPSHOT=off`. libvirt
  not answering is no verdict (exit 1), never "missing".
- **At a run's end** the VMs are halted, not destroyed (the cycle): memory freed, the disks and the snapshot kept.
  `task test:copy:drop` destroys the copy and its snapshot.

## Changes

- `scripts/copy-snapshot.sh save|revert|status|drop` and its harness (stub vagrant and virsh, a scratch ops tree).
- Taskfile: `test:copy:build` saves at its cold-boot halt; `test:copy:ready` (the inventory read, revert or build, then
  the cold boot and the Argo layer); `test:copy:drop`; every other task that destroys the copy's VMs takes the copy lock
  first (they delete the snapshot with them - the next run builds, said, never interleaved with a run).
- Vagrantfile: `graceful_halt_timeout` 300.
- `scripts/upgrade-cycle.sh`: the proof's copy from `test:copy:ready`; halted, not destroyed, when the run ends and after
  the review; its harness and copy-tasks' expected commands follow.
- The scratchpad copy-run scripts take `test:copy:ready` too.

## Proof

The first run after it lands builds and saves; the next reverts and builds the Argo layer. Both runs' inventories
(`.copy/vagrant-inventory.txt`) compared: equal but for what the second run's change changed; the second run's checks
green as the first's. A stale case forced (a base file touched): the run builds. Then the full review again, then the
cycle on it.
