---
name: java-spring-developer
description: Backend discipline for this org's Java 25 / Spring Boot 4 services (monitor, chat, admin, plane-tracker/backend). Read BEFORE writing or reviewing Java, build.gradle, entities, @Cacheable, Testcontainers tests, or Spring wiring. Encodes the split-Jackson import trap (databind is `tools.jackson.*`, annotations stay `com.fasterxml`), who owns the DB schema per app (`ddl-auto` differs), the singleton-Testcontainer pattern, negative-cache and cache-degrade rules, env-gated hardware smokes, and the per-repo build gates — plus the deliberate "smells" that must not be refactored away.
---

# Java / Spring Boot backend discipline

Working rules for the schnappy Java services: **Java 25, Spring Boot 4.0.x / Spring 7, Gradle**.
Every rule below is either a trap this codebase already paid for or a place where the four repos
deliberately differ. Generic Java and Spring advice is out of scope — assume it. Check the target
repo's `build.gradle` before trusting any version stated here.

**The repos are not uniform.** `monitor`, `chat`, `admin` are Liquibase-backed services with the full
static-analysis gate. `plane-tracker/backend` is a live port of a Python app, reads a schema Python
owns, and has no analysis gate. Read the repo you are in.

## 1. Jackson is split: databind 3, annotations 2

Boot 4 ships **Jackson 3**, whose databind/core moved to a new package, but Jackson 3 *reuses the 2.x
annotations artifact*. So a single file legitimately imports from both trees:

```java
import tools.jackson.databind.ObjectMapper;            // Jackson 3 — databind, core, JsonNode, JsonMapper
import com.fasterxml.jackson.annotation.JsonProperty;  // still 2.x — annotations only
```

`com.fasterxml.jackson.databind.ObjectMapper` is the wrong artifact on this line, and
`tools.jackson.annotation.JsonProperty` **does not exist** (the annotations jar contains only the
`com/fasterxml` tree). Also: Jackson 3's `JacksonException` extends `RuntimeException`, so it is
*unchecked* — a leftover `catch (IOException e)` around a Jackson-3 call is now a **compile error**
("exception IOException is never thrown in body of corresponding try statement").

One deliberate exception: admin's `SubTokenSigner` uses the Jackson-2 `ObjectMapper` on purpose for
hand-rolled HS256 minting. Don't "unify" it.

## 2. Hibernate does not own the schema — and `ddl-auto` differs per app

| repo | `ddl-auto` | schema owner |
|---|---|---|
| plane-tracker | `validate` | the **Python** app (`src/plane_tracker/schema.sql`) |
| chat | `validate` | Liquibase |
| monitor, admin | `none` | Liquibase (monitor also generates jOOQ from the changelog) |

Consequences in plane-tracker specifically: never add or alter a mapping without matching `schema.sql`;
do **not** add `@GeneratedValue` (Postgres `gen_random_uuid()` fills the id on the Python insert); and a
table read only through a native subquery must carry **no `@Entity`**, or `validate` walks it and boot
fails. `validate` failing at startup is the feature — it catches mapping drift before a query does.

## 3. Never `@Data` on a JPA entity; match the repo's entity idiom

`@Data` generates `equals`/`hashCode` over every field, which breaks JPA identity and can force
lazy-loading. It is confined to DTOs here. The idiom differs by repo:

- **plane-tracker** (read-only entities): `@Getter` + `@NoArgsConstructor(access = AccessLevel.PROTECTED)`,
  no `@Setter`. Nullable columns use **boxed** types.
- **monitor**: no Lombok on entities at all — hand-written accessors (and `@JsonIgnore` on a getter to
  keep a column out of JSON).
- **chat / admin**: `@Getter @Setter @NoArgsConstructor`.

Services and configs are `@RequiredArgsConstructor` over `private final` fields, `@Slf4j` for logging.
There is no field `@Autowired` anywhere — keep it that way. `@RequiredArgsConstructor` cannot carry a
constructor that takes `@Value` parameters: Lombok would have to copy the annotation onto the generated
parameter, and no `lombok.config` (hence no `copyableAnnotations`) exists in any of these repos. Write
that constructor by hand.

## 4. One Testcontainer for the whole suite, started in a static block

The per-class `@Container` lifecycle stops the container between test classes while Spring's **cached
context** still points at it — the suite then fails in a way that passes when you run one class alone.
The pattern that works:

```java
@Testcontainers(disabledWithoutDocker = true)   // supplies ONLY the skip condition — no @Container field
abstract class AbstractPostgresIntegrationTest {
    static final PostgreSQLContainer<?> POSTGRES = ...;
    static {
        if (DockerClientFactory.instance().isDockerAvailable()) POSTGRES.start();  // never stopped; Ryuk reaps
    }
}
```

