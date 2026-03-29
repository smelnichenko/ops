# Plan 044: Istio Ambient Mesh — Full Integration

## Context

Replace Envoy Gateway with Istio ambient mode for the schnappy namespace only. Istio ambient provides automatic mTLS, identity-based AuthorizationPolicy, and L7 waypoint proxies for JWT validation and routing. Keep existing NetworkPolicies for defense-in-depth.

**Not enrolled:** vault (has its own TLS), forgejo (single pod, no service mesh value), woodpecker (transient CI pods, overhead not justified).

**Current stack:** Traefik (external TLS) → Envoy Gateway (JWT + routing + rate limiting) → backend services (plaintext HTTP)

**Target stack:** Traefik (external TLS) → Istio waypoint proxy (JWT + routing + rate limiting) → backend services (mTLS via ztunnel)

**Node:** k3s v1.34.4, single node (ten), 64GB RAM (34% used), 10 cores (2% used). Plenty of headroom for Istio (~1.3GB overhead).

## Architecture (after)

```
External → Traefik:443 (kube-system, NOT in mesh)
                ↓ HTTP
           Istio Waypoint Proxy (schnappy namespace, gatewayClassName: istio-waypoint)
                ├─ JWT validation (RequestAuthentication + Keycloak JWKS)
                ├─ Rate limiting (EnvoyFilter, local)
                ├─ Path-based routing (HTTPRoute, gatewayClassName: istio-waypoint)
                ├─ AuthorizationPolicy (L7: path/method/principal)
                ↓ mTLS (automatic via ztunnel)
           Backend services (monitor, admin, chat, chess, site)
                ↓ mTLS (ztunnel)
           Data stores (postgres, redis, kafka, scylla, minio, elasticsearch)

All pod-to-pod traffic encrypted via ztunnel (L4 mTLS, zero config).
Waypoint proxy handles L7 policies (JWT, routing, auth rules).
```

## Istio Components

| Component | Type | Purpose | Resources |
|-----------|------|---------|-----------|
| istiod | Deployment | Control plane (cert issuance, config distribution) | ~1GB memory |
| ztunnel | DaemonSet | L4 mTLS tunnel (one per node) | ~12MB memory |
| istio-cni | DaemonSet | CNI plugin (traffic redirection) | ~50MB memory |
| waypoint | Deployment | L7 proxy (JWT, routing, AuthorizationPolicy) | ~60MB per waypoint |

## Phases

### Phase 1: Install Istio Ambient

**New Argo CD Application:** `istio-system` namespace

Install via Helm (4 charts, order matters):
1. `istio/base` — CRDs (PeerAuthentication, RequestAuthentication, AuthorizationPolicy, etc.)
2. `istio/istiod` — control plane with `profile=ambient`
3. `istio/cni` — CNI plugin with `global.platform=k3s`
4. `istio/ztunnel` — L4 data plane

**Ansible playbook:** `setup-istio.yml` — installs Istio Helm charts via ArgoCD or direct Helm
**Taskfile entry:** `task deploy:istio`

**Key settings:**
```yaml
# istiod
profile: ambient
meshConfig:
  defaultConfig:
    holdApplicationUntilProxyStarts: false  # ambient doesn't use sidecars
  accessLogFile: /dev/stdout

# istio-cni
global:
  platform: k3s
cni:
  ambient:
    enabled: true

# ztunnel (defaults are fine for single node)
```

**Verification:**
- `istioctl version` shows control plane
- ztunnel DaemonSet running on ten
- `istioctl proxy-status` shows ztunnel

### Phase 2: Enroll Namespaces in Ambient Mesh

Label schnappy namespace for ambient enrollment:
```bash
kubectl label namespace schnappy istio.io/dataplane-mode=ambient
```

**No pod restarts needed** — ztunnel transparently intercepts traffic.

**Verification:**
- All pod-to-pod traffic now encrypted (mTLS)
- `istioctl ztunnel-config workloads` shows enrolled workloads
- Existing services still work (ztunnel is transparent at L4)

### Phase 3: Update NetworkPolicies for HBONE

Schnappy namespace NPs must allow HBONE tunnel traffic (port 15008) and ztunnel health probes (169.254.7.127). Without this, ztunnel traffic gets blocked by default-deny.

