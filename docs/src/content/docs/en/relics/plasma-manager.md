---
title: Plasma Manager
description: plasma-manager relic — declarative KDE Plasma configuration via Home Manager, without touching ~/.config manually.
---

**Module:** `stc.homeModules.relics-plasma-manager`

**Enable option:** `stc.plasmaManager.enable`

Activates [plasma-manager](https://github.com/nix-community/plasma-manager), the
Home Manager module for declarative KDE configuration. Once enabled, the entire
KDE desktop setup (theme, workspace, shortcuts, panels, widgets, cursor) is
declared in `programs.plasma.*` and applied on each Home Manager activation.

The upstream `plasma-manager` flake is already wired as an STC input — consumers
do **not** need to add it to their own `flake.nix`.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.plasmaManager.enable` | bool | `false` | Enable plasma-manager declarative KDE configuration |

All KDE configuration is done through `programs.plasma.*` options provided by
plasma-manager itself — STC does not wrap them.

## Usage Example

```nix
# flake.nix
homeManagerModules = [ stc.homeModules.relics-plasma-manager ];

# home.nix
{
  stc.plasmaManager.enable = true;

  programs.plasma = {
    workspace = {
      lookAndFeel = "Catppuccin-Mocha-Global";
      colorScheme = "CatppuccinMocha";
      iconTheme = "Papirus-Dark";
      cursor = {
        theme = "Catppuccin-Mocha-Dark-Cursors";
        size = 24;
      };
    };
  };
}
```

:::note[Theme packages]
`programs.plasma.workspace.*` sets theme names as strings. The corresponding
theme packages (Catppuccin, Papirus, etc.) must be installed separately — add
them to `home.packages` or `environment.systemPackages`.
:::

## What it configures

```
programs.plasma.enable = true   # via stc.plasmaManager.enable
```

Everything else — workspace appearance, shortcuts, panels, widgets — is
configured directly through `programs.plasma.*` options after enabling the relic.
Refer to the [plasma-manager documentation](https://github.com/nix-community/plasma-manager)
for the full option reference.

## See Also

- [Plasma 6 relic](/stc/en/relics/plasma6/) — system-level Plasma 6 setup (NixOS)
- [cogitator-plasma](/stc/en/cogitator/plasma/) — NixOS Plasma + Pipewire profile
