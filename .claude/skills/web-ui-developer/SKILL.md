---
name: web-ui-developer
description: Front-end discipline for hand-written, no-build web UIs (served-static HTML/CSS/vanilla-JS, verified with a real browser). Read BEFORE writing or reviewing any CSS/layout/DOM change — sizing, flex/grid layout, show/hide toggling, responsive/fluid layout, theme, touch targets, or a served-static frontend driven by fetch/WebSocket. Encodes the measure-the-rendered-DOM-never-the-source discipline and the cascade/`[hidden]`/box-sizing/shared-class traps that bite every time.
---

# Web UI development discipline

Working rules for hand-authored web front-ends with **no build step** — HTML/CSS/vanilla-JS served
as static files, styled by a plain stylesheet, driven by `fetch`/WebSocket, and verified in a real
browser (Playwright/Chromium). Every rule below was paid for on a real UI; skip one and you ship a
layout bug you "verified" by reading the source.

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

No build step usually means no framework and a deliberate hand-authored style. Match it: the same
naming, the same CSS ordering, the same comment density (comments say **why** — "square + right-packed
so it reads as one control family" — not what). Don't introduce a framework, a preprocessor, or a
utility-class system into a plain stylesheet because it's what you'd reach for elsewhere.
