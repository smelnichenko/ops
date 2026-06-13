# Plan 072: Pi active-passive failover fencing (Consul lock + re-converge timer)

## Status (2026-06-13)

- **Part B (re-converge timer + reset-failed): DONE, deployed to prod**
  (`setup-keepalived.yml`, non-disruptive — no keepalived restart). Timer
  armed on both Pis, converge idempotent.
- **Part A (Consul-lock fence): implemented + VALIDATED IN VAGRANT, NOT yet
  prod-deployed.** Vagrant proofs: exactly-one-active (holder serves, holds
  the lock; non-holder fenced), a second `consul lock minio/active` is
  denied, and the lock releases+re-acquires across a failover. Prod deploy
  (`task deploy:pi-services`, a brief MinIO failover) is the remaining step.
- **Known blocker for a fully-green `task test:dual-pi`:** a pre-existing,
  unrelated Vagrant harness issue — Forgejo crashes on
  `/var/local/forgejo/queues/LOCK: permission denied` and HAProxy:5000 is
  down. Tracked separately (stashed fix needs DB passwords in vagrant vars).
  The fence assertions were validated directly against the live VMs.

## TL;DR

The keepalived active-passive protocol for Nexus/MinIO on pi1/pi2 (Plan
063, hardened 2026-06-13) defends the **single-host** stale-handler flip
that caused the 2026-06-12 dual-active incident. Adversarial review found
two **pre-existing** gaps it does not close:

1. **Cross-host dual-active MinIO.** Nothing fences the old master's MinIO
   *exit* against the new master's *start*. On failover the new VIP holder
   can start MinIO while the old holder's is still draining — two writers
   on the same shared-Gluster `xl-single` data dir. A pi↔pi partition where
   both still reach `ten` produces a *sustained* double-master.
2. **Stable-master crash strand.** keepalived `notify_master` only fires on
   a VRRP *transition*. A service that crashes past its systemd start-limit
   on the stable VIP holder is never re-armed — it stays `failed` until a
   human runs `reset-failed`.

This plan closes both:

- **Fence:** wrap MinIO's `ExecStart` in `consul lock`, so MinIO runs only
  while this node holds a **quorum-enforced** Consul lock. Closes all the
  cross-host races, including the pi↔pi partition (the minority side loses
  Consul quorum → loses the lock → its MinIO is killed).
- **Strand:** a `keepalived-converge.timer` re-runs the converge step every
  few minutes, re-arming any service that crashed out on the stable master.

Both are independent and shippable separately. The fence is the larger,
data-safety-critical change and gets a Vagrant + prod-failover test pass.

## Context

### Current state

`deploy/ansible/playbooks/setup-keepalived.yml` (post-2026-06-13):
mastership is read from **live VIP ownership** (`vip_present()` =
`ip -o addr show to 192.168.11.5/32`) under a per-service `flock`, driving
parameterized `service_master.sh` / `service_backup.sh` from a `SERVICES`
table in `notify_lib.sh`. This correctly serializes handlers *on one host*
and yields a stale takeover within ~1s of a VIP loss.

`deploy/ansible/playbooks/setup-pi-services.yml` MinIO unit
(`/etc/systemd/system/minio.service`):

```ini
[Unit]
Description=MinIO Object Storage
RequiresMountsFor=/var/lib/minio/data
StartLimitIntervalSec=600
StartLimitBurst=3
[Service]
User=minio
Group=minio
EnvironmentFile=/etc/minio/env
ExecStart=/usr/local/bin/minio server /var/lib/minio/data --address :9000
Restart=on-failure
RestartSec=10
```

MinIO is `xl-single` on the **shared** Gluster volume `backup-minio`,
mounted on *both* Pis at `/var/lib/minio/data` (verified: both mount
`<pi-ip>:/backup-minio`, the same replicated volume). Two live MinIO
processes against this dir is the catastrophic outcome the protocol exists
to prevent.

### Why the obvious fences don't work (tested 2026-06-13)

- **flock on the shared Gluster mount.** `flock(2)` (BSD locks) does **not**
  propagate across GlusterFS FUSE clients. Verified: pi1 holds an exclusive
  flock on a file under `/var/lib/minio/data`; pi2 acquires the *same* file
  simultaneously. Ruled out.
