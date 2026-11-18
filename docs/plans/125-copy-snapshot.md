# Plan 125 - the Vagrant copy built once, reverted per run; proof matched to risk

**Status:** decided 2026-11-18 (operator: "maybe it's time to make rules more flexible?" - "both, do it"); built,
reviewed twice (the second: architecture and reliability, two Criticals - the policy's text, a base reused before it was
proven - answered below); its proof next.

## Decisions (operator, 2026-11-18)

1. **The copy from a snapshot.** Every copy run, and every upgrade-cycle unit proof, built the copy from nothing - 49 min
   (copy run 5: 04:38-05:27 for the build, 18-22 min for a change and every check) - then destroyed it. From now on the
   copy's base is built once, snapshotted, and each run reverts to it.
2. **Proof matched to risk.** A change ships without a copy run ONLY when it is wholly in the closed list below; any
   other change - and any change not certainly in it - has its copy run. Unchanged: the full review before every
   production change, the one-way gates, the copy never a scratch box.

### What ships without a copy run - the whole list

A change all of whose files and effects are among these:

1. CI pipelines, unit harnesses, render checks, test fixtures (nothing Argo or Ansible applies).
2. Documents: plans, runbooks, research notes, READMEs.
3. Prometheus alert and recording rules with their promtool tests; provisioned Grafana dashboards.
4. Deleting objects that act by a selector - AuthorizationPolicy, PeerAuthentication, RequestAuthentication, Sidecar,
   Telemetry, NetworkPolicy, EnvoyFilter - that a live audit shows select no pod in their namespace, and that no other
   object names. Never a deletion of an object without a selector (a CRD - its resources go with it -, a PVC, a Secret,
   a ConfigMap something mounts, a Service).
5. A render-only refactor: every app it touches renders the same objects for production, field for field.

Everything else has a copy run - among it, by what it touches, never by a list of services: anything that changes a
PersistentVolumeClaim, a StatefulSet, an operator's resource (a CNPG Cluster, a Kafka, KafkaNodePool or KafkaTopic, a
ScyllaCluster, a ClickHouse) or the configuration any of them reads (a retention, a TTL, a parameter reloaded in place);
any Pi host or the node (a playbook against them); a traffic policy on a stateful service's path (an
AuthorizationPolicy, PeerAuthentication, NetworkPolicy or DestinationRule selecting or routing to its pods); backup and
restore logic; a version upgrade; a one-way change; anything that restarts or drains a stateful pod.

### What the exemption needs, in the pull request

- The item of the list it is, by number.
- The production diff of every app whose render moves (each app touched named, a "no change" said): Argo's own diff
  against the live objects (`argocd app diff`, server-side apply and managed fields as production applies them) AND the
  rendered objects' diff with every ignoreDifferences field shown (Argo's diff applies them - a change hidden there is
  read here).
- The live check after it: what is read in production, the value expected.
- The reviewer reads all three before the merge; one missing - a copy run.

## The snapshot - the base, proven before it is reused

