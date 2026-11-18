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
   diff per environment, the full review and a live check after it. When unsure, it is a copy run. Unchanged: the full
   review before every production change, the one-way gates, the copy never a scratch box.

## The snapshot

- **Taken** at the end of `test:copy:build`, once the copy is built and settled (the build already ends with a cold
  boot - the snapshot holds that state): `vagrant halt`, then one internal libvirt snapshot per domain (`ops_kubeadm`,
  `ops_pi1`, `ops_pi2`; `virsh snapshot-create-as <domain> copy-built --atomic` - disk-only, the domains shut off), and
  `.copy/snapshot.json`: when, infra's and platform's mains the copy runs, production's inventory and the Pis'
  versions as read for it (their hashes), ops' tree of the paths that build the copy (Vagrantfile, deploy/ansible,
  tests/ansible/copy, the copy scripts). Then the VMs up again for the run that built it.
- **Reverted** at a run's start when it is fresh: `vagrant halt`, `virsh snapshot-revert <domain> copy-built` each,
  `vagrant up --no-provision`, the VMs ready, Argo settled - about 5 min. If infra's or platform's main moved since
  (CD's promotions do, daily), main is mirrored and settled first, so the run's change is its own diff.
- **Stale - rebuilt, never reused** - when: it is older than 24 h (the copy's clocks, short-lived tokens and leases);
  production's inventory or the Pis' versions read now differ from the snapshot's (production upgraded since: the copy
  must be built at the new versions); ops' build paths differ from the snapshot's; a domain or its snapshot is missing;
  the revert or the settle after it fails. The run then builds, and saves a new snapshot.
- **At a run's end** the VMs are halted, not destroyed: their memory freed (the radar may start, as before), the disks
  and the snapshot kept. `task test:copy:drop` destroys the copy and its snapshot (disk back, the next run builds).

## Changes

- `scripts/copy-snapshot.sh save|revert|status|drop` (revert exits 3 when stale: the caller builds), its harness against
  stubbed vagrant and virsh.
- Taskfile: `test:copy:build` saves at its end; `test:copy:ready` reverts, or builds when stale; `test:copy:drop`.
- `scripts/upgrade-cycle.sh`: the proof's copy from `test:copy:ready`; halted at the run's end instead of destroyed
  (the memory preflight unchanged - halted VMs hold none); its harness's expected commands.
- The scratchpad copy-run scripts take `test:copy:ready` too.

## Proof

The first run after it lands builds and saves; the next reverts. Both runs' inventories after their settle compared
(`.copy/vagrant-inventory.txt`): equal but for what the second run's change changed. A stale case forced (production's
inventory edited in the snapshot's record): the run builds. Then the full review, then the cycle on it.
