# HashiCorp Vault HA Deployment Plan — On-Prem Kubernetes

## Ansible Quickstart

All phases below are automated via two Ansible playbooks:

```bash
# 1. Setup unseal Pi (installs Vault, TLS, transit engine; prompts to save keys offline)
task deploy:vault-pi

# 2. Deploy k3s Vault cluster + ESO + Sealed Secrets + backups + Prometheus monitoring
task deploy:vault

# Or for full fresh deployment (k3s + forgejo + velero + vault + app):
task deploy:full
```

**Vagrant end-to-end test** (Intel Core 125H dev machine with 32GB RAM):

```bash
# Start two-VM environment (k3s at 192.168.56.10, vault-pi at 192.168.56.20)
vagrant up

# Run Vault setup in Vagrant
cd deploy/ansible
venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault-pi.yml \
  -e @vars/vault.yml -e @vars/vault-vagrant.yml
venv/bin/ansible-playbook -i inventory/vagrant.yml playbooks/setup-vault.yml \
  -e @vars/vault.yml -e @vars/vault-vagrant.yml -e @vars/vault-pi-runtime.yml
```

Playbooks: [`deploy/ansible/playbooks/setup-vault-pi.yml`](../deploy/ansible/playbooks/setup-vault-pi.yml),
[`deploy/ansible/playbooks/setup-vault.yml`](../deploy/ansible/playbooks/setup-vault.yml)

---

## Overview

This plan covers deploying HashiCorp Vault in high-availability mode on an on-prem k3s cluster,
integrated with External Secrets Operator (ESO) and Sealed Secrets. The unseal mechanism uses
Vault Transit auto-unseal via a standalone Vault instance on a dedicated Raspberry Pi 5 with
NVMe SSD, separate from the k3s node.

**Key design decisions:**

- Unseal Vault on dedicated Pi 5 — isolated failure domain from k3s node
- Raft HA storage for the main Vault cluster — no Consul dependency
- Transit auto-unseal — no cloud KMS dependency
- ESO for dynamic/rotated secrets, Sealed Secrets for static GitOps secrets
- Longhorn for replicated PVs (defer until multi-node — see note below)

> **Single-node:** On a single-node cluster skip Longhorn and use `local-path` provisioner
> (already in k3s). When you add nodes, install Longhorn, migrate Vault's PVC
> (`raft snapshot save` → new PVC → restore), and set `numberOfReplicas: 3`.
> Change Vault anti-affinity to `requiredDuringSchedulingIgnoredDuringExecution` and
> scale replicas to 3.

---

## Architecture

```
┌──────────────────────────────────────┐     ┌──────────────────────────────┐
│  Debian Router (Raspberry Pi)        │     │  Dedicated Pi 5 (8GB RAM, 2TB NVMe)  │
│                                      │     │                              │
│  Unbound DNS / ISC-DHCP / UFW        │     │  ┌────────────────────────┐  │
│                                      │     │  │ Unseal Vault (transit) │  │
│  DNS: vault.schnappy.io              │     │  │ - Manual unseal (rare) │  │
│        → <UNSEAL_PI_IP>              │     │  │ - systemd managed      │  │
│                                      │     │  │ - File storage on NVMe │  │
└──────────────────────────────────────┘     │  │ - TLS enabled          │  │
                                             │  │ - UFW: port 8200 only  │  │
                                             │  └────────────────────────┘  │
                                             └──────────────┬───────────────┘
                                                            │ :8200 (TLS)
                                                 ┌──────────┴──────────┐
                                                 │                     │
                                            ┌────▼───┐           (add nodes)
                                            │ Node 1 │
                                            │Vault-0 │
                                            │ (Raft) │
                                            └────────┘
                                                 │
                                        ┌────────▼────────┐
                                        │  Vault Service  │
                                        │  (ClusterIP)    │
                                        └────────┬────────┘
                                                 │
                                    ┌────────────┼────────────┐
                                    │                         │
                               ┌────▼─────┐          ┌───────▼───────┐
                               │   ESO    │          │Sealed Secrets │
                               │Controller│          │  Controller   │
                               └──────────┘          └───────────────┘
```

---

## Phase 1: Unseal Vault on Dedicated Raspberry Pi 5

### 1.1 Pi 5 Base Setup

> **OS note:** Raspberry Pi OS (Debian Trixie/13) uses NetworkManager — configure static IP
> via `nmtui` or `nmcli`, not `/etc/network/interfaces` or `dhcpcd`.

