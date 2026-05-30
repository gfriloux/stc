---
title: Applications graphiques
description: Reliques Home Manager pour les applications graphiques — terminal Kitty et Zen Browser.
---

Deux reliques Home Manager pour les applications graphiques qui apportent une
vraie configuration au-delà d'une simple installation de paquet.

## Kitty

**Module :** `stc.homeModules.relics-kitty`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.gui.kitty.enable` | bool | `false` | Active l'émulateur de terminal Kitty |
| `stc.gui.kitty.fonts.enable` | bool | `true` | Installe un ensemble de Nerd Fonts sélectionnées |

Active `programs.kitty` via Home Manager. Quand `fonts.enable = true` (valeur par défaut),
installe les Nerd Fonts suivantes avec Kitty :

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

  # Poser false pour ignorer l'installation des Nerd Fonts
  stc.gui.kitty.fonts.enable = false;
}
```

---

## Zen Browser

**Module :** `stc.homeModules.relics-zen-browser`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.gui.zen-browser.enable` | bool | `false` | Active Zen Browser |

Active `programs.zen-browser` via Home Manager en utilisant le module Home Manager
du flake upstream `zen-browser`.

```nix
modules = [ stc.homeModules.relics-zen-browser ];

# home.nix
{ stc.gui.zen-browser.enable = true; }
```

:::tip[Profil Desktop]
Si tu veux kitty + zen-browser + GIMP + VLC en une seule option, utilise le
profil [`cogitator-desktop`](/fr/cogitator/desktop/) à la place.
:::
