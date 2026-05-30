---
title: Plasma 6
description: Relique KDE Plasma 6 — bureau Wayland-first avec SDDM, portails XDG, et disposition clavier et thème configurables.
---

**Module :** `stc.nixosModules.relics-plasma6`

**Option d'activation :** `stc.plasma6.enable`

Configure un bureau KDE Plasma 6 orienté Wayland. SDDM tourne sous Wayland,
Plasma 6 est le gestionnaire de bureau, et la pile XDG portal est activée pour le
partage d'écran et l'intégration du sélecteur de fichiers. La génération de
miniatures (tumbler), le système de fichiers virtuel (gvfs) et la gestion des
entrées (libinput) sont inclus. Le serveur X11 est désactivé.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.plasma6.enable` | bool | `false` | Active KDE Plasma 6 |
| `stc.plasma6.keyboardLayout` | string | `"us"` | Disposition clavier xkb pour SDDM et Plasma |
| `stc.plasma6.sddmTheme` | string | `""` | Nom du thème SDDM — chaîne vide utilise le thème par défaut de SDDM |

### `sddmTheme`

La relique définit `services.displayManager.sddm.theme` avec cette valeur mais
**n'installe pas** le paquet du thème. Lors de l'utilisation d'un thème personnalisé,
ajoute toi-même le paquet :

```nix
environment.systemPackages = [ pkgs.catppuccin-sddm ];
stc.plasma6.sddmTheme = "catppuccin-mocha-mauve";
```

## Ce que ça configure

```
services.displayManager.sddm.enable = true
services.displayManager.sddm.wayland.enable = true
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

WirePlumber est explicitement ajouté à `default.target` pour que l'audio
s'initialise correctement au démarrage de Plasma. Associe-le à
[`relics-pipewire`](/fr/relics/pipewire/) pour une pile audio complète — ou
utilise [`cogitator-plasma`](/fr/cogitator/plasma/) qui compose les deux reliques.

## Exemple d'utilisation

```nix
modules = [
  stc.nixosModules.relics-plasma6
  stc.nixosModules.relics-pipewire
  ./configuration.nix
];

# configuration.nix
{
  stc.plasma6.enable = true;
  stc.plasma6.keyboardLayout = "fr";
  stc.plasma6.sddmTheme = "catppuccin-mocha-mauve";

  stc.pipewire.enable = true;

  environment.systemPackages = [ pkgs.catppuccin-sddm ];
}
```

## Voir aussi

- [cogitator-plasma](/fr/cogitator/plasma/) — compose cette relique avec Pipewire en une seule option
- [Pipewire](/fr/relics/pipewire/) — relique audio, nécessaire pour l'audio du bureau
