---
title: Bureau Plasma
description: cogitator-plasma — bureau KDE Plasma 6 Wayland composé avec l'audio Pipewire en une seule option.
---

**Module :** `stc.nixosModules.cogitator-plasma`

**Option d'activation :** `stc.cogitator.plasma.enable`

Compose les reliques Plasma 6 et Pipewire en un profil bureau KDE complet.
Une seule option remplace l'activation et le câblage manuel de deux reliques.

## Ce que ça compose

| Relique | Option activée | Rôle |
|---------|----------------|------|
| `relics-plasma6` | `stc.relics.plasma6.enable = true` | SDDM + Wayland + Plasma 6 + portails XDG |
| `relics-pipewire` | `stc.relics.pipewire.enable = true` | RTKit + Pipewire + ALSA 32 bits + compat PulseAudio |

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.plasma.enable` | bool | `false` | Active le profil bureau Plasma |

Les options des reliques sous-jacentes restent réglables après activation :

```nix
stc.relics.plasma6.keyboardLayout = "fr";                 # disposition clavier
stc.relics.plasma6.sddmTheme = "catppuccin-mocha-mauve";  # thème SDDM
```

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.cogitator-plasma
  ./configuration.nix
];

# configuration.nix
{
  stc.cogitator.plasma.enable = true;

  # Réglages des reliques sous-jacentes si nécessaire :
  stc.relics.plasma6.keyboardLayout = "fr";
  stc.relics.plasma6.sddmTheme = "catppuccin-mocha-mauve";
  environment.systemPackages = [ pkgs.catppuccin-sddm ];
}
```

## Voir aussi

- [Relique Plasma 6](/stc/fr/relics/plasma6/) — module Plasma 6 autonome
- [Relique Pipewire](/stc/fr/relics/pipewire/) — module audio autonome
- [cogitator-gaming](/stc/fr/cogitator/gaming/) — profil gaming, compose aussi Pipewire
