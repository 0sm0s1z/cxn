# PRDs

All work ships behind this sequence. Status is updated as branches land in `constellation`.

| PRD | Sequence | Title | Status |
|---|---|---|---|
| PRD-001 | 1 | Fork plumbing and upstream discipline | Draft |
| PRD-002 | 2 | Constellation Router provider | Draft |
| PRD-003 | 3 | Semantic command system | Draft |
| PRD-004 | 4-5 | Editor core + Vim v1 + keymap | Draft |
| PRD-005 | 6-7 | Transcript navigation + editable forkable history | Draft |
| PRD-006 | 8-12 | Mouse + surfaces + Kitty v1 + rich outputs + toggle | Draft |
| PRD-007 | 13-16 | Herdr qualification + browser v1/v2 + parity gate | Draft |

## MVP set

PRD-001 through PRD-005 plus the mouse-selectable slice of PRD-006. That combination is the first version that proves the thesis.

## PRD conventions

Each PRD has: Goal, Background, Scope in/out, Requirements, Interaction spec where relevant, Architecture (upstream touches labeled `upstreamable` or `downstream-hook`, downstream location under `src/constellation/`), Acceptance criteria (built-binary proof), Test plan (focused tests, E2E owner + PGSO classification), Docs, Rollout, Open questions.
