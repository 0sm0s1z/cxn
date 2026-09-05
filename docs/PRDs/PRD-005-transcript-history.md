# PRD-005 — Transcript Navigation + Editable Forkable History

Status: Draft. Sequence: 6-7. Depends on PRD-003, PRD-004.

## Goal

Transcript behaves as an editable conversation document. Navigation is Vim-native. Editing history branches instead of mutating provenance.

## Background

FX separates transcript storage/runtime/painter/viewport and builds blocks separately from cell layout. Upstream is also circling session fork/rewind. Constellation generalizes that into blocks + branch-on-edit.

## Scope

In:

- Block model for every displayed thing (`UserMessage`, `AssistantMessage`, `ReasoningSummary`, `ToolCall`, `ToolResult`, `Code`, `Markdown`, `Image`, `Diagram`, `Browser`, `SystemNotice`) with id, type, source, presentation, interaction, provenance.
- `TRANSCRIPT` mode: keyboard operates on blocks, not the composer.
- Edit flow: rendered -> `i` -> editable source -> save -> branch.
- Fork/rewind integration with sessions.

Out: Kitty raster, browser interactivity, mouse hit-map (PRD-006). Mermaid stays source-or-unicode here; raster arrives later.

## Requirements

1. Transcript bindings:
   ```text
   j/k     next / previous block
   gg / G  beginning / end
   /       search
   Enter   inspect / activate block
   i       edit underlying source
   y       copy
   f       fork from block
   za      fold / unfold
   zt/zz/zb viewport placement
   w/b     move among interactable objects
   ```
2. `i` on a user block opens editable source. Saving shows explicit branch confirmation:
   ```text
   Editing historical prompt will branch the session from this point.
   ```
   Save produces `session A -> branch B` with the edited message. Original provenance is preserved.
3. Same toggle applies where meaningful: assistant Markdown (rendered -> raw), Mermaid (diagram -> source), image instruction (image -> metadata/source), tool call (pretty -> structured invocation). Non-executable types still toggle consistently even if edits do not re-execute.
4. Folding, search, and viewport placement work on semantic blocks, not screen lines.
5. Upstream session fork/rewind concepts are reused where they exist; Constellation adds only the branch-on-edit policy + UI.

## Interaction spec

- Focused block has a visible but quiet affordance. Footer stays minimal.
- Branch confirmation names the source block and states that later blocks are not carried over (or states the exact carry policy once sessions confirm it).
- Copy uses the same path as `conversation.block.copy` from PRD-003.

## Architecture

- Upstream touches:
  - `upstreamable`: any generic block-storage or fork fixes.
  - `downstream-hook`: block-focus host in transcript painter/viewport, branch entry in session runtime.
- Downstream location: `src/constellation/interaction/` (transcript mode, navigation) + `src/constellation/surfaces/` (block types; full lifecycle in PRD-006).

## Acceptance (built binary)

- Navigate a multi-block session with `j/k/gg/G`, search with `/`, fold with `za`, reposition with `zz`.
- Edit an old user prompt, confirm branch, verify new branch contains edited message and original session is intact.
- Toggle an assistant Markdown block and a tool-call block to source and back.

## Test plan

- Focused Zig tests: block navigation, branch-on-save policy, fold/search scoping.
- E2E owner: `tests/e2e/editable-transcript.test.ts`. Classification: `training` (core product behavior). Corpus entry required.
- Repro render bugs via `FX_DEBUG_RECORD=1` tapes + `fx replay`, and land shared-engine unit tests (`resize_tests.zig` pattern) before fixing.

## Docs

- Transcript mode cheat-sheet, branch semantics, block-type table.

## Open questions

- Exact branch-carry policy (context window vs full suffix)?
- Which assistant/tool types allow edit-and-rerun vs view-source-only in MVP?
