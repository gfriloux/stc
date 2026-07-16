# Plan: project structuring — plans, versioning, release tooling

**Type:** project infrastructure (structural, no relic/cogitator behaviour change)

**Objective:** Give STC the same solid working methods as the sibling projects
`astropath` and `auspex`: plans tracked under `.claude/plans/`, an honest version
history backed by real git tags, changelog + release tooling, and a working
process documented for both humans and Claude. Remove the fictional `v3.0
(January 2027)` narrative — STC had zero releases when it was written.

**Why:**
- Plans lived at the repo root, untracked, with heterogeneous names
  (`PLAN_3A`, `REMEDIATION_PLAN_v2`, `MIGRATION_v2.0`). No history, no discipline.
- The migration guide promised a `v1.x → v2.0 → v2.5 → v3.0` timeline anchored to
  calendar dates, yet not a single tag existed. The deprecation story was fiction.
- No changelog, no release automation, no versioning convention.

**Branch:** `chore/project-structuring` (one branch; the user merges/tags/pushes).

## Decisions (validated with the user)

- Retroactive versioning uses semver `0.x` (pre-1.0), 8 tags mapped to merges /
  completed plans — see [`../README.md`](../README.md) for the table.
- Deprecated `stc.*` aliases are removed at the next major (`v1.0.0`), no date.
- The user creates the tags after validation (Claude prepares/executes on OK,
  the user pushes). Claude never pushes or merges.

## Phases

### Phase 1 — Foundation: `.claude/plans/` + archive existing plans  ✅ done in-branch

- [x] Create `.claude/plans/{release,v0.1.0..v0.6.0}/`.
- [x] Move each root plan into its version directory, renamed to `plan.md`
      (second chantier keeps a descriptive name).
- [x] Add `.claude/plans/README.md` (layout + retro version map).
- [x] Author this plan.

### Phase 2 — Remove the v3.0 fiction

- [ ] `README.md` — rewrite the "Migrating from v1.x" section: aliases removed at
      `v1.0.0`, no calendar date.
- [ ] `MIGRATION_v2.0.md` → `MIGRATION.md` — rewrite the timeline table to the real
      `0.x` story; drop `v2.5 (Aug 2026)` / `v3.0 (Jan 2027)`.
- [ ] `relics/default.nix` — fix the `NAMESPACE MIGRATION (v2.0)` comment and the
      "removed in STC v3.0 (January 2027)" line.
- [ ] `PROCEDURE_PLANS.md` — fix the v3.0 references (lines ~470, ~477, ~898).
- [ ] Verify: `nix flake check` still passes (comment-only in Nix).

### Phase 3 — Retroactive tags

- [ ] Create 8 annotated tags at the mapped commits with a one-line summary each.
- [ ] Verify: `git tag` lists `v0.1.0 … v0.6.0`; `git describe` resolves.
- [ ] The user pushes: `git push origin --tags`.

### Phase 4 — Release tooling (astropath parity)

- [ ] `cliff.toml` — git-cliff config (Conventional Commits, groups, `v*` tag pattern).
- [ ] `.github/workflows/release.yml` — on tag `v*`, generate notes + GitHub release.
- [ ] `renovate.json` — weekly grouped updates (flake.lock + Actions).
- [ ] `Justfile` — add a `changelog` recipe (git-cliff).
- [ ] Generate `CHANGELOG.md` from the retro tags.

### Phase 5 — Document the working methods + doc sync

- [ ] `PROCEDURE_PLANS.md` — document `.claude/plans/` location, hybrid git
      (Claude branches/commits; user merges/tags/pushes), semver, changelog flow.
- [ ] `CLAUDE.md` — point to `.claude/plans/`, release tooling, tagging policy.
- [ ] `README.md` — add a short Releases/Changelog section.
- [ ] Bilingual sync (EN + FR) for any doc-site page touched.

## Quality gates

- [ ] `just ci` passes (fmt-check + lint + check + docs-parity).
- [ ] `nix flake check --no-write-lock-file` passes.
- [ ] No stale `v3.0` / `January 2027` references remain in tracked files.
- [ ] Atomic commits on `chore/project-structuring`; docs synced in the same commit.
