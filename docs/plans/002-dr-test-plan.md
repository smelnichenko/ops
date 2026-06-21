# Disaster Recovery Test Plan

Automated Ansible playbook (`tests/ansible/test-dr.yml`) that runs in **Vagrant
(kubeadm)** to validate pod recovery, full namespace restore from a Velero
backup, and offsite restore from a third copy. Invoked via `task test:dr`
(raw) or `task dr:drill` (runs it + records the result to Prometheus).

## Last Run

Revived **2026-06-21** after harness entropy had accumulated since the last
green run (2026-03-05). The revival:

- Modernised the deploy to the current architecture: Keycloak SSO (the
  `schnappy-auth` chart), valkey (not redis), Istio ingress with the retired
  Spring Cloud gateway removed. The monitor now validates JWTs in-app against
  the in-cluster Keycloak's JWKS (`keycloak.jwksUri` chart override).
- Hardened cold-pull provisioning (pre-pull the heaviest images with retries +
  padded readiness timeouts) and gated `smartctl_exporter` to hosts with real
  SMART drives (a Vagrant virtio disk has none).

**All four suites pass** (`target ok=253, failed=0`) as of 2026-06-21 — pod
recovery (incl. CNPG postgres), full Velero + CNPG-barman restore, and offsite
3rd-copy restore, with data integrity verified after both restores (the seeded
monitor survives each). Suite 4 (k6 smoke) skips when no k6 CronJob is present.

## Scope

Four suites in a single playbook (`hosts: target` = the kubeadm node), run
sequentially. The data layer is stood up first: `setup-test-postgres` (an
ephemeral CNPG cluster with the per-service **and `keycloak`** databases) and
`setup-test-valkey`; then `schnappy-auth` deploys Keycloak and the `schnappy`
chart deploys monitor + site, with an HTTPRoute on the Istio gateway exposing
the app.

### Suite 1: Pod Recovery

Seeds data through the **Keycloak SSO** path (create a realm user via `kcadm`,
assign realm roles incl. METRICS, mint a token via the `test-cli` password
grant), then deletes pods and verifies recovery + data integrity.

| # | Test | Validation |
|---|------|------------|
| 1 | Seed: KC user + token + page monitor | monitor created, token authorizes |
| 2 | Kill `monitor` pod | restarts, health UP, seeded data intact |
| 3 | Kill `postgres` (CNPG) pod | restarts, app reconnects, data intact |
| 4 | Kill `valkey` pod | restarts, app health UP |
| 5 | Kill `site` pod | restarts, HTTP 200 on `/` |
| 6 | Kill ALL pods | full stack recovers, data intact |

### Suite 2: Full DR (Velero backup → destroy → restore)

Deploy Velero + a test MinIO, back up the `schnappy` namespace, **delete the
namespace** (simulated disaster), restore from the backup, and verify the app
boots with all data + monitor config intact.

### Suite 3: Offsite Restore (third copy on vault-pi)

Rsync the MinIO backup to vault-pi, wipe the primary + destroy the namespace,
rsync back, restart MinIO, restore from the recovered backup, verify data.

### Suite 4: Post-restore smoke

Run the k6 smoke job against the restored endpoints.

## Recording (manual cadence)

`task dr:drill` runs the full drill and, only on a genuinely passing run,
pushes `restore_verify_success` to the prod Prometheus pushgateway
(`schnappy-pushgateway.schnappy-infra`, job `dr-drill`). The
**RestoreVerificationFailing** alert fires if no successful drill is recorded
for 35 days — the reminder that backups are unverified. There is no scheduler:
the drill is run on demand (it needs Vagrant/libvirt, so it cannot run in CI).

## Usage

```bash
task test:dr     # raw drill: vagrant destroy → up → provision → restore suites
task dr:drill    # the drill + record restore_verify_success on success
```

`task test:dr` starts the VMs (`vagrant up` dep) and halts them on completion
(`defer: vagrant halt`). NOTE: its exit code is masked by that defer, so
`dr:drill` decides success from the playbook's `=== ALL DR TESTS PASSED ===`
marker, not `$?`.

## Vagrant VM resources

| VM | CPUs | RAM |
|----|------|-----|
| kubeadm | 8 | 20GB |
| pi1 / pi2 | 2 | 2GB |

## Key design decisions

1. **Keycloak SSO seed** — API registration is retired; the seed creates a
   realm user via `kcadm` and mints a token via a `test-cli` password-grant
   client. The monitor verifies the token signature against the in-cluster
   Keycloak JWKS while `iss` matches the public `https://localhost` issuer.
2. **Three charts, separate releases** — `setup-test-postgres`/`-valkey` for
   the data layer, `schnappy-auth` (release `schnappy-auth`,
   `fullnameOverride=schnappy` → renders `schnappy-keycloak`), and the
   `schnappy` app chart, mirroring `tasks/deploy-app.yml`.
3. **Velero on-demand** — Suite 2 deploys Velero + a test MinIO with throwaway
   creds; no production secrets.
4. **Cold-pull hardening** — the heaviest CNI/mesh/storage images are
   pre-pulled with retries before their deadline-gated installs, and the
   tightest readiness waits are padded, so a slow Vagrant cold pull doesn't
   trip a Deployment progress deadline.

## Lessons learned

- The harness rots: upstream Helm repos move (the hyperspike valkey-operator
  went OCI), images drift, and Vagrant-only mismatches surface (no SMART drives
  → `smartctl_exporter` must be gated). Each fresh run can uncover the next
  stale link.
- Keycloak DB: KC authenticates as the CNPG `postgres` superuser against a
  `keycloak` database (created in the CNPG `postInitSQL`) via a Secret named
  `schnappy-postgres` carrying `POSTGRES_USER`/`POSTGRES_PASSWORD` — not a
  separate keycloak user.
- Cold image pulls, not docker.io rate limits, were the provisioning flake:
  the host egress had 95/100 pull budget free at failure time.

## Playbook

[tests/ansible/test-dr.yml](../../tests/ansible/test-dr.yml)
