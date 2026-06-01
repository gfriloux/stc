---
title: Boot
description: Generic systemd-boot + EFI bootloader configuration.
---

**Module:** `stc.nixosModules.relics-boot`

Configures the bootloader. Nothing more. No kernel selection, no filesystem
support — those are concerns for the relevant technology relic (`relics-zfs`,
etc.).

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.boot.enable` | bool | `false` | Enable systemd-boot + EFI bootloader configuration |

## What It Does

When enabled:

- Sets `boot.loader.systemd-boot.enable = true`
- Sets `boot.loader.efi.canTouchEfiVariables = true`

## Usage Example

```nix
modules = [
  stc.nixosModules.relics-boot
  ./configuration.nix
];

# configuration.nix
{ stc.boot.enable = true; }
```

## Pair With

- [`relics-zfs`](/stc/en/relics/zfs/) — ZFS-compatible kernel, filesystem support, pool maintenance
- [`relics-impermanence`](/stc/en/relics/impermanence/) — root rollback at each boot
