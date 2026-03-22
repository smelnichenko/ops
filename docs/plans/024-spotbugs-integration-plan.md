# Integrate SpotBugs Static Analysis

## Context

SonarQube is already running for all services but only performs its own static analysis rules. SpotBugs adds bytecode-level bug detection (null pointer dereference, resource leaks, concurrency issues, security vulnerabilities) that SonarQube's source-level analysis misses. Adding SpotBugs to all 5 Java services and feeding results into SonarQube strengthens the quality gate.

## Scope

All Java services: monitor-backend, admin, chat, chess, api-gateway.

## Implementation

### 1. Add SpotBugs Gradle plugin to all services

**Plugin:** `com.github.spotbugs` v6.1.8 (latest, supports Java 25)

Each `build.gradle` gets:
```gradle
plugins {
    id 'com.github.spotbugs' version '6.1.8'
}

spotbugs {
    toolVersion = '4.9.3'
    excludeFilter = file('spotbugs-exclude.xml')
}

spotbugsMain {
    reports {
        xml.required = true
        html.required = true
    }
}
```

**Files to modify:**
- `/home/sm/src/monitor/backend/build.gradle`
- `/home/sm/src/admin/build.gradle`
- `/home/sm/src/chat/build.gradle`
- `/home/sm/src/chess/build.gradle`
- `/home/sm/src/api-gateway/build.gradle`

### 2. Create SpotBugs exclusion files

Each service gets a `spotbugs-exclude.xml` at project root.

**Monitor backend** — exclude jOOQ generated code + DTOs/entities:
```xml
<FindBugsFilter>
    <Match><Package name="~io\.schnappy\.jooq\.generated.*"/></Match>
    <Match><Package name="~io\.schnappy\.monitor\.dto.*"/></Match>
    <Match><Package name="~io\.schnappy\.monitor\.entity.*"/></Match>
</FindBugsFilter>
```

**Other services** — exclude DTOs/entities only:
```xml
<FindBugsFilter>
    <Match><Package name="~io\.schnappy\.\w+\.dto.*"/></Match>
    <Match><Package name="~io\.schnappy\.\w+\.entity.*"/></Match>
</FindBugsFilter>
```

### 3. Wire SpotBugs into SonarQube

Add to each service's `sonar.properties` block:
```gradle
property 'sonar.java.spotbugs.reportPaths', "${layout.buildDirectory.get()}/reports/spotbugs/main.xml"
```

SonarQube's `sonar-findbugs` plugin (already bundled in CE) will import SpotBugs findings automatically.

### 4. CI/CD pipeline — no changes needed

SpotBugs runs as a Gradle task. The `./gradlew test` and `./gradlew sonar` steps already invoke compilation. Add `spotbugsMain` as a dependency of `check`:
```gradle
check.dependsOn spotbugsMain
```

This makes SpotBugs run automatically when `./gradlew test` or `./gradlew check` is called. The `sonar` step then picks up the XML report.

### 5. Run locally, fix initial findings

Run `./gradlew spotbugsMain` on each service, review and fix or suppress initial findings before pushing. This prevents the quality gate from breaking on first run.

## Verification

1. `./gradlew spotbugsMain` passes on all 5 services locally
2. SpotBugs XML reports generated at `build/reports/spotbugs/main.xml`
3. Push to branch → Woodpecker CI runs → SonarQube shows SpotBugs findings
4. Quality gate still passes (no new critical/blocker bugs from SpotBugs)
5. `./gradlew check` includes SpotBugs in the task graph
