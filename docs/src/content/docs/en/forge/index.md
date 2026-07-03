---
title: Forge
description: Dev shells, disk layouts, and project templates — the STC tooling layer.
sidebar:
  order: 0
---

The Forge is the STC tooling layer: pre-built development environments, disk
partition layouts, and project templates. Nothing here touches your running system
— these are tools for building and operating.

## Overview

| Component | What it is | How to use |
|-----------|-----------|------------|
| Shells | `nix develop` environments | `stc.devShells.${system}.<name>` |
| Layouts | Disko partition definitions | `stc.lib.layouts.<name> { ... }` |
| Templates | `nix flake init` starters | `nix flake init -t github:gfriloux/stc#<name>` |
| Purity Seals | CI check builders | `stc.lib.puritySeals.${system}.<seal>` |

## Shells

Seven dev shells are available. Each provides a curated set of tools for a
specific workflow, plus `pre-commit` hooks and a `just` task runner.

| Shell | Key tools |
|-------|-----------|
| `ansible` | ansible (3 versions), ansible-lint, rbw, shellcheck |
| `terraform` | terraform, terragrunt, tflint, tfsec, terraform-docs |
| `mdbook` | mdbook, rumdl |
| `mkdocs` | pipenv, python312, rumdl |
| `zensical` | pipenv, python312, rumdl |
| `vm` | qemu, nix-tree, nvd, alejandra, statix, deadnix |
| `nixos` | alejandra, statix, deadnix, nh, nvd, sops, trivy |

Full documentation: [Forge — Shells](/stc/en/forge/shells/)

## Layouts

One layout is available for QEMU/KVM virtual machines:

| Layout | Function signature | What it creates |
|--------|-------------------|-----------------|
| `zfs-local-vm` | `{ poolName ? "vmpool" }` | EFI 1G + ZFS remainder, three datasets |

Full documentation: [Forge — Layouts](/stc/en/forge/layouts/)

## Templates

Five project templates bootstrap new repositories with a dev shell and CI checks:

| Template | `nix flake init` command |
|----------|--------------------------|
| `ansible` | `nix flake init -t github:gfriloux/stc#ansible` |
| `terraform` | `nix flake init -t github:gfriloux/stc#terraform` |
| `mdbook` | `nix flake init -t github:gfriloux/stc#mdbook` |
| `mkdocs` | `nix flake init -t github:gfriloux/stc#mkdocs` |
| `zensical` | `nix flake init -t github:gfriloux/stc#zensical` |

Full documentation: [Forge — Templates](/stc/en/forge/templates/)

## Purity Seals

Six CI check builders. A passing seal stamps a source tree as inspected and free
of heresy — no dead Nix, no antipatterns, no leaked secrets, clean formatting.

| Seal | What it runs |
|------|--------------|
| `nix` | deadnix + statix + alejandra |
| `gitleaks` | gitleaks secret scan |
| `terraform` | terraform fmt + tflint + tfsec |
| `ansible` | ansible-lint (production profile) |
| `shell` | shellcheck + shfmt |
| `markdown` | rumdl |

Full documentation: [Forge — Purity Seals](/stc/en/forge/purity-seals/)
