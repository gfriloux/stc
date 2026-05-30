---
title: Dev Shells
description: Seven pre-built development environments covering Ansible, Terraform, documentation, VM building, and NixOS operations.
---

STC provides seven dev shells. Reference them from your own flake to give your
project a reproducible development environment without maintaining the tool
definitions yourself.

## How to Use a Shell

In a plain flake:

```nix
outputs = { stc, ... }: {
  devShells.x86_64-linux.default = stc.devShells.x86_64-linux.ansible;
};
```

With flake-parts:

```nix
perSystem = { system, ... }: {
  devShells.default = stc.devShells.${system}.ansible;
};
```

Then enter the environment:

```bash
nix develop
```

All shells install a `pre-commit` configuration on entry (if one is not already
present) and wire up git hooks automatically when inside a git repository.

---

## ansible

Provides three Ansible versions simultaneously for testing against mixed
environments.

| Tool | Purpose |
|------|---------|
| `ansible` | Latest from nixpkgs unstable |
| `ansible_2_16` | Pinned version (nixos-25.05), correctly wrapped with PYTHONPATH |
| `ansible_2_17` | Pinned version (nixos-25.05), correctly wrapped with PYTHONPATH |
| `ansible-lint` | Linting playbooks |
| `ansible-recap` | Run summary formatter |
| `rbw` | Bitwarden CLI (vault access during runs) |
| `openssh_gssapi` | SSH with Kerberos/GSSAPI support |
| `shellcheck` + `shfmt` | Shell script linting |
| `just` | Task runner |
| `gum` | Interactive CLI prompts |
| `pre-commit` | Git hook runner |

On shell entry, the installed versions are printed:

```
[stc:ansible] Operational. Three ansible versions at your service.
  ansible         ansible [core 2.18.x]
  ansible_2_16    ansible [core 2.16.x]
  ansible_2_17    ansible [core 2.17.x]
```

---

## terraform

Infrastructure as Code environment with linting, security scanning, and
documentation generation.

| Tool | Purpose |
|------|---------|
| `terraform` | Main IaC tool |
| `terragrunt` | DRY wrapper for multi-environment deployments |
| `terraform-docs` | Auto-generate module documentation |
| `tflint` | Linting (deprecated syntax, type errors) |
| `tfsec` | Static security analysis |
| `just` | Task runner |
| `glow` | Markdown renderer |
| `pre-commit` | Git hook runner |

:::note[BSL license]
`terraform` from nixpkgs is the Business Source License (BSL) version
(HashiCorp changed the license in 1.6.0). If your organisation requires
an open-source license, use `opentofu` instead and adjust your flake.
:::

---

## mdbook

Rust-based documentation site generator.

| Tool | Purpose |
|------|---------|
| `mdbook` | Build and serve the book |
| `rumdl` | Markdown linting |
| `just` | Task runner |
| `glow` | Markdown preview in terminal |
| `pre-commit` | Git hook runner |

---

## mkdocs

Python-based documentation with MkDocs Material and its plugin ecosystem.

| Tool | Purpose |
|------|---------|
| `pipenv` | Python environment and dependency manager |
| `python312` + `pip` | Python runtime |
| `rumdl` | Markdown linting (Nix-level) |
| `glow` | Markdown preview |
| `pre-commit` | Git hook runner |

On shell entry, `pipenv install` runs automatically if a `Pipfile` is present.
First run requires network access. Subsequent runs use the lockfile.

---

## zensical

Python-based documentation for the Zensical generator, structured identically
to mkdocs.

| Tool | Purpose |
|------|---------|
| `pipenv` | Python environment and dependency manager |
| `python312` + `pip` | Python runtime |
| `rumdl` | Markdown linting (Nix-level) |
| `glow` | Markdown preview |
| `pre-commit` | Git hook runner |

---

## vm

Build and run NixOS VM images. The toolset covers the full build-inspect-boot cycle.

| Tool | Purpose |
|------|---------|
| `qemu` | Boot images (qemu-img for inspection, qemu-system for booting) |
| `nix-tree` | Inspect closure sizes |
| `nvd` | Compare NixOS generations |
| `nix-output-monitor` | Better `nix build` output |
| `alejandra` | Nix formatter |
| `statix` | Lint Nix for antipatterns |
| `deadnix` | Find unused bindings |
| `just` | Task runner |
| `pre-commit` | Git hook runner |

On shell entry:

```
[stc:vm] Machine-spirits awakened. The Omnissiah watches over your images.

  just build    build the qcow2 image
  just run      boot the image in QEMU/KVM
```

---

## nixos

Full NixOS operator toolkit: format, lint, secrets, deployment inspection,
and generation diffing.

| Tool | Purpose |
|------|---------|
| `alejandra` | Format `.nix` files |
| `statix` | Lint for antipatterns |
| `deadnix` | Find unused bindings |
| `nh` | Apply NixOS configurations (`nh os switch`) |
| `nvd` | Compare NixOS generations |
| `nix-tree` | Inspect closure sizes |
| `nix-output-monitor` | Better build output |
| `sops` | Secrets management |
| `serie` | Git log graph viewer |
| `trivy` | Container and filesystem vulnerability scanning |
| `tokei` | Code statistics |
| `just` | Task runner |
| `pre-commit` | Git hook runner |
