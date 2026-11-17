# test-curlimages-curl-8.x - applied 2026-11-17

The upgrade cycle's run (task upgrade): the test environment's unit - merged, the test environment verified; no copy, no review.

## The run

```
2026-11-17 16:58:00 PICK test test-curlimages-curl-8.x minor
2026-11-17 16:58:24 RUN scripts/upgrade-label.py test-curlimages-curl-8.x --green 3600
2026-11-17 16:58:48 RUN scripts/upgrade-label.py test-curlimages-curl-8.x --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-test-curlimages-curl-8.x-579489
2026-11-17 16:59:06 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-17 16:59:06 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-17 16:59:07 RUN scripts/upgrade-verify.sh (the test environment's merge)
2026-11-17 18:00:11 RUN scripts/upgrade-record.sh test-curlimages-curl-8.x /home/sm/src/ops/.copy/upgrade-cycle-20261117-165746-579489.log
```

## Production's inventory after it

```diff
(no change read)
```
