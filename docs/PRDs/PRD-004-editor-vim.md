# PRD-004 — Editor Core + Vim v1 + Keymap

Status: Draft — core logic in `src/constellation/editor.zig`, thin `cxn-status` wiring landed, composer seam pending. Sequence: 4-5. Depends on PRD-003.

## Goal

A real modal editing engine under the composer, not a pile of keybindings. Vim behavior is composition of operators, motions, and text objects.

## Background

FX already has escape parsing, input runtime, shortcuts, action decoding, and visual layout. Constellation puts a proper editor underneath instead of branching that key handler.

## Scope

In:

- Reusable `Editor`: Buffer, Cursor, Selection, Undo tree, Mode, Operator, Motion, TextObject, Command.
- Vim v1: `INSERT`, `NORMAL`, `VISUAL`; core motions/operators/text-objects; command line basics.
- Keymap file (`~/.fx/keymap.toml` or equivalent) binding sequences to semantic commands. Profiles: `default`, `vim`, `minimal`.
- Application modes: `INSERT`, `NORMAL`, `VISUAL`, `TRANSCRIPT`, `COMMAND`, `SURFACE` with unambiguous transitions.

Out: transcript-block navigation details (PRD-005), mouse (PRD-006), surfaces/graphics (PRD-006).

## Requirements

1. Composition examples must work as composition, not special cases:
   ```text
   ci", di(, ci{, yiw, dap, gg, G, w, b, e, f<char>, t<char>, %, 0, $, ^
   ```
   `ci"` = change ∘ inside ∘ quote-object.
2. Mappings become data, e.g. `jj → Escape`, `<leader>m → model picker`, `<leader>r → router info`, `<leader>e → edit block`.
3. Mode transitions:
   - `Esc`: `INSERT -> NORMAL`.
   - `Esc Esc` or `Ctrl+Esc`: `NORMAL -> TRANSCRIPT`.
   - `i` in `TRANSCRIPT` with composer focus returns to `INSERT`; `SURFACE` owns keys while focused, `Esc` releases.
4. Undo tree supports undo/redo acrossComposer edits. State the ownership and allocator discipline per repo Zig rules (explicit allocators, `defer` cleanup, no globals).
5. Keymap binds sequences to semantic commands:
   ```text
   normal."g g" = "cursor.document_start"
   transcript."j" = "block.next"
   transcript."i" = "block.edit"
   ```
   Unbound keys fall back to profile defaults. Bad config reports file + line, never crashes.

## Interaction spec

- Composer shows mode in footer (`INSERT`/`NORMAL`/`VISUAL`). Mode is clickable (explains keymap; full picker later).
- `VISUAL` selections support `y/d/c` + `Esc` to cancel.
- Remap reloads without restart; errors surface inline.

## Architecture

- Upstream touches: `downstream-hook` — replace composer input handling with editor-backed input via one seam; keep escape parser and layout intact.
- Downstream location: `src/constellation/editor/` (buffer, motion, operator, textobject, undo) + `src/constellation/config/` (keymap load, profiles) + `src/constellation/interaction/` (mode machine).
- Do not grow `src/main.zig`. Keep `pub` surface minimal.

## Acceptance (built binary)

- Open composer, enter text, `Esc`, `w/b/e`, `ci"/yiw/dap`, `u`, `jj` mapping, `:w`-style no-op or explicit unsupported message (no silent behavior).
- Switch profiles `default/vim/minimal` and confirm changed bindings.
- Corrupt keymap line: clean error with path, binary keeps running.

## Test plan

- Focused Zig tests in the editor files (`test "…"`) for buffer, motions, operators, undo. Run narrowest tests while developing; `zig build test` stays green.
- Shared terminal engine / resize tests where relevant (`src/ui/resize_tests.zig` pattern).
- E2E owner: new `tests/e2e/vim-composer.test.ts` (tmux-driven). Classification: `training` (common, performance-sensitive product behavior). Add corpus entry.

## Docs

- Keymap reference + default bindings table. `--help` and README composer section.

## Open questions

- Exact keymap path/name (`~/.fx/keymap.toml` proposed)?
- `COMMAND` scope for v1 (picker only vs full `:` ex commands)?