```bash
# Set hostname
sudo hostnamectl set-hostname vault

# Configure static IP via nmtui (interactive) or nmcli:
# nmcli con modify "Wired connection 1" \
#   ipv4.method manual \
#   ipv4.addresses <UNSEAL_PI_IP>/24 \
#   ipv4.gateway <GATEWAY_IP> \
#   ipv4.dns <DNS_IP>
# nmcli con up "Wired connection 1"

# Verify
hostname -I

# Packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y ufw unzip jq curl

# UFW — allow SSH from LAN (IPv4 + IPv6) and port 8200 from k3s node only
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from <LAN_SUBNET>/24 to any port 22 proto tcp    # e.g. 192.168.11.0/24
sudo ufw allow from <LAN_IPV6_SUBNET>/64 to any port 22 proto tcp  # e.g. fd0a:94e6:20b4:9f6b::/64
sudo ufw allow from <K8S_NODE_IP> to any port 8200 proto tcp    # IPv4
sudo ufw allow from <K8S_NODE_IPV6> to any port 8200 proto tcp  # IPv6 (/128)
sudo ufw enable
sudo ufw status
```

### 1.2 Install Vault Binary

```bash
# Always install latest stable — check https://releases.hashicorp.com/vault/
VERSION=1.21.3  # verify current latest before running
curl -fsSL "https://releases.hashicorp.com/vault/${VERSION}/vault_${VERSION}_linux_arm64.zip" \
  -o /tmp/vault.zip
unzip /tmp/vault.zip -d /tmp
sudo mv /tmp/vault /usr/local/bin/vault
sudo chmod +x /usr/local/bin/vault
vault version
```

### 1.3 Vault Configuration

```bash
# Create vault user, directories, and TLS cert BEFORE writing the config
sudo useradd --system --home /var/lib/vault --shell /bin/false vault
sudo mkdir -p /var/lib/vault/data /etc/vault.d/tls
sudo chown -R vault:vault /var/lib/vault /etc/vault.d
```

Create `/etc/vault.d/vault.hcl`:

```hcl
ui = false
# disable_mlock required on Pi (no IPC_LOCK capability without setcap)
disable_mlock = true

storage "file" {
  path = "/var/lib/vault/data"
}

listener "tcp" {
  # [::] = dual-stack IPv4+IPv6 (Linux net.ipv6.bindv6only=0 default)
  address       = "[::]:8200"
  tls_cert_file = "/etc/vault.d/tls/vault-cert.pem"
  tls_key_file  = "/etc/vault.d/tls/vault-key.pem"
}

# Must match DNS name or IP used to connect — must have matching SAN in TLS cert
api_addr = "https://<UNSEAL_DNS_NAME>:8200"
```

### 1.4 TLS Certificate

Use ECDSA P-384 — stronger than RSA at shorter key lengths. The cert must have a SAN matching
the DNS name you'll connect with (not 127.0.0.1 — the Pi uses a different IP for the SAN).

```bash
sudo openssl req -x509 \
  -newkey ec \
  -pkeyopt ec_paramgen_curve:P-384 \
  -days 3650 -nodes \
  -keyout /etc/vault.d/tls/vault-key.pem \
  -out /etc/vault.d/tls/vault-cert.pem \
  -subj "/CN=<UNSEAL_DNS_NAME>" \
  -addext "subjectAltName=DNS:<UNSEAL_DNS_NAME>,IP:<UNSEAL_PI_IP>"

sudo chown vault:vault /etc/vault.d/tls/vault-cert.pem /etc/vault.d/tls/vault-key.pem
sudo chmod 640 /etc/vault.d/tls/vault-key.pem
```

> **VAULT_ADDR must match the SAN.** Use `https://<UNSEAL_PI_IP>:8200` or
> `https://<UNSEAL_DNS_NAME>:8200` — `127.0.0.1` will fail certificate verification.

### 1.5 Systemd Service

Create `/etc/systemd/system/vault.service`:

```ini
[Unit]
Description=Vault Unseal Server
After=network-online.target
Wants=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vault
sudo systemctl status vault
```

### 1.6 Initialize and Configure

```bash
# Use the Pi's IP (or DNS name once configured) — must match cert SAN
export VAULT_ADDR="https://<UNSEAL_PI_IP>:8200"
export VAULT_CACERT="/etc/vault.d/tls/vault-cert.pem"

# Initialize with 3 key shares, threshold 2
vault operator init -key-shares=3 -key-threshold=2

# SAVE THE UNSEAL KEYS AND ROOT TOKEN OFFLINE — USB drive, printed paper, password manager
# NEVER store on the Pi filesystem or in the cluster

vault operator unseal <key1>
vault operator unseal <key2>

vault login  # enter root token

# Enable transit engine
vault secrets enable transit

# Create the auto-unseal key
vault write -f transit/keys/vault-autounseal type=aes256-gcm96

# Policy for main Vault cluster
cat <<'EOF' | vault policy write autounseal -
path "transit/encrypt/vault-autounseal" {
  capabilities = ["update"]
}
path "transit/decrypt/vault-autounseal" {
  capabilities = ["update"]
}
EOF

# Token with ~100-year TTL (non-expiring in practice)
# Must tune max_lease_ttl first — default system cap is 768h
vault write sys/auth/token/tune max_lease_ttl=876000h

vault token create \
  -policy=autounseal \
  -ttl=876000h \
  -explicit-max-ttl=876000h \
  -orphan \
  -no-default-policy \
  -display-name=vault-autounseal
# token_duration should show 876000h

# SAVE THIS TOKEN — it goes into the main cluster as a k8s secret
```

