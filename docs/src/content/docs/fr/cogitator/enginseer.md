---
title: Enginseer
description: cogitator-enginseer — le kit CLI complet de déploiement terrain pour un Technoprêtre.
---

**Module :** `stc.homeModules.cogitator-enginseer`

L'Enginseer est l'opérateur de l'Adeptus Mechanicus envoyé sur le terrain pour
maintenir, opérer et communier avec les machines de toutes sortes. Ce profil Home
Manager assemble le kit CLI complet d'un Enginseer expérimenté : améliorations du
shell, outillage de développement, rites git, et augmentations esthétiques.

## Options

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `stc.cogitator.enginseer.enable` | bool | `false` | Active le profil CLI Enginseer |

## Ce qu'il configure

### Shell

- **fish** — shell principal avec prompt `oh-my-posh` (thème Dracula)
- Alias shell : `cat` → `bat`, `ping` → `prettyping`, `cp` → `xcp`

### Programmes (modules Home Manager)

| Programme | Rôle |
|-----------|------|
| `atuin` | Synchronisation de l'historique shell |
| `bat` | Remplacement de `cat` avec coloration syntaxique |
| `btop` | Moniteur de ressources |
| `delta` | Pager de diff git (intégration git activée) |
| `direnv` + `nix-direnv` | Activation d'env par répertoire, mode silencieux |
| `fzf` | Recherche floue |
| `git` | Contrôle de version |
| `gitflow-toolkit` | Helpers de workflow git |
| `gh` | CLI GitHub (`git_protocol = ssh`) |
| `gpg` | GnuPG — gestion de clés et signature |
| `helix` | Éditeur de texte modal |
| `jq` | Processeur JSON |
| `lsd` | Remplacement de `ls` avec icônes |
| `micro` | Éditeur de terminal simple (réglages opinionnés, LSP `nixd`) |
| `nix-search-tv` | Recherche nixpkgs avec intégration `television` |
| `rbw` | CLI Bitwarden |
| `television` | Recherche et aperçu de fichiers |
| `television-ssh` | Recherche floue d'hôtes SSH |
| `zellij` | Multiplexeur de terminal |
| `zoxide` | Remplacement intelligent de `cd` |

L'éditeur `micro` est livré avec des réglages opinionnés (tabulations douces de
2 espaces, règle, curseur mémorisé, souris) et un binding LSP `nix:nixd` (le
serveur `nixd` est fourni plus bas). Surcharge n'importe lequel depuis ta propre
configuration home.

### Agent GPG

`services.gpg-agent` est activé avec l'intégration fish. L'authentification SSH
n'est **pas** déléguée à gpg (`enableSshSupport = false`) — le consommateur câble
son propre `ssh-agent`. Le pinentry par défaut est `pinentry-curses`, un choix
compatible headless pour que l'Enginseer fonctionne en TTY et sur serveur. Il est
posé avec `lib.mkDefault`, si bien que `cogitator-desktop` le surcharge avec un
pinentry graphique (`pinentry-qt`).

### Paquets

| Paquet | Utilité |
|--------|---------|
| `age` | Chiffrement de fichiers |
| `alejandra` | Formateur Nix |
| `aria2` | Utilitaire de téléchargement multi-sources |
| `croc` | Transfert de fichiers |
| `dive` | Inspecteur de couches d'images Docker |
| `doggo` | Outil de lookup DNS |
| `fastfetch` | Affichage des informations système |
| `fd` | Remplacement de `find` |
| `fzf-make` | Exécuteur de tâches Makefile avec fuzzy search |
| `git-workspace` | Gestionnaire de workspace multi-dépôts |
| `glow` | Rendu Markdown |
| `gum` | Composants UI pour scripts |
| `htop` | Visualiseur de processus interactif |
| `just` | Exécuteur de tâches |
| `ncdu` | Analyseur d'utilisation disque |
| `nh` | Wrapper de `nixos-rebuild` / `home-manager` avec meilleure UX |
| `nix-output-monitor` | Meilleur affichage de `nix build` |
| `nix-tree` | Explorateur interactif du graphe de dépendances Nix |
| `nixd` | Serveur de langage Nix (LSP) pour l'intégration éditeur |
| `nvd` | Diff de générations NixOS — visualise les changements entre builds |
| `oh-my-posh` | Moteur de prompt shell |
| `ouch` | Compression / décompression sans douleur |
| `p7zip` | Outil d'archive |
| `prettyping` | `ping` avec graphes |
| `pv` | Visualiseur de progression de pipe |
| `pwgen` | Générateur de mots de passe |
| `rsync` | Synchronisation de fichiers |
| `sops` | Gestion des secrets |
| `unzip` | Extraction d'archives ZIP |
| `viu` | Visionneuse d'images dans le terminal |
| `xcp` | `cp` avec progression |

### Thème

Catppuccin saveur **Frappe** appliqué sur tous les programmes supportés via le
module Home Manager `catppuccin`.

## Exemple d'utilisation

```nix
# flake.nix
outputs = { nixpkgs, stc, home-manager, ... }: {
  homeConfigurations."alice@workstation" = home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      stc.homeModules.cogitator-enginseer
      ./home.nix
    ];
  };
};

# home.nix
{
  stc.cogitator.enginseer.enable = true;

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.11";
}
```

:::note[Module catppuccin]
Le profil Enginseer utilise le module Home Manager `catppuccin`. Ce module doit être
disponible dans ta liste de modules. Il est fourni via les inputs flake de STC —
importe-le comme `stc.inputs.catppuccin.homeManagerModules.catppuccin` si tu ne
l'as pas dans tes propres inputs.
:::
