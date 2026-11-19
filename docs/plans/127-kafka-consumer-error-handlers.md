# Plan 127 - a Kafka record never skipped while its store restarts

**Status:** 2026-11-19 - proposed (found by plan 126's architecture review: "make sure we will not lose prod data").

## Why

No app sets a Kafka error handler. Spring Kafka's default (`DefaultErrorHandler`, `FixedBackOff(0, 9)`) tries a failing
record 10 times without a pause - milliseconds - then logs it, skips it and commits its offset. A record consumed while
its store restarts is lost from that store; it stays in Kafka only for the topic's retention (7 days):

| app | group | topic | writes to |
|---|---|---|---|
| chat | chat-persistence | chat.messages | ScyllaDB (the history) |
| chat | chat-user | user.events | Postgres |
| monitor | user-sync | user.events | Postgres |
| chess | chess-user | user.events | Postgres |
| masi | masi-user | user.events | Postgres |

Every data-tier restart is such a window (an upgrade, a mesh restart, a node reboot): CNPG restarts its primary in
place, ScyllaDB is one node. None was skipped through 2026-11-18/19 (ClickHouse logs: no "Backoff ... exhausted", no
"Failed to persist" in 7 days, both mesh restarts among them) - by luck and a quiet hour.

## The change, each app

- A `DefaultErrorHandler` bean (Spring Boot wires it into every listener container) with an `ExponentialBackOff`:
  1 s, doubling, 30 s at most, retried for 15 min - longer than any store restart seen (CNPG's primary ~1-2 min) - and
  BLOCKING: the partition waits, so a key's records keep their order (chat's messages, a user's events). Non-blocking
  retry topics are not used: they reorder.
- Not retried (no store can fix them): a record that does not deserialize, fails validation, or names nothing
  (`addNotRetryableExceptions`: `DeserializationException`, `MessageConversionException`, `MethodArgumentNotValidException`,
  the app's own "unknown" exception). They go to `<topic>.DLT` (`DeadLetterPublishingRecoverer`) - kept, never
  dropped; the Kafka backup dumps a DLT like any topic (its restore never folds a child topic into its parent).
- A record that exhausts the 15 min goes to the DLT too, with the failure in its headers - and an alert.
- The log line the gate searches ("Backoff ... exhausted") stays: prod-native-verify.sh and the copy's native-check
  keep reading it.

## Tests, each app

- A listener test with the store failing N times then answering: the record stored once, after the failures, no skip.
- A poison record: on the DLT with its headers, the partition moving on.
- The handler's backoff and its not-retryable list read from the bean (a refactor dropping the bean fails it).
- Revert each mechanism and re-run (the test-quality pass): no backoff, the DLT recoverer gone, the not-retryable
  list emptied - each a red test.

## Alert

`KafkaDeadLetters` - a DLT's end offset grew (the kafka exporter's `kafka_topic_partition_current_offset` on `.*\.DLT`);
its runbook: read the DLT's headers, fix the cause, replay with the console tools (the backup's format).

## Rollout

App by app through each app's pull request, CI and CD (monitor, chat, chess, then masi with its owner's session),
each verified in production by a forced failure on the test environment: its Postgres primary restarted while a test
user event is produced - the event stored after the restart, nothing on the DLT.
