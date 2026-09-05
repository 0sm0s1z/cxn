# Repository Strategy

## Topology

```text
vercel-labs/fx (upstream)
      │
      │ upstream sync
      ▼
origin/main                 ← boring upstream mirror
      │
      │ merge main -> constellation periodically
      ▼
origin/constellation        ← shipping downstream product
      │
      ├── feat/vim-engine
      ├── feat/router-provider
      ├── feat/editable-transcript
      ├── feat/kitty-surfaces
      └── ...
```

- `main` tracks Vercel. No Constellation features land here.
- `constellation` is the integration branch for the distribution.
- Merge `main -> constellation`. Never repeatedly rewrite a long-lived downstream distribution. Rebase short-lived feature branches only.

Current remotes already match this: `upstream` is `vercel-labs/fx`, `origin` is the downstream fork.

## Patch-surface KPI

> downstream patch surface = number of upstream-owned files modified by Constellation

Track it in CI. It must stay small. Growth from ~12 to 70 to 250 files means upstream merges are becoming painful and the architecture has failed.

Rules:

- Prefer `src/constellation/` plus thin hooks over edits inside `src/core/`, `src/ui/`, `src/gateway/`.
- Every upstream-owned touch is labeled `upstreamable` or `downstream-hook` in the PR description.
- Prefer adopting upstream PRs (e.g. OpenAI-compatible provider work) over carrying duplicate transports.

## Sync automation (PRD-001 scope)

- Scheduled or on-demand sync job: fetch upstream, fast-forward or merge into `main`, open `main -> constellation` merge.
- Upstream compatibility CI: build + focused tests on the merge before it lands.
- Corpus discipline: every root `tests/e2e/*.test.ts` keeps exactly one PGSO classification in `scripts/pgso/corpus.json` (`training`, `verification-only`, `intentional-exclusion`). New E2E owners reconsider classification. Removals delete stale entries.

## Branch practice

- Feature branches fork from `constellation`, merge back into `constellation`.
- Checkpoint commits stay clean so Full CI maps to the exact commit.
- PR titles are clean imperative sentences. `type:` label is required (`bug`, `feature`, `improvement`, `docs`, `maintenance`, `release`, `security`).
