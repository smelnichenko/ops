# Hashcash Proof-of-Work Plan

## Context

Public auth endpoints (register, login, forgot-password) need bot protection. Instead of third-party CAPTCHAs or extra services, we implement Hashcash-style proof-of-work: the server issues a challenge, the client computes SHA-256 hashes until finding one with enough leading zero bits, and submits the solution. Difficulty scales with traffic via a sliding window rate tracker in Redis.

## Decision

DIY Hashcash using the existing Redis instance. No new infrastructure — challenges and rate counters stored in Redis with short TTLs. Frontend solves PoW in a Web Worker to avoid blocking the UI thread. Feature-flagged via `monitor.captcha.enabled`.

## How It Works

```
Client                              Server (Spring Boot)                  Redis
  │                                      │                                  │
  │  1. GET /captcha/challenge            │                                  │
  │  ────────────────────────────────────►│                                  │
  │                                      │  2. INCR sliding window counter   │
  │                                      │  ──────────────────────────────► │
  │                                      │  3. Calculate difficulty          │
  │                                      │  4. Generate random challenge     │
  │                                      │  5. SETEX challenge (60s TTL)     │
  │                                      │  ──────────────────────────────► │
  │  6. { challenge, difficulty }         │                                  │
  │  ◄────────────────────────────────────│                                  │
  │                                      │                                  │
  │  7. Web Worker: SHA-256(challenge     │                                  │
  │     + nonce) until N leading zeros    │                                  │
  │                                      │                                  │
  │  8. POST /auth/login                  │                                  │
  │     { email, password,                │                                  │
  │       captchaChallenge, captchaNonce }│                                  │
  │  ────────────────────────────────────►│                                  │
  │                                      │  9. GET challenge from Redis      │
  │                                      │  ──────────────────────────────► │
  │                                      │  10. DEL challenge (single-use)   │
  │                                      │  ──────────────────────────────► │
  │                                      │  11. Verify SHA-256 has N zeros   │
  │                                      │  12. Process auth request         │
  │  13. Auth response                    │                                  │
  │  ◄────────────────────────────────────│                                  │
```

## Adaptive Difficulty

Track auth requests in a **sliding window** (1-minute window, stored in Redis sorted set):

| Requests/min (global) | Required zero bits | ~Solve time (modern CPU) |
|------------------------|-------------------|--------------------------|
| 0-20                   | 16                | ~1ms                     |
| 21-50                  | 18                | ~4ms                     |
| 51-100                 | 20                | ~15ms                    |
| 101-200                | 22                | ~60ms                    |
| 201+                   | 24                | ~250ms                   |

Thresholds configurable via `monitor.captcha.difficulty.*`.

## Components

### Backend

**New files:**
- `CaptchaProperties.java` — config record (`monitor.captcha.*`)
- `HashcashService.java` — challenge generation, rate tracking, verification (uses `StringRedisTemplate`)
- `CaptchaController.java` — `GET /captcha/challenge` (conditional on `monitor.captcha.enabled=true`)
- `CaptchaConfigController.java` — `GET /captcha/config` (always active, reports enabled status)

**Modified files:**
- `AuthController.java` — verify PoW before processing register/login/forgot-password
- `AuthRequest.java` — add `captchaChallenge` + `captchaNonce` fields
- `SecurityConfig.java` — add `/captcha/**` to public endpoints + CSRF ignore
- `application.yml` — add `monitor.captcha` section

**Redis keys:**
- `pow:challenge:{challengeId}` — stores difficulty (SETEX, 60s TTL)
- `pow:rate` — sorted set for sliding window (member=requestId, score=timestamp)

### Frontend

**New files:**
- `frontend/src/workers/hashcash.worker.ts` — Web Worker: SHA-256 PoW solver
- `frontend/src/hooks/useHashcash.ts` — hook wrapping challenge fetch + worker solve

**Modified files:**
- `Login.tsx` — integrate hashcash hook, send challenge+nonce with form
- `Register.tsx` — same
- `ForgotPassword.tsx` — same

### Helm

**Modified files:**
- `values.yaml` — add `captcha:` section
- `app-deployment.yaml` — pass `CAPTCHA_ENABLED` env var (only if not already covered by app config)

## Configuration

