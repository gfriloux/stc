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

### Phase 2 — Remove the v3.0 fiction  ✅ done

- [x] `README.md` — aliases removed at `v1.0.0`, no calendar date.
- [x] `MIGRATION_v2.0.md` → `MIGRATION.md` — real `0.x` timeline; dropped
      `v2.5 (Aug 2026)` / `v3.0 (Jan 2027)`, incl. the FAQ.
- [x] `relics/default.nix` — comment fixed (`since v0.2.0` / removed at `v1.0.0`).
- [x] `PROCEDURE_PLANS.md` — v3.0 references fixed.
- [x] Also brought the untracked core docs (DESIGN/CLAUDE/PROCEDURE_PLANS/
      SECURITY/MIGRATION) under version control.

### Phase 3 — Retroactive tags  ✅ done (local)

- [x] Created 8 annotated tags `v0.1.0 … v0.6.0` at the mapped commits.
- [x] `git describe` resolves (`v0.6.0-N-g…`).
- [ ] **User action:** `git push origin --tags` after merging this branch.

### Phase 4 — Release tooling (astropath parity)  ✅ done

- [x] `cliff.toml` — git-cliff config (Conventional Commits, groups, `v*` pattern).
- [x] `.github/workflows/release.yml` — on tag `v*` (actions SHA-pinned).
- [x] `renovate.json` — weekly grouped updates (flake inputs + Actions).
- [x] `Justfile` — `changelog` recipe; `git-cliff` added to the dev shell.
- [x] Generated `CHANGELOG.md` from the retro tags.

### Phase 5 — Document the working methods + doc sync  ✅ done

- [x] `PROCEDURE_PLANS.md` — new "Plans & Releases" section (plans location,
      hybrid git, semver, changelog flow).
- [x] `CLAUDE.md` — new "Working methods" section.
- [x] `README.md` — added a "Releases" section.
- [x] No doc-site (`docs/`) page touched → no bilingual sync needed.

## Quality gates

- [ ] `just ci` passes (fmt-check + lint + check + docs-parity).
- [ ] `nix flake check --no-write-lock-file` passes.
- [ ] No stale `v3.0` / `January 2027` references remain in tracked files.
- [ ] Atomic commits on `chore/project-structuring`; docs synced in the same commit.
