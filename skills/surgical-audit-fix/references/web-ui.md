# Web UI/UX & functionality path

Scope first: audit only the surfaces rendered by files in scope. Ask the map/closure which components, styles and routes render the surface; inspect those. Judge rendered output (screenshot or browser automation), not just CSS numbers.

Contents: 1 Design system, 2 Browser-native UI, 3 Spacing & alignment, 4 Responsive & portrait, 5 Interaction, 6 Touch targets, 7 Accessibility, 8 Typography, 9 Motion & performance, 10 Functional correctness, 11 Layers & transient UI, 12 Test matrix, 13 Severity.

## 1. Design system (extract before judging)
Pull tokens from the code: colors, surfaces, borders, radii, shadows, type, icon size, spacing scale, control heights, z-index, motion timings, focus/selected/disabled/loading treatments. Decide if it is internally coherent. Preserve product identity; enforce consistency, don't normalise toward a generic system. If a token or shared primitive is wrong, fix it there, then check all consumers.

## 2. Browser-native UI
Look for accidental default controls (buttons, checkbox, radio, select, range, file input, search decorations, validation bubbles, dialogs/tooltips, scrollbars, focus rings, text selection, tap highlight). Style them to the product, but keep semantics: use real HTML controls where possible, never lose keyboard, focus, labels or ARIA when going custom. On touch consider `-webkit-tap-highlight-color: transparent`. Branded selection color must stay readable. Don't fight useful native behaviour that is intentionally kept.

## 3. Spacing and alignment
Check margins, padding, sibling gaps, icon-label gaps, section rhythm, fixed-bar clearance and safe-area insets. Spot both cramped and bloated UI. Check optical alignment: icons 1-4px off, mixed control heights in a row, inconsistent SVG viewBox padding, baselines. Fix the shared primitive when several instances share the defect.

## 4. Responsive and portrait
Test wide/normal/small desktop, landscape and portrait tablet, large/narrow mobile, short and tall viewports, portrait and landscape. Use dynamic viewport units (`svh`, `lvh`, `dvh`) where appropriate. Look for horizontal overflow, clipped content, scroll traps, fixed bars covering content, dialogs/drawers taller than the viewport, keyboard and safe-area overlap, awkward one-off breakpoints, hidden-but-focusable controls. Portrait is not a narrow desktop: check reachability, fixed elements stealing height, and that key actions stay visible.

## 5. Interaction
Prefer the shortest understandable path. **Tap-to-enter:** when an item is the natural entry point, tapping it should open it, not select it and then require an Open button, unless multi-select or a separate action is genuinely needed. Check every state: default, hover, focus, keyboard-focus, pressed, selected, checked, disabled, loading, success, error, drag-over. Never rely on hover for essential info on touch.

## 6. Touch targets and gestures
About 44x44pt interactive hit area as a reference, measured on the real hit box, not the icon. Expand with transparent/internal hit areas instead of inflating visuals. Watch gesture conflicts: scrolling, edge swipe, drawers, nested scroll, pinch/zoom, carousels.

## 7. Accessibility
Contrast (4.5:1 text, 3:1 large text and non-text), visible focus, keyboard order and traps, accessible names, form label/error associations, status announcements, reduced motion, zoom/reflow, expanded/selected/disabled semantics, hidden content. Never remove focus indication without a visible equivalent.

## 8. Typography
Font loading and fallback, weights, hierarchy, line length (~45-90 chars body), line height (~1.2-1.45), truncation/wrapping, numeric alignment, long words, localisation expansion.

## 9. Motion and performance
Motion should explain a state change. Reference: ~100ms instant, 200-300ms snappy, 300-500ms deliberate, ~1s interrupts thought. Prefer transform/opacity over layout properties; support reduced motion; check interruption and layout shift. Frame budgets: 8.3ms at 120Hz, 16.7ms at 60Hz. Look for long tasks, layout thrashing, needless re-renders, duplicate listeners, heavy scroll handlers, image sizing and lazy loading. Measure or point to structural cost; don't optimise blindly.

## 10. Functional correctness
For features in scope: create/read/update/delete, search (typing, clear, empty, no results, debounce, stale results), filter, sort, selection, navigation and back, persistence and refresh, undo/redo, cancel/retry, duplicate prevention. Hunt for stale state, races, double-submit, lost updates, URL/state mismatch, modal state leaks, duplicate handlers, derived-state drift. UI that looks right but shows wrong state is a functional defect. Every data surface needs coherent loading, empty, no-results, error, retry, success and offline states.

## 11. Layers and transient UI
Map z-index to a documented scale, not random numbers; check menus behind dialogs, click-through overlays, invisible blockers. Toasts: placement, stacking, dismissal, safe-area and keyboard collisions, severity semantics; avoid a second contradictory notification system and browser `alert/prompt` where the product has a themed one. If an installed navigation skill (e.g. recursive-navigation, "invisible glass openers") owns sidebars/toolbars/transitions, follow it rather than building a competing mechanism.

## 12. Test matrix (adapt, don't exhaust)
Width x height x orientation x device class x input (mouse/touch/keyboard) x state (loading/empty/populated/error) x content length x reduced motion x zoom x navigation (entry/back/deep) x persistence. Cover the cells the change can affect; list skipped cells.

## 13. Severity
P0 core unusable or data endangered. P1 major workflow broken or systemic a11y/responsive failure. P2 meaningful usability, consistency, performance or maintainability problem. P3 polish. P4 observation. Don't inflate severity because a defect is visible.

Issue table columns: ID, severity, area, viewport/device, reproduction, expected, actual, root cause, fix, affected files, regression risk, verification.
