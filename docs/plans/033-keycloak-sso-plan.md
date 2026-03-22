# Keycloak SSO Integration

## Status: Phase 1 COMPLETE (2026-03-22), Phases 2-6 PENDING

## Context

Single Keycloak identity provider for all web UIs. One user, one login, everywhere. Replaces admin service JWT issuance with Keycloak OIDC.

## Phase 1: Deploy Keycloak — COMPLETE

- Keycloak 26.5.6 in schnappy namespace
- Ingress: `auth.pmon.dev` (DNS-01 TLS via letsencrypt-dns)
- Database: `keycloak` in shared schnappy-postgres (same user, separate DB)
- Vault secrets: `secret/schnappy/keycloak` (admin_password, db_password)
- Health probes on management port 9000
- readOnlyRootFilesystem: false (Quarkus build writes to /opt/keycloak/lib)
- Realm `schnappy` configured:
  - Roles: PLAY, CHAT, EMAIL, METRICS, MANAGE_USERS
  - Groups: Admins (all roles), Users (METRICS+PLAY, default)
  - Clients: `app` (public, PKCE), `grafana` (confidential), `forgejo` (confidential)
  - Registration allowed, email verification enabled
- OIDC discovery: `https://auth.pmon.dev/realms/schnappy/.well-known/openid-configuration`

### Helm templates created:
- `keycloak-deployment.yaml` — Recreate strategy, `start` command
- `keycloak-service.yaml` — ClusterIP:8080
- `keycloak-ingress.yaml` — auth.pmon.dev
- `keycloak-networkpolicy.yaml` — Traefik/app/gateway/admin ingress, postgres/DNS/HTTPS egress
- `keycloak-secret.yaml` — admin + DB passwords
- `external-secrets.yaml` — Keycloak ESO entry added
- `network-policies.yaml` — postgres ingress from keycloak added
- `postgres-deployment.yaml` — keycloak DB in init container

### Issues encountered:
- `--optimized` flag fails on first start (needs build phase)
- readOnlyRootFilesystem breaks Quarkus JarResultBuildStep
- Health endpoint on management port 9000, not app port 8080
- Shared postgres: same monitor_user credentials, separate keycloak DB
- Master realm tokens expire in 60s — refresh per API call batch
- Missing YAML `---` separator between game/postgres NPs caused Kustomize post-renderer failure

## Phase 2: Gateway RS256 — PENDING

Switch `JwtAuthFilter` from HS256 shared secret to RS256 JWKS:
- Fetch JWKS from `auth.pmon.dev/realms/schnappy/protocol/openid-connect/certs`
- Cache keys, refresh on rotation
- Map Keycloak claims → X-User-* headers
- Dual-auth: validate both HS256 (old) and RS256 (new) during migration
- User ID mapping: custom token mapper or admin DB lookup

**Files:** `api-gateway/src/main/java/io/schnappy/gateway/filter/JwtAuthFilter.java`, `AuthProperties.java`, `build.gradle`

## Phase 3: Admin Service → Keycloak Client — PENDING

- Remove JWT issuer (JwtEncoder bean)
- Remove AuthService login/register, PasswordResetService, EmailVerificationService, HashcashService
- Add Keycloak Admin Client for user/role management
- Add user event listener (KC webhook → Kafka user.events)
- Keep AdminController for group management UI

**Files:** `admin/src/main/java/io/schnappy/admin/service/`, `admin/src/main/java/io/schnappy/admin/controller/`

## Phase 4: Frontend OIDC — PENDING

- Remove Login/Register/ForgotPassword/ResetPassword pages
- Add OIDC Authorization Code Flow with PKCE
- Redirect to Keycloak for auth
- Token in HttpOnly cookie (same as now)
- Use `keycloak-js` adapter or manual OIDC

**Files:** `site/src/pages/Login.tsx`, `site/src/contexts/AuthContext.tsx`

## Phase 5: Tool Integrations — PENDING

- **Grafana:** Enable generic OAuth → Keycloak client `grafana`
- **Forgejo:** OIDC provider → Keycloak client `forgejo`
- **Woodpecker:** Keep Forgejo OAuth (chains to KC)
- **Kibana:** Traefik forward-auth or OpenID Connect
- **SonarQube CE:** HTTP Header SSO via forward-auth

## Phase 6: Migration — PENDING

1. Create admin user in Keycloak matching existing
2. Sync users from admin DB to Keycloak
3. Switch gateway to RS256
4. Switch frontend to OIDC
5. Switch tool integrations
6. Remove old auth code

## Critical: Phases 2-4 must deploy together

Gateway, admin service, and frontend changes are interdependent. Deploy as coordinated release.
