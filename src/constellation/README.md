# src/constellation — downstream interaction layer

All cxn-owned code lives here. Upstream `src/` files are touched only for
thin registration points (provider select arms, command registrations, hook
calls). See `docs/cxn/README.md` for the fork discipline and build order.

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
