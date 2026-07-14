# 078 — Radar frontend rewrite: React web first, React Native later

## Decision
Rewrite `radar`'s served frontend (`app.js`, ~2500 lines of vanilla JS) as a componentized
**React 19 + TypeScript + Vite** app, with the API/state core kept **platform-neutral** so a
**React Native** mobile shell can reuse it as a later arc. ("Both, web first" — decided 2026-07-14.)

## Why
- app.js has outgrown single-file discipline: 8 views, a WebSocket state feed, Leaflet, two canvas
  renderers, photo/lightbox machinery, gesture handling, band control, telemetry — all in one scope.
  Tonight's bug ledger (#255-#272) repeatedly traced to cross-cutting state no one owns.
- "Proper design, separation, and low complexity" (the user's framing): components own their DOM,
  a store owns the state, the API layer owns the wire.

## Architecture
```
frontend/                     # React 19 + TS + Vite (dir in the radar repo)
  src/core/                   # PLATFORM-NEUTRAL (the future RN app imports this)
    api/    ws.ts http.ts     # /ws state feed (reconnect), REST verbs (band/target/stop/nudge/...)
    state/  store.ts          # single store: live snapshot + UI intent (zero-dep, useSyncExternalStore)
    lib/    units.ts geo.ts   # formatting, closest/shown selection, gesture window constants
  src/web/                    # WEB-ONLY
    views/  Sky Sea SkyMap SeaMap SkyCoverage SeaCoverage Settings
    components/ RadarScope MapView(Leaflet) Panel PhotoBox Lightbox Deck HistoryList Badges
  index.html                  # built to backend/src/main/resources/web/static-v2 during migration
```
- No state library: a ~50-line store module + `useSyncExternalStore` (matches "low complexity";
  RN-compatible; `site/` uses plain React contexts — same spirit).
- Leaflet, canvas PPIs, SVG scopes are web components; RN later swaps `src/web` for `src/native`
  (react-native-maps etc.) over the same core.

## Migration strategy (the live tool must never regress)
1. **Scaffold PR**: `frontend/` + Gradle wiring (a `buildFrontend` task runs `vite build` into
   `static-v2/`; the jar serves it at `/v2/`). The old page stays the default.
2. **Core PR**: ws feed + store + REST layer + unit tests (vitest). `/v2/` renders the status header
   live — proof of the pipe.
3. **View parity PRs**, one surface each, verified against the rendered DOM (playwright, the house
   discipline): Sky scope → Sea scope → Maps (markers/trails/heat/domains) → Panels (info/photo/
   lightbox/history) → Deck (track/stop/release/nudge/align — the #261 semantics!) → Coverages →
   Settings.
4. **Parity checklist gate** (grown from tonight's fixes — each is a regression test):
   700ms double-click window + miss telemetry (#262); band sync + 20s keepalive, hidden-tab guarded
   (#256); sea auto-track ring/row semantics (#263, #259); Release preserves stopped (#261); resume
   grace (#260); ship photos incl. Commons fallback + persistent img (#252/#265/#266); trails on
   separate layers (#253); mount reticles both scopes (#258); fluid panel heights (#270-#272);
   status badge decay (#268); XSS-safe tooltips; no /api/band calls from hidden tabs.
5. **Swap PR**: `/` serves the React build; the old page moves to `/v1/` for one release, then deleted.
6. **RN arc** (separate plan when reached): Expo shell over `src/core`, native maps, the field-use case.

## Risks / notes
- Playwright headless must keep aborting `/api/band/**` (hardware!).
- The jar serves everything; CSP/no-CDN discipline unchanged (all deps bundled).
- Woodpecker CI gets a `vite build + vitest` step (after the rename re-sync).
- app.js stays frozen except critical fixes during the migration (double-maintenance window kept short).
