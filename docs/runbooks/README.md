# Runbooks moved

Runbooks now live in the platform repo and are served at
https://runbooks.pmon.dev (no login required).

Source: `platform/helm/schnappy-observability/runbooks/*.md`
Served by: `schnappy-observability` chart (nginx + ConfigMap)

Alert emails' `runbook_url` annotation points directly at the live
site. To edit a runbook, change the `.md` in the platform repo and
ArgoCD will reload the ConfigMap on next sync.
