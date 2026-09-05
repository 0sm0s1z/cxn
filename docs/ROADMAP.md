# Roadmap

Build order matters. Early items establish primitives everything after them needs.

## Sequence

1. Fork plumbing and upstream discipline.
2. Constellation Router provider (OpenAI-compatible transport + Router profile).
3. Semantic command system.
4. Real editor core (buffer, cursor, selection, undo, motions, operators, text objects).
5. Vim v1 (Insert/Normal/Visual, keymap file, `default`/`vim`/`minimal`).
6. Transcript object navigation (block focus, Transcript mode).
7. Editable historical prompts (branch/rewind, never silent mutation).
8. Mouse interaction model (hit regions, focus, scroll, clickable footer).
9. Surface abstraction (source vs presentation lifecycles).
10. Kitty graphics v1 (probe, placements, resize invalidation, fallback).
11. Rich outputs (images first, then Mermaid/SVG/charts).
12. Raw/rendered toggle everywhere.
13. Herdr qualification (Kitty/Ghostty direct + nested Herdr matrix).
14. Browser v1 (preview block + temporary takeover via helper).
15. Browser v2 (embedded surface via helper IPC).
16. Broader parity (hooks, workflows, approvals, tools) only after the interaction architecture can absorb it.

PRD mapping is in `PRDs/README.md`.

## MVP (proves the thesis)

```text
FX upstream
+ Constellation Router (auto + discovered catalog + metadata)
+ Vim composer
+ Transcript normal mode
+ Editable/forkable prompts
+ Mouse-selectable transcript blocks
```

MVP acceptance is end-to-end in the built binary: connect Router, pick a model, edit in Normal mode, navigate blocks with `j/k`, fork from an edited prompt, click a block to focus. No Kitty or browser required.

## v1.5 (establishes graphics architecture)

```text
+ generic Surface abstraction
+ Kitty image output
+ rendered/source toggling
```

Acceptance: image block shows Kitty raster where capable and clean ANSI/text fallback elsewhere; `i` toggles to source; resize destroys and re-places graphics deterministically.

## Gates

- Focused tests + `zig build` + built-binary (`./zig-out/bin/fx`) exercise per PRD.
- Full CI on the exact commit across all four native runners before marking ready.
- Herdr + direct-terminal matrix becomes an E2E acceptance criterion from the Surface stage onward.
- Binary-size and startup-latency budgets are observed; browser work must not regress the ~7.8 MiB native story via linked engines.
