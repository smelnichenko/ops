# End-to-End Encryption for Chat

## Context

Chat messages are currently stored and transmitted as plaintext. The server (Kafka, ScyllaDB, backend) can read all message content. E2E encryption ensures only channel members can read messages — the server stores and relays ciphertext it cannot decrypt. This builds on the existing hash chain (which will operate on ciphertext) and channel membership infrastructure.

## Cryptographic Design

- **Identity keys**: ECDH P-256 key pair per user (Web Crypto API native, no npm packages)
- **Private key protection**: PBKDF2(password, 16-byte salt, 600k iterations) derives AES-256-GCM wrapping key; private key exported as PKCS8, encrypted client-side before upload
- **Channel key**: Random AES-256-GCM symmetric key per channel
- **Channel key distribution**: Ephemeral ECDH key pair per wrap; ECDH(ephemeral, recipient_public) derives shared secret; AES-GCM-wrap channel key with shared secret; store ephemeral public key alongside wrapped key
- **Message encryption**: AES-256-GCM, random 12-byte IV per message, stored as `base64(iv || ciphertext || tag)`
- **Hash chain**: Operates on ciphertext (no change to hash computation logic)
- **Key rotation**: New channel key on member removal; old key version retained for historical message decryption

**Why P-256**: Native Web Crypto API support (X25519 requires external library). P-256 is fast, widely supported, and sufficient security margin.

**Why not Signal Double Ratchet**: Overkill for small-scale app. Per-channel symmetric key with rotation on member removal provides adequate forward secrecy.

## Database Schema Changes

### PostgreSQL (Liquibase `018-add-e2e-encryption.xml`)

```sql
-- User identity key pairs (encrypted private key stored server-side)
CREATE TABLE user_keys (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT UNIQUE NOT NULL REFERENCES users(id),
    public_key TEXT NOT NULL,              -- JWK-encoded ECDH P-256 public key
    encrypted_private_key TEXT NOT NULL,   -- base64(AES-GCM encrypted PKCS8)
    pbkdf2_salt TEXT NOT NULL,             -- base64(16-byte random salt)
    pbkdf2_iterations INT NOT NULL DEFAULT 600000,
    key_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Per-member encrypted channel keys
CREATE TABLE channel_key_bundles (
    id BIGSERIAL PRIMARY KEY,
    channel_id BIGINT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_version INT NOT NULL DEFAULT 1,
    encrypted_channel_key TEXT NOT NULL,   -- base64(ECDH-wrapped AES-256 key)
    wrapper_public_key TEXT NOT NULL,      -- JWK of ephemeral ECDH public key
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(channel_id, user_id, key_version)
);

-- Add to channels table
ALTER TABLE channels ADD COLUMN encrypted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE channels ADD COLUMN current_key_version INT NOT NULL DEFAULT 0;
```

### ScyllaDB

Add `key_version int` column to `messages_by_channel` and `message_edits` tables (nullable for backward compat). No other schema changes — `content` column stores ciphertext as text (base64).

## New REST Endpoints

```
# Key management
GET    /api/chat/keys                          # Get user's keys (public + encrypted private)
POST   /api/chat/keys                          # Upload key pair (first time)
PUT    /api/chat/keys                          # Re-encrypt private key (password change)
GET    /api/chat/keys/public?userIds=1,2,3     # Batch fetch public keys

# Channel key management
GET    /api/chat/channels/{id}/keys            # Get encrypted channel key for current user
POST   /api/chat/channels/{id}/keys            # Set encrypted channel keys for all members
POST   /api/chat/channels/{id}/keys/rotate     # Rotate key (generates new version)
```

## Message Flow (Before vs After)

```
BEFORE: plaintext -> Kafka -> ScyllaDB (plaintext) -> WebSocket -> display
AFTER:  plaintext -> encrypt(channelKey) -> ciphertext -> Kafka -> ScyllaDB (ciphertext) -> WebSocket -> decrypt(channelKey) -> display
```

Backend code unchanged for message persistence — it stores whatever `content` string arrives. Hash chain computes on ciphertext.

## Implementation Steps

All steps complete.

### Step 1: Database schema + backend entities ✅

- `018-add-e2e-encryption.xml` — Liquibase migration (user_keys, channel_key_bundles, channels.encrypted, channels.current_key_version)
- `UserKeys.java` — JPA entity
- `ChannelKeyBundle.java` — JPA entity
- `UserKeysRepository.java` — Spring Data repo
- `ChannelKeyBundleRepository.java` — Spring Data repo
- `E2eProperties.java` — `@ConfigurationProperties("monitor.chat.e2e")` with `enabled` flag
- Update `Channel.java` — add `encrypted`, `currentKeyVersion` fields
- Update `ChannelDto.java` — add `encrypted` field
- Update `CreateChannelRequest.java` — add `encrypted` field
- ScyllaDB schema: add `key_version int` to `messages_by_channel` and `message_edits`

### Step 2: Backend key management endpoints ✅

- DTOs: `UserKeysDto`, `UploadKeysRequest`, `ChannelKeyBundleDto`, `SetChannelKeysRequest`
- Key management endpoints on `ChatController`: GET/POST/PUT keys, GET public keys
- Channel key endpoints: GET/POST/POST-rotate channel keys
- Update `ChatService`: key distribution on invite, key bundle deletion on kick/leave, key rotation trigger
- Update `ChatMessageDto` + `ScyllaMessageRepository`: pass through `keyVersion`
- Update `ChatMessageConsumer`: pass through `keyVersion`

### Step 3: Frontend crypto module ✅

- `crypto.ts` — Web Crypto API wrapper: key generation, PBKDF2 derivation, private key encrypt/decrypt, channel key wrap/unwrap, message encrypt/decrypt
- `keyStore.ts` — In-memory key cache (identity key pair + channel keys by version), cleared on logout

