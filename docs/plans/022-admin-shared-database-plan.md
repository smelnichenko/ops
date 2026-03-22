# Migrate User/Auth Ownership to Admin Service

**Status: COMPLETE (2026-03-19)**

## Context

The admin service was extracted from the core app to own authentication, user management, groups, and permissions. It has its own database (`monitor_admin`). The core app needed to be cleaned of all duplicated functionality and data migrated to microservice databases.

## What Was Done

### Phase 1: Data Migration + Auth Routing (2026-03-18)

1. **Enriched admin's UserEventProducer** — `USER_CREATED`, `USER_ENABLED/DISABLED` events with full user data (userId, uuid, email, enabled). Hooked up `publishUserEnabled()` in `AdminService.setUserEnabled()`.

2. **Added Kafka UserEventConsumer to core app** — Listens to `user.events` topic, upserts users into local `users` table for JWT validation and FK integrity. Also triggers default monitor creation for new users.

3. **SQL data migration** — Copied users, user_groups, email_verification_tokens, password_reset_tokens from `monitor` → `monitor_admin` via dblink. Group IDs matched (both had Admins=1, Users=2).

4. **Gateway routing** — `/api/auth/**`, `/api/captcha/**`, `/api/user/**`, `/api/permissions/**`, `/api/admin/**` route to admin service. Core app catch-all handles remaining `/api/**`.

5. **Added REDIS_PASSWORD** to admin, chat, chess Helm deployments.

### Phase 2: Core App Cleanup (2026-03-19)

Removed ~12,500 lines of dead code from the core app:

- `chess/` package (15 files) + tests — now in chess service
- `chat/` package (27 files) + tests — now in chat service
- Auth/Admin/Captcha/User/Permissions controllers + services — now in admin service
- Related entities, repositories, configs, events
- DataStax driver, chesslib, websocket dependencies removed from build.gradle

**Core app now only owns:** monitors, RSS feeds, inbox/webhooks, game (slots).

### Phase 2b: Data Migration for Chess/Chat (2026-03-19)

- Migrated chess_games (3 rows) from `monitor` → `monitor_chess`
- Migrated channels (1), channel_members (3) from `monitor` → `monitor_chat`
- Chat/chess services don't need UserEventConsumer — JWT-only validation, no DB user lookups

### Phase 2c: Swagger/OpenAPI (2026-03-19)

Added `springdoc-openapi-starter-webmvc-ui:2.8.6` to all 4 services:
- Core app: `/api/swagger-ui.html`
- Admin: `/api/swagger-ui.html`
- Chat: `/api/swagger-ui.html`
- Chess: `/api/swagger-ui.html`

## Architecture After Migration

```
Frontend → Gateway → admin (monitor_admin DB) — auth, users, groups, captcha, permissions
                   → core app (monitor DB)     — monitors, RSS, inbox, webhooks, game
                   → chat (monitor_chat DB)    — channels, messages (ScyllaDB)
                   → chess (monitor_chess DB)  — chess games

Admin → Kafka (user.events) → Core app UserEventConsumer → upserts users + creates default monitors
```

## Future Work

- [ ] Webhooks: move to dedicated service or keep in core (TBD)
- [ ] Drop orphaned tables from `monitor` DB (chess_games, channels, channel_members, etc.)
- [ ] JWT invalidation on password reset
