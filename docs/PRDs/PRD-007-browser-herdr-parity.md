# PRD-007 — Herdr Qualification + Browser v1/v2 + Parity Gate

Status: Draft. Sequence: 13-16. Depends on PRD-006.

## Goal

Prove nested-terminal correctness, ship browser value without embedding Chromium, and only then broaden feature parity.

## Scope

In:

- Herdr qualification matrix (direct Kitty/Ghostty + nested Herdr): resize, font change, scrollback, mouse, image placement.
- Browser v1: `BrowserBlock` (URL, metadata, screenshot/preview, open action) + temporary interactive takeover via external helper. Escape returns to FX.
- Browser v2: helper IPC (framebuffer + geometry + input events), embedded `BrowserSurface` without multiplexer behavior.
- Parity gate: hooks, workflows, commands, approvals, richer tools — absorbed via semantic commands/surfaces, not hacks.
- Reference: `zenbu-labs/terminal-browser` (Chromium offscreen + Kitty pixels + event forwarding) as the architectural pattern, not a linked dependency.

Out: linking Chromium/Electron into FX (explicit non-goal; protects ~7.8 MiB story).

## Requirements

1. Herdr E2E acceptance: resize/font/scrollback/mouse/placement behave identically direct and nested, with cheap deterministic redraw. Herdr's known resize/font stale-graphics caveat is covered by re-place tests.
2. Browser v1: Enter on a URL/Browser block opens takeover; Escape returns; transcript state is preserved.
3. Browser v2: FX owns placement + input routing; helper owns Chromium. IPC carries frames down, geometry + input up. FX never becomes a container for nested graphical apps beyond one focused surface.
4. Parity features land only through PRD-003 commands and PRD-006 surfaces. Any proposal adding a second execution path or hidden shell-only state is rejected.
5. Binary-size observability (`.github/workflows/binary-size.yml`, 7.800 MiB ceiling context) and startup budgets (`benchmarks/startup.sh`, `FX_BENCH=1`) stay green; helper binaries are versioned separately.

## Architecture

- Downstream: `src/constellation/browser/` (block, preview, helper client), `src/constellation/surfaces/` (BrowserSurface focus/blur/resize), `src/constellation/graphics/` (framebuffer placement).
- Upstream touches: `downstream-hook` — surface geometry + input-routing hook. No provider/agent rewrites.
- Helper is a separate process/binary. No Chromium in `build.zig` dependencies.

## Acceptance (built binary + helper)

- Qualification matrix passes direct and under Herdr.
- v1: open URL preview, take over, interact, Escape back with transcript intact.
- v2: embedded browser frame tracks resize/focus; input forwards; fallback to preview on helper failure.
- A trial parity feature (e.g. one approval UX improvement) ships via commands/surfaces with small patch surface.

## Test plan

- E2E: `tests/e2e/herdr-qualification.test.ts` (matrix), `tests/e2e/browser-v1.test.ts` (preview + takeover with local fixture server, no live net). Classifications: Herdr matrix `verification-only` (rare/recovery); browser v1 `verification-only` or `intentional-exclusion` if it needs live net — prefer fixture server to stay deterministic. Corpus entries required.
- Binary-size + bench workflows observed per PR.

## Docs

- Herdr support matrix, browser helper protocol + versioning, parity intake checklist.

## Open questions

- Helper transport (stdio JSON vs socket) and framebuffer encoding?
- v1 helper choice: reuse `terminal-browser` helper vs minimal stub?
