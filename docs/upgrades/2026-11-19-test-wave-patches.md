# test-wave-patches - applied 2026-11-19

The upgrade cycle's run (task upgrade): the test environment's unit - merged, the test environment verified; no copy, no review.

## The run

```
2026-11-19 19:49:51 PICK test test-wave-patches patch
2026-11-19 19:50:18 RUN scripts/upgrade-label.py test-wave-patches --green 3600
2026-11-19 19:50:43 RUN scripts/upgrade-label.py test-wave-patches --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-test-wave-patches-1472203
2026-11-19 19:51:00 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-19 19:51:00 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-19 19:51:01 RUN scripts/upgrade-verify.sh (the test environment's merge)
2026-11-19 20:53:13 RUN scripts/upgrade-record.sh test-wave-patches /home/sm/src/ops/.copy/upgrade-cycle-20261119-194937-1472203.log
```

## Production's inventory after it

```diff
-image git.pmon.dev/schnappy/admin d0eab4b
+image git.pmon.dev/schnappy/admin 9bca905
-image git.pmon.dev/schnappy/chat b744e8d
-image git.pmon.dev/schnappy/chess e5a1654
+image git.pmon.dev/schnappy/chat 1eb78b3
+image git.pmon.dev/schnappy/chess 9d9a284
-image git.pmon.dev/schnappy/monitor 83018a8
+image git.pmon.dev/schnappy/monitor 77aa2c7
```