### 1.7 DNS Entry

Add to your DNS server (Unbound or equivalent):

```
local-data: "vault.schnappy.io. A <UNSEAL_PI_IP>"
```

Verify from k3s node: `dig vault.schnappy.io`

### 1.8 Health Check Cron

```bash
sudo tee /usr/local/bin/vault-health-check.sh <<'EOF'
#!/bin/bash
# Use the Pi's actual IP — cert SAN does not include 127.0.0.1
HEALTH=$(curl -s --cacert /etc/vault.d/tls/vault-cert.pem \
  https://<UNSEAL_PI_IP>:8200/v1/sys/health \
  -o /tmp/vault-health.json -w "%{http_code}")
SEALED=$(jq -r '.sealed // true' /tmp/vault-health.json 2>/dev/null)
if [ "$SEALED" != "false" ]; then
  logger -t vault-unseal "ALERT: Unseal Vault sealed or unreachable, HTTP $HEALTH"
fi
EOF
sudo chmod +x /usr/local/bin/vault-health-check.sh
echo "*/5 * * * * root /usr/local/bin/vault-health-check.sh" | sudo tee /etc/cron.d/vault-health

# Test
sudo /usr/local/bin/vault-health-check.sh && echo "OK"
```

---

## Phase 2: Storage — Longhorn (Defer for single-node)

> **Skip for single-node k3s.** Use `local-path` (built-in). Install Longhorn when you add
> nodes — it installs non-destructively alongside existing workloads. When adding, migrate
> Vault's Raft PVC: snapshot → new Longhorn PVC → restore.

When ready for multi-node:

```bash
# Prerequisite on each k3s node:
sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid

# Install
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=1  # increase to 3 when nodes available
```

StorageClass for Vault:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vault-storage
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "1"   # increase to "3" when nodes available
  dataLocality: "best-effort"
  staleReplicaTimeout: "2880"
reclaimPolicy: Retain
```

---

## Phase 3: Main Vault HA Cluster

**Prerequisites:** cert-manager must be installed. On k3s clusters already using cert-manager
for ingress TLS (e.g. Forgejo), it is likely already present — verify before installing:

```bash
kubectl get pods -n cert-manager
```

If missing:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

### 3.1 Namespace, CA Cert, and Autounseal Token

Run on the k3s node **before** the Helm install:

```bash
# Copy the Pi's TLS cert to the k3s node
# (or use scp from the Pi: scp /etc/vault.d/tls/vault-cert.pem sm@<K8S_NODE>:/etc/vault-unseal/vault-cert.pem)
sudo mkdir -p /etc/vault-unseal

# Create namespace
sudo k3s kubectl create namespace vault --dry-run=client -o yaml | sudo k3s kubectl apply -f -

# Store Pi's cert as k8s secret (key must be ca.pem)
sudo k3s kubectl create secret generic vault-unseal-ca \
  --from-file=ca.pem=/etc/vault-unseal/vault-cert.pem \
  -n vault \
  --dry-run=client -o yaml | sudo k3s kubectl apply -f -

# Store autounseal token
sudo k3s kubectl create secret generic vault-unseal-token \
  -n vault \
  --from-literal=token=<AUTOUNSEAL_TOKEN> \
  --dry-run=client -o yaml | sudo k3s kubectl apply -f -
```

### 3.2 Vault TLS via cert-manager

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-ca
  namespace: vault
spec:
  isCA: true
  commonName: vault-ca
  secretName: vault-ca-secret
  issuerRef:
    name: vault-selfsigned
    kind: ClusterIssuer
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-ca-issuer
  namespace: vault
spec:
  ca:
    secretName: vault-ca-secret
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-tls
  namespace: vault
spec:
  secretName: vault-tls
  issuerRef:
    name: vault-ca-issuer
    kind: Issuer
  commonName: vault
  dnsNames:
    - vault
    - vault.vault.svc
    - vault.vault.svc.cluster.local
    - vault-internal
    - vault-0.vault-internal
    - vault-0.vault-internal.vault.svc.cluster.local
    - "*.vault-internal"
  ipAddresses:
    - "127.0.0.1"
EOF

# Verify both READY: True before proceeding
kubectl get certificate -n vault
```

### 3.3 Helm Values

Create `vault-values.yaml` (single-node configuration — adjust replicas/anti-affinity for multi-node):

