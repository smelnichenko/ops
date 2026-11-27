# test-valkey-valkey-9.x - applied 2026-11-23

The upgrade cycle's run (task upgrade:run): the test environment's unit - merged, the test environment verified; no copy, no review.

## The run

```
2026-11-23 08:00:09 PICK test test-valkey-valkey-9.x minor
2026-11-23 08:00:42 RUN scripts/upgrade-label.py test-valkey-valkey-9.x --green 3600
2026-11-23 08:01:13 RUN scripts/upgrade-label.py test-valkey-valkey-9.x --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-test-valkey-valkey-9.x-980442
2026-11-23 08:01:33 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-23 08:01:33 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-23 08:01:33 RUN scripts/upgrade-verify.sh (the test environment's merge)
2026-11-23 09:02:47 RUN scripts/upgrade-record.sh test-valkey-valkey-9.x /home/sm/src/ops/.copy/upgrade-cycle-20261123-075947-980442.log
```

## Production's inventory after it

```diff
(no change read)
```
