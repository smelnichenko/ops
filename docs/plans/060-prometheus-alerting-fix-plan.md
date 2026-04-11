# Plan 060: Fix Prometheus scraping + alerting after namespace restructure

## Status: COMPLETED (2026-04-12)

## Problem

After namespace restructure, Prometheus only scraped infra services. Production/test app pods invisible. All alert rules hardcoded to `schnappy-infra` namespace and `job="schnappy-app"` (nonexistent).

## Implementation

### Scraping
- Extended existing Istio PodMonitor to scrape `schnappy-production` and `schnappy-test` via `scrapeNamespaces` config
- Prometheus scrapes merged metrics on port 15020 (plaintext, no mTLS needed)
- 7 production targets verified: monitor, admin, chat, chess, site, game-scp, redis, database

### Alert rules split
- **Apps chart** (`schnappy/templates/prometheus-rules.yaml`): AppDown, HTTP errors, HikariPool, JVM, PodCrashLoop, PodNotReady, OOMKilled, k6 failures — gated on `alerts.enabled`
- **Data chart** (`schnappy-data/templates/prometheus-rules.yaml`): PostgreSQLDown, KafkaBrokerDown, ScyllaDBDown, PVC usage, backup alerts — gated on `alerts.enabled`
- **Observability chart**: Watchdog, ELK alerts, cert expiry, infra PVC usage only

### Ephemeral env support
- `alerts.enabled: false` default in chart values
- `alerts.enabled: true` in production infra values only
- ServiceMonitor always active (metrics regardless), PrometheusRules only when alerts enabled

### Other fixes
- Monitor component renamed from `app` to `monitor` across all 4 charts
- `alerts.pmon.dev` route added for alertmanager UI
- Custom email template with timestamp, summary, description, labels
- Kubelet graceful shutdown enabled (60s/15s) — fixes shutdown hang and stale pods
- Prometheus `scrapeNamespaces` configurable per environment