```yaml
global:
  enabled: true
  tlsDisable: false

server:
  image:
    repository: hashicorp/vault
    tag: "1.21.3"  # pin — Vault has breaking changes between versions

  extraSecretEnvironmentVars:
    - envName: VAULT_TRANSIT_TOKEN
      secretName: vault-unseal-token
      secretKey: token

  extraVolumes:
    # IMPORTANT: do NOT set `path` — Vault Helm mounts at /vault/userconfig/{name}
    # Setting path changes it to {path}/{name} which breaks the config file paths below
    - type: secret
      name: vault-unseal-ca
    - type: secret
      name: vault-tls

  ha:
    enabled: true
    replicas: 1  # increase to 3 for multi-node
    raft:
      enabled: true
      config: |
        ui = true

        listener "tcp" {
          address         = "[::]:8200"
          cluster_address = "[::]:8201"
          # paths = /vault/userconfig/{secret-name}/{key}
          tls_cert_file   = "/vault/userconfig/vault-tls/tls.crt"
          tls_key_file    = "/vault/userconfig/vault-tls/tls.key"
        }

        storage "raft" {
          path = "/vault/data"
          retry_join {
            leader_api_addr     = "https://vault-0.vault-internal:8200"
            leader_ca_cert_file = "/vault/userconfig/vault-tls/ca.crt"
          }
          # Add retry_join blocks for vault-1, vault-2 on multi-node
        }

        seal "transit" {
          address     = "https://<UNSEAL_DNS_NAME>:8200"
          token       = "env://VAULT_TRANSIT_TOKEN"
          key_name    = "vault-autounseal"
          mount_path  = "transit"
          tls_ca_cert = "/vault/userconfig/vault-unseal-ca/ca.pem"
        }

        service_registration "kubernetes" {}

        # Required to expose /v1/sys/metrics for Prometheus scraping
        telemetry {
          prometheus_retention_time = "24h"
          disable_hostname = true
        }

        disable_mlock = true

  # Override readiness probe: default uses `-tls-skip-verify` which times out
  # when the listener uses IPv6 dual-stack ([::]:8200). Use VAULT_CACERT instead.
  readinessProbe:
    enabled: true
    exec:
      command:
        - /bin/sh
        - -ec
        - |
          VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt vault status

  affinity: |
    podAntiAffinity:
      # Use requiredDuringSchedulingIgnoredDuringExecution for multi-node
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/name: vault
                component: server
            topologyKey: kubernetes.io/hostname

  dataStorage:
    enabled: true
    size: 10Gi
    storageClass: local-path  # change to vault-storage when Longhorn is ready

  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

ui:
  enabled: true
  serviceType: ClusterIP

injector:
  enabled: false
```

### 3.4 Install

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault hashicorp/vault \
  --namespace vault \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  -f vault-values.yaml

# Pod will be 0/1 Running (not ready until initialized) — NOT CrashLoopBackOff
kubectl get pods -n vault
kubectl logs vault-0 -n vault | tail -20
# Expect: "security barrier not initialized", "stored unseal keys are supported, but none were found"
# These are normal pre-init messages
```

### 3.5 Initialize the Cluster

```bash
# With transit auto-unseal: use -recovery-shares/-recovery-threshold (NOT -key-shares)
# Recovery keys are used only if the Pi transit seal becomes unavailable
kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3 \
  -format=json

# SAVE THE OUTPUT OFFLINE IMMEDIATELY — contains recovery keys and root token

# vault-0 auto-unseals via transit — verify
kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault status
# Expect: Initialized: true, Sealed: false, Storage Type: raft

# For multi-node: join vault-1 and vault-2
# kubectl exec -n vault vault-1 -- \
#   env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
#   vault operator raft join https://vault-0.vault-internal:8200
```

---

## Phase 4: Vault Configuration

All commands use `kubectl exec` into vault-0 with `env VAULT_CACERT=...`:

```bash
VAULT_EXEC="kubectl exec -n vault vault-0 -- env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt"

# Login
$VAULT_EXEC vault login  # enter root token

# KV v2
$VAULT_EXEC vault secrets enable -path=secret kv-v2

# Kubernetes auth
$VAULT_EXEC vault auth enable kubernetes

# Configure Kubernetes auth
# IMPORTANT: only set kubernetes_host — do NOT set kubernetes_ca_cert or token_reviewer_jwt
# Vault uses built-in local JWT validation (disable_local_ca_jwt=false by default)
# Explicitly setting token_reviewer_jwt with a pod SA token will break auth when that
# short-lived token expires — it is NOT automatically refreshed
$VAULT_EXEC vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

# Verify config
$VAULT_EXEC vault read auth/kubernetes/config
# token_reviewer_jwt_set should be: false
```

### 4.1 Policy for monitor app

```bash
# Pipe policy via stdin using -i flag (heredoc doesn't pass through kubectl exec without it)
cat <<'EOF' | kubectl exec -i -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault policy write monitor -
path "secret/data/monitor/*" {
  capabilities = ["read"]
}
path "secret/metadata/monitor/*" {
  capabilities = ["read", "list"]
}
EOF
```

### 4.2 Kubernetes Auth Role

```bash
kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault write auth/kubernetes/role/monitor \
  bound_service_account_names=monitor \
  bound_service_account_namespaces=monitor \
  policies=monitor \
  ttl=1h
