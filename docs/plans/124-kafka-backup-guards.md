# Plan 124 - Kafka's backups guarded against the loss they exist for

**Status:** 2026-11-18 - built (platform fix/backup-guards, ops fix/batch3), reviewed (architecture, reliability: two
Criticals answered), round two built (the BASELINE per topic, the restore's store reads, the unpin, a dump after a
restore, the rehearsal re-runnable); its copy run after plan 123's push.

## Why

The daily dump (live since 2026-11-18 04:34 UTC) kept the newest KEEP complete dumps. A Kafka that lost its messages
but kept its topics (Strimzi's topic operator makes them again) dumps nothing, night after night: within KEEP nights
every dump that held the data was pruned. A restore could lose its own source the same way, and a dump taken while a
restore ran would be pruned in as the newest. The first fix - keep the newest dump counting messages - was beaten by one
message after a loss.

## What changes

- **Platform (schnappy-data):** before the upload, `files/kafka-backup-guard.sh` compares Kafka with the store's newest
  complete dump - every topic there by its TopicId, every partition at or past its latest offset. A loss refuses the
  upload and the prune (KafkaBackupMissed). The store's `BASELINE` (a restore writes it for the topics it restored;
  `task deploy:kafka-backup-baseline -- -e kafka_baseline_topics=<topic>` for a topic removed on purpose) bounds what
  is compared for the topics it names - every other topic is still compared with the dump before: a restore of one
  topic never hides another's loss (review, round one: a BASELINE for every topic did). The prune never removes a
  `PINNED` dump; it deletes a dump's marker before its files. The dump refuses while the restore's lock is mounted, at
  its start and before DONE. The restore checks the dump against itself first. KafkaBackupRestoreLockStale (lock over 2 h).
- **Ops:** `tasks/kafka-restore.yml` reads the lock's name from the CronJob (a chart without the mount: no restore),
  makes it by create, out of Velero's backups, refuses while a dump is unfinished, pins its source (`PINNED` says when,
  why and the unpin command), restores, writes the BASELINE for its topics (`kafka_topics`, or all), and removes the lock
  only when it made it and the restore succeeded or never started. `newest` is the newest dump holding messages; a dump
  of 0 is refused unless `kafka_allow_empty=true`; a store read that fails stops the fetch (never an older dump taken for
  the newest). The restore Job's scratch 2Gi. The playbook dumps the restored Kafka after it (the store holds it now,
  not a night later). `tasks/kafka-baseline.yml`: the topics named; an earlier BASELINE no complete dump followed keeps
  its topics covered (a restore, then a topic removed the same day). `task deploy:kafka-backup-unpin` gives a restore's
  source back to the prune. `tasks/kafka-store.yml` runs one rclone command in a Job from the CronJob's upload
  container. DR-PROCEDURE's Kafka step.
- **Copy rehearsal** (`test:copy:kafka-restore`): after the restore - its source pinned (its unpin said) and the
  BASELINE written for that topic alone; with the lock there a dump refuses; the marker topic removed, the next dump
  refused by the guard; the baseline task for that topic; a dump passing. Re-runnable on the same copy: a lock a failed
  run left removed first, the marker topic under a BASELINE before its first dump; a failure after the topic went
  still writes its baseline.

## Order

Plan 123's push first (the copy's checks), then this: platform's chart (the lock's mount) before ops' restore task - a
restore against the old chart refuses, it never runs unlocked.
