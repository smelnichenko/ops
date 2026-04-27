# Ops

Operational tooling, deployment automation, and integration testing for pmon.dev.

## Architecture

Everything needed to provision, deploy, and test the pmon.dev infrastructure. Ansible playbooks set up the kubeadm cluster and the bare-metal services on the Pis (Vault, Keycloak, Forgejo, MinIO, HAProxy, Patroni, Consul). Vagrant provides reproducible integration test environments. The Taskfile is the primary interface for all operations — never run `ansible-playbook` directly, always use `task deploy:*`.

## Contents

```
ops/
  Taskfile.yml           # Task runner — single entry point for build/test/deploy
  docker-compose.yml     # Local development stack (PostgreSQL, Valkey, Kafka, ScyllaDB, …)
  Vagrantfile            # Vagrant VMs for integration testing
  deploy/
    ansible/
      playbooks/         # Ansible playbooks for all infrastructure
      inventory/         # Production and Vagrant inventories
      vars/              # Configuration variables
  tests/
    ansible/             # Vagrant integration test playbooks
  scripts/               # Utility scripts
  docs/
    plans/               # Design and implementation plans
```

## Quick Start

```bash
task dev              # Start all infra + backend + frontend
task dev:infra        # Start only infra (for IDE debugging)
task dev:monitoring   # Start dev observability stack
task dev:stop         # Stop local environment
task test             # Run backend + E2E tests
task test:backend     # Gradle tests only
task deploy:status    # Production pod status
```

## Ansible Playbooks

| Playbook | Command | Purpose |
|----------|---------|---------|
| `setup-kubeadm.yml` | `task deploy:kubeadm` | kubeadm cluster provisioning |
| `setup-pi-services.yml` | `task deploy:pi-services` | Forgejo, Keycloak, MinIO, HAProxy on the Pis |
| `setup-consul.yml` + `setup-patroni.yml` | (via Pi-services chain) | Consul + Patroni Postgres HA |
| `setup-vault-pi.yml` | `task deploy:vault-pi` | Pi Vault with Consul backend (both Pis) |
| `setup-keycloak-clients.yml` | `task deploy:keycloak-clients` | OIDC client provisioning |
| `setup-argocd.yml` | `task deploy:argocd` | Argo CD bootstrap |
| `setup-istio.yml` | `task deploy:istio` | Istio control plane + ingress |
| `setup-velero.yml` | `task deploy:velero` | Velero backups + MinIO |
| `setup-woodpecker.yml` | `task deploy:woodpecker` | Woodpecker CI |
| `setup-nexus.yml` | `task deploy:nexus` | Nexus repository manager (Pi) |
| `setup-gluster.yml` | `task deploy:gluster` | GlusterFS repo replication |
| `setup-keepalived.yml` | `task deploy:keepalived` | Keepalived VIP |
| `setup-pgbouncer.yml` | `task deploy:pgbouncer` | PgBouncer |
| `setup-caddy.yml` | `task deploy:caddy` | Caddy reverse proxy |
| `verify-restore.yml` | `task deploy:restore:verify` | Velero restore verification |

## Integration Tests (Vagrant)

```bash
task test:dual-pi-clean   # Full HA stack: destroy → up → deploy → assert
task test:dual-pi         # Same, no destroy (fast iteration)
task test:vault-unseal    # Vault auto-unseal after cold start
task test:logs            # ELK stack
task test:grafana         # Grafana + Prometheus + Mimir
task test:kafka-scylla    # Kafka + ScyllaDB
task test:realtime        # Centrifugo realtime
task test:dr              # Disaster recovery
task test:failure-modes   # Fault injection
task test:argocd          # Argo CD bootstrap
task test:cicd            # End-to-end CI/CD
```

## Deployment

This repo does not deploy applications directly — it provisions and configures the infrastructure they run on:

- **Initial setup:** `task deploy:full` provisions kubeadm and installs all infrastructure
- **Application deploys:** Argo CD GitOps (image tags committed to `schnappy/infra` by Woodpecker)
- **Infrastructure changes:** Run the relevant `task deploy:*` command
