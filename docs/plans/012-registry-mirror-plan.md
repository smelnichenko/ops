# Docker Registry Pull-Through Cache Plan — DONE

Deploy three registry:2 pull-through cache instances on the Pi (192.168.11.4) to avoid Docker Hub rate limits and speed up Vagrant test cycles.

## Decision

**registry v3.0.0 x3** — one instance per upstream registry (Docker Hub :5000, Elastic :5001, Quay :5002), running as standalone binaries via systemd on the Pi (no Docker dependency).

Alternatives evaluated and rejected: Zot (k3s rewrite bugs), Harbor (no arm64, 4GB+), Nexus (8GB RAM minimum), Artifactory (no arm64), Dragonfly/Kraken (P2P needs multi-node), Spegel (single-node useless), airgap tarballs (fragile), auth-only (still has ceiling).

## Architecture

```
                          ┌──────────────────────────────────┐
                          │  Pi (192.168.11.4)               │
                          │                                  │
aqua (Docker)  ──────────►│  :5000 → registry-1.docker.io   │
ten (k3s)      ──────────►│  :5001 → docker.elastic.co      │
Vagrant k3s VM ──────────►│  :5002 → quay.io                │
                          │                                  │
                          │  /mnt/data/registry-cache/       │
                          └──────────────────────────────────┘
```

## Implementation

- `deploy/ansible/playbooks/setup-registry-mirror.yml` — Pi playbook: standalone registry binary (distribution/distribution v3.0.0), 3 systemd services, UFW, weekly GC cron
- `deploy/ansible/playbooks/setup-k3s.yml` — registries.yaml with 3 mirrors (conditional on `registry_mirror_ip` var)
- `Vagrantfile` — registries.yaml written before k3s install in `install-deps` provisioner
- `Taskfile.yml` — `deploy:registry-mirror` task, integrated into `deploy:full`
- `deploy/ansible/vars/production.yml` — `registry_mirror_ip: 192.168.11.4`

## Vagrant Flow

- `registries.yaml` written before k3s starts → containerd configured with mirrors on first boot
- First `vagrant up`: all images pulled through Pi (cached on NVMe)
- Subsequent cycles: zero upstream pulls, all served from Pi's cache at LAN speed
- If Pi is down: k3s falls back to upstream registries automatically

## Manual Setup (aqua)

Docker daemon only supports Docker Hub mirrors:
```json
# /etc/docker/daemon.json
{ "registry-mirrors": ["http://192.168.11.4:5000"] }
```
Then `sudo systemctl restart docker`.
