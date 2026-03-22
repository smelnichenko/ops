# Keycloak SSO Integration

## Status: Phase 1-2 COMPLETE, Phase 5 partial (2026-03-22). Phases 3-4, 5b, 6 PENDING.

## What's done

### Phase 1: Deploy Keycloak — COMPLETE
- Keycloak 26.5.6 in schnappy namespace (`schnappy-keycloak`)
- Ingress: `auth.pmon.dev` (HTTP-01 TLS via letsencrypt-prod)
- Database: `keycloak` in shared schnappy-postgres
- Realm `schnappy`: roles (PLAY/CHAT/EMAIL/METRICS/MANAGE_USERS), groups (Admins/Users), clients (app/grafana/forgejo)
- OIDC discovery: `https://auth.pmon.dev/realms/schnappy/.well-known/openid-configuration`

### Phase 2: Gateway RS256 — COMPLETE
- Dual-auth: RS256 (Keycloak JWKS) + HS256 (admin service) fallback
- JWKS URI injected via env var when Keycloak enabled
- Keycloak `realm_access.roles` mapped to `X-User-Permissions`
- Legacy `permissions` claim also supported

### Phase 5a: Grafana SSO — COMPLETE
- Grafana OAuth pointing to Keycloak (`schnappy` realm)
- Client secret in Vault (`secret/schnappy/grafana`)
- NP: Grafana ↔ Keycloak bidirectional

## Issues resolved
- `--optimized` flag fails on first start → removed
- readOnlyRootFilesystem breaks Quarkus build → disabled
- Health probes on management port 9000, not app port 8080
- Missing `---` YAML separator between game/postgres NPs → fixed
- Keycloak → postgres NP missing → added
- Porkbun API returns 403 from server IP → switched to HTTP-01 for auth.pmon.dev
- Wildcard CNAME `*.pmon.dev` interfered with DNS-01 challenge → was not root cause, restored
- Stale TXT record from manual test → deleted
- Duplicate `autoLogin` key in helmrelease → fixed

## What's pending

### Phase 3: Admin service → Keycloak client — PENDING
- Remove JWT issuer, delegate auth to Keycloak
- Add Keycloak event listener for user sync
- Keep AdminController for group management

### Phase 4: Frontend OIDC — PENDING
- Replace login form with Keycloak redirect
- Authorization Code Flow with PKCE
- Token in HttpOnly cookie

### Phase 5b: Forgejo + Woodpecker + Kibana SSO — PENDING
- Forgejo OIDC config
- Woodpecker chains via Forgejo
- Kibana via forward-auth or OpenID Connect
- SonarQube CE via HTTP Header SSO

### Phase 6: User migration — PENDING
- Sync existing admin DB users to Keycloak
- Coordinated deploy (gateway + admin + frontend)
- Remove old auth code

## Critical: Phases 3-4 must deploy together
