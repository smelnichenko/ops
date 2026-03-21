# Integrate Pitest (PIT) Mutation Testing

## Context

Unit tests exist but we have no way to measure their effectiveness — a test can pass with 100% line coverage yet miss critical logic bugs. Pitest mutates production code (flips conditionals, removes statements, changes return values) and checks if tests catch the mutations. Low mutation score = weak tests.

Pitest is slow (~5-10 min per service) so it runs as a separate non-blocking CI step, not part of `./gradlew check`.

## Scope

All 5 Java services: monitor-backend, admin, chat, chess, api-gateway. Only unit tests (Mockito-based) are targeted — integration tests (Testcontainers/SpringBootTest) are excluded.

## Implementation

### 1. Add Pitest Gradle plugin to all services

Each `build.gradle` gets:
```gradle
plugins {
    id 'info.solidsoft.pitest' version '1.15.0'
}

pitest {
    junit5PluginVersion = '1.2.1'
    targetClasses = ['io.schnappy.{service}.**']
    excludedClasses = ['**Config', '**Dto', '**Properties', '**Application']
    threads = 4
    outputFormats = ['XML', 'HTML']
    timestampedReports = false
    mutators = ['DEFAULTS']
    timeoutConstInMillis = 10000
}
```

Exclude jOOQ in monitor backend:
```gradle
excludedClasses = ['io.schnappy.jooq.**', '**Config', '**Dto', '**Properties']
```

**Files:** `*/build.gradle` (5 services)

### 2. Nightly cron pipeline in Woodpecker

Create a separate pipeline file `.woodpecker/pitest.yaml` triggered by Woodpecker cron at 3 AM. Not part of CI/CD push pipelines.

```yaml
when:
  - event: cron
    cron: pitest-nightly

steps:
  - name: pitest
    image: eclipse-temurin:25-jdk
    commands:
      - ./gradlew pitest --no-daemon
    backend_options:
      kubernetes:
        resources:
          requests: { cpu: 500m, memory: 2Gi }
          limits: { cpu: 4000m, memory: 4Gi }
        secrets:
          - name: woodpecker-ci-secrets
            key: nexus_url
            target:
              env: NEXUS_URL
```

For monitor: `cd backend &&` prefix.

**Woodpecker cron setup** (per repo via API or UI):
- Name: `pitest-nightly`
- Schedule: `0 3 * * *` (3 AM daily)
- Branch: `master` (monitor) / `main` (microservices)

### 3. Run locally, review mutation score

Run `./gradlew pitest` on each service. Review HTML report at `build/reports/pitest/`. Focus on survived mutants in critical code (security, validation, business logic).

## Files to create/modify

| File | Action |
|------|--------|
| `*/build.gradle` (5 services) | Add pitest plugin + config |
| `monitor/.woodpecker/pitest.yaml` | New nightly cron pipeline |
| `admin/.woodpecker/pitest.yaml` | New nightly cron pipeline |
| `chat/.woodpecker/pitest.yaml` | New nightly cron pipeline |
| `chess/.woodpecker/pitest.yaml` | New nightly cron pipeline |
| `api-gateway/.woodpecker/pitest.yaml` | New nightly cron pipeline |
| `docs/plans/pitest-plan.md` | This plan |

## Verification

1. `./gradlew pitest` completes on all 5 services locally
2. HTML reports generated at `build/reports/pitest/`
3. Woodpecker cron `pitest-nightly` configured for each repo (3 AM daily)
4. Review survived mutants → improve tests where mutation score is low
