# Replace Common Library: JWT Validation at Gateway Edge

## Context

The `io.schnappy:common:1.0.0` shared library (8 files, ~185 lines) causes friction: Nexus publishing, version drift, local dev `publishToMavenLocal` pain, tight coupling. Moving JWT validation to the gateway eliminates the shared library entirely — services trust the gateway and receive user identity as headers.

## Architecture After

```
Frontend → Gateway (validates JWT, extracts claims, adds headers)
              → admin (reads X-User-* headers, still validates JWT for auth endpoints it issues)
              → core app (reads X-User-* headers, no JWT validation)
              → chat (reads X-User-* headers, no JWT validation)
              → chess (reads X-User-* headers, no JWT validation)
```

**Network policies already enforce gateway-only access** — services can't be reached externally.

## What the Gateway Does

1. Extract JWT from `AUTH_TOKEN` cookie or `Authorization: Bearer` header
2. Validate HS256 signature + expiry (same shared secret)
3. Extract claims: `uid`, `sub` (uuid), `email`, `permissions`, `pv`
4. Add request headers to downstream:
   - `X-User-ID` (Long, internal DB id)
   - `X-User-UUID` (UUID, JWT subject)
   - `X-User-Email`
   - `X-User-Permissions` (comma-separated)
   - `X-Permission-Version` (Long)
5. Public paths (`/api/auth/**`, `/api/captcha/**`, `/api/health`, etc.) pass through without JWT
6. Invalid/expired JWT → 401

## Implementation Steps

### 1. Gateway: Add JWT validation filter

**Dependencies** (gateway `build.gradle`):
```gradle
implementation 'org.springframework.security:spring-security-oauth2-jose'
```

**New files:**
- `JwtAuthFilter.java` — reactive `GlobalFilter` that validates JWT + adds headers
- `AuthProperties.java` — `@ConfigurationProperties` for `monitor.auth.jwt-secret` (copy from common, ~10 lines)
- `GatewaySecurityConfig.java` — Spring Security WebFlux config with public path exclusions

**Config** (`application.yml`):
```yaml
monitor:
  auth:
    jwt-secret: ${JWT_SECRET}
  gateway:
    public-paths:
      - /api/auth/**
      - /api/captcha/**
      - /api/health
      - /api/build-info
      - /api/actuator/health/**
      - /api/actuator/prometheus
      - /api/permissions/required
      - /api/webhooks/**
```

### 2. Helm: Add JWT_SECRET to gateway deployment

- `gateway-deployment.yaml`: add `JWT_SECRET` env var from auth secret
- Already has network policy restricting ingress

### 3. Downstream services: Replace JWT validation with header reading

For each service (core, chat, chess):
- Remove `SecurityConfig` JWT decoder/validator
- Remove `spring-boot-starter-oauth2-resource-server` dependency
- Remove `io.schnappy:common:1.0.0` dependency
- Add simple filter/interceptor that reads `X-User-ID`, `X-User-Permissions` headers
- `@RequirePermission` checks permissions from header instead of JWT claim
- Keep network policy: only accept traffic from gateway

**Admin service is special:**
- Keeps JWT validation (it issues tokens, needs full auth flow)
- Also reads gateway headers for internal forwarded requests
- Keeps common library code inline (AuthProperties, JwtConfig, etc.)

### 4. Permission checking without common library

Each service gets a lightweight permission check:
- Read `X-User-Permissions` header (comma-separated string)
- Simple `@RequirePermission` annotation + interceptor (~30 lines)
- No `PermissionVersionChecker` needed — gateway checks `pv` claim
- No Redis dependency for permission version in downstream services

### 5. Remove common library

- Delete `backend/common/` subproject
- Remove from `backend/settings.gradle`
- Remove Nexus publish step from CD pipeline
- Remove `mavenLocal()` workarounds from microservice build.gradle files

### 6. WebSocket handling

- Gateway validates JWT during WebSocket upgrade handshake
- Passes `X-User-*` headers on the upgrade request
- Chat/chess WebSocket interceptors read headers instead of JWT cookie

## Deployment Order

1. Deploy gateway with JWT filter (additive — doesn't break existing JWT validation in services)
2. Verify headers are being added (check downstream service logs)
3. Migrate services one-by-one to header-based auth (core → chat → chess)
4. Admin keeps JWT validation (issues tokens)
5. Remove common library after all services migrated

## Risks

| Risk | Mitigation |
|------|-----------|
| Gateway bypass (direct pod access) | Network policies already block this |
| Header spoofing from malicious pod | NP default-deny + explicit allow from gateway only |
| Gateway down = all auth down | Gateway is already the single entry point (ingress routes all /api to it) |
| WebSocket auth complexity | Validate JWT on upgrade, pass headers — same pattern as HTTP |

## Verification

1. Gateway adds `X-User-*` headers on authenticated requests
2. Services respond correctly using header-based identity
3. `@RequirePermission` works via header permissions
4. Public endpoints (auth, captcha, health) pass through without JWT
5. WebSocket connections work through gateway
6. Common library fully removed, no Nexus dependency
