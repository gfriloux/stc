---
title: Home Apps
description: Home Manager relics for GUI applications — Kitty terminal and Zen Browser.
---

Two Home Manager relics for GUI applications that carry real configuration beyond
a bare package install.

## Kitty

**Module:** `stc.homeModules.relics-kitty`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.gui.kitty.enable` | bool | `false` | Enable Kitty terminal emulator |
| `stc.gui.kitty.fonts.enable` | bool | `true` | Install a curated set of Nerd Fonts |

Enables `programs.kitty` via Home Manager. When `fonts.enable = true` (the default),
installs the following Nerd Fonts alongside Kitty:

- JetBrainsMono Nerd Font
- ProFont Nerd Font
- Inconsolata Nerd Font
- Iosevka Nerd Font
- Bitstream Vera Sans Mono Nerd Font
- Droid Sans Mono Nerd Font
- Iosevka (upstream)

```nix
modules = [ stc.homeModules.relics-kitty ];

# home.nix
{
  stc.gui.kitty.enable = true;

  # Set false to skip the Nerd Font installation
  stc.gui.kitty.fonts.enable = false;
}
```

---

## Zen Browser

**Module:** `stc.homeModules.relics-zen-browser`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.gui.zen-browser.enable` | bool | `false` | Enable Zen Browser |

Enables `programs.zen-browser` via Home Manager using the upstream
`zen-browser` flake's Home Manager module.

```nix
modules = [ stc.homeModules.relics-zen-browser ];

# home.nix
{ stc.gui.zen-browser.enable = true; }
```

:::tip[Desktop profile]
If you want kitty + zen-browser + GIMP + VLC in one option, use the
[`cogitator-desktop`](/en/cogitator/desktop/) profile instead.
:::
