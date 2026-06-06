---
title: Desktop
description: cogitator-desktop — the full GUI workstation profile for a Techpriest.
---

**Module:** `stc.homeModules.cogitator-desktop`

The Desktop profile assembles the full GUI toolkit for a workstation: two
GPU-accelerated terminals, a privacy-focused browser, an image editor, and a
media player.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.desktop.enable` | bool | `false` | Enable the Desktop GUI profile |

## What It Configures

| Component | Source | Notes |
|-----------|--------|-------|
| `programs.kitty` | `relics-kitty` | GPU-accelerated terminal + curated Nerd Fonts |
| `programs.ghostty` | `relics-ghostty` | GPU-accelerated terminal, native GTK4, extended protocol |
| `programs.zen-browser` | `relics-zen-browser` | Privacy-focused Firefox fork |
| `pkgs.gimp` | direct package | Image editor |
| `pkgs.vlc` | direct package | Media player |

GIMP and VLC are installed as plain packages — no Home Manager program module
exists for them, so there is nothing to configure beyond the install.

Kitty and Ghostty coexist without conflict — each has its own `programs.*`
namespace. Nerd Fonts are installed via `relics-kitty` and are available to
both terminals.

Kitty's Nerd Font installation is on by default. To skip it:

```nix
stc.relics.gui.kitty.fonts.enable = false;
```

## Usage Example

```nix
# flake.nix
outputs = { nixpkgs, stc, home-manager, ... }: {
  homeConfigurations."alice@workstation" = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      stc.homeModules.cogitator-desktop
      ./home.nix
    ];
  };
};

# home.nix
{
  stc.cogitator.desktop.enable = true;

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.11";
}
```

:::note[zen-browser module]
The Desktop profile imports `inputs.zen-browser.homeModules.beta` automatically.
The upstream `zen-browser` flake is bundled as an STC input — you do not need to
add it yourself. If you already have it, there is no conflict.
:::
