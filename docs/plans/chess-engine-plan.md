# Chess Engine Integration Plan

## Context

Add a chess platform as a new `/chess` page alongside the existing Godot slot machine game at `/game`. AI games use **Stockfish WASM** running entirely in the browser (Web Worker) — zero server load. PvP games use the backend for move validation with **Kafka** for cross-replica event fan-out and **Redis** for game state caching. Game lifecycle is managed by a lightweight **enum-based state machine** on the JPA entity. The frontend uses `react-chessboard` + `chess.js`.

## Architecture Overview

```
React (react-chessboard + chess.js)
  ├── AI games:  Stockfish WASM (Web Worker, client-side only)
  └── PvP games: REST + STOMP/WebSocket
                    ↕
              Spring Boot ChessController (any replica)
                    ↕
              ChessService (enum state machine + chesslib validation)
                    ↕                         ↕
              Redis (game state cache)    Kafka topic: chess.moves
                                              ↕
                                    ChessEventConsumer (all replicas)
                                              ↕
                                    SimpMessagingTemplate → /topic/chess.{uuid}
```

### AI Games (client-side only)
- Stockfish WASM runs in a Web Worker — no backend involvement for AI moves
- Frontend sends UCI commands (`position fen ...`, `go movetime ...`) to the worker
- Difficulty controlled by Stockfish `Skill Level` (0-20) + `movetime`
- Game state persisted to backend for history/resume

### PvP Games (server-validated, multi-replica ready)
- **Move flow:** REST request hits any replica → validate with chesslib → persist to PostgreSQL → publish to Kafka `chess.moves` topic → all replicas consume → each replica broadcasts via `SimpMessagingTemplate` to locally-connected WebSocket clients
- **Same pattern as chat:** `ChatKafkaProducer` → Kafka → `ChatMessageConsumer` (delivery group) → `SimpMessagingTemplate`. Chess uses the same split: persistence consumer group + delivery consumer group.
- **Redis game cache:** Active game state (FEN, status, whose turn) cached in Redis. Reads hit Redis first, writes update both PostgreSQL and Redis. Avoids DB reads on every poll/move.
- **No sticky sessions needed:** Kafka fan-out ensures every replica delivers WebSocket events to its local clients regardless of which replica processed the move.

### Game State Machine (enum-based)

```java
public enum GameStatus {
    WAITING_FOR_OPPONENT,  // PvP: waiting for second player
    IN_PROGRESS,           // Game active, accepting moves
    FINISHED,              // Terminal: checkmate, stalemate, draw, resignation
    ABANDONED              // Terminal: player left before game started
}

public enum GameEvent {
    OPPONENT_JOINED,       // PvP: second player joins → IN_PROGRESS
    MOVE_MADE,             // Stay in IN_PROGRESS (validated by chesslib)
    CHECKMATE,             // → FINISHED
    STALEMATE,             // → FINISHED
    RESIGN,                // → FINISHED
    DRAW_AGREED,           // → FINISHED
    ABANDON                // → ABANDONED (only from WAITING_FOR_OPPONENT)
}
```

**Allowed transitions** (enforced in `ChessGame.transition()`):
| From | Event | To |
|------|-------|----|
| `WAITING_FOR_OPPONENT` | `OPPONENT_JOINED` | `IN_PROGRESS` |
| `WAITING_FOR_OPPONENT` | `ABANDON` | `ABANDONED` |
| `IN_PROGRESS` | `MOVE_MADE` | `IN_PROGRESS` |
| `IN_PROGRESS` | `CHECKMATE` | `FINISHED` |
| `IN_PROGRESS` | `STALEMATE` | `FINISHED` |
| `IN_PROGRESS` | `RESIGN` | `FINISHED` |
| `IN_PROGRESS` | `DRAW_AGREED` | `FINISHED` |

## Database Schema

### New migration: `021-create-chess-tables.xml`

```sql
chess_games (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid            UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    white_player_id BIGINT NOT NULL REFERENCES users(id),
    black_player_id BIGINT REFERENCES users(id),          -- NULL for AI games
    game_type       VARCHAR(10) NOT NULL,                  -- AI, PVP
    status          VARCHAR(20) NOT NULL,                  -- WAITING_FOR_OPPONENT, IN_PROGRESS, FINISHED, ABANDONED
    result          VARCHAR(20),                           -- WHITE_WINS, BLACK_WINS, DRAW
    result_reason   VARCHAR(30),                           -- CHECKMATE, RESIGNATION, STALEMATE, AGREEMENT, INSUFFICIENT_MATERIAL
    fen             TEXT NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    pgn             TEXT,
    ai_difficulty   INT,                                   -- Stockfish skill level 0-20, NULL for PVP
    move_count      INT NOT NULL DEFAULT 0,
    draw_offered_by BIGINT,                                -- user_id of draw offerer, NULL if no pending offer
    last_move_at    TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);
CREATE INDEX idx_chess_games_white ON chess_games(white_player_id);
CREATE INDEX idx_chess_games_black ON chess_games(black_player_id);
CREATE INDEX idx_chess_games_status ON chess_games(status);
```

