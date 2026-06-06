---
title: Schematics
description: Complete consumer flake examples — read them to understand how STC pieces fit together in practice.
sidebar:
  order: 0
---

A schematic is a complete, working consumer flake. It is not a library, not an
abstract example — it is a real `flake.nix` with all required inputs, modules,
and configuration that you can copy and adapt.

Schematics serve two purposes:

1. **Learning** — see how STC modules are wired together in a realistic scenario
2. **Starting point** — copy the schematic that matches your use case and adapt it

## How to Read a Schematic

Each schematic consists of:

- `flake.nix` — the root flake with inputs and `nixosConfigurations`
- `Justfile` — task runner with standard recipes (build, deploy, run, ssh)

The `flake.nix` in a schematic shows exactly which STC modules are imported and
what configuration values they need. The comments explain the non-obvious choices.

Each schematic contains a Justfile with build / run / ssh recipes.

:::note[Each schematic has its own flake.lock]
Schematics pin STC as `stc.url = "path:../.."` and carry their **own**
`flake.lock`. This is a deliberate trade-off: it keeps each schematic
self-contained and runnable on its own, but it is a second source of truth for
`nixpkgs` (it can drift from the repo-root lock) and the lock goes stale
whenever the parent repo changes. After updating STC, run `nix flake update stc`
inside the schematic you are working with to refresh its pin.
:::

## Available Schematics

| Schematic | What it builds | Key STC components |
|-----------|---------------|-------------------|
| `local-vm` | QEMU/KVM development VM with ZFS + impermanence | `cogitator-sarcophagus-kvm`, `cogitator-vm` |
| `aws-ami` | AWS EC2 AMI with ZFS + impermanence + hardening | `cogitator-sarcophagus-aws` |
| `dreadnought` | NixOS EC2 instance managed via deploy-rs | `cogitator-dreadnought` |

## See Also

- [local-vm schematic](/stc/en/schematics/local-vm/)
- [aws-ami schematic](/stc/en/schematics/aws-ami/)
- [dreadnought schematic](/stc/en/schematics/dreadnought/)
