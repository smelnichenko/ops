# Keycloak-Only Auth Migration

## Status: PLANNED

## Goal

Remove dual-auth (HS256 admin JWT + RS256 Keycloak), go fully Keycloak. All clients (web, mobile, CLI) use standard OIDC with Bearer tokens.

## Current State

- Gateway: dual RS256 (Keycloak JWKS) + HS256 (admin service) validation
- Admin service: OIDC callback exchanges auth code → issues HS256 JWT as AUTH_TOKEN cookie
- Frontend: redirects to Keycloak, gets auth code, calls `/api/auth/oidc/callback`, stores cookie
- Permissions: admin DB (groups → permissions), embedded in HS256 JWT at login time
- Downstream services: trust gateway X-User-* headers

## Target State

- Gateway validates ONLY RS256 Keycloak JWTs via JWKS
- No HS256 JWT issuance, no AUTH_TOKEN cookie
- Frontend uses Keycloak access tokens directly (Bearer header, memory storage)
- Permissions: Keycloak realm roles in `realm_access.roles` claim
- Admin service: user/group CRUD only, no auth/JWT issuance
- Mobile clients: standard OIDC with PKCE

## Phases

### Phase 1: Keycloak Realm Roles (platform repo)

Add roles to realm import JSON:

```json
"roles": {
  "realm": [
    { "name": "PLAY" },
    { "name": "CHAT" },
    { "name": "EMAIL" },
    { "name": "METRICS" },
    { "name": "MANAGE_USERS" }
  ]
},
"defaultRoles": ["METRICS", "PLAY"]
```

- Composite roles: `Users` (METRICS, PLAY), `Admins` (all five)
- Verify `realm_access.roles` mapper is in `app` client scope
- Assign roles to existing Keycloak users
- Enforce PKCE: `"pkce.code.challenge.method": "S256"` on `app` client
- Token lifetimes: access=5min, refresh=30min, SSO session=10h

### Phase 2: Frontend OIDC (site repo)

Replace cookie-based auth with direct Keycloak token management.

- Create `oidcClient.ts` — lightweight OIDC token manager (no npm deps):
  - `login()`: redirect to Keycloak with PKCE
  - `handleCallback(code)`: client-side code→token exchange (public client)
  - `getAccessToken()`: return token, auto-refresh if near expiry
  - `logout()`: Keycloak end-session redirect
- Token storage: **memory only** (module-scoped vars). Tokens lost on refresh, silently re-obtained via Keycloak session.
- PKCE: `code_verifier` in sessionStorage (ephemeral, cleared after exchange)
- Update `AuthContext.tsx`: parse access token for user info, no backend call
- Update `api.ts`: `Authorization: Bearer` instead of `credentials: 'include'`, remove CSRF
- Silent refresh: timer before `expires_at`, call refresh endpoint
- On 401: redirect to `oidcClient.login()`

### Phase 3: Gateway RS256-Only (api-gateway repo)

- Remove HS256 decoder from `JwtAuthFilter.java`
- Remove AUTH_TOKEN cookie extraction — Bearer header only
- Remove `jwtSecret` config, make `jwksUri` required
- Keep `realm_access.roles` → `X-User-Permissions` mapping
- Remove `X-Permission-Version` header
- Add query param token extraction for WebSocket: `?access_token=<token>`
- `X-User-ID` strategy: keep UUID as `X-User-UUID`, downstream services resolve Long ID from their user table

### Phase 4: User Provisioning (admin repo)

Replace OIDC callback with gateway-triggered user sync.

- New endpoint: `POST /api/auth/ensure-user` — upsert from gateway headers, publish Kafka event
- Gateway calls this on first request from unknown UUID (Redis cache, TTL 5min)
- Remove: `OidcController`, `OidcService`, `OidcCallbackRequest`, `KeycloakProperties`
- Remove: `AuthService.generateToken()`, `JwtEncoder` bean
- Remove: cookie handling in `SecurityConfig`
- Keep: `AdminController`, `AdminService`, `UserEventProducer`
- Admin SecurityConfig: switch from JWT validation to `GatewayAuthFilter` pattern (trust gateway headers)

### Phase 5: Downstream UUID Migration (all service repos)

- Update `GatewayAuthFilter`/`GatewayUser` to use UUID as primary ID
- Each service resolves Long ID from local user table: `SELECT id FROM users WHERE uuid = ?`
- Redis cache for UUID → Long ID (TTL 5min)
- Alternative: gateway includes Long ID from ensure-user response in headers

### Phase 6: Admin Keycloak API (admin repo) — DEFERRED

- Admin service calls Keycloak Admin REST API for group/role management
- Service account client (`admin-service`) with `realm-admin` role
- Admin DB becomes read-through cache of Keycloak state
- Can defer — manage roles in Keycloak admin UI initially

### Phase 7: Cleanup

- Remove: `auth.jwtSecret` from Helm, Vault, ESO
- Remove: `AUTH_TOKEN` cookie code everywhere
- Remove: CSRF handling in frontend
- Remove: permission version tracking
- Remove: `KEYCLOAK_ENABLED` env vars from admin deployment
- Remove: `secret/schnappy/auth` from Vault

## Deployment Order

1. **Phase 1** (realm roles + PKCE) — independent, no app changes
2. **Phase 4** (ensure-user endpoint) — deploy but not yet used
3. **Phase 2 + 3 + 5** (big switch) — coordinated deploy, invalidates all sessions
4. **Phase 6** (admin KC API) — deferred
5. **Phase 7** (cleanup)

## Risks

| Risk | Mitigation |
|---|---|
| All sessions invalidated | Expected; Keycloak session may still be active (seamless re-login) |
| CORS preflight with Bearer | Gateway already has CORS config; verify `Authorization` in allowed headers |
| WebSocket auth | Pass token as `?access_token` query param; gateway reads it for WS upgrade |
| E2E chat encryption | `chat.e2eEnabled: false` in prod; if enabled later, use separate encryption passphrase |
| Keycloak downtime = no auth | Already true; KC is critical dependency |

## Key Files

| File | Changes |
|---|---|
| `api-gateway/.../JwtAuthFilter.java` | Remove HS256, cookie extraction; add WS query param |
| `site/src/contexts/AuthContext.tsx` | Direct KC token management, Bearer auth |
| `site/src/services/oidcClient.ts` | New: PKCE, token exchange, refresh |
| `admin/.../OidcController.java` | Remove; replace with ensure-user endpoint |
| `platform/helm/.../keycloak-realm-configmap.yaml` | Add realm roles, PKCE |
