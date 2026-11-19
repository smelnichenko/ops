# Plan 127 - a Kafka record never skipped while its store restarts

**Status:** 2026-11-19 - in progress (found by plan 126's architecture review: "make sure we will not lose prod data").
monitor: PR 24 (handler, DLT, counter; an embedded-broker test with production's application.yml). platform: the
KafkaDeadLetters alert, its promtool tests and runbook - main 2da35dc. chat:
ready, opened after monitor's CI is green. chess, masi (its owner's session): next.

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
- The DLT's partition is left to Kafka (by key): a `.DLT` needs no partition count matching its topic's. The broker
  creates it on first use (production: auto-create on, no ACLs on 9092); the nightly dump reads every topic, a DLT
  among them. A restore wants each topic made first: a KafkaTopic per DLT is a follow-up (a new object: a copy run).
- A topic read by several apps shares its DLT (`user.events`: monitor, chat, chess, masi); the header
  `kafka_dlt-original-consumer-group` names the app. A replay to the topic reaches every group - each idempotent but
  chat's admin-channel notices (a second notice).
- Spring logs no "Backoff ... exhausted" once a recoverer is set: each app logs `Kafka record <t>-<p>@<o> given up on,
  kept on <t>.DLT` after the DLT took it, and counts it (`kafka_dead_letters_total{topic}`). Spring's "Error handler
  threw an exception" is each retry's seek - a retry, never a skip: the gates (prod-native-verify.sh, the copy's
  native-check) search "Backoff ... exhausted" (an app still on Spring's default), "given up on, kept on" and chat's
  old "Failed to persist" - no longer "Error handler threw".

## Tests, each app

- A listener test with the store failing N times then answering: the record stored once, after the failures, no skip.
- A poison record: on the DLT with its headers, the partition moving on.
- The handler's backoff and its not-retryable list read from the bean (a refactor dropping the bean fails it).
- Revert each mechanism and re-run (the test-quality pass): no backoff, the DLT recoverer gone, the not-retryable
  list emptied - each a red test.

## Alert

`KafkaDeadLetters` - production runs no Kafka exporter (no topic offsets), so the apps count their dead letters:
`sum by (namespace, job, topic) ((x - x offset 30m) or x) > 0` on `kafka_dead_letters_total` (the series appears at
its first count, which `increase()` cannot see - promtool-tested, a plain `increase()` rule reverted and failing). Its
runbook: read the DLT's headers, fix the cause, replay with the console producer.

## Found on the way

- chat's `saveMessage` makes a new time UUID per call: a retry after a write that half landed (or timed out having
  landed) stores the message twice, under two ids - a duplicate where Spring's default lost it. Follow-up: the
  producer's message id as the row's id (an idempotent write).
- chat's `REGISTRATION_APPROVED` / `REGISTRATION_DECLINED` handlers return when the event has no uuid - and admin's
  events carry none (approvalId, email): the admin-channel notices never post. A separate fix.

## Rollout

App by app through each app's pull request, CI and CD (monitor, chat, chess, then masi with its owner's session),
each verified in production by a forced failure on the test environment: its Postgres primary restarted while a test
user event is produced - the event stored after the restart, nothing on the DLT.