Functions in `crypto.ts`:
- `generateIdentityKeyPair()` — ECDH P-256
- `deriveWrappingKey(password, salt, iterations)` — PBKDF2 -> AES-256-GCM key
- `encryptPrivateKey(privateKey, wrappingKey)` / `decryptPrivateKey(encrypted, wrappingKey)`
- `generateChannelKey()` — random AES-256-GCM key
- `wrapChannelKeyForMember(channelKey, recipientPublicKey)` — ephemeral ECDH + AES-GCM wrap
- `unwrapChannelKey(encryptedKey, ephemeralPublicKey, recipientPrivateKey)` — ECDH derive + unwrap
- `encryptMessage(plaintext, channelKey)` / `decryptMessage(ciphertext, channelKey)`

### Step 4: Login integration ✅

- `AuthContext.tsx`: On login, after auth succeeds (password still in memory):
  - Fetch `GET /api/chat/keys`
  - If exists: derive wrapping key from password, decrypt private key, store in KeyStore
  - If not exists: generate key pair, encrypt private key, upload via `POST /api/chat/keys`, store in KeyStore
- On logout: `keyStore.clear()`
- `api.ts`: Add key management API functions

### Step 5: Encrypted channel messaging ✅

- `CreateChannelModal.tsx`: "Encrypted" toggle; after creation, generate channel key, wrap for creator, upload
- `MessageArea.tsx`:
  - On mount: fetch channel key bundle, unwrap with identity private key, cache in KeyStore
  - On send: encrypt plaintext with channel key, send ciphertext
  - On receive (WebSocket): decrypt with channel key
  - On edit: encrypt new content
  - Decryption failure: show "[Unable to decrypt]" with lock icon
- `ChannelList.tsx`: Lock icon next to encrypted channels

### Step 6: Member management + key rotation ✅

- `InviteModal.tsx`: On invite to encrypted channel, fetch invitee's public key, wrap channel key, upload bundle
- `MembersModal.tsx`: On kick from encrypted channel, trigger key rotation — generate new channel key, wrap for remaining members, upload via rotate endpoint
- `ChatService.java`: On leave, delete user's key bundle, flag rotation needed
- Handle "waiting for encryption key" state for new members

### Step 7: Password change handling ✅

- Password reset flow: user loses encrypted private key. On next login, generate new key pair, overwrite old. Old channel key bundles invalidated — user must be re-invited to encrypted channels.
- UI warning on forgot-password/reset-password pages: "Resetting your password will revoke access to encrypted chat history."
- Future "change password" feature (old password available): re-encrypt private key with new password, no data loss.

### Step 8: Helm + feature flag ✅

- `values.yaml`: add `chat.e2e.enabled: false`
- `application.yml`: add `monitor.chat.e2e-enabled: ${CHAT_E2E_ENABLED:false}`
- When disabled: key endpoints return 404, `encrypted` flag ignored, everything works as before

### Step 9: Tests ✅

- `crypto.test.ts`: Key generation, encrypt/decrypt round-trips, wrong-key failures, wrap/unwrap
- `ChatServiceTest.java`: Key CRUD, channel key distribution, rotation on kick
- `ChatControllerTest.java`: Key management endpoints, encrypted channel creation
- Playwright E2E: create encrypted channel, send/receive, invite member, kick + rotation

### Step 10: Documentation ✅

- Update `CLAUDE.md` — Chat Service section with E2E encryption details

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Curve | ECDH P-256 | Native Web Crypto API, no npm dependency |
| Private key storage | Server-side (encrypted) | Multi-device support, key recovery on same password |
| Channel key distribution | Ephemeral ECDH per wrap | Compromise of distributor's identity key doesn't reveal past channel keys |
| Key rotation trigger | Member removal | Forward secrecy for removed members |
| Existing messages | No migration | Cannot retroactively encrypt; new encrypted channels only |
| Password reset | New key pair, lose history | Fundamental E2E tradeoff; warn user in UI |
| Hash chain | On ciphertext | Server can verify chain integrity without decrypting |
| PBKDF2 iterations | 600,000 | OWASP 2023 recommendation for SHA-256 |

## Edge Cases

- **Channel owner offline during rotation**: Rotation deferred until owner's client loads channel. Accepted tradeoff.
- **Multiple tabs**: Each tab independently downloads/decrypts keys (in-memory only). No persistent browser storage.
- **WebSocket race**: If channel key not loaded when message arrives, queue messages and decrypt once key available.
- **Pre-E2E messages**: Unencrypted channels and messages continue to work. Mixed mode supported.

## Files Summary

| Category | New Files | Modified Files |
|----------|-----------|----------------|
| Backend entities/repos | 6 | 0 |
| Backend DTOs | 4 | 3 |
| Backend service/controller | 0 | 4 |
| Backend config | 2 | 2 |
| Backend schema | 1 | 2 |
| Frontend crypto | 2 | 0 |
| Frontend components | 0 | 6 |
| Helm | 0 | 1 |
| Total | **15 new** | **18 modified** |

## Verification

1. `./gradlew test` — all existing + new tests pass
2. `tsc --noEmit` — frontend compiles
3. `helm lint` — chart valid
4. Manual: create encrypted channel, send message, verify ciphertext in ScyllaDB, verify plaintext in UI
5. Manual: invite user, verify they can decrypt; kick user, verify new messages use rotated key
6. Manual: password reset, verify new key pair generated, old encrypted channels show "[Unable to decrypt]"
7. Manual: verify hash chain still works (on ciphertext)
8. `task test:chat` — Vagrant integration test passes
