# wave-patches - applied 2026-11-19

The upgrade cycle's run (task upgrade): proven on the Vagrant copy, reviewed, applied, verified.

## The run

```
2026-11-19 20:57:43 PICK prove wave-patches patch
2026-11-19 20:58:09 RUN scripts/upgrade-label.py wave-patches --update
2026-11-19 20:59:05 RUN scripts/upgrade-label.py wave-patches --green 3600
2026-11-19 21:36:59 RUN task test:copy:ready
2026-11-19 22:02:17 RUN task test:copy:unit UNIT=wave-patches
2026-11-19 22:22:00 RUN claude -p <the review of renovate/wave-patches>
2026-11-19 22:24:54 RUN scripts/copy-snapshot.sh used
2026-11-19 22:24:54 RUN vagrant halt
2026-11-19 22:28:11 RUN scripts/upgrade-label.py wave-patches --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-wave-patches-1531209
2026-11-19 22:28:44 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-19 22:28:44 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-19 22:28:46 RUN scripts/upgrade-verify.sh
2026-11-19 23:30:57 RUN task test:copy:inventory
2026-11-19 23:31:04 RUN scripts/upgrade-record.sh wave-patches /home/sm/src/ops/.copy/upgrade-cycle-20261119-205728-1531209.log
```

## Production's inventory after it

```diff
-image clickhouse/clickhouse-server 26.8.40.7-alpine
+image clickhouse/clickhouse-server 26.8.41.14-alpine
-image docker.io/scylladb/scylla 2026.1.15
+image docker.io/scylladb/scylla 2026.1.16
-image git.pmon.dev/schnappy/admin 9bca905
+image git.pmon.dev/schnappy/admin 71f0d6e
-image git.pmon.dev/schnappy/chat 1eb78b3
-image git.pmon.dev/schnappy/chess 9d9a284
+image git.pmon.dev/schnappy/chat dc45177
+image git.pmon.dev/schnappy/chess 260e33d
-image git.pmon.dev/schnappy/monitor 77aa2c7
+image git.pmon.dev/schnappy/monitor 6a99194
-image scylladb/scylla 2026.1.15
+image scylladb/scylla 2026.1.16
```
