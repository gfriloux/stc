---
title: Architecture
description: How the STC is structured and why.
---

## The Grand Design

The STC is built around a single principle: **STC is a library, not a system.**

Your flake declares your machines. STC provides the modules those machines import.
There are no `nixosConfigurations` in STC, no `homeConfigurations`, no opinions about
what your system should look like. Only tools.

## The Chambers of the Archivum

```
stc/
├── relics/        Atomic modules — one concern per relic
│   ├── nixos/     NixOS modules
│   └── home/      Home Manager modules
│
├── cogitator/     Profiles — relics assembled for a purpose
│   ├── nixos/     NixOS profiles
│   └── home/      Home Manager profiles
│
├── forge/         Dev shells, disk layouts, project templates
│   ├── shells/    Development environments (ansible, terraform, vm, …)
│   ├── layouts/   Disko partition layouts
│   └── templates/ Project starters (ansible, terraform, etc.)
│
└── schematics/    Example consumer flakes
```

## Naming Conventions

STC modules are exposed in two namespaces:

| Output | Prefix | Example |
|--------|--------|---------|
| `nixosModules` | `relics-` | `stc.nixosModules.relics-networking` |
| `nixosModules` | `cogitator-` | `stc.nixosModules.cogitator-hardening` |
| `homeModules` | `relics-` | `stc.homeModules.relics-kitty` |
| `homeModules` | `cogitator-` | `stc.homeModules.cogitator-enginseer` |
| `devShells` | — | `stc.devShells.${system}.ansible` |
| `templates` | — | `nix flake init -t github:gfriloux/stc#ansible` |
| `lib` | — | `stc.lib.layouts.zfs-local-vm` |

## Options Namespace

All STC options live under `stc.*`:

```nix
stc.relics.networking.enable = true;
stc.relics.gui.zen-browser.enable = true;
stc.relics.docker.crowdsec.dataDir = "/srv/docker/crowdsec";
```

No collision with other modules. No surprises.

## Relics vs Cogitators

**Relics** are atomic. Each one controls a single concern and has its own `enable` option.
Import only what you need:

```nix
modules = [
  stc.nixosModules.relics-boot
  stc.nixosModules.relics-zfs
  stc.nixosModules.relics-networking
];
```

**Cogitator profiles** are composed relics. They group related relics under a single
`enable` toggle for common use cases:

```nix
modules = [
  stc.nixosModules.cogitator-hardening   # enables kernel + network + filesystem + SSH hardening
];
```

Use cogitators when the defaults suit you. Use individual relics when you need
surgical control.

## Framework

STC uses [flake-parts](https://flake.parts) as its structuring framework. This gives
complete freedom over directory naming (hence the Warhammer-themed layout) while
keeping outputs well-defined and composable.

## Secrets

STC is **secrets-agnostic**. Modules that need secrets expose a `*File` option
pointing to a file path. How that file gets there is your concern, not STC's:

```nix
# sops-nix example
stc.relics.docker.traefik.dynamicConfigFile = config.sops.secrets."traefik/dynamic".path;

# agenix example
stc.relics.docker.crowdsec.envFile = config.age.secrets.crowdsec-env.path;
```

Whether you use sops-nix, agenix, or a shell script of dubious provenance from
the Age of Strife, STC accepts a path and asks no further questions.