```

### 4.3 ESO Role

```bash
kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault write auth/kubernetes/role/eso-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=monitor \
  ttl=1h
# The "audience not configured" warning is harmless
```

### 4.4 Test a secret

```bash
kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault kv put secret/monitor/test value=hello
```

---

## Phase 5: External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --kubeconfig /etc/rancher/k3s/k3s.yaml

kubectl get pods -n external-secrets
kubectl get crds | grep external-secrets
```

### 5.1 ClusterSecretStore

> **API version:** ESO v0.10 uses `external-secrets.io/v1beta1` (CRD does not include `v1`).
> If CRDs are freshly installed, clear kubectl's discovery cache first:
> `sudo rm -rf /root/.kube/cache/`

```bash
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.vault.svc:8200"
      path: "secret"
      version: "v2"
      caProvider:
        type: Secret
        name: vault-ca-secret
        namespace: vault
        key: ca.crt
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF

kubectl get clustersecretstore vault-backend
# Expect: STATUS=Valid, READY=True
```

### 5.2 ExternalSecret Example

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: monitor-secrets
  namespace: monitor
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: monitor-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: monitor/production
        property: db-password
```

### 5.3 Troubleshooting ESO → Vault auth

If ClusterSecretStore shows `InvalidProviderConfig` with `403 permission denied`:

1. **Check the role exists:** `vault read auth/kubernetes/role/eso-role`
2. **Manually test auth:**
   ```bash
   TOKEN=$(kubectl create token external-secrets -n external-secrets)
   kubectl exec -n vault vault-0 -- \
     env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
     vault write auth/kubernetes/login role=eso-role jwt=$TOKEN
   ```
3. **Check auth config — token_reviewer_jwt must NOT be explicitly set:**
   ```bash
   kubectl exec -n vault vault-0 -- \
     env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
     vault read auth/kubernetes/config
   # token_reviewer_jwt_set should be: false
   ```
4. **If token_reviewer_jwt_set is true, reset:**
   ```bash
   kubectl exec -n vault vault-0 -- \
     env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
     vault write auth/kubernetes/config \
     kubernetes_host="https://kubernetes.default.svc:443"
   ```

---

## Phase 6: Sealed Secrets

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --kubeconfig /etc/rancher/k3s/k3s.yaml

# Install kubeseal CLI
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest \
  | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
curl -Lo /tmp/kubeseal.tar.gz \
  "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xzf /tmp/kubeseal.tar.gz -C /tmp kubeseal
sudo install -m 755 /tmp/kubeseal /usr/local/bin/kubeseal
kubeseal --version
```

### Backup the controller private key immediately:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml
# Store OFFLINE — required to decrypt existing SealedSecrets after cluster loss
```

### Usage:

```bash
# Create a sealed secret
kubectl create secret generic ss-example \
  --from-literal=password=hunter2 \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-example.yaml

# Commit sealed-example.yaml to Forgejo; delete the plaintext
```

---

## Phase 7: Backup Strategy

### 7.0 vault-backup-token (after Vault is initialized)

```bash
cat <<'EOF' | kubectl exec -i -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault policy write vault-backup -
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
EOF

kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault write sys/auth/token/tune max_lease_ttl=876000h

kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault token create \
  -policy=vault-backup \
  -ttl=876000h \
  -explicit-max-ttl=876000h \
  -orphan \
  -no-default-policy \
  -display-name=vault-backup \
  -format=json | jq -r '.auth.client_token' > /tmp/vault-backup-token.txt

kubectl create secret generic vault-backup-token \
  --from-file=token=/tmp/vault-backup-token.txt \
  -n vault
rm /tmp/vault-backup-token.txt
```

### 7.1 Velero Exclusion

Vault's Raft PVC is backed up via snapshots, not Velero file-system backup:

```bash
kubectl label namespace vault velero.io/exclude-from-backup=true
```

### 7.2 Raft Snapshot CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vault-raft-backup
  namespace: vault
spec:
  schedule: "0 */6 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: hashicorp/vault:1.21.3
              env:
                - name: VAULT_ADDR
                  value: "https://vault.vault.svc:8200"
                - name: VAULT_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: vault-backup-token
                      key: token
                - name: VAULT_CACERT
                  value: "/vault/tls/ca.crt"
              command:
                - /bin/sh
                - -c
                - |
                  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                  vault operator raft snapshot save /tmp/vault-snapshot-${TIMESTAMP}.snap
                  mc alias set minio https://minio-backup.velero.svc:9000 $MINIO_ACCESS $MINIO_SECRET
                  mc cp /tmp/vault-snapshot-${TIMESTAMP}.snap minio/vault-backups/
                  mc ls --json minio/vault-backups/ | \
                    jq -r '.key' | sort | head -n -30 | \
                    xargs -I{} mc rm minio/vault-backups/{}
              volumeMounts:
                - name: vault-tls
                  mountPath: /vault/tls
          volumes:
            - name: vault-tls
              secret:
                secretName: vault-ca-secret
          restartPolicy: OnFailure
```

