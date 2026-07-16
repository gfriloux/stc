# Maintenance Plan: Internalize `nix-checks` as Purity Seals

**Type:** New forge capability + input removal (refactor across templates)

**Objective:** Bring the CI check builders currently provided by the external
`nix-checks` flake into STC as a first-class forge artefact named **Purity
Seals**, expose them through a clean public API (`stc.lib.puritySeals.<system>`),
rewire the five forge templates onto that API, and drop the `nix-checks` input.

**Why:**
- The templates reach into `stc.inputs.nix-checks.lib.<system>.checks` — a
  **private implementation detail** of STC's input closure. That is an
  abstraction leak: downstream projects generated from our templates depend on
  what STC happens to have as an input, not on STC's public contract.
- CI checks are the third leg of the forge stool alongside shells (develop) and
  templates (start): **validate**. They belong in `forge/` per DESIGN.md
  ("artefacts de construction consommables qui ne sont pas des modules").
- Removing the input eliminates a fork/version-skew surface and makes STC the
  single source of truth for the checks its templates ship.

**Naming:** *Purity Seals* — a passing check stamps an artefact as inspected and
free of heresy/corruption. API: `stc.lib.puritySeals.<system>.<seal>`.

**Scope note (fork divergence — accepted):** `github:gfriloux/nix-checks`
remains a standalone public flake. Internalizing here creates an intentional
copy that will diverge. Other repos keep working against upstream until they are
migrated to `stc.lib.puritySeals` separately. This plan does **not** delete the
upstream repo.

---

## Affected Files

**New:**
- [ ] `forge/purity-seals/seals.nix` — pure builders `{pkgs, pkgs-unfree, lib}: { nix; terraform; ansible; gitleaks; shell; markdown; }`
- [ ] `forge/purity-seals/default.nix` — flake-parts module exposing `flake.lib.puritySeals.<system>` via `withSystem` over `config.systems`
- [ ] `docs/src/content/docs/en/forge/purity-seals.md`
- [ ] `docs/src/content/docs/fr/forge/purity-seals.md`

**Modified:**
- [ ] `forge/default.nix` — `imports = [ ./purity-seals ]`
- [ ] `DESIGN.md` — add `forge/purity-seals/` row to the forge table + `stc.lib.puritySeals.*` to the rites `stc.lib.*` list (dual-listing, same as layouts)
- [ ] `README.md` — extend the Forge pillar row to mention CI checks / purity seals
- [ ] `flake.nix` — remove the `nix-checks` input block
- [ ] `flake.lock` — regenerated (drops `nix-checks` + orphaned `utils`/`systems_4`)
- [ ] `forge/templates/ansible/flake.nix`
- [ ] `forge/templates/terraform/flake.nix`
- [ ] `forge/templates/mdbook/flake.nix`
- [ ] `forge/templates/mkdocs/flake.nix`
- [ ] `forge/templates/zensical/flake.nix`
- [ ] `docs/src/content/docs/en/forge/index.md` — list Purity Seals
- [ ] `docs/src/content/docs/fr/forge/index.md`
- [ ] `docs/src/content/docs/en/forge/templates.md` — update the checks reference
- [ ] `docs/src/content/docs/fr/forge/templates.md`

---

## Atomic Steps

### Step 1: Add the Purity Seals builders + public API

**Description:** Port the six `nix-checks` builders faithfully into
`forge/purity-seals/seals.nix`, correcting the copy-pasted derivation name
(`check-shell` → `check-markdown` in the markdown builder). Keep terraform's
unfree pkgs narrowly scoped, mirroring the existing `pkgs-unfree` idiom in
`forge/default.nix`. Expose `flake.lib.puritySeals.<system>` from
`forge/purity-seals/default.nix` using flake-parts `withSystem` +
`config.systems`, and import it from `forge/default.nix`. No template changes yet.

Per DESIGN.md's invariant (structural change + doc in the **same commit**), this
commit also inscribes Purity Seals in the canonical docs: the `forge/` table and
the `rites/` `stc.lib.*` list in `DESIGN.md`, and the Forge pillar row in
`README.md`. The `docs/` reference site is handled in Step 4.

**API shape (must match current consumer surface):**
```
stc.lib.puritySeals.<system> = {
  nix       = path: drv;
  terraform = path: drv;
  ansible   = path: drv;
  gitleaks  = path: drv;
  shell     = path: drv;
  markdown  = { path, args ? "" }: drv;
};
```

