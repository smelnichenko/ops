# PublicEndpointDown

**Severity:** critical · **For:** 3m

## What fired

Blackbox HTTP probe to `$labels.instance` failed for 3+ min.

## Impact

User-visible outage on that hostname. One of:
- `pmon.dev`, `test.pmon.dev` — app frontend
- `auth.pmon.dev` — Keycloak (breaks all auth)
- `cd.pmon.dev` — ArgoCD UI
- `grafana.pmon.dev`, `logs.pmon.dev` — observability UIs

## First steps

```bash
curl -vI https://$INSTANCE/ 2>&1 | head -20
kubectl -n schnappy-infra logs deploy/schnappy-infra-gateway-istio --tail=50 | grep 404
kubectl get httproute -A | grep $HOST
```

## Common causes

| Symptom | Cause |
|---|---|
| TLS handshake fails | cert missing or invalid — `kubectl get cert -A \| grep $HOST` |
| 404 NR route_not_found | HTTPRoute not bound — check sectionName, listener hostname |
| 503 upstream | backend Deployment has 0 ready replicas |
| Connection timeout | gateway pod not Running, keepalived/DNS issue |

## Fix

Depends on cause. Typical:
- `task deploy:promote SERVICE=...` if a new tag is broken (rollback)
- `kubectl -n argocd annotate app <app> argocd.argoproj.io/refresh=hard` if drift
- Restart affected deployment

## Verification

- `curl -I https://$HOST/` → 200 (or 200-series)
- Alert clears within 3m
