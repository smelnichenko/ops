# PrometheusNotificationsFailing

**Severity:** critical · **For:** 10m

## What fired

`alertmanager_notifications_failed_total{integration=...}` is increasing. Alertmanager tried to send but got an error.

## Impact

**Meta-outage:** the alerting pipeline itself is broken. Operators won't be notified of new failures.

## First steps

```bash
kubectl -n schnappy-infra logs deploy/schnappy-alertmanager -c alertmanager --tail=100 | grep -iE "smtp|notify|error"
kubectl -n schnappy-infra exec deploy/schnappy-alertmanager -c alertmanager -- wget -qO- http://localhost:9093/metrics | grep notifications_failed
```

## Common causes

| Integration | Likely cause |
|---|---|
| email | SMTP creds expired, `smtp.resend.com` unreachable, from-domain DMARC broken |
| webhook | receiver endpoint 4xx/5xx |

## Fix

- SMTP creds: rotate in Vault (`secret/schnappy/alertmanager` → `SMTP_PASSWORD`), ESO refreshes in ≤15m, AM reloads configmap
- SMTP host unreachable: test with `dig`, fallback to alt provider in config

## Verification

- Post a synthetic critical alert:
  ```bash
  AM=$(kubectl -n schnappy-infra get pod -l app.kubernetes.io/component=alertmanager -o jsonpath='{.items[0].metadata.name}')
  AMIP=$(kubectl -n schnappy-infra get pod $AM -o jsonpath='{.status.podIP}')
  kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
    wget -qO- --post-data='[{"labels":{"alertname":"PipelineTest","severity":"critical","namespace":"schnappy-infra"}}]' \
    --header='Content-Type: application/json' http://$AMIP:9093/api/v2/alerts
  ```
- `alertmanager_notifications_total{integration="email"}` increments
- Email arrives at `sergei.melnichenko@gmail.com`
