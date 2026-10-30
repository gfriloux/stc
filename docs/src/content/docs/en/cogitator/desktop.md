---
title: Desktop
description: cogitator-desktop — the full GUI workstation profile for a Techpriest.
---

**Module:** `stc.homeModules.cogitator-desktop`

The Desktop profile assembles the full GUI toolkit for a workstation: a
GPU-accelerated terminal, a privacy-focused browser, an image editor, and a
media player.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stc.cogitator.desktop.enable` | bool | `false` | Enable the Desktop GUI profile |

## What It Configures

| Component | Source | Notes |
|-----------|--------|-------|
| `programs.ghostty` | `relics-ghostty` | GPU-accelerated terminal, native GTK4, extended protocol + curated Nerd Fonts |
| `programs.zen-browser` | `relics-zen-browser` | Privacy-focused Firefox fork |
| `services.gpg-agent.pinentry` | direct config | Graphical pinentry (`pinentry-qt`) |
| `pkgs.gimp` | direct package | Image editor |
| `pkgs.libnotify` | direct package | Desktop notification sender (`notify-send`) |
| `pkgs.vlc` | direct package | Media player |

GIMP, `libnotify`, and VLC are installed as plain packages — no Home Manager
program module exists for them, so there is nothing to configure beyond the
install.

### Graphical pinentry

When paired with `cogitator-enginseer`, the Desktop profile overrides the
gpg-agent pinentry with `pinentry-qt` (via `lib.mkOverride 900`), replacing the
headless-safe `pinentry-curses` default so passphrase prompts appear in a
graphical dialog. The override is inert if gpg-agent is not enabled.

Priority 900 sits between a default (1000) and a plain definition (100): it
beats enginseer's `mkDefault`, but not you. To pick another pinentry, a plain
`services.gpg-agent.pinentry.package = pkgs.pinentry-gnome3;` is enough — no
`mkForce` needed.

### Nerd Fonts

Nerd Fonts are installed through `relics-ghostty` and are on by default. To skip
them:

```nix
stc.relics.gui.ghostty.fonts.enable = false;
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

## Kitty removed in `v0.22.0`

Until `v0.21.0` the profile shipped both kitty and ghostty; since `v0.22.0` it
ships ghostty only (#1), and the Nerd Fonts follow `relics-ghostty`. If you
upgrade without changing anything, kitty and its `kitty.conf` disappear from
your profile; the fonts stay.

If your configuration still sets `stc.relics.gui.kitty.enable` (the old way to
keep ghostty only was `stc.relics.gui.kitty.enable = false;`) or
`stc.relics.gui.kitty.fonts.enable`, the build still succeeds, with an
evaluation warning: drop the line. To keep kitty, enable it yourself with
`programs.kitty.enable = true;`.

Two cases change without a warning, because they set no kitty option:

- **You kept kitty only** with `stc.relics.gui.ghostty.enable = false;`: you
  now get neither kitty nor the Nerd Fonts, which follow the ghostty relic.
  Add `programs.kitty.enable = true;` and list the fonts you want in
  `home.packages`.
- **You kept ghostty only** with `stc.relics.gui.kitty.enable = false;`: you
  had no Nerd Fonts, and now get seven font packages. Set
  `stc.relics.gui.ghostty.fonts.enable = false;` to keep the previous closure.

The GUI relics are enabled with `lib.mkDefault`, so you can take the profile
and decline any of them, for instance `stc.relics.gui.ghostty.enable = false;`.
See [Overridable defaults](/stc/en/reference/overridable-defaults/).
