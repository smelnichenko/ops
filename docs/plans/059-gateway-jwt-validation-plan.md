# Plan 059: Gateway-level JWT validation

## Status: COMPLETED (2026-04-12)

## Implementation

### Gateway validates JWT signature
- `RequestAuthentication` with Keycloak JWKS endpoint (already existed, `jwt.enabled: true`)
- Invalid/expired tokens rejected with 401 at gateway level
- `forwardOriginalToken: true` — JWT forwarded to backend services

### Claim extraction to headers
- `sub` → `X-User-UUID` (via `outputClaimToHeaders`)
- `email` → `X-User-Email` (via `outputClaimToHeaders`)
- `realm_access.roles` — NOT extractable (nested claim, Envoy limitation)

### Service auth
- Identity (UUID, email): from gateway-set X-User-* headers
- Roles: parsed from JWT payload (signature already verified by gateway)
- No unsigned JWT trust issue — gateway validates signature before forwarding

### Public routes bypass
- `EnvoyFilter` disables JWT validation on: git, sonar, ci, auth, cd, grafana, logs, reports, hubble, alerts

### Passthrough hosts managed in infra-mesh values
- `jwt.passthroughHosts` list in `schnappy-infra-mesh/values.yaml`

## Verified
- Valid token → 200
- Invalid token → 401
- No token on public endpoint → 200
- No token on protected endpoint → 401
- k6 smoke test: all 13 checks pass