Seed the **real production schema** into the container (plane-tracker mounts Python's `schema.sql`) so
`validate` checks mappings against production rather than a hand-maintained copy that drifts.

monitor takes the other road — `@TestConfiguration(proxyBeanMethods = false)` + `@ServiceConnection`
beans, gated `@Profile("!ci")`. Follow whichever the repo already uses; don't mix them.

Pick the Postgres artifact that matches the repo's Testcontainers BOM major: `org.testcontainers:postgresql`
on the 1.x line, the renamed `org.testcontainers:testcontainers-postgresql` on 2.x.

## 5. Cache only positive results, and degrade when the cache is down

```java
@Cacheable(value = "routes", key = "#callsign", unless = "#result == null || #result.isEmpty()")
```

Without the `unless`, a transient upstream failure or an offline lookup returns empty, and the L1 pins
that emptiness for the whole TTL — while the L2 deliberately *didn't* persist it precisely so it would
retry. An adsbdb/Nominatim blip becomes days of "no route".

The cache manager implements `CachingConfigurer` with a `CacheErrorHandler` that logs and swallows on
get/put/evict/clear, so a Valkey outage degrades to the source instead of breaking the lookup. Values are
JSON-serialized (`GenericJackson2JsonRedisSerializer`) so they stay `valkey-cli`-inspectable and tolerate
additive record changes across a rolling deploy — not JDK serialization.

## 6. Gate hardware and live smokes on an env var, with `assumeTrue` (skip, never fail)

```java
assumeTrue(System.getenv("SMOKE_MOUNT") != null, "set SMOKE_MOUNT=1 to run the live mount read");
```

A `-D` system property does **not** reach the forked test JVM — use the environment. `assumeTrue` makes
the test *skip* in CI and when the device is absent or busy; a failing assertion there would redden the
build for a missing telescope. Run form: `SMOKE_MOUNT=1 ./gradlew -p backend test --tests '*MountReadSmokeTest'`.

Devices are exclusive: the RSP1A is single-tuner, so a live SDR smoke requires the Python tracker stopped.

## 7. Spring wiring: conditionals, lifecycle, and fail-fast

- Gate optional feature areas with `@ConditionalOnProperty` (`matchIfMissing = true` makes the feature a
  no-op when unset). Select exactly one implementation with mutually exclusive conditionals.
- Tie a subprocess or reader thread to the context with `@Bean(initMethod = "start", destroyMethod = "stop")`,
  so it cannot outlive the context.
- Validate the selector in `@PostConstruct` and fail fast. A missing conditional otherwise surfaces as a
  baffling "no such bean" deep inside a constructor.
- `@ConfigurationProperties` registration style differs: plane-tracker uses a mutable `@Getter/@Setter`
  class with `@EnableConfigurationProperties`; monitor/chat/admin use immutable records with `@DefaultValue`
  picked up by `@ConfigurationPropertiesScan`. Mixing styles leaves a record props class silently unbound.

## 8. Build gates exist in three repos out of four

monitor, chat and admin run SpotBugs (+ `check.dependsOn spotbugsMain`, `spotbugsTest.enabled = false`, a
global `EI_EXPOSE_REP/EI_EXPOSE_REP2` suppression that is a false positive on records and Spring beans),
PITest (`features = ['-FSPRING']`, excluding `**Config`/`**Dto`/`**Properties`/`**Application`), JaCoCo,
OWASP dependency-check, and Sonar with `qualitygate.wait=true`. **plane-tracker runs none of them.** Don't
write code to satisfy a gate that isn't there, and don't be blindsided by one that is.

Those same three (not plane-tracker) exclude `opentelemetry-exporter-sender-okhttp` and add `-sender-jdk`:
the OkHttp sender ignores `otlp.timeout` and silently caps every export at OkHttp's 10 s defaults.

CD pipelines run `./gradlew clean check` (a stale-workspace guard); jars are built inside the Kaniko image
build, not as a pipeline step.

## 9. There is no Java line-length limit — don't invent one

No checkstyle, spotless, `.editorconfig`, or line-length property exists in any of the four Java repos.
(The `ruff = 100` rule is Python-only.) Match the surrounding file's wrapping; don't reflow code to a
column that nothing enforces.

Java 25 idioms in use: unnamed binders `catch (X _)` and `_ ->` for unused parameters (~30 sites), records
for value types, pattern matching. A single-line text block `"""{...}"""` is a **compile error** — the
opening delimiter needs a newline after it.

## 10. The odd-looking constraints are load-bearing — read the comment before "simplifying"

This codebase deliberately keeps things that pattern-match as smells. Each one has a `WHY` comment and a
test. Removing it reintroduces the exact bug that paid for it:

- **Fail-closed with no default** (`Dialect` is unset until probed) — a default would let the driver guess
  a protocol dialect and silently mispoint a telescope.
- **Package-private actuation methods** — a structural guardrail so nothing outside the package can command
  hardware.
- **Floor-modulo, not Java's `%`, for angles; `Math.rint`, not `Math.round`** — Python's `round()` is
  banker's rounding, and `((a % m) + m) % m` perturbs the operand by 1 ULP, flipping a rounding tie.
- **Encode every command before sending any of them** — so an out-of-range value throws with nothing on
  the wire instead of half-loading a target.
- **A dedicated daemon-thread ticker instead of `@Scheduled`** — the scheduler must never die silently.
- **Boxed types on nullable columns** — a primitive would NPE on unboxing a null.

When porting from Python, parity is the default and every divergence is a decision that belongs in the
commit message. `Thread.interrupt()` does **not** unblock a native pipe `InputStream.read` — to stop a
subprocess reader you must close the stream.

The *reasoning* behind several of these lives in a sibling skill — `math` owns floor-modulo and
banker's rounding, `concurrency` owns silent-death of background loops and cancellation, and
`platform-reliability` owns the negative-caching question. They are listed here only so you recognise
the marker and don't refactor it away; go there for the derivation.

## 11. Tests: a passing test is not a test

- Every fix ships a **positive** test and a **negative** one guarding the old behavior.
- Ask of each test: *would this still pass if I deleted the method body?* If yes, it asserts nothing. A
  test that drains a command log and discards it, then checks a later call is silent, is satisfied by a
  no-op implementation.
- An assertion that sits under a `containsExactly` which already pins the full sequence is a tautology —
  it can never fail independently. Spend the negative test on something that bites.
- Distinguish a **value** from a **fault**: a mount refusing a below-horizon goto answers `'0'` and that is
  a return value; a response that is neither `'0'` nor `'1'` is an exception. Collapsing the two makes a
  broken link look like a polite refusal.
- Never dismiss a flaky test. Pass-in-isolation / fail-in-suite is a real race or a leaked singleton.
