---
title: Plasma Manager
description: Relique plasma-manager — configuration KDE Plasma déclarative via Home Manager, sans toucher ~/.config manuellement.
---

**Module :** `stc.homeModules.relics-plasma-manager`

**Option d'activation :** `stc.plasmaManager.enable`

Active [plasma-manager](https://github.com/nix-community/plasma-manager), le module
Home Manager pour la configuration déclarative de KDE. Une fois activé, l'ensemble
de la configuration du bureau KDE (thème, workspace, raccourcis, panneaux, widgets,
curseur) est déclaré dans `programs.plasma.*` et appliqué à chaque activation de
Home Manager.

Le flake upstream `plasma-manager` est déjà câblé comme input de STC — les
consommateurs n'ont **pas** besoin de l'ajouter à leur propre `flake.nix`.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.plasmaManager.enable` | bool | `false` | Active la configuration KDE déclarative via plasma-manager |

Toute la configuration KDE se fait via les options `programs.plasma.*` fournies
par plasma-manager lui-même — STC ne les enveloppe pas.

## Exemple d'utilisation

```nix
# flake.nix
homeManagerModules = [ stc.homeModules.relics-plasma-manager ];

# home.nix
{
  stc.plasmaManager.enable = true;

  programs.plasma = {
    workspace = {
      lookAndFeel = "Catppuccin-Mocha-Global";
      colorScheme = "CatppuccinMocha";
      iconTheme = "Papirus-Dark";
      cursor = {
        theme = "Catppuccin-Mocha-Dark-Cursors";
        size = 24;
      };
    };
  };
}
```

:::note[Paquets de thèmes]
`programs.plasma.workspace.*` définit les noms de thèmes sous forme de chaînes.
Les paquets de thèmes correspondants (Catppuccin, Papirus, etc.) doivent être
installés séparément — ajoute-les à `home.packages` ou
`environment.systemPackages`.
:::

## Ce que ça configure

```
programs.plasma.enable = true   # via stc.plasmaManager.enable
```

Tout le reste — apparence du workspace, raccourcis, panneaux, widgets — se
configure directement via les options `programs.plasma.*` après activation de la
relique. Consulte la [documentation de plasma-manager](https://github.com/nix-community/plasma-manager)
pour la référence complète des options.

## Voir aussi

- [Relique Plasma 6](/fr/relics/plasma6/) — configuration système Plasma 6 (NixOS)
- [cogitator-plasma](/fr/cogitator/plasma/) — profil NixOS Plasma + Pipewire