```yaml
# application.yml
monitor:
  captcha:
    enabled: ${CAPTCHA_ENABLED:false}
    challenge-ttl: 60s           # Challenge expiry
    min-difficulty: 16           # Minimum zero bits
    max-difficulty: 24           # Maximum zero bits
    difficulty:
      low: 20                   # threshold: 0-20 req/min → 16 bits
      medium: 50                # threshold: 21-50 req/min → 18 bits
      high: 100                 # threshold: 51-100 req/min → 20 bits
      critical: 200             # threshold: 101-200 req/min → 22 bits
                                # 201+ → 24 bits
    rate-window: 60s            # Sliding window duration
```

## Files to Create/Modify

| File | Change |
|------|--------|
| `docs/plans/hashcash-pow-plan.md` | This plan |
| **Backend** | |
| `backend/src/.../config/CaptchaProperties.java` | Config record |
| `backend/src/.../service/HashcashService.java` | Challenge gen, rate tracking, verification |
| `backend/src/.../controller/CaptchaController.java` | Challenge endpoint (conditional) |
| `backend/src/.../controller/CaptchaConfigController.java` | Config endpoint (always active) |
| `backend/src/.../controller/AuthController.java` | Add PoW verification |
| `backend/src/.../dto/AuthRequest.java` | Add captcha fields |
| `backend/src/.../config/SecurityConfig.java` | Public `/captcha/**` |
| `backend/src/main/resources/application.yml` | Config section |
| **Frontend** | |
| `frontend/src/workers/hashcash.worker.ts` | Web Worker solver |
| `frontend/src/hooks/useHashcash.ts` | React hook |
| `frontend/src/pages/Login.tsx` | Integrate hook |
| `frontend/src/pages/Register.tsx` | Integrate hook |
| `frontend/src/pages/ForgotPassword.tsx` | Integrate hook |
| **Helm** | |
| `infra/helm/values.yaml` | Add captcha values |
| `infra/helm/templates/app-deployment.yaml` | CAPTCHA_ENABLED env var |
| **Test** | |
| `backend/src/.../service/HashcashServiceTest.java` | Unit tests (Mockito) |
| `backend/src/.../controller/CaptchaControllerTest.java` | Integration test (captcha enabled) |
| `backend/src/.../controller/CaptchaConfigControllerTest.java` | Integration test (captcha disabled) |
| `tests/ansible/test-hashcash.yml` | Vagrant integration test |
| `Taskfile.yml` | Add `test:hashcash` task |

## Implementation Order

1. Backend: CaptchaProperties + HashcashService + CaptchaController
2. Backend: AuthController + AuthRequest modifications
3. Frontend: Web Worker + hook + page integration
4. Helm values
5. Vagrant test
6. Tests + lint

## Verification

1. `./gradlew test` passes
2. `helm lint` passes
3. `task test:hashcash` — Vagrant integration test:
   - Redis running, captcha enabled
   - `GET /api/captcha/challenge` returns challenge + difficulty
   - Valid PoW solution accepted by `/api/auth/register`
   - Replayed challenge rejected (single-use)
   - Expired challenge rejected
   - Invalid nonce rejected
4. Frontend: auth pages show "Solving..." indicator, submit only after PoW completes

## Additional Changes

- Moved config classes into centralized `config` package (`ChatProperties`, `KafkaConfig`, `ScyllaConfig`)
- Replaced `@EnableConfigurationProperties` with `@ConfigurationPropertiesScan` for auto-discovery
- Added `NoResourceFoundException` handler to `GlobalExceptionHandler` (was returning 500 for missing resources)
- `AuthRequest` record: added 2-arg convenience constructor for backward compatibility
- `AuthContext.tsx`: added `CaptchaData` interface, extended login signature with optional captcha parameter

## Status

- [x] Plan created
- [x] Backend service + controllers (CaptchaController, CaptchaConfigController)
- [x] HashcashService (challenge gen, rate tracking, verification)
- [x] AuthController integration (register, login, forgot-password)
- [x] Frontend Web Worker + useHashcash hook
- [x] Frontend page integration (Login, Register, ForgotPassword)
- [x] Helm values + deployment template
- [x] Vagrant integration test + Taskfile entry
- [x] Unit + integration tests (HashcashServiceTest, CaptchaControllerTest, CaptchaConfigControllerTest)
- [x] Config package reorganization
- [x] Documentation updated