- **Peer-health poll** (new master waits for the peer's `:9000/minio/health`
  to stop responding before starting). Fundamentally split-brain-unsafe: it
  cannot distinguish "peer is dead" (must take over) from "peer is
  partitioned but still serving" (must not). Fail-open → dual-active;
  fail-closed → a normal pi-death leaves MinIO down. Ruled out.
- **Consul lock — works.** Consul runs as a 3-node raft (pi1, pi2, `ten`),
  ACLs **disabled** (no token plumbing needed). Verified cross-host mutual
  exclusion: with a **block-acquire** (no `-try`) pi1 holds
  `consul lock test/fp …` and the `.lock` KV key carries pi1's session;
  pi2's `consul lock -try=4s test/fp …` is **denied** (`rc=1`, "timeout
  during lock acquisition"). A quorum operation, so a minority-partition
  node cannot hold or acquire it. This is the correct primitive.

  Gotcha discovered: the **holder must block-acquire** (`consul lock`
  without `-try`). A `-try` on the holder races the session handshake and
  can leave the lock unheld — an earlier test with `-try=1s` on *both* sides
  showed a spurious double-acquire. The fence relies on the holder blocking.

## Design

### Part A — Consul-lock fence for MinIO

Wrap MinIO's launch in `consul lock` so the process runs **iff** this node
holds the `minio/active` lock:

```ini
[Unit]
Description=MinIO Object Storage
RequiresMountsFor=/var/lib/minio/data
After=network-online.target consul.service
Wants=consul.service
StartLimitIntervalSec=600
StartLimitBurst=3
[Service]
User=minio
Group=minio
EnvironmentFile=/etc/minio/env
# consul lock block-acquires minio/active (quorum-enforced, cross-host),
# then execs MinIO as its child. When the lock is lost (this node loses
# Consul quorum, e.g. a partition) consul lock SIGTERMs MinIO. When MinIO
# exits, the lock releases — so the peer's queued consul lock can proceed.
ExecStart=/usr/local/bin/consul lock -name=minio -monitor-retry=3 \
  minio/active \
  /usr/local/bin/minio server /var/lib/minio/data --address :9000
Restart=on-failure
RestartSec=10
TimeoutStartSec=300
```

Key behaviors:

- **Normal failover.** Old holder's `service_backup.sh` stops `minio.service`
  → `consul lock`'s child (MinIO) gets SIGTERM, exits → lock releases. New
  holder's `service_master.sh` starts `minio.service` → its `consul lock`
  **block-acquires** (was contended, now free) → MinIO starts. The new
  MinIO literally cannot start until the old one has exited. Closes the
  stop/start race natively.
- **Hard pi-death.** The dead holder's Consul session invalidates after its
  TTL → lock releases → the survivor acquires. Bounded by the session TTL +
  lock-delay.
- **pi↔pi partition, both reach `ten`.** Consul keeps quorum (`ten` + one
  pi). Only the majority side can hold/acquire the lock; the minority pi's
  session cannot be maintained → its `consul lock` kills its MinIO. Closes
  the sustained double-master (Attack 4).
- **Consul unavailable cluster-wide.** No node can acquire → MinIO runs
  nowhere. Acceptable: Consul is already load-bearing (Patroni DCS), and
  "no MinIO without coordination" is the safe posture for backup data.

keepalived still **places** MinIO on the VIP holder (traffic follows the
VIP); the Consul lock is the **safety fence** on top. Belt-and-suspenders,
appropriate for data-safety-critical state. `service_master.sh`'s readiness
loop already polls `:9000/minio/health/cluster`, so it tolerates the extra
lock-acquisition latency; keep the 90s MinIO readiness budget (may widen to
cover lock-delay during a hard-death failover — measure in Vagrant).

Open questions to resolve during implementation:

- **Lock-delay / session TTL.** `consul lock` default lock-delay is 15s
  (prevents immediate re-grab after a session invalidation). On a hard
  pi-death this adds ≤15s to MinIO failover. Tune via `-lock-delay` if too
  slow; do **not** set it to 0 (re-grab race).
