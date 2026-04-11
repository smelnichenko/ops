# Plan 059: Gateway-level JWT validation

## Status: TODO

## Context

Services currently parse Keycloak JWT payloads themselves (unsigned, base64-decoded). While Istio mTLS ensures only gateway-routed traffic reaches services, moving JWT validation to the gateway is the proper architecture — centralized auth, services only read trusted headers.

## Current state

- `jwt.enabled: false` in both production and test mesh values
- Each service has `GatewayAuthFilter` that base64-decodes the JWT payload
- No signature verification — services trust the payload because Istio mTLS limits access
- `X-User-*` headers are not set by the gateway
- An `EnvoyFilter` exists to disable JWT validation on infra routes (git, sonar, ci, etc.)

## Target state

- Gateway validates JWT signature using Keycloak JWKS endpoint
- Gateway extracts claims into `X-User-UUID`, `X-User-Email`, `X-User-Permissions` headers
- Services read headers only — no JWT parsing
- Public endpoints bypass JWT validation (health, frontend, webhooks, actuator)
- Invalid/expired JWTs rejected at gateway with 401

## Implementation

### 1. Enable RequestAuthentication

**File:** `platform/helm/schnappy-mesh/templates/request-authentication.yaml`

Configure with Keycloak JWKS:
```yaml
spec:
  jwtRules:
    - issuer: https://auth.pmon.dev/realms/schnappy
      jwksUri: https://auth.pmon.dev/realms/schnappy/protocol/openid-connect/certs
      forwardOriginalToken: true
      outputClaimToHeaders:
        - header: x-user-uuid
          claim: sub
        - header: x-user-email
          claim: email
```

### 2. EnvoyFilter for role extraction

JWT `realm_access.roles` is a nested array — `outputClaimToHeaders` only handles flat claims. Need an EnvoyFilter with Lua or Wasm to extract roles into `X-User-Permissions` header.

### 3. Update EnvoyFilter for public routes

Disable JWT validation on routes that don't need auth:
- pmon.dev (frontend static files)
- Health/actuator endpoints
- Webhook endpoints
- Infra routes (already done: git, sonar, ci, cd, grafana, logs, reports, hubble, auth)

### 4. Update all services

Remove JWT parsing from `GatewayAuthFilter` in all 4 Java services (monitor, admin, chat, chess). Only read `X-User-*` headers.

### 5. Update k6 smoke tests

k6 sends Bearer token → gateway validates and sets headers → services authenticate via headers. No change needed in k6.

## Risks

- Keycloak JWKS endpoint must be reachable from gateway pods (cross-namespace or external)
- JWT validation adds latency to every request (~1-2ms for signature verification)
- Role extraction from nested JWT claim requires custom EnvoyFilter

## Values changes

| File | Change |
|------|--------|
| `platform/helm/schnappy-mesh/values.yaml` | `jwt.enabled: true` (default) |
| `platform/helm/schnappy-mesh/templates/request-authentication.yaml` | Add JWKS config + claim-to-header |
| `platform/helm/schnappy-mesh/templates/envoy-filter-jwt.yaml` | Role extraction + public route bypass |
| All 4 service repos `GatewayAuthFilter.java` | Remove JWT parsing, headers only |

## Verification

1. `curl -H "Authorization: Bearer <valid-token>" https://pmon.dev/api/monitor/pages` → 200
2. `curl -H "Authorization: Bearer invalid" https://pmon.dev/api/monitor/pages` → 401
3. `curl https://pmon.dev/` → 200 (no auth needed for frontend)
4. `curl https://pmon.dev/api/health` → 200 (public endpoint)
5. k6 smoke test passes in both environments
