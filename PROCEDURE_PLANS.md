# PROCEDURE_PLANS.md — STC Flake Maintenance Procedures

> This document defines the standard process for planning and executing maintenance on the STC flake.
> Every change is decomposed into atomic, testable steps. Each step is independently committable and verifiable.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Plans & Releases](#plans--releases)
- [Sizing a Change](#sizing-a-change)
- [Maintenance Process Overview](#maintenance-process-overview)
- [Change Types & Procedures](#change-types--procedures)
  - [Adding a New Relic](#adding-a-new-relic)
  - [Adding a New Cogitator](#adding-a-new-cogitator)
  - [Renaming an Option (Breaking Change)](#renaming-an-option-breaking-change)
  - [Adding a New Schematic](#adding-a-new-schematic)
  - [Refactoring Internal Code](#refactoring-internal-code)
  - [Documentation-Only Updates](#documentation-only-updates)
- [Execution Discipline](#execution-discipline)
  - [Debugging — root cause before fixes](#debugging--root-cause-before-fixes)
  - [Verification — evidence before claims](#verification--evidence-before-claims)
  - [Tests — what replaces TDD](#tests--what-replaces-tdd)
  - [Closing review — one fresh context](#closing-review--one-fresh-context)
  - [The ledger](#the-ledger)
- [Plan Template](#plan-template)
- [Reference Commands](#reference-commands)
- [Quality Gates](#quality-gates)
- [Skill Arbitration](#skill-arbitration)

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

**Git workflow.**

- Claude works on a **dedicated branch** (`feat/…`, `fix/…`, `refactor/…`,
  `docs/…`, `chore/…`, `ci/…`) — **never directly on `main`**.
- Claude commits **atomically** (Conventional Commits) and runs the full flow
  itself: merge, changelog, tag, push.
- A plan concludes once the branch is integrated into `main`; the next plan
  starts from the updated `main`.

**Closing a branch.** When the work is complete and every quality gate below has
passed, present the integration choice rather than deciding alone:

1. Merge back to `main` locally
2. Push and open a Pull Request
3. Keep the branch as-is

Then carry out the chosen option. A release adds the changelog/tag/push sequence
(see **Versioning & releases** just below).

**Interactive git — stop before the batch.**

Commits and tags are OpenPGP-signed (`commit.gpgsign` and `tag.gpgsign` are both
`true`) and `origin` is reached over SSH with a YubiKey. Every one of these
prompts for a passphrase, or for a PIN and a touch:

| Command | Prompt |
|---------|--------|
| `git commit` | OpenPGP passphrase |
| `git tag -a` | OpenPGP passphrase |
| `git merge --no-ff` | OpenPGP passphrase (it writes a merge commit) |
| `git fetch` / `git pull` / `git push` | YubiKey PIN + touch |

**Announce the batch and wait for the user's go-ahead before the first one** —
"5 atomic commits coming up, then the push — are you at the keyboard?" — then
chain the commands, relying on the `gpg-agent` passphrase cache. One stop per
batch, not per command.

If a prompt hangs or a signature fails: report it and wait. Never retry with
`--no-gpg-sign`, never disable signing, never push over HTTPS to dodge the
YubiKey.

**Versioning & releases.**

- STC follows [Semantic Versioning](https://semver.org/); it is pre-1.0 (`0.x`),
  so breaking changes bump the minor. The deprecated `stc.*` aliases are removed
  at the first major, `v1.0.0`.
- `CHANGELOG.md` is generated from Conventional Commits by `git-cliff`
  (`just changelog`) — review the diff before committing.
- Pushing a tag `v*` triggers `.github/workflows/release.yml`, which renders that
  tag's notes and creates the GitHub release.

Release sequence — one interactive batch, announced before the first command
(`git-cliff` must run the `--tag` of the release being cut, and the changelog is
committed **before** the tag so the tag covers it):

```bash
git checkout main && git pull --ff-only
git merge --no-ff <branch>
gh pr close <n> --comment "…"                    # superseded PRs, if any
nix develop --command git-cliff --tag vX.Y.Z --output CHANGELOG.md
git diff CHANGELOG.md                             # read it before committing
git add CHANGELOG.md && git commit -m "docs(changelog): generate CHANGELOG.md for vX.Y.Z"
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin main && git push origin vX.Y.Z
```

State what the tag will cover beyond the branch (commits already on `main` that
are not tagged yet), and pick the SemVer number yourself with a one-line
justification rather than asking.

---

## Sizing a Change

Not every change earns a plan file. Classify first, **say the classification out
loud** so the user can override it, then follow that path.

| Path | What it is | Artefact |
|------|-----------|----------|
| **Probe** | A feasibility question — "does nixpkgs expose X?", "can disko do Y?". The output is an answer, not code we keep. | None. State the question and how you'll check it in two sentences, then report a recommendation. Anything built is labelled throwaway. |
| **Bounded** | A well-scoped change to code that already exists here: one option added to a relic, a fix in a cogitator, a behaviour change in a doc page. | No plan file. Present a short design in conversation, get an explicit yes, then implement. |
| **Trivial** | No decision to present: a typo, a broken link, a reformat, a wording fix that changes no option and no behaviour. See [Documentation-Only Updates](#documentation-only-updates). | None, and no approval. Just do it and say what was done. |
| **Architectural** | A new relic, a new cogitator, a new schematic, a namespace rename, a refactor that moves responsibilities between layers, anything touching `DESIGN.md`'s boundaries. | A plan file under `.claude/plans/` (see [Plan Template](#plan-template)), reviewed by the user before implementation. |

**Bounded measures the repo, not your familiarity.** If the flow being changed is
not already here to read, the change is not bounded.

**The ratchet is one-way.** In doubt between two paths, take the heavier one.
Complexity discovered mid-task upgrades the path — stop, say so, and step up.
Nothing downgrades mid-task, and a label is never chosen in order to skip work.

There is no separate spec document: for an architectural change the plan file
*is* the spec, which is why it carries Goal, Architecture, Global Constraints and
Review Focus.

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

**Step 5: Write the proving** — mandatory, not a follow-up

A cogitator claims a complete, bootable use case. The proving is what makes the
claim checkable (see [Tests](#tests--what-replaces-tdd)). Three files change
together:

1. `provings/<name>.nix` — a `nixosTest` that boots a VM with the cogitator
   enabled and asserts what it claims. Take `provings/hardening.nix` as the
   reference for the shape; `self` is threaded in so the node can import the real
   flake module.
2. `provings/default.nix` — register it under `legacyPackages.provings`.
3. `Justfile` — add the build to the `test` recipe, or `just test` will pass
   without ever running it.

**Verification:**
```bash
just test
```

**Commit message:** `test(provings): add proving for cogitator-<name>`

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

## Execution Discipline

Five rules, whatever the change type: three govern how a step is worked, two how a
branch is closed. They are adapted from `superpowers`; where the wording differs
from the plugin's, this document wins (see [Skill Arbitration](#skill-arbitration)).

### Debugging — root cause before fixes

**No fix before the cause is understood.** A fix that makes the symptom go away
without an explanation is a failure, even when the error disappears.

1. **Read the error completely.** Nix errors bury the useful line in the middle
   of a trace. Re-run with `--show-trace`. An `infinite recursion` or an
   `attribute missing` names the option path — read that path.
2. **Reproduce narrowly.** Go from `nix flake check` down to the smallest command
   that still fails: `nix eval <schematic>#…config.<the exact option>`. A failure
   you can trigger in one `nix eval` is a failure you can reason about.
3. **Check what changed.** `git diff`, the last commits, a bumped input in
   `flake.lock`. A break that appeared after `just update` is an upstream change,
   not a bug in the module.
4. **Compare against something that works.** Another relic doing the same thing,
   the upstream NixOS module. List every difference; "that cannot matter" is how
   the cause gets skipped.
5. **One hypothesis, one minimal change.** State it — "I think the alias is
   missing because internal code still reads the old path" — then test only that.
   A new hypothesis replaces the old one; fixes are never stacked.

The `/debug-nix` skill is the Nix-specific toolbox for steps 1–2; this rule is
the discipline that decides when to use it.

**Three failed fixes means the design is wrong.** If each fix uncovers a new
problem somewhere else, or every fix requires "just a bit of restructuring":
stop, do not attempt a fourth, and raise the architecture question with the user.
That is not a failed hypothesis, it is a wrong boundary — and `DESIGN.md` is the
place it gets settled.

### Verification — evidence before claims

**If the command has not been run in this message, its result cannot be
claimed.** Before any statement that something passes, works, or is done:

1. Which command proves this?
2. Run it, in full — not a narrowed variant.
3. Read the whole output and the exit code.
4. Does the output actually support the claim? If not, state the real status,
   with the output.

| Claim | Proof required |
|-------|----------------|
| "the flake is fine" | `nix flake check --no-write-lock-file` → exit 0 |
| "the schematics still evaluate" | one `nix eval …drvPath` **per** schematic |
| "no stale namespace left" | the filtered `grep` from [Quality Gates](#quality-gates), zero matches — and a grep written to match the language the file is in, not only English |
| "`en/` and `fr/` hold the same pages" | `just docs-parity` → OK. It compares file paths only; it says nothing about whether the two pages agree |
| "the VM behaves as claimed" | `just test`, read the proving's output — **and** check the `test` recipe actually builds the proving covering what changed |
| "the bug is fixed" | the original symptom re-tested, not the code re-read |

"Should be fine", "the change is trivial", "the linter passed" prove nothing —
`statix` is not an evaluator and `nix flake check` is not a boot. Fatigue, time
pressure and a long green streak are the three moments this rule exists for.

### Tests — what replaces TDD

`superpowers`' TDD Iron Law ("no production code without a failing test first")
does not transfer: STC's tests are `nixosTest`s that boot a VM, they live in
`provings/`, they take minutes, and they are deliberately outside `just ci`.
Writing one before each 5-minute step is not possible, and a test written to
satisfy the ritual tests nothing.

What binds instead:

- **The gates are the law.** No step is committed before its verification
  command passes — `nix flake check` for a module change, `nix eval …drvPath` for
  anything a schematic consumes. That is the fast loop.
- **Every new cogitator ships a proving.** A cogitator claims a complete,
  bootable use case; the proving in `provings/<name>.nix` is what makes the claim
  checkable. It is part of the same plan, not a follow-up. Register it in
  `provings/default.nix` and add it to the `test` recipe in the `Justfile`.
- **A relic needs no proving of its own** when a cogitator's proving already
  composes it. A relic nothing composes yet, and whose behaviour cannot be read
  from an `nix eval`, is the exception — say so in the plan and justify it.
- **A bug fix starts with a reproduction that fails.** Not necessarily a
  `nixosTest`: an `nix eval` that errors, or an assertion in an existing proving,
  is enough. What matters is having watched it fail before the fix and pass
  after. A fix whose failure was never observed is a hope.
- **Provings stay out of `just ci`.** They are heavy and Linux-only. `just test`
  is run when a cogitator changes, and before closing a branch that touched one.

### Closing review — one fresh context

Before presenting the integration options, the branch gets **one review from a
context that did not write it**. Same author, same blind spots: re-reading your
own diff is not this review.

**How to get that context**, in order of preference:

1. A dispatched subagent — the normal path. It reads the diff in its own context
   and only its findings come back.
2. Failing that, a session that has been `/clear`ed, reviewing from the diff and
   the plan alone.

Asking the user to look at it is **not** a substitute: the user is the person the
review protects, and their go-ahead is not a review. If no fresh context can be
obtained, say so plainly in the closing message — a self-review is weaker, and
whether that is enough before merging is the user's call, made knowingly.

Give the reviewer the diff range (`$(git merge-base main HEAD)..HEAD`), the plan,
its Review Focus section verbatim, and the ledger's rulings — never the session
history. Then:

- **Re-grade every finding by its effect**, not by whether the plan mentioned the
  input that triggers it. A plan is a vision document; its silence about an input
  is not permission for that input to break a consumer's build. A finding graded
  Minor because the plan said nothing has graded the plan, not the effect.
- **Critical and Important** get one fix pass, each fix verified by its own
  reproduction, then the gates re-run.
- **Minor** goes to the ledger and to the closing message as a deferred item.
  It does not enter the fix pass — the user decides.
- A finding deliberately left unfixed is a ruling, and it reaches the user.

Incoming review feedback — from the user or from a reviewer — is evaluated, not
performed. Restate the technical point, check it against this codebase, push back
with reasoning when it is wrong. "You're absolutely right" is not a response.

### The ledger

A chantier that spans sessions loses its context to compaction. The plan records
the intent; the **ledger** records what actually happened, and it is the only
thing that survives.

**One ledger per plan file**, beside it and committed — not one per release. A
release built from several chantiers has one plan file per chantier, so it has one
ledger per chantier:

| Plan file | Its ledger |
|-----------|------------|
| `.claude/plans/v0.9.0/plan.md` | `.claude/plans/v0.9.0/progress.md` |
| `.claude/plans/v0.9.0/<chantier>.md` | `.claude/plans/v0.9.0/<chantier>-progress.md` |
| `.claude/plans/release/<name>.md` | `.claude/plans/release/<name>-progress.md` |

A **bounded** change has no plan file, so it has no ledger. Its rulings go
straight into the closing message, which is then the only record — one more reason
the ratchet leans toward the heavier path when a change might grow.

First line names the plan it follows:

```markdown
# Ledger — plan: .claude/plans/v0.9.0/plan.md

Pre-flight: step 3 consumes the option renamed in step 1 — checked, names match.
Step 1: complete (c485656, nix flake check → OK)
Step 2: Ruling: the alias covers `stc.old.sub.*` as a whole rather than one
  module per leaf — mkRenamedOptionModule needs one entry per leaf option —
  cost if wrong: one commit to split it.
Step 2: complete (a1b2c3d..d4e5f6a, nix eval ×3 → OK)
Final: minor (deferred): the FR page for relics-foo lacks a usage example
```

Rules:

- **Rule, don't stall.** A conflict in the plan, an ambiguity, a plan defect:
  decide it, write `Ruling: <what was decided> — <why> — <cost if wrong>`, and
  keep going. A deviation from the plan with no ruling in the ledger is a
  decision taken in secret. **Five things stop the work** instead of being ruled
  on: a destructive or irreversible operation; anything security-sensitive; an
  interactive git command (see the batch rule above); a plan so broken that every
  way forward is a guess; and three failed fixes on the same problem, which is an
  architecture question and never a fourth attempt
  ([Debugging](#debugging--root-cause-before-fixes)).
- **Write the line in the same call as the commit**, not later. Compaction does
  not wait for a convenient moment.
- **After a compaction, trust the ledger and `git log`, not your recollection.**
  A step with a `complete` line is done; resume at the first one without.
- Every `Ruling:` and every deferred minor is repeated in the closing message.
  That message is the only place these decisions reach the user.

---

## Plan Template

Use this template when planning a change to STC. Fill it out before you start coding.

```markdown
## Maintenance Plan: [Title]

**Type:** [Adding a relic | Adding a cogitator | Renaming option | etc.]

**Goal:** [One sentence — what this builds]

**Why:** [Motivation — why is this change needed?]

**Architecture:** [2-3 sentences on the approach, and which DESIGN.md boundary
it sits on]

### Global Constraints

Project-wide requirements that every step below implicitly inherits — one line
each, exact values, no "see above":

- [Canonical namespace the new options live under]
- [Which schematics must keep evaluating]
- [Whether a proving is required — mandatory for a new cogitator]
- [Secrets: any option taking a secret uses the `*File` suffix]

### Review Focus

The failure modes this change could introduce that no step's verification
command exercises — one line each, most likely first, written with the whole
plan in view. An external consumer's build breaking is the usual one. An empty
section means the check was run and found nothing, not that it was skipped.

### Affected Files

List all files that will be modified:
- [ ] `relics/nixos/...`
- [ ] `relics/default.nix`
- [ ] `provings/...`
- [ ] `docs/src/content/docs/en/...`
- [ ] `docs/src/content/docs/fr/...`

### Atomic Steps

Each step must be independently testable and committable.

#### Step 1: [Title]

**Description:** [What this step does]

**Files changed:**
- `path/to/file`

**Interfaces:**
- Consumes: [what this step relies on from an earlier step — exact option paths]
- Produces: [what later steps will read — exact option paths, types, defaults]

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
- [ ] Doc parity: `just docs-parity`
- [ ] If a cogitator changed: `just test`
- [ ] All commits are atomic and independently verifiable
```

### No placeholders

Every step must carry what is actually needed to execute it. These are plan
defects, not shortcuts to fill in later:

- "TBD", "to be detailed", "handle the edge cases", "add the appropriate options"
- A step that says *what* without showing *how* — an option gets its type, its
  default and its description in the plan, not just its name
- "Same as step N" — repeat it; steps get read out of order
- A reference to an option path no step declares

### Pre-flight scan

Before executing step 1, read the Interfaces blocks against each other: for every
step that consumes what an earlier one produces, check that the two spell the
option path the same way. One ledger line per pair, with what was found. Steps
sharing nothing get the single line `Pre-flight: no shared interfaces`.

This is the guard the [namespace rename procedure](#renaming-an-option-breaking-change)
depends on. Its steps 2 and 3 exist precisely because a rename that lands the
alias without updating `cogitator/` and `schematics/` fails at eval time with no
useful message. Declaring the produced path in step 1 and the consumed path in
steps 2 and 3 turns "remember to do it" into a dependency that can be checked
before anything is committed.

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

```bash
just docs-parity
```

Checks that `en/` and `fr/` hold the **same set of file paths** — it does not read
their content. It catches a page added or renamed in one language only. It does
**not** catch an option example updated in `en/` and forgotten in `fr/`; that one
is caught by the grep below and by reading both pages.

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

### Gate 5: Behaviour (cogitators only)

If the change added or touched a cogitator:

```bash
just test
```

Every proving the recipe builds must pass. Before trusting a green run, check
that the recipe actually builds the proving covering what changed — a proving
registered in `provings/default.nix` but absent from the `test` recipe never
runs, and the green is false. See [Tests](#tests--what-replaces-tdd).

Changes that touch no cogitator skip this gate. It is not part of `just ci`:
provings boot VMs, they take minutes, and they are Linux-only.

### Gate 6: Atomicity & Traceability

- Each commit represents exactly one logical change
- Commit messages follow the pattern: `type(scope): message`
  - `type`: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`
  - `scope`: `relics`, `cogitator`, `schematics`, `provings`, etc.
  - `message`: Clear, describes what changed and why
- Every commit can be verified independently (all gates pass for that commit alone)

### Gate 7: Fresh-context review

The branch has had [one review from a context that did not write it](#closing-review--one-fresh-context),
its Critical and Important findings are fixed, and its Minor findings are in the
ledger and the closing message.

---

## Skill Arbitration

The `superpowers` plugin injects its `using-superpowers` skill into every session
— at startup, after `/clear`, and after every compaction — wrapped in
`<EXTREMELY_IMPORTANT>`, with the rule "if there is even a 1% chance a skill
applies, you MUST invoke it". The plugin also states that user instructions take
precedence over its skills. The table below is that precedence, made explicit.
**Where a skill and this document disagree, this document wins.** Arbitrated
against `superpowers` 6.4.1.

What the verdicts mean:

| Verdict | Operative meaning |
|---------|-------------------|
| **Adopted** | Follow the skill as written. Read it when the situation arises. |
| **Adapted** | The skill's shape holds, but this document's version of it is what binds — including where it is narrower. Read this document, not the skill. |
| **Reduced** | Only the part named here applies. Everything else in the skill — its gates, its artefacts, its extra stages — does not. |
| **Replaced** | The skill does not apply at all; the rule named here takes its place. |
| **Rejected by default** | Do not use it unless the user asks for it explicitly. |
| **Rejected** | Do not use it. |
| **Overridden** | Its instructions do not bind here. |
| **Marginal** | Allowed, never the default, no rule attached. |

| Skill | Verdict | Why |
|-------|---------|-----|
| `systematic-debugging` | **Adopted** | See [Debugging](#debugging--root-cause-before-fixes). `/debug-nix` is the toolbox, this is the discipline. |
| `verification-before-completion` | **Adopted** | See [Verification](#verification--evidence-before-claims). Our gates said what to check, never when. |
| `requesting-code-review` | **Adapted** | Its fresh-context principle and its context-packaging rule are in. Its cadence is not: the skill mandates a review after every task and before every merge; here it is **one** review at branch close. See [Closing review](#closing-review--one-fresh-context). |
| `receiving-code-review` | **Adopted** | Evaluate feedback, push back with reasoning, no performative agreement. |
| `finishing-a-development-branch` | **Adopted** | Its three integration options are how a branch is closed. Claude runs the git flow, under the interactive batch rule in [Plans & Releases](#plans--releases). |
| `writing-skills` | **Adopted** | For STC's own skills (`/nix-refactor`, `/nixos-module`, `/debug-nix`), which were written without a method. |
| `writing-plans` | **Adapted** | Header, Global Constraints, Review Focus, Interfaces blocks and the no-placeholders rule are in. Its locations (`docs/superpowers/plans/`) are not: plans live in `.claude/plans/`, and `docs/` is the bilingual Astro tree. Its per-step red-green granularity is replaced by the gates. |
| `executing-plans` | **Adapted** | Ledger, rulings-not-stalls, and the final fresh-context review are in. The `.superpowers/sdd/` workspace and its scripts are not — the ledger sits beside its plan and is committed. |
| `brainstorming` | **Reduced** | Its probe/bounded/architectural triage became [Sizing a Change](#sizing-a-change). No separate spec document: the plan file is the spec. The browser visual companion is not used. |
| `test-driven-development` | **Replaced** | Its Iron Law cannot transfer to modules whose tests boot a VM. See [Tests](#tests--what-replaces-tdd). |
| `subagent-driven-development` | **Rejected by default** | An implementer plus a reviewer per step, each re-reading the flake from zero, is not worth it at STC's change size. Available if the user asks for it on a large chantier; propose it when a plan passes roughly eight steps. The fresh-context review at the end is kept either way. |
| `using-git-worktrees` | **Rejected** | A dedicated branch is the isolation. A second worktree loses `.direnv` and the eval cache, so the first evaluation in it is slow — flake inputs themselves are not refetched, they resolve from `flake.lock` into the shared store. Its Step 2 auto-setup is a no-op here (guarded on `package.json` / `Cargo.toml`, neither at the repo root), so the cost is the lost direnv, not the setup. This rejects the skill's manual `git worktree add` workflow, not a harness-native worktree the user asks for. |
| `using-superpowers` | **Overridden** | Its "1% chance → you must invoke it" does not override a verdict in this table. It is the reason this table exists. |
| `dispatching-parallel-agents` | **Marginal** | Genuinely independent parallel work is rare in a flake this size. Not forbidden, never the default. |
| `diagnosing-superpowers` | **Marginal** | Only to build a bug report for the plugin's maintainers. Nothing to do with STC. |

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

**Last Updated:** 2026-09-27  
**Status:** Active for STC v0.2.0 and onwards
