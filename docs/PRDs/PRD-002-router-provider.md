# PRD-002 — Constellation Router Provider

Status: Draft — core logic in `src/constellation/provider.zig`, thin `cxn-status` wiring landed, full provider registration pending. Sequence: 2. Depends on PRD-001.

## Goal

FX becomes a good native client for Constellation Router without forking the wire protocol.

## Background

FX documents Gateway, Codex, and Grok as primary providers. Upstream PR #553 implements a first-class OpenAI-compatible provider (`/chat/completions`, streaming tool calls, configurable base URL, `GET /v1/models` discovery). That is exactly the transport Constellation needs.

## Scope

In:

- Generic OpenAI-compatible transport adoption (carry tiny impl temporarily or selectively adopt #553, then delete the duplicate when upstream lands it).
- Constellation profile: endpoint config + router metadata, reusing the generic transport.
- `/provider` UX with `Constellation` entry plus `Custom OpenAI`.
- Router-first model catalog: dynamic discovery, `Auto` as router pseudo-model.
- Routing metadata surfacing (provider, seat, route, subscription, cached tokens, reasoning tier, request ID, latency) for later hover/click inspection.

Out: Vim, transcript, graphics, browser. No FX-side routing heuristics. No proprietary wire protocol.

## Requirements

1. Provider shape (conceptual):
   ```text
   provider: constellation
   base_url: http://router...
   model: auto
   auth: ...
   headers:
     x-constellation-client: fx
   ```
2. Transport is shared OpenAI-compatible code. Constellation profile only adds endpoint defaults, auth, headers, and metadata parsing.
3. Provider picker:
   ```text
   /provider
     Vercel
     Codex
     Grok
     Constellation
     Custom OpenAI
   ```
4. Model picker for Constellation lists discovered models plus `Auto` first. No static model IDs shipped. The router routes; FX presents.
5. Optional response metadata is parsed into a typed struct and retained for display. Unknown fields are ignored. Generic OpenAI path never breaks on router extras.
6. Auth follows existing FX credential patterns. No tokens logged. Host-managed auth mode keeps working.

## Interaction spec

- Selecting `Constellation` prompts for base URL + credentials once, then discovers models.
- Footer shows `CONSTELLATION · auto` as clickable objects (picker hooks land here; full hit-map in PRD-006).
- Metadata appears in a minimal inspection view (exact surface finalized with PRD-005 transcript work; v1 can be a details line).

## Architecture

- Upstream touches (label in PR):
  - `upstreamable`: generic OpenAI-compat fixes worth sending upstream.
  - `downstream-hook`: provider-profile registration, catalog hook, metadata carrier.
- Downstream location: `src/constellation/provider/` (profile, discovery, metadata types, picker wiring).
- Want upstream fixes automatically: keep transport diff minimal so #553 improvements merge cleanly.

## Acceptance (built binary `./zig-out/bin/fx`)

- Point at a test Router (or stub with `/v1/models` + `/chat/completions` streaming), select Constellation, pick `Auto` and one discovered model, complete a prompt on each.
- Disconnect Router: picker reports unavailability cleanly, existing providers keep working.
- Metadata from stub response appears in inspection view; generic OpenAI path ignores it without error.

## Test plan

- Focused Zig tests: profile parsing, header injection, metadata parsing with unknown-field tolerance, catalog merge with `Auto` first.
- E2E owner: new `tests/e2e/router-provider.test.ts` against a local stub server. PGSO classification: `verification-only` (correctness/recovery, not hot path). Add entry to `scripts/pgso/corpus.json`.
- Live-network evals stay out; stub only.

## Docs

- README provider section, `/provider` help text via command specs, `docs/` Router setup page.

## Rollout

Land as `feat/router-provider` into `constellation`. Delete any temporary transport duplicate the moment upstream #553 (or equivalent) lands.

## Open questions

- Exact Router auth shape (key vs OAuth vs team)? Confirm before finalizing settings keys.
- Does Router support `Auto` natively, or is a sentinel needed? `Auto` must remain a router-side decision either way.