**Files to update:**
- `clusters/production/cluster-config/schnappy-default-deny.yaml` — add port 15008 egress + ingress
- All Helm chart NPs in schnappy, schnappy-data, schnappy-observability, schnappy-auth

**Pattern:** Add to every NP:
```yaml
ingress:
  # Istio HBONE tunnel
  - ports:
      - protocol: TCP
        port: 15008
egress:
  # Istio HBONE tunnel
  - ports:
      - protocol: TCP
        port: 15008
  # ztunnel health probes
  - to:
      - ipBlock:
          cidr: 169.254.7.127/32
    ports:
      - protocol: TCP
        port: 15021
```

**Verification:**
- Services still communicate after NP update
- No connection timeouts

### Phase 4: L4 AuthorizationPolicy

Add identity-based authorization on top of NetworkPolicies (defense-in-depth).

**New Helm chart:** `schnappy-mesh` (or add to existing charts)

Example policies:
```yaml
# Only admin, monitor, chat, chess can reach PostgreSQL
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: postgres-access
  namespace: schnappy
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: postgres
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/schnappy/sa/schnappy-monitor
              - cluster.local/ns/schnappy/sa/schnappy-admin
              - cluster.local/ns/schnappy/sa/schnappy-chat
              - cluster.local/ns/schnappy/sa/schnappy-chess
              - cluster.local/ns/schnappy/sa/schnappy-keycloak
```

Similar policies for: Redis, Kafka, ScyllaDB, MinIO, Elasticsearch.

**Note:** L4 AuthorizationPolicy enforced by ztunnel — no waypoint needed.

### Phase 5: Deploy Waypoint Proxy

Create a waypoint proxy for the schnappy namespace to handle L7 policies:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: schnappy-waypoint
  namespace: schnappy
  labels:
    istio.io/waypoint-for: service
spec:
  gatewayClassName: istio-waypoint
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
```

**Verification:**
- Waypoint proxy pod running
- `istioctl waypoint list` shows it

### Phase 6: Migrate JWT Validation (Envoy Gateway → Istio)

Replace Envoy Gateway's SecurityPolicy with Istio RequestAuthentication + AuthorizationPolicy:

```yaml
# RequestAuthentication — validates JWT structure & signature
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: keycloak-jwt
  namespace: schnappy
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: schnappy-monitor
    - kind: Service
      group: ""
      name: schnappy-admin
    # ... all backend services
  jwtRules:
    - issuer: https://auth.pmon.dev/realms/schnappy
      jwksUri: http://schnappy-keycloak:8080/realms/schnappy/protocol/openid-connect/certs
      forwardOriginalToken: true
      outputClaimToHeaders:
        - header: x-user-uuid
          claim: sub
        - header: x-user-email
          claim: email

# AuthorizationPolicy — enforce JWT on protected paths
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: require-jwt
  namespace: schnappy
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: schnappy-monitor
  action: ALLOW
  rules:
    # Public paths — no JWT required
    - to:
        - operation:
            paths: ["/api/health", "/api/actuator/*", "/api/swagger-ui/*", "/api/auth/approval-mode", "/api/webhooks/*", "/api/permissions/required"]
    # All other paths — require valid JWT
    - from:
        - source:
            requestPrincipals: ["*"]
```

**Claim-to-header mapping:** Istio's `outputClaimToHeaders` replaces Envoy Gateway's `claimToHeaders`.

### Phase 7: Migrate Routing (Envoy Gateway → Istio)

Replace Envoy Gateway HTTPRoutes with Istio-compatible routing. Two options:

**Option A: HTTPRoute with istio-waypoint gatewayClassName**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: admin-routes
  namespace: schnappy
spec:
  parentRefs:
    - name: schnappy-waypoint
      kind: Gateway
  rules:
    - matches:
        - path: {type: PathPrefix, value: /api/admin}
        - path: {type: PathPrefix, value: /api/auth}
      backendRefs:
        - name: schnappy-admin
          port: 8080
```

**Option B: VirtualService (Istio-native)**
```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: schnappy-routing
spec:
  hosts: ["*"]
  http:
    - match: [{uri: {prefix: /api/admin}}]
      route: [{destination: {host: schnappy-admin, port: {number: 8080}}}]
```

**Recommendation:** Option A (HTTPRoute) — already familiar from Envoy Gateway, standard Gateway API.

