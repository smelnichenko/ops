# Runbooks

One markdown page per alert. Alert emails include a `runbook_url` link.

## Structure

Each page answers: **What fired?**, **How bad?**, **First steps**, **Root-cause investigation**, **Fix**, **Verification**.

## Completed

- [VaultSealed](VaultSealed.md)
- [ClusterSecretStoreNotReady](ClusterSecretStoreNotReady.md)
- [VeleroBSLUnavailable](VeleroBSLUnavailable.md)
- [PublicEndpointDown](PublicEndpointDown.md)
- [PrometheusNotificationsFailing](PrometheusNotificationsFailing.md)
- [ArgoCDAppDegraded](ArgoCDAppDegraded.md)

## Stub (summary only)

All remaining alerts live in `prometheus-rules.yaml` and carry a
runbook_url link. Add a page when you hit an alert and want to capture
the diagnosis steps.
