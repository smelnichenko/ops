# wave-patches - applied 2026-11-18

The upgrade cycle's run (task upgrade): proven on the Vagrant copy, reviewed, applied, verified.

## The run

```
2026-11-18 09:11:12 PICK prove wave-patches patch
2026-11-18 09:11:38 RUN scripts/upgrade-label.py wave-patches --green 3600
2026-11-18 09:19:08 RUN task test:copy:build
2026-11-18 10:06:33 RUN task test:copy:unit UNIT=wave-patches
2026-11-18 10:48:15 RUN claude -p <the review of renovate/wave-patches>
2026-11-18 10:56:24 RUN vagrant destroy -f
2026-11-18 10:56:57 RUN scripts/upgrade-label.py wave-patches --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-wave-patches-1052432
2026-11-18 10:57:56 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-18 10:57:59 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-18 10:58:01 RUN scripts/upgrade-verify.sh
2026-11-18 11:02:09 RUN task --yes deploy:caddy
2026-11-18 11:03:21 RUN scripts/upgrade-verify.sh
2026-11-18 12:03:28 RUN task test:copy:inventory
2026-11-18 12:03:35 RUN scripts/upgrade-record.sh wave-patches /home/sm/src/ops/.copy/upgrade-cycle-20261118-091058-1052432.log
```

## Production's inventory after it

```diff
-argo-chart istio-base base@1.31.1
-argo-chart istio-cni cni@1.31.1
-argo-chart istiod istiod@1.31.1
+argo-chart istio-base base@1.31.4
+argo-chart istio-cni cni@1.31.4
+argo-chart istiod istiod@1.31.4
-argo-chart scylla-manager scylla-manager@v1.22.0
-argo-chart scylla-operator scylla-operator@v1.22.0
+argo-chart scylla-manager scylla-manager@v1.22.1
+argo-chart scylla-operator scylla-operator@v1.22.1
-image alpine/k8s 1.35.9
+image alpine/k8s 1.35.10
+image apache/kafka 4.3.1
-image clickhouse/clickhouse-server 26.8.34.13-alpine
-image cr.fluentbit.io/fluent/fluent-bit 5.1.3
+image clickhouse/clickhouse-server 26.8.39.19-alpine
+image cr.fluentbit.io/fluent/fluent-bit 5.1.5
-image docker.io/istio/install-cni 1.31.1
-image docker.io/istio/pilot 1.31.1
+image docker.io/istio/install-cni 1.31.4
+image docker.io/istio/pilot 1.31.4
+image docker.io/istio/proxyv2 1.31.4
-image grafana/grafana 13.2.3
+image grafana/grafana 13.2.6
-image prom/alertmanager v0.34.1
+image prom/alertmanager v0.34.2
+image quay.io/prometheus-operator/prometheus-config-reloader v0.94.2
-image quay.io/prometheus/pushgateway v1.11.4
+image quay.io/prometheus/pushgateway v1.11.5
-image rclone/rclone 1.75.1
+image rclone/rclone 1.75.2
+image registry.k8s.io/etcd 3.6.16-0
-image scylladb/scylla-operator 1.22.0
+image scylladb/scylla-operator 1.22.1
-pi pi1 caddy 2.10.0
+pi pi1 caddy 2.10.2
-pi pi2 caddy 2.10.0
+pi pi2 caddy 2.10.2
```
