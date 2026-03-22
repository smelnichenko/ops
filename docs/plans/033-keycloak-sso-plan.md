# Keycloak SSO Integration

## Status: COMPLETE (2026-03-22)

## What was implemented

### Phase 1: Deploy Keycloak — COMPLETE
- Keycloak 26.5.6 custom image (`schnappy/keycloak-theme`) with schnappy branding
- Ingress: `auth.pmon.dev` (HTTP-01 TLS — DNS-01 blocked by Porkbun API 403)
- Database: `keycloak` in shared schnappy-postgres
- Realm `schnappy`: roles, groups (Admins/Users), clients (app/grafana/forgejo)

### Phase 2: Gateway RS256 — COMPLETE
- Dual-auth: RS256 (Keycloak JWKS) + HS256 (admin service) fallback
- Keycloak `realm_access.roles` mapped to `X-User-Permissions`

### Phase 3: Admin OIDC Callback — COMPLETE
- `POST /api/auth/oidc/callback` exchanges Keycloak auth code
- OidcService: code→token exchange, ID token decoding
- OidcUserService: upsert user from Keycloak claims
- Existing form login preserved (dual-auth)

### Phase 4: Frontend OIDC — COMPLETE
- "Sign in with Keycloak" button on login page
- AuthCallback page handles code exchange
- Keycloak logout redirect on app logout

### Phase 5: Tool Integrations — COMPLETE
- **Grafana**: Generic OAuth → Keycloak (client secret in Vault)
- **Forgejo**: OIDC source via `forgejo admin auth add-oauth`
- **Woodpecker**: Chains via Forgejo → Keycloak (no changes needed)
- **SonarQube/Kibana**: Deferred (CE limitation / forward-auth needed)

### Keycloak Theme — COMPLETE
- Custom Docker image: `schnappy/keycloak-theme` (extends official image)
- Dark gradient background, blue buttons, rounded cards, SCHNAPPY header
- Built via Woodpecker CD pipeline, versioned in Forgejo registry

## Issues resolved
- `--optimized` fails on first start → removed
- readOnlyRootFilesystem breaks Quarkus → disabled
- Health probes on port 9000, not 8080
- Porkbun API returns 403 from server IP → HTTP-01 for auth.pmon.dev
- ConfigMap theme approach → custom Docker image (cleaner)
- `.Files.Get` only works inside chart directory
- Keycloak theme cache requires pod restart after CSS changes
- `KC_SPI_THEME_DEFAULT` sets ALL theme types → only set login theme via realm API

## Files created/modified

### New repos:
- `schnappy/keycloak-theme` — Dockerfile + theme CSS + Woodpecker CD

### Platform repo:
- `keycloak-deployment.yaml`, `keycloak-service.yaml`, `keycloak-ingress.yaml`
- `keycloak-networkpolicy.yaml`, `keycloak-secret.yaml`
- `external-secrets.yaml` — Keycloak ESO entry
- `gateway-deployment.yaml` — JWKS_URI env var
- `admin-deployment.yaml` — Keycloak env vars
- `network-policies.yaml` — admin→keycloak, grafana↔keycloak, keycloak→postgres
- `values.yaml` — keycloak section

### Admin repo:
- `OidcController.java`, `OidcService.java`, `OidcUserService.java`
- `KeycloakProperties.java`, `OidcCallbackRequest.java`

### Site repo:
- `config/oidc.ts`, `pages/AuthCallback.tsx`
- `contexts/AuthContext.tsx` — loginWithCode, Keycloak logout
- `pages/Login.tsx` — Keycloak button

### API Gateway repo:
- `JwtAuthFilter.java` — dual-auth (RS256 + HS256)
- `AuthProperties.java` — jwksUri field
