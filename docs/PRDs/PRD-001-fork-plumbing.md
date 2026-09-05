# PRD-001 — Fork Plumbing and Upstream Discipline

Status: Draft. Sequence: 1. Covers repository topology, sync, and patch-surface metric.

## Goal

`main` stays a boring upstream mirror. `constellation` ships the product. Upstream merges stay cheap and CI proves it.

## Background

FX moves fast (~1,540 commits, large PR queue) and positions itself as a tiny Unix-like agent, not a terminal IDE. Constellation deliberately takes the interaction model somewhere upstream may never want. The split only works if downstream touches few upstream files.

## Scope

In:

- `main` / `constellation` branch roles, merge direction (`main -> constellation`), feature-branch practice.
- Sync automation: fetch upstream, update `main`, open `main -> constellation` merge.
- Patch-surface metric: count of upstream-owned files modified by Constellation, reported in CI.
- Upstream-compatibility CI on the merge (build + focused tests + smoke).
- PGSO corpus discipline for every root `tests/e2e/*.test.ts`.

Out: any product features, provider work, editor work.

## Requirements

1. Document branch roles in `docs/REPOSITORY-STRATEGY.md` (done) and enforce by convention + PR template checklist.
2. Add sync job (scheduled or manual) that never rewrites `constellation` history. Short-lived feature branches may rebase; `constellation` merges only.
3. Add CI step that diffs `constellation` against `main` and reports patch surface as a number plus file list. Warn on growth; investigate before accepting jumps.
4. Every PR touching upstream-owned code labels each touch `upstreamable` or `downstream-hook` in its description.
5. E2E corpus check keeps rejecting missing, duplicate, stale, or unclassified files.

## Architecture

- No product code. Workflow + scripts only.
- Upstream touches: none expected (`upstreamable`: none; `downstream-hook`: none).
- Downstream location: `.github/workflows/` sync + patch-surface job, `scripts/` helper if needed.

## Acceptance

- `main` fast-forwards to upstream cleanly.
- A test `main -> constellation` merge builds with `./zig-out/bin/fx` and runs one focused test.
- Patch-surface report renders file count + list on a trial PR.

## Test plan

- Focused: workflow dry-run / script unit check.
- E2E owner: none new. If a sync-fixture test is added, classify it `intentional-exclusion` (harness-only) in `scripts/pgso/corpus.json`.

## Docs

- `docs/REPOSITORY-STRATEGY.md` is the source of truth. PR template references it.

## Rollout

Land before any product branch. Create `constellation` from current `main` once this PRD is accepted.

## Open questions

- Sync cadence (daily vs weekly vs on-demand)?
- Patch-surface threshold that blocks vs warns?