- **Restart thrash.** If `consul lock` exits non-zero on a lost lock,
  `Restart=on-failure` + `StartLimitBurst=3` could burn the start-limit
  during a long partition. Decide between a higher burst, `Restart=always`
  with a longer `RestartSec`, or `-monitor-retry`. Verify against the
  strand fix (Part B) so a partitioned node recovers without manual
  `reset-failed`.
- **Does Nexus need the same fence?** Nexus has an H2 lock that refuses
  concurrent starts (a real cross-host fence via the shared Gluster
  `nexus.lock.db`). Lower priority; the SERVICES table makes adding a
  `consul lock` wrap uniform if we want it. Decide: fence MinIO only, or
  both.

### Part B — re-converge timer for the stable-master strand

A systemd timer + oneshot service that re-runs the converge logic
periodically, re-arming a service that crashed past its start-limit on the
stable VIP holder (where no VRRP transition will re-fire `notify_master`):

```ini
# /etc/systemd/system/keepalived-converge.service  (Type=oneshot)
ExecStart=/etc/keepalived/active_services_master.sh   # VIP holder: re-arms
ExecStart=/etc/keepalived/active_services_backup.sh   # non-holder: ensures stopped
# /etc/systemd/system/keepalived-converge.timer
OnBootSec=2min ; OnUnitActiveSec=3min
```

The handlers already self-gate on `vip_present` under the per-service
flock, so this is idempotent: on the VIP holder the master pass re-arms a
crashed service (a fresh `reset-failed` may be needed first — add it to the
master script's start path), on the non-holder the backup pass keeps it
stopped. Runs independently of the fence; ship first if desired.

Velero already ships a `.timer` in this repo (`setup-velero.yml`) — reuse
that pattern.

## Implementation steps

1. **Part B first (low-risk):** add `keepalived-converge.{service,timer}` to
   `setup-keepalived.yml`; add `systemctl reset-failed "$SVC"` before the
   `start --no-block` in `service_master.sh` so a re-converge clears a
   start-limited unit. Deploy (no failover — timer/service install only).
   Confirm a deliberately-crashed MinIO on the stable master self-heals
   within one timer interval.
2. **Part A:** edit the MinIO unit in `setup-pi-services.yml` to the
   `consul lock` wrapper; add `After/Wants=consul.service`; set
   `TimeoutStartSec`. Tune lock-delay and the Restart policy.
3. Adversarial re-verification (workflow) against both invariants —
   dual-active and availability — with the new mechanism, before deploy.
4. **Vagrant** `task test:dual-pi` (and `test:nexus`): cover normal
   failover, hard-kill of the active Pi, and a simulated Consul-minority
   partition; assert exactly-one-active throughout and self-heal after.
5. **Prod deploy** via `task deploy:pi-services` + `task deploy:keepalived`
   (never `ansible-playbook` directly). Expect a brief MinIO failover.
   Verify: lock held by exactly the VIP holder
   (`consul kv get minio/active/.lock`), MinIO active only there, and a
   manual `systemctl stop minio` on the holder lets the peer acquire only
   after exit.

## Risks & tradeoffs

- **MinIO availability now depends on Consul quorum.** Mitigated: Consul is
  already the Patroni DCS and runs 3-node with `ten`. A total Consul outage
  takes MinIO down — but that is the safe choice for shared backup storage.
- **Failover latency +≤15s** from lock-delay on a hard pi-death. Acceptable
  for a backup store; tune if needed.
- **Two coordination layers** (VIP placement + Consul fence) to reason
  about. Documented here and in the handler comments; the fence is the
  hard invariant, the VIP is placement.
- **Restart/start-limit interaction** during a long partition — must be
  validated with Part B so a recovered node re-arms without a human.

## Rollback

Revert the MinIO-unit change in `setup-pi-services.yml` and re-deploy; the
unit returns to a bare `systemctl`-driven MinIO (current behaviour, with the
documented cross-host gap). The Part B timer is independently removable.
No data migration — the fence only changes how the process is launched.

## Out of scope

- Replacing keepalived/Gluster with a real clustered object store.
- STONITH / power-fencing.
- `test-dual-pi.yml` currently starts MinIO on both Pis and asserts
  liveness on both, masking the single-active invariant — it needs a
  redesign to assert *exactly one* active. Fold into step 4.
