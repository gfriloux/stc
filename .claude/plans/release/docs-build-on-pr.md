# Plan — Build the docs site on pull requests

## Context

The six open Renovate pull requests (#20–#26) were all reported green by CI. A
local reproduction showed that one of them, #25 (`@astrojs/starlight` `^0.41.0`
→ `^0.42.0`), does not build at all:

```
[AstroUserError] Invalid config passed to starlight integration
  Hint: Unrecognized key: "tagline"
```

Starlight 0.42.0 removed the `tagline` configuration option, and
`docs/astro.config.mjs` still passes it.

CI missed this because `.github/workflows/docs.yml` only triggers on
`push` to `main`. No workflow builds the site on a pull request, so a dependency
bump that breaks the build reaches `main` with a green tick and only fails once
it is already merged — at which point the failure is a broken Pages deployment
rather than a red PR.

## Scope

1. Drop the dead `tagline` option from the Starlight config.
2. Build the docs site on every pull request that touches `docs/` or `assets/`.

Out of scope: merging the Renovate pull requests themselves (the user merges).

## Decisions

- **`tagline` is dead config, not a feature.** The hero tagline rendered by
  `src/components/Hero.astro` comes from each page's `hero:` frontmatter
  (`src/content/docs/{en,fr}/index.mdx`), not from the Starlight config key.
  Removing the config key changes nothing visually — Starlight's own changelog
  calls the option "never used". It is also still accepted (and ignored) by
  0.41, so this commit is safe to land before #25.
- **Reuse `docs.yml` rather than add a job to `nix.yml`.** The build steps
  already exist there; duplicating them in the Nix workflow would mean two
  copies of the Node setup to keep in sync. The deploy job is gated on
  `github.event_name == 'push'` so pull requests build without publishing.
- **Concurrency group becomes ref-scoped** (`pages-${{ github.ref }}`). The
  single `pages` group would have serialized every pull-request build behind
  live deployments. Pushes to `main` and `workflow_dispatch` both resolve to
  `refs/heads/main`, so deployments stay serialized as before.
- **`permissions` stays at the workflow level.** `pages: write` / `id-token:
  write` are unused by the build job; narrowing them per job is a separate
  cleanup and would touch the deploy path, which cannot be tested from a
  pull request.

## Atomic steps

| # | Step | Verification |
|---|------|--------------|
| 1 | Remove `tagline` from `docs/astro.config.mjs` | `npm run build` in `docs/` on the current lockfile, and on the #25 lockfile |
| 2 | Add the `pull_request` trigger + deploy gate + ref-scoped concurrency in `.github/workflows/docs.yml` | `just ci`; workflow runs green on the next pull request |

## Follow-up

Once this lands and the Renovate branches are rebased, #25 builds cleanly and
every later docs dependency bump is covered by a real build.
