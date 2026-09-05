# PRD-006 — Mouse + Surfaces + Kitty v1 + Rich Outputs + Toggle

Status: Draft. Sequence: 8-12. Depends on PRD-005. Mouse-selectable slice ships with MVP; remainder is v1.5.

## Goal

A coherent surface stack: hit-tested mouse interaction, source/presentation separation, and Kitty graphics where pixels help — without turning text into bitmaps.

## Scope

In:

- Hit-region mouse model, clickable footer and code-fence actions.
- `Surface` protocol + lifecycles (`render/focus/blur/edit/activate/copy/resize/mouse/key`).
- Capability probe (`kitty-native`, `kitty-placeholder`, `sixel`, `symbols`, `text`; v1 needs `kitty` + `text`).
- Kitty placement manager with deterministic resize (`resize -> destroy -> recalc -> re-place`).
- Rich outputs: images first, then Mermaid/SVG/charts. Ordinary Markdown stays terminal-native.
- Universal raw/rendered toggle (`i` or `surface.raw`).

Out: browser surfaces (PRD-007), multiplexer behavior.

## Requirements

1. Every object emits `HitRegion { rect, object_id, actions, cursor_style }`. Flow is `mouse event -> coordinate -> hit map -> semantic action`. No raw mouse handling in renderers.
2. Interactions: click focuses, double-click selects, drag selects text, right-click opens context, wheel scrolls, modifier-click runs alternate. Code fences expose `Copy/Apply/Run/Open` on focus. Footer `CONSTELLATION · auto · 61% · NORMAL` segments open provider/model/context/mode views.
3. Surfaces:
   ```text
   MarkdownSurface, ImageSurface, DiagramSurface, BrowserSurface, DiffSurface, TerminalSurface?
   ```
   Each block offers `presentations[]` (e.g. Mermaid `source / unicode-diagram / kitty-raster`; image `metadata / thumbnail / kitty-image`; browser `URL / screenshot / interactive-surface`). Renderer picks strongest available.
4. No `ESC_G` sprinkled through Markdown. Layout owns geometry; graphics backend owns placement. Ghostty/Kitty/WezTerm support the protocol; nested multiplexers (Herdr) need cheap deterministic redraw.
5. Resize invalidates placements; never preserves fragile raster state. Font-metric changes follow the same path.
6. Fallback is graceful ANSI/text everywhere Kitty is absent.

## Architecture

- Downstream: `src/constellation/interaction/` (hit map, mouse routing), `src/constellation/surfaces/` (protocol, block presentations), `src/constellation/graphics/` (probe, placements, invalidation).
- Upstream touches: `downstream-hook` — hit-region carrier in render engine, placement hook in terminal output, capability probe at startup.

## Acceptance (built binary)

- Click/double-click/drag/wheel on blocks, code actions, and footer behave per spec on direct Kitty/Ghostty and degrade cleanly on plain terminals.
- Image block renders Kitty raster where capable, text fallback elsewhere. `i` toggles source. Resize re-places without stale graphics.
- Mermaid block offers source/unicode/raster with reversible switching.

## Test plan

- Focused Zig tests: hit-map routing, presentation selection, resize invalidation, fallback.
- E2E: `tests/e2e/mouse-surfaces.test.ts` + `tests/e2e/kitty-graphics.test.ts` (tape + tmux resize matrix per `tui-resize.test.ts`). Classifications: mouse/surfaces `training`; graphics fallback/rare paths `verification-only`. Corpus entries required.
- Record tapes with `FX_DEBUG_RECORD=1`, replay with `fx replay --frames/--json/--golden`.

## Docs

- Surface catalog, presentation table, mouse action table, capability/fallback matrix.

## Open questions

- Sixel/symbols beyond `kitty`+`text` for v1?
- Chart/SVG raster pipeline location (in-binary vs helper)?
