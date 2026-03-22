# Keycloak SSO Integration

## Context

Currently each web UI has separate auth (admin service JWT for app, Forgejo OAuth for Woodpecker, local admin for Grafana/Kibana/SonarQube). Goal: single Keycloak identity provider for everything. One user, one login, everywhere.

The gateway header-injection pattern means downstream services (monitor, chat, chess) need ZERO changes — only the edge components change (gateway, admin service, frontend).

## Architecture

```
User → Keycloak (OIDC login) → JWT (RS256)
  ├─ Frontend (Authorization Code Flow → cookie)
  ├─ Grafana (Generic OAuth → Keycloak)
  ├─ Kibana (OpenID Connect → Keycloak)
  ├─ Forgejo (OIDC → Keycloak)
  ├─ Woodpecker (OAuth via Forgejo → Keycloak)
  └─ SonarQube (HTTP Header SSO via reverse proxy → Keycloak)

Gateway validates RS256 JWT → injects X-User-* headers → downstream services unchanged
```

## Phases

### Phase 1: Deploy Keycloak (schnappy namespace)

**Helm templates:**
- `keycloak-deployment.yaml` — Keycloak 26.x (quay.io/keycloak/keycloak)
- `keycloak-service.yaml` — ClusterIP port 8080
- `keycloak-ingress.yaml` — `auth.pmon.dev` (DNS-01 TLS)
- `keycloak-pvc.yaml` — NOT needed (stateless, config in DB)
- `keycloak-networkpolicy.yaml` — ingress from Traefik + app, egress to postgres + DNS

**Database:** Dedicated `keycloak` database in existing schnappy-postgres (add to postgres init)

**Secrets in Vault:** `secret/schnappy/keycloak` with `admin_password`, `db_password`

**Realm setup job** (Helm hook, like SQ setup):
1. Create `schnappy` realm
2. Create clients: `app` (frontend), `grafana`, `forgejo`, `sonarqube`
3. Create roles matching current permissions: `PLAY`, `CHAT`, `EMAIL`, `METRICS`, `MANAGE_USERS`
4. Create default groups: `Admins` (all roles), `Users` (METRICS, PLAY)
5. Configure SMTP for email verification + password reset
6. Enable registration with email verification

**Resource allocation:**
- Requests: 500m CPU, 512Mi RAM
- Limits: 2000m CPU, 1Gi RAM

### Phase 2: Gateway RS256 Validation

**Change `JwtAuthFilter`:**
- Switch from HS256 shared secret to RS256 public key validation
- Fetch Keycloak public key via OIDC discovery (`auth.pmon.dev/realms/schnappy/.well-known/openid-configuration`)
- Cache the JWKS (key set) — refresh on rotation
- Map Keycloak claims to X-User-* headers:
  - `sub` (UUID) → `X-User-UUID`
  - `realm_access.roles` → `X-User-Permissions`
  - `email` → `X-User-Email`
  - `X-User-ID` → lookup from admin service DB (UUID→numeric ID mapping)

**User ID mapping challenge:**
- Keycloak JWTs don't have numeric IDs
- Option A: Gateway calls admin service to resolve UUID→numeric ID (adds latency)
- Option B: Add custom Keycloak mapper to include numeric ID in JWT (requires admin DB sync)
- **Recommended: Option B** — admin service listens to Keycloak events, creates local user record with numeric ID, Keycloak token mapper adds `uid` claim

### Phase 3: Admin Service → Keycloak Client

**Changes:**
- Remove JWT issuer (`JwtEncoder` bean) — Keycloak issues tokens
- Remove `AuthService.login/register` — Keycloak handles these
- Remove `PasswordResetService`, `EmailVerificationService`, `HashcashService` — Keycloak handles
- Keep `AdminService` for group management UI (maps to Keycloak roles via Admin REST API)
- Keep `RegistrationApprovalService` as Keycloak event listener (webhook)
- Add Keycloak Admin Client dependency for user/role management
- Add user sync: listen to Keycloak user creation events → create local user record with numeric ID

**Kafka user events:**
- `UserEventProducer` still publishes to `user.events` topic
- Triggered by Keycloak events instead of local registration
- Core app and chat `UserEventConsumer` unchanged

### Phase 4: Frontend OIDC

