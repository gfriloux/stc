---
title: Applications graphiques
description: Reliques Home Manager pour les applications graphiques — Ghostty et Zen Browser.
---

Deux reliques Home Manager pour les applications graphiques qui apportent une
vraie configuration au-delà d'une simple installation de paquet.

## Ghostty

**Module :** `stc.homeModules.relics-ghostty`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.gui.ghostty.enable` | bool | `false` | Active l'émulateur de terminal Ghostty |
| `stc.relics.gui.ghostty.fonts.enable` | bool | `true` | Installe un ensemble de Nerd Fonts sélectionnées |

Active `programs.ghostty` via Home Manager. Ghostty est un terminal accéléré GPU
écrit en Zig, avec un rendu GTK4 natif sous Linux et un protocole terminal étendu.

Quand `fonts.enable = true` (valeur par défaut), installe les polices suivantes
avec Ghostty :

- JetBrainsMono Nerd Font
- ProFont Nerd Font
- Inconsolata Nerd Font
- Iosevka Nerd Font
- Bitstream Vera Sans Mono Nerd Font
- Droid Sans Mono Nerd Font
- Iosevka (amont)

```nix
modules = [ stc.homeModules.relics-ghostty ];

# home.nix
{
  stc.relics.gui.ghostty.enable = true;

  # Mettre à false pour ne pas installer les Nerd Fonts
  stc.relics.gui.ghostty.fonts.enable = false;

  # Configurer via programs.ghostty.settings :
  programs.ghostty.settings = {
    font-size = 13;
    theme = "catppuccin-mocha";
  };
}
```

---

## Zen Browser

**Module :** `stc.homeModules.relics-zen-browser`

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.relics.gui.zen-browser.enable` | bool | `false` | Active Zen Browser |

Active `programs.zen-browser` via Home Manager en utilisant le module Home Manager
du flake upstream `zen-browser`.

```nix
modules = [ stc.homeModules.relics-zen-browser ];

# home.nix
{ stc.relics.gui.zen-browser.enable = true; }
```

:::tip[Profil Desktop]
Si tu veux ghostty + zen-browser + GIMP + VLC en une seule option, utilise le
profil [`cogitator-desktop`](/stc/fr/cogitator/desktop/) à la place.
:::

## Kitty (retirée)

La relique kitty a été retirée en `v0.22.0` (#1) : Ghostty la remplace, et les
Nerd Fonts sont passées sur `stc.relics.gui.ghostty.fonts.enable`.
`stc.homeModules.relics-kitty` existe toujours pour que son import ne casse pas
ton build, mais il ne configure plus rien : poser `stc.relics.gui.kitty.enable`
ou `stc.relics.gui.kitty.fonts.enable` (à n'importe quelle valeur, `false`
compris) lève seulement un avertissement à l'évaluation. Supprime ces lignes ;
les options elles-mêmes disparaissent à la `v1.0.0`.

Pour garder kitty, active-le toi-même avec `programs.kitty.enable = true;`.
