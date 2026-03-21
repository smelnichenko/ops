# Integrate ArchUnit Architecture Tests

## Context

All 5 Java services follow a consistent layered architecture (controller → service → repository) with self-contained security packages, but these constraints are only enforced through code review. ArchUnit adds automated architecture testing that runs with `./gradlew test`, catching violations before they reach CI.

## Scope

All Java services: monitor-backend, admin, chat, chess, api-gateway.

## Implementation

### 1. Add ArchUnit dependency to all services

Each `build.gradle` gets:
```gradle
testImplementation 'com.tngtech.archunit:archunit-junit5:1.4.1'
```

**Files:** `*/build.gradle` (5 services)

### 2. Create architecture test class per service

Each service gets `src/test/java/io/schnappy/{service}/ArchitectureTest.java` with rules tailored to its package structure.

**Rules to enforce:**

**Layering:**
- Controllers must not access repositories directly (must go through services)
- Repositories must not depend on controllers or services
- Entities must not depend on controllers or services

**Naming/annotation consistency:**
- Classes in `controller` package annotated `@RestController`
- Classes in `service` package annotated `@Service`
- Classes in `entity` package annotated `@Entity`
- Classes in `config` package annotated `@Configuration` or `@ConfigurationProperties`

**Security isolation:**
- `GatewayAuthFilter` must be in `security` package
- `@RequirePermission` annotation only used on controller/service classes
- No direct JWT parsing outside `security` package (except admin service which issues tokens)

**No circular dependencies:**
- No package cycles between controller, service, repository, entity

**Gateway-specific rule (api-gateway only):**
- Only `filter` package may reference JWT/security classes

### 3. Service-specific package mappings

| Service | Base package | Notable packages |
|---------|-------------|-----------------|
| monitor | `io.schnappy.monitor` | controller, service, repository, entity, dto, security, event, filter, scheduler, validation, config |
| admin | `io.schnappy.admin` | controller, service, repository, entity, dto, security, config |
| chat | `io.schnappy.chat` | controller, service, repository, entity, dto, security, config, kafka, websocket |
| chess | `io.schnappy.chess` | (flat + config, security) |
| gateway | `io.schnappy.gateway` | config, filter |

Chess and gateway have simpler structures — fewer rules needed.

## Files to create/modify

| File | Action |
|------|--------|
| `monitor/backend/build.gradle` | Add archunit-junit5 dependency |
| `admin/build.gradle` | Add archunit-junit5 dependency |
| `chat/build.gradle` | Add archunit-junit5 dependency |
| `chess/build.gradle` | Add archunit-junit5 dependency |
| `api-gateway/build.gradle` | Add archunit-junit5 dependency |
| `monitor/backend/src/test/.../ArchitectureTest.java` | Architecture rules |
| `admin/src/test/.../ArchitectureTest.java` | Architecture rules |
| `chat/src/test/.../ArchitectureTest.java` | Architecture rules |
| `chess/src/test/.../ArchitectureTest.java` | Architecture rules |
| `api-gateway/src/test/.../ArchitectureTest.java` | Architecture rules |
| `docs/plans/archunit-plan.md` | This plan |

## Verification

1. `./gradlew test` passes on all 5 services with architecture tests
2. Intentionally break a rule (e.g. controller calling repository) → test fails
3. Pipeline runs architecture tests as part of `./gradlew check`
