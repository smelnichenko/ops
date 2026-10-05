# Plan 101 - the Pis' tier-0 services: safe to re-run, backed up, then upgraded

Status: decided 2026-10-05 (below); Forgejo 15.0.9 in progress first. Nothing else on the Pis changes yet.

## Context

pi1 and pi2 (Raspberry Pi 5, arm64, Debian 13.7, nothing pending in apt) and ten as third member run what the
cluster stands on: Consul (quorum pi1/pi2/ten), Vault on Consul storage, Patroni + PostgreSQL 17 (Forgejo's and
Keycloak's databases; DCS Consul) behind HAProxy and PgBouncer, Forgejo (Argo CD's git source), Keycloak (every login,
Istio's JWT keys), Nexus (CI's proxies), Caddy, versitygw (the Pi backup store), GlusterFS (ten the arbiter),
keepalived (the VIP .5). Plan 100 left them out (its R28); it carries only the Gluster boot fix (step 00) and
versitygw 1.8.0 (step 25).

Read 2026-10-05 (pi1; pi2 the same), against upstream:

| Service | Running | Target | Path | Reversible | Note |
|---|---|---|---|---|---|
| Forgejo | 15.0.3 | 15.0.9 (LTS to 2027-07-15) | one hop | patch: yes | 15.0.9 fixes an RCE (`git apply` writes arbitrary files) and an OpenID CSRF; next LTS 19 (2027-04) |
| Vault (Community) | 1.21.3 | 2.1.1 | 1.21.3 -> 2.1.1 (or via 2.0.4) | no (snapshot restore) | no 1.22: IBM versioning; Community 1.21 ended at 1.21.4 - only the newest line gets fixes |
| Consul (Community) | 1.20.6 | 2.0.4 | 1.20.6 -> 1.22.7 -> 2.0.4 | no (snapshot restore) | 1.20.6 is 1.20's last Community build; at most 2 majors a hop |
| Patroni | 4.1.0 | 4.1.5 | one hop | yes | 4.1.3: systemd 257's reload (Debian 13 ships 257); 4.1.5 knows PostgreSQL 17.11's new setting |
| Keycloak | 26.5.7 | 26.8.x | one hop, all nodes stopped | no (DB restore) | 26.5 gets no fixes; 26.6-26.8 change schema, OIDC details, themes |
| Nexus CE | 3.90.1-01 | 3.96.4-01 | one hop, stopped | no (restore) | login rate limit on by default (3.93); anonymous Docker pulls per repository (3.91) |
| Caddy | 2.10.0 | 2.11.7 (not 2.11.6) | one hop | yes (old binary) | 16 KiB header cap, 1-minute idle timeouts; builds need Go 1.26 (trixie-backports) |
| versitygw | 1.6.0 | 1.8.0 | plan 100 step 25 | - | - |
| PostgreSQL, PgBouncer, HAProxy, GlusterFS, keepalived | Debian's | Debian's | apt | - | current; plan 101 only pins nothing new |

## What has to change before any version does (found 2026-10-05, read in ops)

- `setup-patroni.yml` deletes PGDATA ("Clear Postgres data for Patroni init") whenever the patroni unit is not
  active - a re-run during an incident wipes that Pi's databases (Forgejo's, Keycloak's).
- `setup-consul.yml` runs `consul keygen` every time: the config changes, the handler restarts all three servers at
  once - Vault and Patroni lose their quorum together.
- Forgejo's and Keycloak's database port flips between HAProxy :5000 and PgBouncer :6432 with whichever playbook ran
  last (setup-pi-services vs setup-patroni).
- Restarting keepalived stops Nexus (its ExecStopPost drop-in).
- Most playbooks cannot upgrade: Consul (`creates:`), Forgejo (get_url without force), Caddy (rebuilt only when the
  porkbun module is missing), Patroni (pip `present`), the apt packages; Vault, Keycloak and Nexus swap the binary and
  never restart - Nexus deletes /opt/nexus under its running JVM. No checksums for Vault, Consul, Forgejo, Keycloak.
- No backup of the tier-0 data at all: no Consul snapshot (Vault's data lives in Consul - the nightly vault-backup
  tars /var/lib/vault, 1.1 MB without it), no dump of Forgejo's or Keycloak's database, no `forgejo dump`, no realm
  export, no Nexus backup. Replication is the only copy. (ops CLAUDE.md claimed a 6-hourly Vault snapshot job: none
  exists - corrected.) Plan 071 (draft) proposed these; none was built.
- The Vagrant copy does not build PgBouncer or Nexus in the upgrade test; the Pi version inventory has versitygw only.

## Order (operator's question 2026-10-05: Pis or ten first?)

