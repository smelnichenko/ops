# Registration Approval System

**Status: Phases 1–4 complete. Phase 5 (additional testing) pending.**

## Context

New users register, verify email, and then sit with zero permissions until an admin manually assigns groups via the Admin page. There's no notification to admins and no automated approval path. This plan adds a configurable registration approval system with three modes:

- **`ai`** (default) — AI auto-reviews and approves/declines; result posted to admin chat channel
- **`admin`** — posts a message with Accept/Decline buttons to a system chat channel visible to all admins
- **`skip`** — auto-assigns the default group on email verification (current-ish behavior, streamlined)

**Prerequisite:** Chat infrastructure (Kafka, ScyllaDB) becomes always-on (no longer feature-flagged), since the admin notification channel depends on it.

## Phase 1: Make Chat Always-On ✓

Remove the `monitor.chat.enabled` feature flag. Kafka + ScyllaDB become mandatory like PostgreSQL.

### Backend changes
| File | Change |
|------|--------|
| `config/ChatProperties.java` | Remove `enabled` field |
| `chat/service/ChatService.java` | Remove `@ConditionalOnProperty` |
| `chat/controller/ChatController.java` | Remove `@ConditionalOnProperty` |
| `chat/controller/ChatWebSocketController.java` | Remove `@ConditionalOnProperty` |
| `chat/kafka/ChatMessageConsumer.java` | Remove `@ConditionalOnProperty` |
| `chat/kafka/ChatKafkaProducer.java` | Remove `@ConditionalOnProperty` (if present) |
| `chat/WebSocketConfig.java` | Remove `@ConditionalOnProperty` |
| `config/KafkaConfig.java` | Remove conditional; always import KafkaAutoConfiguration |
| `Application.java` | Remove `KafkaAutoConfiguration` from global excludes |
| `application.yml` | Remove `chat.enabled`, keep ScyllaDB/E2E config |

### Infrastructure changes
| File | Change |
|------|--------|
| `docker-compose.yml` | Add Kafka + ScyllaDB services (always started with `task dev`) |
| `infra/helm/values.yaml` | Remove `kafka.enabled`, `scylla.enabled` flags; always deploy |
| `infra/helm/templates/kafka-*.yaml` | Remove `if .Values.kafka.enabled` conditionals |
| `infra/helm/templates/scylla-*.yaml` | Remove `if .Values.scylla.enabled` conditionals |
| `infra/helm/templates/networkpolicy.yaml` | Remove conditionals around Kafka/ScyllaDB NP rules |

### Frontend changes
| File | Change |
|------|--------|
| `services/api.ts` | Remove any chat-enabled config checks (if present) |

### Config cleanup
- Remove `CHAT_ENABLED` env var references from Helm deployment template
- Remove `chat.enabled` from `sonar-project.properties` exclusions (if any)
- Keep `CHAT` permission — controls user access, not infrastructure

## Phase 2: System Channels & Message Types ✓

### Database: Liquibase changeset `020-add-system-channel-and-approvals.xml`

**Implementation note:** Phases 2 and 3 database changes were combined into a single changeset file (`020-add-system-channel-and-approvals.xml`) with two changesets (020-1 for system channel, 020-2 for approvals).

### Planned: Liquibase changeset `020-add-system-channel-support.xml`

```sql
ALTER TABLE channels ADD COLUMN system BOOLEAN NOT NULL DEFAULT FALSE;
```

### ScyllaDB schema update (schema-job CQL + docker-compose init)

Add columns to `messages_by_channel`:
```cql
ALTER TABLE chat.messages_by_channel ADD message_type TEXT;
ALTER TABLE chat.messages_by_channel ADD metadata TEXT;
```

### Backend

**Channel entity** (`chat/entity/Channel.java`):
- Add `system` boolean field (default false)
- System channels: cannot be deleted, left, or have members kicked

**ChatMessageDto** (`chat/dto/ChatMessageDto.java`):
- Add `messageType` field: `USER` (default), `SYSTEM`
- Add `metadata` field: nullable JSON string for structured action data

