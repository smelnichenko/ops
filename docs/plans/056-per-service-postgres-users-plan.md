# Plan 056: Separate Database Names and Users Per Service

## Status: COMPLETED (2026-04-10)

All services running with per-service postgres users and databases. 27/27 ArgoCD apps green.

## Result

| Service | Database | Username | Secret |
|---------|----------|----------|--------|
| monitor | monitor | monitor | `schnappy-{env}-postgres-monitor` |
| admin | admin | admin | `schnappy-{env}-postgres-admin` |
| chat | chat | chat | `schnappy-{env}-postgres-chat` |
| chess | chess | chess | `schnappy-{env}-postgres-chess` |

## Implementation

### Vault secrets
- `secret/schnappy/postgres-{service}` and `secret/schnappy-test/postgres-{service}` with `database`, `username`, `password` keys
- Seeded via `seed-vault-secrets.yml` loop task
- Per-service passwords in `.env` and `.env.test` (gitignored)

### ExternalSecrets
- Per-service ExternalSecrets in `schnappy-data/templates/external-secrets.yaml` using `{{range .Values.postgres.databases}}`
- Each creates a K8s secret `schnappy-{env}-postgres-{service}` with `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` keys

### Init-users Job
- `schnappy-data/templates/cnpg-init-users.yaml` — sync-wave 10, runs after CNPG healthy
- Creates per-service roles, databases, grants schema permissions
- Uses `postgres:17-alpine` image (has `wget` for Istio sidecar quitquitquit)
- Istio sidecar injected (STRICT mTLS requires it for postgres connection)
- Network policy allows job → postgres on port 5432

### App deployments
- Each deployment references its own secret (`schnappy-{env}-postgres-{service}`)
- Monitor app updated to use `DB_NAME`/`DB_USERNAME`/`DB_PASSWORD` env vars (was `POSTGRES_USERNAME`/`POSTGRES_PASSWORD`)

### Values format
```yaml
postgres:
  databases:
    - name: monitor
    - name: admin
    - name: chat
    - name: chess
```

Replaces old `extraDatabases: [monitor_admin, monitor_chat, monitor_chess]` string list.

## Also completed

- **apt-cache moved to schnappy-infra** — shared build tool, all CD pipelines updated
- **Test env quota increased** — 8 CPU / 16Gi request, 64 CPU / 48Gi limit (sidecars need headroom)

## Lessons learned

- CNPG postgresql image (`ghcr.io/cloudnative-pg/postgresql:17`) has no curl, wget, or nc — use `postgres:17-alpine` for jobs that need HTTP tools
- Istio STRICT mTLS: pods without sidecars cannot connect to pods with sidecars — init jobs need sidecar injection
- Jobs are immutable in Kubernetes — ArgoCD can't update a completed/running Job, must delete and recreate
- Sidecar `quitquitquit` via `wget -qO- --post-data= http://localhost:15020/quitquitquit` for Alpine images