**Changes to site repo:**
- Remove Login/Register/ForgotPassword/ResetPassword pages
- Add OIDC Authorization Code Flow:
  1. Unauthenticated user → redirect to `auth.pmon.dev/realms/schnappy/protocol/openid-connect/auth`
  2. User logs in at Keycloak
  3. Keycloak redirects back with `?code=...`
  4. Frontend sends code to gateway/admin → exchanges for token
  5. Token stored in HttpOnly cookie (same as now)
- Use `keycloak-js` adapter or manual OIDC (lighter)
- Logout: redirect to Keycloak logout endpoint
- Token refresh: use refresh token via `/token` endpoint

### Phase 5: Tool Integrations

**Grafana** (easy):
- Enable generic OAuth in Helm values
- Create Keycloak client `grafana` with redirect URI
- Map Keycloak roles to Grafana org roles

**Forgejo** (moderate):
- Add OIDC provider config to Forgejo `app.ini`
- Create Keycloak client `forgejo`
- Auto-create users on first login

**Woodpecker** (easy if Forgejo delegates to KC):
- Keep Woodpecker → Forgejo OAuth
- Forgejo now authenticates via Keycloak
- Chain: Woodpecker → Forgejo → Keycloak (transparent)

**Kibana** (moderate):
- Kibana 8.x supports OpenID Connect (requires subscription or basic security)
- Alternative: Traefik forward-auth with Keycloak (works with free tier)

**SonarQube CE** (workaround):
- HTTP Header SSO (`sonar.web.sso.enable=true`)
- Traefik forward-auth middleware authenticates via Keycloak
- Sets `X-Forwarded-Login` + `X-Forwarded-Email` headers
- SQ auto-creates user from headers

### Phase 6: Migration

1. Deploy Keycloak alongside existing auth (dual-auth period)
2. Create admin user in Keycloak matching existing admin
3. Sync existing users from admin DB to Keycloak (one-time migration script)
4. Switch gateway to validate Keycloak JWTs
5. Switch frontend to OIDC flow
6. Switch tool integrations
7. Remove old auth code from admin service
8. Remove old JWT secret from Vault

## Key Files to Create/Modify

### Platform repo (new templates):
- `helm/templates/keycloak-deployment.yaml`
- `helm/templates/keycloak-service.yaml`
- `helm/templates/keycloak-ingress.yaml`
- `helm/templates/keycloak-networkpolicy.yaml`
- `helm/templates/keycloak-realm-setup-job.yaml`
- `helm/templates/keycloak-secret.yaml`
- `helm/templates/external-secrets.yaml` (add keycloak)
- `helm/values.yaml` (add keycloak section)

### API Gateway repo:
- `JwtAuthFilter.java` — RS256 validation via JWKS
- `AuthProperties.java` — Keycloak OIDC discovery URL
- `build.gradle` — add `spring-security-oauth2-jose` for JWKS

### Admin service repo:
- Remove: `AuthController`, `AuthService` (login/register/reset)
- Remove: `PasswordResetService`, `EmailVerificationService`, `HashcashService`
- Add: `KeycloakEventListener` (webhook for user events)
- Add: `KeycloakAdminClient` (for role/user management)
- Modify: `AdminController` to use Keycloak Admin API

### Site repo:
- Remove: Login, Register, ForgotPassword, ResetPassword pages
- Add: OIDC auth flow (redirect to Keycloak)
- Modify: AuthContext for OIDC token handling

### Ops repo:
- `deploy/ansible/vars/production.yml` — add Keycloak values
- `deploy/ansible/playbooks/setup-vault.yml` — add Keycloak secrets
- Vagrant test: `test-keycloak.yml`

### Infra repo:
- `clusters/production/schnappy/helmrelease.yaml` — add Keycloak values

## Risks

1. **User data migration** — existing users need accounts in Keycloak with matching UUIDs
2. **Numeric ID mapping** — all existing FK references use numeric IDs
3. **SonarQube CE** — no native SSO, workaround needed
4. **Downtime during switch** — dual-auth period minimizes but doesn't eliminate
5. **Keycloak RAM** — adds ~1Gi to cluster footprint

## Verification

1. Login at `pmon.dev` redirects to `auth.pmon.dev` (Keycloak)
2. After login, all pages work (JWT validated by gateway)
3. Same login works at Grafana, Kibana, Forgejo
4. Woodpecker login via Forgejo → Keycloak chain works
5. SonarQube shows logged-in user via header SSO
6. User registration creates account in Keycloak + syncs to admin DB
7. Permission changes in Keycloak reflect immediately in app
8. `task test:keycloak` passes in Vagrant
