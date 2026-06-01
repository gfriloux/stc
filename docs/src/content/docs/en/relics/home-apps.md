---
title: Home Apps
description: Home Manager relics for GUI applications — Kitty, Ghostty, and Zen Browser.
---

Three Home Manager relics for GUI applications that carry real configuration beyond
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

## Ghostty

**Module:** `stc.homeModules.relics-ghostty`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.gui.ghostty.enable` | bool | `false` | Enable Ghostty terminal emulator |

Enables `programs.ghostty` via Home Manager. Ghostty is a GPU-accelerated terminal
with a native GTK4 renderer on Linux, an extended terminal protocol, and a Rust/Zig
implementation.

Ghostty and Kitty can coexist — each has its own configuration namespace and binary.

```nix
modules = [ stc.homeModules.relics-ghostty ];

# home.nix
{
  stc.gui.ghostty.enable = true;

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
| `stc.gui.zen-browser.enable` | bool | `false` | Enable Zen Browser |

Enables `programs.zen-browser` via Home Manager using the upstream
`zen-browser` flake's Home Manager module.

```nix
modules = [ stc.homeModules.relics-zen-browser ];

# home.nix
{ stc.gui.zen-browser.enable = true; }
```

:::tip[Desktop profile]
If you want kitty + ghostty + zen-browser + GIMP + VLC in one option, use the
[`cogitator-desktop`](/stc/en/cogitator/desktop/) profile instead.
:::
