# src/constellation — downstream interaction layer

All cxn-owned code lives here. Upstream `src/` files are touched only for
thin registration points (provider select arms, command registrations, hook
calls). See `docs/cxn/README.md` for the fork discipline and build order.

Current stage: flat pure-logic files (`provider.zig` -> `provider/`,
`editor.zig` -> `editor/`, `commands.zig` -> `interaction/`,
`transcript.zig` -> `interaction/` + `surfaces/`, `surfaces.zig` ->
`interaction/` + `surfaces/` + `graphics/`) plus `integration.zig`, the
thin downstream controller composed by `fx cxn-status [--json]` in
`src/main.zig`. Split into the sub-areas below
when upstream wiring lands; no upstream-owned file may import these paths
except through the thin registration points each PRD defines.

Planned sub-areas (created as features land, per `docs/ARCHITECTURE.md`):
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

Rules:

- No product state in render code; render builds frame-scoped hit maps only.
- No Kitty escape sequences outside `graphics/`.
- No provider wire protocol outside `provider/` (transport stays generic).
- Every file here is downstream-owned and excluded from the patch-surface count.