**Files changed:** `forge/purity-seals/seals.nix`, `forge/purity-seals/default.nix`, `forge/default.nix`, `DESIGN.md`, `README.md`

**Verification:**
```bash
nix flake check --no-write-lock-file --show-trace
nix eval .#lib.puritySeals.x86_64-linux --apply builtins.attrNames --no-write-lock-file
# smoke-build one seal against the repo itself:
nix build --no-write-lock-file --impure \
  --expr '(builtins.getFlake (toString ./.)).lib.puritySeals.x86_64-linux.gitleaks ./.'
```

**Commit:** `feat(forge-purity-seals): internalize CI checks as stc.lib.puritySeals`

---

### Step 2: Rewire the five templates onto `stc.lib.puritySeals`

**Description:** In each `forge/templates/*/flake.nix`, replace
`inherit (stc.inputs.nix-checks.lib.${system}) checks;` with
`checks = stc.lib.puritySeals.${system};` (adjust the `let` binding). Behaviour
per template is unchanged — same seals, same args.

**Files changed:** the five `forge/templates/*/flake.nix`

**Verification (templates are NOT evaluated by STC's own `nix flake check`):**
```bash
# For each template: copy to scratch, point its `stc` input at this repo, check.
d=$(mktemp -d); cp -r forge/templates/terraform/* "$d"/
# rewrite stc input url -> path:<repo> in "$d/flake.nix", then:
nix flake check "$d" --no-write-lock-file --show-trace
```
Repeat for ansible / mdbook / mkdocs / zensical.

**Commit:** `refactor(forge-templates): consume stc.lib.puritySeals instead of stc.inputs.nix-checks`

---

### Step 3: Drop the `nix-checks` input

**Description:** Remove the `nix-checks` input block from `flake.nix`, then
regenerate `flake.lock` (`nix flake lock`) so `nix-checks` and its now-orphaned
transitive inputs (`utils`, `systems_4`) are pruned. Confirm no reference to
`stc.inputs.nix-checks` remains anywhere.

**Files changed:** `flake.nix`, `flake.lock`

**Verification:**
```bash
grep -rn "nix-checks" . --include="*.nix" --include="*.lock" | grep -v '^./.git'   # -> empty
nix flake metadata --no-write-lock-file | grep -i nix-checks                        # -> empty
nix flake check --no-write-lock-file --show-trace
```

**Commit:** `chore(flake): drop nix-checks input, superseded by purity-seals`

---

### Step 4: Documentation sync (bilingual, same change)

**Description:** Add `forge/purity-seals.md` (EN + FR) documenting the seals and
the `stc.lib.puritySeals.<system>.<seal>` API with a template usage example;
link it from both `forge/index.md`; update the checks reference in both
`forge/templates.md` (drop the `nix-checks` mention, point at Purity Seals).

**Files changed:** the four docs files above + two new pages

**Verification:**
```bash
just docs-parity
grep -rn "nix-checks" docs/src/content/docs   # -> empty
nix develop .#docs --command sh -c 'cd docs && npm run astro check'
```

**Commit:** `docs(forge): document Purity Seals, remove nix-checks references`

---

## Quality Gates

- [ ] `nix flake check --no-write-lock-file --show-trace` passes
- [ ] `nix eval .#lib.puritySeals.x86_64-linux --apply builtins.attrNames` lists the six seals
- [ ] One seal builds against the repo (Step 1 smoke build)
- [ ] All five rewired templates `nix flake check` green with `stc` pointed at this repo
- [ ] No `nix-checks` reference remains: `grep -rn nix-checks . | grep -v .git` empty
- [ ] Canonical docs inscribe the artefact: `grep -n puritySeals DESIGN.md README.md` non-empty
- [ ] `just docs-parity` passes; no stale `nix-checks` in docs
- [ ] Schematics still evaluate (unaffected, but sanity-check):
  - [ ] `nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file`
  - [ ] `nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file`
- [ ] Four atomic commits, each independently verifiable

---

## Open technical question (resolve at Step 1)

`flake.lib` is contributed by `rites/default.nix` (`layouts`, `docker`).
`puritySeals` is per-system, so it is built with `withSystem` over
`config.systems` and merges into `flake.lib` under a distinct key — no conflict
with rites' assignments (different attr paths). If flake-parts rejects the merge,
fall back to declaring the aggregation inside `rites/default.nix` (which already
owns `flake.lib`), keeping the builder code in `forge/purity-seals/`. Precedent:
layouts already live in `forge/` but are exposed through `rites/default.nix`.
