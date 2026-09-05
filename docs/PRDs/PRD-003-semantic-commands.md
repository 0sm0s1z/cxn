# PRD-003 — Semantic Command System

Status: Draft — core logic in `src/constellation/commands.zig`, thin `cxn-status` wiring landed, full dispatch wiring pending. Sequence: 3. Required before Vim, mouse, palette.

## Goal

One semantic command under every input method. Vim, mouse, slash command, and palette never duplicate behavior.

## Background

Without this layer, Vim keys, clicks, and commands each grow their own handlers and the fork accumulates hacks. With it, later interaction work is incremental.

## Scope

In:

- Command registry: names, args, context (focused block/surface/mode), availability.
- Core verbs for MVP: `block.next/prev`, `block.edit`, `block.copy`, `block.fork`, `provider.select`, `model.select`, `surface.activate`, `surface.raw`, viewport and fold ops.
- Bindings from keymap, mouse hit actions, slash commands, and palette into the same dispatch.
- Failure and context errors (e.g. no focused block) as structured results.

Out: editor implementation (PRD-004), block storage (PRD-005), rendering (PRD-006). No new user-visible features beyond a test palette/slash wiring.

## Requirements

1. Command IDs are stable strings, e.g. `conversation.block.edit`, `conversation.block.copy`, `conversation.block.fork`, `provider.select`, `model.select`, `surface.activate`, `surface.raw`.
2. Dispatch signature carries explicit context (mode, focused ids) and returns a typed result. No global singletons beyond what FX already uses.
3. Keymap, mouse, slash, and palette are thin callers. Adding a new trigger never adds behavior.
4. Every command documents availability (which modes, what focus) and is testable headlessly.
5. List/revoke-safe: commands that mutate sessions go through existing permission/session seams.

## Architecture

- Upstream touches: `downstream-hook` only — one dispatch registration point in CLI/slash wiring; no rewrites of existing command parsing.
- Downstream location: `src/constellation/interaction/` (registry, dispatch, builtin verbs).
- Follow `src/core/slash_commands/command_specs.zig` + `cli_surface.zig` conventions for any slash surface.

## Acceptance

- In the built binary, the same `conversation.block.copy` runs from a key binding, a slash command, and a click stub, producing identical results.
- Unavailable command (no focus) reports a clean structured error, no crash, stderr clean.

## Test plan

- Focused Zig tests: registry lookup, dispatch with/without context, arg validation.
- E2E owner: extend CLI noninteractive coverage for slash/command parity. No new hot-path file; reuse existing classification unless a new root file is added (then classify it).

## Docs

- `docs/ARCHITECTURE.md` command table + per-command availability. `--help` stays accurate.

## Open questions

- `:` command line vs palette first? Proposal: palette reuses slash machinery; `:` line arrives with Vim v1 command mode.
