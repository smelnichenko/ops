# Integrate OWASP Dependency-Check

## Context

No dependency vulnerability scanning exists. OWASP Dependency-Check scans project dependencies against the NVD (National Vulnerability Database) and reports known CVEs. Adding it to all 5 Java services and feeding reports into SonarQube provides automated supply-chain security checking in CI.

The main challenge is the NVD database download (~500MB on first run). CI pods are ephemeral so we need a caching strategy to avoid re-downloading on every build.

## Scope

All Java services: monitor-backend, admin, chat, chess, api-gateway.

## Implementation

### 1. Add Dependency-Check Gradle plugin to all services

**Plugin:** `org.owasp.dependencycheck` (latest)

Each `build.gradle` gets:
```gradle
plugins {
    id 'org.owasp.dependencycheck' version '12.1.1'
}

dependencyCheck {
    formats = ['HTML', 'XML']
    failBuildOnCVSS = 9   // Only fail on critical (9+), report all
    analyzers {
        assemblyEnabled = false       // .NET, not needed
        nodeEnabled = false           // npm, not needed for Java
        retirejs { enabled = false }  // JS, not needed
    }
    nvd {
        apiKey = System.getenv('NVD_API_KEY') ?: ''  // Optional, increases rate limit
    }
}
```

**Files to modify:**
- `/home/sm/src/monitor/backend/build.gradle`
- `/home/sm/src/admin/build.gradle`
- `/home/sm/src/chat/build.gradle`
- `/home/sm/src/chess/build.gradle`
- `/home/sm/src/api-gateway/build.gradle`

### 2. NVD database caching via shared Gradle cache

OWASP Dependency-Check stores its NVD database in `~/.gradle/dependency-check-data/`. In CI, each pod starts fresh. Options:

**Option A — PVC-backed Gradle cache (recommended):** Mount a shared PVC at `/root/.gradle/dependency-check-data/` in pipeline pods. First run downloads the DB, subsequent runs use cached data with incremental updates (~seconds).

Add to each CI/CD step's `backend_options`:
```yaml
backend_options:
  kubernetes:
    volumes:
      - name: nvd-cache
        persistentVolumeClaim:
          claimName: woodpecker-nvd-cache
    volumeMounts:
      - name: nvd-cache
        mountPath: /root/.gradle/dependency-check-data
```

Create PVC via Helm template: `infra/helm/templates/woodpecker-nvd-cache-pvc.yaml` (1Gi, `local-path`).

**Option B — NVD API key (complementary):** Register for a free NVD API key at https://nvd.nist.gov/developers/request-an-api-key. Increases rate limit from 5 req/30s to 50 req/30s, making updates faster.

### 3. Wire into SonarQube

Add to each service's `sonar.properties` block:
```gradle
property 'sonar.dependencyCheck.htmlReportPath', "${layout.buildDirectory.get()}/reports/dependency-check-report.html"
property 'sonar.dependencyCheck.jsonReportPath', "${layout.buildDirectory.get()}/reports/dependency-check-report.json"
```

Requires **sonar-dependency-check-plugin** installed in SonarQube. Check if installed; if not, download and deploy.

### 4. CI/CD pipeline — add separate step

Dependency-Check is slow (~2-5 min with cached DB). Run as a **separate parallel step** that doesn't block the test/build flow:

Add to `.woodpecker/ci.yaml` and `.woodpecker/cd.yaml`:
```yaml
- name: backend-dependency-check
  image: eclipse-temurin:25-jdk
  commands:
    - ./gradlew dependencyCheckAnalyze --no-daemon
  backend_options:
    kubernetes:
      resources:
        requests: { cpu: 250m, memory: 1Gi }
        limits: { cpu: 2000m, memory: 2Gi }
      volumes:
        - name: nvd-cache
          persistentVolumeClaim:
            claimName: woodpecker-nvd-cache
      volumeMounts:
        - name: nvd-cache
          mountPath: /root/.gradle/dependency-check-data
      secrets:
        - name: woodpecker-ci-secrets
          key: nexus_url
          target:
            env: NEXUS_URL
        - name: woodpecker-ci-secrets
          key: nvd_api_key
          target:
            env: NVD_API_KEY
```

Same pattern for each microservice's `.woodpecker/cd.yaml`.

### 5. Suppress known false positives

Create `dependency-check-suppression.xml` per service if needed:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
    <!-- Add suppressions here as needed -->
</suppressions>
```

Reference in build.gradle:
```gradle
dependencyCheck {
    suppressionFile = 'dependency-check-suppression.xml'
}
```

### 6. Run locally, review initial report

Run `./gradlew dependencyCheckAnalyze` on each service. Review findings, suppress false positives, ensure no critical CVEs block the build.

## Files to create/modify

| File | Action |
|------|--------|
| `*/build.gradle` (5 services) | Add plugin + config |
| `infra/helm/templates/woodpecker-nvd-cache-pvc.yaml` | New PVC for NVD cache |
| `.woodpecker/ci.yaml`, `.woodpecker/cd.yaml` | Add dependency-check step |
| `*/.woodpecker/cd.yaml` (4 microservices) | Add dependency-check step |
| `woodpecker-ci-secrets` | Add `nvd_api_key` (optional) |
| `docs/plans/owasp-dependency-check-plan.md` | This plan |

## Verification

1. `./gradlew dependencyCheckAnalyze` completes on all 5 services locally
2. HTML + XML reports generated at `build/reports/`
3. Push → Woodpecker runs dependency-check step → passes (or reports CVEs)
4. SonarQube shows dependency-check findings (if plugin installed)
5. NVD cache PVC persists across builds (second run is fast)
