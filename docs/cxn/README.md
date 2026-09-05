# cxn fork discipline

cxn is a downstream distribution of [vercel-labs/fx](https://github.com/vercel-labs/fx).
Upstream owns the agent/runtime. cxn owns the interaction layer.

## Branch topology

```text
vercel-labs/fx (upstream)
      │
      ▼
origin/main            ← exact upstream mirror. No direct commits, ever.
      │
      │ merge (PR, human-gated)
      ▼
origin/constellation   ← shipping downstream product
      │
      ├── feat/vim-engine
      ├── feat/router-provider
      ├── feat/editable-transcript
      ├── feat/kitty-surfaces
      └── ...
```

- `main` tracks upstream exactly. The `Upstream sync` workflow
  (`.github/workflows/upstream-sync.yml`) fast-forwards it and opens/updates
  a `main -> constellation` PR. It never pushes to `constellation`.
- Merge `main -> constellation`. Never rebase the distribution branch.
- Rebase short-lived `feat/*` branches onto `constellation` as needed.
- Every upstream-owned file touched by downstream must be either an
  upstreamable change or a thin integration hook. See patch surface below.

## Patch surface

> downstream patch surface = number of upstream-owned files modified
> relative to the merge-base with `main`.

- Warn budget: 12 files. Fail budget: 50 files.
- Enforced by the `Patch surface` workflow on PRs and pushes to
  `constellation`, via `scripts/patch-surface.sh`.
- Downstream-owned paths (excluded from the count):
  `src/constellation/`, `docs/` (upstream has no `docs/` dir, so all of it
  is downstream by definition), the two cxn workflows, and the script
  itself. Register new downstream areas in `OWNED_PREFIXES`.
- If the count grows, the fix is architecture (move code downstream behind a
  hook), not budget inflation.

## Downstream layout

New code lives in `src/constellation/` (see `src/constellation/README.md`
for the planned sub-areas). Registration points into upstream code stay
minimal and explicit.

## Build order

1. Fork plumbing and upstream discipline (this doc).
2. Constellation Router provider (OpenAI-compatible transport + router profile).
3. Semantic command system (input-method-independent commands).
4. Real editor core (buffer/cursor/selection/undo/mode/operator/motion/text-object).
5. Vim v1 (insert/normal/visual, core motions/operators/text objects, keymap file).
6. Transcript object navigation (block focus, Transcript mode).
7. Editable historical prompts (edit forks/rewinds, never mutates history).
8. Mouse interaction model (frame-scoped hit regions -> semantic actions).
9. Surface abstraction (source vs presentation, text/rich/interactive lifecycles).
10. Kitty graphics v1 (capability probe, placement manager, resize invalidation).
11. Rich outputs (images, then mermaid/SVG/charts; prose Markdown stays cells).
12. Raw/rendered toggle everywhere.
13. Herdr qualification (direct + nested terminal matrix).
14. Browser v1 (preview block + helper takeover), then v2 (embedded surface IPC).
15. Claude Code / Grok Build parity (hooks, workflows, approvals) last.

MVP proving the thesis: upstream FX + router + Vim composer + transcript
normal mode + editable/forkable prompts + clickable blocks.

## Verification

```bash
zig fmt --check src/
zig build
./zig-out/bin/fx --version
./scripts/patch-surface.sh
```
