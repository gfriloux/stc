---
title: Desktop
description: cogitator-desktop — le profil complet de station de travail GUI pour un Techprêtre.
---

**Module :** `stc.homeModules.cogitator-desktop`

Le profil Desktop assemble la boîte à outils GUI complète pour une station de travail :
deux terminaux accélérés GPU, un navigateur axé vie privée, un éditeur d'images et un
lecteur multimédia.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.desktop.enable` | bool | `false` | Active le profil GUI Desktop |

## Ce qu'il configure

| Composant | Source | Notes |
|-----------|--------|-------|
| `programs.kitty` | `relics-kitty` | Terminal accéléré GPU + Nerd Fonts sélectionnées |
| `programs.ghostty` | `relics-ghostty` | Terminal accéléré GPU, GTK4 natif, protocole étendu |
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
gpg-agent avec `pinentry-qt` (via `lib.mkForce`), remplaçant le défaut
`pinentry-curses` compatible headless afin que les demandes de passphrase
apparaissent dans une fenêtre graphique. La surcharge est inerte si gpg-agent
n'est pas activé.

Kitty et Ghostty coexistent sans conflit — chacun a son propre namespace `programs.*`.
Les Nerd Fonts sont installées via `relics-kitty` et disponibles pour les deux terminaux.

L'installation des Nerd Fonts de Kitty est active par défaut. Pour la désactiver :

```nix
stc.relics.gui.kitty.fonts.enable = false;
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
