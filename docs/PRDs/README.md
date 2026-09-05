# PRDs

All work ships behind this sequence. Status is updated as branches land in `constellation`.

| PRD | Sequence | Title | Status |
|---|---|---|---|
| PRD-001 | 1 | Fork plumbing and upstream discipline | Landed (`8e6563ff`: sync + patch-surface workflows, PR template, script) |
| PRD-002 | 2 | Constellation Router provider | Draft (core in `provider.zig`) |
| PRD-003 | 3 | Semantic command system | Draft (core in `commands.zig`) |
| PRD-004 | 4-5 | Editor core + Vim v1 + keymap | Draft (core in `editor.zig`) |
| PRD-005 | 6-7 | Transcript navigation + editable forkable history | Draft (core in `transcript.zig`) |
| PRD-006 | 8-12 | Mouse + surfaces + Kitty v1 + rich outputs + toggle | Draft (core in `surfaces.zig`) |
| PRD-007 | 13-16 | Herdr qualification + browser v1/v2 + parity gate | Draft |

## MVP set

PRD-001 through PRD-005 plus the mouse-selectable slice of PRD-006. That combination is the first version that proves the thesis.

## Implementation state

Pure-logic cores for PRD-002 through PRD-006 live as flat files in `src/constellation/` (`provider`, `commands`, `editor`, `transcript`, `surfaces`) plus the `integration` controller that composes them, with 32 focused tests via `zig test src/constellation/root.zig`. Thin product wiring has landed as a local-only `fx cxn-status [--json]` early dispatch in `src/main.zig`: it resolves the Router endpoint from the environment, builds a demo catalog, and exercises the shipped editor, transcript, fork, hit-map, and presentation paths with no network and no provider registration. Full upstream wiring (provider registration, slash-command dispatch, composer seam, render hit-map) still lands per PRD behind `downstream-hook` registration points. Upstream patch surface so far is exactly one file (`src/main.zig`).

## PRD conventions

Each PRD has: Goal, Background, Scope in/out, Requirements, Interaction spec where relevant, Architecture (upstream touches labeled `upstreamable` or `downstream-hook`, downstream location under `src/constellation/`), Acceptance criteria (built-binary proof), Test plan (focused tests, E2E owner + PGSO classification), Docs, Rollout, Open questions.