### 7.3 Unseal Vault Backup (on Pi)

```bash
sudo tee /usr/local/bin/vault-backup.sh <<'EOF'
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d)
BACKUP_DIR="/var/backups/vault"
mkdir -p "$BACKUP_DIR"
tar czf "${BACKUP_DIR}/unseal-vault-${TIMESTAMP}.tar.gz" /var/lib/vault/data
ls -t "${BACKUP_DIR}"/unseal-vault-*.tar.gz | tail -n +15 | xargs -r rm
EOF
sudo chmod +x /usr/local/bin/vault-backup.sh
echo "0 2 * * * root /usr/local/bin/vault-backup.sh" | sudo tee /etc/cron.d/vault-backup

# Test
sudo /usr/local/bin/vault-backup.sh
ls -lh /var/backups/vault/
```

### 7.4 Offline Backup Checklist

Store the following physically offline (USB drive, safe, printed):

- Unseal Vault unseal keys (3 shares, threshold 2)
- Unseal Vault root token
- Main Vault recovery keys (5 shares, threshold 3) — from `vault operator init` JSON output
- Main Vault root token
- Sealed Secrets controller private key (`sealed-secrets-key-backup.yaml`)

---

## Phase 8: Network Policies

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-allow-only-required
  namespace: vault
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vault
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: external-secrets
      ports:
        - port: 8200
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: vault
      ports:
        - port: 8200
        - port: 8201
  egress:
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: vault
      ports:
        - port: 8200
        - port: 8201
    # Unseal Vault on Pi — IPv4 and IPv6
    - to:
        - ipBlock:
            cidr: <UNSEAL_PI_IP>/32
        - ipBlock:
            cidr: <UNSEAL_PI_IPV6>/128
      ports:
        - port: 8200
    # Kubernetes API (for Kubernetes auth token validation) — IPv4 and IPv6
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
        - ipBlock:
            cidr: ::/0
      ports:
        - port: 443
    # DNS
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
EOF
```

After applying, verify Vault is still unsealed and ESO still syncs:

```bash
kubectl exec -n vault vault-0 -- \
  env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt \
  vault status | grep Sealed
kubectl get clustersecretstore vault-backend
```

---

## Phase 9: Monitoring

### 9.1 Health Check (Pi 5)

Already set up in Phase 1.8. Logs to syslog on seal/unreachable conditions.

### 9.2 Prometheus Setup

**Prerequisites (one-time on k3s):**
```bash
# 1. Vault: create prometheus policy + long-lived token
cat <<'EOF' | kubectl exec -i -n vault vault-0 -- env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt VAULT_ADDR=https://127.0.0.1:8200 VAULT_TOKEN=$ROOT_TOKEN vault policy write prometheus -
path "sys/metrics" {
  capabilities = ["read"]
}
EOF
kubectl exec -n vault vault-0 -- env VAULT_CACERT=... VAULT_TOKEN=$ROOT_TOKEN vault token create \
  -policy=prometheus -ttl=876000h -explicit-max-ttl=876000h -format=json

# 2. Create secrets in monitor namespace
kubectl create secret generic vault-metrics-secret -n monitor --from-literal=token=<hvs...>
kubectl get secret -n vault vault-ca-secret -o jsonpath="{.data.ca\.crt}" | base64 -d | \
  kubectl create secret generic vault-ca-monitor -n monitor --from-literal=ca.crt=/dev/stdin

# 3. Update velero-to-minio NetworkPolicy to allow vault namespace on port 9000
# (if using the backup CronJob)
```

**Prometheus scrape config** (in Helm `prometheus.vault.enabled: true`):
```yaml
- job_name: vault
  metrics_path: /v1/sys/metrics
  params:
    format: ['prometheus']
  bearer_token_file: /var/run/secrets/vault-metrics/token
  scheme: https
  tls_config:
    ca_file: /vault/tls/ca.crt   # mounted from vault-ca-monitor secret
  static_configs:
    - targets:
        - vault.vault.svc:8200   # use service DNS — SANs don't include short pod DNS
