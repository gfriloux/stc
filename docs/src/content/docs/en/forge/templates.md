---
title: Templates
description: Five flake templates to bootstrap Ansible, Terraform, mdBook, MkDocs, and Zensical projects.
---

STC ships five project templates. Each initialises a new flake with the matching
STC dev shell and CI checks pre-wired.

## How to Use

```bash
mkdir my-project && cd my-project
nix flake init -t github:gfriloux/stc#ansible
```

This writes a `flake.nix` into the current directory. Commit it, then run
`nix develop` to enter the development environment.

## Available Templates

| Template | Command |
|----------|---------|
| `ansible` | `nix flake init -t github:gfriloux/stc#ansible` |
| `terraform` | `nix flake init -t github:gfriloux/stc#terraform` |
| `mdbook` | `nix flake init -t github:gfriloux/stc#mdbook` |
| `mkdocs` | `nix flake init -t github:gfriloux/stc#mkdocs` |
| `zensical` | `nix flake init -t github:gfriloux/stc#zensical` |

---

## ansible

Provides:
- `devShells.default` = `stc.devShells.${system}.ansible`
- CI checks: `nix`, `gitleaks`, `ansible`, `shell`
- Supports: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`

```bash
mkdir my-playbooks && cd my-playbooks
nix flake init -t github:gfriloux/stc#ansible
nix develop
```

---

## terraform

Provides:
- `devShells.default` = `stc.devShells.${system}.terraform`
- CI checks: `nix`, `gitleaks`, `terraform`
- Supports: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`

```bash
mkdir my-infra && cd my-infra
nix flake init -t github:gfriloux/stc#terraform
nix develop
```

---

## mdbook

Provides:
- `devShells.default` = `stc.devShells.${system}.mdbook`

```bash
mkdir my-book && cd my-book
nix flake init -t github:gfriloux/stc#mdbook
nix develop
mdbook init    # initialise a new book if starting fresh
```

---

## mkdocs

Provides:
- `devShells.default` = `stc.devShells.${system}.mkdocs`

```bash
mkdir my-docs && cd my-docs
nix flake init -t github:gfriloux/stc#mkdocs
nix develop
# pipenv install runs automatically; add mkdocs-material to your Pipfile
```

---

## zensical

Provides:
- `devShells.default` = `stc.devShells.${system}.zensical`
- A `Justfile`, `Pipfile`, and `zensical.toml` starter

```bash
mkdir my-docs && cd my-docs
nix flake init -t github:gfriloux/stc#zensical
nix develop
```

:::tip[CI checks via Purity Seals]
Every template wires up its CI checks through `stc.lib.puritySeals.${system}` — STC's
own public API, no longer a private input. You can add the same seals to any flake that
uses STC as an input. See [Purity Seals](/stc/en/forge/purity-seals/).
:::
