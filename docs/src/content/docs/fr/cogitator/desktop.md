---
title: Desktop
description: cogitator-desktop — le profil complet de station de travail GUI pour un Techprêtre.
---

**Module :** `stc.homeModules.cogitator-desktop`

Le profil Desktop assemble la boîte à outils GUI complète pour une station de travail :
un terminal accéléré GPU, un navigateur axé vie privée, un éditeur d'images et un
lecteur multimédia.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.desktop.enable` | bool | `false` | Active le profil GUI Desktop |

## Ce qu'il configure

| Composant | Source | Notes |
|-----------|--------|-------|
| `programs.ghostty` | `relics-ghostty` | Terminal accéléré GPU, GTK4 natif, protocole étendu + Nerd Fonts sélectionnées |
| `programs.zen-browser` | `relics-zen-browser` | Fork Firefox axé vie privée |
| `services.gpg-agent.pinentry` | config directe | Pinentry graphique (`pinentry-qt`) |
| `pkgs.gimp` | paquet direct | Éditeur d'images |
| `pkgs.libnotify` | paquet direct | Envoi de notifications bureau (`notify-send`) |
| `pkgs.vlc` | paquet direct | Lecteur multimédia |

GIMP, `libnotify` et VLC sont installés comme paquets simples — il n'existe pas de
module programme Home Manager pour eux, donc il n'y a rien à configurer au-delà de
l'installation.

### Pinentry graphique

Couplé à `cogitator-enginseer`, le profil Desktop surcharge le pinentry de
gpg-agent avec `pinentry-qt` (via `lib.mkOverride 900`), remplaçant le défaut
`pinentry-curses` compatible headless afin que les demandes de passphrase
apparaissent dans une fenêtre graphique. La surcharge est inerte si gpg-agent
n'est pas activé.

La priorité 900 se situe entre un défaut (1000) et une définition simple (100) :
elle bat le `mkDefault` d'enginseer, mais pas toi. Pour choisir un autre
pinentry, une définition simple
`services.gpg-agent.pinentry.package = pkgs.pinentry-gnome3;` suffit — pas
besoin de `mkForce`.

### Nerd Fonts

Les Nerd Fonts sont installées via `relics-ghostty` et actives par défaut. Pour
les désactiver :

```nix
stc.relics.gui.ghostty.fonts.enable = false;
```

## Exemple d'utilisation

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

:::note[module zen-browser]
Le profil Desktop importe automatiquement `inputs.zen-browser.homeModules.beta`.
Le flake upstream `zen-browser` est intégré comme input STC — tu n'as pas besoin
de l'ajouter toi-même. Si tu l'as déjà, il n'y a pas de conflit.
:::

## Kitty retiré en `v0.22.0`

Jusqu'à `v0.21.0` le profil livrait kitty et ghostty ; depuis `v0.22.0` il ne
livre plus que ghostty (#1), et les Nerd Fonts suivent `relics-ghostty`. Si tu
mets à jour sans rien changer, kitty et son `kitty.conf` disparaissent de ton
profil ; les polices restent.

Si ta configuration pose encore `stc.relics.gui.kitty.enable` (l'ancienne façon
de ne garder que ghostty était `stc.relics.gui.kitty.enable = false;`) ou
`stc.relics.gui.kitty.fonts.enable`, le build passe toujours, avec un
avertissement à l'évaluation : supprime la ligne. Pour garder kitty, active-le
toi-même avec `programs.kitty.enable = true;`.

Deux cas changent sans avertissement, parce qu'ils ne posent aucune option kitty :

- **Tu ne gardais que kitty** avec `stc.relics.gui.ghostty.enable = false;` :
  tu n'as plus ni kitty ni les Nerd Fonts, qui suivent la relique ghostty.
  Ajoute `programs.kitty.enable = true;` et liste les polices voulues dans
  `home.packages`.
- **Tu ne gardais que ghostty** avec `stc.relics.gui.kitty.enable = false;` :
  tu n'avais pas de Nerd Fonts, tu en as désormais sept paquets. Pose
  `stc.relics.gui.ghostty.fonts.enable = false;` pour garder la closure
  d'avant.

Les reliques GUI sont activées avec `lib.mkDefault` : tu peux prendre le profil
et en refuser une, par exemple `stc.relics.gui.ghostty.enable = false;`. Voir
[Valeurs par défaut surchargeables](/stc/fr/reference/overridable-defaults/).
