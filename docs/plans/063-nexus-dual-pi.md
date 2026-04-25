# Plan 063: Nexus HA on both Pis (active-passive with Gluster-shared state)

## Context

Nexus today runs on pi1 only (`setup-nexus.yml` targets the `vault_pi` inventory alias = pi1). The cluster has 13 repositories provisioned: 8 proxies, 5 groups, and **3 hosted** (`maven-releases`, `maven-snapshots`, `nuget-hosted`).

**Current usage** (verified via Woodpecker pipelines + build.gradle):
- Nexus port **8082** is a Docker registry pull-through mirror (Kaniko's `--registry-mirror`)
- Maven `maven-public` group serves Gradle dependency downloads
- Container images get pushed to **Forgejo** at `git.pmon.dev`, not Nexus
- The 3 hosted repos are empty today — no pipeline writes to them yet

The hosted repos are provisioned to receive future build-upload artifacts (JAR publishes, NuGet packages). We're building Nexus HA *now* so those uploads are durable from day one, rather than retrofitting HA after hosted-repo usage has already started.

Nexus Repository OSS has no native clustering (that's a paid Pro feature). The correct OSS pattern is **active-passive with shared state**: both Pis have Nexus installed, exactly one Pi runs the service at a time, both the blob store and the H2 metadata DB live on a replicated GlusterFS volume. Keepalived's VIP arbitrates which Pi is active; `notify_master` / `notify_backup` scripts start/stop Nexus on transitions. Failover downtime is ~30–60s (Nexus cold-start).

This mirrors how Forgejo repos are already shared (replica-2 Gluster volume `forgejo-repos` mounted at `/var/lib/forgejo/repos`) — same pattern, new volume.

## Scope

### 0. Promote Gluster from replica-2 → replica-3 with ten as arbiter

Production runs Gluster only on pi1 + pi2 today (replica-2, no quorum). `ten` is already the 3-node tie-breaker for Consul / Patroni / Vault; extending that role to Gluster removes the "irreducible split-brain risk" flagged in §3 below.

Changes in `setup-gluster.yml`:
- Install `glusterfs-server` on `target` (ten) in addition to pi1+pi2
- Peer-probe ten from pi1 on first run (idempotent)
- Create arbiter brick dirs at `/var/lib/gluster/<volume>-arbiter-brick` on ten
- New volumes: `gluster volume create ... replica 3 arbiter 1` (includes ten arbiter from start)
- Existing replica-2 volumes (production `forgejo-repos`, `backup-minio`, `backup-git-mirror`): detect brick count, if =2 run `gluster volume add-brick <name> replica 3 arbiter 1 ten:/var/lib/gluster/<name>-arbiter-brick` (one-time migration, idempotent — skipped if count already 3)
- Pattern matches Consul's native-systemd deployment on ten; no k8s pod, no Istio sidecar. Arbiter storage cost on ten: hundreds of MB for metadata only (no file content)

After this change, pi1↔pi2 split-brain becomes recoverable: whichever side can still reach ten's arbiter gets write quorum; the other side refuses writes. Gluster healing on partition recovery knows which side was "right".

### 1. Add a `nexus-data` GlusterFS volume (`setup-gluster.yml`)

New replica-3-with-arbiter volume alongside the existing volumes:

- Brick path: `/var/lib/gluster/nexus-brick` on pi1 + pi2
- Arbiter brick path: `/var/lib/gluster/nexus-arbiter-brick` on ten
- Mount: `/mnt/data/nexus` on pi1 + pi2 only (owner `nexus:nexus`, mode `0755`). ten doesn't mount it — arbiter only votes on metadata consistency.
- Uses the same idempotent "create → start if not Started → mount" pattern already in the playbook

### 2. Install Nexus on both Pis (`setup-nexus.yml`)

- `hosts: vault_pi` → `hosts: pis`
- Drop the `/mnt/data/nexus` assume-exists behaviour; the Gluster mount (step 1) provides it
- Install binary, user, systemd unit on both Pis
- **Service enabled but NOT started by default** — Keepalived drives state (step 3). A stray `systemctl start nexus` on both Pis would corrupt the shared H2 DB
- First-time init tasks (repos, admin password via REST) run against `http://localhost:8081` on whichever Pi currently has Nexus active. Gated with `run_once: true`, delegated to that Pi.

### 3. Keepalived drives Nexus start/stop (`setup-keepalived.yml`)

Replace the existing "include Nexus in the generic health check" idea — Nexus isn't checked, it's **controlled** by Keepalived:

**Why conflict prevention actually works** (three independent layers):

1. **VRRP election** — exactly one Pi holds the VIP in the common case. notify_master fires only on the winner.
2. **Nexus's own H2 lock** (`/mnt/data/nexus/db/nexus.lock.db`) — if two Nexus instances ever race to start against the same data dir, the second one's JVM sees the lock held and exits with an error. Built into Nexus, not configured by us — this is the *hard* fence.
3. **Gluster replica-3 arbiter (§0)** — during a pi1↔pi2 network partition, only the side that still reaches ten's arbiter gets Gluster write quorum. The other side gets `EROFS` on writes; its Nexus crashes on the first blob write. Prevents divergent blobs / corrupt H2.

The `.active-on-<hostname>` sentinel under `/mnt/data/nexus/` is purely informational — notify_master logs if a stale one exists but relies on layers 2+3 for actual safety. No inter-Pi SSH calls, no stop-before-start dance: Keepalived's own notify_backup on the losing side handles the clean stop.

**notify scripts**:

- `notify_master` (Pi that just gained the VIP):
  1. Log any stale `.active-on-<other>` sentinel (warn only — not blocking)
  2. Write `/mnt/data/nexus/.active-on-$HOSTNAME`
  3. `systemctl start nexus` (Nexus's H2 lock refuses if another instance is active)
  4. Poll `curl http://localhost:8081/service/rest/v1/status` for up to 180s
- `notify_backup` / `notify_fault` (Pi that just lost the VIP):
  1. `systemctl stop nexus` (clean shutdown releases H2 lock)
  2. Remove `/mnt/data/nexus/.active-on-$HOSTNAME`

The existing `check_services.sh` (Forgejo/Keycloak/Patroni) stays as-is — Nexus is intentionally **excluded** from that health check. A failing Nexus shouldn't swap Forgejo/Keycloak/Patroni too.

**Split-brain resistance** comes from §0 above — replica-3 with ten as arbiter. During a pi1↔pi2 partition, at most one side can still reach ten's arbiter, so only that side gets Gluster write quorum. The isolated side refuses writes, so the fencing sentinel + Nexus H2 lock don't get corrupted blob writes under them. Keepalived `nopreempt` prevents VIP flap after recovery.

### 4. Caddy — no change

Already runs on both Pis. Each Pi proxies `nexus.pmon.dev → localhost:8081` and `nexus-docker.pmon.dev → localhost:8082`. When VIP is on pi1, pi1 Caddy answers; its local Nexus is up. When VIP floats to pi2, pi2 Caddy answers; its local Nexus comes up within ~45s of the notify_master script firing. Caddy ACME state might diverge between the two Pi installs — acceptable, both hit the Porkbun DNS-01 webhook independently.

### 5. Rewrite `tests/ansible/test-nexus.yml` for the HA model

- `hosts: pis` for inventory facts, but assertions run selectively:
  - On the **VIP-holding Pi**: Nexus service `active`, health 200, 13 repos provisioned, DockerToken realm, Maven/npm/PyPI proxies
  - On the **non-VIP Pi**: Nexus service `inactive` (expected — Keepalived hasn't asked it to start)
- VIP-level curl: `curl https://nexus.pmon.dev/service/rest/v1/status` (via the VIP) returns 200
- Failover scenario (scope-worthy since this is the whole point):
  1. `systemctl stop keepalived` on the active Pi
  2. Wait ≤ 90s for VIP to float to the other Pi AND that Pi's Nexus to reach `200` on localhost
  3. Assert VIP-level curl still works
  4. Assert hosted-repo contents are intact (write a sentinel artifact pre-failover, read it post-failover)
  5. Restart keepalived on the original Pi — leave Nexus on the failover Pi running (no flap-back)

### 6. Taskfile `test:nexus`

The test now needs the full Pi stack (Gluster depends on Consul; Keepalived integrates with service health):

```yaml
test:nexus:
  - vagrant destroy -f
  - vagrant up pi1 pi2
  - defer: vagrant halt
  - task: _vagrant:pi-stack          # consul → pi-services → patroni → vault-pi
  - setup-gluster.yml                 # now includes nexus-data volume
  - setup-nexus.yml                   # installs on both, services not auto-started
  - setup-keepalived.yml              # notify scripts start nexus on VIP owner
  - tests/ansible/test-nexus.yml     # includes failover scenario
```

## Files modified

| Path | Change |
|---|---|
| `deploy/ansible/playbooks/setup-gluster.yml` | add `nexus-data` volume to the `backup_volumes` loop + mount at `/mnt/data/nexus` |
| `deploy/ansible/playbooks/setup-nexus.yml` | `hosts: pis`; drop `/mnt/data/nexus` assumption; service enabled but `state: stopped`; admin + repo init via `run_once` delegated to VIP holder |
| `deploy/ansible/playbooks/setup-keepalived.yml` | add `notify_master` / `notify_backup` / `notify_fault` scripts; add `vrrp_instance` directives referencing them |
| `tests/ansible/test-nexus.yml` | `hosts: pis`; split active/inactive assertions; add failover scenario with sentinel artifact |
| `Taskfile.yml` | `test:nexus` uses `_vagrant:pi-stack` + setup-gluster + setup-nexus + setup-keepalived |
| `docs/plans/063-nexus-dual-pi.md` | save this plan alongside 062 |

## Execution order

1. **Save this plan** as `ops/docs/plans/063-nexus-dual-pi.md`
2. Extend `setup-gluster.yml` with `nexus-data` in `backup_volumes` (same loop that handles backup-minio / backup-git-mirror). Mount handled by existing "Mount backup volumes" task.
3. Rewrite `setup-nexus.yml`:
   - `hosts: pis`
   - Remove dir-assumption tasks (Gluster mount provides it)
   - All binary/service/UFW tasks run on both Pis
   - Admin password + repo-init block wrapped with `run_once: true` + `delegate_to: "{{ groups['pis'] | first }}"` (Keepalived MASTER starts with pi1)
   - `systemd` unit: `enabled: true`, `state: stopped` (not started directly)
4. Add notify scripts + vrrp directives to `setup-keepalived.yml`
5. Rewrite `test-nexus.yml`:
   - Query Patroni-style: which Pi currently has VIP?
   - Assertions delegate to active/inactive Pi accordingly
   - Sentinel-artifact upload + failover + read-back
6. Update `Taskfile.yml` `test:nexus` chain
7. Syntax-check all 4 touched playbooks + the test
8. `task test:nexus` end-to-end — expect: Gluster volume created, Nexus installed on both, VIP owner has Nexus running, other Pi has Nexus inactive, failover test passes, sentinel artifact survives the transition
9. Idempotency: re-run `task test:nexus` second time (no destroy) — all deploy tasks `ok=…, changed=0`
10. Production migration plan (out-of-band, when you're ready): stop nexus on pi1 → snapshot `/mnt/data/nexus` → migrate to Gluster volume → redeploy on both Pis

## Verification

1. `task test:nexus` — ends `failed=0` across every PLAY RECAP, including the failover scenario
2. During test: SSH to both Pis, confirm exactly ONE has `systemctl is-active nexus` = `active`; the other is `inactive`
3. Sentinel: a jar uploaded to `maven-releases` on pi1 is readable via the VIP after pi1 keepalived is stopped and pi2 takes over
4. Idempotency: second `task test:nexus` (no destroy) has `changed=0` on every deploy task; no Nexus restart triggered
5. Split-brain guard: manually delete `/mnt/data/nexus/.active-on-*` on both Pis, start Nexus on both simultaneously — second start should abort via the fencing check (not corrupt the H2 DB)

## Known caveats

### Partial network partition between pi1↔pi2 (Case B split-brain risk)

If the link between pi1 and pi2 dies but **both** can still reach ten, each Pi's Keepalived sees no VRRP from the other → both claim the VIP. Gluster-with-arbiter doesn't help here because each side has 2 of 3 bricks reachable (self-data + ten-arbiter) → both have write quorum → both Nexus instances can run and write to their own data brick. Arbiter tracks both sides' writes as concurrent.

When the partition heals, Gluster flags the divergent files as split-brain and **refuses to read or write them** until resolved. No silent data corruption — the failure is loud and fail-closed.

**Runbook** (operator response):
```
# 1. Identify split-brain files on both Pis
gluster volume heal nexus-data info split-brain
gluster volume heal forgejo-repos info split-brain  # if also affected

# 2. Pick the surviving side and heal the other
#    latest-mtime is the usual choice for a caching proxy
gluster volume heal nexus-data split-brain latest-mtime /
gluster volume heal nexus-data

# 3. Restart Nexus on whichever Pi currently holds the VIP
systemctl restart nexus
```

Typical resolution time: 2-5 minutes. Could be automated with Consul-based distributed locking, but the added complexity (lock-delay amplification during failover, new Consul dependency, two-clock mismatch between VRRP and Consul sessions) wasn't justified for a rare, loud, manually-resolvable failure. Revisit if Case B happens in practice.

## Out of scope

- Consul-based distributed lock for Case B automatic resolution — see caveat above; premature for observed failure rate
- Migrating hosted-repo blob storage to MinIO S3 (future option; would need Pro or a custom sync layer)
- Backup of `/mnt/data/nexus` to offsite MinIO — already covered by the general Pi backup cron
- Caddy ACME state sharing between the two Pis (current independent renewal is fine)
