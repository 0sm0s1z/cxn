# PR checklist (see `docs/REPOSITORY-STRATEGY.md`)

- [ ] Base is `constellation` (feature branches fork from `constellation`, merge back into it). `main` takes no direct commits.
- [ ] `type:` label applied (`bug`, `feature`, `improvement`, `docs`, `maintenance`, `release`, `security`).
- [ ] Title is a clean imperative sentence.

## Upstream touches

List every upstream-owned file changed, each labeled:

- `upstreamable` — could go to `vercel-labs/fx` as-is, or
- `downstream-hook` — thin registration point for `src/constellation/`.

None / list:

## Patch surface

Paste `./scripts/patch-surface.sh` output. Warn at 12, fail at 50. Growth means architecture (move code downstream), not budget inflation.

## Verification

- [ ] `zig fmt --check src/`
- [ ] `zig build` + `./zig-out/bin/fx --version`
- [ ] Focused tests (and E2E owner + PGSO classification if a root `tests/e2e/*.test.ts` was added/removed)
