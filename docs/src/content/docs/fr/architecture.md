---
title: Architecture
description: Comment le STC est structuré et pourquoi.
---

## Le Grand Dessein

Le STC repose sur un unique principe : **STC est une bibliothèque, pas un système.**

Ton flake déclare tes machines. STC fournit les modules que ces machines importent.
Il n'y a pas de `nixosConfigurations` dans STC, pas de `homeConfigurations`, pas
d'opinions sur ce à quoi ton système devrait ressembler. Uniquement des outils.

## Les Chambres de l'Archivum

```
stc/
├── relics/        Modules atomiques — une préoccupation par relique
│   ├── nixos/     Modules NixOS
│   └── home/      Modules Home Manager
│
├── cogitator/     Profils — des reliques assemblées avec un objectif
│   ├── nixos/     Profils NixOS
│   └── home/      Profils Home Manager
│
├── forge/         Dev shells, layouts de disques, templates de projets
│   ├── shells/    Environnements de développement (ansible, terraform, vm, …)
│   ├── layouts/   Layouts de partitions Disko
│   └── templates/ Starters de projets (ansible, terraform, etc.)
│
└── schematics/    Exemples de flakes consommateurs
```

## Conventions de nommage

Les modules STC sont exposés dans deux espaces de noms :

| Output | Préfixe | Exemple |
|--------|---------|---------|
| `nixosModules` | `relics-` | `stc.nixosModules.relics-networking` |
| `nixosModules` | `cogitator-` | `stc.nixosModules.cogitator-hardening` |
| `homeModules` | `relics-` | `stc.homeModules.relics-kitty` |
| `homeModules` | `cogitator-` | `stc.homeModules.cogitator-enginseer` |
| `devShells` | — | `stc.devShells.${system}.ansible` |
| `templates` | — | `nix flake init -t github:gfriloux/stc#ansible` |
| `lib` | — | `stc.lib.layouts.zfs-local-vm` |

## Namespace des options

Toutes les options STC vivent sous `stc.*` :

```nix
stc.relics.networking.enable = true;
stc.relics.gui.zen-browser.enable = true;
stc.relics.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;
```

Pas de collision avec d'autres modules. Pas de surprises.

## Reliques vs Cogitators

Les **reliques** sont atomiques. Chacune contrôle une seule préoccupation et possède sa
propre option `enable`. Importe uniquement ce dont tu as besoin :

```nix
modules = [
  stc.nixosModules.relics-boot
  stc.nixosModules.relics-zfs
  stc.nixosModules.relics-networking
];
```

Les **profils Cogitator** sont des reliques composées. Ils regroupent des reliques liées
sous un seul interrupteur `enable` pour les cas d'usage courants :

```nix
modules = [
  stc.nixosModules.cogitator-hardening   # active kernel + network + filesystem + SSH
];
```

Utilise les cogitators quand les valeurs par défaut te conviennent. Utilise les reliques
individuelles quand tu as besoin d'un contrôle chirurgical.

## Framework

STC utilise [flake-parts](https://flake.parts) comme framework de structuration. Cela
donne une liberté totale sur le nommage des répertoires (d'où la mise en page thématisée
Warhammer) tout en gardant les outputs bien définis et composables.

## Secrets

STC est **agnostique sur les secrets**. Les modules qui ont besoin de secrets exposent
une option `*File` pointant vers un chemin de fichier. Comment ce fichier y arrive est
ton problème, pas celui de STC :

```nix
# Exemple avec sops-nix
stc.relics.docker.notify.ntfy.topicFile = config.sops.secrets."ntfy/topic".path;

# Exemple avec agenix
stc.relics.docker.crowdsec.envFile = config.age.secrets.crowdsec-env.path;
```

Que tu utilises sops-nix, agenix, ou un script shell d'origine douteuse de l'Âge des
Ténèbres, STC accepte un chemin et ne pose pas d'autres questions.
