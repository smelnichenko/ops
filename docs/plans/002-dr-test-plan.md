# Disaster Recovery Test Plan

Automated Ansible playbook (`test-dr.yml`) that runs in Vagrant to validate pod recovery, full k3s disaster recovery, and offsite backup restore. Invoked via `task test:dr`.

## Last Run

All 3 suites fully passing as of 2026-03-05 (ok=124, changed=20, failed=0).

## Scope

Three test suites in a single playbook, run sequentially:

### Suite 1: Pod Recovery (k3s stays running)

Tests that individual pods recover after deletion and the app returns to a healthy state with data intact.

| # | Test | Method | Validation |
|---|------|--------|------------|
| 1 | **Seed test data** | Register user via API, auto-verify email, assign Admins group, create page monitor, trigger check | User exists, monitor result stored |
| 2 | **Kill app pod** | `kubectl delete pod -l app.kubernetes.io/component=app` | Pod restarts, health endpoint returns UP, API returns seeded data |
| 3 | **Kill postgres pod** | `kubectl delete pod -l app.kubernetes.io/component=postgres` | Pod restarts, app reconnects (HikariCP), seeded data intact |
| 4 | **Kill redis pod** | `kubectl delete pod -l app.kubernetes.io/component=redis` | Pod restarts, app health UP |
| 5 | **Kill frontend pod** | `kubectl delete pod -l app.kubernetes.io/component=frontend` | Pod restarts, HTTP 200 on `/` |
| 6 | **Kill all pods simultaneously** | `kubectl delete pods --all -n monitor` | All pods restart, full stack healthy, seeded data intact |

Each test follows the pattern:
1. Delete pod(s)
2. Wait for rollout (`kubectl rollout status` with timeout)
3. Verify health (probes, API responses)
4. Re-login (JWT tokens invalidated by pod restart)
5. Verify data integrity (query API for seeded data)

### Suite 2: Full k3s Disaster Recovery (Velero backup/restore)

Tests complete namespace destruction and restore from Velero backup.

| # | Step | Method | Validation |
|---|------|--------|------------|
| 1 | **Deploy Velero** | Inline Helm + MinIO with test creds (minioadmin/minioadmin) | Velero pod running, BSL Available |
| 2 | **Verify seed data** | Query API — user + monitor + results from Suite 1 still present | Data intact |
| 3 | **Create Velero backup** | Apply `Backup` CRD, poll `.status.phase` | Backup status = Completed |
| 4 | **Destroy monitor namespace** | `kubectl delete namespace monitor` | Namespace gone, all pods/PVCs deleted |
| 5 | **Restore from backup** | Apply `Restore` CRD, poll `.status.phase` | Restore status = Completed |
| 6 | **Wait for pods** | `kubectl rollout status` for all deployments | All pods Running |
| 7 | **Verify data integrity** | Re-login (same creds), query monitors API | Same user, same monitor config, same results |
| 8 | **Verify app functionality** | Trigger a manual check | App fully functional post-restore |

### Suite 3: Offsite Restore (3rd copy from vault-pi)

Tests restore from the offsite backup copy on vault-pi. Simulates primary backup storage (SATA SSD) failure.

| # | Step | Method | Validation |
|---|------|--------|------------|
| 1 | **Setup SSH k3s → vault-pi** | Generate ed25519 keypair, push pubkey to vault-pi | SSH connectivity test passes |
| 2 | **Rsync to vault-pi** | `rsync -az` MinIO data to vault-pi:/mnt/backups/offsite/ | Files present on vault-pi |
| 3 | **Wipe primary + destroy namespace** | `rm -rf` MinIO data + `kubectl delete namespace monitor` | All data gone on k3s |
| 4 | **Rsync back from vault-pi** | `rsync -az` vault-pi → k3s MinIO directory | Files restored |
| 5 | **Restart MinIO + wait BSL** | Delete MinIO pod, wait for BSL Available | Velero sees recovered data |
| 6 | **Verify backup visible** | Check `dr-test` backup status from recovered MinIO | Backup Completed |
| 7 | **Velero restore** | Apply `Restore` CRD from offsite-recovered backup | Restore Completed |
| 8 | **Verify data integrity** | Re-login, query monitors API | Same data as before |
| 9 | **Verify app functional** | Trigger manual check | App working post-restore |
| 10 | **Cleanup** | Remove SSH keys, delete backup/restore objects | Clean state |

## Usage

```bash
task test:dr        # Start VMs, run DR tests, shut down VMs (~8 min)
```

