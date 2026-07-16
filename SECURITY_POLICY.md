# STC — Security Policy

## Reporting vulnerabilities

Open a private GitHub Security Advisory on this repository. Do not use public issues for vulnerability reports.

## Dependency posture

STC depends on a mix of nix-community projects and personal flakes. This document is explicit about the trust level of each.

### Tier 1 — nix-community (high trust)

Maintained by the nix-community organisation with multiple maintainers and CI.

| Input | Repository |
|-------|-----------|
| `nixpkgs` | github:nixos/nixpkgs |
| `home-manager` | github:nix-community/home-manager |
| `disko` | github:nix-community/disko |
| `impermanence` | github:nix-community/impermanence |
| `sops-nix` | github:Mic92/sops-nix |
| `catppuccin` | github:catppuccin/nix |
| `plasma-manager` | github:nix-community/plasma-manager |

### Tier 2 — project owner (medium trust)

Flakes authored and maintained by the STC project owner. Source is auditable by project contributors.

| Input | Repository |
|-------|-----------|
| `gitflow-toolkit` | github:gfriloux/gitflow-toolkit-flake |
| `television-ssh` | github:gfriloux/television-ssh-flake |
| `ansible-recap` | github:gfriloux/ansible-recap |
| `nix-checks` | github:gfriloux/nix-checks |

### Tier 3 — third-party individual (lower trust)

Maintained by individual accounts outside nix-community or the project owner. These carry supply chain risk.

| Input | Repository | Risk |
|-------|-----------|------|
| `zen-browser` | github:0xc000022070/zen-browser-flake | Unofficial wrapper by an individual account. No official Zen Browser Nix package exists as of 2026. Monitor for ownership changes or unexpected commits. |

**Mitigation for `zen-browser`:** the flake is pinned in `flake.lock`. Updates only happen on explicit `nix flake update`. Review the diff before updating.

## Diamond dependencies

Two inputs (`gitflow-toolkit`, `television-ssh`) use `snowfall-lib`, which pulls `flake-utils-plus` at a pinned revision. This creates duplicate entries in the lock file (`flake-utils-plus`, `flake-compat`) that cannot be deduplicated via `.follows`.

This is a known limitation, not a security issue. The duplicated packages are build tools only and do not appear in any system closure.

## Supply chain checklist for contributors

When adding a new flake input:

1. Prefer `nix-community` or well-known organisations over individual accounts.
2. Add `inputs.nixpkgs.follows = "nixpkgs"` (and `home-manager.follows` where applicable).
3. Document the new dependency in this file under the appropriate trust tier.
4. If the dependency is Tier 3, note the specific risk and mitigation.

## devShell packages

The `devShells.default` shell installs `alejandra`, `statix`, `deadnix`, `just`, `git`, and `nix-tree` — all sourced from nixpkgs. No third-party binary downloads occur during dev environment setup.
