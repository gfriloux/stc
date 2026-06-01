---
title: Plasma Desktop
description: cogitator-plasma — KDE Plasma 6 Wayland desktop composed with Pipewire audio in a single enable option.
---

**Module:** `stc.nixosModules.cogitator-plasma`

**Enable option:** `stc.cogitator.plasma.enable`

Composes the Plasma 6 and Pipewire relics into a complete KDE desktop profile.
One option replaces manually enabling and wiring two relics.

## What it composes

| Relic | Enable option set | Purpose |
|-------|-------------------|---------|
| `relics-plasma6` | `stc.plasma6.enable = true` | SDDM + Wayland + Plasma 6 + XDG portals |
| `relics-pipewire` | `stc.pipewire.enable = true` | RTKit + Pipewire + ALSA 32-bit + PulseAudio compat |

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.plasma.enable` | bool | `false` | Enable the Plasma desktop profile |

Underlying relic options remain tunable after activation:

```nix
stc.plasma6.keyboardLayout = "fr";           # keyboard layout
stc.plasma6.sddmTheme = "catppuccin-mocha-mauve";  # SDDM theme
```

## Usage Example

```nix
modules = [
  stc.nixosModules.cogitator-plasma
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.plasma.enable = true;

  # Tune the underlying relics as needed:
  stc.plasma6.keyboardLayout = "fr";
  stc.plasma6.sddmTheme = "catppuccin-mocha-mauve";
  environment.systemPackages = [ pkgs.catppuccin-sddm ];
}
```

## See Also

- [Plasma 6 relic](/stc/en/relics/plasma6/) — standalone Plasma 6 module
- [Pipewire relic](/stc/en/relics/pipewire/) — standalone audio module
- [cogitator-gaming](/stc/en/cogitator/gaming/) — gaming profile, also composes Pipewire
