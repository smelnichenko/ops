# CI/CD Log Shipping to ELK

## Context

CI/CD job logs from Forgejo Actions Docker containers need to be shipped to the existing ELK stack for centralized search in Kibana. The initial approach used Filebeat with file-based Docker log collection, but this failed because Docker `--rm` deletes container log files before Filebeat can read them.

## Solution: Fluent-bit with Forward Protocol

Replace Filebeat entirely with Fluent-bit. CI containers use `--log-driver=fluentd` to stream logs in real-time to Fluent-bit via forward protocol on `localhost:24224` (hostPort). Pod logs continue via tail input from `/var/log/containers/`.

```
Pod logs (/var/log/containers/*.log)
    │ tail input
    ▼
Fluent-bit DaemonSet (hostPort 24224)
    │                       ▲
    │                       │ forward input (tag: ci)
    │                       │
    │               Docker --log-driver=fluentd
    │               --log-opt fluentd-address=localhost:24224
    │               --log-opt tag=ci
    │                       ▲
    │                       │
    ▼                CI Jobs (Docker containers on host)
Elasticsearch
  ├─ podlogs-*    (pod logs, 30d retention)
  └─ ci-logs-*     (CI logs, 90d retention)
```

## Implementation

### Helm Templates
- `fluentbit-configmap.yaml` — Fluent-bit config: tail input (pod logs), forward input (CI logs), ES outputs
- `fluentbit-daemonset.yaml` — DaemonSet with hostPort 24224, readOnlyRootFilesystem
- `fluentbit-rbac.yaml` — ServiceAccount, ClusterRole, ClusterRoleBinding for k8s metadata
- `elasticsearch-ilm-job.yaml` — Helm hook Job: creates ILM policies + index templates in ES

### Runner Config
- `container.options` in setup-forgejo.yml: `--log-driver=fluentd --log-opt fluentd-address=localhost:24224 --log-opt fluentd-async=true --log-opt tag=ci`
- `fluentd-async=true` prevents Docker from blocking if Fluent-bit is temporarily down

### Network Policies
- Fluent-bit ingress: TCP 24224 from host (Docker containers)
- Fluent-bit egress: ES 9200, K8s API 443+6443 (metadata enrichment), DNS

### Index Strategy
- Pod logs → `podlogs-*` (preserved for backwards compatibility with existing Kibana data views)
- CI logs → `ci-logs-*` (separate index, 90-day retention)
- ILM managed by elasticsearch-ilm-job (not Fluent-bit — Fluent-bit has no built-in ILM)

## Configuration

```yaml
# values.yaml
elk:
  enabled: true
  fluentbit:
    image: cr.fluentbit.io/fluent/fluent-bit:4.2.3
  ciLogs:
    enabled: true        # Enable forward input + ci-logs index
    retention:
      days: 90
```

```yaml
# ci-runner.yml (Ansible extra vars)
elk:
  ciLogs:
    enabled: true
    retention:
      days: 90
```

## Testing

- `task test:elk` — Vagrant: Fluent-bit pods running, pod logs in `podlogs-*` index
- `task test:ci-logs` — Vagrant: Docker `--log-driver=fluentd` → test marker in `ci-logs-*` index

## Status

- [x] CI Docker images built & pushed (`ci-java`, `ci-node`)
- [x] Runner dual-mode labels configured
- [x] Workflows updated (`runs-on: ci-java` / `ci-node`)
- [x] Fluent-bit Helm templates (configmap, daemonset, rbac)
- [x] ILM job for index templates and retention policies
- [x] Network policies updated
- [x] Runner config updated with `--log-driver=fluentd`
- [x] Tests updated (test-elk.yml, test-ci-logs.yml)
- [x] Documentation updated (CLAUDE.md)
- [ ] Deploy to production
- [ ] Verify CI logs appear in Kibana
