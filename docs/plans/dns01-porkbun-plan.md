# DNS-01 Validation with Porkbun for Internal Hosts

## Goal

Switch TLS certificate issuance for internal-only hosts from HTTP-01 to DNS-01 via Porkbun API. This eliminates the need for public A records — internal hosts resolve only via local Unbound DNS on the router.

## Current State

| Host | DNS | ClusterIssuer | Access |
|------|-----|---------------|--------|
| `pmon.dev` | Public A record | `letsencrypt-prod` (HTTP-01) | Public |
| `git.pmon.dev` | Public A record | `letsencrypt-prod` (HTTP-01) | Public |
| `grafana.pmon.dev` | None yet | N/A | N/A |
| `logs.pmon.dev` | None yet | N/A | N/A |

## Target State

| Host | DNS | ClusterIssuer | Access |
|------|-----|---------------|--------|
| `pmon.dev` | Public A record | `letsencrypt-prod` (HTTP-01) | Public |
| `git.pmon.dev` | Unbound only | `letsencrypt-dns` (DNS-01) | LAN only |
| `grafana.pmon.dev` | Unbound only | `letsencrypt-dns` (DNS-01) | LAN only |
| `logs.pmon.dev` | Unbound only | `letsencrypt-dns` (DNS-01) | LAN only |

## Prerequisites

- Porkbun API key + secret key from https://porkbun.com/account/api
- API access enabled for the `pmon.dev` domain in Porkbun dashboard

## Implementation Steps

### Step 1: Deploy cert-manager-webhook-porkbun

Install the Porkbun DNS-01 webhook into the `cert-manager` namespace using the Talinx Helm chart.

```bash
helm repo add cert-manager-webhook-porkbun https://talinx.github.io/cert-manager-webhook-porkbun
helm install cert-manager-webhook-porkbun cert-manager-webhook-porkbun/cert-manager-webhook-porkbun \
  -n cert-manager
```

Add to `setup-k3s.yml` so it's reproducible.

Files: `deploy/ansible/playbooks/setup-k3s.yml`

### Step 2: Create Porkbun API credentials secret

Store Porkbun API key + secret as a k8s Secret in `cert-manager` namespace.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: porkbun-secret
  namespace: cert-manager
type: Opaque
stringData:
  PORKBUN_API_KEY: pk1_...
  PORKBUN_SECRET_API_KEY: sk1_...
```

For production: store in Vault KV (`secret/certmanager/porkbun`), sync via ESO ExternalSecret.
For initial setup: pass via env vars to Ansible.

Files: `deploy/ansible/playbooks/setup-k3s.yml`

### Step 3: Create `letsencrypt-dns` ClusterIssuer

New ClusterIssuer using DNS-01 with Porkbun webhook for the `pmon.dev` zone.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: sergei.melnichenko@gmail.com
    privateKeySecretRef:
      name: letsencrypt-dns
    solvers:
    - selector:
        dnsZones:
          - pmon.dev
      dns01:
        webhook:
          groupName: porkbun.talinx.dev
          solverName: porkbun
          config:
            apiKey:
              key: PORKBUN_API_KEY
              name: porkbun-secret
            secretApiKey:
              key: PORKBUN_SECRET_API_KEY
              name: porkbun-secret
```

Files: `deploy/ansible/playbooks/setup-k3s.yml`

### Step 4: Update production.yml — switch internal hosts to `letsencrypt-dns`

Change `clusterIssuer` for Grafana, Kibana ingress from `letsencrypt-prod` to `letsencrypt-dns`.

```yaml
# Grafana
grafana:
  ingress:
    tls:
      clusterIssuer: "letsencrypt-dns"

# Kibana
elk:
  kibana:
    ingress:
      tls:
        clusterIssuer: "letsencrypt-dns"
```

Keep `pmon.dev` (app ingress) on `letsencrypt-prod` (HTTP-01, public).

Files: `deploy/ansible/vars/production.yml`

### Step 5: Update Forgejo ingress to `letsencrypt-dns`

Change `cert-manager.io/cluster-issuer` annotation in `setup-forgejo.yml` from `letsencrypt-prod` to `letsencrypt-dns`.

Files: `deploy/ansible/playbooks/setup-forgejo.yml`

### Step 6: Configure Unbound on router — Done

Added local DNS entries (A + AAAA) for internal hosts on router's Unbound.

### Step 7: Remove public CNAME for `git.pmon.dev` — Done

Deleted CNAME from Porkbun. `pmon.dev` A record kept (HTTP-01 needs it).

### Step 8: Re-issue certificates — Done

Forgejo cert re-issued via DNS-01 (`kubectl delete secret forgejo-tls -n forgejo`).
Grafana and Kibana certs issued fresh via DNS-01 (new ingresses).

**Note:** cert-manager uses cluster CoreDNS → node DNS for TXT record verification. If node DNS (Unbound) caches NXDOMAIN before TXT records exist, restart Unbound to clear cache.

### Step 9: Vagrant test updates — N/A

Tests already skip real cert issuance. No changes needed.

### Step 10: Update docs — Done

## Files to Create/Modify

| File | Change | Status |
|------|--------|--------|
| `deploy/ansible/playbooks/setup-k3s.yml` | Webhook chart + secret + ClusterIssuer | Done |
| `deploy/ansible/vars/production.yml` | Switch clusterIssuer for grafana, kibana + Porkbun vars | Done |
| `deploy/ansible/playbooks/setup-forgejo.yml` | Switch clusterIssuer for Forgejo | Done |
| `CLAUDE.md` | Document DNS-01 setup | Done |

## Verification

1. `k3s kubectl get clusterissuer letsencrypt-dns` — Ready
2. `k3s kubectl get pods -n cert-manager` — webhook pod running
3. `k3s kubectl get cert -A` — all certificates Ready
4. `https://grafana.pmon.dev` — valid TLS cert (from LAN)
5. `https://logs.pmon.dev` — valid TLS cert (from LAN)
6. `https://git.pmon.dev` — valid TLS cert (from LAN)
7. `nslookup grafana.pmon.dev 8.8.8.8` — should NOT resolve (no public A record)

## Rollback

Switch `clusterIssuer` back to `letsencrypt-prod` and re-add public A records. Existing HTTP-01 issuer is untouched.
