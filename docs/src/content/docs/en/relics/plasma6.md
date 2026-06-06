---
title: Plasma 6
description: KDE Plasma 6 relic — Wayland-first desktop with SDDM, XDG portals, and configurable keyboard layout and theme.
---

**Module:** `stc.nixosModules.relics-plasma6`

**Enable option:** `stc.relics.plasma6.enable`

Configures a Wayland-first KDE Plasma 6 desktop. SDDM runs under Wayland, Plasma
6 is the desktop manager, and the XDG portal stack is enabled for screen sharing
and file picker integration. Thumbnail generation (tumbler), virtual filesystem
(gvfs), and input handling (libinput) are included. The X11 server is disabled.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.plasma6.enable` | bool | `false` | Enable KDE Plasma 6 |
| `stc.relics.plasma6.keyboardLayout` | string | `"us"` | xkb keyboard layout for SDDM and Plasma |
| `stc.relics.plasma6.sddmTheme` | string | `""` | SDDM theme name — empty string uses SDDM default |
| `stc.relics.plasma6.wayland` | bool | `true` | Use Wayland for the SDDM greeter. Set to `false` to fall back to X11 (older or incompatible GPUs). |

### `sddmTheme`

The relic sets `services.displayManager.sddm.theme` to this value but does **not**
install any theme package. When using a custom theme, add the package yourself:

```nix
environment.systemPackages = [ pkgs.catppuccin-sddm ];
stc.relics.plasma6.sddmTheme = "catppuccin-mocha-mauve";
```

## What it configures

```
services.displayManager.sddm.enable = true
services.displayManager.sddm.wayland.enable = <wayland>
services.displayManager.sddm.theme = <sddmTheme>
services.desktopManager.plasma6.enable = true
services.gvfs.enable = true
services.tumbler.enable = true
services.libinput.enable = true
services.xserver.enable = false
services.xserver.xkb.layout = <keyboardLayout>
xdg.portal.enable = true
xdg.portal.config.common.default = "*"
systemd.user.services.wireplumber.wantedBy = [ "default.target" ]
```

WirePlumber is explicitly added to `default.target` so audio initialises reliably
when Plasma starts. Pair with [`relics-pipewire`](/stc/en/relics/pipewire/) for a
complete audio stack — or use [`cogitator-plasma`](/stc/en/cogitator/plasma/) which
composes both relics.

## Usage Example

```nix
modules = [
  stc.nixosModules.relics-plasma6
  stc.nixosModules.relics-pipewire
  ./configuration.nix
];

# configuration.nix
{
  stc.relics.plasma6.enable = true;
  stc.relics.plasma6.keyboardLayout = "fr";
  stc.relics.plasma6.sddmTheme = "catppuccin-mocha-mauve";

  stc.relics.pipewire.enable = true;

  environment.systemPackages = [ pkgs.catppuccin-sddm ];
}
```

## See Also

- [cogitator-plasma](/stc/en/cogitator/plasma/) — composes this relic with Pipewire in one enable option
- [Pipewire](/stc/en/relics/pipewire/) — audio relic, required for desktop audio
