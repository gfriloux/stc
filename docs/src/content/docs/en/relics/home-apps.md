---
title: Home Apps
description: Home Manager relics for GUI applications — Ghostty and Zen Browser.
---

Two Home Manager relics for GUI applications that carry real configuration beyond
a bare package install.

## Ghostty

**Module:** `stc.homeModules.relics-ghostty`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.gui.ghostty.enable` | bool | `false` | Enable Ghostty terminal emulator |
| `stc.relics.gui.ghostty.fonts.enable` | bool | `true` | Install a curated set of Nerd Fonts |

Enables `programs.ghostty` via Home Manager. Ghostty is a GPU-accelerated terminal
written in Zig, with a native GTK4 renderer on Linux and an extended terminal
protocol.

When `fonts.enable = true` (the default), installs the following fonts alongside
Ghostty:

- JetBrainsMono Nerd Font
- ProFont Nerd Font
- Inconsolata Nerd Font
- Iosevka Nerd Font
- Bitstream Vera Sans Mono Nerd Font
- Droid Sans Mono Nerd Font
- Iosevka (upstream)

```nix
modules = [ stc.homeModules.relics-ghostty ];

# home.nix
{
  stc.relics.gui.ghostty.enable = true;

  # Set false to skip the Nerd Font installation
  stc.relics.gui.ghostty.fonts.enable = false;

  # Configure via programs.ghostty.settings:
  programs.ghostty.settings = {
    font-size = 13;
    theme = "catppuccin-mocha";
  };
}
```

---

## Zen Browser

**Module:** `stc.homeModules.relics-zen-browser`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.relics.gui.zen-browser.enable` | bool | `false` | Enable Zen Browser |

Enables `programs.zen-browser` via Home Manager using the upstream
`zen-browser` flake's Home Manager module.

```nix
modules = [ stc.homeModules.relics-zen-browser ];

# home.nix
{ stc.relics.gui.zen-browser.enable = true; }
```

:::tip[Desktop profile]
If you want ghostty + zen-browser + GIMP + VLC in one option, use the
[`cogitator-desktop`](/stc/en/cogitator/desktop/) profile instead.
:::

## Kitty (removed)

The kitty relic was removed in `v0.22.0` (#1); Ghostty replaces it, and the Nerd
Fonts moved to `stc.relics.gui.ghostty.fonts.enable`. `stc.homeModules.relics-kitty`
still exists so that importing it does not break your build, but it configures
nothing: setting `stc.relics.gui.kitty.enable` or `stc.relics.gui.kitty.fonts.enable`
(to any value, `false` included) only raises an evaluation warning. Drop those
lines; the options themselves disappear at `v1.0.0`.

To keep kitty, enable it yourself with `programs.kitty.enable = true;`.