**ScyllaMessageRepository**: Update save/read queries for new columns.

**ChatService**: Add guards — system channels block delete/leave/kick operations.

**SystemChannelService** (new: `chat/service/SystemChannelService.java`):
- `getOrCreateAdminChannel()` — lazily creates the "Admin Notifications" channel with `system=true`, `createdBy` = first admin user ID
- `syncAdminChannelMembers()` — ensures all users with MANAGE_USERS permission are members; called on channel access and when admin groups change
- `postSystemMessage(channelId, content, metadata)` — sends a message with `messageType=SYSTEM`, `userId=0`, `username=System`

### Frontend

**MessageArea.tsx**: Detect `messageType === 'SYSTEM'` messages and render differently:
- Different styling (centered, muted background, no edit button)
- If `metadata` contains `type: "approval"`, render Accept/Decline buttons
- Buttons call `/api/admin/approvals/{id}/approve` or `/decline`
- After action, buttons become disabled showing the outcome ("Approved by admin@..." or "Declined")

**ChannelList.tsx**: System channels get a distinct icon (bell or shield instead of #).

## Phase 3: Registration Approval ✓

**Implementation note:** Database changeset merged into `020-add-system-channel-and-approvals.xml` (changeset 020-2). Event handling uses `@TransactionalEventListener(phase = AFTER_COMMIT)` instead of `@EventListener` + `@Async` to avoid transaction contamination in the caller's context.

### Database: Liquibase changeset (merged into 020)

```sql
CREATE TABLE registration_approvals (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING, APPROVED, DECLINED
    decided_by VARCHAR(100),        -- admin email or "ai"
    decision_reason VARCHAR(1000),  -- AI explanation or admin note
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at TIMESTAMPTZ
);
CREATE INDEX idx_reg_approval_status ON registration_approvals(status);
```

### Config

**ApprovalProperties.java** (new: `config/ApprovalProperties.java`):
```java
@ConfigurationProperties(prefix = "monitor.auth.approval")
public record ApprovalProperties(
    @DefaultValue("ai") ApprovalMode mode,
    @DefaultValue("") String criteria,       // AI evaluation prompt
    @DefaultValue("Users") String defaultGroup
) {
    public enum ApprovalMode { SKIP, ADMIN, AI }
}
```

**application.yml** — add under `monitor.auth`:
```yaml
approval:
  mode: ${REGISTRATION_APPROVAL_MODE:ai}
  criteria: ${REGISTRATION_APPROVAL_CRITERIA:}
  default-group: ${REGISTRATION_APPROVAL_DEFAULT_GROUP:Users}
```

### Backend

**RegistrationApproval entity** (`entity/RegistrationApproval.java`):
- Fields: id, userId, status (enum: PENDING/APPROVED/DECLINED), decidedBy, decisionReason, createdAt, decidedAt

**RegistrationApprovalRepository** (`repository/RegistrationApprovalRepository.java`):
- `findByUserId(Long)`, `findByStatus(String)`, `existsByUserIdAndStatus(Long, String)`

**EmailVerifiedEvent** (new: `event/EmailVerifiedEvent.java`):
- Published from `EmailVerificationService.verify()` and the auto-verify path (mail disabled)
- Fields: userId, email

**RegistrationApprovalService** (new: `service/RegistrationApprovalService.java`):
- `@EventListener` for `EmailVerifiedEvent`
- `onEmailVerified(event)`:
  - If user already has groups (first user auto-admin), skip
  - `SKIP` mode: assign default group directly
  - `ADMIN` mode: create PENDING approval record, post system message to admin channel with metadata `{type:"approval", approvalId:N, userEmail:"..."}`
  - `AI` mode: create approval, call `AiApprovalService`, apply decision, post result to admin channel. On AI failure, fall back to ADMIN behavior (pending + message)
- `approve(approvalId, actingAdminId)`: set APPROVED, assign default group, bump permission version, update system message metadata
- `decline(approvalId, actingAdminId)`: set DECLINED, disable user, bump permission version, update system message metadata
- `getApprovalStatus(userId)`: returns status for the PendingApproval component
- `getPendingApprovals()`: returns list for admin visibility

**AiApprovalService** (new: `service/AiApprovalService.java`):
- Uses same Anthropic SDK pattern as `AiCollectionGeneratorService`
- Reuses `AiProperties` for client config (enabled, apiKey, model)
- Structured output: `AiApprovalDecision { boolean approved, String reason }`
- Input: user email + configurable criteria text
- Default criteria (when empty): "Approve all legitimate registrations. Decline obvious spam, disposable emails, or bot patterns."

**Admin API endpoints** (add to `AdminController.java`):
```
GET  /api/admin/approvals              — list pending approvals
POST /api/admin/approvals/{id}/approve — approve registration
POST /api/admin/approvals/{id}/decline — decline registration
```

**Auth API endpoint** (add to `AuthController.java`):
```
GET /api/auth/approval-status          — authenticated, returns {status, reason}
```

### Frontend

**PendingApproval.tsx**: Enhance to poll `/api/auth/approval-status` every 5s. When status changes to APPROVED, call `refreshPermissions()` and redirect. When DECLINED, show reason.

**Admin.tsx**: Add pending approval count badge on the Admin nav link. Optionally add an "Approvals" tab showing pending items (redundant with chat but useful for bulk management).

**api.ts**: Add `fetchApprovalStatus()`, `fetchPendingApprovals()`, `approveRegistration(id)`, `declineRegistration(id)`.

### Helm

**values.yaml**: Add under `auth`:
```yaml
auth:
  registrationApproval:
    mode: ai
    criteria: ""
    defaultGroup: Users
```

**Deployment template**: Add env vars `REGISTRATION_APPROVAL_MODE`, `REGISTRATION_APPROVAL_CRITERIA`, `REGISTRATION_APPROVAL_DEFAULT_GROUP`.

## Phase 4: User-Facing Messaging & Approval Email ✓

### Registration success screen (`Register.tsx`)
When approval mode is not `skip`, update the success message:
> "Check your email to verify your account. Once verified, your registration will be reviewed and you'll receive an email when approved."

Add `GET /api/auth/approval-mode` (public) returning `{mode: "admin"|"ai"|"skip"}` so frontend can tailor the message. When `skip`, show current message ("Check your email to verify your account").

### PendingApproval screen (`PendingApproval.tsx`)
Update message to: "Your account is pending approval. You'll receive an email when your account is approved."
Poll `/api/auth/approval-status` every 5s. On APPROVED → `refreshPermissions()` → redirect. On DECLINED → show reason + logout option.

### Approval notification email
When `RegistrationApprovalService.approve()` runs, send an email to the user:
- Subject: "Your account has been approved"
- Body: "Your registration has been approved. You can now log in at {appUrl}/login"
- Reuse existing `JavaMailSender` + `MailProperties` pattern from `EmailVerificationService`
- If mail is disabled, log the approval (consistent with existing pattern)

### Decline notification email
When `RegistrationApprovalService.decline()` runs, send an email:
- Subject: "Registration update"
- Body: "Your registration could not be approved. Reason: {reason}" (or generic message if no reason)
- Same mail pattern

## Phase 5: Testing (partial)

- **RegistrationApprovalServiceTest**: SKIP auto-assigns, ADMIN creates pending + posts message, AI approve/decline/fallback — not yet written
- **SystemChannelServiceTest**: Channel creation, member sync, system message posting — not yet written
- **AdminController approval tests**: Approve/decline endpoints, permission checks — not yet written
- **Frontend**: PendingApproval tests updated ✓, MessageArea system message rendering tests updated ✓, Register tests updated ✓, ChannelList tests updated ✓, Chat tests updated ✓

## Key Design Decisions

1. **Chat is always-on**: Kafka + ScyllaDB are mandatory infrastructure, like PostgreSQL. Simplifies conditional logic everywhere.
2. **System messages via existing chat pipeline**: Messages go through Kafka → ScyllaDB like normal messages but with `messageType=SYSTEM` and `userId=0`. Frontend renders them with action buttons based on `metadata`.
3. **Approval state in PostgreSQL**: `registration_approvals` table is the source of truth. Chat messages are notifications, not state.
4. **AI fallback**: If AI call fails, automatically fall back to ADMIN mode (create pending record, post to admin channel). No silent failures.
5. **First user exempt**: First user gets auto-added to Admins via existing migration. Approval service skips users who already have groups after verification.
6. **Admin channel membership sync**: `SystemChannelService.syncAdminChannelMembers()` runs when the channel is accessed and when admin group membership changes. No background polling.

## Critical Files

### New files
- `backend/.../config/ApprovalProperties.java`
- `backend/.../entity/RegistrationApproval.java`
- `backend/.../repository/RegistrationApprovalRepository.java`
- `backend/.../event/EmailVerifiedEvent.java`
- `backend/.../service/RegistrationApprovalService.java`
- `backend/.../service/AiApprovalService.java`
- `backend/.../chat/service/SystemChannelService.java`
- `backend/src/main/resources/db/changelog/changes/020-add-system-channel-and-approvals.xml`
- `infra/kafka/server.properties` (local dev Kafka config with dual listeners)
- `infra/scylla/schema.cql` (local dev ScyllaDB schema)

### Modified files
- `backend/.../chat/entity/Channel.java` — add `system` field
- `backend/.../chat/dto/ChatMessageDto.java` — add `messageType`, `metadata`
- `backend/.../chat/service/ChatService.java` — system channel guards, remove conditional
- `backend/.../chat/repository/ScyllaMessageRepository.java` — new columns
- `backend/.../service/EmailVerificationService.java` — publish EmailVerifiedEvent
- `backend/.../controller/AdminController.java` — approval endpoints
- `backend/.../controller/AuthController.java` — approval-status endpoint
- `backend/.../config/ChatProperties.java` — remove `enabled`
- `backend/.../config/KafkaConfig.java` — always-on
- `backend/src/main/resources/application.yml` — new config, remove chat.enabled
- `frontend/src/components/PendingApproval.tsx` — polling + status display
- `frontend/src/components/chat/MessageArea.tsx` — system message + action buttons
- `frontend/src/components/chat/ChannelList.tsx` — system channel icon
- `frontend/src/services/api.ts` — new API functions
- `frontend/src/pages/Admin.tsx` — approval count badge
- `frontend/src/App.tsx` — badge on Admin nav link
- `docker-compose.yml` — add Kafka + ScyllaDB
- `infra/helm/values.yaml` — remove kafka/scylla enabled flags, add approval config
- Various Helm templates — remove conditionals

## Additional Changes (not in original plan)

- **`task dev:infra`**: New Taskfile target — starts only infrastructure (postgres, redis, kafka, scylla, minio) for IDE debugging workflow. Backend runs via VS Code launch config.
- **Kafka dual listeners**: Local dev uses PLAINTEXT (Docker-internal) + EXTERNAL (host access on port 19092). Backend defaults to `localhost:19092`.
- **E2E tests moved**: Playwright tests moved from `tests/e2e/` to `frontend/tests/e2e/` (within frontend package scope for proper module resolution).
- **VS Code launch config**: Added `JWT_SECRET` env var to `.vscode/launch.json` for local debugging.

## Verification

1. `task dev` — verify Kafka + ScyllaDB start, chat works without feature flag
2. Register a new user with `mode: skip` — verify auto-assigned to Users group
3. Register with `mode: admin` — verify registration success page shows approval messaging
4. Verify email → log in → see PendingApproval screen with "you'll receive an email" message
5. Verify message appears in Admin Notifications channel with Accept/Decline buttons
6. Click Accept → verify approval email sent, user gets Users group, PendingApproval screen auto-transitions
7. Click Decline on another user → verify decline email sent, user sees declined message
8. Register with `mode: ai` — verify AI decision applied, result posted to admin channel, email sent
9. Test AI failure — verify fallback to pending admin review
10. `task test:backend` — all existing + new tests pass
11. `task test:e2e` — existing E2E tests still pass
