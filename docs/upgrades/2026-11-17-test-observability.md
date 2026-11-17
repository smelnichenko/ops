# test-observability - applied 2026-11-17

The upgrade cycle's run (task upgrade): proven on the Vagrant copy, reviewed, applied, verified.

## The run

```
2026-11-17 14:29:31 PICK test test-observability minor
2026-11-17 14:29:55 RUN scripts/upgrade-label.py test-observability --green 3600
2026-11-17 14:30:20 RUN scripts/upgrade-label.py test-observability --merge --expect /home/sm/src/ops/.upgrade-cycle/heads-test-observability-189608
2026-11-17 14:30:37 RUN git -C /home/sm/src/ops fetch -q origin main
2026-11-17 14:30:37 RUN git -C /home/sm/src/ops merge -q --ff-only origin/main
2026-11-17 14:30:37 RUN scripts/upgrade-verify.sh (the test environment's merge)
2026-11-17 15:31:47 RUN scripts/upgrade-record.sh test-observability /home/sm/src/ops/.copy/upgrade-cycle-20261117-142918-189608.log
```

## Production's inventory after it

```diff
(no change read)
```
