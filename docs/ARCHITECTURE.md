# Architecture

## Upstream/downstream rule

Every change touching upstream-owned code is classified as either:

- **Upstreamable**: could go to `vercel-labs/fx` as-is (fix, generic improvement, protocol compatibility).
- **Downstream hook**: thin registration point that lets `src/constellation/` plug in (provider profile, command registration, surface host, hit-region carrier).

If a change is neither, it lives in the wrong place.

FX already separates `input`, `render_engine`, `terminal`, `transcript` in UI and `agent`, `auth`, `input`, `output`, `session`, `terminal`, `mods` in core. Constellation builds on those seams instead of rewriting them.

## Downstream layout

```text
src/constellation/
  provider/      Router profile, catalog discovery, routing metadata display
  editor/        Buffer, cursor, selection, undo, motions, operators, text objects
  interaction/   Semantic commands, keymap, modes, transcript navigation, mouse hit map
  surfaces/      Surface protocol, block types, text/rich/interactive lifecycles
  graphics/      Capability probe, Kitty placement manager, resize invalidation
  browser/       BrowserBlock, preview, helper-process client (v2)
  config/        Keymap file, profiles (default, vim, minimal)
```

Most implementation lives here. Registration points into FX stay thin.

Investigate `core/mods` and the native mod API as a future extension seam, but do not depend on its stability yet.

## The three core abstractions

These come before Vim keys, mouse events, or Kitty sequences. If they are good, everything else is incremental.

### 1. Semantic commands

Application commands independent of physical input:

```text
conversation.block.edit
conversation.block.copy
conversation.block.fork
provider.select
model.select
surface.activate
surface.raw
```

Invoked by Vim binding, mouse, slash command, or palette.

### 2. Editable conversation blocks

```text
Block
  id
  type
  source
  presentation
  interaction
  provenance
```

Types: `UserMessage`, `AssistantMessage`, `ReasoningSummary`, `ToolCall`, `ToolResult`, `Code`, `Markdown`, `Image`, `Diagram`, `Browser`, `SystemNotice`.

Editing historical source branches the session (see `PRD-005`). It never silently mutates executed history.

### 3. Renderable/focusable surfaces

```text
Surface
  id
  content_type
  preferred_size
  presentations[]
  focusable
  editable
  input_handler
```

Concrete: `MarkdownSurface`, `ImageSurface`, `DiagramSurface`, `BrowserSurface`, `DiffSurface`, possibly `TerminalSurface`.

Operations: `render`, `focus`, `blur`, `edit`, `activate`, `copy`, `resize`, `mouse`, `key`. Not every surface implements everything.

## Rendering model

```text
RenderNode
  ├── CellSurface      ANSI / Unicode, selectable, searchable
  └── GraphicSurface   Kitty placement, pixel-driven
```

Layout decides `x, y, width, height`. The graphics backend expresses that region. Semantic content is preserved; presentation derives from terminal width. Resize can reversibly switch between rendered output and source.

Ordinary Markdown stays in `CellSurface`. Kitty is for images, Mermaid, charts, SVG, HTML artifacts, browser, PDF previews, mockups.

## Input model

Application modes:

```text
INSERT      composer text entry
NORMAL      composer modal editing
VISUAL      composer selection
TRANSCRIPT  keys operate on conversation blocks
COMMAND     palette / `:` line
SURFACE     focused interactive object owns input
```

Example flow: `Esc` moves `INSERT -> NORMAL`. `Esc Esc` or `Ctrl+Esc` moves `NORMAL -> TRANSCRIPT`. In `TRANSCRIPT`, `j/k` move by block, `/` searches, `Enter` activates, `i` edits source, `y` copies, `f` forks, `za` folds, `zt/zz/zb` place viewport.

Keymap binds sequences to semantic commands, e.g. `transcript."j" = "block.next"`. Ship `default`, `vim`, `minimal` profiles from `~/.fx/keymap.toml` or equivalent.

## Mouse model

Every rendered object emits hit regions:

```text
HitRegion
  rect
  object_id
  actions
  cursor_style
```

Event flow: `terminal mouse event -> coordinate -> hit map -> semantic action`. Renderers never handle raw mouse input directly. Click focuses, double-click selects, drag selects text, right-click opens context, wheel scrolls, modifier-click runs alternates.

## Browser staging

- v1: `BrowserBlock` with URL, metadata, screenshot/preview, open action. Enter switches the terminal to an interactive browser surface; Escape returns.
- v2: FX owns placement and input routing; a separate helper owns Chromium and exchanges framebuffer + geometry + input events. Never link Chromium into the FX binary.

## Embeddability

Keep the interaction layer separable so the same core serves native CLI, Herdr pane, web terminal, Constellation IDE pane, and ACP client via existing `createFxAgent()` / `createFxTerminal()` seams.
