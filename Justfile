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
    nix flake check --no-write-lock-file --show-trace

# Update all flake inputs
update:
    nix flake update

# Show the flake output tree
show:
    nix flake show

# Full CI gate: formatting + linting + flake check + doc parity
ci: fmt-check lint check docs-parity


# ── Provings ──────────────────────────────────────────────────────────────────

# Run the provings — internal nixosTests that boot a VM per cogitator and assert
# it behaves as claimed. Heavy and manual: deliberately NOT part of `just ci`.
# Exposed via legacyPackages, which `nix flake check` skips. Linux only.
test:
    nix build .#legacyPackages.x86_64-linux.provings.hardening -L --no-write-lock-file
    nix build .#legacyPackages.x86_64-linux.provings.docker-server -L --no-write-lock-file


# ── Documentation ─────────────────────────────────────────────────────────────

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