```

> **Note:** `vault-0.vault-internal.vault.svc:8200` is NOT in the TLS cert SANs.
> Use `vault.vault.svc:8200` (the service endpoint) instead.

### 9.3 Critical Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| Vault sealed | `vault_core_unsealed == 0` | Critical |
| Raft leader lost | No leader for > 30s | Critical |
| Unseal Vault down | Pi 5 port 8200 unreachable | Critical |
| Raft snapshot failed | CronJob last failure > last success | Warning |
| High request latency | p99 > 500ms | Warning |

---

## Execution Order Summary

> **All steps 1–18 are automated** by `task deploy:vault-pi` (Pi steps) and
> `task deploy:vault` (k3s steps). Manual steps: Pi static IP setup, saving keys offline
> when prompted, and the offline backup checklist.

| Step | Action | Automated by | Depends On |
|------|--------|--------------|------------|
| 1 | Pi 5: OS, static IP, UFW | `setup-vault-pi.yml` (partial — static IP manual) | Pi hardware |
| 2 | Pi 5: Install Vault, TLS, systemd | `setup-vault-pi.yml` | Step 1 |
| 3 | Pi 5: Init, transit engine, autounseal token | `setup-vault-pi.yml` (prompts to save keys) | Step 2 |
| 4 | Router: DNS entry | Manual | Step 2 |
| 5 | k3s: cert-manager (may already exist) | pre-existing / setup-forgejo.yml | k3s running |
| 6 | k3s: Create vault namespace + secrets | `setup-vault.yml` | Steps 3, 5 |
| 7 | k3s: Vault TLS via cert-manager | `setup-vault.yml` | Steps 5, 6 |
| 8 | k3s: Deploy Vault via Helm | `setup-vault.yml` | Steps 4, 6, 7 |
| 9 | k3s: Initialize Vault, save keys offline | `setup-vault.yml` (prompts to save keys) | Step 8 |
| 10 | k3s: Configure Vault (KV, K8s auth, policies) | `setup-vault.yml` | Step 9 |
| 11 | k3s: Install ESO, configure ClusterSecretStore | `setup-vault.yml` | Step 10 |
| 12 | k3s: Install Sealed Secrets, backup controller key | `setup-vault.yml` (prompts to save key) | k3s running |
| 13 | k3s: Velero exclusion label on vault namespace | `setup-vault.yml` | Step 8 |
| 14 | k3s: vault-backup-token + Raft snapshot CronJob | `setup-vault.yml` | Step 9 |
| 15 | Pi 5: Unseal Vault backup cron | `setup-vault-pi.yml` | Step 3 |
| 16 | k3s: Network policies | `setup-vault.yml` | Step 11 |
| 17 | k3s: Prometheus monitoring secrets | `setup-vault.yml` | Step 10 |
| 18 | Offline backup checklist | Manual (prompted) | Steps 9, 12 |

---

## Disaster Recovery Scenarios

### Scenario: Single Vault pod dies
- **Impact:** None — pod auto-restarts and auto-unseals via Pi transit.
- **Action:** None needed.

### Scenario: Unseal Vault Pi goes down
- **Impact:** Running Vault pods stay unsealed. Pods that restart cannot unseal.
- **Action:** Fix/reboot Pi, `sudo systemctl start vault`, unseal with 2 of 3 keys.
  Vault pods will then auto-unseal on next restart.

### Scenario: Router goes down
- **Impact:** DNS for `vault.schnappy.io` breaks. Running Vault stays unsealed.
  New pods may fail unseal if they can't resolve the hostname.
- **Mitigation:** Use IP in the transit seal `address` as fallback, or ensure local DNS
  (e.g. CoreDNS override) resolves the name.

### Scenario: All Vault pods restart simultaneously
- **Impact:** All pods need auto-unseal. Automatic if Pi is up.
- **Action:** Ensure Pi unseal Vault is running first.

### Scenario: Raft data corruption
- **Action:** `vault operator raft snapshot restore <snapshot-file>`

### Scenario: Pi NVMe failure
- **Action:** Replace NVMe, reinstall OS and Vault (Phase 1), restore from backup
  (`/var/backups/vault/`). If no backup, re-initialize — requires creating a new transit
  key and updating the main cluster's seal config + re-initializing main Vault.

### Scenario: Complete cluster loss
1. Restore k3s cluster
2. Ensure Pi unseal Vault is running (independent — unaffected by k3s loss)
3. Reinstall Vault via Helm (Phase 3.3)
4. Restore Raft snapshot from MinIO
5. Restore Sealed Secrets controller key from offline backup
6. Reinstall ESO (Phase 5)
7. Verify all ExternalSecrets sync
8. Restore remaining workloads via Velero

---

## Placeholder Reference

| Placeholder | Description | Actual value |
|-------------|-------------|--------------|
| `<UNSEAL_PI_IP>` | Pi 5 static IP | 192.168.11.4 |
| `<UNSEAL_PI_IPV6>` | Pi 5 IPv6 address | fd0a:94e6:20b4:9f6b::4 |
| `<UNSEAL_DNS_NAME>` | DNS name for unseal Vault | vault.schnappy.io |
| `<K8S_NODE_IP>` | k3s node IPv4 | 192.168.11.2 |
| `<K8S_NODE_IPV6>` | k3s node IPv6 | fd0a:94e6:20b4:9f6b::2 |
| `<LAN_SUBNET>` | LAN IPv4 subnet | 192.168.11.0 |
| `<LAN_IPV6_SUBNET>` | LAN IPv6 subnet | fd0a:94e6:20b4:9f6b:: |
| `<GATEWAY_IP>` | Router/gateway IP | 192.168.11.1 |
| `<AUTOUNSEAL_TOKEN>` | Token from Phase 1.6 | (saved offline) |

---

## Lessons Learned

- **Do not set `token_reviewer_jwt` explicitly** in `vault write auth/kubernetes/config`.
  Pod SA tokens are short-lived and won't refresh. Use only `kubernetes_host` — Vault uses
  local JWT validation by default (`disable_local_ca_jwt=false`).

- **`extraVolumes` in Vault Helm chart** mount at `/vault/userconfig/{name}`, NOT
  `{path}/{name}`. Do not set the `path` field unless you update all config file paths to
  match `{path}/{name}`.

- **VAULT_ADDR must match cert SAN.** The self-signed cert has `IP:192.168.11.4` and
  `DNS:vault.schnappy.io` — using `https://127.0.0.1:8200` will fail TLS verification.
  Use the Pi's actual IP or hostname.

