# Constellation Docs

Downstream product built on FX. FX supplies the agent and runtime. Constellation supplies the interaction layer.

Start here:

- `VISION.md` — what Constellation is and is not, the four layers, product identity.
- `ARCHITECTURE.md` — upstream/downstream split, patch-surface rule, `src/constellation/` layout, the three core abstractions.
- `REPOSITORY-STRATEGY.md` — `main` vs `constellation` branches, merge discipline, upstream sync.
- `ROADMAP.md` — build sequence 1-16, MVP, v1.5, acceptance gates.
- `PRDs/README.md` — PRD index and status.

Normative fork discipline (branches, patch surface, sync) lives in `cxn/README.md`. This file is the reading map; that file is the rulebook.

## Terms

- **FX**: upstream agent/runtime from `vercel-labs/fx`. Agent loop, tools, sessions, permissions, MCP, skills, subagents, provider machinery.
- **Constellation Router**: model routing service with an OpenAI-compatible endpoint (`/chat/completions`, streaming tool calls, `GET /v1/models`).
- **Constellation**: this downstream distribution. FX plus a modal, editable, graphical agent console.
- **Herdr**: external mouse-native agent multiplexer. Arranges consoles. Never merged into this repo.
- **Patch surface**: number of upstream-owned files modified by Constellation. First-class KPI.
