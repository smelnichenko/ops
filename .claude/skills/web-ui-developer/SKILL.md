---
name: web-ui-developer
description: Front-end discipline across this org's web UIs — the hand-written no-build served-static surfaces (plane-tracker) AND the compiled component frontends (React 19 + Vite in `site/`; Svelte if adopted). Read BEFORE writing or reviewing any CSS/layout/DOM change — sizing, flex/grid layout, show/hide toggling, responsive/fluid layout, theme, touch targets — or any fetch/WebSocket-driven UI. Encodes the measure-the-rendered-DOM-never-the-source discipline; the cascade/`[hidden]`/box-sizing traps that apply to GLOBAL stylesheets only; and the reactive-effect/subscription-lifecycle traps of component frameworks.
---

# Web UI development discipline

Working rules for this org's web front-ends. Two surfaces, with **opposite** constraints:

- **No-build, served-static** (plane-tracker `web/static/`): hand-authored HTML/CSS/vanilla-JS read from
  disk per request, one global stylesheet, driven by `fetch`/WebSocket.
- **Compiled component frontend** (`site/`, package `monitor-frontend`): React 19 + Vite 7 + TypeScript,
  tested with Vitest + Testing Library, realtime via Centrifugo.

Rules **1, 3, 4, 5, 6, 8, 9, 10** are universal — they are CSS and browser facts, not framework facts.
Rules **2, 7, 11, 13** describe a *global* stylesheet and a *no-build* pipeline; §14 says exactly how each
changes under a compiler. Read §14 before applying them to `site/`.

Every rule below was paid for on a real UI; skip one and you ship a layout bug you "verified" by reading
the source.

## 1. Verify in the rendered DOM, never from the source

CSS source does not tell you the rendered size, position, or visibility of anything — the cascade,
box model, flex/grid, and inherited resets do. **Measure the live DOM after every change:**

- `getBoundingClientRect()` for actual size/position; `getComputedStyle(el)` for the used value of a
  property (it resolves `44px`, `flex`, `none` even for a `display:none` element — so you can assert
  a rule that governs a currently-hidden element).
- A screenshot for anything you're judging visually (wrapping, overlap, alignment, "does it look
  right"). Read the screenshot; don't infer it.
- After a change, re-measure the thing you changed **and** its neighbors — sizing one element
  reflows siblings, wraps rows, and grows containers.

"It's a one-line CSS change, it obviously works" is how you ship a clipped label. One-line changes to
shared rules are the *most* likely to regress something off-screen. Measure.

## 2. `hidden` attribute vs `display` — the companion-rule trap
*(global stylesheets. Mostly moot in a component framework — see §14.)*

The UA sheet has `[hidden] { display: none }` at the lowest specificity. **Any** author rule that
sets `display` (e.g. `.route { display: flex }`) beats it, so toggling the `hidden` attribute on that
element does nothing — it stays visible. Every element that (a) has an author `display:flex/grid/...`
rule and (b) is shown/hidden via the `hidden` attribute needs a companion rule:

```css
.route { display: flex; }
.route[hidden] { display: none; }   /* author-specificity so `hidden` actually hides it */
```

Decide per element: toggle the `hidden` attribute (needs the companion rule; keeps semantics/AX) **or**
toggle `style.display`/a class. Don't half-do it. When you flip visibility in JS, prefer one mechanism
consistently across the view (e.g. a `showView()` that sets `style.display` on each panel).

## 3. Know the box model in force before you size anything

Grep for a global reset first: `* { box-sizing: border-box }` changes what `width` means. Under
`border-box`, `width: 44px` **is** the outer box (padding + border included) — the right way to hit an
exact rendered size. Under the default `content-box`, that same `width` renders `44 + padding + border`
px. Don't add a local `box-sizing: border-box` when a global reset already sets it — it's a no-op that
misleads the next reader into thinking the element is a content-box exception.

## 4. Equal sizes must share a unit and a value

If two controls must render the same size, give them the **same unit and number**, not two that
"happen to match at the default font-size." `2.75rem` equals `44px` only while the root is 16px;
`44px` equals `44px` always. When several controls should read as one family, size them from one
declaration or one custom property, and assert equality in a test (`max(sizes) - min(sizes) < 1`).

## 5. Lay out with flex/grid + `gap`; let content wrap, not overflow

- Space siblings with a flex/grid container and `gap`, not per-element margins that collapse or double.
- A row of items that may not fit gets `flex-wrap: wrap` so it reflows to a second line instead of
  overflowing or forcing a page scrollbar. Right-/left-/center-align the wrapped remainder deliberately
  (`justify-content`).
- A flex item won't shrink below its content unless you set `min-width: 0` (the classic "flex child
  overflows its parent" cause).