- **Health check on Pi uses Pi's IP**, not 127.0.0.1, for the same SAN reason above.

- **ESO CRD API version:** ESO v0.10 uses `external-secrets.io/v1beta1`; ESO v2.0+ uses
  `external-secrets.io/v1`. After installing ESO via Helm, clear kubectl's discovery cache
  if apply fails with "no matches for kind": `sudo rm -rf /root/.kube/cache/`

- **Token TTL for autounseal:** `-period=0` does not create a non-expiring token — it uses
  the system default (768h). Tune `sys/auth/token/tune max_lease_ttl=876000h` first, then
  create with `-ttl=876000h -explicit-max-ttl=876000h`.

- **`vault operator init` inside a pod** requires
  `env VAULT_CACERT=/vault/userconfig/vault-tls/ca.crt` — the pod has no default CA trust.

- **With transit auto-unseal**, use `-recovery-shares`/`-recovery-threshold` (not
  `-key-shares`/`-key-threshold`) for `vault operator init`. Recovery keys are for emergency
  access if the transit seal is unavailable.

- **Heredocs through `kubectl exec`** are consumed by the local shell. Use
  `cat <<'EOF' | kubectl exec -i ...` with the `-i` flag to pipe stdin into the pod.

- **`vault operator init -status` exit codes:** rc=0 = initialized, rc=2 = NOT initialized,
  rc=1 = error/unreachable. This applies both to standalone Vault and `kubectl exec` variants.
  Do NOT confuse rc=1 (error) with "not initialized".

- **k3s NetworkPolicy and Kubernetes API egress:** k3s v1.34+ enforces NetworkPolicies via
  iptables `KUBE-POD-FW-*` chains in the FORWARD hook, which runs AFTER kube-proxy DNAT. The
  kubernetes default service (`10.43.0.1:443`) is DNAT'd to the API server at `x.x.x.x:6443`.
  Any pod with a NetworkPolicy must allow egress on port **6443** (not just 443) to reach the
  Kubernetes API. This affects Vault's kubernetes auth backend (which calls TokenReview) and
  any other in-cluster workload that communicates with the API server.

- **Jinja2 `indent()` in YAML block scalars:** When writing a multi-line value (e.g. a PEM cert)
  into a YAML block scalar inside an Ansible `copy` task, `indent(N)` adds N spaces to every
  line *except* the first. If the expression is at indent level 2 in the output, use
  `indent(2)` so lines 2+ match the first line. Using `indent(4)` when the expression is at
  position 2 adds 2 extra spaces to every continuation line, breaking PEM parsing.

- **k3s CoreDNS and `/etc/hosts`:** k3s CoreDNS resolves custom names from the `NodeHosts`
  key in the `coredns` ConfigMap (not from the node's `/etc/hosts`). Add custom entries via:
  `kubectl patch configmap coredns -n kube-system --type=merge -p '{"data":{"NodeHosts":"..."}}'`
  Use Python subprocess if the patch string contains newlines (direct shell escaping fails).

- **Vault Helm chart auto-adds `disable_mlock = true`:** Do NOT include `disable_mlock = true`
  in `server.ha.raft.config` — the chart inserts it automatically, causing a duplicate-argument
  error on startup.

- **`vault operator init -status` returns rc=2 for connection refused:** When vault isn't
  listening yet (pod starting up), `vault operator init -status` returns rc=2 (same as "not
  initialized"). Guard the retry loop with `'connection refused' not in stdout` to avoid
  triggering init before vault is ready.

- **Ansible extra vars override inventory vars:** Ansible inventory `all.vars` are LOWER
  precedence than `-e` extra vars. Pass Vagrant-specific overrides as a dedicated extra vars
  file (`-e @vars/vault-vagrant.yml`) AFTER `-e @vars/vault.yml` to ensure they win.
  The `vault-vagrant.yml` file covers `vault_pi_ip`, `vault_arch`, `vault_k3s_ip`, etc.

- **Sealed Secrets Helm release name determines service/deployment name:** If the Helm release
  is named `sealed-secrets` (the default), the deployment and service are named
  `sealed-secrets`, NOT `sealed-secrets-controller` (kubeseal's default). Pass
  `--set fullnameOverride=sealed-secrets-controller` to Helm to match kubeseal's default.
