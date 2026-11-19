# Plan 127 - a Kafka record never skipped while its store restarts

**Status:** 2026-11-20 - the consumer side done; monitor, chess, chat and admin live in production (the last promotes queued for the upgrade chain's gap) - masi with its owner (found by plan 126's architecture review: "make sure we will not lose prod data").
The design below is the one monitor PR 24's full review settled; the first draft (15 min of retries for every failure,
then the DLT) is gone (see "What the review changed").

| part | state |
|---|---|
| monitor PR 24 | MERGED 77aa2c7, in production 2026-11-19 14:45Z: both pods' consumer config names `ErrorHandlingDeserializer`, `user-sync` holds user.events-0..2, no ERROR, `kafka_dead_letters_total{topic="user.events"}` 0 on both |
| platform: KafkaDeadLetters (on increase()), KafkaDeadLettersRefused, KafkaListenerFailing + runbooks | on main 486cbddd |
| platform + infra: the DLT KafkaTopics, ACLs, monitor's ConfigMap without spring.kafka, its JDBC socketTimeout | copy-proven (run 1119b rc=0), on main (platform 946c662, infra 262e0fc7) 2026-11-19 15:35Z: user.events.DLT and chat.messages.DLT Ready (1 partition) in production; monitor rolled onto the ConfigMap (socketTimeout=300, the image's deserializer) |
| chess PR 10 | MERGED 9d9a284, in production 15:12Z (verified) |
| chat PR 12 | MERGED 1eb78b3, in production 15:29Z (verified: three chat-persistence consumers, chat-user, both counters x2 at 0) |
| admin PR 14: user.events keyed by user | MERGED 9bca905, in production 15:40Z |
| chat PR 13: the registration notices (admin's REGISTRATION_* carry no uuid) | MERGED b034e2f |
| chat PR 14: a message written as the same row on every try | MERGED d5a3841 after two concurrency reviews: the row id one tick after the chain head (rows in chain order; a replay appended, never over its row); a message without its uuid id or its time, or a time out of bounds, to the DLT. Deferred: a lightweight transaction on chain_heads (one writer per channel today) |
| Sonar: monitor PR 25, chess PR 11, chat PR 15, admin PR 15 | MERGED - every app at 0 open issues; chess and chat lost a stale `/ws/**` permitAll (their STOMP endpoints gone) |
| the last promotes (monitor 6a99194, chess 260e33d, chat a800d06, admin 71f0d6e) | queued for the upgrade chain's gap (after run 2) |
| chat PR 16: a message's send waited for | MERGED dc45177, in production: a 503 when chat.messages did not take a message, never a 201 for a lost one; producer delivery 15 s, waited 20 s |
| admin PR 16: user events through an outbox | MERGED fe31031, in production 2026-11-19 22:54Z (changeset 011 ran; heartbeat fresh, backlog 0); operator-approved; reviewed twice (concurrency): written in the change's transaction, sent in order by one publisher on its own thread (heartbeat, lock re-checked per send, each mark its own commit, only on unsent rows), the user's row locked where it changes (never across Keycloak or mail), Keycloak's client bounded, admin's JDBC socketTimeout; alert UserEventOutboxStuck on platform main |
| masi | its owner's session, the same handler |

## Why

No app set a Kafka error handler. Spring Kafka's default (`DefaultErrorHandler`, `FixedBackOff(0, 9)`) tries a failing
record 10 times without a pause - milliseconds - then logs it, skips it and commits its offset. A record consumed while
its store restarts is lost from that store; it stays in Kafka only for the topic's retention (7 days):

| app | group | topic | writes to |
|---|---|---|---|
| chat | chat-persistence | chat.messages | ScyllaDB (the history) |
| chat | chat-user | user.events | Redis (the user cache), Postgres (the system channel) |
| monitor | user-sync | user.events | Postgres |
| chess | chess-user | user.events | Postgres |
| masi | masi-user | user.events | Postgres |

Every data-tier restart is such a window (an upgrade, a mesh restart, a node reboot): CNPG restarts its primary in
place, ScyllaDB is one node. None was skipped through 2026-11-18/19 - by luck and a quiet hour.

## The handler, each app

One `DefaultErrorHandler` (Boot wires it into every listener container). It blocks: the listener's one consumer
thread waits, and every partition it reads waits with it. There is no retry topic, because that reorders.

- **The store away** (a connection refused or lost, a transaction not begun, the database starting up or shutting
  down - Spring's `DataAccessResourceFailureException`, `TransientDataAccessException`, `CannotCreateTransactionException`,
  SQLState 08/57P/53; for chat also ScyllaDB's driver exceptions: no node, timeouts, closed/busy connection, unavailable,
  overloaded, bootstrapping):
  - The record is retried for as long as the store is away: 1 s, doubling, at most 30 s between tries, with no end.
  - It never goes to the DLT. There it would come back out of order, behind the events that followed it.
  - `KafkaListenerFailing` says the listener is held.
- **Any other failure:** 15 min of waits, then `<topic>.DLT`.
- **Records no retry can fix, straight to the DLT:**
  - a value that does not deserialize (`ErrorHandlingDeserializer`, wrapping whatever deserializer the configuration
    names - monitor's ConfigMap named the bare `JsonDeserializer`);
  - an event naming nothing (monitor `InvalidUserEventException`, chat `InvalidChatMessageException`);
  - a constraint broken (monitor `DataIntegrityViolationException`).
- **A dead letter's headers are one-line text.**
  - The nightly backup dumps topics as text lines. It refused Spring's binary partition/offset/timestamp headers and
    its multi-line stack trace, and that refusal stops every topic's backup.
  - So those headers are excluded, and the original's partition, offset and timestamp plus a one-line message are added
    as text.
  - The partition is left to Kafka (by key), so a one-partition DLT takes a record from any partition.
- **Counted:**
  - `kafka_dead_letters_total{topic}`, and `kafka_dead_letters_refused_total{topic}` for a DLT that refused a record
    (retried again, never committed).
  - Both are registered at 0 per listener topic at start, so the alert can read `increase()`.
  - Each dead letter is logged once: "given up on, kept on <topic>.DLT".
- **Dead-letter templates:** a closed bean. A send gives up in 15 s; the producer's default is 2 min, holding the
  listener all that time.

## What the review changed (monitor PR 24, 2026-11-19)

- **The deserializer wrapped in code.** `ErrorHandlingDeserializer` was set in application.yml only, and monitor's
  ConfigMap overrode it (read after the image's), so production would never have run it.
- **Store-down unbounded.** A store down past 15 min dead-lettered whichever records were first in line. They were out
  of order and unsafe to replay.
- **Text headers.** One dead letter made the backup refuse every topic for 7 days.
- **A user and its default monitors in one transaction** (monitor `UserSyncService`).
  - The user row committed alone, so a retry after the monitors failed read the user as known, and it never got its
    monitors.
  - New-ness comes from the insert (`INSERT ... ON CONFLICT DO NOTHING`), so an overlapping consumer is not new.
  - The monitors' first checks fetch pages, so they run after the commit, outside it. A fetch failing inside it marked
    it rollback-only, and the user rolled back with it.
- **monitor's enable/disable** sets the flag alone. A read-and-save of the whole row undid a concurrent last-path write.
- **The DLT topics declared** (KafkaTopics, one partition). The restore restores only topics that exist, and Argo
  ignores a KafkaTopic's spec after creation.
- **Alerts:** `KafkaListenerFailing`, and `KafkaDeadLettersRefused` (critical). `KafkaDeadLetters` moved to
  `increase()`, because the `or x` form fired on a scrape gap and missed a dead letter after a counter reset.
- **The runbook's replay.**
  - It sent only `__TypeId__`. JsonDeserializer refuses a map without `__ContentTypeId__` and `__KeyTypeId__`, so
    every `user.events` group would have failed on it.
  - Replaying an old user state overwrites newer ones in every group. The runbook now says: prefer the source sending
    the current state.

## Ordering: admin keys by user

Admin keyed `user.events` by event type. A user's USER_CREATED and USER_DISABLED were on different partitions, read by
different consumers (monitor runs two pods), each with its own retries. After an outage either could be applied first:
a disable before its user (skipped), or a stale state over a newer one. Admin now keys by the user's uuid, a
registration by its email (admin `feat/user-events-keyed-by-user`). No consumer reads the key.

## Tests, each app

- Embedded-broker listener test with production's application.yml and handler. The back-off is shortened, the outage
  counted in tries: each retry costs the broker about 0.5 s, so a timed test cannot tell the back-off from Spring's
  default. Cases:
  - the store failing 20 tries (past the ~14 any other failure gets) still stores;
  - a failure no store explains is dead-lettered after its budget;
  - invalid and poison records are dead-lettered at once;
  - every dead letter's headers are asserted UTF-8 and one line;
  - the DLT's one partition is asserted;
  - the counters start at 0;
  - the deserializer is wrapped despite a config naming the bare one;
  - `@Timeout(90)`.
- Unit tests:
  - the recoverer: kept counted once; refused rethrown and counted as refused;
  - the store-down classifier;
  - the text headers;
  - the back-offs.
- monitor: a real-database test. The user rolls back with its monitors; the checks run outside any transaction, with
  the user committed before them.
- Mutation passes (test-quality, twice). Every mechanism reverted fails a test, except the partition resolver: an
  equivalent mutant (Spring's `verifyPartition`), now pinned by a no-warning assertion.

## Found on the way

- **chat's `saveMessage` makes a new time UUID per call.** A retry after a write that half landed (or timed out having
  landed) stores the message twice, a duplicate where Spring's default lost it. The fix is an idempotent write: a
  deterministic id from the producer's message id. Its own chat PR.
- **chat's `REGISTRATION_APPROVED` / `REGISTRATION_DECLINED` handlers return when the event has no uuid**, and admin's
  carry none, so the admin-channel notices never post. Its own chat PR.

## Rollout

1. The DLT topics (copy-proven) on main.
2. Monitor (PR 24), verified in production by a forced failure on the test environment: its Postgres primary restarted
   while a test user event is produced. The event must be stored after the restart, with nothing on the DLT.
3. Then chess, chat, admin's keying, and masi with its owner.