`task test:dr` automatically starts Vagrant VMs via `vagrant:up` dependency and shuts them down on completion (or failure) via `defer: vagrant halt`. No manual VM management needed.

To keep VMs running for debugging:

```bash
task vagrant:up     # Start VMs manually
cd deploy/ansible && venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/test-dr.yml
task vagrant:halt   # Stop VMs when done
task vagrant:destroy  # Destroy VMs entirely
```

### Vagrant VM resources

Sized for Intel Core Ultra 125H (14C/18T) + 32GB RAM:

| VM | CPUs | RAM | Disk |
|----|------|-----|------|
| k3s | 10 | 20GB | 20GB |
| vault-pi | 2 | 2GB | default |

## Test execution flow

```
Play 0: Prepare vault-pi
  PASS  Install rsync, create offsite dir

Suite 1: Pod Recovery
  PASS  Seed test data (register, create monitor, trigger check)
  PASS  Kill app pod -> verify recovery + data
  PASS  Kill postgres pod -> verify recovery + data
  PASS  Kill redis pod -> verify recovery
  PASS  Kill frontend pod -> verify recovery
  PASS  Kill all pods -> verify full recovery + data

Suite 2: Full k3s DR
  PASS  Deploy Velero + test MinIO
  PASS  Trigger pg_dump + create Velero backup
  PASS  Delete monitor namespace (simulates disaster)
  PASS  Restore from Velero backup
  PASS  Verify all pods healthy
  PASS  Verify data integrity (login, monitors, results)
  PASS  Verify app functional (trigger new check)

Suite 3: Offsite Restore
  PASS  Setup SSH k3s -> vault-pi
  PASS  Rsync MinIO data to vault-pi
  PASS  Wipe primary backup + destroy namespace
  PASS  Rsync back from vault-pi
  PASS  Restart MinIO, verify BSL available
  PASS  Verify backup visible from recovered data
  PASS  Velero restore from offsite backup
  PASS  Verify data integrity (login, monitors, results)
  PASS  Verify app functional (trigger new check)
  PASS  Cleanup (SSH keys, restore objects)
```

## Key design decisions

1. **Single playbook** — all suites in one file, each suite depends on previous suite's state
2. **Two-play structure** — Play 0 targets vault-pi (rsync prep), Play 1 targets k3s (all tests)
3. **Runs on Vagrant** — requires both k3s + vault-pi VMs (the Vagrantfile provisions both)
4. **Velero deployed on-demand** — Suite 2 deploys Velero with test MinIO creds, no production secrets needed
5. **API-driven validation** — uses `ansible.builtin.uri` to call REST endpoints, not kubectl to inspect DB directly
6. **Idempotent** — can be re-run; re-seeds data if user already exists (register returns 400, login still works)
7. **MinIO for Velero uses /tmp** — HostPath PV under `/tmp/velero-test-backups`, no `/mnt/backups` needed
8. **Velero backup/restore via CRDs** — uses `kubectl apply` for Backup/Restore CRDs and polls `.status.phase`, avoiding the need for `velero` CLI on the host or `kubectl exec` into the velero pod
9. **Ephemeral SSH keys** — Suite 3 generates a temporary ed25519 keypair for k3s → vault-pi rsync, cleans up after
10. **Suite 2 keeps backup for Suite 3** — `dr-test` backup object is preserved so Suite 3 can verify it survives MinIO data wipe + restore

## Lessons learned

- **Auth uses `email` not `username`** — `AuthRequest` record is `(String email, String password)`, both register and login use `email` field
- **Registration returns 201** — not 200; duplicate registration returns 400 (not 409) with generic "Registration failed" to prevent email enumeration
- **Email verification required** — new users must verify email before login; in test, auto-verify via direct DB update of `email_verification_tokens.used = true`
- **New users have no groups** — must assign groups (e.g., Admins) via DB for API access; METRICS permission required for monitor endpoints
- **MinIO mc needs MC_CONFIG_DIR** — mc image runs as non-root user 1000 with no writable home; must set `MC_CONFIG_DIR=/tmp/mc` for `mc alias` to work
- **Velero CLI not available inside pod for kubectl exec** — `velero` inside the pod can't use `--kubeconfig`; use Backup/Restore CRDs via `kubectl apply` instead
- **Helm pod labels** — pods use `app.kubernetes.io/name=monitor,app.kubernetes.io/component=app` (not `app=monitor-app`)
- **Ansible shell uses /bin/sh** — `<<<` (here-string) is bash-only; `ssh-keygen` prompts avoided with `-N "" -q` instead of `<<< y`

## Playbook

[tests/ansible/test-dr.yml](../tests/ansible/test-dr.yml)