## Backend: New Files

All under `backend/src/main/java/io/schnappy/monitor/chess/`:

### `GameStatus.java` + `GameEvent.java`
Enums as shown above. `GameStatus` persisted as `@Enumerated(EnumType.STRING)`.

### `ChessGame.java` (JPA entity)
- Maps to `chess_games` table
- `transition(GameEvent)` with allowed-transitions map, throws `IllegalStateException` on invalid
- `@JsonIgnore` on `whitePlayerId`, `blackPlayerId`

### `ChessGameRepository.java`
- `findByUuid(UUID)`
- `findActiveByUserId(Long userId)` — status IN_PROGRESS or WAITING, user is white or black
- `findByStatus(GameStatus)` — open lobby games
- `findByStatusAndIdGreaterThan(GameStatus, Long)` — paginated history

### `ChessGameDto.java`
- DTO for Kafka messages and API responses
- Fields: `gameUuid`, `fen`, `pgn`, `status`, `result`, `resultReason`, `moveCount`, `lastMove`, `whitePlayerEmail`, `blackPlayerEmail`, `drawOfferedBy`, `gameType`

### `ChessService.java`
- Orchestrates game lifecycle, move validation (chesslib), Kafka publishing, Redis caching
- `createAiGame(userId, difficulty)` → IN_PROGRESS, cache in Redis
- `createPvpGame(userId)` → WAITING_FOR_OPPONENT, cache in Redis
- `joinGame(gameUuid, userId)` → transition(OPPONENT_JOINED), publish to Kafka, update Redis
- `makeMove(gameUuid, move, userId)`:
  1. Load from Redis (fallback to DB)
  2. Verify it's the user's turn
  3. Validate move with chesslib against current FEN
  4. Apply move, update FEN + PGN + move_count
  5. Check for checkmate/stalemate → transition if terminal
  6. Persist to PostgreSQL
  7. Update Redis cache
  8. Publish `ChessGameDto` to Kafka `chess.moves` topic
  9. Return updated game
- `resign`, `offerDraw`, `acceptDraw`, `declineDraw`, `abandon` — all follow same pattern: validate → persist → cache → publish
- `getGame(gameUuid)` — Redis first, DB fallback

### `ChessKafkaProducer.java`
- Same pattern as `ChatKafkaProducer`
- Topic: `chess.moves` (keyed by game UUID for partition ordering)
- Publishes `ChessGameDto` after every state change

### `ChessEventConsumer.java`
- Same pattern as `ChatMessageConsumer` with two consumer groups:
  - `chess-persistence` group: persists game events (audit log, optional)
  - `chess-delivery` group: broadcasts to WebSocket clients via `SimpMessagingTemplate.convertAndSend("/topic/chess." + dto.getGameUuid(), dto)`
- Every replica consumes from delivery group → every replica pushes to its local WebSocket clients

### `ChessGameCacheService.java`
- Redis cache for active game state using `StringRedisTemplate`
- Key: `chess:game:{uuid}` → JSON-serialized `ChessGameDto`
- TTL: 1 hour (auto-evicts finished/abandoned games)
- Methods: `cacheGame(ChessGameDto)`, `getGame(UUID)`, `evictGame(UUID)`
- On cache miss: load from DB, cache, return

### `ChessController.java`
- `@RequestMapping("/chess")` + `@RequirePermission(Permission.PLAY)`
- `POST /api/chess/games` — Create game `{ type: "AI"|"PVP", difficulty?: 0-20 }`
- `GET /api/chess/games` — User's active games
- `GET /api/chess/games/open` — PvP lobby
- `GET /api/chess/games/{uuid}` — Game state (from Redis cache)
- `GET /api/chess/games/history` — Completed games (paginated, from DB)
- `POST /api/chess/games/{uuid}/join`
- `POST /api/chess/games/{uuid}/move` — `{ move: "e2e4" }`
- `POST /api/chess/games/{uuid}/resign`
- `POST /api/chess/games/{uuid}/draw`
- `POST /api/chess/games/{uuid}/draw/accept`
- `POST /api/chess/games/{uuid}/draw/decline`
- `DELETE /api/chess/games/{uuid}` — Abandon

### `ChessProperties.java`
- `@ConfigurationProperties(prefix = "monitor.chess")`
- `enabled` (feature flag)

## Backend: Modified Files

