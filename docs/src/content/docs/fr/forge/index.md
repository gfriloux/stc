---
title: Forge
description: Dev shells, layouts de disques et templates de projets — la couche d'outillage STC.
sidebar:
  order: 0
---

La Forge est la couche d'outillage STC : environnements de développement pré-construits,
layouts de partitions de disque, et templates de projets. Rien ici ne touche ton système
en cours d'exécution — ce sont des outils pour construire et opérer.

## Vue d'ensemble

| Composant | Ce que c'est | Comment l'utiliser |
|-----------|--------------|-------------------|
| Shells | Environnements `nix develop` | `stc.devShells.${system}.<nom>` |
| Layouts | Définitions de partitions Disko | `stc.lib.layouts.<nom> { ... }` |
| Templates | Starters `nix flake init` | `nix flake init -t github:gfriloux/stc#<nom>` |

## Shells

Sept dev shells sont disponibles. Chacun fournit un ensemble curé d'outils pour
un workflow spécifique, plus des hooks `pre-commit` et un exécuteur de tâches `just`.

| Shell | Outils clés |
|-------|-------------|
| `ansible` | ansible (3 versions), ansible-lint, rbw, shellcheck |
| `terraform` | terraform, terragrunt, tflint, tfsec, terraform-docs |
| `mdbook` | mdbook, rumdl |
| `mkdocs` | pipenv, python312, rumdl |
| `zensical` | pipenv, python312, rumdl |
| `vm` | qemu, nix-tree, nvd, alejandra, statix, deadnix |
| `nixos` | alejandra, statix, deadnix, nh, nvd, sops, trivy |

Documentation complète : [Forge — Shells](/stc/fr/forge/shells/)

## Layouts

Un layout est disponible pour les machines virtuelles QEMU/KVM :

| Layout | Signature de fonction | Ce qu'il crée |
|--------|----------------------|---------------|
| `zfs-local-vm` | `{ poolName ? "vmpool" }` | EFI 1G + reste ZFS, trois datasets |

Documentation complète : [Forge — Layouts](/stc/fr/forge/layouts/)

## Templates

Cinq templates de projets initialisent de nouveaux dépôts avec un dev shell et des checks CI :

| Template | Commande `nix flake init` |
|----------|---------------------------|
| `ansible` | `nix flake init -t github:gfriloux/stc#ansible` |
| `terraform` | `nix flake init -t github:gfriloux/stc#terraform` |
| `mdbook` | `nix flake init -t github:gfriloux/stc#mdbook` |
| `mkdocs` | `nix flake init -t github:gfriloux/stc#mkdocs` |
| `zensical` | `nix flake init -t github:gfriloux/stc#zensical` |

Documentation complète : [Forge — Templates](/stc/fr/forge/templates/)
