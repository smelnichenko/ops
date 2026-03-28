# Plan 041: Envoy Gateway Migration

**Status:** IN PROGRESS
**Created:** 2026-03-28

## Context

Spring Cloud Gateway bottlenecks at 1,350 req/s on authenticated endpoints due to JVM-based JWT RS256 validation (~0.7ms per decode). Public endpoints achieve 6,000 req/s through the same gateway. The JVM gateway also consumes 1.3Gi memory for a proxy that adds headers.

Envoy Gateway implements the Kubernetes Gateway API backed by Envoy Proxy. JWT validation happens in native C++ (microseconds), routing via HTTPRoute CRDs, and memory usage is ~50Mi.

## Architecture Change

```
Before:
  Traefik (ingress) → Spring Cloud Gateway (JWT + routing + ensure-user) → services

After:
  Traefik (ingress) → Envoy Gateway (JWT + routing) → services
                                                     → admin (ensure-user via ext_authz or first-request)
```

## Phases

### Phase 1: Deploy Envoy Gateway Controller

- Install Envoy Gateway via Helm chart in its own namespace
- Create GatewayClass and Gateway resources
- Verify controller is running

### Phase 2: Configure JWT Authentication

- Create SecurityPolicy with Keycloak JWKS provider
- Extract claims (sub, email, realm_access.roles) into headers
- Map to X-User-UUID, X-User-Email, X-User-Permissions headers
- Public paths bypass JWT (health, actuator, webhooks, permissions)

### Phase 3: Configure Routes

- HTTPRoute for each backend service:
  - /api/auth/**, /api/admin/**, /api/permissions/** → admin
  - /api/chat/**, /ws/chat/** → chat
  - /api/chess/** → chess
  - /api/** (catch-all) → monitor (core app)
  - / → site (frontend)
- Replicate current Spring Cloud Gateway RouteConfig

### Phase 4: Handle ensure-user

The gateway currently calls POST /api/auth/ensure-user on first authenticated request per user (cached 5min). Options:

**Option A: Move to downstream services.** Each service already has GatewayAuthFilter that reads X-User-* headers. Add a check: if UUID not in local users table, call admin service to provision. This moves the concern to where it belongs — user provisioning, not routing.

**Option B: Envoy ext_authz.** External authorization service that calls ensure-user. Adds latency to every request. Overkill.

**Recommendation: Option A.** The monitor service's UserEventConsumer already handles USER_CREATED events from Kafka. The ensure-user call was a gateway shortcut. Move the "ensure user exists" check to GatewayAuthFilter in each downstream service — check local DB, if not found, call admin service once. Cache the result.

### Phase 5: Rate Limiting

- Envoy native rate limiting via BackendTrafficPolicy
- Global rate limit: 300 req/min per client IP
- Skip internal cluster IPs (k6, inter-service)
- Replace Bucket4j Java filter

### Phase 6: Switch Traffic

- Update Traefik IngressRoute to point to Envoy Gateway service
- Verify all endpoints work
- Remove Spring Cloud Gateway deployment, service, and CI pipeline

### Phase 7: Cleanup

- Archive api-gateway repo (keep for reference)
- Remove gateway Helm templates from schnappy chart
- Remove Woodpecker CI pipeline for gateway
- Update CLAUDE.md

## Files to Change

| Repo | File | Action |
|------|------|--------|
| infra | clusters/production/argocd/apps/envoy-gateway.yaml | New — Argo CD Application |
| infra | clusters/production/envoy-gateway/values.yaml | New — Helm values |
| platform | helm/schnappy/templates/envoy-*.yaml | New — Gateway, HTTPRoute, SecurityPolicy |
| platform | helm/schnappy/templates/gateway-*.yaml | Delete — Spring Cloud Gateway |
| monitor | GatewayAuthFilter.java | Add ensure-user check |
| admin | GatewayAuthFilter.java | Add ensure-user check |
| chat | GatewayAuthFilter.java | Add ensure-user check |
| chess | GatewayAuthFilter.java | Add ensure-user check |

## Risks

- Envoy JWT claim extraction to headers requires specific config — need to verify Keycloak token format
- WebSocket support (STOMP/SockJS for chat) needs separate HTTPRoute with websocket upgrade
- Ensure-user move changes auth flow — needs careful testing
- Traefik → Envoy Gateway routing change requires brief downtime or blue-green

## Expected Results

- Authenticated endpoint throughput: 1,350 → 5,000+ req/s
- Gateway memory: 1.3Gi → ~50Mi
- Gateway CPU under load: 900m → ~200m
- One less JVM service to maintain