The snapshot is the **base**: the copy as test:copy:build leaves it at its cold-boot halt - the Pis and the node built
(_copy:base), Argo not yet on it. A run reverts to it, boots it cold (the build's own cold boot) and builds the Argo layer
as the build does (test:copy:argo). Nothing of a former run is in it (a mirror push, a restart history, the Mimir data a
check seeds, a CronJob's missed run). It saves the base's ~21 min of the 49 (copy run 6: base 12:04-12:25, Argo layer
12:26-12:52); a deeper snapshot can be weighed once this one has proven itself. The first design snapshotted the stack
fully built and settled; its review (three Criticals) showed a reverted settled stack is no fresh build.

- **Begun** in _copy:base right after its destroy (`scripts/copy-snapshot.sh begin`): the host's disk checked (350 GB
  free on libvirt's pool by default: three 100 GiB disks at full size and their snapshots), what builds the base hashed
  NOW into a pending record - production's inventory lines the base holds (os, k8s, pkg, containerd-unit, the Pis' and
  kube-system's helm releases) and the Pis' versions; the base's files (the Vagrantfile, deploy/ansible with its
  untracked files, the apt pins and their script, the Taskfile's _copy:base, _vagrant:pi-* and test:copy:build). A hash
  that cannot be computed fails closed: never saved. **Based** at _copy:base's end: this build's base is complete.
- **Saved** at the build's cold-boot halt (`save`): only a base this build made (begun and based - a copy halted after a
  run, its Argo layer on it, is never saved as a base), its hashes still those at its start (a file changed while it
  built is none it was built from), every domain shut down by itself (a forced power-off refused - the Vagrantfile's
  `graceful_halt_timeout` is 300 s), one internal libvirt snapshot each by the UUID vagrant holds, the machines the
  Vagrantfile's. The record **unproven**: the build's last step (`proven`), its Argo layer up on the base booted cold,
  makes it reusable - a base whose cold boot or Argo layer fails is never reused. A save that fails drops what it made
  and never fails the build.
- **Reverted** (`test:copy:ready`): production's inventory read, then - fresh - every domain halted, any managed save
  image removed (libvirt-guests at a host shutdown), reverted, left shut off; booted cold, vms-ready (the VMs' package
  lists refreshed: an install after it reads today's archive), test:copy:argo. A revert that fails drops the record and
  the same run builds; libvirt not answering in time (600 s for a snapshot made, reverted or deleted, 30 s for a read)
  is no verdict - the record dropped, exit 1, never a build racing a revert still running. A reverted base that does not
  come up (its cold boot, vms-ready, its Argo layer) is forgotten: the next run builds.
- **Stale** when: never proven; older than 24 h; the base's inventory lines or the Pis' versions moved (an app's image or
  a CRD moving is no reason - the base holds none); the base's files changed; a domain or its snapshot gone, or another
  domain under a machine's name; the host's disk short; `COPY_SNAPSHOT=off`. libvirt not answering is no verdict
  (exit 1), never "missing"; a domain gone with vagrant's id left is stale.
- **At a run's end** the cycle halts the VMs and marks the copy **used**: test:copy:change, test:copy:check and
  test:copy:playbook refuse it until a run readies it (a fresh Argo layer clears the mark) - a copy carrying the last
  unit is never taken for a fresh one. `task test:copy:drop` destroys the copy and its snapshot.
- **The proof after a fix** builds its base fresh (the cycle forgets the snapshot before it): two proofs never share
  one base - a defect of the base read twice as the unit's ("red after its fix").
- **The lock**: every task that boots, stops, destroys or plays on the copy's VMs takes it first (50 tasks; a nested task
  shares its caller's) - the copy persists between runs now, so a task beside a run would halt it, or a revert the task.
- **Accepted**: a reverted base is up to a day older than a build's - the Debian archive's lists refreshed at the cold
  boot, the base's packages pinned; an upstream download the base makes unpinned is as of its day.

## Changes

- `scripts/copy-snapshot.sh begin|based|save|proven|revert|forget|used|layered|unused|status|drop|disk` and its harness
  (stub vagrant and virsh, a scratch ops tree: every rule above, 41 checks).
- Taskfile: _copy:base begins and bases; test:copy:build saves at its cold-boot halt and proves at its end;
  test:copy:ready (the inventory read, revert or build, the cold boot and the Argo layer - forgotten when it does not come
  up); test:copy:argo clears the used mark; change, check and playbook refuse a used copy; test:copy:drop; the lock on
  every task on the copy's VMs (copy-tasks: asserted for all); test:dual-pi-clean's destroy no longer ignored; the base's
  fingerprint at the cold boot when `COPY_FINGERPRINT=<label>` (tests/ansible/copy/base-fingerprint.yml).
- Vagrantfile: `graceful_halt_timeout` 300. tests/ansible/copy/vms-ready.yml: the package lists refreshed.
- `scripts/upgrade-cycle.sh`: the proof's copy from `test:copy:ready`; marked used and halted, not destroyed, when the
  run ends and after the review; the proof after a fix on a fresh base; its harness and copy-tasks' expected commands.
- The scratchpad copy-run scripts take `test:copy:ready` too.

## Proof

Main against main (no change between the runs - a change would mix two effects):

1. `COPY_FINGERPRINT=fresh task test:copy:ready` with no snapshot: it builds, saves (unproven), proves at its end; the
   base's fingerprint at the cold boot in `.copy/base-fingerprint-fresh.txt`; every check green.
2. 20 h or more later, across 00:00 and 06:00 (the Pis' and Debian's daily timers, the nightly CronJobs' hours):
   `COPY_FINGERPRINT=revert task test:copy:ready`: it reverts ("reverted:" in its log, never a build), the fingerprint
   in `.copy/base-fingerprint-revert.txt`; every check green.
3. The two fingerprints diffed - packages, enabled units, timers, failed units, Consul's members, Vault's state,
   Patroni's members and roles, Gluster's bricks, versitygw's buckets, the cluster's objects, the node's images: equal,
   and no "unreadable" line in either (a fact neither run could read is no fact the two share).
   Both runs' inventories (`.copy/vagrant-inventory.txt`) equal.
4. Stale cases forced: a base file touched - the next ready builds; a domain's snapshot deleted - it builds; the copy
   marked used - change and check refuse it.
5. The full review again, then the cycle on it.