- Wide, irreducible content — tables, code, diagrams, a long readout — goes in its own
  `overflow-x: auto` container so **the page body never scrolls sideways**.
- A shared row of a fixed-width label + a growing control: give the control `flex: 1` and, if it also
  wraps, remember the label eats width the wrapped items then can't use — measure whether it still fits.

## 6. Fluid/responsive: bound by the viewport, center the shell

- `clamp(min, preferred, max)` for a size that should scale but not run away; drive the "preferred"
  term from viewport units (`dvh`/`dvw` — `dvh` accounts for mobile URL bars).
- To keep a square element from overflowing height, bound it by the viewport height, e.g.
  `--stage: clamp(24rem, calc(100dvh - 19rem), 80rem)`.
- Center the shell with `margin-inline: auto` + a `max-width` on the container — its width is
  independent of its children, so removing/hiding a column doesn't un-center it.
- Fixed side-panel + fluid main is often steadier than two fluids: a panel that grows can drag a photo
  or list to an awkward size. Pick which axis is fixed on purpose.
- Test at real breakpoints (e.g. 1920×1080, 1366×768, a phone width). Accept and *state* a residual
  minor scroll at the smallest size rather than distorting the common case to chase it.

## 7. The cascade is global — audit every consumer before editing a shared rule
*(global stylesheets, and `:global(...)` blocks inside components. Scoped component styles are exempt — see §14.)*

A class rule (`.chips button`) may style several unrelated things (speed rungs **and** a settings
toggle). Editing it to suit one regresses the others — a fixed square silently clips the toggle's text.
Before changing a shared selector: **grep every element that matches it.** Then scope your override to
the specific consumer by ID or descendant (`#nudge-rates button { ... }`), leaving the shared base
intact. Prefer adding a scoped rule over mutating a shared one. Watch specificity: `#id button`
(1 id + 1 type) beats `.class button` (1 class + 1 type), so the scoped override lands.

## 8. No silent clipping

Fixed-size buttons/containers can clip their text with no error. After sizing, assert nothing is cut:
`scrollWidth <= clientWidth + 1` (and the height equivalent). If a label must fit, either the box grows
to it or the text is allowed to wrap/ellipsize on purpose — never leave it clipped-by-accident.

## 9. Design both themes, from tokens

The page renders in the viewer's theme. `prefers-color-scheme` carries the OS preference; a viewer
toggle typically stamps `data-theme="dark|light"` on the root and must override the media query in both
directions. Define the palette as custom properties on `:root`, redefine only the tokens under the dark
media query and under `:root[data-theme=...]`, and style components **through the tokens** — never hard-
code a color inside the dark block. Give the second theme the same care (don't naively invert; keep
contrast and the accent legible on both grounds). A deliberate single-theme look is a choice, not an
omission.

## 10. Touch, pointer, and accessibility are not optional

- Interactive targets ≥ **44×44 px** (finger target); this often drives the "make the buttons bigger"
  requests — honor it by default on anything tapped in the field.
- Every control has a **visible focus** state and an accessible name (`aria-label` on icon-only
  buttons). Respect `prefers-reduced-motion` for anything that animates.
- Drag/press-and-hold controls need `touch-action: none` (and `stopPropagation` on nested nav buttons)
  so the browser doesn't hijack the gesture into a scroll.
- Single-click-inspect vs double-click-act: debounce by id+timestamp (~300–350 ms) and cancel the
  pending single when the double fires; share one handler across the surfaces that offer the action.

## 11. Served-static, no-build front-end discipline
*(no-build surfaces only. A bundler handles most of this for you — see §14.)*

- Files are read from disk per request — a change shows on reload with no bundler. But that means **no
  cache-busting**: set `Cache-Control: must-revalidate` (or equivalent) on the assets, or a stale
  `app.js`/`style.css` sticks after a deploy. Test that the header is present.
- Keep a clean **state → render** split: hold the incoming snapshot (fetch/WebSocket) in one place and
  have render functions read it; don't scatter DOM writes through the socket handler.
- Use **event delegation** for lists that re-render (bind once on the container, match the target),
  not a listener per row that leaks across renders.
- Any state the UI must survive a reload with (selected view, last target, units) persists server-side
  or in `localStorage` — decide which, and restore it before the first render.

## 12. Test the served UI in a real browser, and isolate its writes

- Drive a **real** app subprocess with a real browser (Playwright) so you exercise real HTTP + the
  socket, not a mock DOM. Assert through the rendered DOM and the app's own state endpoint.
- Wait for a **stable signal** (a status class, a selector, a network-idle), never a bare `sleep`, to
  deselect flakiness — but a short settle after an action that has no clean signal is fine.
- Assert size/visibility via `getComputedStyle` when the element may be hidden in the test fixture
  (e.g. a pager that only appears past one page) — it reports the governing rule regardless of layout.
