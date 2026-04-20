# Ops

Operational tooling, deployment automation, and testing for pmon.dev.

## Architecture

Contains everything needed to provision, deploy, and test the pmon.dev infrastructure. Ansible playbooks set up the k3s cluster and all supporting services. Vagrant provides reproducible integration test environments. The Taskfile is the primary interface for all operations.

## Contents

```
ops/
  Taskfile.yml           # Task runner (build, test, deploy commands)
  docker-compose.yml     # Local development stack (PostgreSQL, Redis, Kafka, ScyllaDB, etc.)
  Vagrantfile            # Vagrant VMs for integration testing
  deploy/
    ansible/
      playbooks/         # Ansible playbooks for all infrastructure
      inventory/         # Production and Vagrant inventories
      vars/              # Configuration variables
  tests/
    ansible/             # Vagrant integration test playbooks
    k6/                  # k6 load test scripts
  scripts/               # Utility scripts
  docs/
    plans/               # Design and implementation plans
```

## Quick Start

```bash
task dev              # Start all infra + backend + frontend
task dev:infra        # Start only infra (for IDE debugging)
task dev:stop         # Stop local environment
task test             # Run backend + E2E tests
task test:backend     # Gradle tests only
task deploy:status    # Check production pod status
```

## Ansible Playbooks

| Playbook | Command | Purpose |
|----------|---------|---------|
| `setup-kubeadm.yml` | `task deploy:kubeadm` | kubeadm cluster provisioning |
| `setup-pi-services.yml` | `task deploy:pi-services` | Forgejo, Keycloak, MinIO, HAProxy on Pis |
| `setup-woodpecker.yml` | `task deploy:woodpecker` | Woodpecker CI |
| `setup-velero.yml` | `task deploy:velero` | Velero backups + MinIO |
| `setup-vault-pi.yml` | `task deploy:vault-pi` | Vault unseal server (Pi) |
| `setup-vault.yml` | `task deploy:vault` | Vault on kubeadm + ESO |
| `setup-nexus.yml` | `task deploy:nexus` | Nexus repository manager (Pi) |

## Integration Tests (Vagrant)

```bash
task test:vault           # Vault + ESO integration
task test:elk             # ELK stack integration
task test:grafana         # Grafana + Prometheus
task test:kafka-scylla    # Kafka + ScyllaDB
task test:dr              # Disaster recovery
task test:hashcash        # Hashcash PoW captcha
task test:nexus           # Nexus repository manager
task test:flux            # Flux CD GitOps
```

## Deployment

This repo does not deploy directly to production. It provides the tooling:

- **Initial setup:** `task deploy:full` provisions k3s and installs all infrastructure
- **Ongoing deploys:** Handled by Flux CD GitOps (image tags committed to `schnappy/infra` by Woodpecker)
- **Infrastructure changes:** Run the relevant `task deploy:*` command
