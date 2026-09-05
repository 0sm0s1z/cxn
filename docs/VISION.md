# Vision

Constellation is a modal, editable, graphical agent console built on FX.

It is not a version of FX. It is not a terminal IDE.

## The split

| Layer | Ownership | Purpose |
|---|---|---|
| FX agent/runtime | Upstream (`vercel-labs/fx`) | Agent loop, tools, sessions, permissions, MCP, skills, subagents, provider machinery |
| Constellation transport | Mostly downstream | Router connection, model discovery, routing metadata |
| Interactive document shell | Downstream | Vim semantics, editable conversation, focus/navigation, mouse interaction |
| Rich terminal surfaces | Downstream | Kitty graphics, diagrams, images, eventually browser surfaces |

The bottom three layers must not gradually infect the first. Upstream merges must stay cheap six months from now.

## Product identity

- The important noun is **agent console**. Conversation, composer, and objects inside the conversation.
- Herdr arranges consoles. Constellation Router routes their models. FX supplies the agent. Constellation changes how humans interact with the agent.
- Composition is `Ghostty -> Herdr -> FX instances + shell + browser`. FX never becomes a multiplexer, pane manager, tab system, or fleet view.

## Design principles

1. **Semantic commands under every input.** Vim bindings, mouse, slash commands, and palette invoke the same `conversation.block.edit`-style commands. Behavior stays DRY.
2. **Transcript is a projection, not output.** Every displayed thing is a `Block` with source, presentation, interaction, and provenance. Rendering is a view of the semantic object.
3. **Everything editable where meaningful.** Rendered Markdown, Mermaid, images, tool calls all toggle to source with `i` or equivalent. Editing history branches instead of mutating.
4. **Surfaces separate source from presentation.** A block offers `source`, `unicode-diagram`, `kitty-raster`, etc. The renderer picks the strongest available presentation.
5. **Chrome stays invisible.** No permanent panels. Footer segments (`CONSTELLATION · auto · 61% · NORMAL`) are clickable objects. Code fences reveal `Copy / Apply / Run / Open` on focus.
6. **Small binary stays small.** Never link Chromium or Electron into FX. Browser interactivity lives in a helper process.

## What Constellation is not

- Not a fork that rewrites FX internals for every feature.
- Not a multiplexer. No workspace tree, pane splitting, background process manager, tabs, or agent fleet view.
- Not a bitmap Markdown renderer. Ordinary headings, lists, quotes, tables, code, and inline markup stay terminal-native. Pixels are for images, Mermaid, charts, SVG, HTML artifacts, browser, PDF previews, and mockups.
