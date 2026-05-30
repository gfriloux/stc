---
title: Templates
description: Cinq templates de flakes pour démarrer des projets Ansible, Terraform, mdBook, MkDocs et Zensical.
---

STC livre cinq templates de projets. Chacun initialise un nouveau flake avec le dev
shell STC correspondant et des checks CI pré-câblés.

## Comment utiliser

```bash
mkdir mon-projet && cd mon-projet
nix flake init -t github:gfriloux/stc#ansible
```

Ceci écrit un `flake.nix` dans le répertoire courant. Commite-le, puis exécute
`nix develop` pour entrer dans l'environnement de développement.

## Templates disponibles

| Template | Commande |
|----------|---------|
| `ansible` | `nix flake init -t github:gfriloux/stc#ansible` |
| `terraform` | `nix flake init -t github:gfriloux/stc#terraform` |
| `mdbook` | `nix flake init -t github:gfriloux/stc#mdbook` |
| `mkdocs` | `nix flake init -t github:gfriloux/stc#mkdocs` |
| `zensical` | `nix flake init -t github:gfriloux/stc#zensical` |

---

## ansible

Fournit :
- `devShells.default` = `stc.devShells.${system}.ansible`
- Checks CI : `nix`, `gitleaks`, `ansible`, `shell`
- Supporte : `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`

```bash
mkdir mes-playbooks && cd mes-playbooks
nix flake init -t github:gfriloux/stc#ansible
nix develop
```

---

## terraform

Fournit :
- `devShells.default` = `stc.devShells.${system}.terraform`
- Checks CI : `nix`, `gitleaks`, `terraform`
- Supporte : `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`

```bash
mkdir mon-infra && cd mon-infra
nix flake init -t github:gfriloux/stc#terraform
nix develop
```

---

## mdbook

Fournit :
- `devShells.default` = `stc.devShells.${system}.mdbook`

```bash
mkdir mon-livre && cd mon-livre
nix flake init -t github:gfriloux/stc#mdbook
nix develop
mdbook init    # initialiser un nouveau livre si tu pars de zéro
```

---

## mkdocs

Fournit :
- `devShells.default` = `stc.devShells.${system}.mkdocs`

```bash
mkdir mes-docs && cd mes-docs
nix flake init -t github:gfriloux/stc#mkdocs
nix develop
# pipenv install s'exécute automatiquement ; ajoute mkdocs-material à ton Pipfile
```

---

## zensical

Fournit :
- `devShells.default` = `stc.devShells.${system}.zensical`
- Un `Justfile`, un `Pipfile`, et un `zensical.toml` de démarrage

```bash
mkdir mes-docs && cd mes-docs
nix flake init -t github:gfriloux/stc#zensical
nix develop
```

:::tip[Checks CI via stc.inputs.nix-checks]
Les templates ansible et terraform câblent `stc.inputs.nix-checks.lib.${system}.checks`
pour leurs définitions de checks CI. Tu peux ajouter les mêmes checks à n'importe quel
flake qui utilise STC comme input.
:::