- **Isolate the app's side-effect files**: spawn the test app with its `cwd` in a tmp dir so CWD-
  relative site files (session/observer/calibration state) land there, not in the repo where they
  clobber a real running instance's state. A UI test writing the repo's live state file is a real bug.

## 13. Match the surrounding code
*(on a no-build surface this means: do not introduce a framework. On a component surface it inverts — see §14.)*

No build step usually means no framework and a deliberate hand-authored style. Match it: the same
naming, the same CSS ordering, the same comment density (comments say **why** — "square + right-packed
so it reads as one control family" — not what). Don't introduce a framework, a preprocessor, or a
utility-class system into a plain stylesheet because it's what you'd reach for elsewhere.

## 14. Compiled component frontends (React today; Svelte if adopted)

A compiler changes which of the rules above are load-bearing. What **survives unchanged**: §1 (measure
the rendered DOM — it matters *more*, because the source is not the output), §3, §4, §5, §6, §8, §9, §10,
and §12's "drive a real browser, wait for a stable signal, never `sleep`".

What changes:

- **§7 (global cascade)** — falsified *inside* scoped component styles (Svelte hashes each component's
  `<style>`; CSS Modules do the same), so the grep-every-consumer step is unnecessary there. It is fully
  **re-armed** for any shared global stylesheet and for `:global(...)` escapes. `site/src/index.css` is
  1010 lines of global CSS: §7 applies to it verbatim.
- **§2 (`[hidden]`)** — mostly moot: idiomatic components remove the node (`{#if}` / conditional render)
  rather than hiding it. The trap only returns if you combine the `hidden` attribute with an author
  `display` rule in a global sheet.
- **§11 (no-build discipline)** — drop it. Vite fingerprints assets, so the cache-busting rule is handled;
  state→render is the framework's job; the framework owns event delegation.
- **§13 (don't introduce a framework)** — **inverts.** On a component surface, match the component idioms;
  don't hand-roll vanilla-DOM manipulation or bolt global CSS onto a component.

### Reactive effects and subscriptions — the recurring bug

An effect that *writes* state it also *depends on* re-runs forever, or tears down and rebuilds a
subscription on every update. This is the one framework bug that actually costs money here.

- **Derive, don't mirror.** A value computed from other state is `useMemo`/`$derived` — never state written
  inside an effect. Writing `setTotal(a + b)` in an effect (or `$effect(() => { total = a + b })`) adds a
  render pass and reads stale for one frame.
- **Every subscription, interval, socket and fetch gets a teardown**, and the effect must depend on the
  *narrowest* thing that should retrigger it. In `site/`, the correct shape is `MessageArea`'s cleanup
  (cancel flag + `AbortController` + `clearInterval` + `unsubscribe`). The costly shape is an effect that
  lists a whole object in its deps and so re-subscribes on every message.
- **Reset a subtree on identity change** by keying it (`key={id}` / `{#key id}`). Switching channel, game,
  or route otherwise reuses the instance with stale state — old scroll, old form, old subscription.
- **Guard browser-only APIs** (`localStorage`, `window`, `WebSocket`) if SSR is ever used; module-top-level
  code runs on the server. Even in jsdom this bites: `site/src/test/setup.ts` must polyfill `localStorage`
  because jsdom 28 changed it to a Proxy without the standard methods.

### Testing components (`site/`: Vitest 4 + Testing Library + Playwright)

Query the way a user (and a screen reader) finds things: **`getByRole` with the accessible name** first,
then `getByLabelText`. `site/` currently uses `getByText` 308 times against `getByRole` 31 — that ratio is
drift, not a target. `getByTestId` is the last resort; it asserts nothing about accessibility. A component
that can only be found by test id usually has no accessible name — that is the bug, fix that.

### Svelte — not yet used here

**There is no Svelte anywhere in this org's repos today.** These rules are forward-looking; when the first
Svelte component lands, verify them against it rather than trusting this list.

- Runes: `$state` for owned state, `$derived`/`$derived.by` for computed values, `$effect` **only** for
  side effects that must run after paint. `$effect` never runs during SSR. Pre-paint work is `$effect.pre`.
- `$effect` tracks the state it *reads*, automatically. That makes an over-broad read the exact equivalent
  of an over-broad dependency array: read narrowly.
- The `$store` prefix auto-subscribes **only inside a component**. A `store.subscribe(...)` in a plain
  module, class, or util leaks unless you call the returned unsubscriber.
- Prefer one-way props (`{value}` + a callback) and reach for `bind:` only for genuine two-way form state;
  overusing it makes "who changed this?" untraceable.
- Scoped `<style>` means §7 does not apply to it — but a `:global(...)` block opts you back into the global
  cascade, with all of §7's consequences.
- After a state change, `await tick()` before measuring the DOM (§1), or you measure the previous frame.