Ten first for the majors - its Istio 1.25 and containerd 1.7.24 are out of support, plan 100 is proven against
today's Pis (full run 7 builds them), and its rollout leans on the Pis for days (Forgejo for every merge, Vault for
every secret, the Pi store for every backup). Before plan 100 goes live, only what makes the Pis safer without
changing what plan 100 leans on: phases 0 and 1 below, folded into the fixes of plan 100's full review so the next
full run proves them too (plan 100's production check freezes deploy/ from the proving run on - a Pi change in the
middle of its rollout would stop it). The full run builds the Pis with phase 0's playbooks (their first-install
path); each re-run guard and each phase-1 upgrade is proven by its own Vagrant test, checked from outside the
playbook and revert-checked (task test:pi:rerun-guards, test:pi-backups, test:forgejo-upgrade,
test:patroni-upgrade, test:vault-upgrade). Phase 2 after plan 100's rollout.

## Phase 0 - safe to re-run, backed up, inventoried (no version moves)

1. setup-patroni: the data wipe only on a first install - no Patroni unit and no patroni.dynamic.json on the node
   (Debian's own initial cluster has a PG_VERSION, so that cannot be the test), and never on the node Consul names
   as the leader; never because the unit is stopped (refused). The Keycloak dump restored only in the run that took
   it, then moved aside.
2. setup-consul: the gossip key generated once and kept (Vault, as the other secrets), never regenerated; the kept
   key must be in the running keyring; restarts one server at a time, Patroni paused around each (its leader
   demotes after 10 s without its Pi's agent), each gated on autopilot health (every server healthy - log caught
   up - and one loss tolerated).
3. One database port for Forgejo and Keycloak (PgBouncer :6432), set by one playbook; PgBouncer installed but not
   running is refused, not answered with :5000.
4. keepalived's drop-in: a restart does not stop Nexus (only a real stop or a BACKUP transition).
5. Backups, timed, into the Pi store (offsite copies as the others) with a restore rehearsed in Vagrant each:
   `consul snapshot save` (holds Vault and Patroni's state), pg_dump of every Patroni database, Keycloak realm export,
   `forgejo dump` (stopped-consistent copy at the upgrade; the regular one from the replica). setup-pi-backups.yml,
   restored in Vagrant (task test:pi-backups). Late: infra's kube-system CronJob pi-backup-check reads the bucket's
   last-success every 3 h - older than 26 h or missing fails it, KubeJobFailed fires (local branch
   feat/pi-backup-check, pushed after the Pis' first production backup, or it fires at once).
   Nexus gets no daily backup: read on production 2026-10-05, everything it holds is rebuilt by setup-nexus.yml
   (repositories, realms, anonymous read, the cleanup policy, the admin password; users and roles are Nexus's
   defaults, no content selectors or routing rules) or refilled from upstream (15 GB of proxy cache); its hosted
   content is two torch wheels the playbook uploads and the retired common-1.0.0 jar nothing builds against. Its
   blobs are on Gluster (replica 3). Its phase-2 upgrade copies the H2 database (db/, 37 MB) aside while stopped.
6. The Pi version inventory (scripts/version-inventory-pi.sh) lists every service above by its running process;
   plan 100's checks then cover them too.
7. The Vagrant upgrade copy builds the Pi stack plan 100's steps reach as production runs it - PgBouncer added.
   Nexus and Caddy stay out of the full run (only CI pulls through Nexus; ten's containerd has no mirror, and no
   cluster step reaches either): each gets its Vagrant proof with its phase-2 upgrade (test:nexus exists).

## Phase 1 - patches on the current lines (low risk, reversible)

- Forgejo 15.0.3 -> 15.0.9 (the RCE fix) - first, on its own (decision 2): upgrade-forgejo.yml - a pg_dump, both
  Pis stopped (15.0.9 migrates the database), the VIP's started first, the doctor after.
- Vault 1.21.3 -> 1.21.4 (the line's last Community build): upgrade-vault.yml - a Consul snapshot first, the
  standby, then the active (SIGTERM steps it down: one failover, older to newer), each unsealed by its own script;
  the old binary kept (task test:vault-upgrade, deploy:vault:upgrade).
- Patroni 4.1.0 -> 4.1.5 (pip, pinned in vars/patroni.yml): upgrade-patroni.yml - `patronictl pause --wait`, the
  package on each node, restart one at a time, `resume` (task test:patroni-upgrade, deploy:patroni:upgrade).
Each with a Vagrant proof (the copy at today's versions, the patch applied, the checks green), then production one
Pi at a time with the operator's approval.

## Review (2026-10-05) and the production order

A reliability review and a test audit of phases 0-1 found, and these were fixed before anything ran in production:
upgrade-forgejo.yml let one Pi carry on when the other failed (two versions on one migrated database);
upgrade-patroni.yml ignored its own final health check and passed a paused cluster; upgrade-vault.yml passed a
sealed Vault on a re-run and put the unseal key shares on command lines; the Pi inventory script exited 1 on every
Pi; setup-consul kept a config key Consul never loaded (the old playbook left that on every Vagrant server);
Keycloak's passwords sat in a world-readable unit; the backup script put its token on command lines and could
age out every bucket on an empty name. The tests behind each were rebuilt to check from outside the playbook
(sampled versions and health, Postgres start times and timelines, traced processes, marker rows) and every guard
revert-checked red.

Production order (each step the operator's go):
1. task deploy:forgejo:upgrade (15.0.9).
2. task deploy:pi-backups, then one run of pi-tier0-backup.service.
3. infra branch feat/pi-backup-check pushed (the late-backup check; before the first backup it fires at once).
4. task deploy:patroni:upgrade (4.1.5).
5. task deploy:vault:upgrade (1.21.4; also installs the stdin unseal script).
6. prod-inventory.txt's Pi lines refreshed from production, then plan 100's full run 7.
Keycloak's root-only secrets file reaches production with the next setup-pi-services run (it restarts Keycloak):
with phase 2's Keycloak upgrade.

## Phase 2 - after plan 100's rollout (majors and migrating minors)

Each a step file of its own, through a Vagrant full run and plan 100's production procedure (ledger, Wave 0, soak):
1. Consul 1.20.6 -> 1.22.7 -> 2.0.4: a snapshot before each hop; Patroni paused (or failsafe_mode) during each, servers
   one at a time, followers first. 1.22 validates KV key names - Vault's and Patroni's keys checked first. py-consul
   (Patroni's client) lists Consul up to 1.22: 2.0 with Patroni proven in Vagrant before production.
2. Vault 1.21.4 -> 2.1.1 (or via 2.0.4): a fresh Consul snapshot right before; 2.0 makes `sys/rekey` and
   `sys/generate-root` need a token - the break-glass procedure updated (or `enable_unauthenticated_access`); canonical
   paths (check ESO's and Ansible's); ESO, hvac and Kubernetes auth proven against 2.x in Vagrant (no vendor matrix).
3. Keycloak 26.5.7 -> 26.8.x: both nodes stopped (a minor is a recreate), a database dump first; review 26.6-26.8's
   OIDC changes against our clients (clock skew, `aud`, refresh/offline token expiry, Full Scope Allowed's WARN), the
   CSS-only theme looked at, Istio's JWT validation and every app's login proven in Vagrant.
4. Nexus 3.90.1 -> 3.96.4: stopped, H2 backup and blobs first; login rate limiting (3.93; a 3.94-3.96.3 lockout bug -
   `nexus.auth.ratelimit.enabled=false` if 3.96.4 still has it) against CI's credentials; Docker proxies' anonymous
   pulls (3.91); nexus.vmoptions diffed with 3.96.4's.
5. Caddy 2.10.0 -> 2.11.7: built with Go 1.26 (trixie-backports) - or without the unused porkbun module; header cap and
   idle timeouts tested with a large git push/clone and a big Docker layer through Nexus.
6. Forgejo: stay on 15 LTS (to 2027-07); 19 LTS (2027-04) is the next major - its own plan then.

## Decisions (operator, 2026-10-05)

1. Phases 0-1 before plan 100 goes live, folded into its review fixes and proven by its next full run; phase 2 after
   plan 100's rollout - OK.
2. Forgejo 15.0.9 sooner, on its own - full run 7 stopped (14:14, in its build) to free the Vagrant Pis; it restarts
   with phases 0-1. 15.0.9 adds a database migration (forgejo_migrations: action_run.workflow_source_commit,
   backported) - an older Forgejo does not start on a migrated database, so both Pis stop and the VIP's starts first
   (upgrade-forgejo.yml: pg_dump first, the old binary kept, doctor after; `task deploy:forgejo:upgrade`).
3. Vault's storage: asked whether raft gives HA with two instances - it does not tolerate a loss with two (raft needs
   a majority: three voters, a third Vault on ten). Today two Vaults on Consul's three-server quorum already survive
   one node, and Consul stays for Patroni and HAProxy anyway - recommended: keep Vault on Consul (supported in 2.x;
   Vault on Consul 2.x proven in Vagrant in phase 2).
4. Forgejo stays on the 15 LTS line, patch updates only, until the next LTS (19, 2027-04).

## Unconfirmed (to settle in phase 2's research)

Vault 1.21 -> 2.1 in one hop; Vault's Consul storage and py-consul on Consul 2.x; whether Keycloak can skip minors in
one start (Liquibase applies all - no official sentence); whether Nexus 3.96.4 fixes the lockout bug; whether
caddy-dns/porkbun builds against 2.11; Vault 1.21.4's security content. Sources: the research notes of 2026-10-05
(HashiCorp, Patroni, Forgejo, Keycloak, Sonatype, Caddy release notes and upgrade guides).
