# STC — Standard Template Construct
# Run `just` to list all available recipes.

default:
    @just --list --unsorted


# ── Nix ───────────────────────────────────────────────────────────────────────

# Format all Nix files
fmt:
    alejandra .

# Check formatting without modifying files
fmt-check:
    alejandra --check .

# Lint for antipatterns and dead code
lint:
    statix check .
    deadnix --fail . --exclude .direnv

# Apply statix auto-fixes
lint-fix:
    statix fix .

# Evaluate the full flake (modules, shells, templates, lib).
# Flags kept in lockstep with .github/workflows/nix.yml so local and CI match.
check:
    nix flake check --all-systems --no-build --no-write-lock-file --show-trace
    nix flake check --no-write-lock-file --show-trace

# Evaluate each schematic's artefact. Schematics are separate flakes that take
# STC as `path:../..`, so they cannot be checks of this flake; their input
# follows the working tree, so this evaluates the current code. Evaluation
# only: the drvPath is computed, nothing is built. CI runs this same recipe.
# Each schematic's flake.lock records STC's own input list: after adding an
# STC input, run `nix flake update stc` in each schematic or this fails with
# "attribute '<input>' missing".
schematics:
    nix eval ./schematics/local-vm#nixosConfigurations.local-vm.config.system.build.qcow2.drvPath --no-write-lock-file
    nix eval ./schematics/aws-ami#nixosConfigurations.aws-ami.config.system.build.awsImage.drvPath --no-write-lock-file
    nix eval ./schematics/dreadnought#nixosConfigurations.dreadnought.config.system.build.toplevel.drvPath --no-write-lock-file

# Update all flake inputs
update:
    nix flake update

# Show the flake output tree
show:
    nix flake show

# Full CI gate: formatting + linting + flake check + schematics + doc parity
ci: fmt-check lint check schematics docs-parity option-priorities

# Regenerate CHANGELOG.md from Conventional Commits + tags (git-cliff).
# Pass the tag being released — `just changelog v0.8.0` — so its commits land
# under that version instead of an "unreleased" heading. Without an argument
# the already-tagged history is regenerated as-is.
# Review the diff before committing.
changelog tag="":
    git-cliff {{ if tag == "" { "" } else { "--tag " + tag } }} --output CHANGELOG.md


# ── Provings ──────────────────────────────────────────────────────────────────

# Run the provings — internal nixosTests that boot a VM per cogitator and assert
# it behaves as claimed. Heavy and manual: deliberately NOT part of `just ci`.
# Exposed via legacyPackages, which `nix flake check` skips. Linux only.
# The list is read from provings/default.nix, the same source as the CI matrix
# (.github/workflows/provings.yml), so a registered proving cannot be skipped.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for p in $(nix eval --raw .#legacyPackages.x86_64-linux.provings --no-write-lock-file \
        --apply 'p: builtins.concatStringsSep " " (builtins.attrNames p)'); do
        nix build ".#legacyPackages.x86_64-linux.provings.$p" -L --no-write-lock-file
    done


# ── Documentation ─────────────────────────────────────────────────────────────

# Regenerate the option reference fragments from the modules (docs/src/options).
# checks.options-doc fails until they are committed in step with the modules.
options-doc:
    # Built before anything is removed: a failed evaluation leaves the fragments as they were.
    out="$(nix build --no-link --print-out-paths .#legacyPackages.x86_64-linux.options-doc --no-write-lock-file)" \
        && rm -rf docs/src/options \
        && cp -rL --no-preserve=mode "$out" docs/src/options
    # Staged at once: the flake, and so checks.options-doc, only reads tracked files.
    git add docs/src/options

# Install doc dependencies (idempotent — safe to run repeatedly)
docs-install:
    cd docs && npm install

# Start the Astro dev server with live reload
docs-dev: docs-install
    cd docs && npm run dev

# Build the static documentation site
docs-build: docs-install
    cd docs && npm run build

# Preview the built site locally
docs-preview: docs-build
    cd docs && npm run preview

# Fail if the en/ and fr/ documentation trees diverge
docs-parity:
    bash scripts/check-docs-parity.sh

# Fail if an option priority is unregistered, or collides with an upstream default.
# Written after v0.18.0 demoted services.openssh.settings.X11Forwarding to
# mkDefault and broke a hardened Slurm client, which writes the same setting with
# mkDefault too. The rule was documented and still missed, because nothing
# measured it — this is the command that does.
option-priorities:
    bash scripts/check-option-priorities.sh
