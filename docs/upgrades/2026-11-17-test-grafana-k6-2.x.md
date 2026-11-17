# test-grafana-k6-2.x - applied 2026-11-17

The upgrade cycle's run (task upgrade): the test environment's unit - merged, the test environment verified; no copy, no review.

## The run

```
2026-11-17 18:35:22 PICK test test-grafana-k6-2.x major
2026-11-17 18:35:44 RUN scripts/upgrade-label.py test-grafana-k6-2.x --green 3600
2026-11-17 18:36:07 RUN scripts/upgrade-label.py test-grafana-k6-2.x --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-test-grafana-k6-2.x-934699
2026-11-17 18:36:24 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-17 18:36:24 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-17 18:36:25 RUN scripts/upgrade-verify.sh (the test environment's merge)
2026-11-17 19:38:24 RUN scripts/upgrade-record.sh test-grafana-k6-2.x /home/sm/src/ops/.copy/upgrade-cycle-20261117-183509-934699.log
```

## Production's inventory after it

```diff
(no change read)
```
