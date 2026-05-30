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

# Evaluate the full flake (modules, shells, templates, lib)
check:
    nix flake check --show-trace

# Update all flake inputs
update:
    nix flake update

# Show the flake output tree
show:
    nix flake show

# Full CI gate: formatting + linting + flake check
ci: fmt-check lint check


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