| File | Change |
|------|--------|
| `build.gradle` | Add `com.github.bhlangonijr:chesslib:1.3.3` |
| `application.yml` | Add `monitor.chess.enabled` |
| `db.changelog-master.xml` | Include `021-create-chess-tables.xml` |
| `SubscriptionGuard.java` | Add `/topic/chess.{uuid}` pattern, validate game membership |

## Frontend: New Files

### Dependencies
- `react-chessboard` — board UI with drag-and-drop
- `chess.js` — client-side move validation, FEN/PGN parsing
- `stockfish` — Stockfish WASM for AI games

### `frontend/src/hooks/useStockfish.ts`
- Loads Stockfish WASM in a Web Worker
- `getBestMove(fen, skillLevel, moveTimeMs)` async
- Cleans up worker on unmount

### `frontend/src/pages/Chess.tsx`
- **Lobby view**: "Play vs AI" + difficulty slider, "Create PvP Game", open games list, active games
- **Game view**: `ChessBoard` + `MoveHistory` + `GameControls`

### `frontend/src/components/chess/ChessBoard.tsx`
- `react-chessboard` + `chess.js`, drag-and-drop, legal move highlighting
- AI: calls `useStockfish().getBestMove()` after user move
- PvP: subscribes to STOMP `/topic/chess.{uuid}` for real-time opponent moves

### `frontend/src/components/chess/GameLobby.tsx`
### `frontend/src/components/chess/MoveHistory.tsx`
### `frontend/src/components/chess/GameControls.tsx`
### `frontend/src/components/chess/GameOverDialog.tsx`

## Frontend: Modified Files

| File | Change |
|------|--------|
| `App.tsx` | Add lazy import for `Chess`, add `/chess` route + nav link under PLAY permission |
| `api.ts` | Add chess types + API functions (existing game API untouched) |

## Kafka Topic

Add `chess.moves` topic (6 partitions) to the existing Kafka topics init job. Keyed by game UUID to guarantee move ordering per game.

## Helm Values

Add to `values.yaml`:
```yaml
chess:
  enabled: true
```

Add to `app-deployment.yaml`:
```yaml
- name: CHESS_ENABLED
  value: {{ .Values.chess.enabled | quote }}
```

## Implementation Order

### Phase 1: Backend
1. Add `chesslib` to `build.gradle`
2. Create `ChessProperties.java` + config in `application.yml`
3. Create `GameStatus.java`, `GameEvent.java`
4. Create `ChessGame.java` + `ChessGameRepository.java`
5. Create `ChessGameDto.java`
6. Create Liquibase migration `021-create-chess-tables.xml`
7. Implement `ChessGameCacheService.java` (Redis)
8. Implement `ChessKafkaProducer.java`
9. Implement `ChessEventConsumer.java` (Kafka → WebSocket delivery)
10. Implement `ChessService.java` (game lifecycle + chesslib + Redis + Kafka)
11. Implement `ChessController.java`
12. Extend `SubscriptionGuard.java`
13. Add `chess.moves` topic to Kafka topics init

### Phase 2: Frontend
14. Add `react-chessboard`, `chess.js`, `stockfish` to `package.json`
15. Add chess types + API functions to `api.ts`
16. Create `useStockfish.ts`
17. Create chess components
18. Create `Chess.tsx` page
19. Update `App.tsx` (add `/chess` route + nav link)

### Phase 3: Helm
20. Update `values.yaml` + `app-deployment.yaml`

## Status: COMPLETE

All phases implemented on branch `feature/chess-engine`.

**Test results:**
- Backend: 711 tests, 0 failures (49 chess unit tests + 14 chess integration tests + existing tests)
- Frontend: 374 tests, 0 failures (9 chess tests + existing tests)
- TypeScript: compiles clean (`tsc --noEmit`)
- Vite build: succeeds

**Notable fixes during implementation:**
- `ChessGameCacheService`: Uses static `ObjectMapper` (not injected) — matches project pattern, avoids test context loading order issue
- `ChessKafkaProducer`: Null-safe `send()` return — mocked `KafkaTemplate` returns null in tests
- `react-chessboard` v5: Uses `options` prop pattern (not direct props like v4)
- Liquibase `uuid` column: No `defaultValueComputed="gen_random_uuid()"` — H2 (jOOQ codegen) doesn't support it; UUID generated by JPA entity

## Verification

1. **Backend unit tests:** `ChessGame.transition()`, `ChessService` (create, move, checkmate, PvP flow)
2. **Integration tests:** Full PvP flow with Kafka + Redis (TestContainers), WebSocket broadcast
3. **Frontend tests:** Board rendering, move submission, lobby
4. **Manual E2E:** `task dev` → AI game (Stockfish WASM) + PvP game across two browsers (verify Kafka-mediated WebSocket delivery)
