# PROCEDURE_PLANS.md — STC Flake Maintenance Procedures

> This document defines the standard process for planning and executing maintenance on the STC flake.
> Every change is decomposed into atomic, testable steps. Each step is independently committable and verifiable.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Plans & Releases](#plans--releases)
- [Maintenance Process Overview](#maintenance-process-overview)
- [Change Types & Procedures](#change-types--procedures)
  - [Adding a New Relic](#adding-a-new-relic)
  - [Adding a New Cogitator](#adding-a-new-cogitator)
  - [Renaming an Option (Breaking Change)](#renaming-an-option-breaking-change)
  - [Adding a New Schematic](#adding-a-new-schematic)
  - [Refactoring Internal Code](#refactoring-internal-code)
  - [Documentation-Only Updates](#documentation-only-updates)
- [Plan Template](#plan-template)
- [Reference Commands](#reference-commands)
- [Quality Gates](#quality-gates)

---

## Quick Start

Every modification to STC follows this cycle:

1. **Plan** — Document what you're changing and why, then break it into atomic steps
2. **Execute** — Implement each step, verifying as you go
3. **Validate** — Run quality gates
4. **Deliver** — Commit atomically (one logical change = one commit)

**Key principle:** Always prefer small, testable commits over large monolithic ones.
If you can't test a change independently, it's not atomic yet.

---

## Plans & Releases

**Where plans live.** Every plan is a file under `.claude/plans/`, never at the
repo root:

- `.claude/plans/vX.Y.Z/plan.md` — the plan that produces release `vX.Y.Z`.
  A release built from several chantiers keeps one file per chantier.
- `.claude/plans/release/` — plans about tooling/infrastructure (tags, changelog,
  CI, working methods) rather than a single product feature.

An obsolete plan is **deleted**, never duplicated as `_v2` / `_v3`. See
[`.claude/plans/README.md`](.claude/plans/README.md) for the layout and the
retroactive version map.

**Git workflow (hybrid).**

- Claude works on a **dedicated branch** (`feat/…`, `fix/…`, `refactor/…`,
  `docs/…`, `chore/…`, `ci/…`) — **never directly on `main`**.
- Claude commits **atomically** (Conventional Commits) and **never** merges,
  pushes, or tags. The **user** merges the branch to `main`, tags, and pushes.
- A plan concludes when the user merges to `main`; the next plan starts from the
  updated `main`.

**Versioning & releases.**

- STC follows [Semantic Versioning](https://semver.org/); it is pre-1.0 (`0.x`),
  so breaking changes bump the minor. The deprecated `stc.*` aliases are removed
  at the first major, `v1.0.0`.
- `CHANGELOG.md` is generated from Conventional Commits by `git-cliff`
  (`just changelog`) — review the diff before committing.
- Pushing a tag `v*` triggers `.github/workflows/release.yml`, which renders that
  tag's notes and creates the GitHub release.

---

## Maintenance Process Overview

### Phase 1: Planning

Before writing code:

- [ ] Read `DESIGN.md` to verify the change aligns with STC's architecture
- [ ] Determine the change type (see [Change Types & Procedures](#change-types--procedures))
- [ ] Break the change into atomic steps (each step must be independently verifiable)
- [ ] Identify all files affected (Nix code + documentation)
- [ ] List all validation commands for each step

### Phase 2: Execution

For each atomic step:

- [ ] Implement the change in all related files
- [ ] Run the appropriate verification command
- [ ] If Nix syntax checking fails, stop and fix before proceeding
- [ ] If a schematic evaluation fails, that's a hard blocker
- [ ] Once verification passes, commit the step

### Phase 3: Documentation Sync

Documentation changes happen **in the same commit** as code changes, never after.

**Rule:** If a structural change (new module, renamed option, new cogitator) is committed without doc updates in the same commit, the docs will be stale.

### Phase 4: Validation & Delivery

Before final delivery:

- [ ] All Nix flake checks pass (`nix flake check`)
- [ ] All schematics evaluate successfully
- [ ] Documentation builds without errors
- [ ] No stale references to old namespaces in code or docs

---

## Change Types & Procedures

### Adding a New Relic

A relic is an atomic NixOS or Home Manager module that configures exactly one thing.
See `DESIGN.md` for the sarcophagus test: if the only config is a package list, it's not a relic.

#### Atomic Steps

**Step 1: Implement the Nix module**

Create `relics/nixos/<name>.nix` or `relics/home/<name>.nix`:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.stc.relics.<group>.<name>;  # Use canonical namespace
in
{
  options.stc.relics.<group>.<name> = {
    enable = lib.mkEnableOption "description of what this relic does";
    
    option1 = lib.mkOption {
      type = lib.types.str;
      default = "value";
      description = "...";
    };
  };

  config = lib.mkIf cfg.enable {
    # Implementation here
  };
}
```

**Verification:**
```bash
nix flake check --no-write-lock-file
```

**Commit message:** `feat(relics): add relics-<group>-<name> module`

---

**Step 2: Register the relic in `relics/default.nix`**

Add one line under the appropriate section in `flake.nixosModules` or `flake.homeModules`:

```nix
relics-<group>-<name> = ./nixos/<name>.nix;
# or
relics-<group>-<name> = ./home/<name>.nix;
```

If the relic depends on an upstream flake module (like impermanence), use the inputs closure pattern:

```nix
relics-<name> = { ... }: {
  imports = [
    inputs.<upstream>.nixosModules.<module>
    ./nixos/<name>.nix
  ];
};
```

**Verification:**
```bash
nix flake check --no-write-lock-file
```

**Commit message:** `chore(relics): register relics-<group>-<name> in flake outputs`

---

**Step 3: Create bilingual documentation**

Create two files:
- `docs/src/content/docs/en/relics/<name>.md`
- `docs/src/content/docs/fr/relics/<name>.md`

Each page must document:
- What the relic does (1-2 paragraphs)
- All available options with examples
- Common use cases
- Any prerequisites or dependencies

```markdown
---
title: Relic Name
description: Brief description of what this relic does
---

## Overview

Detailed explanation...

## Options

### `stc.relics.<group>.<name>.enable`

Type: `bool`
Default: `false`

Enable this relic.

### `stc.relics.<group>.<name>.option1`

Type: `string`
Default: `"value"`

Description of the option.

## Example

\`\`\`nix
stc.relics.<group>.<name> = {
  enable = true;
  option1 = "custom-value";
};
\`\`\`
```

**Verification:**
```bash
# If you have the docs dev environment set up
nix develop .#docs
npm run astro check
```

**Commit message:** `docs(relics): add documentation for relics-<group>-<name>`

---

**Step 4: Update the relics index pages**

Add an entry to:
- `docs/src/content/docs/en/relics/index.md`
- `docs/src/content/docs/fr/relics/index.md`

Include the relic name, description, and a link to its detailed page.

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs(relics): update index pages for relics-<group>-<name>`

---

### Adding a New Cogitator

A cogitator is a profile that composes multiple relics for a complete use case.
Always compose ≥ 2 relics (or 1 relic + system packages directly).

#### Atomic Steps

**Step 1: Implement the Nix module**

Create `cogitator/nixos/<name>.nix` or `cogitator/home/<name>.nix`:

```nix
# Cogitator: <Name>
#
# What this profile does (1-2 sentences)
# Composed of: relic-A, relic-B, optionally relic-C.
#
{ config, lib, pkgs, ... }:

let
  cfg = config.stc.cogitator.<name>;
in
{
  options.stc.cogitator.<name> = {
    enable = lib.mkEnableOption "description of this profile";
    
    # Expose every option from composed relics so consumes can override them
    relicAOption = lib.mkOption { /* ... */ };
  };

  config = lib.mkIf cfg.enable {
    # Activate composed relics
    stc.relics.relic-a.enable = true;
    stc.relics.relic-b.enable = true;
    
    # Pass options down to relics
    stc.relics.relic-a.option = cfg.relicAOption;
    
    # Add system packages directly
    environment.systemPackages = [ pkgs.tool-x ];
  };
}
```

**Important:** Always reference relics via their **canonical namespace** (`stc.relics.*`), never via deprecated aliases.

**Verification:**
```bash
nix flake check --no-write-lock-file
```

**Commit message:** `feat(cogitator): add cogitator-<name> profile`

---

**Step 2: Register the cogitator in `cogitator/default.nix`**

Add one line under the appropriate section in `flake.nixosModules` or `flake.homeModules`:

```nix
cogitator-<name> = ./nixos/<name>.nix;
# or
cogitator-<name> = ./home/<name>.nix;
```

For image-building cogitators (sarcophagus pattern), use the inputs closure to inject disko:

```nix
cogitator-sarcophagus-<variant> = { ... }: {
  imports = [
    inputs.disko.nixosModules.disko
    ./nixos/sarcophagus-<variant>.nix
  ];
};
```

**Verification:**
```bash
nix flake check --no-write-lock-file
```

**Commit message:** `chore(cogitator): register cogitator-<name> in flake outputs`

---

**Step 3: Create bilingual documentation**

Create two files:
- `docs/src/content/docs/en/cogitator/<name>.md`
- `docs/src/content/docs/fr/cogitator/<name>.md`

Each page must document:
- What the cogitator does (1-2 paragraphs)
- Which relics it composes
- All configurable options
- An example configuration (using schematics as reference)
- Prerequisites and dependencies

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs(cogitator): add documentation for cogitator-<name>`

---

**Step 4: Update the cogitator index pages**

Add an entry to:
- `docs/src/content/docs/en/cogitator/index.md`
- `docs/src/content/docs/fr/cogitator/index.md`

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs(cogitator): update index pages for cogitator-<name>`

---

### Renaming an Option (Breaking Change)

When renaming an option (e.g., `stc.old.path` → `stc.relics.new.path`), you must:

1. Create deprecation aliases using `lib.mkRenamedOptionModule`
2. Update all **internal code** (cogitators + schematics) to use the new namespace
3. Update all documentation

#### Atomic Steps

**Step 1: Add deprecation aliases**

In the relic or cogitator file that declares the renamed option, add imports for each renamed path:

```nix
{
  imports = [
    (lib.mkRenamedOptionModule [ "stc" "old" "path" ] [ "stc" "relics" "new" "path" ])
    (lib.mkRenamedOptionModule [ "stc" "old" "sub" "option" ] [ "stc" "relics" "new" "sub" "option" ])
  ];

  options.stc.relics.new.path = { /* ... */ };
  
  config = lib.mkIf cfg.enable { /* ... */ };
}
```

**Why:** Existing external consumers using `stc.old.path` will see a deprecation warning at eval time,
but their configurations still work. Internal code must not use the deprecated aliases.

**Verification:**
```bash
nix flake check --no-write-lock-file
```

**Commit message:** `chore(relics): add deprecation aliases for stc.old.* → stc.relics.new.*`

---

**Step 2: Update all internal references in `cogitator/`**

Search and replace all uses of the old namespace in cogitator files:

```bash
grep -rn "stc\.old\." cogitator/ --include="*.nix"
```

For each match, update to use the new canonical namespace:

```nix
# Before
stc.old.path = value;

# After
stc.relics.new.path = value;
```

**Verification:**
```bash
nix flake check --no-write-lock-file
```

**Commit message:** `refactor(cogitator): update namespace references to stc.relics.new.* (Step 2 of 4)`

---

**Step 3: Update all internal references in `schematics/`**

Search and replace in all schematic configurations:

```bash
grep -rn "stc\.old\." schematics/ --include="*.nix"
```

Update each occurrence to the new namespace.

**Verification:**
```bash
# Evaluate each schematic
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
```

**Commit message:** `refactor(schematics): update namespace references to stc.relics.new.* (Step 3 of 4)`

---

**Step 4: Update documentation**

Search for all references to the old namespace in documentation:

```bash
grep -rn "stc\.old\." docs/src/content/docs --include="*.md" --include="*.mdx"
```

For each match:
- Update the example code to use the new namespace
- Update narrative text that references the old namespace

Update both EN and FR versions.

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs: update namespace references to stc.relics.new.* (Step 4 of 4)`

---

**Post-rename cleanup (optional, can be deferred):**

At the next major version (STC v1.0.0), the old aliases can be removed entirely:

```bash
# Remove all lib.mkRenamedOptionModule imports from the relic/cogitator
# Remove the comment in relics/default.nix explaining the migration
```

**Commit message:** `chore(relics): remove deprecated aliases (stc.old.* removed in v1.0.0)`

---

### Adding a New Schematic

Schematics are example flakes that demonstrate how to consume STC.
They are not part of the main flake outputs — they are documentation in executable form.

#### Atomic Steps

**Step 1: Create the schematic directory structure**

```bash
mkdir -p schematics/<name>
cd schematics/<name>
cat > flake.nix << 'EOF'
# Schematic: <Name>
# Brief description of what this schematic demonstrates.
#
# Build:
#   nix build .#nixosConfigurations.<config-name>.config.system.build.<artefact>
{
  description = "Schematic: <name>";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stc = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, stc, ... }: {
    nixosConfigurations.<config-name> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        stc.nixosModules.cogitator-<profile>
        ({ ... }: {
          stc.cogitator.<profile> = {
            enable = true;
            # options...
          };
        })
      ];
    };
  };
}
EOF
```

**Verification:**
```bash
nix flake check --no-write-lock-file
nix eval .#nixosConfigurations.<config-name>.config.system.build.<artefact>.drvPath --no-write-lock-file
```

**Commit message:** `feat(schematics): add <name> schematic`

---

**Step 2: Create bilingual schematic documentation**

Create two files:
- `docs/src/content/docs/en/schematics/<name>.md`
- `docs/src/content/docs/fr/schematics/<name>.md`

Each page must document:
- What this schematic demonstrates
- How to build/run it
- Which cogitators and relics it uses
- The complete flake.nix (or a summary)
- Prerequisites (tools, secrets, etc.)

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs(schematics): add documentation for <name> schematic`

---

**Step 3: Update the schematics index**

Add an entry to:
- `docs/src/content/docs/en/schematics/index.md`
- `docs/src/content/docs/fr/schematics/index.md`

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs(schematics): update index for <name> schematic`

---

### Refactoring Internal Code

Non-breaking changes to how relics or cogitators work internally.
Examples: optimizing ZFS module logic, restructuring hardening options hierarchy, fixing a bug.

#### Atomic Steps

**Step 1: Implement the refactor**

Modify the Nix files (relics, cogitators, or lib).
Do not rename options; only change implementation details.

**Verification:**
```bash
nix flake check --no-write-lock-file
```

**Commit message:** `refactor(<scope>): <what changed>`

Example: `refactor(relics-zfs): simplify scrub interval logic`

---

**Step 2: If options changed, update documentation immediately**

If the refactor affects option behavior (even without renaming), update:
- The option description in the Nix code
- The corresponding documentation page (EN + FR)

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs: update documentation for refactored behavior`

---

### Documentation-Only Updates

Changes to docs that don't affect Nix code.
Examples: typos, clarifications, new examples, better structure.

#### Atomic Steps

**Step 1: Update the documentation**

Edit the relevant `.md` files in both EN and FR versions.

**Verification:**
```bash
nix develop .#docs
npm run astro check
```

**Commit message:** `docs: <what changed>`

Examples:
- `docs: fix typo in zfs documentation`
- `docs: add example for cogitator-vm SSH key setup`
- `docs: improve relics index organization`

---

## Plan Template

Use this template when planning a change to STC. Fill it out before you start coding.

```markdown
## Maintenance Plan: [Title]

**Type:** [Adding a relic | Adding a cogitator | Renaming option | etc.]

**Objective:** [What are we trying to achieve?]

**Why:** [Motivation — why is this change needed?]

### Affected Files

List all files that will be modified:
- [ ] `relics/nixos/...`
- [ ] `relics/default.nix`
- [ ] `docs/src/content/docs/en/...`
- [ ] `docs/src/content/docs/fr/...`

### Atomic Steps

Each step must be independently testable and committable.

#### Step 1: [Title]

**Description:** [What this step does]

**Files changed:**
- `path/to/file`

**Verification command(s):**
```bash
command-to-verify
```

**Commit message:** `type(scope): message`

---

#### Step 2: [Title]

[Repeat for each step...]

### Quality Gates

Before final delivery, verify:

- [ ] `nix flake check --no-write-lock-file` passes
- [ ] All schematics evaluate:
  - [ ] `nix eval ./schematics/local-vm#... --no-write-lock-file`
  - [ ] `nix eval ./schematics/aws-ami#... --no-write-lock-file`
  - [ ] `nix eval ./schematics/dreadnought#... --no-write-lock-file`
- [ ] No stale internal references:
  - [ ] `grep -rn "stc\." cogitator/ schematics/ --include="*.nix"` (filtered)
- [ ] Documentation builds: `nix develop .#docs && npm run astro check`
- [ ] All commits are atomic and independently verifiable
```

---

## Reference Commands

### Nix Flake Checks

```bash
# Full flake validation
nix flake check --no-write-lock-file

# Format Nix files (alejandra)
alejandra .

# Lint (statix)
statix check

# Find unused definitions (deadnix)
deadnix .

# All three together
just ci
```

### Schematic Evaluation

```bash
# Local VM (qcow2 image)
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file

# AWS AMI
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file

# Dreadnought (running system)
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
```

### Finding Stale References

```bash
# Find any stc.* references that aren't in canonical form
grep -rn "stc\." relics/ cogitator/ schematics/ --include="*.nix" \
  | grep -v "options\.stc\." \
  | grep -v "cfg = config\.stc\." \
  | grep -v "stc\.relics\." \
  | grep -v "stc\.cogitator\." \
  | grep -v "stc\.lib\." \
  | grep -v "^.*#"

# Find stale references in documentation
grep -rn "stc\." docs/src/content/docs --include="*.md" --include="*.mdx" \
  | grep -v "stc\.relics\." \
  | grep -v "stc\.cogitator\." \
  | grep -v "stc\.lib\." \
  | grep -v "stc\.nixosModules\." \
  | grep -v "stc\.homeModules\."
```

### Documentation

```bash
# Enter the docs dev environment
nix develop .#docs

# Run Astro type checking
npm run astro check

# Build the site locally (for inspection)
npm run build
```

### Development Environment

```bash
# Nix tools (alejandra, statix, deadnix, just)
nix develop

# Node.js tools (Astro, for docs)
nix develop .#docs

# Quick validation
just ci
```

---

## Quality Gates

Every change must pass these gates before being merged or considered complete.

### Gate 1: Nix Syntax & Logic

```bash
nix flake check --no-write-lock-file
```

Must pass with no errors. Warnings are acceptable if they are expected deprecation warnings from external modules.

### Gate 2: Schematic Evaluation

All schematics must evaluate successfully:

```bash
nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file
```

If a schematic fails to evaluate, that's a hard blocker. The change broke a live example.

### Gate 3: Namespace Correctness

```bash
grep -rn "stc\." relics/ cogitator/ schematics/ --include="*.nix" \
  | grep -v "options\.stc\." \
  | grep -v "cfg = config\.stc\." \
  | grep -v "stc\.relics\." \
  | grep -v "stc\.cogitator\." \
  | grep -v "stc\.lib\." \
  | grep -v "^.*#"
```

Should return **zero matches**. If you see internal code using non-canonical namespaces (like deprecated `stc.old.*` inside a cogitator), update it.

### Gate 4: Documentation Integrity

```bash
nix develop .#docs
npm run astro check
```

Must pass with no type errors. Documentation should build and all links should resolve.

For structural changes (new relic, renamed option, new cogitator, new schematic):

```bash
grep -rn "stc\." docs/src/content/docs --include="*.md" --include="*.mdx" \
  | grep -v "stc\.relics\." \
  | grep -v "stc\.cogitator\." \
  | grep -v "stc\.lib\." \
  | grep -v "stc\.nixosModules\." \
  | grep -v "stc\.homeModules\."
```

Should return **zero matches** for unqualified or deprecated namespaces.

### Gate 5: Atomicity & Traceability

- Each commit represents exactly one logical change
- Commit messages follow the pattern: `type(scope): message`
  - `type`: `feat`, `fix`, `refactor`, `chore`, `docs`
  - `scope`: `relics`, `cogitator`, `schematics`, etc.
  - `message`: Clear, describes what changed and why
- Every commit can be verified independently (all gates pass for that commit alone)

---

## Appendix: DESIGN.md Quick Reference

### Namespace Rules

- **Relics options:** `stc.relics.<domain>.*` (e.g., `stc.relics.zfs.enable`)
- **Cogitator options:** `stc.cogitator.<profile>.*` (e.g., `stc.cogitator.vm.username`)
- **Library functions:** `stc.lib.*`
- **Module outputs:** `stc.nixosModules.*`, `stc.homeModules.*`

### The Sarcophagus Test

A relic must do more than just install a package. If the entire `config` block is only `environment.systemPackages = [...]` or similar, it's not a relic — it belongs in a cogitator's package list.

### Secrets Pattern

Options that accept secrets use `*File` suffix:
- `stc.relics.docker.traefik.acmeEmailFile` (not `acmeEmail`)
- The module reads the file at runtime
- STC is agnostic to the secrets backend (sops-nix, agenix, plaintext, etc.)

### Inputs Closure Pattern

If a relic or cogitator depends on a flake input's module (impermanence, disko, zen-browser):

```nix
# In relics/default.nix or cogitator/default.nix
relics-name = { ... }: {
  imports = [
    inputs.upstream.nixosModules.upstream-module
    ./nixos/name.nix
  ];
};
```

The internal file (`name.nix`) never references `inputs`. The wrapper is the only place that manipulates inputs.

---

**Last Updated:** 2026-07-16  
**Status:** Active for STC v0.2.0 and onwards