**Rate limiting:** Add via EnvoyFilter on the waypoint proxy (local rate limit, same 50 req/s pattern).

**Traefik ingress update:** Change `/api` backend from Envoy proxy service to waypoint proxy service (or directly to services if waypoint handles routing internally).

### Phase 8: Remove Envoy Gateway

Once Istio handles JWT + routing + rate limiting:

**Delete from platform repo:**
- `helm/schnappy/templates/envoy-gateway.yaml`
- `helm/schnappy/templates/envoy-routes.yaml`
- `helm/schnappy/templates/envoy-security.yaml`
- `helm/schnappy/templates/envoy-ratelimit.yaml`
- `helm/schnappy/templates/envoy-client-traffic.yaml`
- `helm/schnappy/templates/envoy-network-policy.yaml`

**Delete from infra repo:**
- `clusters/production/argocd/apps/envoy-gateway.yaml`
- `clusters/production/envoy-gateway/` directory

**Update values:**
- Remove `envoyGateway` section from all values files
- Update `app-ingress.yaml` to route to services directly (Istio handles internal routing)

**Uninstall from cluster:**
- `helm uninstall envoy-gateway -n schnappy`
- Delete Envoy-specific CRDs (keep shared Gateway API CRDs)

### Phase 9: Vagrant Test

**New file:** `tests/ansible/test-istio-ambient.yml`
**Taskfile entry:** `task test:istio-ambient`

Test verifies:
1. Istio control plane running (istiod, ztunnel, CNI)
2. Namespace enrollment (ambient label)
3. mTLS between pods (ztunnel proxy-status)
4. L4 AuthorizationPolicy (postgres only reachable by allowed services)
5. Waypoint proxy running
6. JWT validation via RequestAuthentication
7. Routing via HTTPRoute
8. NetworkPolicies coexist (port 15008 allowed)

### Phase 10: CLAUDE.md Update

Update architecture diagram, security notes, networking section, deployment commands.

### Phase 0: Baseline Stress Test (before Istio)

Run Hyperfoil stress test on current stack (no mesh) and record baseline metrics:
```bash
task test:hyperfoil:stress
```
Capture from job logs: requests/s, p99 latency, error rate, node CPU%. Store report URL as baseline reference.

## Migration Strategy

**Phased rollout — each phase independently verifiable:**

1. **Phase 1-3** (install + enroll + NP update): Zero disruption. ztunnel adds mTLS transparently. NPs updated to allow HBONE. All existing services keep working.

2. **Phase 4** (L4 AuthorizationPolicy): Additive security layer. Test with `AUDIT` action first, then switch to `ALLOW`.

3. **Phase 5-7** (waypoint + JWT + routing): This is the critical migration. Run Envoy Gateway and Istio waypoint in parallel briefly, switch Traefik backend, verify, then remove Envoy Gateway.

4. **Phase 8** (remove Envoy Gateway): Cleanup after migration verified.

### Phase 11: Post-Migration Stress Test & Comparison

Run identical Hyperfoil stress test after full Istio migration:
```bash
task test:hyperfoil:stress
```

Compare against Phase 0 baseline:
- **Throughput:** req/s should be within 5-10% of baseline (mTLS overhead)
- **Latency:** p99 should be within 1ms (waypoint replaces Envoy Gateway, similar engine)
- **Error rate:** should be 0% (same as baseline)
- **CPU:** may increase 5-10% due to ztunnel encryption

Both reports accessible at `https://reports.pmon.dev/` for side-by-side comparison.

## Rollback

- Remove namespace labels to leave ambient mesh: `kubectl label namespace schnappy istio.io/dataplane-mode-`
- Re-enable Envoy Gateway: `helm upgrade` with `envoyGateway.enabled=true`
- No pod restarts needed for either direction

## Resource Budget

| Component | Memory | CPU |
|-----------|--------|-----|
| istiod | ~1GB | 200m |
| ztunnel | ~12MB | 50m |
| istio-cni | ~50MB | 25m |
| waypoint (schnappy) | ~60MB | 100m |
| **Total** | **~1.1GB** | **375m** |

Current: 22GB/64GB used (34%). After Istio: ~23GB/64GB (36%). Also removes Envoy Gateway (~200MB), net ~900MB increase.
