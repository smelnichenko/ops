# wave-patches - applied 2026-11-19

The upgrade cycle's run (task upgrade): proven on the Vagrant copy, reviewed, applied, verified.

## The run

```
2026-11-19 13:56:50 PICK prove wave-patches patch
2026-11-19 13:57:15 RUN scripts/upgrade-label.py wave-patches --green 3600
2026-11-19 13:57:29 RUN task test:copy:ready
2026-11-19 14:47:10 RUN task test:copy:unit UNIT=wave-patches
2026-11-19 15:07:34 RUN claude -p <the review of renovate/wave-patches>
2026-11-19 15:09:38 RUN scripts/copy-snapshot.sh used
2026-11-19 15:09:38 RUN vagrant halt
2026-11-19 15:13:22 RUN scripts/upgrade-label.py wave-patches --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-wave-patches-784717
2026-11-19 15:13:55 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-19 15:13:55 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-19 15:13:57 RUN scripts/upgrade-verify.sh
2026-11-19 16:18:09 RUN task test:copy:inventory
2026-11-19 16:18:16 RUN scripts/upgrade-record.sh wave-patches /home/sm/src/ops/.copy/upgrade-cycle-20261119-135637-784717.log
```

## Production's inventory after it

```diff
-image amazon/aws-cli 2.37.1
+image amazon/aws-cli 2.37.13
-image bitnami/kubectl latest
-image clickhouse/clickhouse-server 26.8.39.19-alpine
+image clickhouse/clickhouse-server 26.8.40.7-alpine
+image curlimages/curl 8.10.1
-image docker.io/istio/proxyv2 1.31.1
-image git.pmon.dev/schnappy/masi 61d276d
+image git.pmon.dev/schnappy/masi 68f4b7f
-image git.pmon.dev/schnappy/site 0fa086b
+image git.pmon.dev/schnappy/site 99e8d45
+image grafana/k6 1.7.1
-image registry.k8s.io/etcd 3.6.16-0
+image registry.k8s.io/etcd 3.6.17-0
```
