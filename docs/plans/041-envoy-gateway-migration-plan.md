# Plan 041: Envoy Gateway Migration

**Status:** VALIDATED — needs clean implementation
**Created:** 2026-03-28

## Performance Validation (completed)

| Gateway | Total req/s | p95 | Node CPU |
|---------|-------------|-----|----------|
| Spring Cloud Gateway | 1,353 | 1.06s | 20% |
| Envoy Gateway | 4,586 | 715ms | 91% |

3.4x throughput improvement confirmed. Bottleneck shifts from JWT validation to backend CPU.

## What Failed in First Attempt

1. Switched production traffic before testing full chain — caused downtime
2. 15+ incremental NP fixes debugged in production
3. Argo CD sync wave circular dependency: Gateway health → NPs → proxy → Gateway
4. Cross-namespace then same-namespace moves created label mismatches

## Clean Implementation Plan

### Prerequisites (before touching production)

1. **Vagrant test first** — add Envoy Gateway to `test-failure-modes.yml` or a new `test-envoy.yml`
2. **Pre-create all NPs** — all NP changes must be deployed BEFORE the Gateway resource
3. **Sync wave ordering** — use Argo CD sync waves: NPs (wave 0) → EnvoyProxy config (wave 1) → Gateway + routes (wave 2)
4. **Blue-green switch** — both gateways run simultaneously, Ingress switched only after Envoy health verified

### Phase 1: NP Preparation (deploy with gateway.enabled=true, envoyGateway.enabled=false)

Deploy all NP changes while Spring Cloud Gateway handles traffic. No user impact.

- Add Envoy proxy pod selector to all backend NPs (app, admin, chat, chess, keycloak, site)
- Add Envoy controller NP
- Add Envoy proxy NP
- Verify no existing NPs break

### Phase 2: Deploy Envoy (envoyGateway.enabled=true, gateway.enabled=true)

Both gateways running. Envoy has routes but no traffic from Traefik.

- EnvoyProxy with custom service name (`schnappy-envoy-proxy`, ClusterIP)
- GatewayClass + Gateway + HTTPRoutes + SecurityPolicy
- Verify proxy pod reaches 2/2 Ready
- Verify JWKS fetch succeeds
- Test authenticated requests via `curl http://schnappy-envoy-proxy:8080/api/monitor/pages`

### Phase 3: Switch Traffic (modify Ingress, keep gateway.enabled=true as fallback)

- Update Ingress `/api` and `/ws` backends to `schnappy-envoy-proxy:8080`
- Verify `https://pmon.dev/api/health` works
- Verify authenticated endpoints work
- Run smoke test
- If any failure: revert Ingress to `schnappy-gateway` (1 value change)

### Phase 4: Remove Spring Cloud Gateway (gateway.enabled=false)

Only after 24h of stable Envoy traffic:

- Set `gateway.enabled: false`
- Remove gateway deployment, service, NPs
- Archive api-gateway repo
- Remove Woodpecker pipeline for gateway

### Phase 5: Rate Limiting

- Add BackendTrafficPolicy for rate limiting (Envoy native)
- Or keep Bucket4j in individual services

## Sync Wave Annotations

```yaml
# Wave 0: NPs (must exist before proxy starts)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# Wave 1: EnvoyProxy config (must exist before Gateway)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# Wave 2: Gateway, routes, security policy
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

## Current State to Clean Up

- Envoy Gateway controller running in schnappy namespace (keep)
- Proxy pod running but NPs may be stale (will be fixed in Phase 1)
- Spring Cloud Gateway handling all production traffic (correct)
- All 4 services updated with JWT payload permission extraction (keep — backward compatible)
- Multiple stale NP rules from failed attempts (clean up in Phase 1)

## Files to Change

| Phase | File | Change |
|-------|------|--------|
| 1 | `schnappy/templates/network-policies.yaml` | Clean up all Envoy NP rules, add sync-wave: 0 |
| 1 | `schnappy/templates/envoy-network-policy.yaml` | Clean up, add sync-wave: 0 |
| 1 | `schnappy-auth/templates/network-policies.yaml` | Clean up Envoy proxy selector |
| 2 | `schnappy/templates/envoy-gateway.yaml` | Add sync-wave: 2, verify EnvoyProxy config |
| 2 | `schnappy/templates/envoy-routes.yaml` | Add sync-wave: 2 |
| 2 | `schnappy/templates/envoy-security.yaml` | Add sync-wave: 2 |
| 3 | `schnappy/templates/app-ingress.yaml` | Switch backend to envoy-proxy |
| 3 | `infra/schnappy/values.yaml` | gateway.enabled: false |
