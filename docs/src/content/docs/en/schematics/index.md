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
- One or more module files (`qcow2.nix`, `image.nix`) — image builder overrides
- `Justfile` — task runner with standard recipes (build, run, publish, ssh)

The `flake.nix` in a schematic shows exactly which STC modules are imported and
what configuration values they need. The comments explain the non-obvious choices.

Each schematic contains a Justfile with build / run / ssh recipes.

## Available Schematics

| Schematic | What it builds | Key STC components |
|-----------|---------------|-------------------|
| `local-vm` | QEMU/KVM development VM with ZFS + impermanence | relics-boot, relics-zfs, relics-impermanence, cogitator-hardening, cogitator-vm, zfs-local-vm layout |
| `aws-ami` | AWS EC2 AMI with ZFS + impermanence + hardening | relics-boot, relics-zfs, relics-aws, relics-impermanence, cogitator-hardening, zfs-local-vm layout |

## See Also

- [local-vm schematic](/stc/en/schematics/local-vm/)
- [aws-ami schematic](/stc/en/schematics/aws-ami/)
